-- =====================================================================
-- 003_sites_and_invites.sql
-- 4 Rol Yönetimi, Süper Admin Onay Mekanizması ve Daire Davet Kodu Akışı
-- PostgreSQL RLS Infinite Recursion (42P17) Korumalı ve Güvenli Sürüm
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Güvenli Rol ve Yetki Yardımcı Fonksiyonları (SECURITY DEFINER)
--    Not: RLS politikalarında doğrudan tablo sorgulamak sonsuz döngüye
--    (infinite recursion) yol açtığı için tüm kontroller SECURITY DEFINER
--    fonksiyonlar üzerinden yapılır (RLS bypass).
-- ---------------------------------------------------------------------
create or replace function public.is_super_admin()
returns boolean
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_is_super boolean;
begin
  select is_super_admin into v_is_super from public.profiles where id = auth.uid();
  return coalesce(v_is_super, false);
end;
$$;

create or replace function public.has_site_role(p_site_id uuid, p_role public.member_role)
returns boolean
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  return exists (
    select 1 from public.memberships
    where site_id = p_site_id
      and user_id = auth.uid()
      and role = p_role
      and status = 'active'
  );
end;
$$;

create or replace function public.is_site_admin(p_site_id uuid)
returns boolean
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  return exists (
    select 1 from public.memberships
    where site_id = p_site_id
      and user_id = auth.uid()
      and role = 'site_admin'
      and status = 'active'
  );
end;
$$;

create or replace function public.is_site_member(p_site_id uuid)
returns boolean
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  return exists (
    select 1 from public.memberships
    where site_id = p_site_id
      and user_id = auth.uid()
      and status = 'active'
  );
end;
$$;

create or replace function public.can_admin_view_profile(p_target_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  return exists (
    select 1 from public.memberships m_admin
    join public.memberships m_user on m_user.site_id = m_admin.site_id
    where m_admin.user_id = auth.uid()
      and m_admin.role = 'site_admin'
      and m_admin.status = 'active'
      and m_user.user_id = p_target_user_id
  );
end;
$$;

-- ---------------------------------------------------------------------
-- 2) Site Başvurusu Oluşturma (Admin Adayı Çağırır)
-- ---------------------------------------------------------------------
create or replace function public.create_site(
  p_name text,
  p_city text,
  p_district text,
  p_address text default null
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_site_id uuid;
  v_user_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'İşlem için giriş yapmalısınız.';
  end if;

  if trim(p_name) = '' or trim(p_city) = '' or trim(p_district) = '' then
    raise exception 'Site adı, il ve ilçe alanları zorunludur.';
  end if;

  -- 1. Siteyi 'pending' (onay bekliyor) olarak kaydet
  insert into public.sites (name, city, district, address, status, created_by)
  values (trim(p_name), trim(p_city), trim(p_district), nullif(trim(p_address), ''), 'pending', v_user_id)
  returning id into v_site_id;

  -- 2. Başvuran kullanıcıyı bekleyen 'site_admin' olarak ekle
  insert into public.memberships (user_id, site_id, role, status)
  values (v_user_id, v_site_id, 'site_admin', 'pending');

  return v_site_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 3) Süper Admin: Site Başvurusunu Onaylama ve Reddetme
-- ---------------------------------------------------------------------
create or replace function public.approve_site(p_site_id uuid)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Bu işlem yalnızca Süper Admin tarafından yapılabilir.';
  end if;

  -- Siteyi aktifleştir
  update public.sites
  set status = 'active',
      reviewed_by = auth.uid(),
      reviewed_at = now()
  where id = p_site_id;

  -- Başvuran yöneticinin üyeliğini aktifleştir
  update public.memberships
  set status = 'active'
  where site_id = p_site_id
    and role = 'site_admin'
    and status = 'pending';
end;
$$;

create or replace function public.reject_site(p_site_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Bu işlem yalnızca Süper Admin tarafından yapılabilir.';
  end if;

  update public.sites
  set status = 'rejected',
      rejection_reason = p_reason,
      reviewed_by = auth.uid(),
      reviewed_at = now()
  where id = p_site_id;

  update public.memberships
  set status = 'rejected'
  where site_id = p_site_id
    and role = 'site_admin'
    and status = 'pending';
end;
$$;

-- ---------------------------------------------------------------------
-- 4) Davet Kodu Üretme (Site Yöneticisi Çağırır)
-- ---------------------------------------------------------------------
create or replace function public.create_invite(
  p_site_id uuid,
  p_email text,
  p_role public.member_role default 'resident',
  p_unit_id uuid default null
)
returns text
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_code text;
  v_token_hash text;
  v_site_status public.site_status;
begin
  if not (public.is_super_admin() or public.has_site_role(p_site_id, 'site_admin')) then
    raise exception 'Bu site için davet oluşturma yetkiniz bulunmuyor.';
  end if;

  select status into v_site_status from public.sites where id = p_site_id;
  if v_site_status != 'active' then
    raise exception 'Yalnızca aktif ve onaylanmış sitelere davet kodu oluşturulabilir.';
  end if;

  if p_role = 'resident' and p_unit_id is null then
    raise exception 'Sakin daveti için daire (unit_id) seçilmesi zorunludur.';
  end if;

  v_code := upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 6));
  v_token_hash := encode(sha256(convert_to(v_code, 'UTF8')), 'hex');

  update public.site_invites
  set revoked_at = now()
  where site_id = p_site_id
    and email = lower(trim(p_email))
    and used_at is null
    and revoked_at is null;

  insert into public.site_invites (
    site_id,
    unit_id,
    role,
    email,
    token_hash,
    expires_at,
    created_by
  ) values (
    p_site_id,
    p_unit_id,
    p_role,
    lower(trim(p_email)),
    v_token_hash,
    now() + interval '7 days',
    auth.uid()
  );

  return v_code;
end;
$$;

-- ---------------------------------------------------------------------
-- 5) Daire Davet Kodunu Kullanma (Sakin / Kullanıcı Çağırır)
-- ---------------------------------------------------------------------
create or replace function public.claim_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_user_id uuid;
  v_token_hash text;
  v_invite record;
  v_site_name text;
  v_unit_no text;
  v_block_name text;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Lütfen önce giriş yapınız.';
  end if;

  if trim(p_code) = '' then
    raise exception 'Davet kodu boş olamaz.';
  end if;

  v_token_hash := encode(sha256(convert_to(upper(trim(p_code)), 'UTF8')), 'hex');

  select * into v_invite
  from public.site_invites
  where token_hash = v_token_hash
    and used_at is null
    and revoked_at is null;

  if not found then
    raise exception 'Geçersiz veya daha önce kullanılmış davet kodu.';
  end if;

  if v_invite.expires_at < now() then
    raise exception 'Bu davet kodunun süresi dolmuş.';
  end if;

  insert into public.memberships (user_id, site_id, unit_id, role, status)
  values (v_user_id, v_invite.site_id, v_invite.unit_id, v_invite.role, 'active')
  on conflict (user_id, site_id, role, coalesce(unit_id, '00000000-0000-0000-0000-000000000000'::uuid))
  do update set status = 'active';

  update public.site_invites
  set used_at = now(),
      used_by = v_user_id
  where id = v_invite.id;

  select s.name into v_site_name from public.sites s where s.id = v_invite.site_id;
  
  if v_invite.unit_id is not null then
    select u.unit_no, b.name
    into v_unit_no, v_block_name
    from public.units u
    join public.blocks b on b.id = u.block_id
    where u.id = v_invite.unit_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'site_id', v_invite.site_id,
    'site_name', v_site_name,
    'role', v_invite.role,
    'unit_no', v_unit_no,
    'block_name', v_block_name
  );
end;
$$;

-- ---------------------------------------------------------------------
-- 6) İzinler (Grants)
-- ---------------------------------------------------------------------
grant execute on function public.is_super_admin to authenticated;
grant execute on function public.has_site_role to authenticated;
grant execute on function public.is_site_admin to authenticated;
grant execute on function public.is_site_member to authenticated;
grant execute on function public.can_admin_view_profile to authenticated;
grant execute on function public.create_site to authenticated;
grant execute on function public.approve_site to authenticated;
grant execute on function public.reject_site to authenticated;
grant execute on function public.create_invite to authenticated;
grant execute on function public.claim_invite to authenticated;

grant select on public.sites to authenticated;
grant select on public.memberships to authenticated;
grant select on public.blocks to authenticated;
grant select, insert on public.units to authenticated;
grant select on public.unit_types to authenticated;
grant select, insert on public.tickets to authenticated;
grant update (status, assigned_to, updated_at, closed_at) on public.tickets to authenticated;
grant select on public.announcements to authenticated;

-- ---------------------------------------------------------------------
-- 7) RLS Politikaları (Temiz ve Sıfır Özyinelemeli / No Recursion)
-- ---------------------------------------------------------------------

-- A) PROFILES
drop policy if exists "super admin tum profilleri gorur" on public.profiles;
create policy "super admin tum profilleri gorur"
on public.profiles for select to authenticated
using (public.is_super_admin());

drop policy if exists "site yoneticisi uye profillerini gorur" on public.profiles;
create policy "site yoneticisi uye profillerini gorur"
on public.profiles for select to authenticated
using (public.can_admin_view_profile(id));

-- B) SİTELER
drop policy if exists "siteleri listeleme politikasi" on public.sites;
drop policy if exists "siteleri gorme politikasi" on public.sites;
create policy "siteleri listeleme politikasi"
on public.sites for select to authenticated
using (
  public.is_super_admin()
  or created_by = (select auth.uid())
  or public.is_site_member(id)
);

-- C) ÜYELİKLER (Kendi tablosunu sorgulamadan fonksiyonla kontrol eder - Sonsuz döngü engellendi)
drop policy if exists "uyelikleri gorme politikasi" on public.memberships;
create policy "uyelikleri gorme politikasi"
on public.memberships for select to authenticated
using (
  public.is_super_admin()
  or user_id = (select auth.uid())
  or public.is_site_admin(site_id)
);

-- D) BLOK VE DAİRELER
drop policy if exists "bloklari gorme politikasi" on public.blocks;
create policy "bloklari gorme politikasi"
on public.blocks for select to authenticated
using (
  public.is_super_admin()
  or public.is_site_member(site_id)
);

drop policy if exists "daireleri gorme politikasi" on public.units;
create policy "daireleri gorme politikasi"
on public.units for select to authenticated
using (
  public.is_super_admin()
  or public.is_site_member(site_id)
);

-- E) ARIZA / TİCKETLAR
drop policy if exists "ticketlari gorme politikasi" on public.tickets;
create policy "ticketlari gorme politikasi"
on public.tickets for select to authenticated
using (
  public.is_super_admin()
  or created_by = (select auth.uid())
  or public.is_site_admin(site_id)
  or public.has_site_role(site_id, 'technician')
);

drop policy if exists "sakin ticket olusturur" on public.tickets;
create policy "sakin ticket olusturur"
on public.tickets for insert to authenticated
with check (
  created_by = (select auth.uid())
  and public.is_site_member(site_id)
);

drop policy if exists "teknisyen ve admin ticket gunceller" on public.tickets;
create policy "teknisyen ve admin ticket gunceller"
on public.tickets for update to authenticated
using (
  public.is_super_admin()
  or public.is_site_admin(site_id)
  or public.has_site_role(site_id, 'technician')
);

-- F) DUYURULAR
drop policy if exists "duyurulari gorme politikasi" on public.announcements;
create policy "duyurulari gorme politikasi"
on public.announcements for select to authenticated
using (
  public.is_super_admin()
  or public.is_site_member(site_id)
);

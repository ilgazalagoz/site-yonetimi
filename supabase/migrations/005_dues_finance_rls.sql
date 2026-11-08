-- =====================================================================
-- 005_dues_finance_rls.sql
-- Aidat ve Finans Modülü: Grant, RLS Politikaları ve RPC Fonksiyonları
-- Tablolar: dues_periods, charges, payments + charge_status görünümü
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) API İzinleri (Grants)
-- ---------------------------------------------------------------------
grant select, insert, update, delete on public.dues_periods to authenticated;
grant select, insert, update, delete on public.charges to authenticated;
grant select, insert, update, delete on public.payments to authenticated;
grant select on public.charge_status to authenticated;

-- ---------------------------------------------------------------------
-- 2) DUES_PERIODS (Aidat Dönemleri) RLS Politikaları
--    - Site üyeleri (ve super admin) dönemleri okur
--    - Site admin (ve super admin) ekler, günceller, siler
-- ---------------------------------------------------------------------
create policy "aidat donemlerini gorme politikasi"
on public.dues_periods for select to authenticated
using (
  public.is_super_admin()
  or public.is_site_member(site_id)
);

create policy "site admin aidat donemi ekler"
on public.dues_periods for insert to authenticated
with check (
  public.is_super_admin()
  or public.is_site_admin(site_id)
);

create policy "site admin aidat donemi gunceller"
on public.dues_periods for update to authenticated
using (
  public.is_super_admin()
  or public.is_site_admin(site_id)
)
with check (
  public.is_super_admin()
  or public.is_site_admin(site_id)
);

create policy "site admin aidat donemi siler"
on public.dues_periods for delete to authenticated
using (
  public.is_super_admin()
  or public.is_site_admin(site_id)
);

-- ---------------------------------------------------------------------
-- 3) CHARGES (Borçlar / Aidat Tahakkukları) RLS Politikaları
--    - Site admin tüm borçları görür, sakinler kendi dairesine ait borçları görür
--    - Site admin borç ekler, günceller, siler
-- ---------------------------------------------------------------------
create policy "borclari gorme politikasi"
on public.charges for select to authenticated
using (
  public.is_super_admin()
  or public.is_site_admin(site_id)
  or unit_id in (
    select m.unit_id
    from public.memberships m
    where m.user_id = (select auth.uid())
      and m.site_id = charges.site_id
  )
);

create policy "site admin borc ekler"
on public.charges for insert to authenticated
with check (
  public.is_super_admin()
  or public.is_site_admin(site_id)
);

create policy "site admin borc gunceller"
on public.charges for update to authenticated
using (
  public.is_super_admin()
  or public.is_site_admin(site_id)
)
with check (
  public.is_super_admin()
  or public.is_site_admin(site_id)
);

create policy "site admin borc siler"
on public.charges for delete to authenticated
using (
  public.is_super_admin()
  or public.is_site_admin(site_id)
);

-- ---------------------------------------------------------------------
-- 4) PAYMENTS (Ödemeler / Dekont Bildirimleri) RLS Politikaları
--    - Sakinler kendi dairesine/borcuna ait ve kendi sunduğu ödemeleri okur
--    - Site admin tüm ödemeleri okur, günceller (onay/red) ve yönetir
--    - Sakinler kendi dairesine ait borçlar için ödeme kaydı ekler
-- ---------------------------------------------------------------------
create policy "odemeleri gorme politikasi"
on public.payments for select to authenticated
using (
  public.is_super_admin()
  or public.is_site_admin(site_id)
  or submitted_by = (select auth.uid())
  or charge_id in (
    select c.id
    from public.charges c
    where c.site_id = payments.site_id
      and c.unit_id in (
        select m.unit_id
        from public.memberships m
        where m.user_id = (select auth.uid())
          and m.site_id = payments.site_id
      )
  )
);

create policy "odeme ekleme politikasi"
on public.payments for insert to authenticated
with check (
  submitted_by = (select auth.uid())
  and (
    public.is_super_admin()
    or public.is_site_admin(site_id)
    or charge_id in (
      select c.id
      from public.charges c
      where c.site_id = payments.site_id
        and c.unit_id in (
          select m.unit_id
          from public.memberships m
          where m.user_id = (select auth.uid())
            and m.site_id = payments.site_id
        )
    )
  )
);

create policy "site admin odeme gunceller"
on public.payments for update to authenticated
using (
  public.is_super_admin()
  or public.is_site_admin(site_id)
)
with check (
  public.is_super_admin()
  or public.is_site_admin(site_id)
);

create policy "site admin odeme siler"
on public.payments for delete to authenticated
using (
  public.is_super_admin()
  or public.is_site_admin(site_id)
);

-- ---------------------------------------------------------------------
-- 5) RPC FONKSİYONLARI
-- ---------------------------------------------------------------------

-- A) Toplu Borç Tahakkuku (generate_charges)
--    Sitenin tüm dairelerini ve bağlı unit_types aylık tutarını alıp
--    charges tablosuna toplu olarak ekler.
create or replace function public.generate_charges(
  p_site_id uuid,
  p_period_id uuid
)
returns integer
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_count integer;
begin
  if not (public.is_site_admin(p_site_id) or public.is_super_admin()) then
    raise exception 'Bu işlem için site yöneticisi yetkisi gereklidir.';
  end if;

  if not exists (select 1 from public.dues_periods where id = p_period_id and site_id = p_site_id) then
    raise exception 'Aidat dönemi bulunamadı veya belirtilen siteye ait değil.';
  end if;

  insert into public.charges (site_id, period_id, unit_id, amount)
  select
    u.site_id,
    p_period_id,
    u.id,
    ut.monthly_amount
  from public.units u
  join public.unit_types ut on ut.id = u.unit_type_id and ut.site_id = u.site_id
  where u.site_id = p_site_id
  on conflict (period_id, unit_id) do nothing;

  get diagnostics v_count = row_count;

  -- Audit log kaydı
  insert into public.audit_log (site_id, actor_id, action, entity, entity_id, meta)
  values (
    p_site_id,
    auth.uid(),
    'charges.generated',
    'dues_periods',
    p_period_id,
    jsonb_build_object('count', v_count, 'period_id', p_period_id)
  );

  return v_count;
end;
$$;

-- B) Ödeme Onaylama (approve_payment)
create or replace function public.approve_payment(
  p_payment_id uuid
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_payment public.payments%rowtype;
begin
  select * into v_payment from public.payments where id = p_payment_id;
  if not found then
    raise exception 'Ödeme kaydı bulunamadı.';
  end if;

  if not (public.is_site_admin(v_payment.site_id) or public.is_super_admin()) then
    raise exception 'Bu işlem için site yöneticisi yetkisi gereklidir.';
  end if;

  update public.payments
  set status = 'approved',
      reviewed_by = (select auth.uid()),
      reviewed_at = now()
  where id = p_payment_id;

  -- Audit log kaydı
  insert into public.audit_log (site_id, actor_id, action, entity, entity_id, meta)
  values (
    v_payment.site_id,
    auth.uid(),
    'payment.approved',
    'payments',
    p_payment_id,
    jsonb_build_object('payment_id', p_payment_id, 'charge_id', v_payment.charge_id, 'amount', v_payment.amount)
  );
end;
$$;

-- C) Ödeme Reddetme (reject_payment)
create or replace function public.reject_payment(
  p_payment_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_payment public.payments%rowtype;
begin
  select * into v_payment from public.payments where id = p_payment_id;
  if not found then
    raise exception 'Ödeme kaydı bulunamadı.';
  end if;

  if not (public.is_site_admin(v_payment.site_id) or public.is_super_admin()) then
    raise exception 'Bu işlem için site yöneticisi yetkisi gereklidir.';
  end if;

  update public.payments
  set status = 'rejected',
      reviewed_by = (select auth.uid()),
      reviewed_at = now(),
      rejection_reason = p_reason
  where id = p_payment_id;

  -- Audit log kaydı
  insert into public.audit_log (site_id, actor_id, action, entity, entity_id, meta)
  values (
    v_payment.site_id,
    auth.uid(),
    'payment.rejected',
    'payments',
    p_payment_id,
    jsonb_build_object('payment_id', p_payment_id, 'charge_id', v_payment.charge_id, 'reason', p_reason)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- 6) RPC İzinleri
-- ---------------------------------------------------------------------
grant execute on function public.generate_charges(uuid, uuid) to authenticated;
grant execute on function public.approve_payment(uuid) to authenticated;
grant execute on function public.reject_payment(uuid, text) to authenticated;

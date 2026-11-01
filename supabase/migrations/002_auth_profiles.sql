-- =====================================================================
-- 002_auth_profiles.sql
-- Kayıt/giriş modülü: otomatik profil oluşturma + profiles izinleri ve RLS
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Yeni kullanıcı kaydında otomatik profil satırı
--    Flutter kayıt sırasında şu bilgileri "metadata" olarak gönderir:
--    full_name, phone (opsiyonel), consent ('true'), consent_version
--    Not: Hesap açmak bir siteye üye olmak demek değildir.
--    Üyelik (memberships) davet veya site kaydı ile ayrıca kurulur.
-- ---------------------------------------------------------------------
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone, consent_at, consent_version)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), 'İsimsiz kullanıcı'),
    nullif(trim(new.raw_user_meta_data ->> 'phone'), ''),
    case when (new.raw_user_meta_data ->> 'consent') = 'true' then now() end,
    case when (new.raw_user_meta_data ->> 'consent') = 'true'
         then new.raw_user_meta_data ->> 'consent_version' end
  );
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- 2) profiles: kapı (grant)
--    - Okuma: giriş yapmış kullanıcılar (satırları aşağıdaki politika sınırlar)
--    - Güncelleme: SADECE full_name ve phone sütunları.
--      is_super_admin, consent_at, anonymized_at gibi alanları kullanıcı
--      API üzerinden değiştiremez (kendini süper admin yapamaz).
--    - Ekleme/silme izni yok: profil yalnızca tetikleyiciyle oluşur.
-- ---------------------------------------------------------------------
grant select on public.profiles to authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

-- ---------------------------------------------------------------------
-- 3) profiles: RLS politikaları (kapının içi)
--    Kullanıcı yalnızca kendi profilini görür ve günceller.
--    (Site yöneticisinin üyelerin adını görmesi üyelik modülünde eklenecek.)
-- ---------------------------------------------------------------------
create policy "kullanici kendi profilini okur"
on public.profiles for select to authenticated
using (id = (select auth.uid()));

create policy "kullanici kendi profilini gunceller"
on public.profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

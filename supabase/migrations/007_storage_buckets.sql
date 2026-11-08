-- =====================================================================
-- 007_storage_buckets.sql
-- Supabase Storage: 'receipts' (Dekontlar) Bucket ve RLS Politikaları
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) 'receipts' Private Storage Bucket Oluşturma
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'receipts',
  'receipts',
  false,
  5242880, -- 5 MB maksimum dosya boyutu
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do update set
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];

-- ---------------------------------------------------------------------
-- 2) storage.objects RLS Politikaları
--    (storage.objects üzerinde RLS varsayılan olarak açıktır)
-- ---------------------------------------------------------------------

-- A) Yükleme (INSERT): Giriş yapmış kullanıcılar dekont yükleyebilir
create policy "sakin dekont yukler"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'receipts'
  and (select auth.uid()) is not null
);

-- B) Okuma (SELECT): Kendi dekontunu yükleyen sakin, site yöneticileri ve süper admin okur
create policy "dekontlari okuma politikasi"
on storage.objects for select to authenticated
using (
  bucket_id = 'receipts'
  and (
    public.is_super_admin()
    or owner = (select auth.uid())
    or owner_id = (select auth.uid())::text
    or exists (
      select 1 from public.memberships m
      where m.user_id = (select auth.uid())
        and m.role = 'site_admin'
        and m.status = 'active'
    )
  )
);

-- C) Güncelleme (UPDATE): Dosya sahibi veya süper admin günceller
create policy "dekont guncelleme politikasi"
on storage.objects for update to authenticated
using (
  bucket_id = 'receipts'
  and (
    public.is_super_admin()
    or owner = (select auth.uid())
    or owner_id = (select auth.uid())::text
  )
)
with check (
  bucket_id = 'receipts'
  and (
    public.is_super_admin()
    or owner = (select auth.uid())
    or owner_id = (select auth.uid())::text
  )
);

-- D) Silme (DELETE): Dosya sahibi veya süper admin siler
create policy "dekont silme politikasi"
on storage.objects for delete to authenticated
using (
  bucket_id = 'receipts'
  and (
    public.is_super_admin()
    or owner = (select auth.uid())
    or owner_id = (select auth.uid())::text
  )
);

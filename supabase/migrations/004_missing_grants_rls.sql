-- =====================================================================
-- 004_missing_grants_rls.sql
-- Eksik Grant ve RLS Politikaları:
--   blocks (INSERT/UPDATE/DELETE), unit_types (SELECT/INSERT/UPDATE/DELETE),
--   units (INSERT RLS), announcements (INSERT/UPDATE/DELETE),
--   site_invites (SELECT), ticket_events (SELECT/INSERT), audit_log (SELECT)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) BLOCKS — Site Admin blok ekler/günceller/siler
-- ---------------------------------------------------------------------
grant insert, update, delete on public.blocks to authenticated;

create policy "site admin blok ekler"
on public.blocks for insert to authenticated
with check (
  public.is_site_admin(site_id)
);

create policy "site admin blok gunceller"
on public.blocks for update to authenticated
using (
  public.is_site_admin(site_id)
)
with check (
  public.is_site_admin(site_id)
);

create policy "site admin blok siler"
on public.blocks for delete to authenticated
using (
  public.is_site_admin(site_id)
);

-- ---------------------------------------------------------------------
-- 2) UNIT_TYPES — Site Admin daire tipi yönetir, üyeler okur
-- ---------------------------------------------------------------------
grant insert, update, delete on public.unit_types to authenticated;

-- SELECT: Üyeler ve super admin okur
create policy "daire tiplerini gorme politikasi"
on public.unit_types for select to authenticated
using (
  public.is_super_admin()
  or public.is_site_member(site_id)
);

create policy "site admin daire tipi ekler"
on public.unit_types for insert to authenticated
with check (
  public.is_site_admin(site_id)
);

create policy "site admin daire tipi gunceller"
on public.unit_types for update to authenticated
using (
  public.is_site_admin(site_id)
)
with check (
  public.is_site_admin(site_id)
);

create policy "site admin daire tipi siler"
on public.unit_types for delete to authenticated
using (
  public.is_site_admin(site_id)
);

-- ---------------------------------------------------------------------
-- 3) UNITS — Site Admin daire ekler (SELECT + INSERT grant zaten var)
-- ---------------------------------------------------------------------
grant update, delete on public.units to authenticated;

create policy "site admin daire ekler"
on public.units for insert to authenticated
with check (
  public.is_site_admin(site_id)
);

create policy "site admin daire gunceller"
on public.units for update to authenticated
using (
  public.is_site_admin(site_id)
)
with check (
  public.is_site_admin(site_id)
);

create policy "site admin daire siler"
on public.units for delete to authenticated
using (
  public.is_site_admin(site_id)
);

-- ---------------------------------------------------------------------
-- 4) ANNOUNCEMENTS — Site Admin duyuru oluşturur/günceller/siler
-- ---------------------------------------------------------------------
grant insert, update, delete on public.announcements to authenticated;

create policy "site admin duyuru olusturur"
on public.announcements for insert to authenticated
with check (
  created_by = (select auth.uid())
  and public.is_site_admin(site_id)
);

create policy "site admin duyuru gunceller"
on public.announcements for update to authenticated
using (
  public.is_site_admin(site_id)
)
with check (
  public.is_site_admin(site_id)
);

create policy "site admin duyuru siler"
on public.announcements for delete to authenticated
using (
  public.is_site_admin(site_id)
);

-- ---------------------------------------------------------------------
-- 5) SITE_INVITES — Site Admin kendi sitesinin davetlerini görür
-- ---------------------------------------------------------------------
grant select on public.site_invites to authenticated;

create policy "site admin davetleri gorur"
on public.site_invites for select to authenticated
using (
  public.is_super_admin()
  or public.is_site_admin(site_id)
);

-- ---------------------------------------------------------------------
-- 6) TICKET_EVENTS — İlgili üyeler okur, teknisyen/admin yazar
-- ---------------------------------------------------------------------
grant select, insert on public.ticket_events to authenticated;

-- Olay okuma: Ticket'ı görebilen herkes olayları da görebilir
-- (ticket'ın site_id'si üzerinden kontrol)
create policy "ticket olaylarini gorme politikasi"
on public.ticket_events for select to authenticated
using (
  public.is_super_admin()
  or exists (
    select 1 from public.tickets t
    where t.id = ticket_id
      and t.site_id = ticket_events.site_id
      and (
        t.created_by = (select auth.uid())
        or public.is_site_admin(t.site_id)
        or public.has_site_role(t.site_id, 'technician')
      )
  )
);

-- Olay yazma: Admin ve teknisyen ticket olayı ekleyebilir
create policy "admin ve teknisyen ticket olayi ekler"
on public.ticket_events for insert to authenticated
with check (
  actor_id = (select auth.uid())
  and (
    public.is_site_admin(site_id)
    or public.has_site_role(site_id, 'technician')
  )
);

-- ---------------------------------------------------------------------
-- 7) AUDIT_LOG — Site Admin ve Super Admin okur (yazma trigger ile)
-- ---------------------------------------------------------------------
grant select on public.audit_log to authenticated;

create policy "audit log gorme politikasi"
on public.audit_log for select to authenticated
using (
  public.is_super_admin()
  or (site_id is not null and public.is_site_admin(site_id))
);

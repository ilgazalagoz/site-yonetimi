-- =====================================================================
-- 006_audit_triggers.sql
-- Tetikleyiciler:
--   1) tickets.updated_at güncelleme tetikleyicisi
--   2) tickets durumu değiştiğinde ticket_events tablosuna kayıt (tickets_status_history_trigger)
--   3) Denetim Günlüğü (audit_log) tetikleyicileri (site ve üyelik durumu değişiklikleri)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) tickets.updated_at ve closed_at Otomatik Güncelleme
-- ---------------------------------------------------------------------
create or replace function public.set_tickets_updated_at()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  new.updated_at = now();

  -- Durum 'resolved' veya 'closed' olduğunda closed_at set edilir
  if new.status in ('resolved', 'closed') and (old is null or old.status not in ('resolved', 'closed')) then
    new.closed_at = coalesce(new.closed_at, now());
  elsif new.status not in ('resolved', 'closed') and old is not null and old.status in ('resolved', 'closed') then
    new.closed_at = null;
  end if;

  return new;
end;
$$;

create or replace trigger tickets_set_updated_at_trigger
before update on public.tickets
for each row
execute function public.set_tickets_updated_at();

-- ---------------------------------------------------------------------
-- 2) tickets Durum Geçmişi -> ticket_events (tickets_status_history_trigger)
-- ---------------------------------------------------------------------
create or replace function public.tickets_status_history_handler()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_actor_id uuid;
  v_note text;
begin
  v_actor_id := auth.uid();
  if v_actor_id is null then
    v_actor_id := new.created_by;
  end if;

  if (tg_op = 'INSERT') then
    insert into public.ticket_events (
      ticket_id,
      site_id,
      actor_id,
      from_status,
      to_status,
      note
    )
    values (
      new.id,
      new.site_id,
      v_actor_id,
      null,
      new.status,
      'Talep oluşturuldu.'
    );
    return new;
  elsif (tg_op = 'UPDATE' and old.status is distinct from new.status) then
    v_note := case
      when new.status = 'closed' then 'Talep kapatıldı.'
      when new.status = 'resolved' then 'Talep çözüldü olarak işaretlendi.'
      when new.status = 'assigned' then 'Talep teknisyene atandı.'
      when new.status = 'in_progress' then 'Talep üzerinde çalışılıyor.'
      when new.status = 'reviewing' then 'Talep incelemeye alındı.'
      when new.status = 'open' then 'Talep tekrar açıldı.'
      else 'Durum güncellendi: ' || new.status::text
    end;

    insert into public.ticket_events (
      ticket_id,
      site_id,
      actor_id,
      from_status,
      to_status,
      note
    )
    values (
      new.id,
      new.site_id,
      v_actor_id,
      old.status,
      new.status,
      v_note
    );
    return new;
  end if;

  return new;
end;
$$;

create or replace trigger tickets_status_history_trigger
after insert or update on public.tickets
for each row
execute function public.tickets_status_history_handler();

-- ---------------------------------------------------------------------
-- 3) Genel Denetim Günlüğü (audit_log) Tetikleyicileri
-- ---------------------------------------------------------------------

-- A) Site Durum Değişiklikleri
create or replace function public.log_site_status_change()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if (old.status is distinct from new.status) then
    insert into public.audit_log (site_id, actor_id, action, entity, entity_id, meta)
    values (
      new.id,
      auth.uid(),
      'site.' || new.status::text,
      'sites',
      new.id,
      jsonb_build_object('old_status', old.status, 'new_status', new.status, 'name', new.name)
    );
  end if;
  return new;
end;
$$;

create or replace trigger audit_sites_status_trigger
after update on public.sites
for each row
when (old.status is distinct from new.status)
execute function public.log_site_status_change();

-- B) Üyelik Değişiklikleri
create or replace function public.log_membership_change()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if (tg_op = 'INSERT') then
    insert into public.audit_log (site_id, actor_id, action, entity, entity_id, meta)
    values (
      new.site_id,
      auth.uid(),
      'membership.created',
      'memberships',
      new.id,
      jsonb_build_object('user_id', new.user_id, 'role', new.role, 'status', new.status)
    );
  elsif (tg_op = 'UPDATE' and (old.status is distinct from new.status or old.role is distinct from new.role)) then
    insert into public.audit_log (site_id, actor_id, action, entity, entity_id, meta)
    values (
      new.site_id,
      auth.uid(),
      'membership.updated',
      'memberships',
      new.id,
      jsonb_build_object('user_id', new.user_id, 'old_status', old.status, 'new_status', new.status, 'old_role', old.role, 'new_role', new.role)
    );
  end if;
  return new;
end;
$$;

create or replace trigger audit_memberships_trigger
after insert or update on public.memberships
for each row
execute function public.log_membership_change();

-- =====================================================================
-- 001_schema.sql
-- Akıllı Apartman / Site Yönetimi - Project I temel şema
-- Hedef: Supabase (PostgreSQL 15+)
--
-- Bu dosya SADECE tabloları, tipleri, indeksleri ve görünümü kurar.
-- API izinleri (grant) ve RLS politikaları modül modül sonraki
-- migration dosyalarında eklenir. O zamana kadar hiçbir tablo API
-- üzerinden erişilebilir değildir (güvenli varsayılan).
-- =====================================================================

-- ---------------------------------------------------------------------
-- ENUM tipleri
-- ---------------------------------------------------------------------
create type site_status     as enum ('pending', 'active', 'rejected', 'suspended');
create type member_role     as enum ('site_admin', 'technician', 'resident');
create type member_status   as enum ('pending', 'active', 'rejected', 'inactive');
create type payment_method  as enum ('havale_eft', 'nakit');
create type payment_status  as enum ('pending', 'approved', 'rejected');
create type payment_source  as enum ('resident', 'admin');
create type ticket_status   as enum ('open', 'reviewing', 'assigned', 'in_progress', 'resolved', 'closed');

-- ---------------------------------------------------------------------
-- 1) Kullanıcı profili (auth.users ile 1-1)
-- ---------------------------------------------------------------------
create table profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  full_name       text not null,
  phone           text,
  is_super_admin  boolean not null default false,   -- yalnızca sunucu tarafında değiştirilebilir
  consent_at      timestamptz,                      -- KVKK aydınlatma/rıza zamanı
  consent_version text,
  anonymized_at   timestamptz,                      -- hesap anonimleştirildiyse dolu
  created_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2) Site, blok, daire tipi, daire
-- ---------------------------------------------------------------------
create table sites (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  city             text not null,
  district         text not null,
  address          text,
  status           site_status not null default 'pending',
  created_by       uuid not null references profiles(id),
  reviewed_by      uuid references profiles(id),
  reviewed_at      timestamptz,
  rejection_reason text,
  created_at       timestamptz not null default now()
);

create table blocks (
  id       uuid primary key default gen_random_uuid(),
  site_id  uuid not null references sites(id) on delete cascade,
  name     text not null,
  unique (site_id, name),
  unique (id, site_id)            -- bileşik FK'ler için
);

create table unit_types (
  id              uuid primary key default gen_random_uuid(),
  site_id         uuid not null references sites(id) on delete cascade,
  name            text not null,                    -- 1+1, 2+1, 3+1, 4+1 ...
  monthly_amount  numeric(12,2) not null check (monthly_amount >= 0),
  unique (site_id, name),
  unique (id, site_id)
);

create table units (
  id            uuid primary key default gen_random_uuid(),
  site_id       uuid not null,
  block_id      uuid not null,
  unit_type_id  uuid not null,
  unit_no       text not null,
  unique (block_id, unit_no),
  unique (id, site_id),
  -- bileşik FK: blok ve daire tipi aynı siteye ait olmak zorunda
  foreign key (block_id, site_id)     references blocks(id, site_id) on delete cascade,
  foreign key (unit_type_id, site_id) references unit_types(id, site_id)
);

-- ---------------------------------------------------------------------
-- 3) Üyelik ve davet
-- ---------------------------------------------------------------------
create table memberships (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  site_id     uuid not null references sites(id) on delete cascade,
  unit_id     uuid,                                  -- sadece resident için dolu
  role        member_role not null,
  status      member_status not null default 'pending',
  created_at  timestamptz not null default now(),
  foreign key (unit_id, site_id) references units(id, site_id) on delete cascade,
  check ((role = 'resident') = (unit_id is not null))
);

create unique index memberships_unique
  on memberships (user_id, site_id, role,
                  coalesce(unit_id, '00000000-0000-0000-0000-000000000000'::uuid));

create table site_invites (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references sites(id) on delete cascade,
  unit_id     uuid,
  role        member_role not null,
  email       text not null,
  token_hash  text not null unique,                   -- token düz metin saklanmaz
  expires_at  timestamptz not null,
  used_at     timestamptz,
  used_by     uuid references profiles(id),
  revoked_at  timestamptz,
  created_by  uuid not null references profiles(id),
  created_at  timestamptz not null default now(),
  foreign key (unit_id, site_id) references units(id, site_id) on delete cascade,
  check ((role = 'resident') = (unit_id is not null))
);

-- ---------------------------------------------------------------------
-- 4) Aidat: dönem, borç, ödeme
-- ---------------------------------------------------------------------
create table dues_periods (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references sites(id) on delete cascade,
  period      date not null check (extract(day from period) = 1),  -- ayın ilk günü
  due_date    date not null,
  created_by  uuid not null references profiles(id),
  created_at  timestamptz not null default now(),
  unique (site_id, period),                           -- aynı ay iki kez tahakkuk olmaz
  unique (id, site_id),
  check (due_date >= period)
);

create table charges (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null,
  period_id   uuid not null,
  unit_id     uuid not null,
  amount      numeric(12,2) not null check (amount >= 0),   -- tahakkuk anındaki tutar (kopya)
  created_at  timestamptz not null default now(),
  unique (period_id, unit_id),
  unique (id, site_id),
  foreign key (period_id, site_id) references dues_periods(id, site_id) on delete cascade,
  foreign key (unit_id, site_id)   references units(id, site_id)        -- geçmiş korunur, silme engellenir
);

create table payments (
  id               uuid primary key default gen_random_uuid(),
  site_id          uuid not null,
  charge_id        uuid not null,
  submitted_by     uuid not null references profiles(id),
  amount           numeric(12,2) not null check (amount >= 0),  -- fonksiyon charge.amount'a eşitler
  method           payment_method not null,
  receipt_path     text,                                        -- private storage yolu
  status           payment_status not null default 'pending',
  source           payment_source not null default 'resident',
  reviewed_by      uuid references profiles(id),
  reviewed_at      timestamptz,
  rejection_reason text,
  created_at       timestamptz not null default now(),
  foreign key (charge_id, site_id) references charges(id, site_id) on delete cascade,
  check (source = 'admin' or receipt_path is not null)          -- sakin bildiriminde dekont şart
);

-- Bir borç için aynı anda tek bekleyen/onaylı ödeme olabilir
create unique index payments_one_active_per_charge
  on payments (charge_id) where status in ('pending', 'approved');

-- ---------------------------------------------------------------------
-- 5) Duyuru
-- ---------------------------------------------------------------------
create table announcements (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references sites(id) on delete cascade,
  title       text not null,
  body        text not null,
  pinned      boolean not null default false,
  created_by  uuid not null references profiles(id),
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 6) Arıza ve durum geçmişi
-- ---------------------------------------------------------------------
create table tickets (
  id           uuid primary key default gen_random_uuid(),
  site_id      uuid not null,
  unit_id      uuid not null,
  created_by   uuid not null references profiles(id),
  title        text not null,
  description  text not null,
  status       ticket_status not null default 'open',
  assigned_to  uuid references profiles(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  closed_at    timestamptz,
  unique (id, site_id),
  foreign key (unit_id, site_id) references units(id, site_id),
  check (status in ('open', 'reviewing') or assigned_to is not null)
);

create table ticket_events (
  id           bigint generated always as identity primary key,
  ticket_id    uuid not null,
  site_id      uuid not null,
  actor_id     uuid not null references profiles(id),
  from_status  ticket_status,
  to_status    ticket_status not null,
  note         text,
  created_at   timestamptz not null default now(),
  foreign key (ticket_id, site_id) references tickets(id, site_id) on delete cascade
);

-- ---------------------------------------------------------------------
-- 7) Denetim kaydı
-- ---------------------------------------------------------------------
create table audit_log (
  id          bigint generated always as identity primary key,
  site_id     uuid references sites(id) on delete set null,
  actor_id    uuid references profiles(id) on delete set null,
  action      text not null,                -- örn. 'invite.created', 'payment.approved'
  entity      text,
  entity_id   uuid,
  meta        jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- İndeksler
-- ---------------------------------------------------------------------
create index memberships_user_active_idx on memberships (user_id) where status = 'active';
create index memberships_site_idx        on memberships (site_id);
create index units_site_idx              on units (site_id);
create index charges_unit_idx            on charges (unit_id);
create index payments_site_status_idx    on payments (site_id, status);
create index announcements_site_idx      on announcements (site_id, created_at desc);
create index tickets_site_status_idx     on tickets (site_id, status);
create index tickets_assigned_idx        on tickets (assigned_to) where assigned_to is not null;
create index ticket_events_ticket_idx    on ticket_events (ticket_id, created_at);
create index audit_log_site_idx          on audit_log (site_id, created_at desc);

-- ---------------------------------------------------------------------
-- Borç durumu: saklanmaz, hesaplanır
-- ---------------------------------------------------------------------
create view charge_status with (security_invoker = true) as
select
  c.id        as charge_id,
  c.site_id,
  c.unit_id,
  c.period_id,
  c.amount,
  p.due_date,
  case
    when exists (select 1 from payments pay
                 where pay.charge_id = c.id and pay.status = 'approved') then 'paid'
    when exists (select 1 from payments pay
                 where pay.charge_id = c.id and pay.status = 'pending')  then 'pending_approval'
    when p.due_date < (now() at time zone 'Europe/Istanbul')::date        then 'overdue'
    else 'unpaid'
  end as status
from charges c
join dues_periods p on p.id = c.period_id;

-- ---------------------------------------------------------------------
-- RLS: hepsi açık (politika yoksa kimse bir şey göremez = güvenli varsayılan)
-- Politikalar bir sonraki adımda yazılacak.
-- ---------------------------------------------------------------------
alter table profiles       enable row level security;
alter table sites          enable row level security;
alter table blocks         enable row level security;
alter table unit_types     enable row level security;
alter table units          enable row level security;
alter table memberships    enable row level security;
alter table site_invites   enable row level security;
alter table dues_periods   enable row level security;
alter table charges        enable row level security;
alter table payments       enable row level security;
alter table announcements  enable row level security;
alter table tickets        enable row level security;
alter table ticket_events  enable row level security;
alter table audit_log      enable row level security;

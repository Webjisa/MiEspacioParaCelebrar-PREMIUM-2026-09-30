-- MiEspacioParaCelebrar — PREMIUM MASTER 2026-10-01
-- ESTADO: PREPARADO, NO EJECUTAR TODAVÍA.
-- Esta migración amplía el backend para las funciones Premium nuevas.
-- No contiene service_role, contraseñas ni claves privadas.
-- Ejecutar solamente después de revisar la compatibilidad con el esquema actual.

create extension if not exists pgcrypto;

-- ============================================================
-- 1. LEADS DE PROPIETARIOS
-- ============================================================
create table if not exists public.owner_leads (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text not null,
  email text not null,
  city text,
  space_name text not null,
  capacity integer,
  description text,
  notes text,
  status text not null default 'new' check (status in ('new','contacted','interested','documents','approved','rejected','active')),
  admin_notes text,
  next_follow_up_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists owner_leads_status_idx on public.owner_leads(status, created_at desc);

alter table public.owner_leads enable row level security;

create or replace function public.submit_owner_lead(
  p_name text,
  p_phone text,
  p_email text,
  p_city text,
  p_space_name text,
  p_capacity integer default null,
  p_description text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if nullif(trim(p_name),'') is null or nullif(trim(p_phone),'') is null or nullif(trim(p_email),'') is null or nullif(trim(p_space_name),'') is null then
    raise exception 'Faltan datos obligatorios.';
  end if;
  insert into public.owner_leads(name,phone,email,city,space_name,capacity,description,notes)
  values(trim(p_name),trim(p_phone),lower(trim(p_email)),nullif(trim(p_city),''),trim(p_space_name),p_capacity,nullif(trim(p_description),''),nullif(trim(p_notes),''))
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.submit_owner_lead(text,text,text,text,text,integer,text,text) to anon, authenticated;

-- ============================================================
-- 2. ALERTAS DE DISPONIBILIDAD
-- ============================================================
create table if not exists public.availability_alerts (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  email text not null,
  start_date date not null,
  end_date date not null,
  active boolean not null default true,
  notified_at timestamptz,
  created_at timestamptz not null default now(),
  constraint availability_alert_dates check (end_date >= start_date)
);

create index if not exists availability_alerts_active_idx on public.availability_alerts(space_id,start_date,end_date) where active;
alter table public.availability_alerts enable row level security;

create or replace function public.create_availability_alert(
  p_space_id uuid,
  p_email text,
  p_start_date date,
  p_end_date date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if nullif(trim(p_email),'') is null then raise exception 'Email obligatorio.'; end if;
  if p_end_date < p_start_date then raise exception 'Rango de fechas no válido.'; end if;
  insert into public.availability_alerts(space_id,email,start_date,end_date)
  values(p_space_id,lower(trim(p_email)),p_start_date,p_end_date)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on function public.create_availability_alert(uuid,text,date,date) to anon, authenticated;

-- ============================================================
-- 3. NOTIFICACIONES INTERNAS
-- ============================================================
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  title text not null,
  body text,
  href text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_profile_idx on public.notifications(profile_id,created_at desc);
alter table public.notifications enable row level security;

create policy notifications_owner_read on public.notifications
for select to authenticated
using (profile_id = auth.uid());

create policy notifications_owner_update on public.notifications
for update to authenticated
using (profile_id = auth.uid())
with check (profile_id = auth.uid());

-- ============================================================
-- 4. TICKETS DE SOPORTE
-- ============================================================
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  booking_id uuid references public.bookings(id) on delete set null,
  subject text not null,
  message text not null,
  status text not null default 'open' check (status in ('open','in_progress','resolved','closed')),
  admin_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists support_tickets_status_idx on public.support_tickets(status,created_at desc);
alter table public.support_tickets enable row level security;

create policy support_ticket_owner_read on public.support_tickets
for select to authenticated
using (profile_id = auth.uid());

create policy support_ticket_owner_insert on public.support_tickets
for insert to authenticated
with check (profile_id = auth.uid());

-- ============================================================
-- 5. CONFIGURACIÓN PÚBLICA
-- ============================================================
create table if not exists public.site_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  public_visible boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.site_settings enable row level security;

create policy site_settings_public_read on public.site_settings
for select to anon, authenticated
using (public_visible = true);

create or replace function public.get_public_settings()
returns setof public.site_settings
language sql
stable
security invoker
as $$
  select * from public.site_settings where public_visible = true order by key;
$$;

grant execute on function public.get_public_settings() to anon, authenticated;

-- ============================================================
-- 6. PLANTILLAS DE EMAIL
-- ============================================================
create table if not exists public.email_templates (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  subject text not null,
  body_html text not null,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.email_templates enable row level security;

-- ============================================================
-- 7. ANALÍTICA DE EVENTOS
-- ============================================================
create table if not exists public.analytics_events (
  id bigint generated always as identity primary key,
  event_name text not null,
  space_id uuid references public.spaces(id) on delete set null,
  path text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists analytics_events_created_idx on public.analytics_events(created_at desc);
create index if not exists analytics_events_name_idx on public.analytics_events(event_name,created_at desc);
alter table public.analytics_events enable row level security;

create or replace function public.track_public_event(
  p_event_name text,
  p_space_id uuid default null,
  p_path text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if nullif(trim(p_event_name),'') is null then return; end if;
  insert into public.analytics_events(event_name,space_id,path,metadata)
  values(left(trim(p_event_name),100),p_space_id,left(coalesce(p_path,''),500),coalesce(p_metadata,'{}'::jsonb));
end;
$$;

grant execute on function public.track_public_event(text,uuid,text,jsonb) to anon, authenticated;

-- ============================================================
-- 8. ÍNDICES OPERATIVOS
-- ============================================================
create index if not exists bookings_status_dates_idx on public.bookings(booking_status,start_date,end_date);
create index if not exists spaces_public_catalog_idx on public.spaces(active,admin_enabled,owner_active,active_until);

-- FIN — REVISAR Y EJECUTAR SOLO COMO MIGRACIÓN CONTROLADA.

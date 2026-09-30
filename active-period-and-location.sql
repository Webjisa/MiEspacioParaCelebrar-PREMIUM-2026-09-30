-- HISTÓRICO: para v22 utilizar supabase/v22-final.sql como actualización consolidada.
-- MiEspacioParaCelebrar — periodo de actividad y ubicación pública de espacios
-- Ejecutar en Supabase SQL Editor.

alter table public.spaces
  add column if not exists address text,
  add column if not exists latitude numeric(9,6),
  add column if not exists longitude numeric(9,6),
  add column if not exists active_from date,
  add column if not exists active_until date;

create index if not exists spaces_active_until_idx on public.spaces(active_until);
create index if not exists spaces_public_active_idx on public.spaces(active, active_until);

-- La visibilidad pública debe depender también de la fecha de vencimiento.
-- Esta política mantiene la lectura pública solo para espacios activos y no caducados.
drop policy if exists "Public can view active spaces" on public.spaces;
create policy "Public can view active spaces"
  on public.spaces
  for select
  to anon, authenticated
  using (
    active = true
    and (active_until is null or active_until >= current_date)
  );

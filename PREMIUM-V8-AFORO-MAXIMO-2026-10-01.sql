-- MiEspacioParaCelebrar · V8 · Aforo máximo estructurado
-- TÍTULO EXACTO: PREMIUM-V8-AFORO-MAXIMO-2026-10-01.sql
-- ESTADO: NO EJECUTADO. Ejecutar una sola vez en Supabase SQL Editor cuando se autorice.
-- No modifica reservas ni fotografías. Añade únicamente el aforo máximo del espacio.

alter table public.spaces
  add column if not exists capacity integer;

alter table public.spaces
  drop constraint if exists spaces_capacity_positive;

alter table public.spaces
  add constraint spaces_capacity_positive check (capacity is null or capacity > 0);

create or replace function public.admin_set_space_capacity(p_space_id uuid, p_capacity integer)
returns void language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos'; end if;
  if p_capacity is not null and p_capacity <= 0 then raise exception 'El aforo máximo debe ser mayor que cero'; end if;
  update public.spaces
  set capacity=p_capacity, updated_at=now()
  where id=p_space_id;
  if not found then raise exception 'Espacio no encontrado'; end if;
end; $$;

revoke all on function public.admin_set_space_capacity(uuid,integer) from public,anon;
grant execute on function public.admin_set_space_capacity(uuid,integer) to authenticated;

-- Recupera automáticamente aforos que ya estuvieran escritos como
-- características del tipo “Hasta 80 personas”, “Aforo máximo: 80”, etc.
update public.spaces s
set capacity = x.capacity, updated_at=now()
from lateral (
  select (regexp_match(sf.feature, '(?:hasta\s*)?(\d{1,4})\s*(?:personas?|comensales?|plazas?)', 'i'))[1]::integer as capacity
  from public.space_features sf
  where sf.space_id=s.id
    and sf.feature ~* '(?:hasta\s*)?\d{1,4}\s*(?:personas?|comensales?|plazas?)'
  order by sf.sort_order, sf.id
  limit 1
) x
where s.capacity is null and x.capacity is not null;

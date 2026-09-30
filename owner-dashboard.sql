-- HISTÓRICO: para v22 utilizar supabase/v22-final.sql como actualización consolidada.
-- MiEspacioParaCelebrar — acceso seguro del propietario al panel
-- 🗂️ GUARDAR — Owner dashboard RPC
-- ▶️ SOLO EJECUTAR en Supabase SQL Editor. Esta SQL debe conservarse en el proyecto.

create or replace function public.get_my_owner_id()
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not private.is_owner() then
    return null;
  end if;

  return private.current_owner_id();
end;
$$;

revoke all on function public.get_my_owner_id() from public, anon;
grant execute on function public.get_my_owner_id() to authenticated;

create or replace function public.get_owner_spaces()
returns table (
  id uuid,
  name text,
  city text,
  province text,
  active boolean,
  active_from date,
  active_until date
)
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not private.is_owner() then
    raise exception 'No tienes permisos de propietario';
  end if;

  return query
  select s.id, s.name, s.city, s.province, s.active, s.active_from, s.active_until
  from public.spaces s
  where s.owner_id = private.current_owner_id()
  order by s.name;
end;
$$;

revoke all on function public.get_owner_spaces() from public, anon;
grant execute on function public.get_owner_spaces() to authenticated;

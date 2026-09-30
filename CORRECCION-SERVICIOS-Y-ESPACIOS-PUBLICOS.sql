-- TÍTULO: CORRECCION-SERVICIOS-Y-ESPACIOS-PUBLICOS
-- Ejecutar una sola vez en Supabase SQL Editor.
-- Corrige la función del catálogo de servicios y deja documentada
-- la corrección de la consulta pública en app.js (esta última no es SQL).

create or replace function public.admin_get_service_catalog()
returns table(id uuid,name text,description text,active boolean)
language plpgsql
security definer
set search_path=public,private
as $$
begin
  if not private.is_admin() then
    raise exception 'No tienes permisos';
  end if;

  return query
    select sc.id, sc.name, sc.description, sc.active
    from public.service_catalog sc
    order by lower(sc.name);
end;
$$;

revoke all on function public.admin_get_service_catalog() from public, anon;
grant execute on function public.admin_get_service_catalog() to authenticated;

-- HISTÓRICO: para v22 utilizar supabase/v22-final.sql como actualización consolidada.
-- MiEspacioParaCelebrar — precios por día, fianza configurable y acceso propietario
-- ▶️ SOLO EJECUTAR en Supabase SQL Editor. No es necesario guardarlo como archivo de trabajo.

alter table public.spaces
  add column if not exists deposit numeric(10,2);

create index if not exists spaces_owner_id_idx on public.spaces(owner_id);

-- Los propietarios pueden consultar únicamente sus propios locales.
grant select on public.spaces to authenticated;

drop policy if exists "Owners can view own spaces" on public.spaces;
create policy "Owners can view own spaces"
  on public.spaces
  for select
  to authenticated
  using (
    public.private.is_admin()
    or owner_id = public.private.current_owner_id()
  );

-- El propietario puede consultar su propio registro y los administradores todos.
grant select on public.owners to authenticated;
drop policy if exists "Owners can view own owner record" on public.owners;
create policy "Owners can view own owner record"
  on public.owners
  for select
  to authenticated
  using (
    public.private.is_admin()
    or profile_id = auth.uid()
  );


-- Solo el administrador puede modificar periodo, precios, fianza y ubicación.
create or replace function public.admin_update_space(
  p_space_id uuid,
  p_active boolean,
  p_active_from date default null,
  p_active_until date default null,
  p_weekday_price numeric default null,
  p_friday_price numeric default null,
  p_saturday_price numeric default null,
  p_sunday_price numeric default null,
  p_deposit numeric default null,
  p_address text default null,
  p_latitude numeric default null,
  p_longitude numeric default null
)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin() then
    raise exception 'No tienes permisos de administrador';
  end if;
  if p_active_until is not null and p_active_from is not null and p_active_until < p_active_from then
    raise exception 'La fecha de fin no puede ser anterior a la fecha de inicio';
  end if;
  update public.spaces
  set active=p_active,
      active_from=p_active_from,
      active_until=p_active_until,
      weekday_price=p_weekday_price,
      friday_price=p_friday_price,
      saturday_price=p_saturday_price,
      sunday_price=p_sunday_price,
      deposit=p_deposit,
      address=p_address,
      latitude=p_latitude,
      longitude=p_longitude,
      updated_at=now()
  where id=p_space_id;
  if not found then raise exception 'Espacio no encontrado'; end if;
end;
$$;
revoke all on function public.admin_update_space(uuid,boolean,date,date,numeric,numeric,numeric,numeric,numeric,text,numeric,numeric) from public, anon;
grant execute on function public.admin_update_space(uuid,boolean,date,date,numeric,numeric,numeric,numeric,numeric,text,numeric,numeric) to authenticated;

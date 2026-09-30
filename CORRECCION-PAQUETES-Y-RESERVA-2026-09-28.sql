-- MiEspacioParaCelebrar — corrección de paquetes, dependencias y snapshot de reserva
-- 🗂️ GUARDAR — CORRECCION-PAQUETES-Y-RESERVA-2026-09-28
-- ▶️ SOLO EJECUTAR una vez en Supabase SQL Editor. No ejecutar FINAL-2026.sql después.
-- Esta actualización NO modifica reservas existentes ni precios guardados.
-- Corrige la validación de dependencias: la selección pública usa space_services.id,
-- mientras depends_on_service_id conserva service_catalog.id.

begin;

create or replace function public.get_booking_quote(
  p_space_id uuid,
  p_start_date date,
  p_end_date date,
  p_cleaning_requested boolean default false,
  p_selected_services jsonb default '[]'::jsonb
) returns jsonb
language plpgsql security definer set search_path=public,private as $$
declare
  v_deposit numeric:=0;
  v_cleaning_available boolean:=false;
  v_cleaning_price numeric:=0;
  v_rental numeric:=0;
  v_cleaning numeric:=0;
  v_services_total numeric:=0;
  v_has_override boolean:=false;
  v_day date;
  v_price numeric;
  v_requested jsonb;
  v_service_id uuid;
  v_service_name text;
  v_service_description text;
  v_service_price numeric;
  v_group text;
  v_required boolean;
  v_replaces boolean;
  v_mode text;
  v_allowed smallint[];
  v_dep uuid;
  v_services jsonb:='[]'::jsonb;
  v_daily jsonb:='[]'::jsonb;
  v_selected_ids uuid[]:=array[]::uuid[];
  v_days integer:=(p_end_date-p_start_date)+1;
begin
  if p_start_date is null or p_end_date is null or p_end_date<p_start_date then
    raise exception 'Rango de fechas no válido';
  end if;

  if not exists(select 1 from public.spaces where id=p_space_id) then
    raise exception 'El espacio no existe';
  end if;

  select coalesce(deposit,0),coalesce(cleaning_available,false),coalesce(cleaning_price,0)
    into v_deposit,v_cleaning_available,v_cleaning_price
  from public.spaces where id=p_space_id;

  if p_cleaning_requested and not v_cleaning_available then
    raise exception 'El servicio de limpieza no está disponible';
  end if;

  for v_day in select generate_series(p_start_date,p_end_date,interval '1 day')::date loop
    select p.price into v_price
    from public.space_day_prices p
    where p.space_id=p_space_id
      and p.day_of_week=extract(isodow from v_day)::smallint;

    if v_price is null then
      raise exception 'No hay un precio configurado para %',to_char(v_day,'DD/MM/YYYY');
    end if;

    v_rental:=v_rental+v_price;
    v_daily:=v_daily||jsonb_build_array(
      jsonb_build_object(
        'date',v_day,
        'day_of_week',extract(isodow from v_day)::int,
        'price',round(v_price,2)
      )
    );
  end loop;

  for v_requested in select value from jsonb_array_elements(coalesce(p_selected_services,'[]'::jsonb)) loop
    begin
      v_service_id:=(v_requested->>'id')::uuid;
    exception when others then
      raise exception 'Servicio seleccionado no válido';
    end;

    if v_service_id=any(v_selected_ids) then
      raise exception 'No se puede seleccionar dos veces la misma opción';
    end if;

    v_selected_ids:=array_append(v_selected_ids,v_service_id);

    select sc.name,
           sc.description,
           ss.price,
           ss.selection_group,
           ss.selection_required,
           ss.replaces_rental,
           ss.price_mode,
           ss.allowed_days,
           ss.depends_on_service_id
      into v_service_name,
           v_service_description,
           v_service_price,
           v_group,
           v_required,
           v_replaces,
           v_mode,
           v_allowed,
           v_dep
    from public.space_services ss
    join public.service_catalog sc on sc.id=ss.service_id
    where ss.id=v_service_id
      and ss.space_id=p_space_id
      and ss.active=true
      and ss.included=false
      and sc.active=true;

    if not found then
      raise exception 'Uno de los servicios seleccionados ya no está disponible';
    end if;

    if v_allowed is not null and exists(
      select 1
      from generate_series(p_start_date,p_end_date,interval '1 day') d
      where extract(isodow from d)::smallint <> all(v_allowed)
    ) then
      raise exception 'La opción "%" no está disponible para todas las fechas seleccionadas',v_service_name;
    end if;

    if v_group is not null and (
      select count(*)
      from public.space_services z
      where z.space_id=p_space_id
        and z.active=true
        and z.selection_group=v_group
        and z.included=false
        and z.id=any(v_selected_ids)
    )>1 then
      raise exception 'Solo puedes elegir una opción del grupo "%"',v_group;
    end if;

    if coalesce(v_replaces,false) then
      v_has_override:=true;
    end if;

    if coalesce(v_mode,'fixed')='per_day' then
      v_services_total:=v_services_total+coalesce(v_service_price,0)*v_days;
    else
      v_services_total:=v_services_total+coalesce(v_service_price,0);
    end if;

    v_services:=v_services||jsonb_build_array(
      jsonb_build_object(
        'id',v_service_id,
        'service_id',(select ss.service_id from public.space_services ss where ss.id=v_service_id),
        'name',v_service_name,
        'description',v_service_description,
        'price',v_service_price,
        'total',case
          when coalesce(v_mode,'fixed')='per_day'
            then coalesce(v_service_price,0)*v_days
          else coalesce(v_service_price,0)
        end,
        'selection_group',v_group,
        'price_mode',coalesce(v_mode,'fixed'),
        'replaces_rental',coalesce(v_replaces,false),
        'depends_on_service_id',v_dep
      )
    );
  end loop;

  -- depends_on_service_id contiene service_catalog.id.
  -- La selección pública contiene space_services.id.
  -- Se valida después de leer todas las opciones para que el orden no importe.
  for v_dep in
    select distinct ss.depends_on_service_id
    from public.space_services ss
    where ss.space_id=p_space_id
      and ss.active=true
      and ss.included=false
      and ss.id=any(v_selected_ids)
      and ss.depends_on_service_id is not null
  loop
    if not exists(
      select 1
      from public.space_services dep
      where dep.space_id=p_space_id
        and dep.active=true
        and dep.included=false
        and dep.id=any(v_selected_ids)
        and dep.service_id=v_dep
    ) then
      raise exception 'Una de las opciones seleccionadas requiere el paquete correspondiente';
    end if;
  end loop;

  for v_group in
    select distinct ss.selection_group
    from public.space_services ss
    where ss.space_id=p_space_id
      and ss.active=true
      and ss.included=false
      and ss.selection_required=true
      and ss.selection_group is not null
  loop
    if not exists(
      select 1
      from public.space_services ss
      where ss.space_id=p_space_id
        and ss.active=true
        and ss.included=false
        and ss.selection_group=v_group
        and ss.id=any(v_selected_ids)
    ) then
      raise exception 'Debes seleccionar una opción de "%"',v_group;
    end if;
  end loop;

  if v_has_override then
    v_rental:=0;
  end if;

  if p_cleaning_requested then
    v_cleaning:=v_cleaning_price;
  end if;

  return jsonb_build_object(
    'rental_total',round(v_rental,2),
    'cleaning_total',round(v_cleaning,2),
    'services_total',round(v_services_total,2),
    'deposit',round(v_deposit,2),
    'grand_total',round(v_rental+v_cleaning+v_services_total+v_deposit,2),
    'services_snapshot',v_services,
    'daily_rental',v_daily
  );
end;
$$;

revoke all on function public.get_booking_quote(uuid,date,date,boolean,jsonb) from public,anon,authenticated;
grant execute on function public.get_booking_quote(uuid,date,date,boolean,jsonb) to anon,authenticated;

commit;

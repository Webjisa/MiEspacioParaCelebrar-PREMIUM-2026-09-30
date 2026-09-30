-- 🗂️ GUARDAR — MIGRACION-PRECIOS-DIARIOS-Y-PAQUETES
-- ▶️ EJECUTAR UNA SOLA VEZ en Supabase SQL Editor.
-- Convierte los precios de lunes-jueves en precios configurables por cada día
-- y amplía los servicios por espacio para soportar paquetes/opciones seleccionables.

begin;

-- ============================================================
-- 1. PRECIO INDIVIDUAL PARA CADA DÍA
-- ============================================================
create table if not exists public.space_day_prices (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 1 and 7),
  price numeric(10,2) not null default 0 check (price >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(space_id, day_of_week)
);

create index if not exists space_day_prices_space_idx
  on public.space_day_prices(space_id, day_of_week);

alter table public.space_day_prices enable row level security;

drop policy if exists "Public can view public space day prices" on public.space_day_prices;
create policy "Public can view public space day prices"
on public.space_day_prices for select to anon, authenticated
using (exists (
  select 1 from public.spaces s
  where s.id=space_day_prices.space_id
    and s.active=true and s.admin_enabled=true and s.owner_active=true
    and (s.active_from is null or s.active_from <= current_date)
    and (s.active_until is null or s.active_until >= current_date)
));

drop policy if exists "Admins manage space day prices" on public.space_day_prices;
create policy "Admins manage space day prices"
on public.space_day_prices for all to authenticated
using (private.is_admin()) with check (private.is_admin());

-- Los propietarios no escriben directamente: lo hacen mediante RPC.
drop policy if exists "Owners read own space day prices" on public.space_day_prices;
create policy "Owners read own space day prices"
on public.space_day_prices for select to authenticated
using (exists (
  select 1 from public.spaces s
  where s.id=space_day_prices.space_id
    and s.owner_id=private.current_owner_id()
));

-- Migración inicial desde los precios antiguos.
insert into public.space_day_prices(space_id,day_of_week,price)
select s.id,d.day_of_week,
       case
         when d.day_of_week between 1 and 4 then coalesce(s.weekday_price,0)
         when d.day_of_week=5 then coalesce(s.friday_price,0)
         when d.day_of_week=6 then coalesce(s.saturday_price,0)
         when d.day_of_week=7 then coalesce(s.sunday_price,0)
       end
from public.spaces s
cross join (values (1::smallint),(2::smallint),(3::smallint),(4::smallint),(5::smallint),(6::smallint),(7::smallint)) d(day_of_week)
where not exists (select 1 from public.space_day_prices x where x.space_id=s.id);

-- ============================================================
-- 2. OPCIONES / PAQUETES POR ESPACIO
-- ============================================================
alter table public.space_services
  add column if not exists selection_group text,
  add column if not exists selection_required boolean not null default false,
  add column if not exists replaces_rental boolean not null default false,
  add column if not exists price_mode text not null default 'fixed',
  add column if not exists allowed_days smallint[],
  add column if not exists depends_on_service_id uuid references public.service_catalog(id) on delete set null;

alter table public.space_services
  drop constraint if exists space_services_price_mode_check;
alter table public.space_services
  add constraint space_services_price_mode_check
  check (price_mode in ('fixed','per_day'));

-- ============================================================
-- 3. FUNCIONES DE PRECIOS DIARIOS
-- ============================================================
create or replace function public.get_public_space_day_prices(p_space_id uuid)
returns table(day_of_week smallint,price numeric)
language sql stable security definer set search_path=public,private as $$
  select p.day_of_week,p.price
  from public.space_day_prices p
  where p.space_id=p_space_id
  order by p.day_of_week;
$$;
revoke all on function public.get_public_space_day_prices(uuid) from public,anon,authenticated;
grant execute on function public.get_public_space_day_prices(uuid) to anon,authenticated;

create or replace function public.admin_get_space_day_prices(p_space_id uuid)
returns table(day_of_week smallint,price numeric)
language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos'; end if;
  return query select p.day_of_week,p.price from public.space_day_prices p where p.space_id=p_space_id order by p.day_of_week;
end; $$;
revoke all on function public.admin_get_space_day_prices(uuid) from public,anon;
grant execute on function public.admin_get_space_day_prices(uuid) to authenticated;

create or replace function public.admin_save_space_day_prices(
  p_space_id uuid,
  p_monday numeric,
  p_tuesday numeric,
  p_wednesday numeric,
  p_thursday numeric,
  p_friday numeric,
  p_saturday numeric,
  p_sunday numeric
) returns void language plpgsql security definer set search_path=public,private as $$
declare vals numeric[] := array[p_monday,p_tuesday,p_wednesday,p_thursday,p_friday,p_saturday,p_sunday]; i integer;
begin
  if not private.is_admin() then raise exception 'No tienes permisos'; end if;
  if not exists(select 1 from public.spaces where id=p_space_id) then raise exception 'Espacio no encontrado'; end if;
  for i in 1..7 loop
    if coalesce(vals[i],0) < 0 then raise exception 'El precio no puede ser negativo'; end if;
    insert into public.space_day_prices(space_id,day_of_week,price)
    values(p_space_id,i,coalesce(vals[i],0))
    on conflict(space_id,day_of_week) do update set price=excluded.price,updated_at=now();
  end loop;
  -- Compatibilidad con código histórico que todavía consulte estos campos.
  update public.spaces set
    weekday_price=coalesce(p_monday,0),
    friday_price=coalesce(p_friday,0),
    saturday_price=coalesce(p_saturday,0),
    sunday_price=coalesce(p_sunday,0),
    updated_at=now()
  where id=p_space_id;
end; $$;
revoke all on function public.admin_save_space_day_prices(uuid,numeric,numeric,numeric,numeric,numeric,numeric,numeric) from public,anon;
grant execute on function public.admin_save_space_day_prices(uuid,numeric,numeric,numeric,numeric,numeric,numeric,numeric) to authenticated;

create or replace function public.owner_get_space_day_prices(p_space_id uuid)
returns table(day_of_week smallint,price numeric)
language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_owner() then raise exception 'No tienes permisos'; end if;
  return query
  select p.day_of_week,p.price
  from public.space_day_prices p join public.spaces s on s.id=p.space_id
  where p.space_id=p_space_id and s.owner_id=private.current_owner_id()
  order by p.day_of_week;
end; $$;
revoke all on function public.owner_get_space_day_prices(uuid) from public,anon;
grant execute on function public.owner_get_space_day_prices(uuid) to authenticated;

create or replace function public.owner_save_space_day_prices(
  p_space_id uuid,
  p_monday numeric,
  p_tuesday numeric,
  p_wednesday numeric,
  p_thursday numeric,
  p_friday numeric,
  p_saturday numeric,
  p_sunday numeric
) returns void language plpgsql security definer set search_path=public,private as $$
declare vals numeric[] := array[p_monday,p_tuesday,p_wednesday,p_thursday,p_friday,p_saturday,p_sunday]; i integer;
begin
  if not private.is_owner() then raise exception 'No tienes permisos'; end if;
  if not exists(select 1 from public.spaces where id=p_space_id and owner_id=private.current_owner_id()) then raise exception 'No tienes permisos sobre este espacio'; end if;
  for i in 1..7 loop
    if coalesce(vals[i],0) < 0 then raise exception 'El precio no puede ser negativo'; end if;
    insert into public.space_day_prices(space_id,day_of_week,price)
    values(p_space_id,i,coalesce(vals[i],0))
    on conflict(space_id,day_of_week) do update set price=excluded.price,updated_at=now();
  end loop;
  update public.spaces set weekday_price=coalesce(p_monday,0),friday_price=coalesce(p_friday,0),saturday_price=coalesce(p_saturday,0),sunday_price=coalesce(p_sunday,0),updated_at=now() where id=p_space_id;
end; $$;
revoke all on function public.owner_save_space_day_prices(uuid,numeric,numeric,numeric,numeric,numeric,numeric,numeric) from public,anon;
grant execute on function public.owner_save_space_day_prices(uuid,numeric,numeric,numeric,numeric,numeric,numeric,numeric) to authenticated;

-- ============================================================
-- 4. SERVICIOS / PAQUETES PÚBLICOS CON METADATOS DE SELECCIÓN
-- ============================================================
drop function if exists public.get_public_space_services(uuid);
create or replace function public.get_public_space_services(p_space_id uuid)
returns table(
  id uuid,service_id uuid,name text,description text,included boolean,price numeric,active boolean,
  selection_group text,selection_required boolean,replaces_rental boolean,price_mode text,allowed_days smallint[],depends_on_service_id uuid
)
language sql stable security definer set search_path=public,private as $$
  select ss.id,ss.service_id,sc.name,sc.description,ss.included,ss.price,ss.active,
         ss.selection_group,ss.selection_required,ss.replaces_rental,ss.price_mode,ss.allowed_days,ss.depends_on_service_id
  from public.space_services ss
  join public.service_catalog sc on sc.id=ss.service_id
  where ss.space_id=p_space_id and ss.active=true and sc.active=true
  order by coalesce(ss.selection_group,''),lower(sc.name);
$$;
revoke all on function public.get_public_space_services(uuid) from public,anon,authenticated;
grant execute on function public.get_public_space_services(uuid) to anon,authenticated;

create or replace function public.admin_save_space_service_v2(
  p_space_id uuid,p_service_id uuid,p_included boolean,p_price numeric,p_active boolean,
  p_selection_group text default null,p_selection_required boolean default false,p_replaces_rental boolean default false,
  p_price_mode text default 'fixed',p_allowed_days smallint[] default null,p_depends_on_service_id uuid default null
) returns uuid language plpgsql security definer set search_path=public,private as $$
declare v uuid;
begin
  if not private.is_admin() then raise exception 'No tienes permisos'; end if;
  if not exists(select 1 from public.spaces where id=p_space_id) then raise exception 'Espacio no encontrado'; end if;
  if not exists(select 1 from public.service_catalog where id=p_service_id) then raise exception 'Servicio no encontrado'; end if;
  if p_price_mode not in ('fixed','per_day') then raise exception 'Modo de precio no válido'; end if;
  if p_price is not null and p_price < 0 then raise exception 'El precio no puede ser negativo'; end if;
  insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode,allowed_days,depends_on_service_id)
  values(p_space_id,p_service_id,coalesce(p_included,false),case when p_included then null else coalesce(p_price,0) end,coalesce(p_active,true),nullif(btrim(p_selection_group),''),coalesce(p_selection_required,false),coalesce(p_replaces_rental,false),coalesce(p_price_mode,'fixed'),p_allowed_days,p_depends_on_service_id)
  on conflict(space_id,service_id) do update set
    included=excluded.included,price=excluded.price,active=excluded.active,selection_group=excluded.selection_group,
    selection_required=excluded.selection_required,replaces_rental=excluded.replaces_rental,price_mode=excluded.price_mode,
    allowed_days=excluded.allowed_days,depends_on_service_id=excluded.depends_on_service_id,updated_at=now()
  returning id into v;
  return v;
end; $$;
revoke all on function public.admin_save_space_service_v2(uuid,uuid,boolean,numeric,boolean,text,boolean,boolean,text,smallint[],uuid) from public,anon;
grant execute on function public.admin_save_space_service_v2(uuid,uuid,boolean,numeric,boolean,text,boolean,boolean,text,smallint[],uuid) to authenticated;

-- ============================================================
-- 5. COTIZACIÓN ÚNICA: PRECIOS DIARIOS + PAQUETES/OPCIONES
-- ============================================================
create or replace function public.get_booking_quote(
  p_space_id uuid,p_start_date date,p_end_date date,p_cleaning_requested boolean default false,p_selected_services jsonb default '[]'::jsonb
) returns jsonb
language plpgsql security definer set search_path=public,private as $$
declare
  v_deposit numeric:=0; v_cleaning_available boolean:=false; v_cleaning_price numeric:=0; v_rental numeric:=0; v_cleaning numeric:=0; v_services_total numeric:=0;
  v_has_override boolean:=false; v_day date; v_price numeric; v_requested jsonb; v_service_id uuid; v_service_name text; v_service_description text; v_service_price numeric; v_group text; v_required boolean; v_replaces boolean; v_mode text; v_allowed smallint[]; v_dep uuid;
  v_services jsonb:='[]'::jsonb; v_daily jsonb:='[]'::jsonb; v_selected_ids uuid[]:=array[]::uuid[]; v_days integer:=(p_end_date-p_start_date)+1;
begin
  if p_start_date is null or p_end_date is null or p_end_date<p_start_date then raise exception 'Rango de fechas no válido'; end if;
  if not exists(select 1 from public.spaces where id=p_space_id) then raise exception 'El espacio no existe'; end if;
  select coalesce(deposit,0),coalesce(cleaning_available,false),coalesce(cleaning_price,0)
    into v_deposit,v_cleaning_available,v_cleaning_price from public.spaces where id=p_space_id;
  if p_cleaning_requested and not v_cleaning_available then raise exception 'El servicio de limpieza no está disponible'; end if;

  for v_day in select generate_series(p_start_date,p_end_date,interval '1 day')::date loop
    select p.price into v_price from public.space_day_prices p where p.space_id=p_space_id and p.day_of_week=extract(isodow from v_day)::smallint;
    if v_price is null then raise exception 'No hay un precio configurado para %',to_char(v_day,'DD/MM/YYYY'); end if;
    v_rental:=v_rental+v_price;
    v_daily:=v_daily||jsonb_build_array(jsonb_build_object('date',v_day,'day_of_week',extract(isodow from v_day)::int,'price',round(v_price,2)));
  end loop;

  for v_requested in select value from jsonb_array_elements(coalesce(p_selected_services,'[]'::jsonb)) loop
    begin v_service_id:=(v_requested->>'id')::uuid; exception when others then raise exception 'Servicio seleccionado no válido'; end;
    if v_service_id=any(v_selected_ids) then raise exception 'No se puede seleccionar dos veces la misma opción'; end if;
    v_selected_ids:=array_append(v_selected_ids,v_service_id);
    select sc.name,sc.description,ss.price,ss.selection_group,ss.selection_required,ss.replaces_rental,ss.price_mode,ss.allowed_days,ss.depends_on_service_id
      into v_service_name,v_service_description,v_service_price,v_group,v_required,v_replaces,v_mode,v_allowed,v_dep
    from public.space_services ss join public.service_catalog sc on sc.id=ss.service_id
    where ss.id=v_service_id and ss.space_id=p_space_id and ss.active=true and ss.included=false and sc.active=true;
    if not found then raise exception 'Uno de los servicios seleccionados ya no está disponible'; end if;
    if v_allowed is not null and exists(select 1 from generate_series(p_start_date,p_end_date,interval '1 day') d where extract(isodow from d)::smallint <> all(v_allowed)) then
      raise exception 'La opción "%" no está disponible para todas las fechas seleccionadas',v_service_name;
    end if;
    if v_group is not null and (select count(*) from public.space_services z where z.space_id=p_space_id and z.active=true and z.selection_group=v_group and z.included=false and z.id=any(v_selected_ids))>1 then
      raise exception 'Solo puedes elegir una opción del grupo "%"',v_group;
    end if;
    if coalesce(v_replaces,false) then v_has_override:=true; end if;
    if coalesce(v_mode,'fixed')='per_day' then v_services_total:=v_services_total+coalesce(v_service_price,0)*v_days;
    else v_services_total:=v_services_total+coalesce(v_service_price,0); end if;
    v_services:=v_services||jsonb_build_array(jsonb_build_object('id',v_service_id,'service_id',(select ss.service_id from public.space_services ss where ss.id=v_service_id),'name',v_service_name,'description',v_service_description,'price',v_service_price,'total',case when coalesce(v_mode,'fixed')='per_day' then coalesce(v_service_price,0)*v_days else coalesce(v_service_price,0) end,'selection_group',v_group,'price_mode',coalesce(v_mode,'fixed'),'replaces_rental',coalesce(v_replaces,false),'depends_on_service_id',v_dep));
  end loop;

  -- Las dependencias se comparan contra service_catalog.id, mientras la selección pública usa space_services.id.
  -- Se valida después de leer todas las opciones para no depender del orden en que lleguen.
  for v_dep in select distinct ss.depends_on_service_id from public.space_services ss where ss.space_id=p_space_id and ss.active=true and ss.included=false and ss.id=any(v_selected_ids) and ss.depends_on_service_id is not null loop
    if not exists(select 1 from public.space_services dep where dep.space_id=p_space_id and dep.active=true and dep.included=false and dep.id=any(v_selected_ids) and dep.service_id=v_dep) then
      raise exception 'Una de las opciones seleccionadas requiere el paquete correspondiente';
    end if;
  end loop;

  for v_group in select distinct ss.selection_group from public.space_services ss where ss.space_id=p_space_id and ss.active=true and ss.included=false and ss.selection_required=true and ss.selection_group is not null loop
    if not exists(select 1 from public.space_services ss where ss.space_id=p_space_id and ss.active=true and ss.included=false and ss.selection_group=v_group and ss.id=any(v_selected_ids)) then
      raise exception 'Debes seleccionar una opción de "%"',v_group;
    end if;
  end loop;

  if v_has_override then v_rental:=0; end if;
  if p_cleaning_requested then v_cleaning:=v_cleaning_price; end if;
  return jsonb_build_object('rental_total',round(v_rental,2),'cleaning_total',round(v_cleaning,2),'services_total',round(v_services_total,2),'deposit',round(v_deposit,2),'grand_total',round(v_rental+v_cleaning+v_services_total+v_deposit,2),'services_snapshot',v_services,'daily_rental',v_daily);
end; $$;
revoke all on function public.get_booking_quote(uuid,date,date,boolean,jsonb) from public,anon,authenticated;
grant execute on function public.get_booking_quote(uuid,date,date,boolean,jsonb) to anon,authenticated;

-- ============================================================
-- 6. CREACIÓN DE RESERVA: usa la cotización nueva y guarda snapshot
-- ============================================================
drop function if exists public.create_booking_request(uuid,text,text,text,date,date,boolean,text,jsonb);
create or replace function public.create_booking_request(
  p_space_id uuid,p_customer_name text,p_customer_email text,p_customer_phone text,p_start_date date,p_end_date date,
  p_cleaning_requested boolean default false,p_customer_notes text default null,p_selected_services jsonb default '[]'::jsonb
) returns uuid language plpgsql security definer set search_path=public,private as $$
declare
  v_booking_id uuid; v_owner_id uuid; v_owner_email text; v_owner_name text; v_space public.spaces%rowtype; v_expires timestamptz:=now()+interval '72 hours'; v_quote jsonb;
begin
  if btrim(coalesce(p_customer_name,''))='' or btrim(coalesce(p_customer_email,''))='' or btrim(coalesce(p_customer_phone,''))='' then raise exception 'Nombre, email y teléfono son obligatorios'; end if;
  if p_start_date is null or p_end_date is null or p_end_date<p_start_date then raise exception 'Rango de fechas no válido'; end if;
  if not public.final_space_is_public(p_space_id) then raise exception 'El espacio no está disponible'; end if;
  if exists(select 1 from public.bookings where space_id=p_space_id and booking_status in ('pending','confirmed') and start_date<=p_end_date and end_date>=p_start_date) then raise exception 'Alguna de las fechas seleccionadas no está disponible'; end if;
  if exists(select 1 from public.blocked_dates where space_id=p_space_id and start_date<=p_end_date and end_date>=p_start_date) then raise exception 'Alguna de las fechas seleccionadas no está disponible'; end if;
  select * into v_space from public.spaces where id=p_space_id for share;
  v_quote:=public.get_booking_quote(p_space_id,p_start_date,p_end_date,p_cleaning_requested,p_selected_services);
  insert into public.bookings(customer_name,customer_email,customer_phone,space_id,start_date,end_date,total_days,cleaning_requested,customer_notes,booking_status,expires_at,pricing_snapshot,space_snapshot,conditions_snapshot,services_snapshot,created_at,updated_at)
  values(btrim(p_customer_name),lower(btrim(p_customer_email)),btrim(p_customer_phone),p_space_id,p_start_date,p_end_date,(p_end_date-p_start_date)+1,coalesce(p_cleaning_requested,false),nullif(btrim(p_customer_notes),''),'pending',v_expires,v_quote,
    jsonb_build_object('name',v_space.name,'city',v_space.city,'province',v_space.province,'description',v_space.description,'opening_time',v_space.opening_time,'closing_time',v_space.closing_time,'deposit',v_space.deposit),
    v_space.conditions_text,v_quote->'services_snapshot',now(),now()) returning id into v_booking_id;
  select o.id,p.email,trim(coalesce(p.first_name,'')||' '||coalesce(p.last_name,'')) into v_owner_id,v_owner_email,v_owner_name from public.owners o join public.profiles p on p.id=o.profile_id where o.id=v_space.owner_id;
  perform public.final_queue_email('reservas','customer_request_received',lower(btrim(p_customer_email)),btrim(p_customer_name),jsonb_build_object('booking_id',v_booking_id,'customer_name',p_customer_name,'space_name',v_space.name,'start_date',p_start_date,'end_date',p_end_date),v_booking_id,p_space_id);
  perform public.final_queue_email('reservas','request_created',v_owner_email,v_owner_name,jsonb_build_object('booking_id',v_booking_id,'space_name',v_space.name,'customer_name',p_customer_name,'customer_email',lower(btrim(p_customer_email)),'customer_phone',p_customer_phone,'start_date',p_start_date,'end_date',p_end_date,'expires_at',v_expires,'pricing_snapshot',v_quote,'services_snapshot',v_quote->'services_snapshot'),v_booking_id,p_space_id);
  perform public.final_queue_email('reservas','admin_request_created','miespacioparacelebrar@gmail.com','Administración',jsonb_build_object('booking_id',v_booking_id,'space_name',v_space.name,'customer_name',p_customer_name,'customer_email',lower(btrim(p_customer_email)),'customer_phone',p_customer_phone,'start_date',p_start_date,'end_date',p_end_date,'expires_at',v_expires),v_booking_id,p_space_id);
  return v_booking_id;
end; $$;
revoke all on function public.create_booking_request(uuid,text,text,text,date,date,boolean,text,jsonb) from public,anon,authenticated;
grant execute on function public.create_booking_request(uuid,text,text,text,date,date,boolean,text,jsonb) to anon,authenticated;

-- ============================================================
-- 7. ADMIN: GUARDAR OPCIONES CON METADATOS
-- ============================================================
-- El catálogo existente sigue siendo común; cada espacio decide qué ofrece.

-- ============================================================
-- 8. CUATRO ESPACIOS CASTRAVINARIA (MANU)
-- ============================================================
insert into public.spaces(
  id,owner_id,name,city,province,description,weekday_price,friday_price,saturday_price,sunday_price,
  opening_time,closing_time,deposit,cleaning_available,cleaning_price,active,admin_enabled,owner_active,active_from,active_until,conditions_text
) values
('71000000-0000-4000-8000-000000000001','18e98d2c-8a0d-4be9-bd9e-65a0c12cd232','Castravinaria — Salón I','Lucena','Córdoba','Salón en Calle El Peso para fiestas infantiles y eventos. Incluye barra bar, castillo hinchable, Smart TV y videoconsola, sistema de sonido, carrito de chuches, arco para decorar, futbolín y mix de juegos.',0,0,0,0,'12:00','24:00',50,false,0,true,true,true,current_date,'2027-12-31','Disponibilidad de uso de 12:00 a 24:00. Fianza de 50 €. Los paquetes infantiles entre semana son de lunes a jueves; el paquete de fin de semana es para viernes, sábados, domingos y festivos.'),
('71000000-0000-4000-8000-000000000002','18e98d2c-8a0d-4be9-bd9e-65a0c12cd232','Castravinaria — Salón II · Infantiles en carpa','Lucena','Córdoba','Fiestas infantiles en carpa con pista americana, campo de fútbol, cama elástica, castillo hinchable, piscina de bolas, terraza con carpa, carrito para chuches y arco para decorar.',0,0,0,0,'12:00','24:00',75,false,0,true,true,true,current_date,'2027-12-31','Disponibilidad de uso de 12:00 a 24:00. Solo fines de semana y festivos. Fianza de 75 €.'),
('71000000-0000-4000-8000-000000000003','18e98d2c-8a0d-4be9-bd9e-65a0c12cd232','Castravinaria — Salón II · Infantiles en salón','Lucena','Córdoba','Fiestas infantiles en salón con pista americana, campo de fútbol, cama elástica, castillo hinchable, piscina de bolas, carrito para chuches y arco para decorar.',0,0,0,0,'12:00','24:00',75,false,0,true,true,true,current_date,'2027-12-31','Disponibilidad de uso de 12:00 a 24:00. Solo fines de semana y festivos. Fianza de 75 €.'),
('71000000-0000-4000-8000-000000000004','18e98d2c-8a0d-4be9-bd9e-65a0c12cd232','Castravinaria — Salón II · Fiestas en salón','Lucena','Córdoba','Fiestas en salón con paquete Diversión o paquete Sabor & Diversión. Incluye barra bar, terraza con carpa y los elementos indicados en cada paquete.',0,0,0,0,'12:00','24:00',150,false,0,true,true,true,current_date,'2027-12-31','Disponibilidad de uso durante todo el día, solo fines de semana y festivos. Fianza de 150 €.')
on conflict (id) do update set owner_id=excluded.owner_id,name=excluded.name,city=excluded.city,province=excluded.province,description=excluded.description,opening_time=excluded.opening_time,closing_time=excluded.closing_time,deposit=excluded.deposit,active=true,admin_enabled=true,owner_active=true,active_from=excluded.active_from,active_until=excluded.active_until,conditions_text=excluded.conditions_text,updated_at=now();

-- El precio base queda en 0 porque estos cuatro espacios se contratan mediante paquetes.
-- Se conserva la tabla de precios diarios y se deja 0 € en los siete días.
insert into public.space_day_prices(space_id,day_of_week,price)
select s.id,d.day,0 from public.spaces s cross join generate_series(1,7) d(day)
where s.id in ('71000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000004')
on conflict(space_id,day_of_week) do update set price=0,updated_at=now();

-- Catálogo de opciones / paquetes.
insert into public.service_catalog(name,description,active) values
('Castravinaria · Infantiles entre semana','Paquete infantil de lunes a jueves.',true),
('Castravinaria · Infantiles fin de semana y festivos','Paquete infantil para viernes, sábados, domingos y festivos.',true),
('Castravinaria · Eventos','Eventos desde 200 €. Precio final a consultar.',true),
('Castravinaria · Uso de cocina','Uso de cocina como servicio adicional.',true),
('Castravinaria · 3 horas de juegos','Paquete de 3 horas de juegos.',true),
('Castravinaria · Todo el día de juegos','Paquete de todo el día de juegos.',true),
('Castravinaria · Ludoteca 3 horas','Servicio adicional de ludoteca para el paquete de 3 horas.',true),
('Castravinaria · Ludoteca todo el día','Servicio adicional de ludoteca para el paquete de todo el día.',true),
('Castravinaria · Hora extra','Una hora adicional de uso.',true),
('Castravinaria · Hora extra + ludoteca','Una hora adicional con ludoteca.',true),
('Castravinaria · Paquete Diversión','Salón, barra bar y terraza con carpa. Incluye mesas de tres tipos a elegir, sillas, botelleros, cafetera, microondas, Smart TV, máquina de juegos, WiFi, aire acondicionado, diana, sombrillas exterior y otros utensilios.',true),
('Castravinaria · Paquete Sabor & Diversión','Incluye todo lo indicado en el paquete Diversión más freidora, frigoríficos, plancha de cocina, horno, hornilla, rosco, paellera para 50 personas, peroles y otros utensilios.',true)
on conflict do nothing;

-- Helper para recuperar ids del catálogo.
-- Salón I
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode,allowed_days)
select '71000000-0000-4000-8000-000000000001',id,false,100,true,'paquete',true,true,'fixed',array[1,2,3,4]::smallint[] from public.service_catalog where name='Castravinaria · Infantiles entre semana'
on conflict(space_id,service_id) do update set price=100,active=true,selection_group='paquete',selection_required=true,replaces_rental=true,price_mode='fixed',allowed_days=excluded.allowed_days;
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode,allowed_days)
select '71000000-0000-4000-8000-000000000001',id,false,150,true,'paquete',true,true,'fixed',array[5,6,7]::smallint[] from public.service_catalog where name='Castravinaria · Infantiles fin de semana y festivos'
on conflict(space_id,service_id) do update set price=150,active=true,selection_group='paquete',selection_required=true,replaces_rental=true,price_mode='fixed',allowed_days=excluded.allowed_days;
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode,allowed_days)
select '71000000-0000-4000-8000-000000000001',id,false,200,true,'paquete',true,true,'fixed',null from public.service_catalog where name='Castravinaria · Eventos'
on conflict(space_id,service_id) do update set price=200,active=true,selection_group='paquete',selection_required=true,replaces_rental=true,price_mode='fixed',allowed_days=null;
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode)
select '71000000-0000-4000-8000-000000000001',id,false,60,true,null,false,false,'fixed' from public.service_catalog where name='Castravinaria · Uso de cocina'
on conflict(space_id,service_id) do update set price=60,active=true,selection_group=null,selection_required=false,replaces_rental=false,price_mode='fixed';

-- Salón II · carpa
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode,allowed_days)
select '71000000-0000-4000-8000-000000000002',id,false,150,true,'paquete',true,true,'fixed',array[5,6,7]::smallint[] from public.service_catalog where name='Castravinaria · 3 horas de juegos'
on conflict(space_id,service_id) do update set price=150,active=true,selection_group='paquete',selection_required=true,replaces_rental=true,price_mode='fixed',allowed_days=excluded.allowed_days;
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode,allowed_days)
select '71000000-0000-4000-8000-000000000002',id,false,300,true,'paquete',true,true,'fixed',array[5,6,7]::smallint[] from public.service_catalog where name='Castravinaria · Todo el día de juegos'
on conflict(space_id,service_id) do update set price=300,active=true,selection_group='paquete',selection_required=true,replaces_rental=true,price_mode='fixed',allowed_days=excluded.allowed_days;
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode) select '71000000-0000-4000-8000-000000000002',id,false,60,true,null,false,false,'fixed' from public.service_catalog where name='Castravinaria · Ludoteca 3 horas' on conflict(space_id,service_id) do update set price=60,active=true,selection_group=null,selection_required=false,replaces_rental=false,price_mode='fixed';
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode) select '71000000-0000-4000-8000-000000000002',id,false,100,true,null,false,false,'fixed' from public.service_catalog where name='Castravinaria · Ludoteca todo el día' on conflict(space_id,service_id) do update set price=100,active=true,selection_group=null,selection_required=false,replaces_rental=false,price_mode='fixed';
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode) select '71000000-0000-4000-8000-000000000002',id,false,30,true,null,false,false,'fixed' from public.service_catalog where name='Castravinaria · Hora extra' on conflict(space_id,service_id) do update set price=30,active=true,selection_group=null,selection_required=false,replaces_rental=false,price_mode='fixed';
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode) select '71000000-0000-4000-8000-000000000002',id,false,40,true,null,false,false,'fixed' from public.service_catalog where name='Castravinaria · Hora extra + ludoteca' on conflict(space_id,service_id) do update set price=40,active=true,selection_group=null,selection_required=false,replaces_rental=false,price_mode='fixed';

-- Salón II · salón infantil
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode,allowed_days)
select '71000000-0000-4000-8000-000000000003',id,false,250,true,'paquete',true,true,'fixed',array[5,6,7]::smallint[] from public.service_catalog where name='Castravinaria · 3 horas de juegos'
on conflict(space_id,service_id) do update set price=250,active=true,selection_group='paquete',selection_required=true,replaces_rental=true,price_mode='fixed',allowed_days=excluded.allowed_days;
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode)
select '71000000-0000-4000-8000-000000000003',id,false,60,true,null,false,false,'fixed' from public.service_catalog where name='Castravinaria · Ludoteca 3 horas'
on conflict(space_id,service_id) do update set price=60,active=true,selection_group=null,selection_required=false,replaces_rental=false,price_mode='fixed';
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode)
select '71000000-0000-4000-8000-000000000003',id,false,30,true,null,false,false,'fixed' from public.service_catalog where name='Castravinaria · Hora extra'
on conflict(space_id,service_id) do update set price=30,active=true,selection_group=null,selection_required=false,replaces_rental=false,price_mode='fixed';
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode)
select '71000000-0000-4000-8000-000000000003',id,false,40,true,null,false,false,'fixed' from public.service_catalog where name='Castravinaria · Hora extra + ludoteca'
on conflict(space_id,service_id) do update set price=40,active=true,selection_group=null,selection_required=false,replaces_rental=false,price_mode='fixed';

-- Salón II · fiestas en salón
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode,allowed_days)
select '71000000-0000-4000-8000-000000000004',id,false,400,true,'paquete',true,true,'fixed',array[5,6,7]::smallint[] from public.service_catalog where name='Castravinaria · Paquete Diversión'
on conflict(space_id,service_id) do update set price=400,active=true,selection_group='paquete',selection_required=true,replaces_rental=true,price_mode='fixed',allowed_days=excluded.allowed_days;
insert into public.space_services(space_id,service_id,included,price,active,selection_group,selection_required,replaces_rental,price_mode,allowed_days)
select '71000000-0000-4000-8000-000000000004',id,false,600,true,'paquete',true,true,'fixed',array[5,6,7]::smallint[] from public.service_catalog where name='Castravinaria · Paquete Sabor & Diversión'
on conflict(space_id,service_id) do update set price=600,active=true,selection_group='paquete',selection_required=true,replaces_rental=true,price_mode='fixed',allowed_days=excluded.allowed_days;

-- Dependencias de extras respecto al paquete elegido.
update public.space_services ss set depends_on_service_id=(select id from public.service_catalog where name='Castravinaria · 3 horas de juegos') where ss.space_id='71000000-0000-4000-8000-000000000002' and ss.service_id=(select id from public.service_catalog where name='Castravinaria · Ludoteca 3 horas');
update public.space_services ss set depends_on_service_id=(select id from public.service_catalog where name='Castravinaria · Todo el día de juegos') where ss.space_id='71000000-0000-4000-8000-000000000002' and ss.service_id=(select id from public.service_catalog where name='Castravinaria · Ludoteca todo el día');
update public.space_services ss set depends_on_service_id=(select id from public.service_catalog where name='Castravinaria · 3 horas de juegos') where ss.space_id='71000000-0000-4000-8000-000000000003' and ss.service_id in (select id from public.service_catalog where name in ('Castravinaria · Ludoteca 3 horas','Castravinaria · Hora extra','Castravinaria · Hora extra + ludoteca'));

-- Fotografías de los cuatro espacios.
delete from public.space_images where space_id in ('71000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000004');
insert into public.space_images(space_id,image_url,alt_text,is_main,sort_order)
values
('71000000-0000-4000-8000-000000000001','assets/castravinaria-salon-1.webp','Castravinaria — Salón I',true,0),
('71000000-0000-4000-8000-000000000002','assets/castravinaria-salon-2-infantiles-carpa.webp','Castravinaria — Salón II, infantiles en carpa',true,0),
('71000000-0000-4000-8000-000000000003','assets/castravinaria-salon-2-infantiles-salon.webp','Castravinaria — Salón II, infantiles en salón',true,0),
('71000000-0000-4000-8000-000000000004','assets/castravinaria-salon-2-eventos.webp','Castravinaria — Salón II, fiestas en salón',true,0)
on conflict do nothing;

-- Características visibles en la ficha.
delete from public.space_features where space_id in ('71000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000004');
insert into public.space_features(space_id,feature,sort_order) values
('71000000-0000-4000-8000-000000000001','Salón',1),
('71000000-0000-4000-8000-000000000001','Barra bar',2),
('71000000-0000-4000-8000-000000000001','Castillo hinchable',3),
('71000000-0000-4000-8000-000000000001','Smart TV + videoconsola',4),
('71000000-0000-4000-8000-000000000001','Sistema de sonido',5),
('71000000-0000-4000-8000-000000000001','Carrito de chuches',6),
('71000000-0000-4000-8000-000000000001','Arco para decorar',7),
('71000000-0000-4000-8000-000000000001','Futbolín',8),
('71000000-0000-4000-8000-000000000001','Mix de juegos: diana, 3 en línea gigante, Twister…',9),
('71000000-0000-4000-8000-000000000001','Mesas y sillas',10),
('71000000-0000-4000-8000-000000000001','Botellero, microondas, cafetera y frigorífico',11),
('71000000-0000-4000-8000-000000000001','Horno y aire acondicionado',12),
('71000000-0000-4000-8000-000000000001','Servicios extra: uso de cocina por 60 €',13),
('71000000-0000-4000-8000-000000000002','Pista americana',1),
('71000000-0000-4000-8000-000000000002','Campo de fútbol',2),
('71000000-0000-4000-8000-000000000002','Cama elástica',3),
('71000000-0000-4000-8000-000000000002','Castillo hinchable',4),
('71000000-0000-4000-8000-000000000002','Piscina de bolas',5),
('71000000-0000-4000-8000-000000000002','Terraza con carpa',6),
('71000000-0000-4000-8000-000000000002','Carrito para chuches',7),
('71000000-0000-4000-8000-000000000002','Arco para decorar',8),
('71000000-0000-4000-8000-000000000002','Mesas, sillas, barra bar, cafetera, microondas y botellero incluidos',9),
('71000000-0000-4000-8000-000000000002','Congelador, cañones de aire y estufas incluidos',10),
('71000000-0000-4000-8000-000000000002','Servicios extra opcionales: decoración de mesa de chuches y golosinas, montaje de catering de merienda y máquina de perritos',11),
('71000000-0000-4000-8000-000000000003','Pista americana',1),
('71000000-0000-4000-8000-000000000003','Campo de fútbol',2),
('71000000-0000-4000-8000-000000000003','Cama elástica',3),
('71000000-0000-4000-8000-000000000003','Castillo hinchable',4),
('71000000-0000-4000-8000-000000000003','Piscina de bolas',5),
('71000000-0000-4000-8000-000000000003','Carrito para chuches',6),
('71000000-0000-4000-8000-000000000003','Arco para decorar',7),
('71000000-0000-4000-8000-000000000003','Mesas, sillas, barra bar, cafetera, microondas y botellero incluidos',8),
('71000000-0000-4000-8000-000000000003','Congelador, cañones de aire y estufas incluidos',9),
('71000000-0000-4000-8000-000000000003','Servicios extra opcionales: decoración de mesa de chuches y golosinas, montaje de catering de merienda y máquina de perritos',10),
('71000000-0000-4000-8000-000000000004','Salón',1),
('71000000-0000-4000-8000-000000000004','Barra bar',2),
('71000000-0000-4000-8000-000000000004','Terraza con carpa',3),
('71000000-0000-4000-8000-000000000004','Mesas y sillas',4),
('71000000-0000-4000-8000-000000000004','Botelleros, cafetera y microondas',5),
('71000000-0000-4000-8000-000000000004','Smart TV y máquina de juegos',6),
('71000000-0000-4000-8000-000000000004','WiFi y aire acondicionado',7),
('71000000-0000-4000-8000-000000000004','Diana y sombrillas exterior',8),
('71000000-0000-4000-8000-000000000004','Cocina, freidora, frigoríficos, plancha, horno, hornilla, rosco, paellera 50 p. y peroles en paquete Sabor & Diversión',9),
('71000000-0000-4000-8000-000000000004','Servicios extra: alquiler de manteles, servilletas, caminos, fundas de sillas, máquina de perritos y menaje',10)
on conflict do nothing;

-- ============================================================
-- 9. COTIZACIÓN LEGACY PARA EL ÁREA DEL PROPIETARIO
-- ============================================================
drop function if exists public.get_booking_pricing(uuid,date,date,boolean);
create or replace function public.get_booking_pricing(
  p_space_id uuid,p_start_date date,p_end_date date,p_cleaning_requested boolean default false
) returns table(rental_total numeric,cleaning_total numeric,deposit numeric,grand_total numeric)
language plpgsql security definer set search_path=public,private as $$
declare q jsonb;
begin
  q:=public.get_booking_quote(p_space_id,p_start_date,p_end_date,p_cleaning_requested,'[]'::jsonb);
  return query select (q->>'rental_total')::numeric,(q->>'cleaning_total')::numeric,(q->>'deposit')::numeric,(q->>'grand_total')::numeric;
end; $$;
revoke all on function public.get_booking_pricing(uuid,date,date,boolean) from public,anon,authenticated;
grant execute on function public.get_booking_pricing(uuid,date,date,boolean) to anon,authenticated;

-- ============================================================
-- 10. MODIFICACIÓN DE RESERVAS CONFIRMADAS CON NUEVA COTIZACIÓN
-- ============================================================
drop function if exists public.owner_update_booking(uuid,date,date,boolean,jsonb,text);
create or replace function public.owner_update_booking(
 p_booking_id uuid,p_start_date date,p_end_date date,p_cleaning_requested boolean,p_selected_services jsonb default '[]'::jsonb,p_customer_notes text default null
) returns void language plpgsql security definer set search_path=public,private as $$
declare b public.bookings%rowtype; s public.spaces%rowtype; q jsonb; new_services jsonb;
begin
 if not private.is_owner() then raise exception 'No tienes permisos'; end if;
 select * into b from public.bookings where id=p_booking_id for update;
 select * into s from public.spaces where id=b.space_id;
 if s.owner_id<>private.current_owner_id() then raise exception 'No tienes permisos sobre esta reserva'; end if;
 if b.booking_status<>'confirmed' then raise exception 'Solo se pueden modificar reservas confirmadas'; end if;
 if p_start_date is null or p_end_date<p_start_date then raise exception 'Rango de fechas no válido'; end if;
 if p_start_date < current_date then raise exception 'No se pueden modificar fechas ya iniciadas'; end if;
 if exists(select 1 from public.bookings z where z.id<>b.id and z.space_id=b.space_id and z.booking_status in ('pending','confirmed') and z.start_date<=p_end_date and z.end_date>=p_start_date) then raise exception 'Las nuevas fechas no están disponibles'; end if;
 if exists(select 1 from public.blocked_dates z where z.space_id=b.space_id and z.start_date<=p_end_date and z.end_date>=p_start_date) then raise exception 'Las nuevas fechas no están disponibles'; end if;
 q:=public.get_booking_quote(b.space_id,p_start_date,p_end_date,p_cleaning_requested,p_selected_services);
 new_services:=coalesce(q->'services_snapshot','[]'::jsonb);
 update public.bookings set start_date=p_start_date,end_date=p_end_date,total_days=(p_end_date-p_start_date)+1,cleaning_requested=coalesce(p_cleaning_requested,false),customer_notes=nullif(btrim(p_customer_notes),''),pricing_snapshot=q,services_snapshot=new_services,updated_at=now() where id=b.id;
 perform public.final_queue_email('reservas','customer_updated',b.customer_email,b.customer_name,jsonb_build_object('booking_id',b.id,'space_name',s.name,'start_date',p_start_date,'end_date',p_end_date),b.id,s.id);
 perform public.final_queue_email('reservas','owner_booking_final','miespacioparacelebrar@gmail.com','Administración',jsonb_build_object('booking_id',b.id,'space_name',s.name,'customer_name',b.customer_name,'status','updated','comment','Reserva modificada por el propietario'),b.id,s.id);
end; $$;
revoke all on function public.owner_update_booking(uuid,date,date,boolean,jsonb,text) from public,anon;
grant execute on function public.owner_update_booking(uuid,date,date,boolean,jsonb,text) to authenticated;

commit;

-- MiEspacioParaCelebrar — FINAL 2026
-- 🗂️ GUARDAR — FINAL-2026.sql
-- ▶️ EJECUTAR UNA SOLA VEZ en Supabase SQL Editor.
-- Esta es la migración consolidada de la versión definitiva.
-- No contiene contraseñas, claves service_role ni claves de Resend.

create extension if not exists pgcrypto;

-- ============================================================
-- 1. ESTADOS DE ESPACIO
-- ============================================================
alter table public.spaces
  add column if not exists admin_enabled boolean not null default true,
  add column if not exists owner_active boolean not null default true,
  add column if not exists conditions_text text,
  add column if not exists validity_extended_at timestamptz;

update public.spaces
set admin_enabled = coalesce(admin_enabled, active, true),
    owner_active = coalesce(owner_active, active, true)
where admin_enabled is null or owner_active is null;

-- active queda como compatibilidad histórica; la publicación final usa
-- admin_enabled + owner_active + periodo de vigencia.
create index if not exists spaces_public_state_idx
  on public.spaces(admin_enabled, owner_active, active_until);

-- Compatibilidad de galería avanzada.
alter table public.space_images add column if not exists alt_text text, add column if not exists is_main boolean not null default false, add column if not exists created_at timestamptz not null default now();

-- ============================================================
-- 2. CATÁLOGO DE SERVICIOS
-- ============================================================
create table if not exists public.service_catalog (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists service_catalog_name_uq
  on public.service_catalog(lower(btrim(name)));

create table if not exists public.space_services (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  service_id uuid not null references public.service_catalog(id) on delete restrict,
  included boolean not null default false,
  price numeric(10,2),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint space_services_price_check check (price is null or price >= 0),
  unique(space_id, service_id)
);

create index if not exists space_services_space_idx on public.space_services(space_id);

-- ============================================================
-- 3. RESERVAS: SNAPSHOT INMUTABLE
-- ============================================================
alter table public.bookings
  add column if not exists customer_notes text,
  add column if not exists pricing_snapshot jsonb,
  add column if not exists space_snapshot jsonb,
  add column if not exists conditions_snapshot text,
  add column if not exists services_snapshot jsonb,
  add column if not exists cancelled_reason text,
  add column if not exists finalized_at timestamptz,
  add column if not exists last_customer_email_sent_at timestamptz,
  add column if not exists customer_email_delivery_status text;

-- ============================================================
-- 4. HISTORIAL Y COLA DE EMAILS
-- ============================================================
create table if not exists public.change_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_role text,
  entity_type text not null,
  entity_id uuid,
  action text not null,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

create index if not exists change_log_created_idx on public.change_log(created_at desc);

create table if not exists public.email_queue (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('espacios','reservas','encuestas')),
  communication_type text not null,
  booking_id uuid references public.bookings(id) on delete cascade,
  space_id uuid references public.spaces(id) on delete cascade,
  recipient_email text not null,
  recipient_name text,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','processing','sent','failed')),
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  sent_at timestamptz,
  last_error text,
  created_at timestamptz not null default now()
);

create index if not exists email_queue_pending_idx
  on public.email_queue(status,next_attempt_at,created_at);
create index if not exists email_queue_booking_idx on public.email_queue(booking_id);

create table if not exists public.surveys (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings(id) on delete cascade,
  token_hash text not null unique,
  sent_at timestamptz,
  completed_at timestamptz,
  overall integer,
  facilities integer,
  cleaning integer,
  equipment integer,
  maintenance integer,
  improvements text,
  breakdown boolean,
  breakdown_details text,
  missing_items text,
  would_use_again boolean,
  comments text,
  created_at timestamptz not null default now(),
  constraint surveys_rating_check check (
    (overall is null or overall between 1 and 5) and
    (facilities is null or facilities between 1 and 5) and
    (cleaning is null or cleaning between 1 and 5) and
    (equipment is null or equipment between 1 and 5) and
    (maintenance is null or maintenance between 1 and 5)
  )
);

-- ============================================================
-- 5. RLS
-- ============================================================
alter table public.service_catalog enable row level security;
alter table public.space_services enable row level security;
alter table public.change_log enable row level security;
alter table public.email_queue enable row level security;
alter table public.surveys enable row level security;

drop policy if exists "Public can view active service catalog" on public.service_catalog;
create policy "Public can view active service catalog" on public.service_catalog
for select to anon, authenticated using (active = true);

drop policy if exists "Admins manage service catalog" on public.service_catalog;
create policy "Admins manage service catalog" on public.service_catalog
for all to authenticated using (private.is_admin()) with check (private.is_admin());

drop policy if exists "Public can view offered services" on public.space_services;
create policy "Public can view offered services" on public.space_services
for select to anon, authenticated using (
  active = true and exists (
    select 1 from public.spaces s
    where s.id=space_services.space_id
      and s.admin_enabled=true and s.owner_active=true
      and (s.active_from is null or s.active_from <= current_date)
      and (s.active_until is null or s.active_until >= current_date)
  )
);

drop policy if exists "Admins manage offered services" on public.space_services;
create policy "Admins manage offered services" on public.space_services
for all to authenticated using (private.is_admin()) with check (private.is_admin());

drop policy if exists "Admins read change log" on public.change_log;
create policy "Admins read change log" on public.change_log
for select to authenticated using (private.is_admin());

drop policy if exists "Admins read email queue" on public.email_queue;
create policy "Admins read email queue" on public.email_queue
for select to authenticated using (private.is_admin());

drop policy if exists "Admins read surveys" on public.surveys;
create policy "Admins read surveys" on public.surveys
for select to authenticated using (private.is_admin());

-- ============================================================
-- 6. VISIBILIDAD PÚBLICA DEFINITIVA
-- ============================================================
drop policy if exists "Public can view active spaces" on public.spaces;
drop policy if exists "Public can view enabled active spaces" on public.spaces;
create policy "Public can view enabled active spaces" on public.spaces
for select to anon, authenticated
using (
  admin_enabled=true and owner_active=true and active=true
  and (active_from is null or active_from <= current_date)
  and (active_until is null or active_until >= current_date)
);

-- ============================================================
-- 7. HELPERS
-- ============================================================
create or replace function public.final_space_is_public(p_space_id uuid)
returns boolean language sql stable security definer set search_path=public,private as $$
  select exists(
    select 1 from public.spaces s
    where s.id=p_space_id and s.active=true and s.admin_enabled=true and s.owner_active=true
      and (s.active_from is null or s.active_from <= current_date)
      and (s.active_until is null or s.active_until >= current_date)
  );
$$;
revoke all on function public.final_space_is_public(uuid) from public,anon;
grant execute on function public.final_space_is_public(uuid) to anon,authenticated;

create or replace function public.final_queue_email(
  p_category text,
  p_type text,
  p_recipient_email text,
  p_recipient_name text,
  p_payload jsonb,
  p_booking_id uuid default null,
  p_space_id uuid default null
) returns uuid language plpgsql security definer set search_path=public,private as $$
declare v_id uuid;
begin
  insert into public.email_queue(category,communication_type,booking_id,space_id,recipient_email,recipient_name,payload)
  values(p_category,p_type,p_booking_id,p_space_id,p_recipient_email,p_recipient_name,coalesce(p_payload,'{}'::jsonb))
  returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.final_queue_email(text,text,text,text,jsonb,uuid,uuid) from public,anon,authenticated;

create or replace function public.final_log_change(
  p_entity_type text,p_entity_id uuid,p_action text,p_before jsonb,p_after jsonb
) returns uuid language plpgsql security definer set search_path=public,private as $$
declare v_id uuid;
begin
  insert into public.change_log(actor_user_id,actor_role,entity_type,entity_id,action,before_data,after_data)
  select auth.uid(),p.role,p_entity_type,p_entity_id,p_action,p_before,p_after
  from public.profiles p where p.id=auth.uid();
  if not found then
    insert into public.change_log(actor_user_id,actor_role,entity_type,entity_id,action,before_data,after_data)
    values(auth.uid(),null,p_entity_type,p_entity_id,p_action,p_before,p_after);
  end if;
  return (select id from public.change_log where entity_type=p_entity_type and entity_id=p_entity_id order by created_at desc limit 1);
end; $$;
revoke all on function public.final_log_change(text,uuid,text,jsonb,jsonb) from public,anon;
grant execute on function public.final_log_change(text,uuid,text,jsonb,jsonb) to authenticated;

-- ============================================================
-- 8. SERVICIOS PÚBLICOS POR ESPACIO
-- ============================================================
create or replace function public.get_public_space_services(p_space_id uuid)
returns table(id uuid,service_id uuid,name text,description text,included boolean,price numeric,active boolean)
language sql stable security definer set search_path=public,private as $$
  select ss.id,ss.service_id,sc.name,sc.description,ss.included,ss.price,ss.active
  from public.space_services ss join public.service_catalog sc on sc.id=ss.service_id
  where ss.space_id=p_space_id and ss.active=true and sc.active=true
  order by lower(sc.name);
$$;
revoke all on function public.get_public_space_services(uuid) from public,anon,authenticated;
grant execute on function public.get_public_space_services(uuid) to anon,authenticated;

-- ============================================================
-- 9. RESERVA: SNAPSHOT + RETENCIÓN 72H
-- ============================================================
create or replace function public.create_booking_request(
  p_space_id uuid,
  p_customer_name text,
  p_customer_email text,
  p_customer_phone text,
  p_start_date date,
  p_end_date date,
  p_cleaning_requested boolean default false,
  p_customer_notes text default null,
  p_selected_services jsonb default '[]'::jsonb
) returns uuid
language plpgsql security definer set search_path=public,private as $$
declare
  v_booking_id uuid;
  v_owner_id uuid;
  v_owner_email text;
  v_owner_name text;
  v_space_name text;
  v_city text;
  v_province text;
  v_address text;
  v_description text;
  v_opening time;
  v_closing time;
  v_conditions text;
  v_weekday numeric;
  v_friday numeric;
  v_saturday numeric;
  v_sunday numeric;
  v_deposit numeric;
  v_cleaning_available boolean;
  v_cleaning_price numeric;
  v_total_days integer := (p_end_date-p_start_date)+1;
  v_rental numeric := 0;
  v_cleaning numeric := 0;
  v_services_total numeric := 0;
  v_service_price numeric;
  v_service_id uuid;
  v_service_name text;
  v_services jsonb := '[]'::jsonb;
  v_requested jsonb;
  v_day date;
  v_expires timestamptz := now()+interval '72 hours';
  v_pricing jsonb;
  v_space_snapshot jsonb;
begin
  if p_space_id is null or p_start_date is null or p_end_date is null or p_end_date<p_start_date then
    raise exception 'Rango de fechas no válido';
  end if;
  if btrim(coalesce(p_customer_name,''))='' or btrim(coalesce(p_customer_email,''))='' or btrim(coalesce(p_customer_phone,''))='' then
    raise exception 'Nombre, email y teléfono son obligatorios';
  end if;
  if not public.final_space_is_public(p_space_id) then raise exception 'El espacio no está disponible'; end if;
  if exists(select 1 from public.bookings where space_id=p_space_id and booking_status in ('pending','confirmed') and start_date<=p_end_date and end_date>=p_start_date) then
    raise exception 'Alguna de las fechas seleccionadas no está disponible';
  end if;
  if exists(select 1 from public.blocked_dates where space_id=p_space_id and start_date<=p_end_date and end_date>=p_start_date) then
    raise exception 'Alguna de las fechas seleccionadas no está disponible';
  end if;

  select owner_id,name,city,province,address,description,opening_time,closing_time,conditions_text,
         weekday_price,friday_price,saturday_price,sunday_price,deposit,cleaning_available,cleaning_price
  into v_owner_id,v_space_name,v_city,v_province,v_address,v_description,v_opening,v_closing,v_conditions,
       v_weekday,v_friday,v_saturday,v_sunday,v_deposit,v_cleaning_available,v_cleaning_price
  from public.spaces where id=p_space_id for share;

  if p_cleaning_requested and not coalesce(v_cleaning_available,false) then
    raise exception 'El servicio de limpieza no está disponible';
  end if;

  for v_day in select generate_series(p_start_date,p_end_date,interval '1 day')::date loop
    v_rental := v_rental + coalesce(case extract(isodow from v_day)::integer
      when 5 then v_friday when 6 then v_saturday when 7 then v_sunday else v_weekday end,0);
  end loop;
  if p_cleaning_requested then v_cleaning:=coalesce(v_cleaning_price,0); end if;

  for v_requested in select value from jsonb_array_elements(coalesce(p_selected_services,'[]'::jsonb)) loop
    begin v_service_id := (v_requested->>'id')::uuid; exception when others then raise exception 'Servicio seleccionado no válido'; end;
    select sc.name,ss.price into v_service_name,v_service_price
    from public.space_services ss join public.service_catalog sc on sc.id=ss.service_id
    where ss.id=v_service_id and ss.space_id=p_space_id and ss.active=true and ss.included=false and sc.active=true;
    if not found then raise exception 'Uno de los servicios seleccionados ya no está disponible'; end if;
    v_services_total:=v_services_total+coalesce(v_service_price,0);
    v_services:=v_services||jsonb_build_array(jsonb_build_object('id',v_service_id,'name',v_service_name,'price',v_service_price));
  end loop;

  v_pricing:=jsonb_build_object(
    'rental_total',round(v_rental,2),
    'cleaning_total',round(v_cleaning,2),
    'services_total',round(v_services_total,2),
    'deposit',round(coalesce(v_deposit,0),2),
    'grand_total',round(v_rental+v_cleaning+v_services_total+coalesce(v_deposit,0),2)
  );
  v_space_snapshot:=jsonb_build_object(
    'name',v_space_name,'city',v_city,'province',v_province,'address',v_address,'description',v_description,
    'opening_time',v_opening,'closing_time',v_closing,'weekday_price',v_weekday,'friday_price',v_friday,
    'saturday_price',v_saturday,'sunday_price',v_sunday,'cleaning_available',v_cleaning_available,
    'cleaning_price',v_cleaning_price,'deposit',v_deposit
  );

  insert into public.bookings(customer_name,customer_email,customer_phone,space_id,start_date,end_date,total_days,cleaning_requested,customer_notes,booking_status,expires_at,pricing_snapshot,space_snapshot,conditions_snapshot,services_snapshot,created_at,updated_at)
  values(btrim(p_customer_name),lower(btrim(p_customer_email)),btrim(p_customer_phone),p_space_id,p_start_date,p_end_date,v_total_days,coalesce(p_cleaning_requested,false),nullif(btrim(p_customer_notes),''),'pending',v_expires,v_pricing,v_space_snapshot,v_conditions,v_services,now(),now())
  returning id into v_booking_id;

  select p.email,trim(coalesce(p.first_name,'')||' '||coalesce(p.last_name,''))
  into v_owner_email,v_owner_name
  from public.owners o join public.profiles p on p.id=o.profile_id where o.id=v_owner_id;

  perform public.final_queue_email('reservas','customer_request_received',lower(btrim(p_customer_email)),btrim(p_customer_name),jsonb_build_object('booking_id',v_booking_id,'customer_name',p_customer_name,'space_name',v_space_name,'start_date',p_start_date,'end_date',p_end_date),v_booking_id,p_space_id);
  perform public.final_queue_email('reservas','request_created',v_owner_email,v_owner_name,
    jsonb_build_object('booking_id',v_booking_id,'space_name',v_space_name,'customer_name',p_customer_name,'customer_email',lower(btrim(p_customer_email)),'customer_phone',p_customer_phone,'start_date',p_start_date,'end_date',p_end_date,'expires_at',v_expires,'pricing_snapshot',v_pricing,'services_snapshot',v_services),v_booking_id,p_space_id);
  perform public.final_queue_email('reservas','admin_request_created','miespacioparacelebrar@gmail.com','Administración',
    jsonb_build_object('booking_id',v_booking_id,'space_name',v_space_name,'customer_name',p_customer_name,'customer_email',lower(btrim(p_customer_email)),'customer_phone',p_customer_phone,'start_date',p_start_date,'end_date',p_end_date,'expires_at',v_expires),v_booking_id,p_space_id);
  return v_booking_id;
end; $$;
revoke all on function public.create_booking_request(uuid,text,text,text,date,date,boolean,text,jsonb) from public,anon,authenticated;
grant execute on function public.create_booking_request(uuid,text,text,text,date,date,boolean,text,jsonb) to anon,authenticated;

-- ============================================================
-- 10. FINALIZACIÓN / DECISIÓN DEL PROPIETARIO
-- ============================================================
create or replace function public.confirm_booking(p_booking_id uuid)
returns void language plpgsql security definer set search_path=public,private as $$
declare b public.bookings%rowtype; s public.spaces%rowtype; owner_email text; owner_name text;
begin
  if not private.is_owner() and not private.is_admin() then raise exception 'No tienes permisos'; end if;
  select * into b from public.bookings where id=p_booking_id for update;
  if not found then raise exception 'Solicitud no encontrada'; end if;
  select * into s from public.spaces where id=b.space_id;
  if private.is_owner() and s.owner_id<>private.current_owner_id() then raise exception 'No tienes permisos sobre esta reserva'; end if;
  if b.booking_status<>'pending' then raise exception 'La solicitud ya no está pendiente'; end if;
  if b.expires_at<now() then update public.bookings set booking_status='expired',finalized_at=now(),updated_at=now() where id=b.id; raise exception 'La solicitud ha caducado'; end if;
  if exists(select 1 from public.bookings x where x.id<>b.id and x.space_id=b.space_id and x.booking_status='confirmed' and x.start_date<=b.end_date and x.end_date>=b.start_date) or exists(select 1 from public.blocked_dates x where x.space_id=b.space_id and x.start_date<=b.end_date and x.end_date>=b.start_date) then raise exception 'Las fechas ya no están disponibles'; end if;
  update public.bookings set booking_status='confirmed',expires_at=null,finalized_at=now(),updated_at=now() where id=b.id;
  select p.email,trim(coalesce(p.first_name,'')||' '||coalesce(p.last_name,'')) into owner_email,owner_name from public.owners o join public.profiles p on p.id=o.profile_id where o.id=s.owner_id;
  perform public.final_queue_email('reservas','customer_confirmed',b.customer_email,b.customer_name,jsonb_build_object('booking_id',b.id,'space_name',s.name,'start_date',b.start_date,'end_date',b.end_date),b.id,b.space_id);
  perform public.final_queue_email('reservas','owner_booking_final','miespacioparacelebrar@gmail.com','Administración',jsonb_build_object('booking_id',b.id,'space_name',s.name,'customer_name',b.customer_name,'status','confirmed','comment','No se han añadido comentarios'),b.id,b.space_id);
end; $$;
revoke all on function public.confirm_booking(uuid) from public,anon; grant execute on function public.confirm_booking(uuid) to authenticated;

create or replace function public.reject_booking(p_booking_id uuid)
returns void language plpgsql security definer set search_path=public,private as $$
declare b public.bookings%rowtype; s public.spaces%rowtype;
begin
  if not private.is_owner() and not private.is_admin() then raise exception 'No tienes permisos'; end if;
  select * into b from public.bookings where id=p_booking_id for update;
  if not found then raise exception 'Solicitud no encontrada'; end if;
  select * into s from public.spaces where id=b.space_id;
  if private.is_owner() and s.owner_id<>private.current_owner_id() then raise exception 'No tienes permisos sobre esta reserva'; end if;
  if b.booking_status<>'pending' then raise exception 'La solicitud ya no está pendiente'; end if;
  update public.bookings set booking_status='rejected',expires_at=null,finalized_at=now(),updated_at=now() where id=b.id;
  perform public.final_queue_email('reservas','customer_not_processed',b.customer_email,b.customer_name,jsonb_build_object('booking_id',b.id,'space_name',s.name,'start_date',b.start_date,'end_date',b.end_date),b.id,b.space_id);
  perform public.final_queue_email('reservas','admin_booking_final','miespacioparacelebrar@gmail.com','Administración',jsonb_build_object('booking_id',b.id,'space_name',s.name,'customer_name',b.customer_name,'status','rejected','comment','No se han añadido comentarios'),b.id,b.space_id);
end; $$;
revoke all on function public.reject_booking(uuid) from public,anon; grant execute on function public.reject_booking(uuid) to authenticated;

create or replace function public.expire_pending_bookings()
returns integer language plpgsql security definer set search_path=public,private as $$
declare n integer:=0; b record; s public.spaces%rowtype;
begin
  for b in select * from public.bookings where booking_status='pending' and expires_at is not null and expires_at<now() for update loop
    select * into s from public.spaces where id=b.space_id;
    update public.bookings set booking_status='expired',finalized_at=now(),updated_at=now() where id=b.id;
    perform public.final_queue_email('reservas','customer_expired',b.customer_email,b.customer_name,jsonb_build_object('booking_id',b.id,'space_name',s.name,'start_date',b.start_date,'end_date',b.end_date),b.id,b.space_id);
    perform public.final_queue_email('reservas','admin_booking_final','miespacioparacelebrar@gmail.com','Administración',jsonb_build_object('booking_id',b.id,'space_name',s.name,'customer_name',b.customer_name,'status','expired','comment','No se han añadido comentarios'),b.id,b.space_id);
    n:=n+1;
  end loop;
  return n;
end; $$;
revoke all on function public.expire_pending_bookings() from public,anon,authenticated;
grant execute on function public.expire_pending_bookings() to service_role;

-- ============================================================
-- 11. DISPONIBILIDAD PÚBLICA
-- ============================================================
create or replace function public.get_space_unavailable_ranges(p_space_id uuid)
returns table(start_date date,end_date date,reason text)
language sql stable security definer set search_path=public,private as $$
  select b.start_date,b.end_date,case when b.booking_status='pending' then 'pending' else 'confirmed' end
  from public.bookings b where b.space_id=p_space_id and b.booking_status in ('pending','confirmed')
  union all
  select bd.start_date,bd.end_date,'blocked' from public.blocked_dates bd where bd.space_id=p_space_id
  order by 1;
$$;
revoke all on function public.get_space_unavailable_ranges(uuid) from public,anon,authenticated;
grant execute on function public.get_space_unavailable_ranges(uuid) to anon,authenticated;

-- ============================================================
-- 12. OWNER SPACES: estados definitivos
-- ============================================================
create or replace function public.get_owner_spaces()
returns table(id uuid,name text,city text,province text,active boolean,admin_enabled boolean,owner_active boolean,active_from date,active_until date)
language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_owner() then raise exception 'No tienes permisos de propietario'; end if;
  return query select s.id,s.name,s.city,s.province,s.active,s.admin_enabled,s.owner_active,s.active_from,s.active_until
  from public.spaces s where s.owner_id=private.current_owner_id() order by s.name;
end; $$;
revoke all on function public.get_owner_spaces() from public,anon; grant execute on function public.get_owner_spaces() to authenticated;

-- ============================================================
-- 13. OWNER ACTIVACIÓN
-- ============================================================
create or replace function public.owner_set_space_active(p_space_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public,private as $$
declare s public.spaces%rowtype;
begin
  if not private.is_owner() then raise exception 'No tienes permisos'; end if;
  select * into s from public.spaces where id=p_space_id;
  if not found or s.owner_id<>private.current_owner_id() then raise exception 'Espacio no asignado'; end if;
  if not s.admin_enabled then raise exception 'El espacio está deshabilitado por administración'; end if;
  update public.spaces set owner_active=p_active,active=p_active,updated_at=now() where id=p_space_id;
  perform public.final_log_change('space',p_space_id,case when p_active then 'owner_activate' else 'owner_deactivate' end,to_jsonb(s),(select to_jsonb(x) from public.spaces x where x.id=p_space_id));
end; $$;
revoke all on function public.owner_set_space_active(uuid,boolean) from public,anon; grant execute on function public.owner_set_space_active(uuid,boolean) to authenticated;

-- ============================================================
-- 14. ADMIN ACTIVACIÓN/DESHABILITACIÓN
-- ============================================================
create or replace function public.admin_set_space_state(p_space_id uuid,p_admin_enabled boolean,p_owner_active boolean default null)
returns void language plpgsql security definer set search_path=public,private as $$
declare s public.spaces%rowtype; new_owner_active boolean;
begin
  if not private.is_admin() then raise exception 'No tienes permisos'; end if;
  select * into s from public.spaces where id=p_space_id for update;
  if not found then raise exception 'Espacio no encontrado'; end if;
  -- Un disable administrativo deja el espacio inactivo. Al re-habilitarlo no se reactiva automáticamente.
  new_owner_active:=case when not p_admin_enabled then false else coalesce(p_owner_active,s.owner_active) end;
  update public.spaces set admin_enabled=p_admin_enabled,owner_active=new_owner_active,active=(p_admin_enabled and new_owner_active),updated_at=now() where id=p_space_id;
  perform public.final_log_change('space',p_space_id,case when p_admin_enabled then 'admin_enable' else 'admin_disable' end,to_jsonb(s),(select to_jsonb(x) from public.spaces x where x.id=p_space_id));
  perform public.final_queue_email('espacios',case when p_admin_enabled then 'space_enabled' else 'space_disabled' end,
    (select p.email from public.owners o join public.profiles p on p.id=o.profile_id where o.id=s.owner_id),
    (select trim(coalesce(p.first_name,'')||' '||coalesce(p.last_name,'')) from public.owners o join public.profiles p on p.id=o.profile_id where o.id=s.owner_id),
    jsonb_build_object('space_name',s.name,'admin_enabled',p_admin_enabled),null,p_space_id);
end; $$;
revoke all on function public.admin_set_space_state(uuid,boolean,boolean) from public,anon; grant execute on function public.admin_set_space_state(uuid,boolean,boolean) to authenticated;

-- ============================================================
-- 15. BLOQUEOS: propietario/admin sin solapes
-- ============================================================
create or replace function public.owner_create_blocked_date(p_space_id uuid,p_start_date date,p_end_date date,p_reason text default null)
returns uuid language plpgsql security definer set search_path=public,private as $$
declare v uuid;
begin
  if not private.is_owner() then raise exception 'No tienes permisos'; end if;
  if not exists(select 1 from public.spaces where id=p_space_id and owner_id=private.current_owner_id()) then raise exception 'Espacio no asignado'; end if;
  if p_start_date is null or p_end_date<p_start_date then raise exception 'Rango no válido'; end if;
  if exists(select 1 from public.bookings where space_id=p_space_id and booking_status in ('pending','confirmed') and start_date<=p_end_date and end_date>=p_start_date) then raise exception 'No puedes bloquear fechas con reservas pendientes o confirmadas'; end if;
  insert into public.blocked_dates(space_id,owner_id,start_date,end_date,reason) select id,owner_id,p_start_date,p_end_date,nullif(btrim(p_reason),'') from public.spaces where id=p_space_id returning id into v;
  return v;
end; $$;
revoke all on function public.owner_create_blocked_date(uuid,date,date,text) from public,anon; grant execute on function public.owner_create_blocked_date(uuid,date,date,text) to authenticated;

-- ============================================================
-- 16. LIMPIEZA AUTOMÁTICA DE DATOS
-- ============================================================
create or replace function public.cleanup_old_reservation_data()
returns integer language plpgsql security definer set search_path=public,private as $$
declare n integer;
begin
  delete from public.bookings where
    (booking_status='confirmed' and end_date < current_date - 30) or
    (booking_status in ('rejected','expired','cancelled') and created_at < now() - interval '7 days');
  get diagnostics n = row_count;
  return n;
end; $$;
revoke all on function public.cleanup_old_reservation_data() from public,anon,authenticated;
grant execute on function public.cleanup_old_reservation_data() to service_role;

-- ============================================================
-- 17. SURVEY: TOKEN Y ENVÍO
-- ============================================================
create or replace function public.create_survey_for_booking(p_booking_id uuid)
returns uuid language plpgsql security definer set search_path=public,private as $$
declare v_id uuid; v_token text; b public.bookings%rowtype; s public.spaces%rowtype;
begin
  select * into b from public.bookings where id=p_booking_id and booking_status='confirmed';
  if not found or b.end_date<>current_date-1 then return null; end if;
  if exists(select 1 from public.surveys where booking_id=p_booking_id) then return (select id from public.surveys where booking_id=p_booking_id); end if;
  select * into s from public.spaces where id=b.space_id;
  v_token:=encode(gen_random_bytes(24),'hex');
  insert into public.surveys(booking_id,token_hash) values(b.id,encode(digest(v_token,'sha256'),'hex')) returning id into v_id;
  perform public.final_queue_email('encuestas','survey_created',b.customer_email,b.customer_name,jsonb_build_object('survey_id',v_id,'token',v_token,'space_name',s.name,'end_date',b.end_date),b.id,b.space_id);
  return v_id;
end; $$;
revoke all on function public.create_survey_for_booking(uuid) from public,anon,authenticated;
grant execute on function public.create_survey_for_booking(uuid) to service_role;

-- ============================================================
-- 18. CRON (si pg_cron está disponible en el proyecto)
-- ============================================================
do $$ begin
  if exists(select 1 from pg_extension where extname='pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname in ('miespacio-expire-bookings','miespacio-cleanup');
    perform cron.schedule('miespacio-expire-bookings','*/15 * * * *',$cron$select public.expire_pending_bookings();$cron$);
    perform cron.schedule('miespacio-cleanup','20 3 * * *',$cron$select public.cleanup_old_reservation_data();$cron$);
  end if;
exception when others then null;
end $$;

-- ============================================================
-- 19. LA NUBE
-- ============================================================
update public.spaces
set latitude=37.417400,longitude=-4.485511,
    admin_enabled=true,
    owner_active=coalesce(owner_active,active,true)
where id='340c371d-e09b-4a59-bfaa-343d7509a35c';


-- ============================================================
-- 20. COMPATIBILIDAD CON EL PANEL ADMINISTRADOR V27
-- ============================================================
create or replace function public.admin_set_space_active(p_space_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos'; end if;
  perform public.admin_set_space_state(p_space_id,p_active,null);
end; $$;
revoke all on function public.admin_set_space_active(uuid,boolean) from public,anon;
grant execute on function public.admin_set_space_active(uuid,boolean) to authenticated;

create or replace function public.admin_update_space(
 p_space_id uuid,p_owner_id uuid,p_name text,p_city text default null,p_province text default null,p_description text default null,
 p_weekday_price numeric default 0,p_friday_price numeric default 0,p_saturday_price numeric default 0,p_sunday_price numeric default 0,
 p_opening_time time default '11:00',p_closing_time time default '23:00',p_cancellation_policy text default null,
 p_cleaning_available boolean default false,p_cleaning_price numeric default 0,p_payment_information text default null,
 p_active boolean default true,p_latitude numeric default null,p_longitude numeric default null,p_deposit numeric default 0,
 p_active_from date default null,p_active_until date default null
) returns void language plpgsql security definer set search_path=public,private as $$
declare s public.spaces%rowtype; new_admin boolean; new_owner boolean;
begin
  if not private.is_admin() then raise exception 'No tienes permisos'; end if;
  select * into s from public.spaces where id=p_space_id for update;
  if not found then raise exception 'Espacio no encontrado'; end if;
  if not exists(select 1 from public.owners where id=p_owner_id and active=true) then raise exception 'Propietario no válido o inactivo'; end if;
  new_admin:=coalesce(p_active,true);
  new_owner:=case when not new_admin then false else s.owner_active end;
  update public.spaces set owner_id=p_owner_id,name=btrim(p_name),city=p_city,province=p_province,description=p_description,
    weekday_price=p_weekday_price,friday_price=p_friday_price,saturday_price=p_saturday_price,sunday_price=p_sunday_price,
    opening_time=p_opening_time,closing_time=p_closing_time,cancellation_policy=p_cancellation_policy,
    cleaning_available=coalesce(p_cleaning_available,false),cleaning_price=coalesce(p_cleaning_price,0),payment_information=p_payment_information,
    active=new_admin and new_owner,admin_enabled=new_admin,owner_active=new_owner,latitude=p_latitude,longitude=p_longitude,deposit=p_deposit,
    active_from=p_active_from,active_until=p_active_until,updated_at=now() where id=p_space_id;
  perform public.final_log_change('space',p_space_id,'admin_update',to_jsonb(s),(select to_jsonb(x) from public.spaces x where x.id=p_space_id));
end; $$;
revoke all on function public.admin_update_space(uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,time,time,text,boolean,numeric,text,boolean,numeric,numeric,numeric,date,date) from public,anon;
grant execute on function public.admin_update_space(uuid,uuid,text,text,text,text,numeric,numeric,numeric,numeric,time,time,text,boolean,numeric,text,boolean,numeric,numeric,numeric,date,date) to authenticated;

-- Sobrecarga compatible con el creador de espacios del panel actual.
create or replace function public.admin_create_space(
 p_owner_id uuid,p_name text,p_city text default null,p_province text default null,p_description text default null,
 p_weekday_price numeric default 0,p_friday_price numeric default 0,p_saturday_price numeric default 0,p_sunday_price numeric default 0,
 p_opening_time time default '11:00',p_closing_time time default '23:00',p_cancellation_policy text default null,
 p_cleaning_available boolean default false,p_cleaning_price numeric default 0,p_payment_information text default null,
 p_active boolean default true,p_latitude numeric default null,p_longitude numeric default null,p_deposit numeric default 0,
 p_active_from date default null,p_active_until date default null
) returns uuid language plpgsql security definer set search_path=public,private as $$
declare v_id uuid;
begin
  if not private.is_admin() then raise exception 'No tienes permisos'; end if;
  if not exists(select 1 from public.owners where id=p_owner_id and active=true) then raise exception 'Propietario no válido o inactivo'; end if;
  insert into public.spaces(owner_id,name,city,province,description,weekday_price,friday_price,saturday_price,sunday_price,opening_time,closing_time,cancellation_policy,cleaning_available,cleaning_price,payment_information,active,admin_enabled,owner_active,latitude,longitude,deposit,active_from,active_until)
  values(p_owner_id,btrim(p_name),p_city,p_province,p_description,p_weekday_price,p_friday_price,p_saturday_price,p_sunday_price,p_opening_time,p_closing_time,p_cancellation_policy,coalesce(p_cleaning_available,false),coalesce(p_cleaning_price,0),p_payment_information,coalesce(p_active,true),coalesce(p_active,true),coalesce(p_active,true),p_latitude,p_longitude,p_deposit,p_active_from,p_active_until)
  returning id into v_id;
  perform public.final_log_change('space',v_id,'admin_create',null,(select to_jsonb(x) from public.spaces x where x.id=v_id));
  return v_id;
end; $$;
revoke all on function public.admin_create_space(uuid,text,text,text,text,numeric,numeric,numeric,numeric,time,time,text,boolean,numeric,text,boolean,numeric,numeric,numeric,date,date) from public,anon;
grant execute on function public.admin_create_space(uuid,text,text,text,text,numeric,numeric,numeric,numeric,time,time,text,boolean,numeric,text,boolean,numeric,numeric,numeric,date,date) to authenticated;

-- Owner: edición de su configuración operativa.
create or replace function public.owner_update_space(
 p_space_id uuid,p_weekday_price numeric,p_friday_price numeric,p_saturday_price numeric,p_sunday_price numeric,
 p_opening_time time,p_closing_time time,p_cleaning_available boolean,p_cleaning_price numeric,p_deposit numeric,p_conditions text
) returns void language plpgsql security definer set search_path=public,private as $$
declare s public.spaces%rowtype;
begin
  if not private.is_owner() then raise exception 'No tienes permisos'; end if;
  select * into s from public.spaces where id=p_space_id and owner_id=private.current_owner_id() for update;
  if not found then raise exception 'Espacio no asignado'; end if;
  update public.spaces set weekday_price=p_weekday_price,friday_price=p_friday_price,saturday_price=p_saturday_price,sunday_price=p_sunday_price,
    opening_time=p_opening_time,closing_time=p_closing_time,cleaning_available=p_cleaning_available,cleaning_price=p_cleaning_price,
    deposit=p_deposit,conditions_text=p_conditions,updated_at=now() where id=p_space_id;
  perform public.final_log_change('space',p_space_id,'owner_update',to_jsonb(s),(select to_jsonb(x) from public.spaces x where x.id=p_space_id));
end; $$;
revoke all on function public.owner_update_space(uuid,numeric,numeric,numeric,numeric,time,time,boolean,numeric,numeric,text) from public,anon;
grant execute on function public.owner_update_space(uuid,numeric,numeric,numeric,numeric,time,time,boolean,numeric,numeric,text) to authenticated;

-- Owner booking query: pricing siempre sale del snapshot, no de los precios actuales.
create or replace function public.get_owner_bookings()
returns table(id uuid,space_id uuid,space_name text,customer_name text,customer_email text,customer_phone text,start_date date,end_date date,total_days integer,cleaning_requested boolean,booking_status text,expires_at timestamptz,created_at timestamptz,rental_total numeric,cleaning_total numeric,deposit numeric,grand_total numeric,services_snapshot jsonb,customer_notes text,conditions_snapshot text)
language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_owner() then raise exception 'No tienes permisos de propietario'; end if;
  return query
  select b.id,b.space_id,s.name,b.customer_name,b.customer_email,b.customer_phone,b.start_date,b.end_date,b.total_days,b.cleaning_requested,b.booking_status,b.expires_at,b.created_at,
    coalesce((b.pricing_snapshot->>'rental_total')::numeric,0),coalesce((b.pricing_snapshot->>'cleaning_total')::numeric,0),coalesce((b.pricing_snapshot->>'deposit')::numeric,0),coalesce((b.pricing_snapshot->>'grand_total')::numeric,0),b.services_snapshot,b.customer_notes,b.conditions_snapshot
  from public.bookings b
  join public.spaces s on s.id=b.space_id
  where s.owner_id=private.current_owner_id()
    and b.end_date >= current_date
  order by b.start_date asc, b.end_date asc, b.created_at asc;
end; $$;
revoke all on function public.get_owner_bookings() from public,anon; grant execute on function public.get_owner_bookings() to authenticated;

-- ============================================================
-- 21. ENCUESTA: ENLACE DE UN SOLO USO
-- ============================================================
create or replace function public.submit_survey(
 p_token text,p_overall integer,p_facilities integer default null,p_cleaning integer default null,p_equipment integer default null,p_maintenance integer default null,
 p_improvements text default null,p_breakdown boolean default false,p_breakdown_details text default null,p_missing_items text default null,p_would_use_again boolean default null,p_comments text default null
) returns void language plpgsql security definer set search_path=public,private as $$
declare v_id uuid;
begin
  if nullif(btrim(coalesce(p_token,'')),'') is null then raise exception 'Enlace no válido'; end if;
  select id into v_id from public.surveys where token_hash=encode(digest(p_token,'sha256'),'hex') and completed_at is null;
  if not found then raise exception 'La encuesta ya ha sido completada o el enlace no es válido'; end if;
  update public.surveys set overall=p_overall,facilities=p_facilities,cleaning=p_cleaning,equipment=p_equipment,maintenance=p_maintenance,
    improvements=nullif(btrim(p_improvements),''),breakdown=coalesce(p_breakdown,false),breakdown_details=nullif(btrim(p_breakdown_details),''),
    missing_items=nullif(btrim(p_missing_items),''),would_use_again=p_would_use_again,comments=nullif(btrim(p_comments),''),completed_at=now() where id=v_id;
end; $$;
revoke all on function public.submit_survey(text,integer,integer,integer,integer,integer,text,boolean,text,text,boolean,text) from public,anon,authenticated;
grant execute on function public.submit_survey(text,integer,integer,integer,integer,integer,text,boolean,text,text,boolean,text) to anon;

-- ============================================================
-- 22. FUNCIÓN DE RESERVA PARA CAMBIOS FUTUROS / REAPERTURA
-- ============================================================
create or replace function public.owner_cancel_booking(p_booking_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,private as $$
declare b public.bookings%rowtype; s public.spaces%rowtype;
begin
  if not private.is_owner() then raise exception 'No tienes permisos'; end if;
  if nullif(btrim(coalesce(p_reason,'')),'') is null then raise exception 'El motivo es obligatorio'; end if;
  select * into b from public.bookings where id=p_booking_id for update;
  select * into s from public.spaces where id=b.space_id;
  if s.owner_id<>private.current_owner_id() then raise exception 'No tienes permisos sobre esta reserva'; end if;
  if b.booking_status<>'confirmed' then raise exception 'Solo se pueden cancelar reservas confirmadas'; end if;
  update public.bookings set booking_status='cancelled',cancelled_reason=btrim(p_reason),finalized_at=now(),updated_at=now() where id=b.id;
  perform public.final_queue_email('reservas','customer_cancelled',b.customer_email,b.customer_name,jsonb_build_object('booking_id',b.id,'space_name',s.name,'start_date',b.start_date,'end_date',b.end_date,'reason',btrim(p_reason)),b.id,b.space_id);
  perform public.final_queue_email('reservas','owner_booking_final','miespacioparacelebrar@gmail.com','Administración',jsonb_build_object('booking_id',b.id,'space_name',s.name,'customer_name',b.customer_name,'status','cancelled','comment',btrim(p_reason)),b.id,b.space_id);
end; $$;
revoke all on function public.owner_cancel_booking(uuid,text) from public,anon; grant execute on function public.owner_cancel_booking(uuid,text) to authenticated;

-- ============================================================
-- 23. ADMINISTRACIÓN DE SERVICIOS
-- ============================================================
create or replace function public.admin_get_service_catalog()
returns table(id uuid,name text,description text,active boolean)
language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos'; end if;
  return query select sc.id,sc.name,sc.description,sc.active from public.service_catalog sc order by lower(sc.name);
end; $$;
revoke all on function public.admin_get_service_catalog() from public,anon; grant execute on function public.admin_get_service_catalog() to authenticated;

create or replace function public.admin_save_space_service(p_space_id uuid,p_service_id uuid,p_included boolean,p_price numeric,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,private as $$
declare v uuid;
begin
  if not private.is_admin() then raise exception 'No tienes permisos'; end if;
  if not exists(select 1 from public.spaces where id=p_space_id) then raise exception 'Espacio no encontrado'; end if;
  if not exists(select 1 from public.service_catalog where id=p_service_id) then raise exception 'Servicio no encontrado'; end if;
  insert into public.space_services(space_id,service_id,included,price,active)
  values(p_space_id,p_service_id,coalesce(p_included,false),case when p_included then null else p_price end,coalesce(p_active,true))
  on conflict(space_id,service_id) do update set included=excluded.included,price=excluded.price,active=excluded.active,updated_at=now()
  returning id into v;
  return v;
end; $$;
revoke all on function public.admin_save_space_service(uuid,uuid,boolean,numeric,boolean) from public,anon; grant execute on function public.admin_save_space_service(uuid,uuid,boolean,numeric,boolean) to authenticated;

create or replace function public.admin_remove_space_service(p_space_service_id uuid)
returns void language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos'; end if;
  delete from public.space_services where id=p_space_service_id;
end; $$;
revoke all on function public.admin_remove_space_service(uuid) from public,anon; grant execute on function public.admin_remove_space_service(uuid) to authenticated;

-- ============================================================
-- 24. DETALLE DEL ESPACIO PARA EL PROPIETARIO
-- ============================================================
create or replace function public.get_owner_space_detail(p_space_id uuid)
returns table(id uuid,name text,weekday_price numeric,friday_price numeric,saturday_price numeric,sunday_price numeric,opening_time time,closing_time time,cleaning_available boolean,cleaning_price numeric,deposit numeric,conditions_text text,admin_enabled boolean,owner_active boolean,active_from date,active_until date)
language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_owner() then raise exception 'No tienes permisos'; end if;
  return query select s.id,s.name,s.weekday_price,s.friday_price,s.saturday_price,s.sunday_price,s.opening_time,s.closing_time,s.cleaning_available,s.cleaning_price,s.deposit,s.conditions_text,s.admin_enabled,s.owner_active,s.active_from,s.active_until
  from public.spaces s where s.id=p_space_id and s.owner_id=private.current_owner_id();
end; $$;
revoke all on function public.get_owner_space_detail(uuid) from public,anon; grant execute on function public.get_owner_space_detail(uuid) to authenticated;

-- ============================================================
-- 25. MODIFICACIÓN DE RESERVAS CONFIRMADAS POR EL PROPIETARIO
-- ============================================================
create or replace function public.owner_update_booking(
 p_booking_id uuid,p_start_date date,p_end_date date,p_cleaning_requested boolean,p_selected_services jsonb default '[]'::jsonb,p_customer_notes text default null
) returns void language plpgsql security definer set search_path=public,private as $$
declare
 b public.bookings%rowtype; s public.spaces%rowtype; x jsonb; sid uuid; sname text; sprice numeric; services jsonb:='[]'::jsonb; service_total numeric:=0;
 week numeric; fri numeric; sat numeric; sun numeric; dep numeric; ca boolean; cp numeric; rental numeric:=0; clean numeric:=0; d date; owner_email text; owner_name text;
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
 select weekday_price,friday_price,saturday_price,sunday_price,deposit,cleaning_available,cleaning_price into week,fri,sat,sun,dep,ca,cp from public.spaces where id=s.id;
 if p_cleaning_requested and not ca then raise exception 'El servicio de limpieza no está disponible'; end if;
 for d in select generate_series(p_start_date,p_end_date,interval '1 day')::date loop rental:=rental+coalesce(case extract(isodow from d)::int when 5 then fri when 6 then sat when 7 then sun else week end,0); end loop;
 if p_cleaning_requested then clean:=coalesce(cp,0); end if;
 for x in select value from jsonb_array_elements(coalesce(p_selected_services,'[]'::jsonb)) loop
   sid:=(x->>'id')::uuid;
   select sc.name,ss.price into sname,sprice from public.space_services ss join public.service_catalog sc on sc.id=ss.service_id where ss.id=sid and ss.space_id=s.id and ss.active=true and ss.included=false and sc.active=true;
   if not found then raise exception 'Uno de los servicios seleccionados ya no está disponible'; end if;
   service_total:=service_total+coalesce(sprice,0); services:=services||jsonb_build_array(jsonb_build_object('id',sid,'name',sname,'price',sprice));
 end loop;
 update public.bookings set start_date=p_start_date,end_date=p_end_date,total_days=(p_end_date-p_start_date)+1,cleaning_requested=coalesce(p_cleaning_requested,false),customer_notes=nullif(btrim(p_customer_notes),''),pricing_snapshot=jsonb_build_object('rental_total',round(rental,2),'cleaning_total',round(clean,2),'services_total',round(service_total,2),'deposit',round(coalesce(dep,0),2),'grand_total',round(rental+clean+service_total+coalesce(dep,0),2)),services_snapshot=services,updated_at=now() where id=b.id;
 perform public.final_queue_email('reservas','customer_updated',b.customer_email,b.customer_name,jsonb_build_object('booking_id',b.id,'space_name',s.name,'start_date',p_start_date,'end_date',p_end_date),b.id,s.id);
 perform public.final_queue_email('reservas','owner_booking_final','miespacioparacelebrar@gmail.com','Administración',jsonb_build_object('booking_id',b.id,'space_name',s.name,'customer_name',b.customer_name,'status','updated','comment','Reserva modificada por el propietario'),b.id,s.id);
end; $$;
revoke all on function public.owner_update_booking(uuid,date,date,boolean,jsonb,text) from public,anon; grant execute on function public.owner_update_booking(uuid,date,date,boolean,jsonb,text) to authenticated;

-- ============================================================
-- 26. VISTAS ADMIN: EMAILS Y ENCUESTAS
-- ============================================================
create or replace function public.admin_get_email_history(p_category text default null)
returns table(id uuid,category text,communication_type text,booking_id uuid,space_id uuid,recipient_email text,recipient_name text,status text,attempts integer,sent_at timestamptz,last_error text,created_at timestamptz)
language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos'; end if;
  return query select e.id,e.category,e.communication_type,e.booking_id,e.space_id,e.recipient_email,e.recipient_name,e.status,e.attempts,e.sent_at,e.last_error,e.created_at from public.email_queue e where p_category is null or e.category=p_category order by e.created_at desc limit 300;
end; $$;
revoke all on function public.admin_get_email_history(text) from public,anon; grant execute on function public.admin_get_email_history(text) to authenticated;

create or replace function public.admin_get_surveys()
returns table(id uuid,booking_id uuid,space_name text,customer_name text,overall integer,facilities integer,cleaning integer,equipment integer,maintenance integer,breakdown boolean,improvements text,missing_items text,would_use_again boolean,comments text,completed_at timestamptz)
language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos'; end if;
  return query select sv.id,sv.booking_id,s.name,b.customer_name,sv.overall,sv.facilities,sv.cleaning,sv.equipment,sv.maintenance,sv.breakdown,sv.improvements,sv.missing_items,sv.would_use_again,sv.comments,sv.completed_at
  from public.surveys sv join public.bookings b on b.id=sv.booking_id join public.spaces s on s.id=b.space_id order by sv.created_at desc;
end; $$;
revoke all on function public.admin_get_surveys() from public,anon; grant execute on function public.admin_get_surveys() to authenticated;

-- ============================================================
-- 27. RPCs UTILIZADAS POR EL PANEL ADMINISTRADOR FINAL
-- ============================================================
create or replace function public.admin_get_spaces()
returns setof public.spaces language sql security definer set search_path=public,private as $$ select s.* from public.spaces s where private.is_admin() order by s.name; $$;
revoke all on function public.admin_get_spaces() from public,anon; grant execute on function public.admin_get_spaces() to authenticated;

create or replace function public.admin_get_owners()
returns table(id uuid,profile_id uuid,email text,first_name text,last_name text,phone text,address text,city text,postal_code text,legal_name text,tax_id text,active boolean)
language plpgsql security definer set search_path=public,private as $$
begin if not private.is_admin() then raise exception 'No tienes permisos'; end if; return query select o.id,o.profile_id,p.email,p.first_name,p.last_name,p.phone,p.address,p.city,p.postal_code,o.legal_name,o.tax_id,o.active from public.owners o join public.profiles p on p.id=o.profile_id order by p.last_name,p.first_name,p.email; end; $$;
revoke all on function public.admin_get_owners() from public,anon; grant execute on function public.admin_get_owners() to authenticated;

create or replace function public.admin_get_bookings()
returns table(id uuid,space_id uuid,space_name text,owner_name text,customer_name text,customer_email text,customer_phone text,start_date date,end_date date,total_days integer,cleaning_requested boolean,booking_status text,expires_at timestamptz,created_at timestamptz)
language plpgsql security definer set search_path=public,private as $$
begin if not private.is_admin() then raise exception 'No tienes permisos'; end if; return query select b.id,b.space_id,s.name,trim(coalesce(p.first_name,'')||' '||coalesce(p.last_name,'')),b.customer_name,b.customer_email,b.customer_phone,b.start_date,b.end_date,b.total_days,b.cleaning_requested,b.booking_status,b.expires_at,b.created_at from public.bookings b join public.spaces s on s.id=b.space_id join public.owners o on o.id=s.owner_id join public.profiles p on p.id=o.profile_id order by b.created_at desc; end; $$;
revoke all on function public.admin_get_bookings() from public,anon; grant execute on function public.admin_get_bookings() to authenticated;

create or replace function public.admin_get_space_images(p_space_id uuid)
returns table(id uuid,image_url text,alt_text text,is_main boolean,sort_order integer) language plpgsql security definer set search_path=public,private as $$
begin if not private.is_admin() then raise exception 'No tienes permisos'; end if; return query select i.id,i.image_url,coalesce(i.alt_text,s.name),coalesce(i.is_main,false),coalesce(i.sort_order,0) from public.space_images i join public.spaces s on s.id=i.space_id where i.space_id=p_space_id order by i.is_main desc,i.sort_order,i.created_at; end; $$;
revoke all on function public.admin_get_space_images(uuid) from public,anon; grant execute on function public.admin_get_space_images(uuid) to authenticated;

create or replace function public.admin_add_space_image(p_space_id uuid,p_image_url text,p_alt_text text default null,p_is_main boolean default false,p_sort_order integer default 0)
returns uuid language plpgsql security definer set search_path=public,private as $$ declare v uuid; begin if not private.is_admin() then raise exception 'No tienes permisos'; end if; if p_is_main then update public.space_images set is_main=false where space_id=p_space_id; end if; insert into public.space_images(space_id,image_url,alt_text,is_main,sort_order) values(p_space_id,p_image_url,p_alt_text,p_is_main,p_sort_order) returning id into v; return v; end; $$;
revoke all on function public.admin_add_space_image(uuid,text,text,boolean,integer) from public,anon; grant execute on function public.admin_add_space_image(uuid,text,text,boolean,integer) to authenticated;

create or replace function public.admin_update_space_image(p_image_id uuid,p_image_url text,p_alt_text text,p_is_main boolean,p_sort_order integer)
returns void language plpgsql security definer set search_path=public,private as $$ declare sid uuid; begin if not private.is_admin() then raise exception 'No tienes permisos'; end if; select space_id into sid from public.space_images where id=p_image_id; if p_is_main then update public.space_images set is_main=false where space_id=sid; end if; update public.space_images set image_url=p_image_url,alt_text=p_alt_text,is_main=p_is_main,sort_order=p_sort_order where id=p_image_id; end; $$;
revoke all on function public.admin_update_space_image(uuid,text,text,boolean,integer) from public,anon; grant execute on function public.admin_update_space_image(uuid,text,text,boolean,integer) to authenticated;

create or replace function public.admin_delete_space_image(p_image_id uuid)
returns void language plpgsql security definer set search_path=public,private as $$ begin if not private.is_admin() then raise exception 'No tienes permisos'; end if; delete from public.space_images where id=p_image_id; end; $$;
revoke all on function public.admin_delete_space_image(uuid) from public,anon; grant execute on function public.admin_delete_space_image(uuid) to authenticated;

create or replace function public.admin_get_space_features(p_space_id uuid)
returns table(id uuid,feature text,sort_order integer) language plpgsql security definer set search_path=public,private as $$ begin if not private.is_admin() then raise exception 'No tienes permisos'; end if; return query select f.id,f.feature,f.sort_order from public.space_features f where f.space_id=p_space_id order by lower(f.feature); end; $$;
revoke all on function public.admin_get_space_features(uuid) from public,anon; grant execute on function public.admin_get_space_features(uuid) to authenticated;

create or replace function public.admin_add_space_feature(p_space_id uuid,p_feature text,p_sort_order integer default 0)
returns uuid language plpgsql security definer set search_path=public,private as $$ declare v uuid; begin if not private.is_admin() then raise exception 'No tienes permisos'; end if; insert into public.space_features(space_id,feature,sort_order) values(p_space_id,btrim(p_feature),p_sort_order) returning id into v; return v; end; $$;
revoke all on function public.admin_add_space_feature(uuid,text,integer) from public,anon; grant execute on function public.admin_add_space_feature(uuid,text,integer) to authenticated;

create or replace function public.admin_update_space_feature(p_feature_id uuid,p_feature text,p_sort_order integer)
returns void language plpgsql security definer set search_path=public,private as $$ begin if not private.is_admin() then raise exception 'No tienes permisos'; end if; update public.space_features set feature=btrim(p_feature),sort_order=p_sort_order where id=p_feature_id; end; $$;
revoke all on function public.admin_update_space_feature(uuid,text,integer) from public,anon; grant execute on function public.admin_update_space_feature(uuid,text,integer) to authenticated;

create or replace function public.admin_delete_space_feature(p_feature_id uuid)
returns void language plpgsql security definer set search_path=public,private as $$ begin if not private.is_admin() then raise exception 'No tienes permisos'; end if; delete from public.space_features where id=p_feature_id; end; $$;
revoke all on function public.admin_delete_space_feature(uuid) from public,anon; grant execute on function public.admin_delete_space_feature(uuid) to authenticated;

create or replace function public.admin_get_blocked_dates(p_space_id uuid)
returns table(id uuid,space_id uuid,start_date date,end_date date,reason text,created_at timestamptz) language plpgsql security definer set search_path=public,private as $$ begin if not private.is_admin() then raise exception 'No tienes permisos'; end if; return query select b.id,b.space_id,b.start_date,b.end_date,b.reason,b.created_at from public.blocked_dates b where b.space_id=p_space_id order by b.start_date; end; $$;
revoke all on function public.admin_get_blocked_dates(uuid) from public,anon; grant execute on function public.admin_get_blocked_dates(uuid) to authenticated;

create or replace function public.admin_create_blocked_date(p_space_id uuid,p_start_date date,p_end_date date,p_reason text default null)
returns uuid language plpgsql security definer set search_path=public,private as $$ declare v uuid; begin if not private.is_admin() then raise exception 'No tienes permisos'; end if; if p_end_date<p_start_date then raise exception 'Rango no válido'; end if; if exists(select 1 from public.bookings where space_id=p_space_id and booking_status in ('pending','confirmed') and start_date<=p_end_date and end_date>=p_start_date) then raise exception 'El periodo coincide con una reserva'; end if; insert into public.blocked_dates(space_id,owner_id,start_date,end_date,reason) select id,owner_id,p_start_date,p_end_date,nullif(btrim(p_reason),'') from public.spaces where id=p_space_id returning id into v; return v; end; $$;
revoke all on function public.admin_create_blocked_date(uuid,date,date,text) from public,anon; grant execute on function public.admin_create_blocked_date(uuid,date,date,text) to authenticated;

create or replace function public.admin_delete_blocked_date(p_blocked_id uuid)
returns void language plpgsql security definer set search_path=public,private as $$ begin if not private.is_admin() then raise exception 'No tienes permisos'; end if; delete from public.blocked_dates where id=p_blocked_id; end; $$;
revoke all on function public.admin_delete_blocked_date(uuid) from public,anon; grant execute on function public.admin_delete_blocked_date(uuid) to authenticated;

create or replace function public.admin_get_space_bookings(p_space_id uuid)
returns table(id uuid,start_date date,end_date date,customer_name text,cleaning_requested boolean,booking_status text)
language plpgsql security definer set search_path=public,private as $$ begin if not private.is_admin() then raise exception 'No tienes permisos'; end if; return query select b.id,b.start_date,b.end_date,b.customer_name,b.cleaning_requested,b.booking_status from public.bookings b where b.space_id=p_space_id order by b.start_date; end; $$;
revoke all on function public.admin_get_space_bookings(uuid) from public,anon; grant execute on function public.admin_get_space_bookings(uuid) to authenticated;

-- Compatibilidad de galería para gestión avanzada de fotografías.
alter table public.space_images
  add column if not exists alt_text text,
  add column if not exists is_main boolean not null default false,
  add column if not exists created_at timestamptz not null default now();
update public.space_images i set is_main=true where i.sort_order=(select min(x.sort_order) from public.space_images x where x.space_id=i.space_id) and not exists(select 1 from public.space_images y where y.space_id=i.space_id and y.is_main=true);

-- ============================================================
-- 28. REENVÍO SEGURO DE LA ÚLTIMA COMUNICACIÓN AL CLIENTE
-- ============================================================
create or replace function public.owner_resend_customer_email(p_booking_id uuid)
returns uuid language plpgsql security definer set search_path=public,private as $$
declare b public.bookings%rowtype; s public.spaces%rowtype; q record; v_type text; v_id uuid;
begin
  if not private.is_owner() then raise exception 'No tienes permisos'; end if;
  select * into b from public.bookings where id=p_booking_id;
  select * into s from public.spaces where id=b.space_id;
  if s.owner_id<>private.current_owner_id() then raise exception 'No tienes permisos sobre esta reserva'; end if;
  select communication_type,payload into q from public.email_queue where booking_id=b.id and communication_type like 'customer_%' order by created_at desc limit 1;
  if not found then raise exception 'No existe una comunicación de cliente para reenviar'; end if;
  v_type:=q.communication_type;
  insert into public.email_queue(category,communication_type,booking_id,space_id,recipient_email,recipient_name,payload)
  values('reservas',v_type,b.id,b.space_id,b.customer_email,b.customer_name,q.payload)
  returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.owner_resend_customer_email(uuid) from public,anon; grant execute on function public.owner_resend_customer_email(uuid) to authenticated;

create or replace function public.owner_update_customer_email(p_booking_id uuid,p_customer_email text)
returns void language plpgsql security definer set search_path=public,private as $$
declare b public.bookings%rowtype; s public.spaces%rowtype; owner_email text; owner_name text;
begin
  if not private.is_owner() then raise exception 'No tienes permisos'; end if;
  if nullif(btrim(p_customer_email),'') is null then raise exception 'El email es obligatorio'; end if;
  select * into b from public.bookings where id=p_booking_id;
  if not found then raise exception 'Reserva no encontrada'; end if;
  select * into s from public.spaces where id=b.space_id;
  if s.owner_id<>private.current_owner_id() then raise exception 'No tienes permisos sobre esta reserva'; end if;
  update public.bookings set customer_email=lower(btrim(p_customer_email)),updated_at=now(),customer_email_delivery_status='pending' where id=b.id;
  select p.email,trim(coalesce(p.first_name,'')||' '||coalesce(p.last_name,'')) into owner_email,owner_name from public.owners o join public.profiles p on p.id=o.profile_id where o.id=s.owner_id;
  perform public.final_queue_email('reservas','owner_email_changed',owner_email,owner_name,jsonb_build_object('booking_id',b.id,'space_name',s.name,'customer_name',b.customer_name,'customer_email',lower(btrim(p_customer_email)),'start_date',b.start_date,'end_date',b.end_date),b.id,b.space_id);
  perform public.final_queue_email('reservas','admin_owner_email_changed','miespacioparacelebrar@gmail.com','Administración',jsonb_build_object('booking_id',b.id,'space_name',s.name,'customer_name',b.customer_name,'customer_email',lower(btrim(p_customer_email)),'start_date',b.start_date,'end_date',b.end_date),b.id,b.space_id);
end; $$;
revoke all on function public.owner_update_customer_email(uuid,text) from public,anon; grant execute on function public.owner_update_customer_email(uuid,text) to authenticated;


-- ============================================================
-- 29. RECORDATORIO AL PROPIETARIO DE SOLICITUDES PENDIENTES
-- ============================================================
create or replace function public.queue_pending_owner_reminders()
returns integer language plpgsql security definer set search_path=public,private as $$
declare r record; n integer:=0; owner_email text; owner_name text;
begin
  for r in select b.id,b.space_id,b.customer_name,b.customer_email,b.customer_phone,b.start_date,b.end_date,b.expires_at,s.name,s.owner_id from public.bookings b join public.spaces s on s.id=b.space_id where b.booking_status='pending' and b.expires_at>now() and b.expires_at<=now()+interval '12 hours' and not exists(select 1 from public.email_queue e where e.booking_id=b.id and e.communication_type='owner_pending_reminder' and e.created_at>now()-interval '12 hours') loop
    select p.email,trim(coalesce(p.first_name,'')||' '||coalesce(p.last_name,'')) into owner_email,owner_name from public.owners o join public.profiles p on p.id=o.profile_id where o.id=r.owner_id;
    perform public.final_queue_email('reservas','owner_pending_reminder',owner_email,owner_name,jsonb_build_object('booking_id',r.id,'space_name',r.name,'customer_name',r.customer_name,'customer_email',r.customer_email,'customer_phone',r.customer_phone,'start_date',r.start_date,'end_date',r.end_date,'expires_at',r.expires_at),r.id,r.space_id); n:=n+1;
  end loop; return n;
end; $$;
revoke all on function public.queue_pending_owner_reminders() from public,anon,authenticated; grant execute on function public.queue_pending_owner_reminders() to service_role;

do $$ begin
  if exists(select 1 from pg_extension where extname='pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname='miespacio-owner-reminders';
    perform cron.schedule('miespacio-owner-reminders','0 * * * *',$cron$select public.queue_pending_owner_reminders();$cron$);
  end if;
exception when others then null;
end $$;

-- FIN FINAL-2026

-- ============================================================
-- 30. CADUCIDAD AUTOMÁTICA DE ESPACIOS
-- ============================================================
create or replace function public.expire_space_validity()
returns integer language plpgsql security definer set search_path=public,private as $$
declare n integer;
begin
  update public.spaces set admin_enabled=false,owner_active=false,active=false,updated_at=now() where active_until is not null and active_until<current_date and (admin_enabled=true or owner_active=true or active=true);
  get diagnostics n=row_count; return n;
end; $$;
revoke all on function public.expire_space_validity() from public,anon,authenticated; grant execute on function public.expire_space_validity() to service_role;

do $$ begin
  if exists(select 1 from pg_extension where extname='pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname='miespacio-expire-spaces';
    perform cron.schedule('miespacio-expire-spaces','10 2 * * *',$cron$select public.expire_space_validity();$cron$);
  end if;
exception when others then null;
end $$;

-- FIN FINAL-2026

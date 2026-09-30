-- HISTÓRICO: para v22 utilizar supabase/v22-final.sql como actualización consolidada.
-- MiEspacioParaCelebrar — gestión básica de propietarios y locales desde Administración
-- ▶️ SOLO EJECUTAR en Supabase SQL Editor. No es necesario guardarlo aparte.

create or replace function public.admin_list_owners()
returns table (
  owner_id uuid,
  profile_id uuid,
  email text,
  first_name text,
  last_name text,
  phone text,
  legal_name text,
  tax_id text,
  active boolean
)
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
  return query
  select o.id,p.id,p.email,p.first_name,p.last_name,p.phone,o.legal_name,o.tax_id,o.active
  from public.owners o join public.profiles p on p.id=o.profile_id
  order by p.last_name nulls last,p.first_name nulls last,p.email;
end;
$$;
revoke all on function public.admin_list_owners() from public, anon;
grant execute on function public.admin_list_owners() to authenticated;

create or replace function public.admin_create_space(
  p_owner_id uuid,
  p_name text,
  p_city text default null,
  p_province text default null,
  p_description text default null,
  p_weekday_price numeric default null,
  p_friday_price numeric default null,
  p_saturday_price numeric default null,
  p_sunday_price numeric default null,
  p_deposit numeric default null,
  p_opening_time time default null,
  p_closing_time time default null,
  p_cleaning_available boolean default false,
  p_cleaning_price numeric default 0,
  p_cancellation_policy text default null,
  p_address text default null,
  p_latitude numeric default null,
  p_longitude numeric default null,
  p_active boolean default true,
  p_active_from date default null,
  p_active_until date default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare v_id uuid;
begin
  if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
  if p_owner_id is null or not exists(select 1 from public.owners where id=p_owner_id and active=true) then
    raise exception 'Propietario no válido o inactivo';
  end if;
  if p_name is null or btrim(p_name)='' then raise exception 'El nombre del espacio es obligatorio'; end if;
  if p_active_until is not null and p_active_from is not null and p_active_until < p_active_from then
    raise exception 'La fecha de fin no puede ser anterior a la fecha de inicio';
  end if;
  insert into public.spaces(owner_id,name,city,province,description,weekday_price,friday_price,saturday_price,sunday_price,deposit,opening_time,closing_time,cleaning_available,cleaning_price,cancellation_policy,address,latitude,longitude,active,active_from,active_until)
  values(p_owner_id,btrim(p_name),p_city,p_province,p_description,p_weekday_price,p_friday_price,p_saturday_price,p_sunday_price,p_deposit,p_opening_time,p_closing_time,coalesce(p_cleaning_available,false),coalesce(p_cleaning_price,0),p_cancellation_policy,p_address,p_latitude,p_longitude,coalesce(p_active,true),p_active_from,p_active_until)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.admin_create_space(uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,time,time,boolean,numeric,text,text,numeric,numeric,boolean,date,date) from public, anon;
grant execute on function public.admin_create_space(uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,time,time,boolean,numeric,text,text,numeric,numeric,boolean,date,date) to authenticated;

create or replace function public.admin_get_all_bookings()
returns table (
  id uuid, space_id uuid, space_name text, owner_name text, customer_name text, customer_email text,
  customer_phone text, start_date date, end_date date, total_days integer, cleaning_requested boolean,
  booking_status text, expires_at timestamptz, created_at timestamptz
)
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
  update public.bookings set booking_status='expired'
  where booking_status='pending' and expires_at is not null and expires_at < now();
  return query
  select b.id,b.space_id,s.name,
    trim(coalesce(p.first_name,'')||' '||coalesce(p.last_name,'')),b.customer_name,b.customer_email,b.customer_phone,
    b.start_date,b.end_date,b.total_days,b.cleaning_requested,b.booking_status,b.expires_at,b.created_at
  from public.bookings b
  join public.spaces s on s.id=b.space_id
  join public.owners o on o.id=s.owner_id
  join public.profiles p on p.id=o.profile_id
  order by b.created_at desc;
end;
$$;
revoke all on function public.admin_get_all_bookings() from public, anon;
grant execute on function public.admin_get_all_bookings() to authenticated;

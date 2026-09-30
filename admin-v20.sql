-- HISTÓRICO: para v22 utilizar supabase/v22-final.sql como actualización consolidada.
-- MiEspacioParaCelebrar v20 — funciones de administración avanzada
-- 🗂️ GUARDAR — Administración avanzada v20
-- ▶️ SOLO EJECUTAR en Supabase SQL Editor.
-- Este archivo amplía el panel de administración sin sustituir las funciones existentes.

create or replace function public.admin_update_space_full(
  p_space_id uuid,
  p_owner_id uuid default null,
  p_active boolean,
  p_active_from date default null,
  p_active_until date default null,
  p_name text default null,
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
  p_payment_information text default null,
  p_address text default null,
  p_latitude numeric default null,
  p_longitude numeric default null
)
returns void
language plpgsql security definer
set search_path = public, private
as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
  if p_owner_id is not null and not exists(select 1 from public.owners where id=p_owner_id and active=true) then raise exception 'Propietario no válido o inactivo'; end if;
  if p_name is null or btrim(p_name)='' then raise exception 'El nombre del espacio es obligatorio'; end if;
  if p_active_until is not null and p_active_from is not null and p_active_until < p_active_from then
    raise exception 'La fecha de fin no puede ser anterior a la fecha de inicio';
  end if;
  update public.spaces set
    owner_id=coalesce(p_owner_id,owner_id),
    active=p_active, active_from=p_active_from, active_until=p_active_until,
    name=btrim(p_name), city=p_city, province=p_province, description=p_description,
    weekday_price=p_weekday_price, friday_price=p_friday_price,
    saturday_price=p_saturday_price, sunday_price=p_sunday_price,
    deposit=p_deposit, opening_time=p_opening_time, closing_time=p_closing_time,
    cleaning_available=coalesce(p_cleaning_available,false), cleaning_price=coalesce(p_cleaning_price,0),
    cancellation_policy=p_cancellation_policy, payment_information=p_payment_information,
    address=p_address, latitude=p_latitude, longitude=p_longitude, updated_at=now()
  where id=p_space_id;
  if not found then raise exception 'Espacio no encontrado'; end if;
end; $$;
revoke all on function public.admin_update_space_full(uuid,uuid,boolean,date,date,text,text,text,text,numeric,numeric,numeric,numeric,numeric,time,time,boolean,numeric,text,text,text,numeric,numeric) from public,anon;
grant execute on function public.admin_update_space_full(uuid,uuid,boolean,date,date,text,text,text,text,numeric,numeric,numeric,numeric,numeric,time,time,boolean,numeric,text,text,text,numeric,numeric) to authenticated;

create or replace function public.admin_replace_space_features(p_space_id uuid, p_features text[])
returns void language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
  delete from public.space_features where space_id=p_space_id;
  insert into public.space_features(space_id,feature,sort_order)
  select p_space_id,btrim(x),row_number() over() - 1 from unnest(coalesce(p_features,ARRAY[]::text[])) x where btrim(x)<>'';
end; $$;
revoke all on function public.admin_replace_space_features(uuid,text[]) from public,anon;
grant execute on function public.admin_replace_space_features(uuid,text[]) to authenticated;

create or replace function public.admin_replace_space_images(p_space_id uuid, p_images text[])
returns void language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
  delete from public.space_images where space_id=p_space_id;
  insert into public.space_images(space_id,image_url,sort_order)
  select p_space_id,btrim(x),row_number() over() - 1 from unnest(coalesce(p_images,ARRAY[]::text[])) x where btrim(x)<>'';
end; $$;
revoke all on function public.admin_replace_space_images(uuid,text[]) from public,anon;
grant execute on function public.admin_replace_space_images(uuid,text[]) to authenticated;

create or replace function public.admin_list_blocked_dates(p_space_id uuid default null)
returns table(id uuid,space_id uuid,space_name text,start_date date,end_date date,reason text,created_at timestamptz)
language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
  return query select b.id,b.space_id,s.name,b.start_date,b.end_date,b.reason,b.created_at
  from public.blocked_dates b join public.spaces s on s.id=b.space_id
  where p_space_id is null or b.space_id=p_space_id order by b.start_date,s.name;
end; $$;
revoke all on function public.admin_list_blocked_dates(uuid) from public,anon;
grant execute on function public.admin_list_blocked_dates(uuid) to authenticated;

create or replace function public.admin_block_dates(p_space_id uuid,p_start_date date,p_end_date date,p_reason text default null)
returns uuid language plpgsql security definer set search_path=public,private as $$
declare v_id uuid;
begin
  if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
  if p_start_date is null or p_end_date is null or p_end_date<p_start_date then raise exception 'Rango de fechas no válido'; end if;
  if not exists(select 1 from public.spaces where id=p_space_id) then raise exception 'Espacio no encontrado'; end if;
  if exists(select 1 from public.bookings where space_id=p_space_id and booking_status in ('pending','confirmed') and start_date<=p_end_date and end_date>=p_start_date) then
    raise exception 'El periodo coincide con una reserva pendiente o confirmada';
  end if;
  insert into public.blocked_dates(space_id,owner_id,start_date,end_date,reason)
  select p_space_id,s.owner_id,p_start_date,p_end_date,coalesce(nullif(btrim(p_reason),''),'Bloqueado por administración')
  from public.spaces s where s.id=p_space_id returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.admin_block_dates(uuid,date,date,text) from public,anon;
grant execute on function public.admin_block_dates(uuid,date,date,text) to authenticated;

create or replace function public.admin_unblock_dates(p_blocked_id uuid)
returns void language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
  delete from public.blocked_dates where id=p_blocked_id;
  if not found then raise exception 'Bloqueo no encontrado'; end if;
end; $$;
revoke all on function public.admin_unblock_dates(uuid) from public,anon;
grant execute on function public.admin_unblock_dates(uuid) to authenticated;

-- Almacenamiento público de fotografías de espacios. Las operaciones de escritura quedan limitadas al administrador.
insert into storage.buckets(id,name,public)
values('space-images','space-images',true)
on conflict (id) do update set public=true;

drop policy if exists "Admin upload space images" on storage.objects;
create policy "Admin upload space images" on storage.objects for insert to authenticated
with check (bucket_id='space-images' and public.private.is_admin());
drop policy if exists "Admin delete space images" on storage.objects;
create policy "Admin delete space images" on storage.objects for delete to authenticated
using (bucket_id='space-images' and public.private.is_admin());

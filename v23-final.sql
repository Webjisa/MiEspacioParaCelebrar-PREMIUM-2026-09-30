-- MiEspacioParaCelebrar v23 — SQL FINAL DE ACTUALIZACIÓN
-- 🗂️ GUARDAR — v23-final.sql
-- ▶️ SOLO EJECUTAR una vez en Supabase SQL Editor.
-- No sustituye el historial: consolida las piezas necesarias para el panel admin v22.

-- 1) Campos necesarios para ubicación y vigencia
alter table public.spaces
  add column if not exists address text,
  add column if not exists latitude numeric(9,6),
  add column if not exists longitude numeric(9,6),
  add column if not exists active_from date,
  add column if not exists active_until date;

create index if not exists spaces_active_until_idx on public.spaces(active_until);
create index if not exists spaces_public_active_idx on public.spaces(active, active_until);

-- 2) Visibilidad pública: solo activos y no caducados
drop policy if exists "Public can view active spaces" on public.spaces;
create policy "Public can view active spaces" on public.spaces
for select to anon, authenticated
using (active = true and (active_until is null or active_until >= current_date));

-- 3) Lectura/gestión segura de características e imágenes por administrador
drop policy if exists "Admins can manage space features" on public.space_features;
create policy "Admins can manage space features" on public.space_features
for all to authenticated using (public.private.is_admin()) with check (public.private.is_admin());

drop policy if exists "Public can view active space features" on public.space_features;
create policy "Public can view active space features" on public.space_features
for select to anon, authenticated
using (exists(select 1 from public.spaces s where s.id=space_features.space_id and s.active=true and (s.active_until is null or s.active_until >= current_date)));

drop policy if exists "Admins can manage space images" on public.space_images;
create policy "Admins can manage space images" on public.space_images
for all to authenticated using (public.private.is_admin()) with check (public.private.is_admin());

drop policy if exists "Public can view active space images" on public.space_images;
create policy "Public can view active space images" on public.space_images
for select to anon, authenticated
using (exists(select 1 from public.spaces s where s.id=space_images.space_id and s.active=true and (s.active_until is null or s.active_until >= current_date)));

-- 4) Bucket de fotografías
insert into storage.buckets(id,name,public) values('space-images','space-images',true)
on conflict (id) do update set public=true;

drop policy if exists "Admin upload space images" on storage.objects;
create policy "Admin upload space images" on storage.objects for insert to authenticated
with check (bucket_id='space-images' and public.private.is_admin());

drop policy if exists "Admin delete space images" on storage.objects;
create policy "Admin delete space images" on storage.objects for delete to authenticated
using (bucket_id='space-images' and public.private.is_admin());

-- 5) Propietarios
create or replace function public.admin_list_owners()
returns table(owner_id uuid, profile_id uuid, email text, first_name text, last_name text, phone text, legal_name text, tax_id text, active boolean)
language plpgsql security definer set search_path=public,private as $$
begin
  if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
  return query select o.id,p.id,p.email,p.first_name,p.last_name,p.phone,o.legal_name,o.tax_id,o.active
  from public.owners o join public.profiles p on p.id=o.profile_id
  order by p.last_name nulls last,p.first_name nulls last,p.email;
end; $$;
revoke all on function public.admin_list_owners() from public,anon;
grant execute on function public.admin_list_owners() to authenticated;

-- 6) Crear espacio desde el panel
create or replace function public.admin_create_space(
 p_owner_id uuid,p_name text,p_city text default null,p_province text default null,p_description text default null,
 p_weekday_price numeric default null,p_friday_price numeric default null,p_saturday_price numeric default null,p_sunday_price numeric default null,
 p_deposit numeric default null,p_opening_time time default null,p_closing_time time default null,p_cleaning_available boolean default false,p_cleaning_price numeric default 0,
 p_cancellation_policy text default null,p_address text default null,p_latitude numeric default null,p_longitude numeric default null,p_active boolean default true,p_active_from date default null,p_active_until date default null)
returns uuid language plpgsql security definer set search_path=public,private as $$
declare v_id uuid;
begin
 if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
 if p_owner_id is null or not exists(select 1 from public.owners where id=p_owner_id and active=true) then raise exception 'Propietario no válido o inactivo'; end if;
 if p_name is null or btrim(p_name)='' then raise exception 'El nombre del espacio es obligatorio'; end if;
 if p_active_until is not null and p_active_from is not null and p_active_until < p_active_from then raise exception 'La fecha de fin no puede ser anterior a la fecha de inicio'; end if;
 insert into public.spaces(owner_id,name,city,province,description,weekday_price,friday_price,saturday_price,sunday_price,deposit,opening_time,closing_time,cleaning_available,cleaning_price,cancellation_policy,payment_information,address,latitude,longitude,active,active_from,active_until)
 values(p_owner_id,btrim(p_name),p_city,p_province,p_description,p_weekday_price,p_friday_price,p_saturday_price,p_sunday_price,p_deposit,p_opening_time,p_closing_time,coalesce(p_cleaning_available,false),coalesce(p_cleaning_price,0),p_cancellation_policy,null,p_address,p_latitude,p_longitude,coalesce(p_active,true),p_active_from,p_active_until)
 returning id into v_id; return v_id;
end; $$;
revoke all on function public.admin_create_space(uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,time,time,boolean,numeric,text,text,numeric,numeric,boolean,date,date) from public,anon;
grant execute on function public.admin_create_space(uuid,text,text,text,text,numeric,numeric,numeric,numeric,numeric,time,time,boolean,numeric,text,text,numeric,numeric,boolean,date,date) to authenticated;

-- 7) Edición completa del espacio
create or replace function public.admin_update_space_full(
 p_space_id uuid,p_owner_id uuid,p_active boolean,p_active_from date default null,p_active_until date default null,p_name text default null,p_city text default null,p_province text default null,p_description text default null,
 p_weekday_price numeric default null,p_friday_price numeric default null,p_saturday_price numeric default null,p_sunday_price numeric default null,p_deposit numeric default null,p_opening_time time default null,p_closing_time time default null,
 p_cleaning_available boolean default false,p_cleaning_price numeric default 0,p_cancellation_policy text default null,p_payment_information text default null,p_address text default null,p_latitude numeric default null,p_longitude numeric default null)
returns void language plpgsql security definer set search_path=public,private as $$
begin
 if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
 if p_owner_id is not null and not exists(select 1 from public.owners where id=p_owner_id and active=true) then raise exception 'Propietario no válido o inactivo'; end if;
 if p_name is null or btrim(p_name)='' then raise exception 'El nombre del espacio es obligatorio'; end if;
 if p_active_until is not null and p_active_from is not null and p_active_until < p_active_from then raise exception 'La fecha de fin no puede ser anterior a la fecha de inicio'; end if;
 update public.spaces set owner_id=coalesce(p_owner_id,owner_id),active=p_active,active_from=p_active_from,active_until=p_active_until,name=btrim(p_name),city=p_city,province=p_province,description=p_description,weekday_price=p_weekday_price,friday_price=p_friday_price,saturday_price=p_saturday_price,sunday_price=p_sunday_price,deposit=p_deposit,opening_time=p_opening_time,closing_time=p_closing_time,cleaning_available=coalesce(p_cleaning_available,false),cleaning_price=coalesce(p_cleaning_price,0),cancellation_policy=p_cancellation_policy,payment_information=p_payment_information,address=p_address,latitude=p_latitude,longitude=p_longitude,updated_at=now() where id=p_space_id;
 if not found then raise exception 'Espacio no encontrado'; end if;
end; $$;
revoke all on function public.admin_update_space_full(uuid,uuid,boolean,date,date,text,text,text,text,numeric,numeric,numeric,numeric,numeric,time,time,boolean,numeric,text,text,text,numeric,numeric) from public,anon;
grant execute on function public.admin_update_space_full(uuid,uuid,boolean,date,date,text,text,text,text,numeric,numeric,numeric,numeric,numeric,time,time,boolean,numeric,text,text,text,numeric,numeric) to authenticated;

-- 8) Características y galería
create or replace function public.admin_replace_space_features(p_space_id uuid,p_features text[]) returns void language plpgsql security definer set search_path=public,private as $$
begin
 if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
 delete from public.space_features where space_id=p_space_id;
 insert into public.space_features(space_id,feature,sort_order) select p_space_id,btrim(x),row_number() over()-1 from unnest(coalesce(p_features,ARRAY[]::text[])) x where btrim(x)<>'';
end; $$;
revoke all on function public.admin_replace_space_features(uuid,text[]) from public,anon; grant execute on function public.admin_replace_space_features(uuid,text[]) to authenticated;

create or replace function public.admin_replace_space_images(p_space_id uuid,p_images text[]) returns void language plpgsql security definer set search_path=public,private as $$
begin
 if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
 delete from public.space_images where space_id=p_space_id;
 insert into public.space_images(space_id,image_url,sort_order) select p_space_id,btrim(x),row_number() over()-1 from unnest(coalesce(p_images,ARRAY[]::text[])) x where btrim(x)<>'';
end; $$;
revoke all on function public.admin_replace_space_images(uuid,text[]) from public,anon; grant execute on function public.admin_replace_space_images(uuid,text[]) to authenticated;

-- 9) Fechas bloqueadas
create or replace function public.admin_list_blocked_dates(p_space_id uuid default null)
returns table(id uuid,space_id uuid,space_name text,start_date date,end_date date,reason text,created_at timestamptz) language plpgsql security definer set search_path=public,private as $$
begin
 if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
 return query select b.id,b.space_id,s.name,b.start_date,b.end_date,b.reason,b.created_at from public.blocked_dates b join public.spaces s on s.id=b.space_id where p_space_id is null or b.space_id=p_space_id order by b.start_date,s.name;
end; $$;
revoke all on function public.admin_list_blocked_dates(uuid) from public,anon; grant execute on function public.admin_list_blocked_dates(uuid) to authenticated;

create or replace function public.admin_block_dates(p_space_id uuid,p_start_date date,p_end_date date,p_reason text default null)
returns uuid language plpgsql security definer set search_path=public,private as $$
declare v_id uuid;
begin
 if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
 if p_start_date is null or p_end_date is null or p_end_date<p_start_date then raise exception 'Rango de fechas no válido'; end if;
 if not exists(select 1 from public.spaces where id=p_space_id) then raise exception 'Espacio no encontrado'; end if;
 if exists(select 1 from public.bookings where space_id=p_space_id and booking_status in ('pending','confirmed') and start_date<=p_end_date and end_date>=p_start_date) then raise exception 'El periodo coincide con una reserva pendiente o confirmada'; end if;
 insert into public.blocked_dates(space_id,owner_id,start_date,end_date,reason) select p_space_id,s.owner_id,p_start_date,p_end_date,coalesce(nullif(btrim(p_reason),''),'Bloqueado por administración') from public.spaces s where s.id=p_space_id returning id into v_id; return v_id;
end; $$;
revoke all on function public.admin_block_dates(uuid,date,date,text) from public,anon; grant execute on function public.admin_block_dates(uuid,date,date,text) to authenticated;

create or replace function public.admin_unblock_dates(p_blocked_id uuid) returns void language plpgsql security definer set search_path=public,private as $$
begin
 if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
 delete from public.blocked_dates where id=p_blocked_id; if not found then raise exception 'Bloqueo no encontrado'; end if;
end; $$;
revoke all on function public.admin_unblock_dates(uuid) from public,anon; grant execute on function public.admin_unblock_dates(uuid) to authenticated;

-- 10) Todas las reservas para el administrador
create or replace function public.admin_get_all_bookings()
returns table(id uuid,space_id uuid,space_name text,owner_name text,customer_name text,customer_email text,customer_phone text,start_date date,end_date date,total_days integer,cleaning_requested boolean,booking_status text,expires_at timestamptz,created_at timestamptz)
language plpgsql security definer set search_path=public,private as $$
begin
 if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
 update public.bookings set booking_status='expired' where booking_status='pending' and expires_at is not null and expires_at<now();
 return query select b.id,b.space_id,s.name,trim(coalesce(p.first_name,'')||' '||coalesce(p.last_name,'')),b.customer_name,b.customer_email,b.customer_phone,b.start_date,b.end_date,b.total_days,b.cleaning_requested,b.booking_status,b.expires_at,b.created_at from public.bookings b join public.spaces s on s.id=b.space_id join public.owners o on o.id=s.owner_id join public.profiles p on p.id=o.profile_id order by b.created_at desc;
end; $$;
revoke all on function public.admin_get_all_bookings() from public,anon; grant execute on function public.admin_get_all_bookings() to authenticated;

-- 11) La Nube
update public.spaces set latitude=37.417400,longitude=-4.485511 where name='La Nube' and city='Lucena';

-- 12) Eliminar físicamente una fotografía del bucket desde el panel admin
-- ▶️ Incluido en este SQL final; no requiere ejecución separada.
create or replace function public.admin_remove_space_image(p_image_id uuid)
returns text language plpgsql security definer set search_path=public,private as $$
declare v_url text;
begin
  if not private.is_admin() then raise exception 'No tienes permisos de administrador'; end if;
  select image_url into v_url from public.space_images where id=p_image_id;
  if v_url is null then raise exception 'Fotografía no encontrada'; end if;
  delete from public.space_images where id=p_image_id;
  return v_url;
end; $$;
revoke all on function public.admin_remove_space_image(uuid) from public,anon;
grant execute on function public.admin_remove_space_image(uuid) to authenticated;

-- FIN v23

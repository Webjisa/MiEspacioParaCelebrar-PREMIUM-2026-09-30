-- HISTÓRICO: para v22 utilizar supabase/v22-final.sql como actualización consolidada.
-- MiEspacioParaCelebrar — solicitudes en área privada
-- 🗂️ GUARDAR — Owner bookings + pricing v2
-- ▶️ SOLO EJECUTAR en Supabase SQL Editor.

create or replace function public.get_owner_bookings()
returns table (
  id uuid,
  space_id uuid,
  space_name text,
  customer_name text,
  customer_email text,
  customer_phone text,
  start_date date,
  end_date date,
  total_days integer,
  cleaning_requested boolean,
  booking_status text,
  expires_at timestamptz,
  created_at timestamptz,
  rental_total numeric,
  cleaning_total numeric,
  deposit numeric,
  grand_total numeric
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
  select
    b.id,
    b.space_id,
    s.name,
    b.customer_name,
    b.customer_email,
    b.customer_phone,
    b.start_date,
    b.end_date,
    b.total_days,
    b.cleaning_requested,
    b.booking_status,
    b.expires_at,
    b.created_at,
    pricing.rental_total,
    pricing.cleaning_total,
    pricing.deposit,
    pricing.grand_total
  from public.bookings b
  inner join public.spaces s on s.id = b.space_id
  cross join lateral public.get_booking_pricing(
    b.space_id,
    b.start_date,
    b.end_date,
    b.cleaning_requested
  ) pricing
  where s.owner_id = private.current_owner_id()
  order by b.created_at desc;
end;
$$;

revoke all on function public.get_owner_bookings() from public, anon;
grant execute on function public.get_owner_bookings() to authenticated;

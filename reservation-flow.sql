-- HISTÓRICO: para v22 utilizar supabase/v22-final.sql como actualización consolidada.
-- MiEspacioParaCelebrar — reserva: comprobación de la función existente
-- 🗂️ GUARDAR — Reservation flow verification
-- ▶️ SOLO EJECUTAR en Supabase SQL Editor.
-- Esta consulta NO modifica nada. Sirve para verificar qué función de reserva existe antes de tocarla.

select
  n.nspname as esquema,
  p.oid::regprocedure as funcion,
  pg_get_function_result(p.oid) as devuelve,
  pg_get_functiondef(p.oid) as definicion
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_booking_request','check_space_availability','confirm_booking','reject_booking','expire_pending_bookings')
order by p.proname, p.oid::regprocedure::text;

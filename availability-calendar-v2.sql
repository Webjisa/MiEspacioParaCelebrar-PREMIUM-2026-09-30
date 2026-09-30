-- HISTÓRICO: para v22 utilizar supabase/v22-final.sql como actualización consolidada.
-- MiEspacioParaCelebrar
-- 🗂️ GUARDAR — Availability calendar v2
-- Devuelve únicamente rangos de fechas no disponibles.
-- No expone datos del cliente ni datos económicos de reservas.

create or replace function public.get_space_unavailable_ranges(
    p_space_id uuid
)
returns table (
    start_date date,
    end_date date,
    reason text
)
language plpgsql
security definer
set search_path to ''
as $function$
begin

    if p_space_id is null then
        return;
    end if;

    if not exists (
        select 1
        from public.spaces s
        where s.id = p_space_id
          and s.active = true
          and (s.active_from is null or s.active_from <= current_date)
          and (s.active_until is null or s.active_until >= current_date)
    ) then
        return;
    end if;

    return query
    select
        bd.start_date,
        bd.end_date,
        'blocked'::text
    from public.blocked_dates bd
    where bd.space_id = p_space_id

    union all

    select
        b.start_date,
        b.end_date,
        case
            when b.booking_status = 'confirmed' then 'confirmed'
            else 'pending'
        end::text
    from public.bookings b
    where b.space_id = p_space_id
      and (
          b.booking_status = 'confirmed'
          or (
              b.booking_status = 'pending'
              and b.expires_at is not null
              and b.expires_at > now()
          )
      )

    order by 1, 2;

end;
$function$;

revoke all on function public.get_space_unavailable_ranges(uuid)
from public, anon, authenticated;

grant execute on function public.get_space_unavailable_ranges(uuid)
to anon, authenticated;

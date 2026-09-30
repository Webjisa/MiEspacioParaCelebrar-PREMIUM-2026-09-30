-- HISTÓRICO: para v22 utilizar supabase/v22-final.sql como actualización consolidada.
-- 🗂️ NO GUARDAR / ▶️ SOLO EJECUTAR
-- Ubicación exacta facilitada para La Nube.
-- Coordenadas: 37.417400, -4.485511

UPDATE public.spaces
SET
  latitude = 37.417400,
  longitude = -4.485511
WHERE name = 'La Nube'
  AND city = 'Lucena';

-- Comprobación
SELECT id, name, city, latitude, longitude
FROM public.spaces
WHERE name = 'La Nube'
  AND city = 'Lucena';

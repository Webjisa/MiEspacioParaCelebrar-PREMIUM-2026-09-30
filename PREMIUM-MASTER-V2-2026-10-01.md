# MiEspacioParaCelebrar — PREMIUM MASTER V2 — 2026-10-01

## Dirección visual fijada

- Logo oficial único: `assets/logo-miespacio-oficial.png`.
- Cabecera común en todas las páginas públicas y privadas.
- Área privada en cápsula negra.
- Menú hamburguesa minimalista con el mismo tratamiento visual.
- Estética editorial contemporánea, blanca, limpia y fotográfica.
- Sistema común de botones, campos, tarjetas, iconos, calendarios, modales, estados y responsive.

## Selector de fechas

- Tarjeta blanca flotante.
- Bordes redondeados y sombra suave.
- Entrada, salida y personas.
- Calendario compacto flotante.
- Apertura/cierre al pulsar.
- Sin desplazamiento del contenido.
- Misma estética en portada y ficha.
- La lógica real de disponibilidad/reserva continúa en `app.js` y `disponibilidad.js`.

## Características

- Iconografía lineal homogénea.
- Círculos de fondo crema.
- Datos derivados del espacio.
- Tratamiento especial para La Nube con sus características conocidas cuando sea necesario como fallback.

## La Nube

La portada y la ficha priorizan La Nube cuando está disponible y utilizan sus fotografías dinámicas desde Supabase. Como fallback visual local se conservan fotografías existentes del proyecto para evitar una pantalla vacía si Supabase no responde.

## Backend

No se ejecuta ninguna migración SQL automáticamente.

`supabase/PREMIUM-MASTER-MIGRATION-2026-10-01.sql` sigue siendo una migración separada y debe revisarse/ejecutarse manualmente cuando se decida activar sus funciones.

## Integridad

- No se modifican GitHub ni Supabase desde esta versión.
- No se reemplaza la lógica de reservas existente.
- `admin.js` y la gestión de fotografías existentes se conservan.
- El rediseño se aplica mediante `premium-master.js` y `premium-master.css` y ajustes de cabeceras/logotipo.

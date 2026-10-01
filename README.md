# MiEspacioParaCelebrar — versión definitiva 2026

Portal web para consultar espacios privados de celebración y enviar solicitudes de reserva a sus propietarios.

## Arquitectura

- Frontend estático: GitHub Pages.
- Datos, autenticación, RLS y RPC: Supabase.
- Correo transaccional: Resend mediante Edge Functions.
- Mapas: Leaflet/OpenStreetMap.
- Clientes: sin cuenta.
- Propietarios y administración: acceso privado.
- Pagos: fuera de la plataforma; cliente y propietario acuerdan directamente las condiciones económicas.

## Funcionalidades principales

- Búsqueda por fecha.
- Listado de todos los espacios públicos activos.
- Ficha individual con fotos, características, servicios, precios, condiciones, mapa y disponibilidad.
- Solicitudes de reserva con retención de 72 horas.
- Revisión final antes de enviar la solicitud.
- Snapshot de precios, servicios y condiciones en el momento de solicitar.
- Área privada de propietarios.
- Activación/desactivación operativa por propietario.
- Administración de propietarios y espacios.
- Administración de fotografías y características.
- Catálogo de servicios y servicios ofrecidos por espacio.
- Bloqueos de fechas.
- Modificación y cancelación de reservas confirmadas.
- Historial de emails.
- Encuestas de una sola respuesta.
- Limpieza automática de datos según los plazos definidos.
- Soporte físico NFC/QR conservado en `display-nfc/`.

## Puesta en marcha

Seguir **`DEPLOY-FINAL.md`** en el orden indicado.

La SQL definitiva es:

`supabase/FINAL-2026.sql`

### Regla SQL del proyecto

**🗂️ GUARDAR — FINAL-2026.sql**

Debe conservarse como la SQL consolidada de la versión final. Las SQL anteriores de `supabase/` se mantienen como histórico y no deben ejecutarse una detrás de otra como procedimiento de instalación.

## Seguridad

No guardar secretos en el frontend. La service role key de Supabase y la API key de Resend se configuran exclusivamente como secretos de Edge Functions.

## Publicación

El proyecto está preparado para GitHub Pages. No se incluye ninguna afirmación de que la versión esté ya desplegada: primero hay que sustituir el contenido del repositorio y completar la configuración de Supabase/Resend siguiendo `DEPLOY-FINAL.md`.


## PREMIUM V8 · 2026-10-01
- Aforo máximo opcional y dinámico en el selector de fechas.
- Campo de administración para aforo máximo del espacio.
- La migración estructurada está en `supabase/PREMIUM-V8-AFORO-MAXIMO-2026-10-01.sql` y NO se ha ejecutado.
- Eliminado el sello circular del logotipo sobre las fotografías de portada.
- Eliminadas las páginas y funcionalidades públicas de Favoritos y Comparar.
- Eliminadas las categorías de celebración y el filtro de precio de la experiencia pública.
- Mantiene búsqueda pública por nombre/localidad y disponibilidad por fechas.
- Botones oscuros con estados normal/hover/seleccionado coherentes con el panel de administración.

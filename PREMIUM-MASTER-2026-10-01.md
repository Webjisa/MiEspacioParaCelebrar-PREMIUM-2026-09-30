# MiEspacioParaCelebrar — PREMIUM MASTER 2026-10-01

## Qué contiene esta versión

Esta versión parte del Premium actual y añade una capa de producto Premium sobre la aplicación existente, manteniendo la lógica de Supabase, reservas, propietarios, administración y gestión de fotografías ya existente.

### Experiencia pública incorporada

- Portada editorial Premium con fotografía protagonista.
- Carrusel dinámico basado en espacios públicos y fotografía principal.
- Buscador de espacio + fecha inicio + fecha fin.
- Beneficios y categorías de celebración.
- Listado de espacios con búsqueda y filtros.
- Favoritos locales por dispositivo.
- Selección de espacios para comparación.
- Comparador de espacios.
- Ficha de espacio compatible con la reserva actual.
- Compartir espacio.
- Galería con lightbox.
- Acciones de navegación Google Maps / Apple Maps.
- Consulta de disponibilidad existente conservada.
- Calendario flotante sin desplazar el formulario.
- Página de seguimiento preparada.
- Centro de ayuda.
- Contacto.
- Captación de propietarios.
- 404 Premium.
- Diseño móvil específico y menú móvil.

### Área de propietario

Se conserva el área privada existente y se añade un panel Premium independiente con:

- KPIs de espacios.
- KPIs de reservas.
- Accesos rápidos a calendario, espacios, solicitudes y ayuda.
- Protección por rol.

La gestión real continúa utilizando las funciones Supabase existentes de propietario.

### Administración

Se conserva la administración actual y se añade un centro de control Premium independiente con:

- KPIs de espacios.
- KPIs de propietarios.
- KPIs de reservas.
- Historial de comunicaciones.
- Accesos rápidos a los módulos actuales.
- Protección por rol.

### Backend preparado

Se incorpora, sin ejecutar, `supabase/PREMIUM-MASTER-MIGRATION-2026-10-01.sql` para preparar:

- Leads de propietarios.
- Alertas de disponibilidad.
- Notificaciones internas.
- Tickets de soporte.
- Configuración pública.
- Plantillas de email.
- Analítica de eventos.
- Índices operativos adicionales.

## Importante

La migración SQL está marcada expresamente como **NO EJECUTAR TODAVÍA**. Esta versión no modifica Supabase ni despliega nada.

Para que las funciones nuevas de backend queden activas habrá que revisar la migración contra el esquema real y ejecutarla de forma controlada.

## Archivos principales nuevos

- `premium-master.js`
- `premium-master.css`
- `favoritos.html`
- `comparar.html`
- `seguimiento.html`
- `incluir-espacio.html`
- `ayuda.html`
- `contacto.html`
- `premium-propietario.html`
- `premium-admin.html`
- `supabase/PREMIUM-MASTER-MIGRATION-2026-10-01.sql`

## Regla de desarrollo

El proyecto original y el backup permanecen intactos. Esta versión se genera como nueva versión de trabajo Premium.

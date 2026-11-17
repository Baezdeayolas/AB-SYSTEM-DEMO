# Etapa 2D.1 — inventario de consumidores de datos DEMO

**Estado: auditoría estática del código; no prueba dinámica.**

Ámbito: `AB-SYSTEM-DEMO`, rama `work/ab-system-multempresa-ui`. No se inspeccionó ni modificó producción.

## Archivos de aplicación inspeccionados

- `index.html`
- `cloud-sync-demo.js`
- `data-demo.js`
- `README.md`
- `ARQUITECTURA-MULTIEMPRESA.md`

El árbol de la rama también contiene `style.css`, `service-worker.js`, `manifest.json` y documentos de diseño. Los archivos de lógica de datos encontrados son `cloud-sync-demo.js` y `data-demo.js`.

## Mapa de consumidores detectados

| Tabla/objeto | Operación detectada | Ubicación / comportamiento | Riesgo o trabajo pendiente |
|---|---|---|---|
| `profiles` | SELECT `role,seller_label` por `id` | `cloud-sync-demo.js`, función `activate()` | La app decide autorización desde `profiles.role` legacy (`admin/seller`). Migrar a memberships y rol global después de probar RLS. |
| `catalog_items` | SELECT `code,payload`, ordenado por `code` | `loadData()` | No filtra por empresa; `payload` se usa como objeto de artículo. Añadir contexto de empresa tras migración backend. |
| `catalog_clients` | SELECT `code,payload`, ordenado por `code` | `loadData()` | No filtra por empresa; `payload` se usa como objeto de cliente. |
| `seller_assignments` | SELECT `seller_label` filtrado por `user_id` | `loadData()` para perfil seller | El admin no consulta asignaciones: genera tres vendedores estáticos. Reemplazar por memberships `seller` activas de la empresa. |
| `orders` | SELECT `id,legacy_id,legacy_source,payload,updated_at`, últimos 50 | `loadOrders()` | No filtra por `company_id`; la consulta depende de RLS. |
| `orders` | INSERT `owner_id,legacy_id,legacy_source,payload,updated_at` | manejador `save-order` | No envía `company_id` ni `created_by`; `owner_id` siempre es el usuario conectado aunque el selector permita elegir vendedor por etiqueta. Requiere rediseñar identidad y validación backend antes de multiempresa. |
| `inventory_current` | No se encontró consulta directa | `cloud-sync-demo.js` | La pantalla Stock muestra `items` del catálogo y `sc` del `payload`, no el snapshot `inventory_current`. Verificar si el importador externo actualiza JSONB de catálogo o inventario. |
| `catalog_import_rows` | No se encontró consulta directa | — | Consumidor no localizado en frontend inspeccionado; podría ser importador externo/administrativo. Confirmar antes de cambiar esquema o permisos. |
| `companies` | No se encontró consulta | — | Selector/contexto multiempresa no implementado. `index.html` muestra texto estático `EMPRESA DEMO`. |
| `company_memberships` | No se encontró consulta | — | El frontend todavía no obtiene empresas ni roles desde memberships. |
| `global_roles` | No se encontró consulta | — | El frontend no implementa contexto de superadmin global. |

## Hallazgos funcionales críticos

1. `index.html` muestra una empresa activa fija (`EMPRESA DEMO`); no representa un contexto real.
2. `cloud-sync-demo.js` acepta `profiles.role` solo si es `admin` o `seller`; no consulta `company_memberships` ni `global_roles`.
3. Para `admin`, la lista de vendedores está hardcodeada como `VENDEDOR DEMO 1/2/3`. Para `seller`, procede de `seller_assignments`.
4. El pedido guarda la etiqueta elegida en `payload.vendedor`, pero establece `owner_id: user.id`. Por tanto, no implementa la regla acordada para admin que crea en nombre de vendedor.
5. La inserción de pedidos no incluye `company_id` ni `created_by`.
6. Los artículos y clientes se cargan globalmente según las políticas actuales y luego se filtran localmente en memoria.
7. La pantalla Stock usa `items` del catálogo y `sc` de cada payload; no consume `inventory_current` directamente.
8. Los catálogos de respaldo `data-demo.js` son sintéticos y no deben confundirse con datos de empresa.
9. La pantalla Admin es un marcador de posición; no hay gestión real de empresas o membresías.

## Orden recomendado de adaptación

1. No cambiar aún el guardado de pedidos ni las consultas hasta que esquema y RLS multiempresa estén desplegados y probados en DEMO.
2. Implementar un cargador de contexto que obtenga memberships activas y rol global; bloquear si no hay empresa válida.
3. Reemplazar la etiqueta fija de empresa y vendedores hardcodeados.
4. Añadir `company_id` a lecturas/escrituras, manteniendo RLS como autoridad.
5. Rediseñar el pedido para separar `owner_id` (vendedor propietario) de `created_by` (actor autenticado).
6. Aclarar si el inventario será derivado del catálogo o si `inventory_current` se convierte en la fuente de stock por empresa; no duplicar fuentes sin decisión.
7. Localizar el proceso de importación de `catalog_import_rows` y `inventory_current` antes de cambiar permisos.

## Limitaciones de esta revisión

- Auditoría estática de archivos de la rama, no búsqueda exhaustiva en servicios externos, Edge Functions, tareas programadas o scripts fuera del repositorio.
- No se ejecutó navegador, no se autenticó contra Supabase y no se realizaron peticiones de prueba.
- No se inspeccionaron filas de datos reales.
- Este informe no autoriza cambios SQL, despliegues, merge ni publicación.
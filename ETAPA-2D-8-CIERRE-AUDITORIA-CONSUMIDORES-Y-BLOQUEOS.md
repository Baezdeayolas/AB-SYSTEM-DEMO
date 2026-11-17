# ETAPA 2D-8 — CIERRE DE AUDITORÍA DE CONSUMIDORES Y BLOQUEOS

**Entorno:** AB SYSTEM DEMO exclusivamente  
**Rama:** `work/ab-system-multempresa-ui`  
**Tipo:** auditoría estática de repositorio y estado de preparación  
**No autoriza:** ejecución SQL, cambios de esquema, cambios frontend, importación, despliegue, merge ni modificación de producción.

## 1. Archivos de aplicación inspeccionados en la rama

- `index.html` — SHA `a2628f0cede443251bb3690531fa4ba52e938eb4`.
- `cloud-sync-demo.js` — SHA `5ef98ae36907bffe9754445fdccc8876b2ce004b`.
- `data-demo.js` — SHA `6c962476c2d9189d3902ed035b9478849d747a6f`.
- `service-worker.js` — SHA `041977c08925aefffb296858bcc0f3b3db943cce`.
- `README.md` — guía de estado y límites del entorno.
- `ETAPA-2D-1-INVENTARIO-CONSUMIDORES-DATOS.md` y `ETAPA-2D-5-ANALISIS-CODIGO-CATALOGO-PEDIDOS-INVENTARIO.md` — auditorías anteriores.

El árbol raíz de esta rama no muestra otros archivos de lógica de aplicación o importadores. Contiene además `style.css`, `manifest.json` y documentos de arquitectura/auditoría. Esta conclusión se limita al árbol inspeccionado; no demuestra que no existan servicios externos.

## 2. Consumidores/escritores encontrados

| Archivo / función | Objeto | Operación confirmada |
|---|---|---|
| `cloud-sync-demo.js` / `loadData()` | `catalog_items` | SELECT `code,payload`; usa `payload` como objeto de producto. |
| `cloud-sync-demo.js` / `loadData()` | `catalog_clients` | SELECT `code,payload`; usa `payload` como objeto de cliente. |
| `cloud-sync-demo.js` / `loadData()` | `seller_assignments` | SELECT de `seller_label` por `user_id` para perfil seller. |
| `cloud-sync-demo.js` / `loadOrders()` | `orders` | SELECT de últimos 50 pedidos. |
| `cloud-sync-demo.js` / `save-order` | `orders` | INSERT con `owner_id`, `legacy_id`, `legacy_source`, `payload`, `updated_at`. |
| `cloud-sync-demo.js` / `render()` | `catalog_items.payload.sc` | Lee `sc` para mostrar stock en búsqueda y panel de stock. |
| `data-demo.js` | memoria local | Proporciona cinco productos y cuatro clientes ficticios de respaldo. No escribe Supabase. |
| `index.html` | UI | Muestra empresa DEMO fija; no resuelve contexto empresarial real. |

En los archivos de aplicación DEMO inspeccionados no se encontró escritura ni lectura directa de `inventory_current`, `catalog_import_rows`, `company_memberships`, `companies` o `global_roles`. Tampoco se encontró un parser/importador Excel en estos archivos.

## 3. Hallazgos sobre stock y precios

1. La UI DEMO carga `catalog_items.payload` y muestra `sc`. En el código actual inspeccionado no se lee `sd`.
2. `sd` aparece en los datos sintéticos, pero no se encontró consumidor funcional en `index.html` ni `cloud-sync-demo.js`. Su significado sigue sin demostrarse.
3. La auditoría previa del código Ko’ẽju de producción encontró otro flujo que procesa stock/precios y escribe `inventory_current` como fila única `id=1`. Ese archivo pertenece a producción y no fue modificado. No se ha identificado un importador equivalente dentro del repositorio DEMO.
4. El estado compartido de Supabase DEMO informó `inventory_current` con un arreglo `items` vacío en la inspección realizada. Esto no demuestra que no existan otros escritores externos.
5. Por tanto, no hay base suficiente para afirmar que el stock actual de DEMO tenga una única fuente operativa ni para migrar `sc`/`sd` automáticamente.

## 4. Mapa de tablas en DEMO

| Tabla | Uso en frontend DEMO encontrado | Estado de migración |
|---|---|---|
| `catalog_items` | SELECT y lectura de `payload.sc` | Agregar empresa solo después de preflight; conservar JSONB en transición. |
| `catalog_clients` | SELECT | Agregar empresa después de preflight. |
| `orders` | SELECT e INSERT legacy | Requiere identidad owner/actor y company_id validados en backend. |
| `seller_assignments` | SELECT para seller | Compatibilidad temporal; memberships serán autoridad futura. |
| `inventory_current` | Ningún uso directo en frontend DEMO | No alterar hasta localizar importadores/escritores. |
| `catalog_import_rows` | Ningún uso directo en frontend DEMO | Consumidor externo no confirmado. |
| `companies`, `company_memberships`, `global_roles` | Sin consulta frontend | Tablas existentes pero aún no integradas en UI. |

## 5. Reglas seguras para celdas vacías

Para cerrar el comportamiento del importador sin inventar valores:
- Artículo nuevo: código y descripción obligatorios; los demás campos descriptivos opcionales vacíos se almacenan como NULL/ausentes, no como texto artificial.
- Artículo existente: campo descriptivo opcional vacío conserva el valor previamente guardado; no borra información por omisión accidental.
- Stock o precio vacío: bloquea la publicación mientras no exista una regla específica aprobada. Nunca convertir vacío a cero.
- Cero numérico explícito en stock o precio: valor válido y se guarda como cero.
- Campo opcional descriptivo presente con texto: actualiza ese dato.
- `Envases`, `Master`, `Inner`: conservar valor de origen; no calcular ni inferir unidades de empaque.

Esta política evita que una celda vacía destruya datos existentes y diferencia explícitamente vacío de cero.

## 6. Bloqueos externos que no pueden resolverse desde el repositorio

### 6.1 Backup y restauración

No se dispone de acceso a la consola/infraestructura de Supabase para generar ni restaurar un backup. No existe evidencia verificable en el repositorio de una restauración de prueba. El usuario o administrador del proyecto debe confirmar backup descargable y restauración en un proyecto separado antes de cualquier SQL mutante.

### 6.2 Escritores externos

No se inspeccionaron Edge Functions, tareas programadas, integraciones privadas ni computadoras/archivos externos. No afirmar que el inventario de escritores sea exhaustivo. Debe verificarse en Supabase y en el entorno operativo si hay funciones, triggers o integraciones que actualicen catálogos, inventario o importaciones.

### 6.3 Pruebas JWT/RLS

No se ejecutaron sesiones JWT reales de superadmin, admin de empresa, seller ni usuario sin membership. Las políticas y grants conocidos siguen requiriendo pruebas de aislamiento tras el diseño de sustitución coordinada.

## 7. Criterio para autorizar el primer lote SQL

El primer lote mutante no está listo para ejecución. Antes se requiere:
1. Evidencia de backup DEMO y restauración comprobada fuera del proyecto activo.
2. Confirmación de inventario de Edge Functions, triggers y procesos externos que escriben datos comerciales.
3. Resolver el origen real de `sc` y el significado/uso de `sd`; no hacer backfill de stock por suposición.
4. Revisar un preflight SQL de solo lectura con el estado actual inmediatamente antes del cambio.
5. Aprobar explícitamente el script mutante completo, con preflight, verificaciones posteriores y rollback.

## 8. Resultado

Se completó la auditoría estática del repositorio DEMO disponible y se fijó una política conservadora para celdas vacías. No se puede declarar terminada la migración multiempresa ni la importación porque faltan evidencias externas de backup/restauración, procesos de escritura y RLS/JWT.

**Ejecución:** no se ejecutó SQL; no se accedió ni modificó Supabase; no se cambió código de aplicación; no se importaron datos; no se modificó Ko’ẽju producción; no se abrió PR, no se hizo merge y no se publicó.
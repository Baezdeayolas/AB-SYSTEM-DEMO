# ETAPA 2D-10 — PLAN DE CORRECCIÓN Y CIERRE DE BLOQUEOS

**Entorno:** AB SYSTEM DEMO exclusivamente  
**Rama:** `work/ab-system-multempresa-ui`  
**Estado:** plan operativo; no es autorización para ejecutar SQL mutante.  
**Alcance:** consolidar resultados 2D-7, 2D-8 y 2D-9, ordenar correcciones y separar tareas ejecutables en repositorio de verificaciones que requieren al administrador de Supabase.

## 1. Decisión de seguridad

No se aplicarán cambios a Supabase hasta contar con:
1. backup DEMO verificable y restauración probada en un proyecto separado;
2. inventario de Edge Functions, tareas programadas e integraciones que escriban datos;
3. script SQL completo revisado, con preflight, cambios por objeto, verificaciones posteriores y rollback;
4. aprobación explícita del usuario sobre ese script;
5. pruebas JWT/RLS planificadas para superadmin, admin de empresa, vendedor y usuario sin membresía.

No tocar Ko’ẽju producción, no modificar la rama de producción, no publicar, no fusionar ramas y no importar el Excel durante esta etapa.

## 2. Hallazgos confirmados del preflight 2D-9

### A — Triggers en tablas comerciales
La consulta sobre triggers no internos de las tablas comerciales/autorización no devolvió filas.

### B — Funciones públicas con referencias textuales
La búsqueda textual de funciones públicas que mencionaran `catalog_items`, `catalog_clients`, `inventory_current`, `catalog_import_rows` u `orders` no devolvió filas. Esto no descarta SQL dinámico ni escritores externos.

### C — Políticas RLS
Se identificaron 13 políticas. Tres políticas SELECT permisivas con `USING (true)` mantienen lectura abierta en:
- `catalog_clients`
- `catalog_items`
- `inventory_current`

Por ser políticas PERMISSIVE, añadir otra política restrictiva/permisiva sin retirar coordinadamente las políticas abiertas no cierra el acceso. Las cuatro políticas CRUD de `orders` conocidas se basan en `owner_id = auth.uid()` o administrador global y todavía no expresan pertenencia a empresa.

### D — RLS
RLS está activado en 10/10 tablas inspeccionadas. FORCE RLS está desactivado en 10/10. Esto no demuestra aislamiento correcto: dependen también de políticas, roles, grants, funciones SECURITY DEFINER y contexto de ejecución.

### E — Vistas
No se encontraron vistas normales ni materializadas que coincidan textualmente con las tablas consultadas.

### F — Trigger de autenticación
Existe `auth.users.on_demo_user_created`, AFTER INSERT, que ejecuta `public.create_demo_profile()`. Debe preservarse mientras se revisa su compatibilidad con el alta multiempresa. No eliminar ni reemplazar de forma aislada.

### G — Extensiones y publicación
Extensiones: `pg_stat_statements 1.11`, `pgcrypto 1.3`, `plpgsql 1.0`, `supabase_vault 0.3.2`, `uuid-ossp 1.1`.
Publicación: `supabase_realtime`, `puballtables=false`, INSERT/UPDATE/DELETE/TRUNCATE habilitados. El resultado no identifica por sí mismo qué tablas están incluidas; consultar la lista de tablas publicadas antes de cualquier cambio que dependa de Realtime.

### H — Estadísticas
Las ocho tablas solicitadas aparecen en `pg_stat_user_tables`. `n_live_tup` es estimado; `last_analyze` y `last_autoanalyze` son NULL en el resultado recibido. No usar estas estadísticas como conteos exactos ni como prueba de integridad.

## 3. Correcciones necesarias y orden obligatorio

### C1 — Cerrar lectura abierta legacy
Preparar un cambio coordinado y específico por tabla para reemplazar las tres políticas SELECT `USING (true)` por reglas de pertenencia a empresa. No basta con agregar políticas nuevas. Antes de retirar las políticas abiertas debe existir:
- columna/relación de empresa válida y datos asignados;
- funciones de autorización probadas bajo JWT;
- políticas nuevas para cada rol;
- plan de rollback;
- pruebas negativas entre Empresa A y Empresa B.

No ejecutar esta corrección antes de completar el esquema y el backfill. Aplicar primero la política sin datos/relaciones listas puede bloquear la aplicación o dejar accesos inconsistentes.

### C2 — Alinear `orders` con empresa
El esquema/políticas actuales de pedidos no tienen pertenencia empresarial demostrada. Diseñar la adición y backfill de `company_id` conservando `owner_id`, `legacy_id`, `legacy_source` y `payload`. El único pedido histórico inspeccionado se atribuyó a un vendedor con membership activa en Ko’ẽju, pero debe repetirse el preflight inmediatamente antes del cambio. No inferir `created_by` histórico si no hay evidencia.

### C3 — Reducir grants por objeto, no globalmente
Existe antecedente de grants amplios legacy, incluidos TRUNCATE, REFERENCES y TRIGGER. Preparar matriz objeto/rol/operación y revisar consumidores. Revocar únicamente privilegios confirmados como innecesarios, uno por objeto, después de probar el flujo correspondiente. No aplicar REVOKE global ni alterar ACL por defecto de Supabase.

### C4 — Preservar el alta de perfiles
Inspeccionar definición, owner, SECURITY DEFINER, search_path, ACL y dependencias de `public.create_demo_profile()`. Diseñar una transición que mantenga el trigger de `auth.users` y cree solo el perfil básico; la membresía empresarial debe ser un acto separado, autorizado y auditado. No conceder membership automáticamente a todo usuario nuevo.

### C5 — Determinar escritores externos y Realtime
En Supabase DEMO, revisar:
- Edge Functions desplegadas y su código/configuración;
- Database Webhooks;
- Cron/jobs y tareas programadas;
- integraciones externas y clientes que usen service_role;
- tablas incluidas en `supabase_realtime`;
- secretos/credenciales solo por inventario de nombres y uso, nunca pegarlos en el chat.

Registrar nombre, objeto escrito, operación, identidad técnica, frecuencia, propietario y plan de actualización. No compartir claves, tokens ni valores secretos.

### C6 — Backup y restauración
El administrador debe generar/exportar backup de DEMO y probar restauración en un proyecto Supabase separado. Registrar fecha, proyecto destino no productivo, resultado y evidencia no sensible. Un mensaje de “backup habilitado” no sustituye una restauración probada.

### C7 — Resolver compatibilidad de stock
No hacer backfill automático de `sc` o `sd` a stock normalizado todavía. La UI DEMO observada lee `payload.sc`, no `sd`; el significado de `sd` no está demostrado y no se identificaron todos los escritores. `inventory_current` contiene un arreglo vacío en el snapshot anterior y tiene un solo registro `id=1`. Antes de migrar, decidir fuente canónica, adaptador temporal y estrategia de conciliación. CENTRAL y CDE deben seguir separados; pedidos no descuentan ni reservan stock.

## 4. Decisiones funcionales ya fijadas para importación
- Código de artículo y descripción son obligatorios para artículos nuevos.
- Códigos se conservan como texto.
- Precios y stock cero explícitos son válidos.
- Vacío numérico bloquea publicación; nunca se convierte silenciosamente en cero.
- En artículo existente, campo descriptivo opcional vacío conserva valor anterior.
- En artículo nuevo, campo descriptivo opcional vacío queda NULL/ausente.
- `Envases`, `Master`, `Inner` se conservan sin semántica operativa inferida.
- CENTRAL y CDE se actualizan por separado.
- Artículos ausentes del Excel no se borran ni se ponen a cero.
- Pedidos históricos no se modifican y los pedidos nuevos no descuentan stock.

## 5. Próxima secuencia ejecutable

1. Usuario/administrador completa C5 y C6 en Supabase DEMO y devuelve solo resultados no sensibles.
2. Preparar una auditoría específica de `create_demo_profile()`, privilegios efectivos y tablas publicadas en Realtime.
3. Repetir preflight de datos, claves, grants y políticas justo antes de cualquier cambio.
4. Preparar lote SQL aditivo separado: tablas normalizadas/lotes/stock/precios y relaciones empresariales, con constraints e índices compatibles. Sin activar todavía nuevas políticas abiertas ni cambiar frontend.
5. Revisar y aprobar explícitamente el SQL completo.
6. Ejecutar manualmente primero en DEMO; validar conteos, integridad y rollback.
7. Probar RLS/JWT con usuarios de prueba de dos empresas y roles distintos.
8. Sustituir políticas legacy y grants por objeto en un lote separado, con pruebas y rollback.
9. Integrar frontend DEMO después de que el esquema/RLS esté validado.
10. Probar importación Excel con lote de prueba, preview, publicación atómica y conciliación; nunca importar a producción en esta etapa.

## 6. Información que debe aportar el administrador

No enviar secretos. Confirmar:
- ¿Existe backup DEMO reciente y se restauró correctamente en un proyecto separado?
- ¿Hay Edge Functions, cron/jobs, webhooks o integraciones que escriban en las tablas comerciales? Indicar nombres y objetos, no claves.
- ¿Qué tablas están incluidas en `supabase_realtime`?
- ¿Hay clientes externos que utilicen service_role para escribir catálogo, stock, clientes, importaciones o pedidos?

## 6.1 Estado del respaldo confirmado por el usuario

El usuario informó que actualmente no dispone de un backup de Supabase DEMO. Por tanto:
- **Bloqueo de seguridad abierto:** no ejecutar DDL/DML ni cambios de RLS/grants sobre el proyecto activo.
- Próxima tarea: el propietario/administrador del proyecto debe comprobar si el panel ofrece copias automáticas y, si no hay una copia utilizable, generar una exportación lógica fuera del proyecto.
- Una exportación no se considera respaldo validado hasta comprobar que puede restaurarse en un proyecto separado no productivo.
- El backup de la base de datos no incluye los objetos binarios almacenados mediante Storage API; esos archivos requieren exportación separada.
- No compartir contraseñas, tokens, connection strings ni claves en el chat.

## 7. Estado de ejecución

Este documento organiza correcciones y bloqueos. No se ejecutó SQL, no se cambió Supabase, no se importó Excel, no se modificó código de aplicación, no se tocó producción, no se abrió PR, no se fusionó ni publicó.
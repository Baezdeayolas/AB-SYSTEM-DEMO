# Etapa 2B — Plan de corrección de seguridad

**Proyecto:** AB SYSTEM DEMO (Ko’ẽju como primera empresa)
**Rama:** `work/ab-system-multempresa-ui`
**Estado:** plan técnico; no ejecutar cambios todavía

## 1. Alcance y límites

Este documento organiza los hallazgos de la auditoría de solo lectura y define el orden de trabajo para corregir privilegios y preparar el aislamiento multiempresa.

- Alcance exclusivo de Supabase DEMO.
- No modificar Ko’ẽju producción ni su proyecto Supabase.
- No ejecutar SQL, migraciones, `GRANT`, `REVOKE`, cambios RLS ni cambios de frontend como parte de este plan.
- Cualquier script futuro deberá entregarse completo para revisión y requerirá aprobación explícita antes de que el usuario lo ejecute manualmente.
- Los hallazgos describen el estado observado durante la auditoría; deben volver a verificarse antes de preparar cambios.

## 2. Hallazgos confirmados

### 2.1 Privilegios actuales de tablas

La consulta agregada G mostró que `anon` y `authenticated` tienen `DELETE`, `INSERT`, `REFERENCES`, `SELECT`, `TRIGGER`, `TRUNCATE` y `UPDATE` sobre:

- `catalog_clients`
- `catalog_import_rows`
- `catalog_items`
- `inventory_current`
- `orders`
- `seller_assignments`

`service_role` también tiene esos privilegios en las tablas comerciales. En `companies`, `company_memberships` y `global_roles`, el resultado mostró privilegios para `service_role`, pero no para `anon` ni `authenticated`.

**Riesgo principal:** `TRUNCATE` no está sujeto a las políticas RLS. Los privilegios SQL y RLS son capas distintas: tener RLS habilitado no sustituye la necesidad de limitar los privilegios de tabla.

La presencia de privilegios amplios no demuestra por sí sola que cualquier operación tenga éxito: RLS, constraints, funciones y otros controles también intervienen. Sin embargo, esos privilegios no siguen el principio de mínimo privilegio y deben corregirse.

### 2.2 Privilegios de secuencias

La consulta H corregida sobre `information_schema.role_usage_grants` terminó con `Success. No rows returned` para `anon`, `authenticated` y `service_role` en `public`. Esto solo confirma que esa consulta no encontró concesiones coincidentes; no demuestra que no existan secuencias ni reemplaza una inspección específica de ACL de secuencias.

### 2.3 Privilegios predeterminados

La consulta I encontró ACL predeterminadas en el esquema `public` para los roles creadores `postgres` y `supabase_admin`:

- Tablas (`object_type = 'r'`): `anon` y `authenticated` reciben `arwdDxtm`.
- Secuencias (`object_type = 'S'`): `anon` y `authenticated` reciben `rwU`.
- Funciones (`object_type = 'f'`): `anon` y `authenticated` reciben `X` (EXECUTE).

También aparecen concesiones predeterminadas para `service_role`. Estas ACL se aplican a objetos futuros creados por el rol correspondiente en el esquema indicado; no cambian retroactivamente los permisos de objetos ya existentes. La corrección deberá considerar cada rol creador por separado.

### 2.4 RLS y propietarios

La consulta J confirmó RLS habilitado en las diez tablas públicas revisadas. Todas pertenecen a `postgres` y tienen `rls_forced = false`.

Con `FORCE ROW LEVEL SECURITY` desactivado, el propietario de una tabla normalmente puede omitir RLS. No se debe activar `FORCE` indiscriminadamente: primero hay que revisar funciones `SECURITY DEFINER`, tareas administrativas, migraciones y flujos legítimos del propietario.

### 2.5 Contexto de políticas existente

La auditoría previa identificó políticas permisivas de lectura con `USING (true)` en `catalog_clients`, `catalog_items` e `inventory_current`, además de políticas heredadas basadas en `is_demo_admin()` y `owner_id`. Las políticas permisivas se combinan mediante OR. Deben diseñarse y probarse políticas multiempresa que reemplacen explícitamente las reglas antiguas; añadir una política restrictiva sin revisar las existentes no garantiza aislamiento.

Las funciones centrales `ab_is_global_superadmin()`, `ab_has_company_access(uuid)` y `ab_is_company_admin(uuid)` existen, son `SECURITY DEFINER`, usan `search_path` vacío y tienen ejecución concedida a `authenticated` y `service_role`, no a `anon` ni `PUBLIC`, según la auditoría previa. Aún faltan pruebas funcionales bajo sesiones reales.

## 3. Objetivos de seguridad

1. Aplicar mínimo privilegio a `anon`, `authenticated` y `service_role`.
2. Evitar que nuevos objetos reciban automáticamente permisos amplios.
3. Garantizar aislamiento por `company_id` mediante RLS y validaciones del backend.
4. Mantener las operaciones administrativas legítimas sin depender de permisos excesivos.
5. Preservar la identidad de pedidos: `owner_id` identifica al vendedor propietario y `created_by` al usuario que registró el pedido.
6. Mantener trazabilidad de inventario mediante movimientos append-only y operaciones transaccionales.

## 4. Orden de corrección propuesto

### Paso 1 — Inventario de dependencias y permisos

- Revalidar grants de tablas y columnas, ACL de secuencias, permisos de funciones, vistas, triggers y `ALTER DEFAULT PRIVILEGES`.
- Identificar qué operaciones realiza el frontend directamente y cuáles deben pasar a funciones RPC o backend.
- Revisar dependencias de `is_demo_admin()`, `create_demo_profile()` y el trigger `on_demo_user_created` antes de tocar ACL o lógica.
- Confirmar si hay funciones, vistas o procesos que dependan de privilegios actuales.

**Criterio de salida:** matriz por objeto y operación (SELECT/INSERT/UPDATE/DELETE/EXECUTE/USAGE) con el rol que realmente la necesita.

### Paso 2 — Diseñar privilegios mínimos

- Definir qué necesita `anon` (por defecto, nada sobre datos comerciales privados).
- Definir permisos precisos para `authenticated`, sin `TRUNCATE`, `TRIGGER` ni `REFERENCES` salvo justificación documentada.
- Reservar `service_role` para backend confiable; nunca incluir su clave en el navegador.
- Definir ACL predeterminadas para `postgres` y `supabase_admin` de modo que las tablas, secuencias y funciones nuevas no otorguen acceso general automáticamente.
- Considerar permisos por columna solo si existe una necesidad concreta; preferir RPC controladas para operaciones sensibles.

**Criterio de salida:** script de permisos mínimo, revisado y acompañado de consultas de verificación antes/después. No ejecutar hasta aprobación explícita.

### Paso 3 — Preparar modelo multiempresa

- Añadir `company_id` a las entidades comerciales pertinentes, con FK a `companies` y estrategia de backfill validada.
- Revisar unicidad de códigos dentro de cada empresa y constraints existentes antes de alterarlos.
- En `orders`, conservar `owner_id` y el unique existente `(owner_id, legacy_source, legacy_id)` salvo que un análisis de colisiones justifique otro diseño.
- Incorporar `created_by` para distinguir quién registra un pedido de quién es su propietario.
- Definir inventario por empresa y tabla de movimientos con empresa, artículo, cantidad anterior/nueva, tipo de movimiento, actor, fecha/hora y motivo.

**Criterio de salida:** esquema y estrategia de migración revisados, con plan de rollback y validación de datos históricos.

### Paso 4 — Reemplazar políticas RLS

- Eliminar o sustituir las políticas heredadas que permiten lectura global o dependen únicamente de `is_demo_admin()`.
- Vendedores: acceso únicamente a su empresa y a sus propios pedidos, según reglas aprobadas.
- Administradores de empresa: acceso a los datos de su empresa.
- Superadministrador global: acceso global controlado y explícito.
- Validar que el `company_id` del registro y la membership activa del usuario coincidan.
- No confiar en el selector de empresa ni en valores enviados por el navegador.

**Criterio de salida:** matriz de pruebas RLS con usuarios de dos empresas, vendedor, administrador y superadministrador.

### Paso 5 — Pruebas funcionales y de regresión

- Probar SELECT, INSERT, UPDATE y DELETE permitidos y denegados por rol.
- Probar que un usuario de una empresa no pueda leer ni modificar registros de otra.
- Probar pedidos creados por vendedor y pedidos registrados por administrador en nombre de vendedor.
- Probar que un cambio de empresa no conserve carrito, cliente, vendedor ni estado temporal de la empresa anterior.
- Probar inventario y movimientos dentro de transacciones.
- Verificar que las funciones `SECURITY DEFINER` tengan propietario, `search_path`, ACL y validaciones apropiadas.

**Criterio de salida:** resultados reproducibles documentados; sin errores de aislamiento ni regresiones críticas.

### Paso 6 — Habilitar cambios de frontend

Solo después de completar y verificar esquema, grants y RLS se podrá adaptar `index.html` y `cloud-sync-demo.js` para selector real de empresa, memberships, roles y operaciones comerciales multiempresa. Si falta el esquema nuevo, la aplicación debe bloquear el guardado multiempresa y no recurrir silenciosamente al modelo legacy.

## 5. Riesgos y precauciones

- No revocar permisos en bloque sin conocer dependencias: podría romper login, sincronización, importaciones o creación de perfiles.
- No mantener políticas `USING (true)` en tablas comerciales multiempresa.
- No considerar RLS como sustituto de grants mínimos.
- No exponer `service_role` en código cliente.
- No confiar en `profiles.role` ni en datos del navegador como autoridad para el rol global.
- No permitir que un vendedor elija otro `owner_id`.
- No borrar ni editar silenciosamente movimientos históricos de inventario.
- No ejecutar SQL de este documento: es un plan, no un script de migración.

## 6. Estado y aprobaciones

| Actividad | Estado |
|---|---|
| Auditoría de solo lectura A–J | Completada según resultados compartidos |
| Plan de corrección | Documentado |
| Revalidación de grants y dependencias | Pendiente |
| Script de privilegios mínimos | No preparado |
| Migración multiempresa comercial | Pendiente |
| Políticas RLS multiempresa | Pendientes |
| Pruebas con sesiones reales | Pendientes |
| Cambios de frontend multiempresa | Bloqueados hasta completar backend/RLS |

**Este documento no autoriza la ejecución de SQL ni cambios en producción.**
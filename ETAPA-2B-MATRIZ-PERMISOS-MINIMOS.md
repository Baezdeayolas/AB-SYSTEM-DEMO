# Etapa 2B — Matriz de permisos mínimos

**Proyecto:** AB SYSTEM DEMO (Ko’ẽju como primera empresa)  
**Rama:** `work/ab-system-multempresa-ui`  
**Estado:** propuesta de diseño; requiere validar dependencias antes de convertirla en SQL.

> Este documento no es SQL ejecutable ni autoriza cambios en Supabase. Todas las decisiones son para Supabase DEMO. Producción queda fuera de alcance.

## 1. Principios

- `anon`: sin acceso a datos comerciales ni a funciones internas.
- `authenticated`: solo los privilegios SQL necesarios para las operaciones de la aplicación; RLS decide qué filas puede consultar o modificar.
- `service_role`: solo backend confiable. Nunca incluir su clave en `index.html`, `cloud-sync-demo.js` ni ningún bundle del navegador.
- No conceder `TRUNCATE`, `TRIGGER` ni `REFERENCES` a `anon` o `authenticated` para las tablas de la aplicación.
- Los permisos SQL no sustituyen RLS; RLS tampoco sustituye los permisos SQL.
- Las políticas multiempresa deben reemplazar expresamente las políticas permisivas heredadas; no basta con añadir una política nueva.
- Los privilegios predeterminados deben revisarse para cada rol creador (`postgres` y `supabase_admin`) y cada tipo de objeto.

## 2. Roles considerados

| Rol | Propósito |
|---|---|
| `anon` | Sesión no autenticada; sin acceso a datos privados |
| `authenticated` | Usuario autenticado de la aplicación; permisos acotados por RLS |
| `service_role` | Procesos de backend confiables; nunca navegador |
| `postgres` / `supabase_admin` | Propietarios/roles administrativos de creación y mantenimiento; no son roles de usuario final |

Los roles de negocio (`superadmin_global`, `company_admin`, `seller`) no son roles SQL. Se validan mediante las tablas de autorización y funciones seguras.

## 3. Matriz propuesta para tablas

Las letras de la matriz describen operaciones de negocio previstas, no concesiones SQL listas para aplicar. `R` = leer, `C` = crear, `U` = actualizar, `D` = eliminar. La columna de RLS indica el alcance de filas.

| Tabla | `anon` | `authenticated` | Backend confiable | Regla RLS / autorización prevista |
|---|---:|---:|---:|---|
| `companies` | — | R acotada | Administración | Usuario ve empresas donde tiene membership activa; superadmin ve empresas activas según política global. Cambios solo superadmin. |
| `company_memberships` | — | R acotada | Administración | Usuario puede consultar sus memberships; admin de empresa gestiona memberships de su empresa; superadmin global gestiona globalmente. No permitir autoasignación de roles. |
| `global_roles` | — | — | Administración | No exponer lectura directa al cliente. Consultar autorización mediante funciones seguras; cambios solo por procedimiento administrativo controlado. |
| `catalog_items` | — | R/C/U/D según rol y flujo | Importación/administración | Filas siempre limitadas por `company_id`; seller solo lectura de catálogo de su empresa; admin de empresa gestiona catálogo; superadmin global según contexto. |
| `catalog_clients` | — | R/C/U/D según rol y flujo | Importación/administración | Filas limitadas por `company_id`; seller opera clientes de su empresa según permisos de negocio; admin gestiona clientes de su empresa. |
| `catalog_import_rows` | — | — preferentemente RPC | Importación | No exponer staging de importación directamente. Operaciones de carga y confirmación mediante backend/RPC validada por empresa y rol. |
| `inventory_current` (legacy) | — | — durante transición | Migración/backend | Tabla singleton `id=1` no representa inventario multiempresa. Mantener bloqueada para el flujo multiempresa hasta migrar a saldos por empresa y validar transición. |
| `orders` | — | R/C/U/D por propiedad y rol | Backend/RPC para operaciones sensibles | Seller solo pedidos propios (`owner_id=auth.uid()`) dentro de su empresa; admin de empresa todos los de su empresa; superadmin global según política global. `created_by` no otorga propiedad. |
| `profiles` | — | R de perfil permitido | Bootstrap/administración | Usuario consulta su perfil; campos de rol no editables por el usuario. Admin solo accede a los campos necesarios de miembros de su empresa; evitar exponer perfiles globalmente. |
| `seller_assignments` (legacy) | — | — durante transición | Migración/backend | Sustituir su función por memberships activas `seller` por empresa. No usarla como autoridad multiempresa. |

**Nota importante:** la matriz no significa que se deban conceder todos los verbos de una celda directamente a `authenticated`. Para catálogo, pedidos y membresías se debe decidir operación por operación si el cliente puede usar DML directo con RLS o si la acción debe encapsularse en una función RPC. Las operaciones de mayor impacto (cambios de rol, importaciones, selección de `owner_id`, inventario) deben preferir RPC/backend con validaciones transaccionales.

## 4. Matriz de funciones

| Función / trigger | `anon` | `authenticated` | `service_role` | Decisión propuesta |
|---|---:|---:|---:|---|
| `ab_is_global_superadmin()` | No | Sí, si se invoca desde políticas/flujo autorizado | Sí | Mantener ejecución restringida; revisar que no filtre datos sensibles por mensajes o resultados. |
| `ab_has_company_access(uuid)` | No | Sí, para políticas y comprobaciones | Sí | Mantener; validar empresa activa y membership activa o superadmin. |
| `ab_is_company_admin(uuid)` | No | Sí, para políticas y comprobaciones | Sí | Mantener; validar admin de empresa o superadmin y empresa activa. |
| `is_demo_admin()` | No para el cliente final, sujeto a dependencias | Solo si sigue siendo necesaria durante transición | Solo si procede | Función legacy basada en `profiles.role`; retirar de políticas multiempresa cuando se reemplacen, tras comprobar dependencias. |
| `create_demo_profile()` | No | No invocación directa | Solo si el flujo de bootstrap lo requiere | Trigger de `auth.users` puede invocarla como función interna; revisar ACL y dependencias antes de revocar EXECUTE. |
| `on_demo_user_created` | No aplica como grant de tabla | No aplica | No aplica | Trigger interno de `auth.users`; no alterar hasta revisar el alta de usuarios y el bootstrap de perfil. |

Las tres funciones `ab_*` se observaron como `SECURITY DEFINER`, con `search_path` vacío y ejecución concedida a `authenticated` y `service_role`. Antes de cambiar ACL se debe confirmar su cuerpo completo, propietario, configuración, dependencias y comportamiento con JWT reales. `PUBLIC` y `anon` no deben tener EXECUTE salvo justificación específica.

## 5. Privilegios SQL: línea base deseada

| Tipo de objeto | `anon` | `authenticated` | `service_role` |
|---|---|---|---|
| Tablas privadas | Sin privilegios | Solo SELECT/INSERT/UPDATE/DELETE necesarios; nunca TRUNCATE/TRIGGER/REFERENCES por defecto | Según operaciones backend justificadas |
| Secuencias | Sin privilegios | USAGE/SELECT solo si un flujo real las necesita | Según necesidad backend |
| Funciones | Sin EXECUTE por defecto | EXECUTE solo en RPC y helpers que deban invocarse desde políticas/cliente | EXECUTE solo en funciones necesarias |
| Vistas | Sin acceso por defecto | Solo vistas expresamente diseñadas y seguras | Según necesidad backend |

Para funciones internas `SECURITY DEFINER`, evaluar `REVOKE EXECUTE` a `PUBLIC` y concesión explícita solo a los roles necesarios. No aplicar una revocación global sin inventariar funciones que Supabase, Auth o la aplicación necesiten.

## 6. Privilegios predeterminados

La auditoría I encontró ACL predeterminadas amplias para `postgres` y `supabase_admin` en `public`: tablas, secuencias y funciones otorgan permisos a `anon` y `authenticated`.

Propuesta:

1. Corregir las ACL predeterminadas para cada rol creador por separado.
2. No otorgar acceso de tabla o secuencia a `anon` automáticamente.
3. No otorgar EXECUTE a `PUBLIC`/`anon` automáticamente en funciones nuevas.
4. Conceder explícitamente a `authenticated` solo lo que requiera cada objeto, después de decidir si será DML directo o RPC.
5. Mantener las ACL administrativas de propietarios sin abrir acceso a roles de cliente.
6. Auditar también privilegios por columna y objetos existentes: cambiar defaults no corrige objetos ya creados.

## 7. Operaciones que deben pasar por RPC/backend

- Alta, suspensión y cambio de rol de memberships.
- Asignación de vendedor propietario en pedidos creados por un administrador.
- Importación y confirmación de catálogos.
- Ajustes y movimientos de inventario, con saldo y movimiento en una transacción.
- Operaciones globales de superadmin y consolidación entre empresas.

Cada función debe derivar el actor desde `auth.uid()`, validar empresa activa y rol/membership en servidor, validar relaciones entre entidades y no confiar en `company_id`, `owner_id`, actor o rol enviados por el navegador.

## 8. Datos que faltan validar antes de producir SQL

- Inventario completo de grants actuales por tabla, columna, secuencia, vista y función, incluidos grants heredados y `PUBLIC`.
- ACL de secuencias mediante catálogo de PostgreSQL, no solo `role_usage_grants`.
- Cuerpos completos y ACL de todas las funciones; confirmar dependencias del trigger `on_demo_user_created`.
- Operaciones reales del frontend y cualquier Edge Function/backend existente.
- Políticas RLS completas actuales, incluidos comandos, roles, `USING` y `WITH CHECK`.
- Esquema y constraints definitivos de las tablas comerciales después de incorporar `company_id`.
- Pruebas con al menos dos empresas y sesiones reales de admin, seller y superadmin.

## 9. Criterios de aceptación

1. `anon` no puede leer ni modificar datos privados ni ejecutar funciones internas.
2. `authenticated` no tiene `TRUNCATE`, `TRIGGER` ni `REFERENCES` sobre tablas comerciales.
3. No se conceden permisos por defecto a `anon` en tablas, secuencias o funciones nuevas.
4. Las operaciones legítimas del cliente siguen funcionando con permisos mínimos y RLS.
5. Vendedor A no puede leer ni modificar pedidos de Vendedor B ni datos de otra empresa.
6. Admin de empresa solo accede a su empresa.
7. Superadmin opera globalmente solo a través de funciones/políticas expresamente diseñadas.
8. Las operaciones sensibles validan actor, empresa y rol en backend/RPC.
9. No se expone `service_role` al navegador.
10. Las pruebas de regresión y aislamiento quedan documentadas antes de tocar frontend.

## 10. Estado

| Trabajo | Estado |
|---|---|
| Hallazgos de auditoría A–J | Recibidos según resultados compartidos |
| Matriz de permisos propuesta | Documentada; pendiente validar dependencias |
| Revalidación de grants y ACL | Pendiente |
| Inventario de funciones y dependencias | Pendiente |
| Script de permisos | No preparado |
| Ejecución en Supabase DEMO | No autorizada ni realizada |
| Producción | Sin cambios |

**Este archivo es una matriz de diseño, no una instrucción para ejecutar `GRANT`/`REVOKE` ni una migración.**
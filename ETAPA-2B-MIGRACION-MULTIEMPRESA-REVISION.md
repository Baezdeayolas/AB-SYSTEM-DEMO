# Etapa 2B — paquete de migración para revisión

> **ESTADO: BORRADOR TÉCNICO. NO PEGAR NI EJECUTAR EN SUPABASE.**
> Este documento define el trabajo de la siguiente migración DEMO. No reemplaza una revisión del DDL real, backup restaurable y pruebas con JWT de cada rol.

## Alcance

- Proyecto exclusivo: Supabase DEMO de `AB-SYSTEM-DEMO`.
- Empresa inicial ya creada: Ko’ẽju (`c8c4f6bf-a941-48a2-be99-6322b4ac19fd`).
- No tocar Ko’ẽju producción, su repositorio ni su proyecto Supabase.
- La Etapa 1 (tablas base, membresías iniciales y `global_roles`) y la Etapa 2A (helpers de autorización) fueron ejecutadas manualmente por el usuario y verificadas según los resultados compartidos.

## 1. Estado de partida conocido

| Tabla | Filas conocidas | Tratamiento |
|---|---:|---|
| `catalog_items` | 5 | Asignar a Ko’ẽju |
| `catalog_clients` | 4 | Asignar a Ko’ẽju |
| `catalog_import_rows` | 0 | Añadir ámbito; no hay filas que backfillear |
| `orders` | 1 | Asignar a Ko’ẽju y conservar propietario/payload |
| `seller_assignments` | 1 | Vincular a membresía activa del vendedor |
| `inventory_current` | 1 contenedor, `items=[]` | Conservar intacta durante transición |

Las claves primarias actuales de productos y clientes son `code`; la de importaciones es `(import_id, catalog_type, code)`. Los pedidos tienen UNIQUE `(owner_id, legacy_source, legacy_id)`. No cambiar esas PK/UNIQUE en esta etapa sin inventariar antes todas sus dependencias.

## 2. Reglas que debe cumplir la migración

1. Agregar `company_id` primero como nullable, asignar las filas actuales a Ko’ẽju, validar y recién después imponer `NOT NULL` y FK.
2. Agregar `orders.created_by`. El backfill histórico puede quedar NULL porque no se puede demostrar quién actuó originalmente. Las nuevas escrituras deben establecerlo mediante backend/RPC/trigger confiable.
3. Mantener `orders.owner_id` como propietario vendedor. Si un admin registra en nombre de un vendedor, `owner_id` será el UUID del vendedor elegido y `created_by` será el UUID del admin que actuó.
4. Vendedor: consultar solo pedidos cuyo `owner_id=auth.uid()` dentro de su empresa. Admin de empresa: consultar pedidos de su empresa. Superadmin global: acceso autorizado a todas las empresas.
5. No permitir al vendedor cambiar `owner_id`, `created_by` o `company_id` para suplantar identidades o mover registros entre empresas.
6. No basar ninguna autorización en el selector de empresa del navegador.
7. Reemplazar expresamente las políticas antiguas de lectura `USING (true)` de productos, clientes e inventario. Las políticas permisivas se combinan con OR; agregar una política nueva no neutraliza las antiguas.
8. Los movimientos de inventario serán append-only para los usuarios de aplicación. Las modificaciones de saldo se realizarán mediante una operación transaccional que registre el movimiento y el saldo anterior/nuevo.

## 3. Preflight obligatorio antes de redactar el SQL final

Ejecutar consultas de solo lectura en Supabase DEMO y guardar resultados:

```sql
-- Confirmar empresa inicial
select id, code, name, status
from public.companies
where id = 'c8c4f6bf-a941-48a2-be99-6322b4ac19fd';

-- Confirmar memberships y rol global (no mostrar emails ni credenciales)
select company_id, user_id, role, status
from public.company_memberships
order by company_id, role;
select user_id, role from public.global_roles;

-- Confirmar conteos y valores NULL de los futuros backfills
select 'catalog_items' as tabla, count(*) as filas from public.catalog_items
union all select 'catalog_clients', count(*) from public.catalog_clients
union all select 'catalog_import_rows', count(*) from public.catalog_import_rows
union all select 'orders', count(*) from public.orders
union all select 'seller_assignments', count(*) from public.seller_assignments;

-- Inventariar FKs entrantes a claves actuales antes de cualquier cambio de PK
select conrelid::regclass as tabla_hija, conname, pg_get_constraintdef(oid) as definicion
from pg_constraint
where contype = 'f'
  and confrelid in ('public.catalog_items'::regclass, 'public.catalog_clients'::regclass);

-- Inventariar todas las policies actuales de las tablas afectadas
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('catalog_items','catalog_clients','catalog_import_rows','orders','seller_assignments','inventory_current')
order by tablename, policyname;

-- Inventariar grants actuales de las tablas afectadas
select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('catalog_items','catalog_clients','catalog_import_rows','orders','seller_assignments','inventory_current')
order by table_name, grantee, privilege_type;
```

**No continuar** si los conteos difieren de los valores conocidos sin explicar primero la diferencia, si Ko’ẽju no existe/está suspendida, si los usuarios/membresías no coinciden con las identidades confirmadas o si aparecen FKs entrantes no analizadas.

## 4. Diseño de cambios aditivos

### 4.1 Tablas comerciales

- `catalog_items.company_id uuid NOT NULL REFERENCES companies(id)`; índice único objetivo `(company_id, code)` después de resolver la PK global actual.
- `catalog_clients.company_id uuid NOT NULL REFERENCES companies(id)`; índice único objetivo `(company_id, code)` después de resolver la PK global actual.
- `catalog_import_rows.company_id uuid NOT NULL REFERENCES companies(id)`; unicidad objetivo `(company_id, import_id, catalog_type, code)` después de revisar consumidores.
- `orders.company_id uuid NOT NULL REFERENCES companies(id)` y `orders.created_by uuid NULL REFERENCES auth.users(id)` para historia; las nuevas escrituras deberán exigir actor.
- `seller_assignments.company_id uuid NOT NULL REFERENCES companies(id)`; revisar si su PK actual `(user_id)` debe convertirse para permitir asignaciones por empresa. Validar que cada fila corresponda a una membresía activa `seller`.

Los cambios de PK no forman parte de un ALTER automático: primero deben migrarse consultas, upserts, claves de conflicto y FKs consumidoras.

### 4.2 Helpers de autorización faltantes

Antes de políticas definitivas, implementar y revisar helpers `SECURITY DEFINER` con `search_path=''`, objetos calificados y `EXECUTE` revocado de `PUBLIC`/`anon`:

- `ab_is_company_seller(company_id, user_id)` — membership activa `seller` en esa empresa.
- `ab_can_read_order(company_id, owner_id)` — superadmin global, admin de empresa o vendedor activo dueño del pedido.
- Si se usan funciones RPC para crear pedidos o movimientos, validar dentro de la función el rol, la empresa, el producto y el vendedor elegido; no confiar en parámetros enviados por el cliente.

Los helpers existentes `ab_is_global_superadmin()`, `ab_has_company_access(uuid)` y `ab_is_company_admin(uuid)` no sustituyen la comprobación de vendedor ni la validación del propietario de pedido.

### 4.3 Matriz RLS prevista

| Tabla | SELECT | INSERT/UPDATE/DELETE |
|---|---|---|
| `catalog_items` | Miembros activos de empresa; superadmin global | Admin de empresa/superadmin; vendedor sin escritura salvo autorización funcional explícita |
| `catalog_clients` | Miembros activos de empresa; superadmin global | Admin de empresa/superadmin; vendedor sin escritura salvo autorización funcional explícita |
| `catalog_import_rows` | Admin de empresa/superadmin | Admin de empresa/superadmin |
| `orders` | Superadmin; admin de empresa; vendedor solo si `owner_id=auth.uid()` | Preferentemente RPC validada; vendedor solo para sí mismo; admin para vendedor activo de su empresa |
| `seller_assignments` | Admin de empresa/superadmin y el vendedor respecto de su propia asignación | Admin de empresa/superadmin, validando membership |
| tablas nuevas de inventario | Miembros autorizados de empresa; superadmin | RPC transaccional; no DML directo sobre movimientos |

Las políticas antiguas deben eliminarse por nombre exacto después de revisar `pg_policies`. No ejecutar `DROP POLICY` a ciegas.

## 5. Inventario multiempresa

Crear tablas nuevas, sin reutilizar ni truncar `inventory_current`:

- `inventory_balances`: PK `(company_id, product_code)`, cantidad no negativa y `updated_at`.
- `inventory_movements`: id, empresa, producto, tipo (`entry`, `exit`, `adjustment`), delta, cantidad anterior/nueva, motivo, actor y timestamp.
- FK compuesta `(company_id, product_code)` hacia la clave única empresarial del catálogo, cuando esa clave esté implementada.
- RPC transaccional: validar empresa y permiso; bloquear saldo con `SELECT ... FOR UPDATE`; calcular cantidades; rechazar stock negativo; actualizar saldo e insertar movimiento en la misma transacción.
- Revocar `UPDATE`/`DELETE` directo de movimientos a roles de aplicación. Correcciones mediante un nuevo ajuste.

Decisión provisional para DEMO: no permitir stock negativo. Confirmar unidades/precisión decimal y si se requiere registrar reservas antes de definir la RPC final.

## 6. Pedidos y trazabilidad

Para nuevos pedidos:

- Vendedor crea para sí: `owner_id=auth.uid()`, `created_by=auth.uid()`.
- Admin crea para vendedor seleccionado: `owner_id=<UUID vendedor validado>`, `created_by=auth.uid()`.
- `company_id` siempre debe coincidir con empresa activa y membresías verificadas.
- El backend debe validar que el vendedor elegido tenga membership activa `seller` en la misma empresa.
- No permitir que el cliente envíe libremente `created_by` ni que el vendedor elija otro `owner_id`.
- Mantener intacto `payload`, incluidos precios históricos y líneas, durante esta migración.

## 7. Pruebas de aceptación requeridas

Probar con sesiones/JWT reales de superadmin, admin Ko’ẽju, vendedor Ko’ẽju y usuario sin membresía. Ejecutar también pruebas negativas con una segunda empresa y usuarios sintéticos:

- vendedor A no puede leer pedido de vendedor B ni datos de empresa B;
- admin A no puede consultar ni modificar empresa B;
- usuario sin membresía no puede leer datos comerciales;
- el selector/`company_id` manipulado no concede acceso;
- un vendedor no puede autoasignarse rol ni suplantar otro `owner_id`;
- admin solo puede crear pedido para vendedor activo de su empresa;
- dos empresas pueden usar el mismo código tras migrar las PK/índices correctamente;
- movimientos de stock concurrentes mantienen saldo e historial consistentes;
- usuarios de aplicación no pueden editar/borrar movimientos;
- las escrituras fallidas no dejan saldo ni movimiento parcial.

Una consulta ejecutada como `postgres` no demuestra que RLS funcione para `authenticated`. Estas pruebas no se consideran completadas hasta probar con JWT de cada rol.

## 8. Criterios de salida antes de ejecutar

- Backup DEMO realizado y restauración verificada.
- Preflight completo guardado y coincidente con el esquema real.
- Dependencias de PK/FK y consumidores del frontend resueltos.
- SQL final revisado en una transacción o fases reversibles documentadas.
- Policies antiguas identificadas por nombre y reemplazo definido.
- Grants, `EXECUTE`, propietarios y funciones `SECURITY DEFINER` revisados.
- Pruebas RLS con JWT preparadas y usuarios de prueba disponibles.
- Aprobación expresa del usuario sobre el script final completo.

## 9. Estado actual

- Este paquete es documentación de diseño; no contiene un script final ejecutable.
- No se ha ejecutado ninguna consulta de modificación con este documento.
- No se ha modificado Supabase en esta etapa.
- No se ha cambiado `index.html` ni `cloud-sync-demo.js`.
- No se ha modificado producción, abierto/mezclado PR ni publicado Pages.

## 10. Siguiente acción concreta

Obtener y revisar los resultados de las consultas de preflight de la sección 3. Con esos resultados se redactará el SQL final de Etapa 2B con nombres exactos de policies, constraints, índices y dependencias, evitando asumir que el esquema sigue idéntico al último diagnóstico.
## 11. Hallazgo recibido: privilegios SQL amplios

El usuario compartió el resultado de `information_schema.role_table_grants` para las seis tablas actuales inspeccionadas (`catalog_clients`, `catalog_import_rows`, `catalog_items`, `inventory_current`, `orders`, `seller_assignments`). En todas aparecen privilegios para `anon` y `authenticated`, incluyendo `INSERT`, `UPDATE`, `DELETE` y `TRUNCATE`; también aparecen los privilegios esperables de `postgres` y `service_role`.

Interpretación:
- Es una configuración demasiado amplia para un esquema multiempresa y debe corregirse en la migración de seguridad.
- RLS filtra operaciones por fila, pero no sustituye los privilegios SQL. En particular, `TRUNCATE` no está protegido por RLS; no debe estar concedido a `anon` ni a `authenticated`.
- La presencia de estos GRANT no demuestra por sí sola que los datos sean públicamente legibles o modificables: eso depende también de RLS, políticas, vistas y funciones. No afirmar exposición efectiva sin revisar esas capas.
- No ejecutar todavía un `REVOKE` aislado: primero hay que definir los privilegios mínimos requeridos por el frontend, RPC y políticas finales para evitar romper la aplicación o dejar una falsa sensación de seguridad.

Acción para SQL final: incluir revocación explícita de privilegios innecesarios a `anon` y `authenticated`, conceder únicamente los privilegios mínimos por tabla/operación y revisar privilegios por columna, secuencias, funciones, vistas y `ALTER DEFAULT PRIVILEGES`. Mantener `service_role` solo en backend seguro.

Este hallazgo se basa en la salida compartida por el usuario. Aún faltan los resultados de conteos/backfill, memberships/global_roles, FKs entrantes y `pg_policies` para cerrar el preflight.

# Addendum — resultado de auditoría RLS (consulta A)

El usuario compartió `pg_policies` para las seis tablas actuales. Se confirma:

- `catalog_items`: `demo_items_read` es PERMISSIVE SELECT para `authenticated` con `USING (true)`. `demo_items_admin_all` usa `is_demo_admin()` para ALL.
- `catalog_clients`: `demo_clients_read` es PERMISSIVE SELECT con `USING (true)`. `demo_clients_admin_all` usa `is_demo_admin()` para ALL.
- `inventory_current`: `demo_inventory_read` es PERMISSIVE SELECT con `USING (true)`. `demo_inventory_admin_all` usa `is_demo_admin()` para ALL.
- `orders`: SELECT/UPDATE/DELETE permiten `owner_id = auth.uid()` o `is_demo_admin()`; INSERT usa esa misma condición en `WITH CHECK`. No hay comprobación de `company_id`, membership activa ni `created_by`.
- `catalog_import_rows`: solo `demo_imports_admin_all` con `is_demo_admin()`.
- `seller_assignments`: `demo_assignments_admin_all` usa `is_demo_admin()`; SELECT también permite al usuario leer su propia fila por `user_id`.

Implicaciones para Etapa 2B:

1. Las políticas `demo_items_read`, `demo_clients_read` y `demo_inventory_read` deben retirarse/reemplazarse explícitamente al activar RLS por empresa. Por ser PERMISSIVE, se combinan mediante OR con otras políticas permisivas; añadir una política restrictiva permisiva nueva no neutraliza el `USING (true)` existente.
2. Las policies de `orders` deben migrarse conjuntamente a reglas multiempresa que validen empresa activa, membership y propiedad del pedido. `is_demo_admin()` no debe seguir siendo autoridad para el modelo multiempresa.
3. Las policies de importaciones y asignaciones también deben pasar a autorización por empresa; la lectura de asignaciones propias debe quedar limitada a la empresa correspondiente.
4. No ejecutar aún `DROP POLICY` ni cambios de grants. Primero completar preflight y preparar reemplazos exactos para evitar ventanas de acceso indebido o interrupciones.

Falta todavía el resultado de la consulta B sobre FKs entrantes a `catalog_items` y `catalog_clients`. Sin él no se puede cerrar el análisis de dependencias de claves y referencias.
## Addendum — resultado de auditoría de FKs entrantes

El usuario ejecutó la consulta de claves foráneas entrantes hacia `public.catalog_items` y `public.catalog_clients` y obtuvo `Success. No rows returned`.

Interpretación: la consulta no encontró FKs declaradas en otras tablas que referencien esas dos tablas. Esto reduce las dependencias referenciales declaradas que habría que migrar al cambiar sus claves; no descarta dependencias en código, vistas, funciones, triggers, procesos de importación ni consultas del frontend. Antes de cambiar PK o claves únicas todavía deben revisarse esos consumidores.

El preflight sigue incompleto: faltan los resultados actuales de empresa/memberships/global_roles y conteos de tablas, o confirmación de que coinciden con el inventario documentado. No redactar ni ejecutar aún el SQL final.
## Addendum — conteos de tablas confirmados

El usuario compartió los conteos actuales de Supabase DEMO:

| Tabla | Filas confirmadas |
|---|---:|
| `catalog_items` | 5 |
| `catalog_clients` | 4 |
| `catalog_import_rows` | 0 |
| `orders` | 1 |
| `seller_assignments` | 1 |

Los conteos coinciden con el inventario previo documentado. Aún falta recibir la salida de `companies`, `company_memberships` y `global_roles` para validar empresa y membresías antes de cerrar el preflight.
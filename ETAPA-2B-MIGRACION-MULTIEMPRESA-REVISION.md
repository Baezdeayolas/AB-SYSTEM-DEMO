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
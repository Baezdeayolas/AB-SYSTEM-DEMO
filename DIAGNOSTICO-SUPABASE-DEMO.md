# Diagnóstico de Supabase DEMO — cierre de inspección inicial

**Repositorio:** AB-SYSTEM-DEMO  
**Rama:** work/ab-system-multempresa-ui  
**Estado:** diagnóstico documental; no se ejecutaron cambios en Supabase.

## 1. Conteos reportados

Resultados de la consulta de conteos compartida por el usuario:

| Tabla | Registros |
|---|---:|
| catalog_items | 5 |
| catalog_clients | 4 |
| catalog_import_rows | 0 |
| inventory_current | 1 |
| orders | 1 |
| profiles | 2 |
| seller_assignments | 1 |
| **Total de filas en las siete tablas** | **14** |

Nota: inventory_current tiene una fila contenedora, pero su campo items es un array vacío. Por tanto, hay cero artículos de inventario en ese array. El total 14 cuenta filas de tablas, no entidades comerciales ni existencias.

## 2. Estructura actual relevante

- `catalog_items`: `code text` como clave primaria, `payload jsonb`, `updated_at timestamptz`.
- `catalog_clients`: `code text` como clave primaria, `payload jsonb`, `updated_at timestamptz`.
- `catalog_import_rows`: clave primaria compuesta (`import_id`, `catalog_type`, `code`), `payload jsonb`, `created_at timestamptz`.
- `inventory_current`: clave primaria `id integer`, restricción `id = 1`, `items jsonb` con array vacío, `imported_at`, `imported_by`.
- `orders`: `id uuid`, `owner_id uuid`, `legacy_id text`, `legacy_source text`, `payload jsonb`, `updated_at timestamptz`. UNIQUE (`owner_id`, `legacy_source`, `legacy_id`).
- `profiles`: `id uuid`, `role text` limitado actualmente a `admin` y `seller`, `seller_label`, `created_at`.
- `seller_assignments`: `user_id uuid` como clave primaria, `seller_label`, `created_at`.

## 3. Forma JSONB observada

### Productos — catalog_items

Las claves observadas son: `b`, `c`, `d`, `g1`, `g2`, `g3`, `p1`, `p2`, `p3`, `sc`, `sd`.

### Clientes — catalog_clients

Las claves observadas son: `c`, `ciu`, `dep`, `dst`, `ident`, `n`, `tel`, `tip`.

### Pedidos — orders

Las claves observadas son: `cliente`, `clienteCiudad`, `clienteCodigo`, `condicion`, `createdAt`, `demo`, `estado`, `id`, `lines`, `total`, `updatedAt`, `vendedor`.

Se deben preservar los nombres y formatos existentes de estas claves durante la primera migración, hasta que el frontend y sus importadores se adapten y se prueben expresamente.

## 4. Hallazgos de arquitectura

1. Productos y clientes usan actualmente `code` como PK global. En multiempresa, dos empresas pueden necesitar el mismo código. La futura unicidad debe ser por empresa, por ejemplo UNIQUE (`company_id`, `code`), después de revisar dependencias y datos.
2. `catalog_import_rows` también requiere ámbito de empresa. Su clave lógica futura debe contemplar `company_id` junto con `import_id`, `catalog_type` y `code`.
3. El inventario actual es un único contenedor JSONB con `id = 1`. El inventario multiempresa real debe normalizarse en registros por empresa/producto y movimientos inmutables, no replicar el contenedor global.
4. Los pedidos están ligados a `owner_id`; la futura autorización debe combinar empresa y usuario autorizado, conservando propiedad y trazabilidad.
5. Los perfiles solo admiten `admin` y `seller`. El superadministrador global debe modelarse separadamente de los roles por empresa, protegido por backend y RLS; nunca permitir que el frontend se autoconceda privilegios.
6. El inventario JSONB está vacío y `catalog_import_rows` no contiene filas, lo que reduce la carga de migración inicial, pero no elimina la necesidad de copia de seguridad y validación.

## 5. Conservación de datos

- Conservar las 5 filas de productos, 4 de clientes, 1 pedido, 2 perfiles y 1 asignación de vendedor.
- No borrar ni recrear las tablas actuales como atajo.
- No asumir que la fila de `inventory_current` es stock: su array `items` está vacío.
- Antes de asignar registros existentes a una empresa inicial, definir explícitamente cuál será esa empresa DEMO y verificar la relación entre los dos perfiles, la asignación de vendedor y el pedido. No inferirla solo por conteos.

## 6. Próxima fase propuesta — todavía no ejecutada

1. Confirmar la empresa inicial de DEMO y el mapeo de usuarios existentes a membresías.
2. Preparar un diseño SQL revisable que incluya `companies`, `company_memberships` y un mecanismo separado para el rol global.
3. Diseñar el ámbito empresarial para productos, clientes, importaciones, pedidos y asignaciones.
4. Diseñar inventario normalizado por empresa/producto y tabla de movimientos append-only, con operación transaccional.
5. Definir políticas RLS por empresa y privilegios de superadmin mediante funciones seguras.
6. Preparar migración en fases con respaldo, validaciones, pruebas de aislamiento entre empresas y plan de reversión.
7. Adaptar el frontend DEMO solo después de acordar el esquema y las políticas.

## 7. Límites de este diagnóstico

- Los conteos, columnas, claves JSONB y restricciones se basan en los resultados compartidos por el usuario.
- Este documento no constituye una auditoría completa de seguridad ni prueba de RLS.
- No se ejecutó SQL de modificación, migración, GRANT, REVOKE ni cambios de datos.
- No se modificó Supabase de producción ni la aplicación de producción.
- No se abrió ni fusionó un PR ni se publicó la rama.

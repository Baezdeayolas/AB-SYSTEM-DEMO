-- ETAPA-2D-2-PREFLIGHT-DATOS-JSONB-SOLO-LECTURA.sql
-- Supabase DEMO exclusivamente. Ejecutar cada bloque por separado.
-- SOLO LECTURA: no contiene DDL, DML, GRANT, REVOKE ni cambios de datos.
-- No devuelve valores de clientes, productos, pedidos ni datos personales.

-- A) Conteos por tabla y existencia de filas.
SELECT 'catalog_clients' AS table_name, count(*) AS row_count FROM public.catalog_clients
UNION ALL SELECT 'catalog_items', count(*) FROM public.catalog_items
UNION ALL SELECT 'catalog_import_rows', count(*) FROM public.catalog_import_rows
UNION ALL SELECT 'inventory_current', count(*) FROM public.inventory_current
UNION ALL SELECT 'orders', count(*) FROM public.orders
UNION ALL SELECT 'seller_assignments', count(*) FROM public.seller_assignments
UNION ALL SELECT 'companies', count(*) FROM public.companies
UNION ALL SELECT 'company_memberships', count(*) FROM public.company_memberships
ORDER BY table_name;

-- B) Forma del JSONB de catálogo: tipo raíz y cantidad de claves, sin mostrar valores.
SELECT 'catalog_items' AS table_name, jsonb_typeof(payload) AS json_type,
       count(*) AS rows_count,
       min(jsonb_object_length(payload)) FILTER (WHERE jsonb_typeof(payload) = 'object') AS min_object_keys,
       max(jsonb_object_length(payload)) FILTER (WHERE jsonb_typeof(payload) = 'object') AS max_object_keys
FROM public.catalog_items GROUP BY jsonb_typeof(payload)
UNION ALL
SELECT 'catalog_clients', jsonb_typeof(payload), count(*),
       min(jsonb_object_length(payload)) FILTER (WHERE jsonb_typeof(payload) = 'object'),
       max(jsonb_object_length(payload)) FILTER (WHERE jsonb_typeof(payload) = 'object')
FROM public.catalog_clients GROUP BY jsonb_typeof(payload)
UNION ALL
SELECT 'inventory_current.items', jsonb_typeof(items), count(*),
       NULL::integer, NULL::integer
FROM public.inventory_current GROUP BY jsonb_typeof(items);

-- C) Forma del payload de pedidos: solo tipo raíz y cantidad de claves.
SELECT jsonb_typeof(payload) AS json_type, count(*) AS rows_count,
       min(jsonb_object_length(payload)) FILTER (WHERE jsonb_typeof(payload) = 'object') AS min_object_keys,
       max(jsonb_object_length(payload)) FILTER (WHERE jsonb_typeof(payload) = 'object') AS max_object_keys
FROM public.orders GROUP BY jsonb_typeof(payload);

-- D) Duplicados de códigos en tablas cuyo código hoy es PK (se espera cero filas).
SELECT 'catalog_items' AS table_name, code, count(*) AS duplicate_count
FROM public.catalog_items GROUP BY code HAVING count(*) > 1
UNION ALL
SELECT 'catalog_clients', code, count(*)
FROM public.catalog_clients GROUP BY code HAVING count(*) > 1;

-- E) Duplicados de clave de importación (se espera cero filas por la PK actual).
SELECT import_id, catalog_type, code, count(*) AS duplicate_count
FROM public.catalog_import_rows
GROUP BY import_id, catalog_type, code HAVING count(*) > 1;

-- F) Resumen de pedidos por legacy_source y presencia de owner_id; no expone UUID.
SELECT legacy_source, count(*) AS rows_count,
       count(*) FILTER (WHERE owner_id IS NULL) AS missing_owner_count
FROM public.orders GROUP BY legacy_source ORDER BY legacy_source;

-- G) Resumen de inventario actual; no expone el contenido JSONB.
SELECT count(*) AS inventory_rows,
       coalesce(sum(jsonb_array_length(items)) FILTER (WHERE jsonb_typeof(items) = 'array'), 0) AS array_item_count
FROM public.inventory_current;

-- H) Distribución de memberships por empresa/rol/estado (sin user_id).
SELECT company_id, role, status, count(*) AS members_count
FROM public.company_memberships
GROUP BY company_id, role, status
ORDER BY company_id, role, status;

-- I) Distribución de pedidos por propietario (conteos solamente; no muestra IDs).
SELECT count(DISTINCT owner_id) AS distinct_order_owners, count(*) AS total_orders
FROM public.orders;
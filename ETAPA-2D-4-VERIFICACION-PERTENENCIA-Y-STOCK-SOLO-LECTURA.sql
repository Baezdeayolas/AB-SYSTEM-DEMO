-- ETAPA-2D-4-VERIFICACION-PERTENENCIA-Y-STOCK-SOLO-LECTURA.sql
-- Supabase DEMO exclusivamente. Ejecutar cada bloque por separado.
-- SOLO LECTURA: no contiene DDL, DML, GRANT, REVOKE ni cambios de datos.
-- Los resultados agregan conteos/estados y no muestran UUID de usuarios ni valores de stock.

-- A) Comprueba si los propietarios de pedidos tienen membresía en la empresa KOEJU.
-- Devuelve conteos por origen y estado de membresía, sin exponer owner_id.
WITH target_company AS (
  SELECT id FROM public.companies WHERE code = 'KOEJU'
), order_memberships AS (
  SELECT o.id, o.legacy_source,
         cm.status AS membership_status, cm.role AS membership_role
  FROM public.orders AS o
  LEFT JOIN public.company_memberships AS cm
    ON cm.user_id = o.owner_id
   AND cm.company_id = (SELECT id FROM target_company)
)
SELECT legacy_source,
       count(*) AS orders_count,
       count(*) FILTER (WHERE membership_status = 'active') AS owners_with_active_membership,
       count(*) FILTER (WHERE membership_status = 'suspended') AS owners_with_suspended_membership,
       count(*) FILTER (WHERE membership_status IS NULL) AS owners_without_company_membership,
       count(*) FILTER (WHERE membership_status = 'active' AND membership_role = 'seller') AS active_seller_owners,
       count(*) FILTER (WHERE membership_status = 'active' AND membership_role = 'company_admin') AS active_admin_owners
FROM order_memberships
GROUP BY legacy_source
ORDER BY legacy_source;

-- B) Comprueba si el código de la aplicación usa claves de stock dentro de payload.
-- Informa únicamente presencia y tipos JSON de sc/sd; no muestra cantidades.
SELECT
  count(*) AS product_rows,
  count(*) FILTER (WHERE payload ? 'sc') AS rows_with_sc_key,
  count(*) FILTER (WHERE payload ? 'sd') AS rows_with_sd_key,
  count(*) FILTER (WHERE jsonb_typeof(payload->'sc') = 'number') AS sc_numeric_rows,
  count(*) FILTER (WHERE jsonb_typeof(payload->'sd') = 'number') AS sd_numeric_rows,
  count(*) FILTER (WHERE payload ? 'sc' AND jsonb_typeof(payload->'sc') <> 'number') AS sc_non_numeric_rows,
  count(*) FILTER (WHERE payload ? 'sd' AND jsonb_typeof(payload->'sd') <> 'number') AS sd_non_numeric_rows
FROM public.catalog_items;

-- C) Confirma únicamente la forma y el tamaño del documento inventory_current.
-- No muestra valores del array ni contenido de sus elementos.
SELECT
  count(*) AS inventory_rows,
  count(*) FILTER (WHERE jsonb_typeof(items) = 'array') AS rows_with_array_items,
  coalesce(sum(jsonb_array_length(items)) FILTER (WHERE jsonb_typeof(items) = 'array'), 0) AS total_array_elements
FROM public.inventory_current;

-- D) Confirma que existe una sola empresa con código KOEJU.
SELECT count(*) AS koeju_company_count
FROM public.companies
WHERE code = 'KOEJU';
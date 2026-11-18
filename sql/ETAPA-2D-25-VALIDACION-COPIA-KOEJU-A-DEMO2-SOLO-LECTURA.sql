-- ETAPA 2D-25 — VALIDACIÓN PREVIA KOEJU -> DEMO2 (SOLO LECTURA)
-- Ejecutar solo en Supabase AB-SYSTEM-DEMO. No devuelve valores personales ni modifica datos.

-- 1. Conteos por empresa y tabla.
WITH x AS (
 SELECT 'catalog_items' t,company_id,count(*) n FROM public.catalog_items GROUP BY company_id
 UNION ALL SELECT 'catalog_clients',company_id,count(*) FROM public.catalog_clients GROUP BY company_id
 UNION ALL SELECT 'catalog_import_rows',company_id,count(*) FROM public.catalog_import_rows GROUP BY company_id
 UNION ALL SELECT 'orders',company_id,count(*) FROM public.orders GROUP BY company_id
 UNION ALL SELECT 'seller_assignments',company_id,count(*) FROM public.seller_assignments GROUP BY company_id
)
SELECT c.code,c.name,c.status,c.id company_id,t.t,coalesce(x.n,0) row_count
FROM public.companies c CROSS JOIN (VALUES ('catalog_items'),('catalog_clients'),('catalog_import_rows'),('orders'),('seller_assignments')) t(t)
LEFT JOIN x ON x.company_id=c.id AND x.t=t.t
WHERE c.code IN ('KOEJU','DEMO2') ORDER BY c.code,t.t;

-- 2. Colisiones de códigos de producto entre origen y destino.
SELECT count(*) product_code_collisions
FROM public.catalog_items s
JOIN public.companies cs ON cs.id=s.company_id AND cs.code='KOEJU'
JOIN public.companies cd ON cd.code='DEMO2'
JOIN public.catalog_items d ON d.company_id=cd.id AND d.code=s.code;

-- 3. Calidad del payload de productos (solo conteos).
SELECT count(*) source_products,
 count(*) FILTER(WHERE payload IS NULL OR jsonb_typeof(payload)<>'object') invalid_payloads,
 count(*) FILTER(WHERE NOT(payload?'d')) missing_description_key,
 count(*) FILTER(WHERE NOT(payload?'p1')) missing_price1_key,
 count(*) FILTER(WHERE NOT(payload?'p2')) missing_price2_key,
 count(*) FILTER(WHERE NOT(payload?'p3')) missing_price3_key
FROM public.catalog_items i JOIN public.companies c ON c.id=i.company_id WHERE c.code='KOEJU';

-- 4. Campos sensibles presentes en clientes (nunca muestra valores).
SELECT count(*) source_clients,
 count(*) FILTER(WHERE payload?'n') name_key,
 count(*) FILTER(WHERE payload?'ident') identity_key,
 count(*) FILTER(WHERE payload?'tel') phone_key,
 count(*) FILTER(WHERE payload?'ciu' OR payload?'dep' OR payload?'dst') location_keys,
 count(*) FILTER(WHERE payload?'ctaCbleDeuda' OR payload?'saldoActExt' OR payload?'saldoActGs') financial_keys
FROM public.catalog_clients i JOIN public.companies c ON c.id=i.company_id WHERE c.code='KOEJU';

-- 5. Estado de tablas e indicadores RLS.
SELECT v.t, to_regclass('public.'||v.t) IS NOT NULL exists,
 coalesce(pc.relrowsecurity,false) rls_enabled,coalesce(pc.relforcerowsecurity,false) rls_forced
FROM (VALUES('inventory_location_balances'),('inventory_location_movements'),('inventory_current')) v(t)
LEFT JOIN pg_class pc ON pc.oid=to_regclass('public.'||v.t);

-- 6. RPC esperadas por el frontend.
SELECT p.proname,pg_get_function_identity_arguments(p.oid) arguments,p.prosecdef security_definer
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN
('ab_set_inventory_location_balance','ab_import_company_catalog_v2','ab_is_global_superadmin','ab_is_company_admin','ab_has_company_access')
ORDER BY p.proname,arguments;

-- 7. Políticas RLS instaladas en tablas críticas.
SELECT tablename,policyname,permissive,roles,cmd FROM pg_policies
WHERE schemaname='public' AND tablename IN
('companies','company_memberships','catalog_items','catalog_clients','catalog_import_rows','orders','seller_assignments','inventory_location_balances','inventory_location_movements','inventory_current')
ORDER BY tablename,policyname;

-- 8. Triggers instalados en tablas críticas.
SELECT event_object_table table_name,trigger_name,action_timing,event_manipulation
FROM information_schema.triggers WHERE trigger_schema='public' AND event_object_table IN
('catalog_items','catalog_clients','catalog_import_rows','orders','seller_assignments','inventory_location_balances','inventory_location_movements','inventory_current')
ORDER BY event_object_table,trigger_name,event_manipulation;

-- 9. Membresías por rol/estado, sin identificar usuarios.
SELECT c.code,m.role,m.status,count(*) memberships
FROM public.company_memberships m JOIN public.companies c ON c.id=m.company_id
WHERE c.code IN ('KOEJU','DEMO2') GROUP BY c.code,m.role,m.status ORDER BY c.code,m.role,m.status;

-- 10. Conteos resumidos de origen y destino para confirmar invariantes.
SELECT
 (SELECT count(*) FROM public.catalog_items i JOIN public.companies c ON c.id=i.company_id WHERE c.code='KOEJU') source_products,
 (SELECT count(*) FROM public.catalog_items i JOIN public.companies c ON c.id=i.company_id WHERE c.code='DEMO2') destination_products,
 (SELECT count(*) FROM public.catalog_clients i JOIN public.companies c ON c.id=i.company_id WHERE c.code='KOEJU') source_clients,
 (SELECT count(*) FROM public.catalog_clients i JOIN public.companies c ON c.id=i.company_id WHERE c.code='DEMO2') destination_clients,
 (SELECT count(*) FROM public.orders i JOIN public.companies c ON c.id=i.company_id WHERE c.code='KOEJU') source_orders,
 (SELECT count(*) FROM public.orders i JOIN public.companies c ON c.id=i.company_id WHERE c.code='DEMO2') destination_orders;

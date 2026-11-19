-- ETAPA 2D-13 — PREFLIGHT MULTIEMPRESA (SOLO LECTURA)
-- Ejecutar únicamente en AB-SYSTEM-DEMO.
-- No crea/modifica objetos ni datos. No copiar resultados que contengan información sensible.
BEGIN TRANSACTION READ ONLY;

-- 1) Columnas de las tablas comerciales y de autorización.
SELECT table_name, ordinal_position, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
    'companies','company_memberships','global_roles','profiles',
    'catalog_items','catalog_clients','catalog_import_rows',
    'inventory_current','orders','seller_assignments'
  )
ORDER BY table_name, ordinal_position;

-- 2) PK, UNIQUE, FK, CHECK y demás restricciones.
SELECT c.conrelid::regclass AS table_name,
       c.conname AS constraint_name,
       CASE c.contype
         WHEN 'p' THEN 'PRIMARY KEY'
         WHEN 'u' THEN 'UNIQUE'
         WHEN 'f' THEN 'FOREIGN KEY'
         WHEN 'c' THEN 'CHECK'
         WHEN 'x' THEN 'EXCLUSION'
         ELSE c.contype::text
       END AS constraint_type,
       pg_get_constraintdef(c.oid, true) AS definition,
       c.convalidated AS is_validated
FROM pg_constraint c
JOIN pg_namespace n ON n.oid = c.connamespace
WHERE n.nspname = 'public'
  AND c.conrelid IN (
    'public.companies'::regclass,'public.company_memberships'::regclass,
    'public.global_roles'::regclass,'public.profiles'::regclass,
    'public.catalog_items'::regclass,'public.catalog_clients'::regclass,
    'public.catalog_import_rows'::regclass,'public.inventory_current'::regclass,
    'public.orders'::regclass,'public.seller_assignments'::regclass
  )
ORDER BY 1, 2;

-- 3) Índices existentes.
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
    'companies','company_memberships','global_roles','profiles',
    'catalog_items','catalog_clients','catalog_import_rows',
    'inventory_current','orders','seller_assignments'
  )
ORDER BY tablename, indexname;

-- 4) Estado RLS y FORCE RLS.
SELECT c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname IN (
    'companies','company_memberships','global_roles','profiles',
    'catalog_items','catalog_clients','catalog_import_rows',
    'inventory_current','orders','seller_assignments'
  )
ORDER BY c.relname;

-- 5) Políticas RLS activas (incluye USING/WITH CHECK).
SELECT schemaname, tablename, policyname, permissive, roles,
       cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'companies','company_memberships','global_roles','profiles',
    'catalog_items','catalog_clients','catalog_import_rows',
    'inventory_current','orders','seller_assignments'
  )
ORDER BY tablename, policyname;

-- 6) Triggers no internos en tablas relevantes y auth.users.
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       t.tgname AS trigger_name,
       pg_get_triggerdef(t.oid, true) AS trigger_definition,
       pn.nspname AS function_schema,
       p.proname AS function_name
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_proc p ON p.oid = t.tgfoid
JOIN pg_namespace pn ON pn.oid = p.pronamespace
WHERE NOT t.tgisinternal
  AND (
    (n.nspname = 'public' AND c.relname IN (
      'companies','company_memberships','global_roles','profiles',
      'catalog_items','catalog_clients','catalog_import_rows',
      'inventory_current','orders','seller_assignments'
    ))
    OR (n.nspname = 'auth' AND c.relname = 'users')
  )
ORDER BY schema_name, table_name, trigger_name;

-- 7) Resumen de empresas (sin UUID ni datos personales).
SELECT code, status, count(*) AS rows_with_same_code
FROM public.companies
GROUP BY code, status
ORDER BY code, status;

-- 8) Resumen de membresías por empresa/rol/estado (sin user_id).
SELECT c.code AS company_code, m.role, m.status, count(*) AS membership_count
FROM public.company_memberships m
JOIN public.companies c ON c.id = m.company_id
GROUP BY c.code, m.role, m.status
ORDER BY c.code, m.role, m.status;

-- 9) Conteos exactos de las tablas comerciales (sin extraer payloads).
SELECT 'catalog_items' AS table_name, count(*) AS row_count FROM public.catalog_items
UNION ALL SELECT 'catalog_clients', count(*) FROM public.catalog_clients
UNION ALL SELECT 'catalog_import_rows', count(*) FROM public.catalog_import_rows
UNION ALL SELECT 'inventory_current', count(*) FROM public.inventory_current
UNION ALL SELECT 'orders', count(*) FROM public.orders
UNION ALL SELECT 'seller_assignments', count(*) FROM public.seller_assignments
ORDER BY table_name;

-- 10) Verifica si las tablas comerciales ya tienen columnas empresariales.
SELECT table_name,
       bool_or(column_name = 'company_id') AS has_company_id,
       bool_or(column_name = 'created_by') AS has_created_by
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
    'catalog_items','catalog_clients','catalog_import_rows',
    'inventory_current','orders','seller_assignments'
  )
GROUP BY table_name
ORDER BY table_name;

-- 11) Tablas actualmente incluidas en Realtime.
SELECT schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
ORDER BY schemaname, tablename;

COMMIT;

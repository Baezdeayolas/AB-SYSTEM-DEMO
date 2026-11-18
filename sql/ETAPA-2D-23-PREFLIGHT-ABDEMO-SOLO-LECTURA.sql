-- ETAPA 2D-23 — PREFLIGHT AB SYSTEM DEMO (SOLO LECTURA)
-- Ejecutar únicamente en el proyecto Supabase DEMO existente.
-- Todas las sentencias son SELECT. No modifica datos, permisos ni esquema.
-- No copiar ni compartir datos personales; este preflight devuelve metadatos y conteos.

-- 1) Columnas reales de las tablas empresariales y comerciales.
SELECT table_schema, table_name, ordinal_position, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
    'companies',
    'company_memberships',
    'catalog_items',
    'catalog_clients',
    'catalog_import_rows',
    'orders',
    'seller_assignments',
    'inventory_current',
    'profiles'
  )
ORDER BY table_name, ordinal_position;

-- 2) Restricciones de empresas y tablas comerciales.
SELECT
  conrelid::regclass AS table_name,
  conname AS constraint_name,
  contype AS constraint_type,
  pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
  AND (
    conrelid IN (
      to_regclass('public.companies'),
      to_regclass('public.company_memberships'),
      to_regclass('public.catalog_items'),
      to_regclass('public.catalog_clients'),
      to_regclass('public.catalog_import_rows'),
      to_regclass('public.orders'),
      to_regclass('public.seller_assignments')
    )
    OR confrelid = to_regclass('public.companies')
  )
ORDER BY table_name::text, constraint_type, constraint_name;

-- 3) Índices únicos de companies y tablas relacionadas.
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
    'companies',
    'company_memberships',
    'catalog_items',
    'catalog_clients',
    'catalog_import_rows',
    'orders',
    'seller_assignments'
  )
ORDER BY tablename, indexname;

-- 4) Empresas actuales: lectura tolerante a diferencias de columnas.
-- to_jsonb evita que la consulta falle si name/status aún no existen.
SELECT
  to_jsonb(c)->>'id' AS company_id,
  to_jsonb(c)->>'code' AS company_code,
  to_jsonb(c)->>'name' AS company_name,
  to_jsonb(c)->>'status' AS company_status
FROM public.companies c
ORDER BY to_jsonb(c)->>'code';

-- 5) Membresías resumidas, sin nombres, correos ni identificadores de usuarios.
SELECT c.code AS company_code, m.role, m.status, count(*) AS memberships
FROM public.company_memberships m
JOIN public.companies c ON c.id = m.company_id
GROUP BY c.code, m.role, m.status
ORDER BY c.code, m.role, m.status;

-- 6) Conteos generales, sin devolver filas ni contenido de clientes/pedidos.
SELECT 'catalog_items' AS table_name, count(*) AS row_count FROM public.catalog_items
UNION ALL SELECT 'catalog_clients', count(*) FROM public.catalog_clients
UNION ALL SELECT 'catalog_import_rows', count(*) FROM public.catalog_import_rows
UNION ALL SELECT 'orders', count(*) FROM public.orders
UNION ALL SELECT 'seller_assignments', count(*) FROM public.seller_assignments
UNION ALL SELECT 'inventory_current', count(*) FROM public.inventory_current
ORDER BY table_name;

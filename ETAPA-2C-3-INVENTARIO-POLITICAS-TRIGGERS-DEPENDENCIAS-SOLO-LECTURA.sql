-- Etapa 2C.3 — inventario de políticas, triggers, vistas y dependencias
-- SOLO LECTURA. Ejecutar exclusivamente en Supabase DEMO.
-- No contiene DDL, DML, GRANT ni REVOKE.
-- Ejecutar como rol administrativo para obtener la mayor visibilidad posible.

-- A. Todas las políticas RLS de public: comando, roles, modo y expresiones.
SELECT
  schemaname, tablename, policyname, permissive, roles, cmd,
  qual AS using_expression,
  with_check AS with_check_expression
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;

-- B. Estado RLS de las tablas de public y propietario.
SELECT
  n.nspname AS schema_name, c.relname AS table_name,
  pg_get_userbyid(c.relowner) AS table_owner,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
ORDER BY c.relname;

-- C. Triggers no internos en public y en auth.users.
-- Incluye definición y función invocada para detectar automatizaciones.
SELECT
  trigger_ns.nspname AS trigger_schema,
  table_ns.nspname AS table_schema,
  table_class.relname AS table_name,
  trigger_row.tgname AS trigger_name,
  pg_get_triggerdef(trigger_row.oid, true) AS trigger_definition,
  function_ns.nspname AS function_schema,
  function_row.proname AS function_name,
  pg_get_function_identity_arguments(function_row.oid) AS function_arguments,
  pg_get_userbyid(function_row.proowner) AS function_owner,
  function_row.prosecdef AS security_definer,
  function_row.proconfig AS function_settings,
  pg_get_functiondef(function_row.oid) AS function_definition
FROM pg_trigger trigger_row
JOIN pg_class table_class ON table_class.oid = trigger_row.tgrelid
JOIN pg_namespace table_ns ON table_ns.oid = table_class.relnamespace
JOIN pg_namespace trigger_ns ON trigger_ns.oid = table_ns.oid
JOIN pg_proc function_row ON function_row.oid = trigger_row.tgfoid
JOIN pg_namespace function_ns ON function_ns.oid = function_row.pronamespace
WHERE NOT trigger_row.tgisinternal
  AND (table_ns.nspname = 'public' OR (table_ns.nspname = 'auth' AND table_class.relname = 'users'))
ORDER BY table_ns.nspname, table_class.relname, trigger_row.tgname;

-- D. Vistas y vistas materializadas de public, con definición y opciones de seguridad.
SELECT
  n.nspname AS schema_name,
  c.relname AS view_name,
  CASE c.relkind WHEN 'v' THEN 'view' WHEN 'm' THEN 'materialized_view' END AS object_type,
  pg_get_userbyid(c.relowner) AS object_owner,
  CASE WHEN c.relkind = 'v' THEN pg_get_viewdef(c.oid, true) ELSE NULL END AS view_definition,
  c.reloptions AS relation_options
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('v', 'm')
ORDER BY c.relname;

-- E. Dependencias de vistas sobre tablas/objetos de public.
-- Una fila por objeto referenciado por una vista.
SELECT DISTINCT
  view_ns.nspname AS view_schema,
  view_class.relname AS view_name,
  referenced_ns.nspname AS referenced_schema,
  referenced_class.relname AS referenced_object,
  referenced_class.relkind AS referenced_object_kind
FROM pg_rewrite rewrite_row
JOIN pg_class view_class ON view_class.oid = rewrite_row.ev_class
JOIN pg_namespace view_ns ON view_ns.oid = view_class.relnamespace
JOIN pg_depend dependency_row ON dependency_row.classid = 'pg_rewrite'::regclass
  AND dependency_row.objid = rewrite_row.oid
JOIN pg_class referenced_class ON referenced_class.oid = dependency_row.refobjid
JOIN pg_namespace referenced_ns ON referenced_ns.oid = referenced_class.relnamespace
WHERE view_ns.nspname = 'public'
  AND referenced_ns.nspname = 'public'
  AND view_class.relkind IN ('v', 'm')
  AND referenced_class.oid <> view_class.oid
ORDER BY view_name, referenced_object;

-- F. Constraints y claves foráneas de las tablas comerciales legacy y multiempresa.
SELECT
  table_ns.nspname AS schema_name,
  table_class.relname AS table_name,
  constraint_row.conname AS constraint_name,
  constraint_row.contype AS constraint_type,
  pg_get_constraintdef(constraint_row.oid, true) AS constraint_definition,
  constraint_row.convalidated AS is_validated
FROM pg_constraint constraint_row
JOIN pg_class table_class ON table_class.oid = constraint_row.conrelid
JOIN pg_namespace table_ns ON table_ns.oid = table_class.relnamespace
WHERE table_ns.nspname = 'public'
  AND table_class.relname IN (
    'catalog_clients', 'catalog_import_rows', 'catalog_items',
    'inventory_current', 'orders', 'profiles', 'seller_assignments',
    'companies', 'company_memberships', 'global_roles'
  )
ORDER BY table_class.relname, constraint_row.conname;

-- G. Columnas de las tablas comerciales: tipo, nullability y default.
SELECT
  table_class.relname AS table_name,
  attribute_row.attnum AS ordinal_position,
  attribute_row.attname AS column_name,
  format_type(attribute_row.atttypid, attribute_row.atttypmod) AS data_type,
  NOT attribute_row.attnotnull AS is_nullable,
  pg_get_expr(default_row.adbin, default_row.adrelid) AS column_default
FROM pg_attribute attribute_row
JOIN pg_class table_class ON table_class.oid = attribute_row.attrelid
JOIN pg_namespace table_ns ON table_ns.oid = table_class.relnamespace
LEFT JOIN pg_attrdef default_row
  ON default_row.adrelid = table_class.oid AND default_row.adnum = attribute_row.attnum
WHERE table_ns.nspname = 'public'
  AND table_class.relname IN (
    'catalog_clients', 'catalog_import_rows', 'catalog_items',
    'inventory_current', 'orders', 'profiles', 'seller_assignments',
    'companies', 'company_memberships', 'global_roles'
  )
  AND attribute_row.attnum > 0
  AND NOT attribute_row.attisdropped
ORDER BY table_class.relname, attribute_row.attnum;

-- Interpretación:
-- * El bloque A identifica políticas permisivas que pueden ampliar acceso por OR.
-- * El bloque C permite preservar triggers de autenticación y automatizaciones de negocio.
-- * Los bloques D-E identifican vistas y dependencias declaradas; no detectan referencias dinámicas construidas en SQL/PLpgSQL.
-- * Los bloques F-G ayudan a preparar una migración compatible y un backfill correcto.
-- * Compartir resultados completos, indicando si algún bloque produjo error.
-- * No aplicar cambios de permisos o estructura basándose solo en este inventario.
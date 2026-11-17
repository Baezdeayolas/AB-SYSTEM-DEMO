-- ETAPA 2D-9 — PREFLIGHT DE DEPENDENCIAS Y ESCRITORES (SOLO LECTURA)
-- Ejecutar manualmente SOLO en Supabase DEMO. No contiene DDL/DML.
-- No ejecutar en producción. Revisar resultados antes de diseñar cualquier migración.

-- A. Triggers no internos en tablas comerciales y de autorización
SELECT n.nspname AS schema_name, c.relname AS table_name, t.tgname AS trigger_name,
       pg_get_triggerdef(t.oid, true) AS trigger_definition,
       pn.nspname AS function_schema, p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS function_arguments,
       p.prosecdef AS security_definer, p.proconfig AS function_settings
FROM pg_trigger t
JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN pg_proc p ON p.oid=t.tgfoid
JOIN pg_namespace pn ON pn.oid=p.pronamespace
WHERE NOT t.tgisinternal
  AND n.nspname='public'
  AND c.relname IN ('catalog_items','catalog_clients','catalog_import_rows','inventory_current','orders','profiles','seller_assignments','companies','company_memberships','global_roles')
ORDER BY c.relname,t.tgname;

-- B. Funciones públicas que mencionan tablas/columnas comerciales conocidas.
-- Es una búsqueda textual de pistas, no prueba completa de dependencias dinámicas.
SELECT n.nspname AS schema_name, p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       p.prosecdef AS security_definer, p.proconfig AS function_settings,
       pg_get_userbyid(p.proowner) AS owner,
       has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prokind IN ('f','p','w')
  AND (pg_get_functiondef(p.oid) ILIKE '%catalog_items%'
    OR pg_get_functiondef(p.oid) ILIKE '%catalog_clients%'
    OR pg_get_functiondef(p.oid) ILIKE '%inventory_current%'
    OR pg_get_functiondef(p.oid) ILIKE '%catalog_import_rows%'
    OR pg_get_functiondef(p.oid) ILIKE '%orders%')
ORDER BY p.proname;

-- C. Políticas actuales de las tablas comerciales
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname='public'
  AND tablename IN ('catalog_items','catalog_clients','catalog_import_rows','inventory_current','orders','profiles','seller_assignments','companies','company_memberships','global_roles')
ORDER BY tablename,policyname;

-- D. Estado RLS y FORCE RLS
SELECT n.nspname AS schema_name,c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,c.relforcerowsecurity AS force_rls
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r'
  AND c.relname IN ('catalog_items','catalog_clients','catalog_import_rows','inventory_current','orders','profiles','seller_assignments','companies','company_memberships','global_roles')
ORDER BY c.relname;

-- E. Vistas y vistas materializadas que referencian objetos comerciales
SELECT schemaname,viewname,definition FROM pg_views
WHERE schemaname='public'
  AND (definition ILIKE '%catalog_items%' OR definition ILIKE '%catalog_clients%'
    OR definition ILIKE '%inventory_current%' OR definition ILIKE '%orders%')
ORDER BY viewname;
SELECT schemaname,matviewname,definition FROM pg_matviews
WHERE schemaname='public'
  AND (definition ILIKE '%catalog_items%' OR definition ILIKE '%catalog_clients%'
    OR definition ILIKE '%inventory_current%' OR definition ILIKE '%orders%')
ORDER BY matviewname;

-- F. Triggers de auth.users y otras tablas fuera del esquema public
SELECT n.nspname AS schema_name,c.relname AS table_name,t.tgname AS trigger_name,
       pg_get_triggerdef(t.oid,true) AS trigger_definition,
       pn.nspname AS function_schema,p.proname AS function_name
FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
JOIN pg_proc p ON p.oid=t.tgfoid JOIN pg_namespace pn ON pn.oid=p.pronamespace
WHERE NOT t.tgisinternal AND (n.nspname='auth' OR n.nspname='public')
ORDER BY n.nspname,c.relname,t.tgname;

-- G. Extensiones y publicaciones (contexto de integraciones/replicación)
SELECT extname,extversion FROM pg_extension ORDER BY extname;
SELECT pubname,puballtables,pubinsert,pubupdate,pubdelete,pubtruncate
FROM pg_publication ORDER BY pubname;

-- H. Estado de las tablas y conteos aproximados desde estadísticas
SELECT schemaname,relname,n_live_tup,n_mod_since_analyze,last_analyze,last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname='public'
  AND relname IN ('catalog_items','catalog_clients','catalog_import_rows','inventory_current','orders','companies','company_memberships','global_roles')
ORDER BY relname;

-- LIMITACIONES:
-- 1) No detecta necesariamente procesos externos, clientes directos, Edge Functions fuera de esta BD,
--    tareas programadas externas ni SQL dinámico que construya nombres de tabla.
-- 2) No demuestra que exista un backup restaurable. Backup/restore debe verificarse en Supabase.
-- 3) No ejecuta cambios ni prueba permisos JWT de usuarios reales.
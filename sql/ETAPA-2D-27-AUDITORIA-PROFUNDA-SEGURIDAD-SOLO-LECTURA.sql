-- ETAPA 2D-27 — AUDITORÍA PROFUNDA DE SEGURIDAD AB-SYSTEM-DEMO (SOLO LECTURA)
-- Ejecutar únicamente en el proyecto Supabase AB-SYSTEM-DEMO.
-- Todas las sentencias son SELECT. No modifica datos, políticas, funciones, permisos ni triggers.
-- IMPORTANTE: revisar las definiciones antes de compartir resultados y ocultar cualquier secreto
-- que accidentalmente estuviera escrito como literal en código SQL.

-- 1. Definición completa de políticas RLS: condiciones USING y WITH CHECK.
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual AS using_expression,
       with_check AS with_check_expression
FROM pg_policies
WHERE schemaname='public'
  AND tablename IN ('companies','company_memberships','catalog_items','catalog_clients',
    'catalog_import_rows','orders','seller_assignments','inventory_location_balances',
    'inventory_location_movements','inventory_current')
ORDER BY tablename, policyname;

-- 2. Definiciones de las funciones RPC SECURITY DEFINER relevantes.
-- Incluye propietario, configuración search_path, permisos efectivos y código fuente.
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS arguments,
       pg_get_userbyid(p.proowner) AS function_owner,
       p.prosecdef AS security_definer,
       p.proconfig AS function_settings,
       r.rolname AS checked_role,
       has_function_privilege(r.rolname,p.oid,'EXECUTE') AS can_execute,
       pg_get_functiondef(p.oid) AS function_definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
CROSS JOIN pg_roles r
WHERE n.nspname='public'
  AND p.proname IN ('ab_has_company_access','ab_import_company_catalog_v2',
    'ab_is_company_admin','ab_is_global_superadmin','ab_set_inventory_location_balance')
  AND r.rolname IN ('anon','authenticated','service_role')
ORDER BY p.proname, arguments, r.rolname;

-- 3. Definiciones de triggers y código de sus funciones asociadas.
SELECT c.relname AS table_name, t.tgname AS trigger_name,
       pg_get_triggerdef(t.oid,true) AS trigger_definition,
       pn.nspname AS function_schema, p.proname AS trigger_function,
       pg_get_userbyid(p.proowner) AS function_owner,
       p.prosecdef AS function_security_definer,
       p.proconfig AS function_settings,
       pg_get_functiondef(p.oid) AS trigger_function_definition
FROM pg_trigger t
JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace cn ON cn.oid=c.relnamespace
JOIN pg_proc p ON p.oid=t.tgfoid
JOIN pg_namespace pn ON pn.oid=p.pronamespace
WHERE cn.nspname='public' AND NOT t.tgisinternal
  AND c.relname IN ('catalog_items','catalog_clients','catalog_import_rows','orders',
    'seller_assignments','inventory_location_balances','inventory_location_movements','inventory_current')
ORDER BY c.relname,t.tgname;

-- 4. Estructura de inventario: columnas, claves y presencia de company_id.
SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public'
  AND table_name IN ('inventory_location_balances','inventory_location_movements','inventory_current')
ORDER BY table_name, ordinal_position;

-- 5. RLS y propietario de las tablas sensibles.
SELECT c.relname AS table_name, pg_get_userbyid(c.relowner) AS table_owner,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind IN ('r','p')
  AND c.relname IN ('companies','company_memberships','catalog_items','catalog_clients',
    'catalog_import_rows','orders','seller_assignments','inventory_location_balances',
    'inventory_location_movements','inventory_current')
ORDER BY c.relname;

-- 6. Privilegios SQL directos sobre tablas críticas para anon/authenticated/service_role.
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema='public'
  AND table_name IN ('companies','company_memberships','catalog_items','catalog_clients',
    'catalog_import_rows','orders','seller_assignments','inventory_location_balances',
    'inventory_location_movements','inventory_current')
  AND grantee IN ('anon','authenticated','service_role')
ORDER BY table_name,grantee,privilege_type;

-- 7. Confirmación de roles de membresía por empresa, solo cantidades y sin datos de usuarios.
SELECT c.code,m.role,m.status,count(*) AS memberships
FROM public.company_memberships m
JOIN public.companies c ON c.id=m.company_id
WHERE c.code IN ('KOEJU','DEMO2')
GROUP BY c.code,m.role,m.status
ORDER BY c.code,m.role,m.status;

-- 8. Comprobación de unicidad de empresa DEMO2 y KOEJU (solo conteos).
SELECT code,count(*) AS company_records
FROM public.companies
WHERE code IN ('KOEJU','DEMO2')
GROUP BY code
ORDER BY code;

-- FIN: auditoría exclusivamente de lectura. No ejecutar migraciones ni scripts de copia.

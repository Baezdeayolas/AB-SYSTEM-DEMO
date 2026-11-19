-- Etapa 2C.1 — inventario de privilegios efectivos actuales
-- SOLO LECTURA. Ejecutar exclusivamente en Supabase DEMO.
-- No contiene DDL, DML, GRANT ni REVOKE.
-- Ejecutar como rol administrativo para obtener la mayor visibilidad posible.

-- A. Privilegios efectivos sobre el esquema public.
-- has_schema_privilege considera privilegios efectivos del rol consultado.
WITH target_roles(role_name) AS (
  VALUES ('anon'), ('authenticated'), ('service_role'), ('postgres'), ('supabase_admin')
), schema_privileges(privilege_name) AS (
  VALUES ('USAGE'), ('CREATE')
)
SELECT
  r.role_name,
  'public' AS schema_name,
  p.privilege_name,
  has_schema_privilege(r.role_name, 'public', p.privilege_name) AS is_effectively_granted
FROM target_roles AS r
CROSS JOIN schema_privileges AS p
ORDER BY r.role_name, p.privilege_name;

-- B. Privilegios efectivos por tabla, vista, vista materializada y tabla particionada.
-- Incluye tablas de usuario y objetos visibles en public; no modifica nada.
WITH target_roles(role_name) AS (
  VALUES ('anon'), ('authenticated'), ('service_role'), ('postgres'), ('supabase_admin')
), relation_privileges(privilege_name) AS (
  VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')
)
SELECT
  n.nspname AS schema_name,
  c.relname AS object_name,
  CASE c.relkind
    WHEN 'r' THEN 'table'
    WHEN 'p' THEN 'partitioned_table'
    WHEN 'v' THEN 'view'
    WHEN 'm' THEN 'materialized_view'
    WHEN 'f' THEN 'foreign_table'
    ELSE c.relkind::text
  END AS object_type,
  r.role_name,
  p.privilege_name,
  has_table_privilege(r.role_name, c.oid, p.privilege_name) AS is_effectively_granted,
  pg_get_userbyid(c.relowner) AS object_owner,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS force_rls
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN target_roles AS r
CROSS JOIN relation_privileges AS p
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
ORDER BY object_type, object_name, r.role_name, p.privilege_name;

-- C. Privilegio EXECUTE efectivo por función/procedimiento y rol.
-- SECURITY DEFINER requiere revisión especial; esta consulta no cambia ACL.
WITH target_roles(role_name) AS (
  VALUES ('anon'), ('authenticated'), ('service_role'), ('postgres'), ('supabase_admin')
)
SELECT
  n.nspname AS schema_name,
  p.proname AS routine_name,
  pg_get_function_identity_arguments(p.oid) AS identity_arguments,
  CASE p.prokind
    WHEN 'f' THEN 'function'
    WHEN 'p' THEN 'procedure'
    WHEN 'a' THEN 'aggregate'
    WHEN 'w' THEN 'window_function'
    ELSE p.prokind::text
  END AS routine_type,
  r.role_name,
  has_function_privilege(r.role_name, p.oid, 'EXECUTE') AS execute_effectively_granted,
  p.prosecdef AS security_definer,
  p.provolatile AS volatility,
  pg_get_userbyid(p.proowner) AS routine_owner,
  p.proconfig AS function_settings,
  pg_get_functiondef(p.oid) AS routine_definition
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
CROSS JOIN target_roles AS r
WHERE n.nspname = 'public'
ORDER BY routine_name, identity_arguments, r.role_name;

-- D. Privilegios efectivos sobre secuencias en public.
WITH target_roles(role_name) AS (
  VALUES ('anon'), ('authenticated'), ('service_role'), ('postgres'), ('supabase_admin')
), sequence_privileges(privilege_name) AS (
  VALUES ('USAGE'), ('SELECT'), ('UPDATE')
)
SELECT
  c.relname AS sequence_name,
  r.role_name,
  p.privilege_name,
  has_sequence_privilege(r.role_name, c.oid, p.privilege_name) AS is_effectively_granted,
  pg_get_userbyid(c.relowner) AS sequence_owner
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN target_roles AS r
CROSS JOIN sequence_privileges AS p
WHERE n.nspname = 'public'
  AND c.relkind = 'S'
ORDER BY sequence_name, r.role_name, p.privilege_name;

-- E. Membresías de roles relevantes: ayuda a interpretar privilegios heredados.
-- La comprobación efectiva principal está en has_*_privilege de los bloques anteriores.
SELECT
  member_role.rolname AS member_role,
  granted_role.rolname AS granted_role,
  am.admin_option
FROM pg_auth_members AS am
JOIN pg_roles AS granted_role ON granted_role.oid = am.roleid
JOIN pg_roles AS member_role ON member_role.oid = am.member
WHERE member_role.rolname IN ('anon', 'authenticated', 'service_role', 'postgres', 'supabase_admin')
   OR granted_role.rolname IN ('anon', 'authenticated', 'service_role', 'postgres', 'supabase_admin')
ORDER BY member_role, granted_role;

-- Interpretación:
-- * has_*_privilege reporta privilegios efectivos, incluidos PUBLIC y membresías aplicables.
-- * Los bloques B-D pueden devolver muchas filas; compartir resultados completos o por bloque.
-- * La definición de rutinas puede ser extensa y contener lógica sensible; compartirla solo en este chat.
-- * Un privilegio efectivo no implica por sí solo que RLS permita acceder a filas.
-- * No aplicar cambios basándose solo en este inventario: primero revisar resultados y dependencias.
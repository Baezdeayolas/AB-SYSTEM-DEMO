-- Etapa 2C.1-B — resumen compacto de privilegios efectivos por tabla
-- SOLO LECTURA. Ejecutar exclusivamente en Supabase DEMO.
-- No contiene DDL, DML, GRANT ni REVOKE.

WITH target_roles(role_name) AS (
  VALUES ('anon'), ('authenticated'), ('service_role'), ('postgres'), ('supabase_admin')
), relation_privileges(privilege_name) AS (
  VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')
), inventory AS (
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
    pg_get_userbyid(c.relowner) AS object_owner,
    c.relrowsecurity AS rls_enabled,
    c.relforcerowsecurity AS force_rls,
    r.role_name,
    p.privilege_name,
    has_table_privilege(r.role_name, c.oid, p.privilege_name) AS granted
  FROM pg_class AS c
  JOIN pg_namespace AS n ON n.oid = c.relnamespace
  CROSS JOIN target_roles AS r
  CROSS JOIN relation_privileges AS p
  WHERE n.nspname = 'public'
    AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
)
SELECT
  schema_name,
  object_name,
  object_type,
  object_owner,
  rls_enabled,
  force_rls,
  role_name,
  string_agg(privilege_name, ', ' ORDER BY privilege_name) FILTER (WHERE granted) AS effective_privileges
FROM inventory
GROUP BY schema_name, object_name, object_type, object_owner, rls_enabled, force_rls, role_name
ORDER BY object_type, object_name, role_name;

-- La columna effective_privileges lista solo privilegios efectivos.
-- Una cadena vacía/NULL indica que el rol no tiene ninguno de los privilegios consultados.
-- Compartir el resultado completo; es mucho más compacto que el bloque B original.
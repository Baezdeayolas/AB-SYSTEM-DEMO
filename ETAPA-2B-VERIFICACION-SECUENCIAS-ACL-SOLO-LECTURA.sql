-- Etapa 2B — verificación directa de secuencias y ACL predeterminadas
-- SOLO LECTURA. Ejecutar exclusivamente en Supabase DEMO.
-- No contiene DDL, DML, GRANT ni REVOKE.

-- A. Todas las secuencias del esquema public, su propietario y ACL efectiva.
SELECT
  n.nspname AS schema_name,
  c.relname AS sequence_name,
  pg_get_userbyid(c.relowner) AS owner,
  COALESCE(c.relacl, acldefault('S', c.relowner)) AS effective_acl,
  x.grantee AS grantee_oid,
  COALESCE(r.rolname, 'PUBLIC') AS grantee,
  x.privilege_type,
  x.is_grantable
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
LEFT JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('S', c.relowner))) AS x ON true
LEFT JOIN pg_roles AS r ON r.oid = x.grantee
WHERE n.nspname = 'public'
  AND c.relkind = 'S'
ORDER BY c.relname, grantee, x.privilege_type;

-- B. ACL predeterminadas configuradas en public, desglosadas por rol creador,
-- tipo de objeto y beneficiario. S = secuencias; r = tablas; f = funciones.
SELECT
  creator.rolname AS creator_role,
  n.nspname AS schema_name,
  d.defaclobjtype AS object_type_code,
  CASE d.defaclobjtype
    WHEN 'r' THEN 'tables'
    WHEN 'S' THEN 'sequences'
    WHEN 'f' THEN 'functions'
    WHEN 'T' THEN 'types'
    WHEN 'n' THEN 'schemas'
    ELSE d.defaclobjtype::text
  END AS object_type,
  COALESCE(grantee.rolname, 'PUBLIC') AS grantee,
  x.privilege_type,
  x.is_grantable
FROM pg_default_acl AS d
JOIN pg_roles AS creator ON creator.oid = d.defaclrole
LEFT JOIN pg_namespace AS n ON n.oid = d.defaclnamespace
CROSS JOIN LATERAL aclexplode(d.defaclacl) AS x
LEFT JOIN pg_roles AS grantee ON grantee.oid = x.grantee
WHERE n.nspname = 'public'
  AND d.defaclobjtype IN ('S', 'r', 'f')
ORDER BY creator_role, object_type, grantee, x.privilege_type;

-- C. Resumen: cantidad de secuencias en public.
SELECT COUNT(*) AS public_sequence_count
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'S';

-- Interpretación:
-- * A muestra las ACL efectivas actuales de cada secuencia existente.
-- * B muestra ACL predeterminadas almacenadas explícitamente; una salida vacía
--   significa que no hay entradas coincidentes en pg_default_acl para public,
--   no que PostgreSQL carezca de privilegios predeterminados incorporados.
-- * C permite distinguir entre cero secuencias y una consulta sin ACL visible.
-- * Ejecutar como rol administrativo en Supabase DEMO para una inspección completa.
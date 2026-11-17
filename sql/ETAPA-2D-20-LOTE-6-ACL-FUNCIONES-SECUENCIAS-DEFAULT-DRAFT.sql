-- ETAPA 2D-20 / LOTE 6 — ACL DE FUNCIONES, SECUENCIAS Y DEFAULT PRIVILEGES
-- Destino exclusivo: Supabase AB-SYSTEM-DEMO.
-- BORRADOR DE REVISION: termina en ROLLBACK.
-- PRECONDICIONES: Lotes 1-5 revisados; funciones y tablas objetivo presentes.
--
-- No cambia ACL de service_role ni objetos internos de auth/storage.
-- Revoca EXECUTE de funciones legacy no usadas por el cliente y mantiene los
-- helpers multiempresa/RPC necesarios para authenticated.
-- Endurece defaults de creacion en public para postgres y supabase_admin.
-- La revocacion GLOBAL de EXECUTE por defecto a PUBLIC para funciones nuevas
-- creadas por esos dos roles afecta todos los esquemas de esos creadores; se
-- documenta expresamente y requiere aprobar ese alcance antes de COMMIT.

BEGIN;

DO $preflight$
DECLARE
  v_role text;
  v_is_super boolean;
  v_missing text;
BEGIN
  SELECT rolsuper INTO v_is_super
  FROM pg_roles WHERE rolname = current_user;

  IF to_regrole('anon') IS NULL OR to_regrole('authenticated') IS NULL
     OR to_regrole('service_role') IS NULL THEN
    RAISE EXCEPTION 'ABORTADO: faltan roles anon/authenticated/service_role.';
  END IF;

  FOREACH v_role IN ARRAY ARRAY['postgres','supabase_admin'] LOOP
    IF to_regrole(v_role) IS NULL THEN
      RAISE EXCEPTION 'ABORTADO: falta el rol creador %.', v_role;
    END IF;
    IF NOT COALESCE(v_is_super, false)
       AND NOT pg_has_role(current_user, v_role, 'MEMBER') THEN
      RAISE EXCEPTION 'ABORTADO: % no puede modificar default privileges de %.', current_user, v_role;
    END IF;
  END LOOP;

  SELECT string_agg(x.signature, ', ')
    INTO v_missing
  FROM (VALUES
    ('public.ab_has_company_access(uuid)'),
    ('public.ab_is_company_admin(uuid)'),
    ('public.ab_is_global_superadmin()'),
    ('public.is_demo_admin()'),
    ('public.create_demo_profile()'),
    ('public.ab_guard_company_membership_identity()'),
    ('public.ab_guard_order_identity()'),
    ('public.ab_guard_seller_assignment_membership()'),
    ('public.ab_inventory_create_balance_for_product()'),
    ('public.ab_set_inventory_balance(uuid,text,numeric,text,text,text)'),
    ('public.ab_import_company_catalog(uuid,text,jsonb)')
  ) AS x(signature)
  WHERE to_regprocedure(x.signature) IS NULL;

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'ABORTADO: faltan funciones esperadas: %.', v_missing;
  END IF;
END
$preflight$;

-- No dejar secuencias actuales expuestas a anon/PUBLIC/authenticated.
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public
FROM PUBLIC, anon, authenticated;

-- Helpers de autorización: solo authenticated (y grants explícitos preexistentes
-- de service_role se conservan).
REVOKE ALL ON FUNCTION public.ab_has_company_access(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ab_has_company_access(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.ab_is_company_admin(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ab_is_company_admin(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.ab_is_global_superadmin() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ab_is_global_superadmin() TO authenticated;

-- Funciones legacy / trigger: no deben invocarse directamente desde clientes.
REVOKE ALL ON FUNCTION public.is_demo_admin() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_demo_profile() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ab_guard_company_membership_identity() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ab_guard_order_identity() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ab_guard_seller_assignment_membership() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ab_inventory_create_balance_for_product() FROM PUBLIC, anon, authenticated;

-- RPCs comerciales: autenticados pueden invocarlas; su cuerpo valida empresa/rol.
REVOKE ALL ON FUNCTION public.ab_set_inventory_balance(uuid,text,numeric,text,text,text)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ab_set_inventory_balance(uuid,text,numeric,text,text,text)
TO authenticated;

REVOKE ALL ON FUNCTION public.ab_import_company_catalog(uuid,text,jsonb)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ab_import_company_catalog(uuid,text,jsonb)
TO authenticated;

-- Default privileges para futuras tablas/secuencias/funciones creadas en public.
-- PUBLIC se revoca globalmente en funciones porque un revoke por-schema no
-- puede neutralizar un grant global heredado.
DO $defaults$
DECLARE
  v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['postgres','supabase_admin'] LOOP
    EXECUTE format(
      'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated',
      v_role
    );
    EXECUTE format(
      'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC, anon, authenticated',
      v_role
    );
    EXECUTE format(
      'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated',
      v_role
    );
    EXECUTE format(
      'ALTER DEFAULT PRIVILEGES FOR ROLE %I REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC',
      v_role
    );
  END LOOP;
END
$defaults$;

-- Verificacion de funciones: PUBLIC y anon no conservan EXECUTE en las funciones
-- enumeradas; authenticated conserva solo helpers y RPCs comerciales.
DO $verify$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text || ':' ||
    CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE COALESCE(r.rolname, a.grantee::text) END,
    ', ')
  INTO v_bad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
  LEFT JOIN pg_roles r ON r.oid=a.grantee
  WHERE n.nspname='public'
    AND p.oid IN (
      'public.ab_has_company_access(uuid)'::regprocedure,
      'public.ab_is_company_admin(uuid)'::regprocedure,
      'public.ab_is_global_superadmin()'::regprocedure,
      'public.is_demo_admin()'::regprocedure,
      'public.create_demo_profile()'::regprocedure,
      'public.ab_guard_company_membership_identity()'::regprocedure,
      'public.ab_guard_order_identity()'::regprocedure,
      'public.ab_guard_seller_assignment_membership()'::regprocedure,
      'public.ab_inventory_create_balance_for_product()'::regprocedure,
      'public.ab_set_inventory_balance(uuid,text,numeric,text,text,text)'::regprocedure,
      'public.ab_import_company_catalog(uuid,text,jsonb)'::regprocedure
    )
    AND a.privilege_type='EXECUTE'
    AND a.grantee IN (0, to_regrole('anon')::oid);

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Verificacion fallida: EXECUTE PUBLIC/anon sigue presente: %', v_bad;
  END IF;
END
$verify$;

-- BORRADOR: no persiste cambios.
ROLLBACK;

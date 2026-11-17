-- ETAPA 2D-17 / LOTE 4 — PRIVILEGIOS MINIMOS DE TABLAS
-- Destino exclusivo: Supabase AB-SYSTEM-DEMO.
-- BORRADOR DE REVISION. Termina en ROLLBACK; no persiste cambios.
-- PRECONDICIONES: Lotes 1, 2 y 3 aplicados y probados; backup restaurado/verificado.
-- No ejecutar en Ko'eju historico/produccion.
--
-- No modifica ACL por defecto, secuencias, funciones ni service_role.
-- Requiere confirmar que no hay grants por columna en las tablas afectadas.
-- Quita privilegios de tabla a PUBLIC/anon/authenticated y vuelve a otorgar
-- solo operaciones requeridas para authenticated. RLS sigue siendo obligatorio.

BEGIN;

DO $preflight$
DECLARE
  v_anon oid := to_regrole('anon')::oid;
  v_auth oid := to_regrole('authenticated')::oid;
  v_public oid := 0;
  v_bad text;
BEGIN
  IF v_anon IS NULL OR v_auth IS NULL THEN
    RAISE EXCEPTION 'ABORTADO: no se encontraron roles anon/authenticated.';
  END IF;

  -- Si existen ACL por columna, REVOKE de tabla no las neutraliza necesariamente.
  SELECT format('%s.%s', a.attrelid::regclass, a.attname)
    INTO v_bad
  FROM pg_attribute a
  CROSS JOIN LATERAL aclexplode(a.attacl) acl
  WHERE a.attrelid IN (
    'public.companies'::regclass,
    'public.company_memberships'::regclass,
    'public.global_roles'::regclass,
    'public.profiles'::regclass,
    'public.catalog_items'::regclass,
    'public.catalog_clients'::regclass,
    'public.catalog_import_rows'::regclass,
    'public.orders'::regclass,
    'public.seller_assignments'::regclass,
    'public.inventory_current'::regclass
  )
    AND a.attnum > 0
    AND NOT a.attisdropped
    AND acl.grantee IN (v_public, v_anon, v_auth)
  LIMIT 1;

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION
      'ABORTADO: hay privilegios por columna en %. Revisarlos antes de aplicar el lote.',
      v_bad;
  END IF;
END
$preflight$;

-- Las policies de Lote 3 gobiernan el acceso fila a fila.
-- Los GRANT siguientes solo habilitan los verbos necesarios para que RLS decida.
REVOKE ALL PRIVILEGES ON TABLE
  public.companies,
  public.company_memberships,
  public.global_roles,
  public.profiles,
  public.catalog_items,
  public.catalog_clients,
  public.catalog_import_rows,
  public.orders,
  public.seller_assignments,
  public.inventory_current
FROM PUBLIC, anon, authenticated;

-- Contexto de empresa y administracion de membresias/roles.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.companies TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.company_memberships TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.global_roles TO authenticated;

-- Perfil privado: lectura propia; no se permite cambiar rol desde el cliente.
GRANT SELECT ON TABLE public.profiles TO authenticated;

-- Catalogos: lectura de miembros y mantenimiento por administradores via RLS.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.catalog_items TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.catalog_clients TO authenticated;

-- Importaciones y pedidos: RLS valida empresa, rol y propiedad.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.catalog_import_rows TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.orders TO authenticated;

-- Asignaciones legacy: RLS restringe escritura a administradores.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.seller_assignments TO authenticated;

-- Inventario singleton legacy: sin acceso directo desde clientes.
-- La carga debe migrar a servicio confiable / inventario normalizado por empresa.

-- Empresas: solo superadmin global puede crear, editar o suspender empresas.
DO $company_admin_policies$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='companies' AND policyname='companies_superadmin_insert') THEN
    CREATE POLICY companies_superadmin_insert
      ON public.companies FOR INSERT TO authenticated
      WITH CHECK (public.ab_is_global_superadmin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='companies' AND policyname='companies_superadmin_update') THEN
    CREATE POLICY companies_superadmin_update
      ON public.companies FOR UPDATE TO authenticated
      USING (public.ab_is_global_superadmin())
      WITH CHECK (public.ab_is_global_superadmin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='companies' AND policyname='companies_superadmin_delete') THEN
    CREATE POLICY companies_superadmin_delete
      ON public.companies FOR DELETE TO authenticated
      USING (public.ab_is_global_superadmin());
  END IF;
END
$company_admin_policies$;

-- Verificacion: anon y PUBLIC no deben conservar privilegios de tabla en estas tablas.
DO $verify$
DECLARE
  v_remaining text;
BEGIN
  SELECT string_agg(c.relname || ':' || r.rolname || ':' || p.privilege_type, ', ')
    INTO v_remaining
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) p
  LEFT JOIN pg_roles r ON r.oid=p.grantee
  WHERE n.nspname='public'
    AND c.relname IN (
      'companies','company_memberships','global_roles','profiles',
      'catalog_items','catalog_clients','catalog_import_rows',
      'orders','seller_assignments','inventory_current'
    )
    AND p.grantee IN (0, to_regrole('anon')::oid)
  ;
  IF v_remaining IS NOT NULL THEN
    RAISE EXCEPTION 'Verificacion fallida: privilegios anon/PUBLIC restantes: %', v_remaining;
  END IF;
END
$verify$;

-- BORRADOR: no persiste cambios.
ROLLBACK;

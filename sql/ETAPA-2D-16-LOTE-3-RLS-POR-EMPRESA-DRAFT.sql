-- ETAPA 2D-16 / LOTE 3 — POLITICAS RLS POR EMPRESA
-- Destino exclusivo: Supabase AB-SYSTEM-DEMO.
-- BORRADOR DE REVISION. Termina en ROLLBACK; no persiste cambios.
-- PRECONDICIONES: Lotes 1 y 2 aplicados; company_id no nulo en tablas objetivo;
-- pruebas de restauracion de backup; validar flujos de negocio antes de COMMIT.
-- No ejecutar en Ko'eju historico/produccion.
--
-- Este lote reemplaza todas las policies de las tablas indicadas para evitar
-- que una policy PERMISSIVE antigua (p.ej. USING true) siga ampliando acceso.
-- No cambia GRANT/REVOKE, ACL por defecto ni funciones/triggers.
-- inventory_current se cierra a authenticated/anon mientras se diseña su reemplazo
-- multiempresa; service_role/backend de confianza puede seguir operando por bypass RLS.

BEGIN;

DO $preflight$
DECLARE
  v_table text;
  v_nulls bigint;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'catalog_items','catalog_clients','catalog_import_rows',
    'orders','seller_assignments'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name=v_table AND column_name='company_id'
    ) THEN
      RAISE EXCEPTION 'ABORTADO: falta %.company_id; aplicar lotes previos.', v_table;
    END IF;
    EXECUTE format('SELECT count(*) FROM public.%I WHERE company_id IS NULL', v_table)
      INTO v_nulls;
    IF v_nulls > 0 THEN
      RAISE EXCEPTION 'ABORTADO: %.company_id contiene % filas NULL.', v_table, v_nulls;
    END IF;
  END LOOP;

  IF to_regprocedure('public.ab_has_company_access(uuid)') IS NULL
     OR to_regprocedure('public.ab_is_company_admin(uuid)') IS NULL
     OR to_regprocedure('public.ab_is_global_superadmin()') IS NULL THEN
    RAISE EXCEPTION 'ABORTADO: faltan helpers de autorizacion multiempresa.';
  END IF;
END
$preflight$;

-- Habilitar RLS y eliminar todas las policies anteriores de las tablas que
-- pasan a tener reglas multiempresa. Esto evita OR accidental con policies legacy.
DO $reset_policies$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname='public'
      AND tablename IN (
        'companies','company_memberships','global_roles','profiles',
        'catalog_items','catalog_clients','catalog_import_rows',
        'orders','seller_assignments','inventory_current'
      )
  LOOP
    EXECUTE format('DROP POLICY %I ON %I.%I',
                   r.policyname, r.schemaname, r.tablename);
  END LOOP;
END
$reset_policies$;

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.global_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalog_import_rows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_current ENABLE ROW LEVEL SECURITY;

-- Inmutabilidad de la identidad empresarial de las membresias.
-- El company_admin puede activar/suspender vendedores, pero no mover usuarios
-- entre empresas ni convertirlos en company_admin. Esas operaciones quedan
-- reservadas al superadministrador global.
CREATE OR REPLACE FUNCTION public.ab_guard_company_membership_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF OLD.company_id IS DISTINCT FROM NEW.company_id
     OR OLD.user_id IS DISTINCT FROM NEW.user_id THEN
    RAISE EXCEPTION 'No se permite cambiar la identidad de una membresia.';
  END IF;

  IF OLD.role IS DISTINCT FROM NEW.role
     AND NOT public.ab_is_global_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadministrador global puede cambiar el rol de una membresia.';
  END IF;

  RETURN NEW;
END;
$$;

DO $membership_trigger$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.company_memberships'::regclass
      AND tgname = 'trg_company_memberships_guard_identity'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'Ya existe trg_company_memberships_guard_identity; revisar antes de continuar.';
  END IF;
  CREATE TRIGGER trg_company_memberships_guard_identity
    BEFORE UPDATE ON public.company_memberships
    FOR EACH ROW EXECUTE FUNCTION public.ab_guard_company_membership_identity();
END
$membership_trigger$;

-- La pertenencia/identidad de un pedido no puede alterarse mediante UPDATE
-- ordinario. Una transferencia futura requerira una funcion administrativa
-- separada, auditada y transaccional.
CREATE OR REPLACE FUNCTION public.ab_guard_order_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF OLD.id IS DISTINCT FROM NEW.id
     OR OLD.company_id IS DISTINCT FROM NEW.company_id
     OR OLD.owner_id IS DISTINCT FROM NEW.owner_id
     OR OLD.legacy_source IS DISTINCT FROM NEW.legacy_source
     OR OLD.legacy_id IS DISTINCT FROM NEW.legacy_id THEN
    RAISE EXCEPTION 'No se permite cambiar la empresa, propietario o identidad de un pedido.';
  END IF;

  -- created_by es inmutable para usuarios de la aplicación. Se permite SET NULL
  -- únicamente en una eliminación administrativa de Auth vía rol privilegiado.
  IF OLD.created_by IS DISTINCT FROM NEW.created_by
     AND NOT (NEW.created_by IS NULL AND current_user IN ('postgres', 'service_role')) THEN
    RAISE EXCEPTION 'No se permite cambiar el creador original del pedido.';
  END IF;
  RETURN NEW;
END;
$$;

DO $order_trigger$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.orders'::regclass
      AND tgname = 'trg_orders_guard_identity'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'Ya existe trg_orders_guard_identity; revisar antes de continuar.';
  END IF;
  CREATE TRIGGER trg_orders_guard_identity
    BEFORE UPDATE ON public.orders
    FOR EACH ROW EXECUTE FUNCTION public.ab_guard_order_identity();
END
$order_trigger$;

-- Una asignacion solo puede apuntar a un vendedor activo de esa empresa.
CREATE OR REPLACE FUNCTION public.ab_guard_seller_assignment_membership()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.company_memberships m
    WHERE m.company_id = NEW.company_id
      AND m.user_id = NEW.user_id
      AND m.role = 'seller'
      AND m.status = 'active'
  ) THEN
    RAISE EXCEPTION 'La asignacion debe corresponder a un vendedor activo de la misma empresa.';
  END IF;
  RETURN NEW;
END;
$;

DO $assignment_trigger$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.seller_assignments'::regclass
      AND tgname = 'trg_seller_assignments_active_seller'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'Ya existe trg_seller_assignments_active_seller; revisar antes de continuar.';
  END IF;
  CREATE TRIGGER trg_seller_assignments_active_seller
    BEFORE INSERT OR UPDATE ON public.seller_assignments
    FOR EACH ROW EXECUTE FUNCTION public.ab_guard_seller_assignment_membership();
END
$assignment_trigger$;

-- Empresas: cada usuario ve empresas donde tiene acceso; superadmin ve todas.
CREATE POLICY companies_read_access
ON public.companies FOR SELECT TO authenticated
USING (public.ab_has_company_access(id) OR public.ab_is_global_superadmin());

-- Membresias: usuario ve la propia; admin ve membresias de su empresa;
-- superadmin ve todas. Solo superadmin administra roles/membresias en este lote.
CREATE POLICY memberships_read_scoped
ON public.company_memberships FOR SELECT TO authenticated
USING (
  user_id = auth.uid()
  OR public.ab_is_company_admin(company_id)
  OR public.ab_is_global_superadmin()
);

CREATE POLICY memberships_superadmin_insert
ON public.company_memberships FOR INSERT TO authenticated
WITH CHECK (public.ab_is_global_superadmin());

CREATE POLICY memberships_superadmin_update
ON public.company_memberships FOR UPDATE TO authenticated
USING (public.ab_is_global_superadmin())
WITH CHECK (public.ab_is_global_superadmin());

CREATE POLICY memberships_superadmin_delete
ON public.company_memberships FOR DELETE TO authenticated
USING (public.ab_is_global_superadmin());

-- Administrador de empresa: puede incorporar, suspender/reactivar o retirar
-- vendedores de su propia empresa. No puede crear administradores ni cambiar roles.
CREATE POLICY memberships_company_admin_insert_seller
ON public.company_memberships FOR INSERT TO authenticated
WITH CHECK (
  public.ab_is_company_admin(company_id)
  AND role = 'seller'
);

CREATE POLICY memberships_company_admin_update_seller
ON public.company_memberships FOR UPDATE TO authenticated
USING (
  public.ab_is_company_admin(company_id)
  AND role = 'seller'
)
WITH CHECK (
  public.ab_is_company_admin(company_id)
  AND role = 'seller'
);

CREATE POLICY memberships_company_admin_delete_seller
ON public.company_memberships FOR DELETE TO authenticated
USING (
  public.ab_is_company_admin(company_id)
  AND role = 'seller'
);

-- Roles globales: cada usuario solo ve su propio rol; solo superadmin gestiona roles.
CREATE POLICY global_roles_read_self
ON public.global_roles FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.ab_is_global_superadmin());

CREATE POLICY global_roles_superadmin_insert
ON public.global_roles FOR INSERT TO authenticated
WITH CHECK (public.ab_is_global_superadmin());

CREATE POLICY global_roles_superadmin_update
ON public.global_roles FOR UPDATE TO authenticated
USING (public.ab_is_global_superadmin())
WITH CHECK (public.ab_is_global_superadmin());

CREATE POLICY global_roles_superadmin_delete
ON public.global_roles FOR DELETE TO authenticated
USING (public.ab_is_global_superadmin());

-- Perfil: solo lectura propia. No se permite editar role desde el cliente.
CREATE POLICY profiles_read_self
ON public.profiles FOR SELECT TO authenticated
USING (id = auth.uid());

-- Catálogos: cualquier miembro activo de la empresa puede leer;
-- solo admin de empresa o superadmin puede insertar/actualizar/eliminar.
CREATE POLICY catalog_items_read_company
ON public.catalog_items FOR SELECT TO authenticated
USING (public.ab_has_company_access(company_id) OR public.ab_is_global_superadmin());

CREATE POLICY catalog_items_admin_insert
ON public.catalog_items FOR INSERT TO authenticated
WITH CHECK (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin());

CREATE POLICY catalog_items_admin_update
ON public.catalog_items FOR UPDATE TO authenticated
USING (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin())
WITH CHECK (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin());

CREATE POLICY catalog_items_admin_delete
ON public.catalog_items FOR DELETE TO authenticated
USING (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin());

CREATE POLICY catalog_clients_read_company
ON public.catalog_clients FOR SELECT TO authenticated
USING (public.ab_has_company_access(company_id) OR public.ab_is_global_superadmin());

CREATE POLICY catalog_clients_admin_insert
ON public.catalog_clients FOR INSERT TO authenticated
WITH CHECK (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin());

CREATE POLICY catalog_clients_admin_update
ON public.catalog_clients FOR UPDATE TO authenticated
USING (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin())
WITH CHECK (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin());

CREATE POLICY catalog_clients_admin_delete
ON public.catalog_clients FOR DELETE TO authenticated
USING (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin());

-- Importaciones: solo admin de empresa/superadmin.
CREATE POLICY catalog_imports_admin_all
ON public.catalog_import_rows FOR ALL TO authenticated
USING (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin())
WITH CHECK (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin());

-- Pedidos: seller ve/actualiza solo los propios; admin ve/gestiona la empresa.
-- En INSERT, created_by debe ser el usuario autenticado y owner_id debe ser
-- un seller activo de la misma empresa. Admin puede crear a nombre de seller.
CREATE POLICY orders_read_company_owner
ON public.orders FOR SELECT TO authenticated
USING (
  public.ab_is_global_superadmin()
  OR (
    public.ab_has_company_access(company_id)
    AND (
      public.ab_is_company_admin(company_id)
      OR owner_id = auth.uid()
    )
  )
);

CREATE POLICY orders_insert_company
ON public.orders FOR INSERT TO authenticated
WITH CHECK (
  created_by = auth.uid()
  -- Siempre debe existir un vendedor activo propietario en la misma empresa,
  -- incluso cuando quien registra el pedido es el superadministrador global.
  AND EXISTS (
    SELECT 1 FROM public.company_memberships m
    WHERE m.company_id = orders.company_id
      AND m.user_id = orders.owner_id
      AND m.role = 'seller'
      AND m.status = 'active'
  )
  AND (
    public.ab_is_global_superadmin()
    OR (
      public.ab_has_company_access(company_id)
      AND (
        owner_id = auth.uid()
        OR public.ab_is_company_admin(company_id)
      )
    )
  )
);

CREATE POLICY orders_update_company_owner
ON public.orders FOR UPDATE TO authenticated
USING (
  public.ab_is_global_superadmin()
  OR (
    public.ab_has_company_access(company_id)
    AND (public.ab_is_company_admin(company_id) OR owner_id = auth.uid())
  )
)
WITH CHECK (
  public.ab_is_global_superadmin()
  OR (
    public.ab_has_company_access(company_id)
    AND (public.ab_is_company_admin(company_id) OR owner_id = auth.uid())
  )
);

CREATE POLICY orders_delete_company_admin
ON public.orders FOR DELETE TO authenticated
USING (
  public.ab_is_global_superadmin()
  OR (public.ab_is_company_admin(company_id) AND public.ab_has_company_access(company_id))
);

-- Asignaciones legacy: lectura propia/admin; escritura solo admin de empresa.
CREATE POLICY seller_assignments_read_company
ON public.seller_assignments FOR SELECT TO authenticated
USING (
  public.ab_is_global_superadmin()
  OR (
    public.ab_has_company_access(company_id)
    AND (user_id = auth.uid() OR public.ab_is_company_admin(company_id))
  )
);

CREATE POLICY seller_assignments_admin_insert
ON public.seller_assignments FOR INSERT TO authenticated
WITH CHECK (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin());

CREATE POLICY seller_assignments_admin_update
ON public.seller_assignments FOR UPDATE TO authenticated
USING (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin())
WITH CHECK (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin());

CREATE POLICY seller_assignments_admin_delete
ON public.seller_assignments FOR DELETE TO authenticated
USING (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin());

-- La tabla legacy inventory_current tiene una sola fila global (id=1) y no
-- contiene company_id. Se eliminan policies abiertas y no se crea acceso
-- authenticated hasta migrar su contenido a inventario normalizado por empresa.

-- Verificacion de que no quedaron policies antiguas en tablas sensibles.
DO $verify$
DECLARE
  v_open_policies text;
BEGIN
  SELECT string_agg(tablename || '.' || policyname, ', ')
    INTO v_open_policies
  FROM pg_policies
  WHERE schemaname='public'
    AND tablename IN (
      'catalog_items','catalog_clients','catalog_import_rows',
      'orders','seller_assignments','inventory_current'
    )
    AND (
      qual = 'true' OR with_check = 'true'
    );

  IF v_open_policies IS NOT NULL THEN
    RAISE EXCEPTION 'Verificacion fallida: policies abiertas: %', v_open_policies;
  END IF;
END
$verify$;

-- BORRADOR: no persiste cambios.
ROLLBACK;

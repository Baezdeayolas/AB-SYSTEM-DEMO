-- AB SYSTEM DEMO — MIGRACION MULTIEMPRESA CONSOLIDADA (BORRADOR)
-- Una sola transaccion para DEMO: esquema, claves, RLS, permisos e inventario.
-- DESTINO EXCLUSIVO: proyecto Supabase AB-SYSTEM-DEMO.
-- NO ejecutar en Ko'eju historico/produccion.
--
-- Este archivo consolida los Lotes 1, 2, 3, 4, 5 y 6 para evitar ejecuciones
-- fragmentadas. El script termina en ROLLBACK y no persiste cambios.
-- Solo despues de revisar el resultado del ensayo y aprobar expresamente,
-- se cambiara la ultima instruccion a COMMIT para ejecutar una unica vez.
--
-- PRECONDICIONES PENDIENTES DE VALIDACION:
-- 0) Rehacer el consolidado: excluir/reemplazar el Lote 5 legacy que colisiona
--    con public.inventory_balances existente y coordinar el nuevo modelo CENTRAL/CDE.
-- 1) Respaldo DEMO completo, restaurable y verificado.
-- 2) Confirmar manualmente la empresa inicial y su codigo objetivo ABDEMO.
-- 3) Revisar el mapeo de perfiles/membresias y propietarios de pedidos.
-- 4) Verificar estructura y datos actuales de inventario legacy.
-- 5) Validar payloads y cantidades del catalogo antes de migrar inventario.
-- 6) Revisar el alcance de default privileges para el rol postgres.
-- El backfill de las filas comerciales existentes a code=KOEJU es INTENCIONAL:
-- KOEJU permanece como empresa fuente dentro de esta base DEMO.
-- DEMO2 (UUID ya existente) se renombrara a AB SYSTEM DEMO y recibira
-- una copia separada de catalogo y clientes ficticios en una etapa posterior.
-- BLOQUEO ACTUAL: el Lote 5 intenta crear public.inventory_balances, pero esa
-- tabla legacy ya existe en este proyecto. La transaccion abortara en ese punto.
-- No ejecutar este archivo hasta separar el inventario legacy del nuevo modelo.
--
-- REGLAS DE NEGOCIO:
-- - Pedidos no facturan, no reservan y no descuentan stock.
-- - Importar artículos no elimina productos ausentes del archivo.
-- - Ko'eju produccion permanece intacto.
--
BEGIN;

-- =====================================================================
-- sql/ETAPA-2D-14-LOTE-1-ESQUEMA-EMPRESA-DRAFT.sql
-- =====================================================================
-- ETAPA 2D-14 / LOTE 1 — ESQUEMA EMPRESARIAL ADITIVO (BORRADOR PARA REVISION)
-- Destino exclusivo: Supabase AB-SYSTEM-DEMO.
-- NO ejecutar hasta: respaldo DEMO restaurado y verificado, inventario de escritores externos
-- cerrado, y aprobacion explicita del propietario.
-- No modifica Ko'eju historico/produccion.
--
-- Alcance de este lote:
--   * Agrega company_id a catalog_items, catalog_clients, catalog_import_rows,
--     orders y seller_assignments.
--   * Agrega orders.created_by (historico queda NULL si no se conoce el actor).
--   * El backfill actual todavia espera code = 'KOEJU'; pendiente de adaptar a ABDEMO.
--     solo si las comprobaciones de pertenencia pasan.
--   * Agrega FK e indices compuestos de transicion.
--
-- Deliberadamente NO hace:
--   * No elimina ni reemplaza PK/UNIQUE legacy.
--   * No cambia RLS, policies, grants, triggers ni Realtime.
--   * No cambia inventory_current (singleton legacy id=1; stock multiempresa
--     requiere el modelo normalizado por CENTRAL/CDE).
--   * No modifica payload, sc, sd, precios ni pedidos.
--   * No descuenta ni reserva stock por pedidos.
--
-- Resultado esperado: esquema aditivo listo para el Lote 2. Las PK legacy
-- todavia impiden repetir codigos entre empresas; no desplegar frontend multiempresa
-- ni crear una segunda empresa comercial hasta completar Lotes 2 y 3.
-- Columnas aditivas: nullable temporalmente para permitir auditar escritores legacy.
ALTER TABLE public.catalog_items
  ADD COLUMN IF NOT EXISTS company_id uuid;

ALTER TABLE public.catalog_clients
  ADD COLUMN IF NOT EXISTS company_id uuid;

ALTER TABLE public.catalog_import_rows
  ADD COLUMN IF NOT EXISTS company_id uuid;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS company_id uuid,
  ADD COLUMN IF NOT EXISTS created_by uuid;

ALTER TABLE public.seller_assignments
  ADD COLUMN IF NOT EXISTS company_id uuid;

DO $migration$
DECLARE
  v_company_id uuid;
  v_company_count integer;
  v_bad_orders bigint;
  v_bad_assignments bigint;
  v_conflicts bigint;
BEGIN
  SELECT count(*), (array_agg(id))[1]
    INTO v_company_count, v_company_id
  FROM public.companies
  WHERE code = 'KOEJU';

  IF v_company_count <> 1 OR v_company_id IS NULL THEN
    RAISE EXCEPTION
      'ABORTADO: se esperaba exactamente una empresa code=KOEJU; encontradas %.',
      v_company_count;
  END IF;

  -- No reasignar silenciosamente filas que ya pertenezcan a otra empresa.
  SELECT count(*) INTO v_conflicts
  FROM (
    SELECT company_id FROM public.catalog_items
    UNION ALL SELECT company_id FROM public.catalog_clients
    UNION ALL SELECT company_id FROM public.catalog_import_rows
    UNION ALL SELECT company_id FROM public.orders
    UNION ALL SELECT company_id FROM public.seller_assignments
  ) x
  WHERE x.company_id IS NOT NULL
    AND x.company_id <> v_company_id;

  IF v_conflicts > 0 THEN
    RAISE EXCEPTION
      'ABORTADO: hay % filas ya asignadas a otra empresa. Requiere conciliacion manual.',
      v_conflicts;
  END IF;

  -- El pedido conserva owner_id como vendedor. Solo se asigna a KOEJU
  -- si cada propietario tiene membership seller activa en esa empresa.
  SELECT count(*) INTO v_bad_orders
  FROM public.orders o
  WHERE o.owner_id IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM public.company_memberships m
       WHERE m.company_id = v_company_id
         AND m.user_id = o.owner_id
         AND m.role = 'seller'
         AND m.status = 'active'
     );

  IF v_bad_orders > 0 THEN
    RAISE EXCEPTION
      'ABORTADO: % pedidos no tienen owner_id verificable como seller activo de KOEJU.',
      v_bad_orders;
  END IF;

  SELECT count(*) INTO v_bad_assignments
  FROM public.seller_assignments s
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.company_memberships m
    WHERE m.company_id = v_company_id
      AND m.user_id = s.user_id
      AND m.role = 'seller'
      AND m.status = 'active'
  );

  IF v_bad_assignments > 0 THEN
    RAISE EXCEPTION
      'ABORTADO: % asignaciones no corresponden a sellers activos de KOEJU.',
      v_bad_assignments;
  END IF;

  -- Backfill conservador: solo filas sin empresa; no sobrescribe asignaciones.
  UPDATE public.catalog_items
     SET company_id = v_company_id
   WHERE company_id IS NULL;

  UPDATE public.catalog_clients
     SET company_id = v_company_id
   WHERE company_id IS NULL;

  UPDATE public.catalog_import_rows
     SET company_id = v_company_id
   WHERE company_id IS NULL;

  UPDATE public.orders
     SET company_id = v_company_id
   WHERE company_id IS NULL;

  UPDATE public.seller_assignments
     SET company_id = v_company_id
   WHERE company_id IS NULL;
END
$migration$;

-- FKs con nombres estables; bloque idempotente.
DO $constraints$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'catalog_items_company_id_fkey'
                 AND conrelid = 'public.catalog_items'::regclass) THEN
    ALTER TABLE public.catalog_items
      ADD CONSTRAINT catalog_items_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'catalog_clients_company_id_fkey'
                 AND conrelid = 'public.catalog_clients'::regclass) THEN
    ALTER TABLE public.catalog_clients
      ADD CONSTRAINT catalog_clients_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'catalog_import_rows_company_id_fkey'
                 AND conrelid = 'public.catalog_import_rows'::regclass) THEN
    ALTER TABLE public.catalog_import_rows
      ADD CONSTRAINT catalog_import_rows_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_company_id_fkey'
                 AND conrelid = 'public.orders'::regclass) THEN
    ALTER TABLE public.orders
      ADD CONSTRAINT orders_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'orders_created_by_fkey'
                 AND conrelid = 'public.orders'::regclass) THEN
    ALTER TABLE public.orders
      ADD CONSTRAINT orders_created_by_fkey
      FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'seller_assignments_company_id_fkey'
                 AND conrelid = 'public.seller_assignments'::regclass) THEN
    ALTER TABLE public.seller_assignments
      ADD CONSTRAINT seller_assignments_company_id_fkey
      FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE RESTRICT;
  END IF;
END
$constraints$;

-- Indices de transicion. Las PK legacy se conservan hasta el Lote 2.
CREATE INDEX IF NOT EXISTS catalog_items_company_id_idx
  ON public.catalog_items(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS catalog_items_company_code_uidx
  ON public.catalog_items(company_id, code);

CREATE INDEX IF NOT EXISTS catalog_clients_company_id_idx
  ON public.catalog_clients(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS catalog_clients_company_code_uidx
  ON public.catalog_clients(company_id, code);

CREATE INDEX IF NOT EXISTS catalog_import_rows_company_id_idx
  ON public.catalog_import_rows(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS catalog_import_rows_company_import_type_code_uidx
  ON public.catalog_import_rows(company_id, import_id, catalog_type, code);

CREATE INDEX IF NOT EXISTS orders_company_updated_idx
  ON public.orders(company_id, updated_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS orders_company_owner_source_legacy_uidx
  ON public.orders(company_id, owner_id, legacy_source, legacy_id);

CREATE INDEX IF NOT EXISTS seller_assignments_company_id_idx
  ON public.seller_assignments(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS seller_assignments_company_user_uidx
  ON public.seller_assignments(company_id, user_id);

-- Validacion final dentro de la misma transaccion: ninguna fila legacy puede quedar sin empresa.
DO $verify$
DECLARE
  v_unassigned bigint;
BEGIN
  SELECT
    (SELECT count(*) FROM public.catalog_items WHERE company_id IS NULL) +
    (SELECT count(*) FROM public.catalog_clients WHERE company_id IS NULL) +
    (SELECT count(*) FROM public.catalog_import_rows WHERE company_id IS NULL) +
    (SELECT count(*) FROM public.orders WHERE company_id IS NULL) +
    (SELECT count(*) FROM public.seller_assignments WHERE company_id IS NULL)
  INTO v_unassigned;

  IF v_unassigned <> 0 THEN
    RAISE EXCEPTION 'ABORTADO: quedan % filas sin company_id.', v_unassigned;
  END IF;
END
$verify$;

-- No hacer COMMIT automatico en este borrador hasta aprobar el contenido.
-- Al ejecutar el lote aprobado, el COMMIT debe habilitarse expresamente.

-- =====================================================================
-- sql/ETAPA-2D-15-LOTE-2-CLAVES-COMPUESTAS-DRAFT.sql
-- =====================================================================
-- ETAPA 2D-15 / LOTE 2 — CLAVES Y UNICIDAD POR EMPRESA
-- Destino exclusivo: Supabase AB-SYSTEM-DEMO.
-- PRECONDICION: Lote 1 debe haberse aplicado y confirmado (company_id/FK/indexes presentes).
-- Este archivo es un BORRADOR DE REVISION. Termina en ROLLBACK y NO persiste cambios.
-- No ejecutar en Ko'eju historico/produccion.
--
-- Objetivo:
--   catalog_items PK (company_id, code)
--   catalog_clients PK (company_id, code)
--   catalog_import_rows PK (company_id, import_id, catalog_type, code)
--   seller_assignments PK (company_id, user_id), y FK a membership de la empresa
--   orders: retirar UNIQUE legacy global y conservar unicidad scoped por empresa.
--
-- No toca inventory_current ni crea/descuenta/reserva stock.
-- No cambia RLS/policies/grants/triggers/realtime.
-- No elimina filas ni cambia payloads.
DO $preflight$
DECLARE
  v_table text;
  v_nulls bigint;
  v_missing_index boolean;
  v_external_fk text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'catalog_items','catalog_clients','catalog_import_rows',
    'orders','seller_assignments'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name=v_table AND column_name='company_id'
    ) THEN
      RAISE EXCEPTION 'ABORTADO: falta %.company_id. Primero completar Lote 1.', v_table;
    END IF;
    EXECUTE format('SELECT count(*) FROM public.%I WHERE company_id IS NULL', v_table)
      INTO v_nulls;
    IF v_nulls > 0 THEN
      RAISE EXCEPTION 'ABORTADO: %.company_id tiene % filas NULL.', v_table, v_nulls;
    END IF;
  END LOOP;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.company_memberships'::regclass
      AND conname='company_memberships_company_id_user_id_key'
  ) THEN
    RAISE EXCEPTION 'ABORTADO: falta UNIQUE(company_id,user_id) en company_memberships.';
  END IF;

  -- No eliminar PK si otra tabla tiene una FK que depende de ella.
  SELECT format('%s depende de %s mediante FK %s',
                conrelid::regclass, confrelid::regclass, conname)
    INTO v_external_fk
  FROM pg_constraint
  WHERE contype='f'
    AND confrelid IN (
      'public.catalog_items'::regclass,
      'public.catalog_clients'::regclass,
      'public.catalog_import_rows'::regclass,
      'public.seller_assignments'::regclass
    )
    AND conrelid NOT IN (
      'public.catalog_items'::regclass,
      'public.catalog_clients'::regclass,
      'public.catalog_import_rows'::regclass,
      'public.seller_assignments'::regclass
    )
  LIMIT 1;

  IF v_external_fk IS NOT NULL THEN
    RAISE EXCEPTION 'ABORTADO: hay FK externa que requiere migracion coordinada: %', v_external_fk;
  END IF;

  -- Las claves legacy deben existir exactamente como se esperan.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.catalog_items'::regclass AND conname='catalog_items_pkey' AND contype='p')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.catalog_clients'::regclass AND conname='catalog_clients_pkey' AND contype='p')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.catalog_import_rows'::regclass AND conname='catalog_import_rows_pkey' AND contype='p')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.seller_assignments'::regclass AND conname='seller_assignments_pkey' AND contype='p') THEN
    RAISE EXCEPTION 'ABORTADO: las PK actuales no coinciden con el preflight recibido.';
  END IF;

  -- Evita cambiar la unicidad de pedidos si el indice scoped de Lote 1 no existe.
  SELECT NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='orders'
      AND indexname='orders_company_owner_source_legacy_uidx'
  ) INTO v_missing_index;
  IF v_missing_index THEN
    RAISE EXCEPTION 'ABORTADO: falta indice de unicidad de pedidos por empresa del Lote 1.';
  END IF;
END
$preflight$;

-- Las nuevas PK permiten que dos empresas usen el mismo codigo.
ALTER TABLE public.catalog_items DROP CONSTRAINT catalog_items_pkey;
ALTER TABLE public.catalog_items
  ADD CONSTRAINT catalog_items_pkey PRIMARY KEY (company_id, code);
DROP INDEX IF EXISTS public.catalog_items_company_code_uidx;

ALTER TABLE public.catalog_clients DROP CONSTRAINT catalog_clients_pkey;
ALTER TABLE public.catalog_clients
  ADD CONSTRAINT catalog_clients_pkey PRIMARY KEY (company_id, code);
DROP INDEX IF EXISTS public.catalog_clients_company_code_uidx;

ALTER TABLE public.catalog_import_rows DROP CONSTRAINT catalog_import_rows_pkey;
ALTER TABLE public.catalog_import_rows
  ADD CONSTRAINT catalog_import_rows_pkey
  PRIMARY KEY (company_id, import_id, catalog_type, code);
DROP INDEX IF EXISTS public.catalog_import_rows_company_import_type_code_uidx;

-- Una asignacion pertenece a un vendedor dentro de una empresa.
ALTER TABLE public.seller_assignments DROP CONSTRAINT seller_assignments_pkey;
ALTER TABLE public.seller_assignments
  ADD CONSTRAINT seller_assignments_pkey PRIMARY KEY (company_id, user_id);
DROP INDEX IF EXISTS public.seller_assignments_company_user_uidx;

DO $seller_fk$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.seller_assignments'::regclass
      AND conname='seller_assignments_company_user_membership_fkey'
  ) THEN
    ALTER TABLE public.seller_assignments
      ADD CONSTRAINT seller_assignments_company_user_membership_fkey
      FOREIGN KEY (company_id, user_id)
      REFERENCES public.company_memberships(company_id, user_id)
      ON DELETE CASCADE;
  END IF;
END
$seller_fk$;

-- Los IDs UUID de pedidos siguen siendo su PK. La unicidad legacy pasa a ser
-- por empresa; el indice scoped fue creado y verificado en Lote 1.
ALTER TABLE public.orders
  DROP CONSTRAINT orders_owner_id_legacy_source_legacy_id_key;

-- Reforzar company_id obligatorio en pedidos; las otras cuatro tablas ya
-- lo tienen NOT NULL por formar parte de su PK compuesta.
ALTER TABLE public.orders
  ALTER COLUMN company_id SET NOT NULL;

-- Comprobacion de estructura resultante.
DO $verify$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.catalog_items'::regclass AND contype='p'
      AND pg_get_constraintdef(oid)='PRIMARY KEY (company_id, code)'
  ) THEN RAISE EXCEPTION 'Verificacion fallida: PK catalog_items.'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.catalog_clients'::regclass AND contype='p'
      AND pg_get_constraintdef(oid)='PRIMARY KEY (company_id, code)'
  ) THEN RAISE EXCEPTION 'Verificacion fallida: PK catalog_clients.'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.catalog_import_rows'::regclass AND contype='p'
      AND pg_get_constraintdef(oid)='PRIMARY KEY (company_id, import_id, catalog_type, code)'
  ) THEN RAISE EXCEPTION 'Verificacion fallida: PK catalog_import_rows.'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.seller_assignments'::regclass AND contype='p'
      AND pg_get_constraintdef(oid)='PRIMARY KEY (company_id, user_id)'
  ) THEN RAISE EXCEPTION 'Verificacion fallida: PK seller_assignments.'; END IF;

  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.orders'::regclass
      AND conname='orders_owner_id_legacy_source_legacy_id_key'
  ) THEN RAISE EXCEPTION 'Verificacion fallida: sigue activa unicidad legacy global de orders.'; END IF;
END
$verify$;

-- =====================================================================
-- sql/ETAPA-2D-16-LOTE-3-RLS-POR-EMPRESA-DRAFT.sql
-- =====================================================================
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
     AND NOT (NEW.created_by IS NULL AND current_user IN ('postgres', 'service_role', 'supabase_auth_admin')) THEN
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
AS $$
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
$$;

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
-- superadmin ve todas. El admin gestiona vendedores de su empresa; el superadmin gestiona todos los roles.
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

-- =====================================================================
-- sql/ETAPA-2D-17-LOTE-4-PRIVILEGIOS-MINIMOS-DRAFT.sql
-- =====================================================================
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
  SELECT string_agg(c.relname || ':' || CASE WHEN p.grantee = 0 THEN 'PUBLIC' ELSE COALESCE(r.rolname, p.grantee::text) END || ':' || p.privilege_type, ', ')
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

-- =====================================================================
-- =====================================================================
-- ETAPA 2D-19 / LOTE 5 — INVENTARIO (SEPARADO DEL CONSOLIDADO BASE)
-- =====================================================================
-- Este consolidado NO crea ni modifica public.inventory_balances ni
-- public.inventory_movements: en el proyecto DEMO ya existe una tabla
-- legacy con el primer nombre y no se debe reutilizar ni borrar.
--
-- El inventario vigente para la aplicación es por depósito:
--   inventory_location_balances(company_id, product_code, location_code)
--   inventory_location_movements(...)
-- La migración independiente 2D-22 es la única responsable de esas tablas,
-- sus triggers, RPC y permisos. Debe ensayarse sobre una restauración DEMO
-- antes de aplicar. Los saldos legacy no se asignan automáticamente a CENTRAL
-- o CDE; se conservan y el Excel completo establecerá los saldos por depósito.
--
-- Regla: crear pedidos nunca reserva ni descuenta stock.
--
-- sql/ETAPA-2D-20-LOTE-6-ACL-FUNCIONES-SECUENCIAS-DEFAULT-DRAFT.sql
-- =====================================================================
-- ETAPA 2D-20 / LOTE 6 — ACL DE FUNCIONES, SECUENCIAS Y DEFAULT PRIVILEGES
-- Destino exclusivo: Supabase AB-SYSTEM-DEMO.
-- BORRADOR DE REVISION: termina en ROLLBACK.
-- PRECONDICIONES: Lotes 1-5 revisados; funciones y tablas objetivo presentes.
--
-- No cambia ACL de service_role ni objetos internos de auth/storage.
-- Revoca EXECUTE de funciones legacy no usadas por el cliente y mantiene los
-- helpers multiempresa/RPC necesarios para authenticated.
-- Endurece defaults de creacion en public para el rol postgres, que es el
-- unico rol creador modificable desde esta sesion. No intenta alterar ACL de
-- supabase_admin, porque Supabase no concede ese permiso a postgres.
-- La revocacion GLOBAL de EXECUTE por defecto a PUBLIC para funciones nuevas
-- creadas por postgres afecta todos los esquemas de ese creador; requiere
-- revisar ese alcance antes de COMMIT.
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

  FOREACH v_role IN ARRAY ARRAY['postgres'] LOOP
    IF to_regrole(v_role) IS NULL THEN
      RAISE EXCEPTION 'ABORTADO: falta el rol creador %.', v_role;
    END IF;
    IF NOT COALESCE(v_is_super, false)
       AND NOT pg_has_role(current_user, v_role::name, 'MEMBER') THEN
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

-- Default privileges para futuras tablas/secuencias/funciones creadas por postgres en public.
-- PUBLIC se revoca globalmente en funciones porque un revoke por-schema no
-- puede neutralizar un grant global heredado. No se modifica supabase_admin.
DO $defaults$
DECLARE
  v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['postgres'] LOOP
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
          )
    AND a.privilege_type='EXECUTE'
    AND a.grantee IN (0, to_regrole('anon')::oid);

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Verificacion fallida: EXECUTE PUBLIC/anon sigue presente: %', v_bad;
  END IF;
END
$verify$;

-- SEGURIDAD: este archivo permanece como borrador no ejecutable.
-- No cambiar a COMMIT ni ejecutar hasta completar adaptacion ABDEMO,
-- anonimización, respaldo restaurable, pruebas y aprobacion especifica.
ROLLBACK;

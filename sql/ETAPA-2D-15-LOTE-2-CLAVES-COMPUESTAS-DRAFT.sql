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

BEGIN;

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

-- BORRADOR: no persiste cambios.
ROLLBACK;

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
--   * Asigna los registros existentes a la empresa cuyo code = 'KOEJU',
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

BEGIN;

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
  SELECT count(*), min(id)
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
ROLLBACK;

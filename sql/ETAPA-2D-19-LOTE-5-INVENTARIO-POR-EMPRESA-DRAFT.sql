-- ETAPA 2D-19 / LOTE 5 — INVENTARIO NORMALIZADO POR EMPRESA
-- Destino exclusivo: Supabase AB-SYSTEM-DEMO.
-- BORRADOR: transaccion termina en ROLLBACK. No ejecutar en produccion.
-- PRECONDICIONES: Lotes 1 y 2 aplicados; Lote 3 RLS validado; respaldo DEMO disponible.
--
-- Fuente inicial de saldo: catalog_items.payload->>'sc', que es el campo de stock
-- que consume actualmente el frontend. El singleton inventory_current debe seguir
-- vacio (items = []). Si no esta vacio o el campo sc no es numerico, aborta.
--
-- IMPORTANTE:
-- - No modifica catalog_items.payload ni inventory_current.
-- - No descuenta ni reserva stock al crear pedidos.
-- - Cada cambio futuro se registra en inventory_movements y actualiza el saldo
--   mediante ab_set_inventory_balance dentro de una sola transaccion.
-- - La importacion Excel masiva debe llamar una RPC batch transaccional posterior;
--   este lote deja preparada la base y la RPC segura por producto.

BEGIN;

DO $preflight$
DECLARE
  v_count bigint;
  v_bad bigint;
  v_bad_inventory bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.catalog_items'::regclass
      AND contype='p'
      AND pg_get_constraintdef(oid)='PRIMARY KEY (company_id, code)'
  ) THEN
    RAISE EXCEPTION 'ABORTADO: catalog_items aun no tiene PK (company_id, code).';
  END IF;

  SELECT count(*) INTO v_count FROM public.inventory_current;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'ABORTADO: inventory_current debe conservar exactamente una fila legacy; hay %.', v_count;
  END IF;

  SELECT count(*) INTO v_bad_inventory
  FROM public.inventory_current
  WHERE id <> 1
     OR CASE WHEN jsonb_typeof(items) = 'array'
             THEN jsonb_array_length(items)
             ELSE -1 END <> 0;
  IF v_bad_inventory > 0 THEN
    RAISE EXCEPTION 'ABORTADO: inventory_current no esta vacio como se documento; requiere conciliacion manual.';
  END IF;

  SELECT count(*) INTO v_bad
  FROM public.catalog_items
  WHERE payload ? 'sc'
    AND NULLIF(btrim(payload->>'sc'), '') IS NOT NULL
    AND btrim(payload->>'sc') !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$';
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'ABORTADO: % productos tienen payload.sc no numerico.', v_bad;
  END IF;

  SELECT count(*) INTO v_bad
  FROM public.catalog_items
  WHERE NULLIF(btrim(payload->>'sc'), '') IS NOT NULL
    AND btrim(payload->>'sc') ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$'
    AND (payload->>'sc')::numeric < 0;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'ABORTADO: % productos tienen stock inicial negativo.', v_bad;
  END IF;

  IF to_regclass('public.inventory_balances') IS NOT NULL
     OR to_regclass('public.inventory_movements') IS NOT NULL THEN
    RAISE EXCEPTION 'ABORTADO: ya existe una tabla de inventario normalizado; revisar antes de continuar.';
  END IF;
END
$preflight$;

CREATE TABLE public.inventory_balances (
  company_id uuid NOT NULL,
  product_code text NOT NULL,
  quantity numeric(14,3) NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT inventory_balances_pkey PRIMARY KEY (company_id, product_code),
  CONSTRAINT inventory_balances_product_fkey
    FOREIGN KEY (company_id, product_code)
    REFERENCES public.catalog_items(company_id, code) ON DELETE RESTRICT
);

CREATE TABLE public.inventory_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  product_code text NOT NULL,
  movement_type text NOT NULL CHECK (movement_type IN ('opening','import','adjustment')),
  quantity_delta numeric(14,3) NOT NULL,
  quantity_before numeric(14,3) NOT NULL CHECK (quantity_before >= 0),
  quantity_after numeric(14,3) NOT NULL CHECK (quantity_after >= 0),
  reason text NOT NULL,
  source_ref text NULL,
  created_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT inventory_movements_product_fkey
    FOREIGN KEY (company_id, product_code)
    REFERENCES public.catalog_items(company_id, code) ON DELETE RESTRICT,
  CONSTRAINT inventory_movements_delta_check
    CHECK (movement_type = 'opening' OR quantity_delta <> 0),
  CONSTRAINT inventory_movements_math_check
    CHECK (quantity_after = quantity_before + quantity_delta)
);

CREATE UNIQUE INDEX inventory_movements_one_opening_uidx
  ON public.inventory_movements(company_id, product_code)
  WHERE movement_type = 'opening';

CREATE INDEX inventory_movements_company_created_idx
  ON public.inventory_movements(company_id, created_at DESC);

-- Cada producto nuevo recibe saldo cero, sin tocar el JSONB del catálogo.
CREATE OR REPLACE FUNCTION public.ab_inventory_create_balance_for_product()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.inventory_balances(company_id, product_code, quantity)
  VALUES (NEW.company_id, NEW.code, 0)
  ON CONFLICT (company_id, product_code) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_catalog_items_create_inventory_balance
AFTER INSERT ON public.catalog_items
FOR EACH ROW EXECUTE FUNCTION public.ab_inventory_create_balance_for_product();

-- RPC de ajuste de saldo. No hay endpoint directo de escritura sobre las tablas.
CREATE OR REPLACE FUNCTION public.ab_set_inventory_balance(
  p_company_id uuid,
  p_product_code text,
  p_quantity numeric,
  p_movement_type text,
  p_reason text,
  p_source_ref text DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_before numeric(14,3);
  v_delta numeric(14,3);
  v_actor uuid;
BEGIN
  v_actor := auth.uid();

  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Se requiere una sesion autenticada.';
  END IF;

  IF NOT (
    public.ab_is_global_superadmin()
    OR public.ab_is_company_admin(p_company_id)
  ) THEN
    RAISE EXCEPTION 'No tienes permiso para actualizar el inventario de esta empresa.';
  END IF;

  IF p_quantity IS NULL OR p_quantity < 0 THEN
    RAISE EXCEPTION 'La cantidad debe ser un numero mayor o igual a cero.';
  END IF;

  IF p_movement_type IS NULL OR p_movement_type NOT IN ('import','adjustment') THEN
    RAISE EXCEPTION 'Tipo de movimiento no permitido.';
  END IF;

  IF NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'El motivo del movimiento es obligatorio.';
  END IF;

  SELECT b.quantity INTO v_before
  FROM public.inventory_balances b
  WHERE b.company_id = p_company_id
    AND b.product_code = p_product_code
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe saldo para ese producto y empresa.';
  END IF;

  v_delta := p_quantity - v_before;
  IF v_delta = 0 THEN
    RETURN v_before;
  END IF;

  UPDATE public.inventory_balances
  SET quantity = p_quantity,
      updated_at = now(),
      updated_by = v_actor
  WHERE company_id = p_company_id
    AND product_code = p_product_code;

  INSERT INTO public.inventory_movements(
    company_id, product_code, movement_type, quantity_delta,
    quantity_before, quantity_after, reason, source_ref, created_by
  ) VALUES (
    p_company_id, p_product_code, p_movement_type, v_delta,
    v_before, p_quantity, btrim(p_reason), p_source_ref, v_actor
  );

  RETURN p_quantity;
END;
$$;

-- Aislamiento y escritura solo por RPC.
ALTER TABLE public.inventory_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_movements ENABLE ROW LEVEL SECURITY;

CREATE POLICY inventory_balances_read_company
ON public.inventory_balances FOR SELECT TO authenticated
USING (public.ab_has_company_access(company_id) OR public.ab_is_global_superadmin());

CREATE POLICY inventory_movements_read_admin
ON public.inventory_movements FOR SELECT TO authenticated
USING (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin());

REVOKE ALL ON TABLE public.inventory_balances, public.inventory_movements FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.inventory_balances, public.inventory_movements TO authenticated;

REVOKE ALL ON FUNCTION public.ab_set_inventory_balance(uuid,text,numeric,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ab_set_inventory_balance(uuid,text,numeric,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.ab_inventory_create_balance_for_product() FROM PUBLIC, anon, authenticated;

-- Cargar saldos iniciales desde el stock que hoy se muestra en catalog_items.payload.sc.
INSERT INTO public.inventory_balances(company_id, product_code, quantity)
SELECT
  ci.company_id,
  ci.code,
  COALESCE(NULLIF(btrim(ci.payload->>'sc'), '')::numeric, 0)
FROM public.catalog_items ci;

INSERT INTO public.inventory_movements(
  company_id, product_code, movement_type, quantity_delta,
  quantity_before, quantity_after, reason, source_ref, created_by
)
SELECT
  b.company_id, b.product_code, 'opening', b.quantity,
  0, b.quantity, 'Saldo inicial migrado desde catalog_items.payload.sc',
  'opening-balance-migration-2026-11-17', NULL
FROM public.inventory_balances b;

DO $verify$
DECLARE
  v_products bigint;
  v_balances bigint;
  v_missing bigint;
  v_mismatches bigint;
BEGIN
  SELECT count(*) INTO v_products FROM public.catalog_items;
  SELECT count(*) INTO v_balances FROM public.inventory_balances;
  SELECT count(*) INTO v_missing
  FROM public.catalog_items ci
  LEFT JOIN public.inventory_balances b
    ON b.company_id=ci.company_id AND b.product_code=ci.code
  WHERE b.product_code IS NULL;

  SELECT count(*) INTO v_mismatches
  FROM public.catalog_items ci
  JOIN public.inventory_balances b
    ON b.company_id=ci.company_id AND b.product_code=ci.code
  WHERE b.quantity <> COALESCE(NULLIF(btrim(ci.payload->>'sc'), '')::numeric, 0);

  IF v_products <> v_balances OR v_missing <> 0 OR v_mismatches <> 0 THEN
    RAISE EXCEPTION 'Verificacion de inventario fallida: productos %, saldos %, faltantes %, diferencias %.',
      v_products, v_balances, v_missing, v_mismatches;
  END IF;
END
$verify$;

-- BORRADOR: no persiste cambios.
ROLLBACK;

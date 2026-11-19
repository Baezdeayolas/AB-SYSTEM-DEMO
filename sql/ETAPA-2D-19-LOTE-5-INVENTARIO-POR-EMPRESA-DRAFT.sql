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

  IF NOT EXISTS (
    SELECT 1 FROM public.companies c
    WHERE c.id = p_company_id AND c.status = 'active'
  ) THEN
    RAISE EXCEPTION 'La empresa no existe o esta suspendida.';
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

-- Importacion masiva atomica de catalogo y stock.
-- Contrato por fila: {"code":"ART-001","payload":{...},"quantity":12.0}
-- Los productos ausentes del archivo NO se eliminan ni se modifican.
CREATE OR REPLACE FUNCTION public.ab_import_company_catalog(
  p_company_id uuid,
  p_import_id text,
  p_rows jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row jsonb;
  v_code text;
  v_payload jsonb;
  v_quantity_text text;
  v_quantity numeric(14,3);
  v_count bigint;
  v_processed integer := 0;
  v_actor uuid;
BEGIN
  v_actor := auth.uid();
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Se requiere una sesion autenticada.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.companies c
    WHERE c.id = p_company_id AND c.status = 'active'
  ) THEN
    RAISE EXCEPTION 'La empresa no existe o esta suspendida.';
  END IF;

  IF NOT (public.ab_is_global_superadmin() OR public.ab_is_company_admin(p_company_id)) THEN
    RAISE EXCEPTION 'No tienes permiso para importar catalogo en esta empresa.';
  END IF;

  IF NULLIF(btrim(p_import_id), '') IS NULL THEN
    RAISE EXCEPTION 'El identificador de importacion es obligatorio.';
  END IF;

  IF CASE WHEN jsonb_typeof(p_rows) = 'array'
          THEN jsonb_array_length(p_rows)
          ELSE 0 END = 0 THEN
    RAISE EXCEPTION 'El archivo no contiene filas para importar.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.catalog_import_rows
    WHERE company_id = p_company_id AND import_id = btrim(p_import_id)
  ) THEN
    RAISE EXCEPTION 'El identificador de importacion ya fue utilizado en esta empresa.';
  END IF;

  IF jsonb_array_length(p_rows) > 10000 THEN
    RAISE EXCEPTION 'El lote supera el maximo de 10000 filas.';
  END IF;

  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(p_rows) e
  WHERE NULLIF(btrim(e.value->>'code'), '') IS NULL
     OR jsonb_typeof(e.value->'payload') IS DISTINCT FROM 'object';
  IF v_count > 0 THEN
    RAISE EXCEPTION 'Hay % filas sin codigo o con payload no valido.', v_count;
  END IF;

  SELECT count(*) INTO v_count
  FROM (
    SELECT e.value->>'code'
    FROM jsonb_array_elements(p_rows) e
    GROUP BY e.value->>'code'
    HAVING count(*) > 1
  ) duplicates;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'El archivo contiene codigos de articulo duplicados.';
  END IF;

  FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows)
  LOOP
    v_code := btrim(v_row->>'code');
    v_payload := v_row->'payload';
    v_quantity_text := COALESCE(
      NULLIF(btrim(v_row->>'quantity'), ''),
      NULLIF(btrim(v_payload->>'sc'), ''),
      '0'
    );

    IF v_quantity_text !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)
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
REVOKE ALL ON FUNCTION public.ab_import_company_catalog(uuid,text,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ab_import_company_catalog(uuid,text,jsonb) TO authenticated;
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
 THEN
      RAISE EXCEPTION 'Cantidad no numerica para articulo %.', v_code;
    END IF;

    v_quantity := v_quantity_text::numeric;
    IF v_quantity < 0 THEN
      RAISE EXCEPTION 'Cantidad negativa para articulo %.', v_code;
    END IF;

    v_payload := jsonb_set(v_payload, '{sc}', to_jsonb(v_quantity), true);

    INSERT INTO public.catalog_items(company_id, code, payload, updated_at)
    VALUES (p_company_id, v_code, v_payload, now())
    ON CONFLICT (company_id, code)
    DO UPDATE SET payload = EXCLUDED.payload, updated_at = now();

    PERFORM public.ab_set_inventory_balance(
      p_company_id,
      v_code,
      v_quantity,
      'import',
      'Importacion de catalogo ' || btrim(p_import_id),
      btrim(p_import_id)
    );

    INSERT INTO public.catalog_import_rows(
      company_id, import_id, catalog_type, code, payload, created_at
    )
    VALUES (
      p_company_id, btrim(p_import_id), 'items', v_code, v_payload, now()
    )
    ON CONFLICT (company_id, import_id, catalog_type, code)
    DO UPDATE SET payload = EXCLUDED.payload, created_at = now();

    v_processed := v_processed + 1;
  END LOOP;

  RETURN v_processed;
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

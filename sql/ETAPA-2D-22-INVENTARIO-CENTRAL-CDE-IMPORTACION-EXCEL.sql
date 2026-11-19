-- AB SYSTEM DEMO — Inventario por depósito e importación Excel v2
-- Ejecutar exclusivamente en AB-SYSTEM-DEMO después de revisar el contenido.
-- No modifica Ko'eju histórico. No altera pedidos ni descuenta stock por pedidos.
-- Los saldos legacy de inventory_balances se conservan sin asignarlos arbitrariamente
-- a CENTRAL o CDE. La primera importación del Excel completo establecerá ambos saldos.

BEGIN;

-- Preflight defensivo: no asumir que una tabla preexistente tiene la forma
-- esperada solo porque CREATE TABLE IF NOT EXISTS no falla.
DO $preflight$
DECLARE
  v_missing text;
  v_ok boolean;
BEGIN
  IF to_regclass('public.catalog_items') IS NULL
     OR to_regclass('public.catalog_import_rows') IS NULL
     OR to_regclass('public.companies') IS NULL THEN
    RAISE EXCEPTION 'ABORTADO: faltan tablas base de multiempresa; aplicar y validar 2D-21 primero.';
  END IF;

  SELECT string_agg(required.column_name, ', ')
    INTO v_missing
  FROM (VALUES
    ('catalog_items','company_id'),('catalog_items','code'),
    ('catalog_items','payload'),('catalog_items','updated_at'),
    ('catalog_import_rows','company_id'),('catalog_import_rows','import_id'),
    ('catalog_import_rows','catalog_type'),('catalog_import_rows','code'),
    ('catalog_import_rows','payload'),('catalog_import_rows','created_at')
  ) AS required(table_name,column_name)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema='public'
      AND c.table_name=required.table_name
      AND c.column_name=required.column_name
  );

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'ABORTADO: faltan columnas requeridas: %.', v_missing;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.catalog_items'::regclass
      AND contype='p'
      AND pg_get_constraintdef(oid)='PRIMARY KEY (company_id, code)'
  ) INTO v_ok;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'ABORTADO: catalog_items requiere PK (company_id, code).';
  END IF;

  IF to_regclass('public.inventory_location_balances') IS NOT NULL THEN
    SELECT string_agg(required.column_name, ', ')
      INTO v_missing
    FROM (VALUES
      ('company_id'),('product_code'),('location_code'),
      ('quantity'),('updated_at'),('updated_by')
    ) AS required(column_name)
    WHERE NOT EXISTS (
      SELECT 1 FROM information_schema.columns c
      WHERE c.table_schema='public'
        AND c.table_name='inventory_location_balances'
        AND c.column_name=required.column_name
    );
    IF v_missing IS NOT NULL THEN
      RAISE EXCEPTION 'ABORTADO: inventory_location_balances existente no coincide; faltan columnas: %.', v_missing;
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM pg_constraint
      WHERE conrelid='public.inventory_location_balances'::regclass
        AND contype='p'
        AND pg_get_constraintdef(oid)='PRIMARY KEY (company_id, product_code, location_code)'
    ) INTO v_ok;
    IF NOT v_ok THEN
      RAISE EXCEPTION 'ABORTADO: la PK existente de inventory_location_balances no es la esperada.';
    END IF;
  END IF;

  IF to_regclass('public.inventory_location_movements') IS NOT NULL THEN
    SELECT string_agg(required.column_name, ', ')
      INTO v_missing
    FROM (VALUES
      ('id'),('company_id'),('product_code'),('location_code'),
      ('movement_type'),('quantity_delta'),('quantity_before'),
      ('quantity_after'),('reason'),('source_ref'),('created_by'),('created_at')
    ) AS required(column_name)
    WHERE NOT EXISTS (
      SELECT 1 FROM information_schema.columns c
      WHERE c.table_schema='public'
        AND c.table_name='inventory_location_movements'
        AND c.column_name=required.column_name
    );
    IF v_missing IS NOT NULL THEN
      RAISE EXCEPTION 'ABORTADO: inventory_location_movements existente no coincide; faltan columnas: %.', v_missing;
    END IF;
  END IF;
END
$preflight$;

CREATE TABLE IF NOT EXISTS public.inventory_location_balances (
  company_id uuid NOT NULL,
  product_code text NOT NULL,
  location_code text NOT NULL CHECK (location_code IN ('CENTRAL','CDE')),
  quantity numeric(14,3) NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT inventory_location_balances_pkey PRIMARY KEY (company_id, product_code, location_code),
  CONSTRAINT inventory_location_balances_product_fkey
    FOREIGN KEY (company_id, product_code)
    REFERENCES public.catalog_items(company_id, code) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS public.inventory_location_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  product_code text NOT NULL,
  location_code text NOT NULL CHECK (location_code IN ('CENTRAL','CDE')),
  movement_type text NOT NULL CHECK (movement_type IN ('opening','import','adjustment')),
  quantity_delta numeric(14,3) NOT NULL,
  quantity_before numeric(14,3) NOT NULL CHECK (quantity_before >= 0),
  quantity_after numeric(14,3) NOT NULL CHECK (quantity_after >= 0),
  reason text NOT NULL,
  source_ref text NULL,
  created_by uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT inventory_location_movements_product_fkey
    FOREIGN KEY (company_id, product_code)
    REFERENCES public.catalog_items(company_id, code) ON DELETE RESTRICT,
  CONSTRAINT inventory_location_movements_math_check
    CHECK (quantity_after = quantity_before + quantity_delta)
);

CREATE INDEX IF NOT EXISTS inventory_location_movements_company_created_idx
  ON public.inventory_location_movements(company_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.ab_inventory_create_location_balances()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  INSERT INTO public.inventory_location_balances(company_id, product_code, location_code, quantity)
  VALUES
    (NEW.company_id, NEW.code, 'CENTRAL', 0),
    (NEW.company_id, NEW.code, 'CDE', 0)
  ON CONFLICT (company_id, product_code, location_code) DO NOTHING;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_catalog_items_create_location_balances ON public.catalog_items;
CREATE TRIGGER trg_catalog_items_create_location_balances
AFTER INSERT ON public.catalog_items
FOR EACH ROW EXECUTE FUNCTION public.ab_inventory_create_location_balances();

INSERT INTO public.inventory_location_balances(company_id, product_code, location_code, quantity)
SELECT ci.company_id, ci.code, loc.location_code, 0
FROM public.catalog_items ci
CROSS JOIN (VALUES ('CENTRAL'::text), ('CDE'::text)) AS loc(location_code)
ON CONFLICT (company_id, product_code, location_code) DO NOTHING;

ALTER TABLE public.inventory_location_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_location_movements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS inventory_location_balances_read_company ON public.inventory_location_balances;
CREATE POLICY inventory_location_balances_read_company
ON public.inventory_location_balances FOR SELECT TO authenticated
USING (public.ab_has_company_access(company_id) OR public.ab_is_global_superadmin());

DROP POLICY IF EXISTS inventory_location_movements_read_admin ON public.inventory_location_movements;
CREATE POLICY inventory_location_movements_read_admin
ON public.inventory_location_movements FOR SELECT TO authenticated
USING (public.ab_is_company_admin(company_id) OR public.ab_is_global_superadmin());

REVOKE ALL ON TABLE public.inventory_location_balances, public.inventory_location_movements FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.inventory_location_balances, public.inventory_location_movements TO authenticated;

CREATE OR REPLACE FUNCTION public.ab_set_inventory_location_balance(
  p_company_id uuid,
  p_product_code text,
  p_location_code text,
  p_quantity numeric,
  p_movement_type text,
  p_reason text,
  p_source_ref text DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_before numeric(14,3);
  v_delta numeric(14,3);
  v_actor uuid;
BEGIN
  v_actor := auth.uid();
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Se requiere una sesion autenticada.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.companies c WHERE c.id=p_company_id AND c.status='active') THEN
    RAISE EXCEPTION 'La empresa no existe o esta suspendida.';
  END IF;
  IF NOT (public.ab_is_global_superadmin() OR public.ab_is_company_admin(p_company_id)) THEN
    RAISE EXCEPTION 'No tienes permiso para actualizar el inventario de esta empresa.';
  END IF;
  IF p_location_code IS NULL OR p_location_code NOT IN ('CENTRAL','CDE') THEN RAISE EXCEPTION 'Deposito no valido.'; END IF;
  IF p_quantity IS NULL OR p_quantity < 0 THEN RAISE EXCEPTION 'La cantidad debe ser mayor o igual a cero.'; END IF;
  IF p_movement_type IS NULL OR p_movement_type NOT IN ('import','adjustment') THEN RAISE EXCEPTION 'Tipo de movimiento no permitido.'; END IF;
  IF NULLIF(btrim(p_reason),'') IS NULL THEN RAISE EXCEPTION 'El motivo es obligatorio.'; END IF;

  SELECT b.quantity INTO v_before
  FROM public.inventory_location_balances b
  WHERE b.company_id=p_company_id AND b.product_code=p_product_code AND b.location_code=p_location_code
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'No existe saldo inicial para el articulo y deposito indicados.'; END IF;

  v_delta := p_quantity-v_before;
  IF v_delta=0 THEN RETURN v_before; END IF;

  UPDATE public.inventory_location_balances
  SET quantity=p_quantity, updated_at=now(), updated_by=v_actor
  WHERE company_id=p_company_id AND product_code=p_product_code AND location_code=p_location_code;

  INSERT INTO public.inventory_location_movements(
    company_id,product_code,location_code,movement_type,quantity_delta,
    quantity_before,quantity_after,reason,source_ref,created_by
  ) VALUES (
    p_company_id,p_product_code,p_location_code,p_movement_type,v_delta,
    v_before,p_quantity,btrim(p_reason),p_source_ref,v_actor
  );
  RETURN p_quantity;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.ab_import_company_catalog_v2(
  p_company_id uuid,
  p_import_id text,
  p_rows jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_row jsonb;
  v_code text;
  v_payload jsonb;
  v_central numeric(14,3);
  v_cde numeric(14,3);
  v_count bigint;
  v_processed integer := 0;
  v_actor uuid;
BEGIN
  v_actor := auth.uid();
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Se requiere una sesion autenticada.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.companies c WHERE c.id=p_company_id AND c.status='active') THEN
    RAISE EXCEPTION 'La empresa no existe o esta suspendida.';
  END IF;
  IF NOT (public.ab_is_global_superadmin() OR public.ab_is_company_admin(p_company_id)) THEN
    RAISE EXCEPTION 'No tienes permiso para importar catalogo en esta empresa.';
  END IF;
  IF NULLIF(btrim(p_import_id),'') IS NULL THEN RAISE EXCEPTION 'El identificador de importacion es obligatorio.'; END IF;
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows)=0 THEN
    RAISE EXCEPTION 'El archivo no contiene filas validas.';
  END IF;
  IF jsonb_array_length(p_rows)>10000 THEN RAISE EXCEPTION 'El lote supera 10000 filas.'; END IF;
  IF EXISTS (SELECT 1 FROM public.catalog_import_rows WHERE company_id=p_company_id AND import_id=btrim(p_import_id)) THEN
    RAISE EXCEPTION 'El identificador de importacion ya fue utilizado.';
  END IF;

  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(p_rows) e
  WHERE NULLIF(btrim(e.value->>'code'),'') IS NULL
     OR jsonb_typeof(e.value->'payload') IS DISTINCT FROM 'object'
     OR NULLIF(btrim(e.value->'payload'->>'d'),'') IS NULL
     OR (
       NULLIF(btrim(e.value->'payload'->>'p1'),'') IS NOT NULL
       AND (e.value->'payload'->>'p1') !~ '^[0-9]+([.][0-9]{1,3})?$'
     )
     OR (
       NULLIF(btrim(e.value->'payload'->>'p2'),'') IS NOT NULL
       AND (e.value->'payload'->>'p2') !~ '^[0-9]+([.][0-9]{1,3})?$'
     )
     OR (
       NULLIF(btrim(e.value->'payload'->>'p3'),'') IS NOT NULL
       AND (e.value->'payload'->>'p3') !~ '^[0-9]+([.][0-9]{1,3})?$'
     )
     OR NULLIF(btrim(e.value->>'stock_central'),'') IS NULL
     OR NULLIF(btrim(e.value->>'stock_cde'),'') IS NULL
     OR (e.value->>'stock_central') !~ '^[0-9]+([.][0-9]{1,3})?$'
     OR (e.value->>'stock_cde') !~ '^[0-9]+([.][0-9]{1,3})?$';
  IF v_count>0 THEN RAISE EXCEPTION 'Hay % filas sin codigo, payload o stock valido.',v_count; END IF;

  -- La deteccion debe coincidir con el frontend: ignora espacios externos,
  -- diferencias entre mayusculas/minusculas y equivalencias Unicode NFKC.
  -- Se conserva el codigo original (solo btrim) al almacenarlo.
  SELECT count(*) INTO v_count FROM (
    SELECT upper(normalize(btrim(e.value->>'code'), NFKC)) AS normalized_code
    FROM jsonb_array_elements(p_rows) e
    GROUP BY upper(normalize(btrim(e.value->>'code'), NFKC))
    HAVING count(*)>1
  ) d;
  IF v_count>0 THEN RAISE EXCEPTION 'El archivo contiene codigos duplicados o equivalentes (espacios, mayusculas o Unicode).'; END IF;

  FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows)
  LOOP
    v_code := btrim(v_row->>'code');
    v_payload := v_row->'payload';
    v_central := (v_row->>'stock_central')::numeric;
    v_cde := (v_row->>'stock_cde')::numeric;

    INSERT INTO public.catalog_items(company_id,code,payload,updated_at)
    VALUES (p_company_id,v_code,v_payload,now())
    ON CONFLICT (company_id,code)
    DO UPDATE SET payload=public.catalog_items.payload || EXCLUDED.payload, updated_at=now();

    PERFORM public.ab_set_inventory_location_balance(
      p_company_id,v_code,'CENTRAL',v_central,'import',
      'Importacion Excel '||btrim(p_import_id),btrim(p_import_id)
    );
    PERFORM public.ab_set_inventory_location_balance(
      p_company_id,v_code,'CDE',v_cde,'import',
      'Importacion Excel '||btrim(p_import_id),btrim(p_import_id)
    );

    INSERT INTO public.catalog_import_rows(company_id,import_id,catalog_type,code,payload,created_at)
    VALUES (p_company_id,btrim(p_import_id),'items',v_code,v_payload,now());
    v_processed := v_processed+1;
  END LOOP;
  RETURN v_processed;
END;
$fn$;

REVOKE ALL ON FUNCTION public.ab_set_inventory_location_balance(uuid,text,text,numeric,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ab_set_inventory_location_balance(uuid,text,text,numeric,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.ab_import_company_catalog_v2(uuid,text,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ab_import_company_catalog_v2(uuid,text,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.ab_inventory_create_location_balances() FROM PUBLIC, anon, authenticated;

-- BORRADOR DE ENSAYO: no persistir hasta validar estructura existente,
-- ejecutar pruebas de RLS/JWT y aprobar expresamente el cambio.
ROLLBACK;

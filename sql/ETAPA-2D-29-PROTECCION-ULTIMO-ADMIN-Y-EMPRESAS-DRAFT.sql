-- AB SYSTEM DEMO — PROTECCION DE ULTIMO ADMINISTRADOR Y BLOQUEO DE BORRADO DE EMPRESAS
-- ETAPA 2D-29 — BORRADOR PARA REVISION (NO EJECUTAR)
-- Destino exclusivo: Supabase AB-SYSTEM-DEMO.
-- Ko'eju produccion: fuera de alcance.
--
-- OBJETIVOS:
-- 1) Impedir que DELETE/UPDATE deje una empresa sin company_admin activo.
-- 2) Serializar cambios de administradores por empresa con advisory transaction lock.
-- 3) Verificar el estado FINAL de UPDATE/DELETE multi-fila mediante transition tables.
-- 4) Bloquear DELETE y TRUNCATE de companies incluso si se omite RLS.
-- 5) Retirar la policy y el privilegio DELETE de authenticated: las empresas se suspenden,
--    nunca se eliminan desde la aplicacion.
--
-- PRECONDICION DETECTADA EN LA AUDITORIA:
-- DEMO2 actualmente no tiene un company_admin activo. Antes de aplicar este parche,
-- asignar un administrador de empresa autorizado a DEMO2 y volver a verificar.
-- El preflight de este archivo aborta si cualquier empresa no tiene al menos uno.
--
-- Este archivo contiene DDL dentro de una transaccion y termina en ROLLBACK.
-- Su inclusion en GitHub NO modifica Supabase. No cambiar a COMMIT sin revision,
-- pruebas PostgreSQL reales sobre una restauracion y aprobacion especifica.

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Preflight: estructura esperada y al menos un administrador activo
--    por empresa. No altera datos.
-- ---------------------------------------------------------------------
DO $preflight$
DECLARE
  v_missing text;
  v_companies_without_admin text;
BEGIN
  SELECT string_agg(required.object_name, ', ')
    INTO v_missing
  FROM (VALUES
    ('public.companies'),
    ('public.company_memberships')
  ) AS required(object_name)
  WHERE to_regclass(required.object_name) IS NULL;

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'ABORTADO: faltan tablas requeridas: %', v_missing;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger
    WHERE tgrelid='public.company_memberships'::regclass
      AND tgname='trg_company_memberships_guard_identity'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION
      'ABORTADO: falta trg_company_memberships_guard_identity; no se puede garantizar la identidad fija de las membresias.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='company_memberships'
      AND column_name='company_id' AND data_type='uuid'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='company_memberships'
      AND column_name='user_id' AND data_type='uuid'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='company_memberships'
      AND column_name='role'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='company_memberships'
      AND column_name='status'
  ) THEN
    RAISE EXCEPTION 'ABORTADO: company_memberships no tiene las columnas esperadas.';
  END IF;

  SELECT string_agg(c.code, ', ' ORDER BY c.code)
    INTO v_companies_without_admin
  FROM public.companies c
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.company_memberships m
    WHERE m.company_id=c.id
      AND m.role='company_admin'
      AND m.status='active'
  );

  IF v_companies_without_admin IS NOT NULL THEN
    RAISE EXCEPTION
      'ABORTADO: estas empresas no tienen administrador activo: %. Asignar un administrador y repetir el preflight.',
      v_companies_without_admin;
  END IF;
END
$preflight$;

-- ---------------------------------------------------------------------
-- 1. Guard por fila.
--    El lock se obtiene ANTES de modificar o borrar una membresia admin.
--    Dos transacciones que intenten retirar administradores de la misma
--    empresa quedan serializadas. El lock se libera al finalizar la transaccion.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ab_prevent_last_active_company_admin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_other_active_admins bigint;
BEGIN
  -- Solo interesa retirar o desactivar una membresia que hoy es admin activo.
  IF OLD.role IS DISTINCT FROM 'company_admin'
     OR OLD.status IS DISTINCT FROM 'active' THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;

  -- Un UPDATE que mantiene al usuario como admin activo no lo retira.
  IF TG_OP = 'UPDATE'
     AND NEW.role = 'company_admin'
     AND NEW.status = 'active' THEN
    RETURN NEW;
  END IF;

  -- Lock transaccional por empresa: previene carreras entre sesiones concurrentes.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(OLD.company_id::text, 0)
  );

  SELECT pg_catalog.count(*)
    INTO v_other_active_admins
  FROM public.company_memberships m
  WHERE m.company_id = OLD.company_id
    AND m.role = 'company_admin'
    AND m.status = 'active'
    AND m.user_id <> OLD.user_id;

  IF v_other_active_admins = 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = '23514',
      MESSAGE = 'No se puede quitar, suspender o degradar al ultimo administrador activo de la empresa.',
      HINT = 'Asigne y active otro company_admin antes de retirar esta membresia.';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_company_memberships_prevent_last_admin
  ON public.company_memberships;

CREATE TRIGGER trg_company_memberships_prevent_last_admin
BEFORE UPDATE OR DELETE ON public.company_memberships
FOR EACH ROW
EXECUTE FUNCTION public.ab_prevent_last_active_company_admin();

-- ---------------------------------------------------------------------
-- 2. Guard de sentencia para UPDATE multi-fila.
--    La validacion row-level serializa transacciones; esta segunda capa
--    comprueba el estado final de toda la sentencia, incluso si se intentan
--    degradar varios administradores en una sola operacion.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ab_assert_active_admin_after_membership_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_company_id uuid;
BEGIN
  FOR v_company_id IN
    SELECT DISTINCT old_rows.company_id
    FROM old_rows
    JOIN new_rows
      ON new_rows.company_id = old_rows.company_id
     AND new_rows.user_id = old_rows.user_id
    WHERE old_rows.role = 'company_admin'
      AND old_rows.status = 'active'
      AND (
        new_rows.role IS DISTINCT FROM 'company_admin'
        OR new_rows.status IS DISTINCT FROM 'active'
      )
  LOOP
    -- La fila BEFORE ya tomo este lock; se repite por claridad y defensa.
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_company_id::text, 0)
    );

    IF NOT EXISTS (
      SELECT 1
      FROM public.company_memberships m
      WHERE m.company_id = v_company_id
        AND m.role = 'company_admin'
        AND m.status = 'active'
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '23514',
        MESSAGE = 'La operacion dejaria a la empresa sin administrador activo.',
        HINT = 'Mantenga al menos un company_admin activo por empresa.';
    END IF;
  END LOOP;

  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_company_memberships_assert_admin_after_update
  ON public.company_memberships;

CREATE TRIGGER trg_company_memberships_assert_admin_after_update
AFTER UPDATE ON public.company_memberships
REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
FOR EACH STATEMENT
EXECUTE FUNCTION public.ab_assert_active_admin_after_membership_update();

-- ---------------------------------------------------------------------
-- 3. Guard de sentencia para DELETE multi-fila.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ab_assert_active_admin_after_membership_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_company_id uuid;
BEGIN
  FOR v_company_id IN
    SELECT DISTINCT old_rows.company_id
    FROM old_rows
    WHERE old_rows.role = 'company_admin'
      AND old_rows.status = 'active'
  LOOP
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_company_id::text, 0)
    );

    IF NOT EXISTS (
      SELECT 1
      FROM public.company_memberships m
      WHERE m.company_id = v_company_id
        AND m.role = 'company_admin'
        AND m.status = 'active'
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '23514',
        MESSAGE = 'La operacion dejaria a la empresa sin administrador activo.',
        HINT = 'Mantenga al menos un company_admin activo por empresa.';
    END IF;
  END LOOP;

  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_company_memberships_assert_admin_after_delete
  ON public.company_memberships;

CREATE TRIGGER trg_company_memberships_assert_admin_after_delete
AFTER DELETE ON public.company_memberships
REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT
EXECUTE FUNCTION public.ab_assert_active_admin_after_membership_delete();

-- ---------------------------------------------------------------------
-- 4. Bloqueo absoluto de borrado fisico de empresas.
--    Es trigger de sentencia para bloquear DELETE y TRUNCATE, incluidos
--    intentos con service_role. La operacion normal es suspender la empresa.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ab_block_company_physical_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = '55000',
    MESSAGE = 'La eliminacion fisica de empresas esta deshabilitada.',
    HINT = 'Cambie companies.status a suspended para conservar el historial.';
END;
$function$;

DROP TRIGGER IF EXISTS trg_companies_block_physical_delete
  ON public.companies;

CREATE TRIGGER trg_companies_block_physical_delete
BEFORE DELETE OR TRUNCATE ON public.companies
FOR EACH STATEMENT
EXECUTE FUNCTION public.ab_block_company_physical_delete();

-- La aplicacion no necesita DELETE ni TRUNCATE sobre companies.
-- Se retira tambien la policy anterior que autorizaba DELETE al superadmin.
DROP POLICY IF EXISTS companies_superadmin_delete ON public.companies;
REVOKE DELETE, TRUNCATE ON TABLE public.companies FROM authenticated;

-- ---------------------------------------------------------------------
-- 5. Las funciones son exclusivamente internas de triggers.
--    No requieren EXECUTE desde PostgREST/cliente.
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.ab_prevent_last_active_company_admin()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ab_assert_active_admin_after_membership_update()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ab_assert_active_admin_after_membership_delete()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ab_block_company_physical_delete()
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. Verificacion estatica del estado resultante dentro de esta transaccion.
-- ---------------------------------------------------------------------
DO $verify$
DECLARE
  v_missing_triggers text;
  v_delete_policy boolean;
  v_delete_grant boolean;
BEGIN
  SELECT string_agg(expected.trigger_name, ', ')
    INTO v_missing_triggers
  FROM (VALUES
    ('trg_company_memberships_prevent_last_admin'),
    ('trg_company_memberships_assert_admin_after_update'),
    ('trg_company_memberships_assert_admin_after_delete'),
    ('trg_companies_block_physical_delete')
  ) AS expected(trigger_name)
  WHERE NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_trigger t
    WHERE t.tgname = expected.trigger_name
      AND NOT t.tgisinternal
  );

  IF v_missing_triggers IS NOT NULL THEN
    RAISE EXCEPTION 'Verificacion fallida: faltan triggers: %', v_missing_triggers;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public'
      AND tablename='companies'
      AND policyname='companies_superadmin_delete'
  ) INTO v_delete_policy;

  IF v_delete_policy THEN
    RAISE EXCEPTION 'Verificacion fallida: permanece la policy de DELETE de companies.';
  END IF;

  SELECT has_table_privilege('authenticated', 'public.companies', 'DELETE')
    INTO v_delete_grant;

  IF v_delete_grant THEN
    RAISE EXCEPTION 'Verificacion fallida: authenticated conserva DELETE sobre companies.';
  END IF;
END
$verify$;

-- SEGURIDAD: BORRADOR. No cambiar a COMMIT.
ROLLBACK;

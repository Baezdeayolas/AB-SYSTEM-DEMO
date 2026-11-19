import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const patch = await readFile(
  "sql/ETAPA-2D-29-PROTECCION-ULTIMO-ADMIN-Y-EMPRESAS-DRAFT.sql",
  "utf8",
);

test("last active company admin cannot be deleted, suspended or demoted", () => {
  assert.match(patch, /CREATE OR REPLACE FUNCTION public\.ab_prevent_last_active_company_admin/);
  assert.match(patch, /BEFORE UPDATE OR DELETE ON public\.company_memberships/);
  assert.match(patch, /OLD\.role IS DISTINCT FROM 'company_admin'/);
  assert.match(patch, /OLD\.status IS DISTINCT FROM 'active'/);
  assert.match(patch, /pg_advisory_xact_lock/);
  assert.match(patch, /hashtextextended\(OLD\.company_id::text, 0\)/);
  assert.match(patch, /m\.user_id <> OLD\.user_id/);
  assert.match(patch, /v_other_active_admins = 0/);
  assert.match(patch, /ERRCODE = '23514'/);
});

test("multi-row membership updates and deletes validate the final company state", () => {
  assert.match(patch, /REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows/);
  assert.match(patch, /AFTER UPDATE ON public\.company_memberships/);
  assert.match(patch, /REFERENCING OLD TABLE AS old_rows\s+FOR EACH STATEMENT/);
  assert.match(patch, /AFTER DELETE ON public\.company_memberships/);
  assert.match(patch, /La operacion dejaria a la empresa sin administrador activo/);
});

test("physical company deletion and truncation are blocked at database level", () => {
  assert.match(patch, /BEFORE DELETE OR TRUNCATE ON public\.companies/);
  assert.match(patch, /eliminacion fisica de empresas esta deshabilitada/);
  assert.match(patch, /DROP POLICY IF EXISTS companies_superadmin_delete/);
  assert.match(patch, /REVOKE DELETE, TRUNCATE ON TABLE public\.companies FROM authenticated/);
});

test("preflight requires the existing membership identity guard", () => {
  assert.match(patch, /trg_company_memberships_guard_identity/);
  assert.match(patch, /no se puede garantizar la identidad fija de las membresias/);
});

test("preflight refuses to install while any company has no active admin", () => {
  assert.match(patch, /v_companies_without_admin/);
  assert.match(patch, /m\.role='company_admin'/);
  assert.match(patch, /m\.status='active'/);
  assert.match(patch, /Asignar un administrador y repetir el preflight/);
});

test("trigger functions are invoker-only, use a fixed search_path and are not client RPCs", () => {
  const functionBlocks = patch.match(/CREATE OR REPLACE FUNCTION[\s\S]*?\$function\$;/g) ?? [];
  assert.equal(functionBlocks.length, 4);
  for (const block of functionBlocks) {
    assert.match(block, /SECURITY INVOKER/);
    assert.match(block, /SET search_path = ''/);
  }
  assert.match(patch, /REVOKE ALL ON FUNCTION public\.ab_prevent_last_active_company_admin\(\)\s+FROM PUBLIC, anon, authenticated/);
});

test("patch remains a non-persistent draft", () => {
  assert.match(patch, /^BEGIN;/m);
  assert.match(patch, /ROLLBACK;\s*$/);
  assert.doesNotMatch(patch, /COMMIT;\s*$/);
});

import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const edge = await readFile("supabase/functions/admin-users/index.ts", "utf8");
const app = await readFile("cloud-sync-demo.js", "utf8");
const html = await readFile("index.html", "utf8");

test("admin endpoint verifies global superadmin before dispatching actions", () => {
  const guard = edge.indexOf('.eq("role", "superadmin_global")');
  const dispatch = edge.indexOf('const action = String(body.action || "")');
  assert.ok(guard >= 0 && dispatch > guard);
  assert.match(edge, /if\s*\(!globalRole\)\s*return reply\(\{ error:/);
});

test("company creation validates code and name on the server", () => {
  assert.match(edge, /code\.length|\^\[A-Z0-9_-\]\{2,24\}\$/);
  assert.match(edge, /name\.length > 120/);
  assert.match(edge, /action === "create-company"/);
});

test("company status is reversible and limited to active or suspended", () => {
  assert.match(edge, /action === "set-company-status"/);
  assert.match(edge, /!\["active", "suspended"\]\.includes\(status\)/);
  assert.match(app, /callGlobalAdmin\('set-company-status'/);
});

test("removing a membership preserves the auth account and last company admin", () => {
  assert.match(edge, /action === "remove-membership"/);
  assert.match(edge, /No se puede quitar al último administrador activo/);
  assert.doesNotMatch(edge, /auth\.admin\.deleteUser/);
  assert.match(app, /Su cuenta de acceso se conservará/);
  assert.match(app, /if\(activeCompany\?\.id===companyId\)await loadData\(\)/);
});

test("inviting an existing user does not overwrite their global profile role", () => {
  assert.match(edge, /select\("id,role"\)/);
  assert.match(edge, /update\(\{ seller_label: displayName \}\)/);
  assert.match(edge, /role: "seller"/);
});

test("global admin forms do not write companies directly from the browser", () => {
  assert.match(app, /callGlobalAdmin\('create-company'/);
  assert.doesNotMatch(app, /db\.from\('companies'\)\.insert/);
  assert.doesNotMatch(app, /db\.from\('companies'\)\.update/);
  assert.match(html, /suspenden\/reactivan sin borrar su historial/);
});

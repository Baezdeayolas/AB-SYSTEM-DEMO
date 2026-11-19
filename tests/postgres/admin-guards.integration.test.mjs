import test, { before } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { execFileSync, spawn } from "node:child_process";
import { randomUUID } from "node:crypto";

const patchPath = "sql/ETAPA-2D-29-PROTECCION-ULTIMO-ADMIN-Y-EMPRESAS-DRAFT.sql";
const fixturePath = "tests/postgres/admin-guards-fixture.sql";
const psqlArgs = ["-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-d", "postgresql://postgres:postgres@127.0.0.1:5432/postgres"];

function runSql(sql) {
  return execFileSync("psql", [...psqlArgs, "-c", sql], { encoding: "utf8" }).trim();
}
function expectSqlstate(sql, state) {
  const wrapped = "DO $test$ BEGIN BEGIN " + sql +
    "; RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'Expected SQLSTATE " + state +
    ", but statement succeeded'; EXCEPTION WHEN SQLSTATE '" + state +
    "' THEN NULL; END; END $test$;";
  runSql(wrapped);
}
async function createCompany(code, adminCount = 1) {
  const companyId = randomUUID();
  const users = Array.from({ length: adminCount }, () => randomUUID());
  const values = users.map((userId) =>
    "('" + companyId + "', '" + userId + "', 'company_admin', 'active')"
  ).join(", ");
  runSql("INSERT INTO public.companies (id, code) VALUES ('" + companyId + "', '" + code + "');" +
    "INSERT INTO public.company_memberships (company_id, user_id, role, status) VALUES " + values + ";");
  return { companyId, users };
}
function spawnPsql(sql) {
  return new Promise((resolve, reject) => {
    const child = spawn("psql", psqlArgs, { env: process.env, stdio: ["pipe", "pipe", "pipe"] });
    let stdout = "", stderr = "";
    child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout += chunk; });
    child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => resolve({ code, stdout, stderr }));
    child.stdin.end(sql);
  });
}
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

before(async () => {
  const patch = await readFile(patchPath, "utf8");
  assert.match(patch, /ROLLBACK;\s*$/);
  execFileSync("psql", [...psqlArgs, "-f", fixturePath], { stdio: "inherit" });
  const executablePatch = patch.replace(/ROLLBACK;\s*$/, "COMMIT;");
  execFileSync("psql", [...psqlArgs], { input: executablePatch, encoding: "utf8", stdio: ["pipe", "inherit", "inherit"] });
});

test("A — DELETE of the only active administrator is rejected (23514)", async () => {
  const c = await createCompany("CASE_A");
  expectSqlstate("DELETE FROM public.company_memberships WHERE company_id='" + c.companyId + "'", "23514");
  assert.equal(runSql("SELECT count(*) FROM public.company_memberships WHERE company_id='" + c.companyId + "' AND status='active' AND role='company_admin'"), "1");
});
test("B — suspending the only active administrator is rejected (23514)", async () => {
  const c = await createCompany("CASE_B");
  expectSqlstate("UPDATE public.company_memberships SET status='suspended' WHERE company_id='" + c.companyId + "'", "23514");
  assert.equal(runSql("SELECT count(*) FROM public.company_memberships WHERE company_id='" + c.companyId + "' AND status='active' AND role='company_admin'"), "1");
});
test("C — demoting the only active administrator is rejected (23514)", async () => {
  const c = await createCompany("CASE_C");
  expectSqlstate("UPDATE public.company_memberships SET role='seller' WHERE company_id='" + c.companyId + "'", "23514");
  assert.equal(runSql("SELECT count(*) FROM public.company_memberships WHERE company_id='" + c.companyId + "' AND status='active' AND role='company_admin'"), "1");
});
test("D — one of two active administrators can be removed", async () => {
  const c = await createCompany("CASE_D", 2);
  runSql("DELETE FROM public.company_memberships WHERE company_id='" + c.companyId + "' AND user_id='" + c.users[0] + "'");
  assert.equal(runSql("SELECT count(*) FROM public.company_memberships WHERE company_id='" + c.companyId + "' AND status='active' AND role='company_admin'"), "1");
});
test("E — removing the remaining administrator is rejected (23514)", async () => {
  const c = await createCompany("CASE_E", 2);
  runSql("DELETE FROM public.company_memberships WHERE company_id='" + c.companyId + "' AND user_id='" + c.users[0] + "'");
  expectSqlstate("DELETE FROM public.company_memberships WHERE company_id='" + c.companyId + "' AND user_id='" + c.users[1] + "'", "23514");
  assert.equal(runSql("SELECT count(*) FROM public.company_memberships WHERE company_id='" + c.companyId + "' AND status='active' AND role='company_admin'"), "1");
});
test("F — bulk demotion of every administrator is rejected atomically (23514)", async () => {
  const c = await createCompany("CASE_F", 2);
  expectSqlstate("UPDATE public.company_memberships SET role='seller' WHERE company_id='" + c.companyId + "' AND role='company_admin'", "23514");
  assert.equal(runSql("SELECT count(*) FROM public.company_memberships WHERE company_id='" + c.companyId + "' AND status='active' AND role='company_admin'"), "2");
});
test("G — concurrent removals serialize and preserve at least one administrator", async () => {
  const c = await createCompany("CASE_G", 2);
  const firstSql = "BEGIN; DELETE FROM public.company_memberships WHERE company_id='" + c.companyId + "' AND user_id='" + c.users[0] + "'; SELECT pg_sleep(2); COMMIT;";
  const secondSql = "BEGIN; DELETE FROM public.company_memberships WHERE company_id='" + c.companyId + "' AND user_id='" + c.users[1] + "'; COMMIT;";
  const first = spawnPsql(firstSql);
  await sleep(300);
  const second = spawnPsql(secondSql);
  const results = await Promise.all([first, second]);
  assert.equal(results[0].code, 0, "first session failed: " + results[0].stderr);
  assert.notEqual(results[1].code, 0, "second session should fail after waiting for the advisory lock");
  assert.match(results[1].stderr, /23514|ultimo administrador activo/i);
  assert.equal(runSql("SELECT count(*) FROM public.company_memberships WHERE company_id='" + c.companyId + "' AND status='active' AND role='company_admin'"), "1");
});
test("H — physical company DELETE is blocked (55000)", async () => {
  const c = await createCompany("CASE_H");
  expectSqlstate("DELETE FROM public.companies WHERE id='" + c.companyId + "'", "55000");
  assert.equal(runSql("SELECT count(*) FROM public.companies WHERE id='" + c.companyId + "'"), "1");
});
test("I — TRUNCATE companies is blocked (55000)", () => {
  expectSqlstate("TRUNCATE TABLE public.companies", "55000");
  assert.ok(Number(runSql("SELECT count(*) FROM public.companies")) > 0);
});
test("J — suspending a company is allowed and preserves its memberships", async () => {
  const c = await createCompany("CASE_J");
  runSql("UPDATE public.companies SET status='suspended' WHERE id='" + c.companyId + "'");
  assert.equal(runSql("SELECT status FROM public.companies WHERE id='" + c.companyId + "'"), "suspended");
  assert.equal(runSql("SELECT count(*) FROM public.company_memberships WHERE company_id='" + c.companyId + "'"), "1");
});

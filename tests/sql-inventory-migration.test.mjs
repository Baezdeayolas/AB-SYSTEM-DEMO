import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const baseMigration = await readFile("sql/ETAPA-2D-21-MIGRACION-MULTIEMPRESA-DEMO-CONSOLIDADA-DRAFT.sql", "utf8");
const locationMigration = await readFile("sql/ETAPA-2D-22-INVENTARIO-CENTRAL-CDE-IMPORTACION-EXCEL.sql", "utf8");

test("base multi-company migration does not recreate legacy inventory tables", () => {
  assert.doesNotMatch(baseMigration, /CREATE TABLE\s+(?:IF NOT EXISTS\s+)?public\.inventory_balances\b/i);
  assert.doesNotMatch(baseMigration, /CREATE TABLE\s+(?:IF NOT EXISTS\s+)?public\.inventory_movements\b/i);
  assert.doesNotMatch(baseMigration, /ab_set_inventory_balance\s*\(|ab_import_company_catalog\s*\(/i);
  assert.match(baseMigration, /inventory_location_balances/);
  assert.match(baseMigration, /ROLLBACK;\s*$/);
});

test("location inventory migration targets CENTRAL/CDE tables and RPCs only", () => {
  assert.match(locationMigration, /inventory_location_balances/);
  assert.match(locationMigration, /inventory_location_movements/);
  assert.match(locationMigration, /ab_set_inventory_location_balance/);
  assert.match(locationMigration, /ab_import_company_catalog_v2/);
  assert.match(locationMigration, /'CENTRAL'.*'CDE'/s);
  assert.doesNotMatch(locationMigration, /CREATE TABLE\s+(?:IF NOT EXISTS\s+)?public\.inventory_balances\b/i);
  assert.doesNotMatch(locationMigration, /DELETE\s+FROM\s+public\.catalog_items/i);
  assert.doesNotMatch(locationMigration, /public\.orders/i);
});

test("inventory migration remains non-persistent until a reviewed live test", () => {
  assert.match(locationMigration, /ROLLBACK;\s*$/);
  assert.doesNotMatch(locationMigration, /COMMIT;\s*$/);
});

test("Excel import validates normalized duplicate product codes", () => {
  assert.match(locationMigration, /upper\(normalize\(btrim\(e\.value->>'code'\), NFKC\)\)/);
  assert.match(locationMigration, /GROUP BY upper\(normalize\(btrim\(e\.value->>'code'\), NFKC\)\)/);
});

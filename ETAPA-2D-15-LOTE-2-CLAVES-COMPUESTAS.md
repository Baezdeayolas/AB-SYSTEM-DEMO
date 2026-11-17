# ETAPA 2D-15 — Lote 2: claves y unicidad por empresa

**Rama:** `work/adaptacion-multiempresa-v1`  
**Estado:** borrador de revisión; no ejecutado.

## Archivo SQL

`sql/ETAPA-2D-15-LOTE-2-CLAVES-COMPUESTAS-DRAFT.sql`

## Cambios propuestos

| Tabla | Clave objetivo |
|---|---|
| catalog_items | (company_id, code) |
| catalog_clients | (company_id, code) |
| catalog_import_rows | (company_id, import_id, catalog_type, code) |
| seller_assignments | (company_id, user_id) |
| orders | conserva PK id; unicidad legacy pasa a ser scoped por empresa |

La asignación de vendedor incorpora además una FK compuesta a `company_memberships(company_id,user_id)`, para impedir asignar a una persona fuera de esa empresa.

## Guardas

- requiere Lote 1 aplicado y confirmado;
- aborta si falta `company_id` o hay valores NULL;
- exige UNIQUE(company_id,user_id) en company_memberships;
- aborta si hay FK externas que dependan de las claves que se van a sustituir;
- exige que las PK coincidan con el diagnóstico recibido;
- exige el índice de unicidad de pedidos creado por Lote 1;
- verifica las PK resultantes antes de finalizar.

## Fuera de alcance

No cambia RLS, políticas, permisos, triggers ni Realtime. No modifica `inventory_current`, inventario físico, payloads, precios ni pedidos. No reserva ni descuenta stock. No elimina productos o clientes.

## Dependencia y advertencia

Este lote depende de que el Lote 1 haya sido aplicado con éxito. Como ambos lotes están en revisión y Lote 1 aún no se ha ejecutado, **no ejecutar Lote 2 antes de Lote 1**. Ambos scripts terminan en `ROLLBACK` para que su ejecución literal no persista modificaciones. Antes de autorizar COMMIT se requiere restauración de respaldo probada, confirmar destino AB-SYSTEM-DEMO y cerrar el inventario de escritores externos.

No desplegar frontend multiempresa todavía: las políticas de seguridad y los escritores de datos deben migrarse en el lote siguiente.

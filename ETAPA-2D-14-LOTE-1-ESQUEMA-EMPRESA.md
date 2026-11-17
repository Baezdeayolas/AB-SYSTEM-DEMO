# ETAPA 2D-14 — Lote 1: esquema empresarial aditivo

**Repositorio:** `Baezdeayolas/AB-SYSTEM-DEMO`  
**Rama:** `work/adaptacion-multiempresa-v1`  
**Estado:** borrador SQL para revisión; NO ejecutado y NO autorizado para ejecución.

## Objetivo

Preparar las tablas comerciales existentes para incorporar aislamiento por empresa sin reemplazar todavía las claves legacy ni cambiar políticas de seguridad.

## Archivo SQL

`sql/ETAPA-2D-14-LOTE-1-ESQUEMA-EMPRESA-DRAFT.sql`

El borrador:
- agrega `company_id` a productos, clientes, filas de importación, pedidos y asignaciones de vendedores;
- agrega `orders.created_by`, dejando NULL el creador histórico no verificable;
- asigna filas existentes a la única empresa `KOEJU` solo si el código existe exactamente una vez y los propietarios de pedidos/asignaciones son vendedores activos de esa empresa;
- agrega claves foráneas e índices compuestos de transición;
- conserva todas las claves primarias y restricciones legacy;
- finaliza deliberadamente con `ROLLBACK`, de modo que copiar y ejecutar el borrador tal cual no persiste cambios.

## Decisiones explícitas

1. No se toca el proyecto histórico Ko'eju.
2. No se crea una segunda empresa todavía.
3. No se cambia ninguna política RLS, GRANT, trigger ni publicación Realtime en este lote.
4. No se modifica `payload`, `sc`, `sd`, precios ni pedidos.
5. Crear/editar pedidos no descuenta ni reserva stock.
6. Los artículos ausentes de Excel no se borran ni se ponen a cero.
7. `inventory_current` se mantiene como tabla legacy de una sola fila (`id=1`); no será la fuente multiempresa. El stock objetivo será normalizado por empresa, artículo y depósito CENTRAL/CDE en una etapa separada.
8. Las PK globales de `catalog_items` y `catalog_clients`, la PK de `seller_assignments` y la unicidad legacy de `orders` se mantienen hasta el Lote 2.

## Validaciones incorporadas

- exige exactamente una empresa con `code='KOEJU'`;
- aborta si hay filas previamente asignadas a otra empresa;
- aborta si algún pedido no tiene propietario verificable como vendedor activo de KOEJU;
- aborta si una asignación de vendedor no corresponde a una membresía activa;
- valida que ninguna fila quede sin `company_id`;
- todas las operaciones DDL/DML están dentro de una transacción.

## Limitaciones y siguiente trabajo

Este lote NO habilita la aplicación multiempresa ni debe ejecutarse todavía:
- las columnas permanecen nullable para identificar y corregir escritores legacy antes de imponer NOT NULL;
- las políticas actuales permisivas siguen vigentes y requieren un lote separado de RLS;
- las PK legacy aún impiden códigos duplicados entre empresas;
- la tabla `inventory_current` y el modelo de precios/stock normalizado requieren un diseño específico;
- no se ha probado restauración del respaldo DEMO ni se ha cerrado el inventario de Edge Functions, webhooks, cron y clientes externos.

## Revisión SQL necesaria

El script debe revisarse contra el estado actual de DEMO inmediatamente antes de una ejecución autorizada. Aunque contiene guardas, el administrador debe confirmar el proyecto destino y contar con restauración probada. No ejecutar en Ko'eju histórico/producción.

## Registro

No se ejecutó SQL, no se modificó Supabase, no se modificaron datos, no se cambió RLS, no se publicó la app y no se hizo merge.

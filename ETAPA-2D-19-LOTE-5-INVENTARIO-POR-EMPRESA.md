# ETAPA 2D-19 — Lote 5: inventario por empresa

**Destino:** AB-SYSTEM-DEMO exclusivamente.  
**Estado:** borrador de revisión; SQL termina en ROLLBACK. No ejecutar todavía.

## Qué resuelve

El inventario deja de depender de la fila global `inventory_current(id=1)`. Se crean:

- `inventory_balances`: saldo actual por `(company_id, product_code)`.
- `inventory_movements`: historial append-only de aperturas, importaciones y ajustes.
- `ab_set_inventory_balance(...)`: RPC transaccional para establecer un saldo y registrar la diferencia en el historial.
- Trigger que crea saldo inicial cero cuando se incorpora un producto nuevo.
- RLS: miembros activos pueden leer el saldo de su empresa; solo administradores pueden leer el historial; las escrituras se realizan mediante la RPC.

## Fuente del saldo inicial

La interfaz actual muestra el stock desde `catalog_items.payload.sc`. El borrador toma ese valor como saldo de apertura y no modifica el JSONB original.

Antes de crear las tablas, el preflight exige:
- que `catalog_items` ya tenga PK `(company_id, code)`;
- que `inventory_current` conserve una única fila id=1 con `items = []`;
- que todo valor no vacío de `payload.sc` sea numérico y no negativo;
- que las tablas normalizadas todavía no existan.

Si cualquiera de estas condiciones no se cumple, la transacción aborta sin persistir cambios. No se intenta adivinar ni combinar fuentes de stock.

## Regla de pedidos

Crear un pedido **no descuenta ni reserva stock**. Este lote no tiene trigger ni función que se ejecute al insertar pedidos. Los cambios de inventario son independientes y explícitos.

## Cambios de frontend incluidos

`cloud-sync-demo.js` ahora consulta `inventory_balances` por empresa y usa su cantidad para mostrar el stock, en lugar de confiar en el campo histórico `payload.sc`. El lote incorpora `ab_import_company_catalog`, una RPC masiva transaccional para recibir filas `{code,payload,quantity}`, crear/actualizar artículos y ajustar sus saldos. El parser/selector de Excel y la conexión de la pantalla todavía no están implementados.

## Pendientes antes de aprobar

1. Ejecutar el borrador en una copia aislada de DEMO y comprobar tipos reales de `payload.sc`.
2. Conectar el parser/selector Excel con `ab_import_company_catalog` y probar el lote completo; la RPC ya está preparada y no borra artículos ausentes.
3. Probar RLS con JWT de superadmin, company_admin, seller y usuario sin membresía.
4. Verificar las dos tablas nuevas y los permisos de RPC con el Lote 6.
5. No desplegar el frontend que consulta `inventory_balances` hasta que este lote y el lote de privilegios estén aplicados y probados.

## Estado de datos

El respaldo DEMO restaurado localmente contiene 5 productos y 1 fila legacy de `inventory_current`. El conteo no confirma por sí mismo los valores de `payload.sc`; por eso el SQL valida cada valor y aborta si no puede interpretarlo sin pérdida.

No se modificó Supabase DEMO ni Ko’ẽju de producción. No se ejecutó SQL ni se publicó la aplicación.

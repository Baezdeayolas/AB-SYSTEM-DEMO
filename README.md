# AB SYSTEM — versión candidata DEMO

Entorno independiente de desarrollo multiempresa. No es producción.

## Rama y destino
- Repositorio: `Baezdeayolas/AB-SYSTEM-DEMO`
- Rama: `work/adaptacion-multiempresa-v1`
- Supabase DEMO: `https://druugcvqxxanhtdkqnjd.supabase.co`
- Ko’ẽju histórico y su Supabase permanecen separados e intactos.

## Funciones incorporadas
- Inicio de sesión Supabase y contexto de empresa según membresía.
- Catálogo, clientes, asignaciones y pedidos filtrados por empresa.
- Pedidos con empresa, vendedor propietario y usuario creador.
- Guardar un pedido no factura, no reserva y no descuenta existencias.
- Stock por depósito CENTRAL y CDE.
- Importación Excel con vista previa, detección de duplicados y validación de código, descripción, existencias y tres listas de precios.
- Los productos nuevos se incorporan; los ausentes del archivo no se eliminan.
- Comprobante imprimible que permite guardar como PDF desde el navegador.

## Instalación de la versión candidata
## Estado de migración (NO ejecutar SQL todavía)

La empresa **DEMO2** (UUID existente `393b1b07-140f-46c7-a866-4436d59edeec`) será renombrada a **AB SYSTEM DEMO**, conservando su UUID. La empresa **KOEJU** (UUID `c8c4f6bf-a941-48a2-be99-6322b4ac19fd`) permanece intacta como fuente dentro de esta base DEMO. Los productos se copiarán a DEMO2 y los clientes de DEMO2 serán ficticios, sin datos personales ni financieros reales. Ko’ẽju producción y su Supabase separado no se modifican.

La migración 2D-21 sigue bloqueada: el backfill a `code='KOEJU'` es correcto porque conserva los datos existentes en su empresa fuente; el destino AB SYSTEM DEMO es `DEMO2`. Sin embargo, el consolidado todavía incluye un Lote 5 que intenta crear `public.inventory_balances`, tabla legacy que ya existe en este proyecto. Debe separarse ese lote y coordinarse con el inventario nuevo CENTRAL/CDE antes de ejecutar. El archivo termina en `ROLLBACK` y no persiste cambios.

El lote 2D-22 depende de las claves compuestas `(company_id, code)` y de los helpers multiempresa. No debe ejecutarse hasta que la migración base corregida esté aplicada y probada; su `COMMIT` actual requiere aprobación específica después del ensayo.

La aplicación usa SheetJS desde CDN para leer archivos XLSX/XLS. Requiere conexión a internet para cargar esa biblioteca y Supabase.

## Reglas de negocio
- No descontar ni reservar stock al guardar pedidos.
- No borrar ni poner a cero productos ausentes del Excel.
- CENTRAL y CDE son saldos independientes.
- Los precios 1, 2 y 3 se guardan por producto y empresa.
- Un precio cero es válido.
- Los datos opcionales vacíos en un artículo existente no deben borrar valores anteriores.
- Los pedidos históricos no se recalculan al importar un catálogo nuevo.

## Pendiente antes de producción
- Ejecutar el lote SQL 2D-22 en AB-SYSTEM-DEMO.
- Importar el libro vigente y conciliar conteos y saldos CENTRAL/CDE.
- Desplegar la Edge Function `admin-users` y probar altas/suspensiones de empresas, invitaciones, cambios de rol/estado y retiro de membresías con cuentas autorizadas.
- Probar inicio de sesión y aislamiento con cuentas reales de superadministrador, administrador, vendedor y usuario sin membresía.
- Probar cambio de empresa, creación/lectura de pedidos, archivo, stock e importación desde Android y escritorio.
- Verificar despliegue en un destino de prueba y confirmar que no apunta a Ko’ẽju histórico.
- La administración global de empresas y membresías está implementada en la rama de desarrollo mediante la Edge Function protegida `admin-users`; todavía requiere despliegue y pruebas reales en Supabase DEMO.
- Las empresas se desactivan/reactivan para conservar pedidos e inventario; quitar un vendedor elimina su membresía de esa empresa, no su cuenta de acceso global.
- La validación automatizada de administración se ejecuta mediante GitHub Actions (Node.js y Deno).

No se ha creado PR, no se fusionó la rama y no se desplegó ni publicó esta versión.

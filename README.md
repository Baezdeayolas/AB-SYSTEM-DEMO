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

La empresa inicial de demostración será **AB SYSTEM DEMO** (código objetivo provisional: `ABDEMO`). La fila empresarial que actualmente se identifica como `KOEJU` en la base DEMO se transformará conservando los registros comerciales que correspondan, sin modificar Ko’ẽju producción.

La migración consolidada 2D-21 sigue en revisión: su backfill histórico todavía busca `code='KOEJU'`. Se corrigió su cierre de seguridad a `ROLLBACK` para impedir confirmaciones accidentales. **No ejecutar 2D-21 ni 2D-22** hasta completar la adaptación de empresa, el respaldo restaurable, la revisión de membresías y la anonimización de datos personales destinados a demostraciones.

El lote 2D-22 depende del esquema multiempresa creado por 2D-21; no es una migración inicial independiente. Cuando el esquema y los permisos estén validados, se revisará y probará en una transacción separada.

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

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
Antes de abrir la aplicación, ejecutar **solo en AB-SYSTEM-DEMO**:

`sql/ETAPA-2D-22-INVENTARIO-CENTRAL-CDE-IMPORTACION-EXCEL.sql`

Este lote crea las tablas de saldos por depósito, el historial de movimientos y las RPC de importación. Conserva las tablas legacy de inventario sin reasignar sus cantidades a CENTRAL o CDE. Después de ejecutar el lote, un administrador debe importar el Excel vigente para cargar los saldos reales de ambos depósitos.

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
- Probar inicio de sesión y aislamiento con cuentas reales de superadministrador, administrador, vendedor y usuario sin membresía.
- Probar cambio de empresa, creación/lectura de pedidos, archivo, stock e importación desde Android y escritorio.
- Verificar despliegue en un destino de prueba y confirmar que no apunta a Ko’ẽju histórico.
- El escáner de códigos de barras y la administración completa de altas de usuarios/empresas no forman parte de esta versión candidata.

No se ha creado PR, no se fusionó la rama y no se desplegó ni publicó esta versión.

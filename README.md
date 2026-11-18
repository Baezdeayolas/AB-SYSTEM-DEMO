# AB SYSTEM DEMO

Entorno independiente para construir y validar la plataforma común AB SYSTEM antes de cualquier cambio en producción.

## Componentes actuales en la rama de trabajo

- `index.html`: estructura DEMO con acceso, cabecera comercial, paneles de búsqueda, pedido, archivo, resumen, stock y administración.
- `cloud-sync-demo.js`: autenticación Supabase DEMO, lectura de catálogo/clientes, asignaciones de vendedor y guardado/consulta básica de pedidos.
- `data-demo.js`: catálogo y clientes ficticios de respaldo.
- `style.css`: estilos de referencia y adaptaciones.
- `service-worker.js`: caché independiente de DEMO.

## Estado de la versión candidata

La rama `work/adaptacion-multiempresa-v1` contiene la base multiempresa y una primera integración funcional de:
- Acceso Supabase DEMO y resolución de empresas/membresías.
- Catálogo, clientes, asignaciones y pedidos filtrados por empresa.
- Pedidos guardados con `company_id`, `owner_id` y `created_by`; guardar un pedido no descuenta ni reserva stock.
- Inventario separado por depósitos CENTRAL y CDE mediante tablas nuevas.
- Previsualización e importación del Excel habitual, con validación de códigos duplicados, descripción, cantidades y listas de precios.
- Conservación de productos ausentes del archivo.
- Comprobante imprimible desde el navegador para guardar como PDF.

**Antes de probar esta versión**, ejecutar en Supabase AB-SYSTEM-DEMO el script `sql/ETAPA-2D-22-INVENTARIO-CENTRAL-CDE-IMPORTACION-EXCEL.sql`. No ejecutarlo en Ko’ẽju histórico. La migración conserva intactas las tablas legacy de inventario y crea tablas separadas para los depósitos, inicializadas en cero; la importación del Excel debe cargar los saldos reales de CENTRAL y CDE.

No se ha desplegado ni publicado esta rama. La versión sigue requiriendo pruebas funcionales con cuentas de cada rol y una importación de prueba controlada antes de considerarse apta para producción.

## Arquitectura multiempresa

La arquitectura objetivo está documentada en `ARQUITECTURA-MULTIEMPRESA.md`. La matriz visual y su estado se describen en `MATRIZ-AB-SYSTEM.md`. El selector de empresa y los roles globales todavía no están implementados.

## Seguridad y límites

- No importar clientes, vendedores, precios, pedidos ni credenciales reales de Ko'eju.
- No copiar scripts de producción ni secretos al frontend.
- No modificar el repositorio ni Supabase de producción.
- No ejecutar migraciones en Supabase DEMO hasta contrastar el esquema existente.
- Mantener RLS y validar los permisos en backend; los filtros del navegador no son una barrera de seguridad.
- No fusionar ni publicar esta rama hasta completar las pruebas de autenticación, permisos, aislamiento entre empresas y comparación visual.

## Datos DEMO

Los catálogos de Supabase DEMO (`catalog_items` y `catalog_clients`) reemplazan los datos ficticios de respaldo al iniciar sesión, siempre que las consultas y sus columnas coincidan con el esquema configurado. Este entorno debe utilizar exclusivamente datos sintéticos.


## Adaptación multiempresa en curso

La rama `work/adaptacion-multiempresa-v1` incorpora el primer tramo de adaptación:
- Contexto de empresa y selector funcional cuando el usuario tiene varias empresas.
- Resolución de empresas desde `company_memberships` y del rol global mediante RPC.
- Lecturas de catálogo, clientes, vendedores y pedidos filtradas por `company_id`.
- Cambio de empresa conectado a la recarga del contexto; si falla, se intenta recuperar la empresa anterior.
- Bloqueo de doble envío de pedidos y cálculo del total mostrado en el archivo.
- Pedidos nuevos guardados con `company_id`; crear pedidos no modifica inventario ni reserva stock.
- Lote 5 preparado: saldos por empresa, historial de movimientos y RPC de importación que conserva artículos ausentes del archivo.
- Contrato frontend preparado para el esquema empresarial; la migración SQL queda pendiente de revisión del preflight y de una restauración de respaldo.

**No aplicar todavía la migración ni publicar esta rama.** Antes se debe revisar el inventario de claves foráneas/índices y probar la migración en una copia aislada. Esta etapa tampoco completa todavía la paridad funcional con Ko'eju (PDF, edición/reutilización de pedidos, importación Excel y administración de usuarios).


### Bloqueos antes de probar o publicar esta adaptación

- El frontend ya consulta `company_id` en tablas comerciales y `created_by` al guardar pedidos; esas columnas todavía no están confirmadas en el esquema activo.
- El guardado identifica al vendedor mediante la asignación de la empresa: `owner_id` es el usuario vendedor y `created_by` es quien creó el pedido.
- La migración SQL se consolidó en `sql/ETAPA-2D-21-MIGRACION-MULTIEMPRESA-DEMO-CONSOLIDADA-DRAFT.sql`; termina en ROLLBACK y no se ha ejecutado.
- El respaldo AB-SYSTEM-DEMO ya tuvo una restauración local de estructura y datos públicos comprobada. Falta ensayar el SQL consolidado contra el proyecto DEMO y probar RLS con JWT reales.
- La adaptación funcional completa de Ko'eju (PDF, edición/reutilización de pedidos, importación Excel y administración) se realizará después de validar esta base multiempresa.


### Corrección de la iteración actual

Se corrigió un defecto funcional: el selector de empresa se mostraba, pero no tenía conectado el evento que cambiaba el contexto. Ahora el cambio activa la recarga de catálogo, clientes, vendedores y pedidos; si la carga falla, se restaura el contexto anterior. También se evita el doble envío de pedidos y se completa el total del archivo.

**Validación pendiente:** no se ejecutaron pruebas de navegador ni pruebas con JWT/RLS. La aplicación sigue sin ser compatible con el esquema Supabase activo hasta que se apruebe y ejecute una migración verificada que añada y proteja las relaciones empresariales. No publicar ni probar contra datos reales todavía.

**Identidad de empresas pendiente de confirmar:** la empresa existente en DEMO figura con código `KOEJU`. La empresa `DEMO` para pruebas de prospectos debe ser una empresa separada; no cambiar el código ni reasignar los registros existentes por suposición.


## Cierre de funcionalidades pendientes
- El botón de comprobante genera una vista imprimible; desde el navegador se puede elegir Guardar como PDF.
- El importador usa SheetJS desde CDN y reconoce los encabezados reales del libro (Cód.Artículo, CENTRAL, CDE y listas 1, 2, 3) o sus alias documentados.
- El escáner de códigos de barras continúa pendiente y no se presenta como función disponible.
- La administración de empresas y altas de usuarios no se considera terminada en esta versión candidata.

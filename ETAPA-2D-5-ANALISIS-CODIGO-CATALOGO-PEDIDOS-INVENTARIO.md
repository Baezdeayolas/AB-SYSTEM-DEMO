# ETAPA 2D-5 — ANÁLISIS DEL CÓDIGO: CATÁLOGO, PEDIDOS E INVENTARIO

**Entorno:** AB SYSTEM DEMO exclusivamente  
**Rama:** `work/ab-system-multempresa-ui`  
**Estado:** auditoría estática completada para los archivos frontend inspeccionados; migración todavía bloqueada para ejecución.

## 1. Archivos revisados

- `index.html`
- `cloud-sync-demo.js`
- `data-demo.js`
- `ETAPA-2D-1-INVENTARIO-CONSUMIDORES-DATOS.md`
- Resultados compartidos por el usuario de los bloques A-D de `ETAPA-2D-4-VERIFICACION-PERTENENCIA-Y-STOCK-SOLO-LECTURA.sql`.

Esta revisión se limita al código fuente disponible en la rama indicada. No es una búsqueda exhaustiva de procesos externos, Edge Functions, importadores privados ni tareas programadas.

## 2. Hallazgos confirmados sobre `sc` y `sd`

| Campo | Evidencia | Conclusión permitida |
|---|---|---|
| `sc` | `cloud-sync-demo.js` lo presenta en la lista de productos y en la pantalla Stock mediante `Number(x.sc || 0)`. `data-demo.js` contiene el campo en los cinco artículos sintéticos. | El frontend usa `sc` como cantidad de stock que muestra. |
| `sd` | Aparece en los cinco artículos sintéticos de `data-demo.js`, pero no se encontró lectura ni escritura de `sd` en `cloud-sync-demo.js` ni en `index.html`. | Su significado funcional no está demostrado. No asignarle semántica ni modificarlo todavía. |

El resultado de Supabase compartido por el usuario confirma que las cinco filas de `catalog_items` contienen ambas claves y que los valores de ambas son numéricos. Eso no demuestra por sí solo qué representa `sd`, ni identifica qué proceso actualiza `sc` o `sd`.

## 3. Fuente de stock actualmente observada

1. `loadData()` consulta `catalog_items` y asigna `payload` directamente a `items`.
2. `render()` muestra `x.sc` en cada tarjeta de producto.
3. La pantalla `panel-stock` también muestra `x.sc` desde `items`.
4. No se encontró consulta directa a `inventory_current` en el frontend inspeccionado.
5. En Supabase DEMO, el usuario confirmó que `inventory_current` tiene una fila cuyo arreglo `items` contiene cero elementos.

**Conclusión:** el stock que ve hoy el frontend procede del campo `sc` dentro de `catalog_items.payload`, no del arreglo de `inventory_current`. No se debe poblar ni reemplazar inventario desde `inventory_current` sin localizar primero el importador y definir una fuente única.

## 4. Hallazgos sobre pedidos que bloquean una migración automática

- La aplicación permite seleccionar una etiqueta de vendedor.
- El guardado actual establece `owner_id: user.id` incluso cuando la etiqueta seleccionada podría corresponder a otro vendedor.
- El guardado no envía `company_id` ni `created_by`.
- La consulta de pedidos no filtra explícitamente por empresa; depende de RLS.
- Para `admin`, el frontend genera etiquetas estáticas `VENDEDOR DEMO 1/2/3` en lugar de consultar memberships activas.

Por tanto, el frontend actual no implementa la identidad acordada. No debe habilitarse multiempresa hasta que el backend valide la empresa, la membership del vendedor y la identidad del actor.

## 5. Diseño de migración recomendado

### 5.1 Catálogo

- Añadir `company_id` de forma aditiva y nullable en una primera fase.
- Verificar que todas las filas legacy pertenecen a Ko’ẽju DEMO antes de asignar el UUID de esa empresa.
- Comprobar duplicados por `(company_id, code)` antes de crear unicidad compuesta.
- Mantener los campos JSONB existentes, incluyendo `sc` y `sd`, sin renombrarlos ni eliminarlos.
- Mantener `sc` como valor de compatibilidad visual durante la transición; mover el origen de stock a una estructura normalizada solo después de documentar el proceso de importación.
- No migrar `sd` hasta que su significado y consumidor estén identificados.

### 5.2 Pedidos

- Añadir `company_id` y `created_by` en una fase aditiva.
- Backfill de `company_id` del único pedido histórico a Ko’ẽju solo con preflight que confirme que todos los propietarios tienen membership activa en esa empresa.
- Mantener `owner_id` sin cambios.
- Dejar `created_by` histórico en NULL si no existe evidencia fiable del actor original.
- Los pedidos nuevos deberán ser creados mediante una operación backend que establezca y valide `company_id`, `owner_id` y `created_by`.

### 5.3 Inventario

- No convertir todavía `inventory_current` en la fuente canónica.
- Antes de crear tablas de stock y movimientos, localizar importadores y procesos que escriben `catalog_items.payload`.
- La futura fuente canónica debe ser por empresa, con movimientos auditables append-only y actualizaciones transaccionales.
- Definir una estrategia de compatibilidad temporal para `sc` para evitar que frontend e importador escriban fuentes divergentes.

## 6. Bloqueos que impiden ejecutar ahora el primer lote mutante

1. No se ha confirmado respaldo y restauración de Supabase DEMO.
2. No está identificado el importador o proceso externo que mantiene los valores de stock.
3. No se ha determinado el significado de `sd`.
4. No hay inventario completo de procesos fuera del frontend inspeccionado.
5. No se han probado RLS ni las funciones de autorización con JWT de admin de empresa, vendedor y superadmin.
6. Las políticas SELECT legacy con `USING (true)` y los privilegios amplios de tablas legacy requieren una sustitución coordinada; añadir políticas nuevas por sí solo no crea aislamiento porque las políticas permisivas se combinan mediante OR.

## 7. Próxima secuencia segura

1. Confirmar y documentar backup/restauración DEMO.
2. Localizar el proceso de importación/actualización de productos y stock, incluyendo procesos fuera del frontend.
3. Preparar lote 1 de SQL aditivo para `company_id` en catálogos y pedidos, con preflight, validaciones y rollback; todavía sin `NOT NULL` ni eliminación de restricciones legacy.
4. Ejecutar el lote solo después de que el usuario revise y apruebe el script completo.
5. Verificar conteos, asignación empresarial y claves únicas.
6. Preparar el lote de RLS y privilegios como operación separada, sustituyendo las políticas permisivas antiguas en forma coordinada.
7. Probar acceso con JWT antes de cambiar el frontend.
8. Adaptar el frontend para membresías, selector de empresa, vendedores reales y propiedad correcta de pedidos.

## 8. Registro de cambios

- Auditoría estática de `index.html`, `cloud-sync-demo.js` y `data-demo.js` completada.
- No se modificó código de aplicación.
- No se ejecutó SQL ni se modificó Supabase.
- No se modificó producción, no se abrió PR, no se hizo merge y no se publicó.

**Resultado:** la fuente visual actual del stock está identificada (`catalog_items.payload.sc`), pero la migración del inventario y el aislamiento multiempresa siguen bloqueados hasta completar las verificaciones de importación, respaldo y RLS.

## 9. Estructura Excel confirmada por el usuario

El usuario compartió registros reales de ejemplo del archivo `ListaPrecios_6571.xlsx`. Los encabezados observados son:

- Identificación: `cod_articulo`, `cod_fabrica`, `cod_barra`.
- Clasificación: `agrup_1`, `agrup_2`, `agrup_3`.
- Descripción y empaque: `descripcion`, `envases`, `master`, `inner`.
- Existencias: `stock_central`, `stock_cde`.
- Precios: `precio_1`, `precio_2`, `precio_3`.

El usuario confirmó expresamente que Central y CDE deben manejarse como depósitos separados. Por tanto:

1. La futura importación debe conservar `stock_central` y `stock_cde` como cantidades independientes; no sumarlas para reemplazar los saldos individuales.
2. Cada saldo y sus movimientos deberán quedar asociados a empresa, producto y depósito.
3. Los tres precios deben conservarse como listas diferenciadas.
4. `cod_articulo` es el identificador comercial candidato para el producto dentro de una empresa; antes de imponer restricciones se deben revisar duplicados y reglas reales del importador.
5. No asumir que `stock_central` equivale a `sc` ni que `stock_cde` equivale a `sd`. El código actual solo demuestra uso visual de `sc`; `sd` sigue sin consumidor identificado.
6. El JSON compartido contiene solo cinco registros de muestra, por lo que no representa un inventario completo ni permite calcular conteos o duplicados del archivo entero.

El código Python compartido por el usuario es únicamente un lector/inspector de Excel que serializa hojas y filas a JSON. No es el importador de la aplicación ni actualiza Supabase.

### Próximo paso técnico

Conseguir el código real que la aplicación utiliza para recibir/procesar el Excel y actualizar el catálogo/stock. Revisar también el flujo de importación completo antes de definir la migración de `catalog_items.payload` y el modelo normalizado de existencias por depósito. No ejecutar SQL mutante ni modificar el frontend hasta cerrar esa revisión.

### Confirmación adicional del usuario: un único Excel para stock y precios

El usuario confirmó que `ListaPrecios_6571.xlsx` es el mismo archivo que utiliza habitualmente desde Ko’ẽju para actualizar stock y precios. Por tanto, el flujo real debe tratar ese archivo como fuente tanto de catálogo/campos descriptivos como de existencias y listas de precios, aunque el frontend actual tenga dos rutas de importación separadas.

El importador `parseSharedInventoryFile()` inspeccionado en `cloud-sync.js` de producción espera encabezados normalizados `CODARTICULO`, `CENTRAL`, `CDE` y tres columnas de precio (`1`/`M1`/`PRECIO1`, etc.). Convierte las existencias a propiedades `central` y `cde`, y los precios a `p1`, `p2`, `p3`, luego reemplaza el contenido de la fila única `inventory_current` mediante upsert. Esto confirma que el stock actual se persiste en `inventory_current.items` por ese flujo, además del campo `sc` mostrado desde `catalog_items.payload` en la ruta de catálogo. La coexistencia de ambas representaciones requiere resolver fuente canónica y sincronización antes de migrar.

El ejemplo real del Excel usa encabezados `cod_articulo`, `stock_central`, `stock_cde`, `precio_1`, `precio_2`, `precio_3`. Hay que comprobar en código la normalización exacta de encabezados y asegurar compatibilidad; no inferirla solo por semejanza textual.

**Riesgo/bloqueo actualizado:** existe una doble representación del inventario: el flujo de catálogo publica campos `sc`/`sd` dentro de `catalog_items.payload`, mientras que la importación de stock y precios actualiza `inventory_current.items` con `central`/`cde`/`p1`/`p2`/`p3`. Antes de multiempresa se debe decidir y probar una única fuente canónica por empresa y depósito, y definir una compatibilidad transitoria para pantallas y pedidos. No sumar depósitos ni borrar campos legacy durante la transición.

**Siguiente inspección:** revisar `normalizeStockHeader()`, `parseStockNumber()`, `loadSharedInventory()` y todos los consumidores de `inventory_current.items`/`sc`/`sd`; verificar si la importación de inventario también actualiza catálogo/precios o si son flujos separados. No modificar producción ni ejecutar SQL.

## 10. Revisión adicional de consumidores y normalización (solo lectura)

Se inspeccionaron `app.js` y `cloud-sync.js` del repositorio de producción únicamente como referencia funcional. No se modificó ese repositorio.

### 10.1 Normalización de encabezados

`normalizeStockHeader()` aplica normalización Unicode NFD, elimina diacríticos, convierte a mayúsculas y elimina todo carácter que no sea A-Z o 0-9. Por ello, encabezados como `cod_articulo`, `stock_central` y `precio_1` se convierten respectivamente en `CODARTICULO`, `STOCKCENTRAL` y `PRECIO1`.

**Hallazgo:** el importador actual busca `CODARTICULO`, `CENTRAL`, `CDE` y nombres de precios, pero el Excel real de muestra tiene `STOCKCENTRAL` y `STOCKCDE`. No se encontró alias para esos encabezados en el parser de inventario ni en el parser de catálogo. El Excel real podría no ser aceptado tal cual por la versión actual, aunque el ejemplo del usuario y los nombres de columna parecen equivalentes semánticamente. Debe probarse con el archivo real completo o un Excel anonimizado antes de cambiar aliases.

### 10.2 Parseo numérico

`parseStockNumber()` acepta valores numéricos y, para texto, elimina puntos y sustituye coma por punto decimal; valores no numéricos terminan como cero. Esto debe probarse con los formatos reales de cantidad y precio del Excel, especialmente si usa puntos decimales, separadores de miles o celdas vacías. No asumir que todo valor inválido debe convertirse a cero sin confirmar la regla comercial.

### 10.3 Carga y consumidores de inventario

- `loadSharedInventory()` consulta `inventory_current` para `id=1` y aplica cada fila a los productos en memoria mediante coincidencia `row.code` con el código del catálogo.
- La carga sobrescribe en memoria `item.sc`, `item.sd`, `item.p1`, `item.p2` e `item.p3` con los campos `central`, `cde`, `p1`, `p2` y `p3` del inventario compartido.
- El panel de stock (`refreshStockSnapshotFromCatalog()` y `renderStockPanel()`) consume `sc` como CENTRAL y `sd` como CDE; muestra ambos por separado y ofrece filtros separados.
- Las tarjetas de producto también muestran CENTRAL y CDE por separado.
- Sin embargo, al agregar un producto a un pedido, `app.js` calcula `disponible = sc + sd` y compara la cantidad solicitada contra el total combinado. La confirmación al usuario también comunica que el total está disponible entre ambos depósitos.
- La selección de precio usa `p1`, `p2` o `p3` según la lista seleccionada.

### 10.4 Consecuencia para el diseño multiempresa

El usuario confirmó que los saldos Central y CDE deben mantenerse separados. La interfaz ya los muestra separados, pero la validación de cantidad del pedido actualmente los suma. No debe asumirse que la separación de inventario implica necesariamente reservar desde un depósito elegido: se requiere definir la regla de venta/compromiso de stock (elegir depósito, permitir surtido desde cualquiera, o mantener validación consolidada sin perder saldos separados).

### 10.5 Bloqueos técnicos confirmados

1. Los nombres de encabezados del Excel real (`STOCKCENTRAL`, `STOCKCDE`) no coinciden literalmente con los alias actuales (`CENTRAL`, `CDE`) después de normalizar; hace falta compatibilidad explícita y prueba.
2. El inventario se persiste en `inventory_current` como un único registro compartido `id=1`, no segmentado por empresa.
3. La UI muestra saldos separados, pero la comprobación de cantidad para pedidos suma ambos depósitos.
4. El catálogo maestro también puede almacenar `sc`/`sd` y precios, pero la carga de inventario compartido los sobrescribe en memoria; hay dos representaciones que deben unificarse.
5. `cod_fabrica`, `envases`, `master` e `inner` no se conservan en el objeto normalizado de catálogo actual.

## 11. Regla funcional confirmada: disponibilidad combinada

El usuario eligió expresamente la **opción B**:

- Mantener los saldos de CENTRAL y CDE separados y visibles como cantidades independientes.
- Para validar la disponibilidad de un pedido, permitir utilizar la suma de ambos saldos.
- La validación se considera satisfecha cuando la cantidad solicitada no supera la disponibilidad combinada de los dos depósitos.
- La suma se utiliza únicamente para comprobar disponibilidad; no reemplaza ni fusiona los saldos individuales almacenados o mostrados.
- La importación y los movimientos deben seguir actualizando y auditando cada depósito por separado.

**Distinción pendiente antes de implementar:** esta decisión define la validación de disponibilidad, pero todavía no especifica cómo se descuenta/reserva físicamente la cantidad vendida entre CENTRAL y CDE. Esa regla de asignación deberá definirse en una etapa posterior para que los movimientos y saldos no queden ambiguos. No inventar una distribución automática ni modificar inventario hasta acordarla.

## 12. Próximo paso

Continuar la revisión del contrato de importación del Excel y diseñar el modelo de inventario multiempresa por depósito, incorporando la regla de disponibilidad combinada confirmada. No ejecutar SQL mutante, no modificar el frontend y no tocar producción en esta etapa.

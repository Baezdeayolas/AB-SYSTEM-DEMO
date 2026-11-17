# ETAPA 2D-6 — CONTRATO DE IMPORTACIÓN EXCEL (DISEÑO)

**Entorno:** AB SYSTEM DEMO exclusivamente  
**Rama:** `work/ab-system-multempresa-ui`  
**Estado:** estructura y tipos del libro real inspeccionados; pendientes algunas reglas funcionales de celdas y campos de empaque.  
**No autoriza:** ejecución SQL, cambios de frontend, importación real, despliegue ni modificación de producción.

## 1. Objetivo

Definir un único flujo controlado para recibir el archivo habitual `ListaPrecios_6571.xlsx` y actualizar, dentro de la empresa activa:

- Datos de identificación y descripción de productos.
- Clasificaciones y datos de empaque disponibles en el libro.
- Stock de CENTRAL y CDE como saldos separados.
- Listas de precios 1, 2 y 3.

La importación no debe modificar, borrar ni recalcular pedidos ya registrados.

## 2. Contrato de columnas conocidas

Los siguientes encabezados proceden de los ejemplos reales compartidos por el usuario. Deben verificarse contra todas las hojas y encabezados del archivo completo antes de activar el importador.

| Encabezado Excel | Campo lógico | Tratamiento |
|---|---|---|
| `cod_articulo` | `product_code` | Identificador candidato obligatorio por fila |
| `cod_fabrica` | `factory_code` | Texto; conservar ceros iniciales |
| `cod_barra` | `barcode` | Texto; conservar ceros iniciales |
| `agrup_1` | `group_1` | Texto |
| `agrup_2` | `group_2` | Texto |
| `agrup_3` | `group_3` | Texto |
| `descripcion` | `description` | Texto |
| `envases` | `packages` | Conservar valor original y validar tipo |
| `master` | `master_pack` | Conservar valor original y validar tipo |
| `inner` | `inner_pack` | Conservar valor original y validar tipo |
| `stock_central` | `stock.central` | Número no negativo; saldo independiente |
| `stock_cde` | `stock.cde` | Número no negativo; saldo independiente |
| `precio_1` | `prices.tier_1` | Número; lista 1 |
| `precio_2` | `prices.tier_2` | Número; lista 2 |
| `precio_3` | `prices.tier_3` | Número; lista 3 |

Los códigos deben tratarse como texto, no como números, para evitar pérdida de ceros iniciales o notación científica.

## 2.1 Inspección del archivo real recibido (17-11-2026)

Se inspeccionó el archivo adjunto `ListaPrecios_6571.xlsx` en modo de solo lectura. No se modificó el libro.

- Una sola hoja: `Sheet0`.
- 9.541 filas físicas y 15 columnas.
- Filas 1 a 4 contienen título, empresa, filtros y rótulos auxiliares.
- Encabezados efectivos en la fila 5.
- Registros de artículos desde la fila 6: **9.536 artículos**.
- Encabezados exactos: `Cód.Artículo`, `Cód.Fábrica`, `Cód.Barra`, `Agrup.1`, `Agrup.2`, `Agrup.3`, `Descripción`, `Envases`, `Master`, `Inner`, `CENTRAL`, `CDE`, `1`, `2`, `3`.
- Los 9.536 códigos de artículo están almacenados como texto, no como números; no se encontraron códigos vacíos ni duplicados.
- No se encontraron códigos de barra duplicados. Hay 22 filas sin código de barra y 5.903 sin código de fábrica.
- Los campos numéricos están almacenados como números nativos de Excel. En las 9.536 filas no hay celdas vacías en `Envases`, `Master`, `Inner`, `CENTRAL`, `CDE` ni en las tres listas de precios; los ceros están expresados explícitamente como valor numérico 0.
- CENTRAL: 6.990 artículos con saldo mayor que cero; CDE: 6.222.
- Listas 1, 2 y 3: 9.237 artículos con precio mayor que cero en cada lista; 299 tienen cero en las tres listas. El usuario confirmó que estos precios cero son válidos y deben conservarse.
- `Envases`, `Master` e `Inner` contienen valores numéricos, incluidos ceros; su significado comercial todavía debe confirmarse.

**Consecuencia para el importador:** debe admitir los encabezados reales tal como aparecen (incluidos `Cód.Artículo`, `Cód.Fábrica`, `Cód.Barra`, `Agrup.1` y las listas `1`, `2`, `3`), además de los alias previamente documentados. El libro real no usa `stock_central`, `stock_cde` ni `precio_1` como encabezados. El parser debe mapear CENTRAL y CDE como saldos separados, y 1/2/3 como listas de precios.

## 3. Normalización de encabezados y compatibilidad

La normalización debe:
1. Quitar espacios externos.
2. Normalizar Unicode y diacríticos.
3. Convertir a mayúsculas.
4. Eliminar separadores no alfanuméricos.

Ejemplos esperados:

| Encabezado | Normalizado |
|---|---|
| `cod_articulo` | `CODARTICULO` |
| `stock_central` | `STOCKCENTRAL` |
| `stock_cde` | `STOCKCDE` |
| `precio_1` | `PRECIO1` |

El parser de referencia inspeccionado espera `CENTRAL` y `CDE`, por lo que no debe asumirse que acepta `STOCKCENTRAL` y `STOCKCDE`. El nuevo contrato reconocerá ambos pares como alias del mismo campo lógico, pero la implementación solo se aprobará después de probar el archivo real o una copia anonimizada.

Si dos columnas del mismo libro se resuelven al mismo campo lógico (por ejemplo, `CENTRAL` y `STOCK_CENTRAL` simultáneamente), la importación debe detenerse por ambigüedad, no elegir una arbitrariamente.

## 4. Validaciones antes de publicar

El proceso debe trabajar primero en modo de previsualización y rechazar la publicación si encuentra errores críticos.

### 4.1 Errores que bloquean

- Falta la columna de código de artículo.
- Código vacío en una fila que contiene datos comerciales.
- Código duplicado dentro del conjunto importado, salvo que el formato real documente expresamente otra regla.
- Encabezados obligatorios ausentes o ambiguos.
- Stock negativo, infinito o no interpretable.
- Precio no interpretable cuando la columna está presente y contiene un valor.
- Formato de libro u hoja no compatible.
- Empresa activa no resuelta o usuario sin permiso de importar para esa empresa.
- Error al guardar cualquier parte del conjunto.

### 4.2 Valores vacíos y formatos numéricos

- No convertir automáticamente un valor inválido a cero.
- Diferenciar celda vacía, cero explícito y texto inválido.
- Probar formatos habituales del libro: números nativos de Excel, separadores de miles, coma decimal y celdas vacías.
- No eliminar puntos de manera indiscriminada sin confirmar el formato real.
- Mostrar errores por fila y columna para corregir el Excel antes de publicar.

### 4.3 Duplicados y productos nuevos

- Detectar códigos repetidos en el archivo y mostrar las filas implicadas.
- Mostrar cuántos códigos coinciden con productos existentes y cuántos serían nuevos.
- Los artículos nuevos presentes en un archivo válido se incorporarán al catálogo de la empresa mediante upsert, una vez superada la validación y confirmada la importación.
- Un artículo nuevo debe incluir como mínimo código de artículo y descripción. Los demás campos pueden estar vacíos o en cero, según corresponda; no rechazarlo por ausencia de datos opcionales.
- La importación nunca debe crear el mismo producto dos veces dentro de una empresa.

## 5. Flujo de importación propuesto

1. **Seleccionar empresa:** el contexto empresarial debe estar resuelto y validado en backend.
2. **Cargar archivo:** recibir el libro sin escribir todavía en tablas definitivas.
3. **Leer y mapear:** identificar hojas, encabezados, filas y tipos.
4. **Validar:** comprobar estructura, duplicados, códigos, números y permisos.
5. **Previsualizar:** mostrar nombre del archivo, fecha, hoja utilizada, cantidad de filas, productos nuevos/existentes, errores, saldos por depósito y precios.
6. **Confirmar:** solo un usuario con permiso administrativo de esa empresa puede publicar.
7. **Publicar atómicamente:** aplicar el conjunto validado en una transacción o mecanismo equivalente; si falla, no dejar catálogo, precios y stock en estados parciales.
8. **Registrar auditoría:** empresa, usuario que importó, fecha/hora, identificador del lote, nombre del archivo, conteos y resultado.
9. **Verificar:** devolver conteos insertados/actualizados/rechazados y permitir revisar el resumen del lote.

No se debe guardar el archivo directamente sobre datos activos mientras todavía se está leyendo o validando.

## 6. Reglas de actualización

- CENTRAL y CDE son dos saldos independientes.
- Los precios 1, 2 y 3 son independientes.
- La importación debe actualizar catálogo, precios y stock desde el mismo libro, manteniendo la asociación con la empresa.
- Los pedidos existentes conservan sus precios, cantidades, totales y contenido histórico; una nueva importación no los recalcula.
- Guardar o editar un pedido no descuenta ni reserva stock.
- La validación del pedido puede mostrar disponibilidad combinada (CENTRAL + CDE) como referencia, pero esa suma no se persiste como saldo ni genera movimientos.
- La actualización de existencias se produce por una importación confirmada del Excel, no por el registro de pedidos.
- No se implementa en esta etapa facturación ni salida física de mercadería.

## 7. Modelo de datos objetivo (conceptual, no SQL)

El diseño debe separar:

- **Producto por empresa:** código, descripción, códigos alternativos, agrupaciones y datos de empaque.
- **Precios por producto/empresa:** tres listas de precios, actualizadas por el lote Excel.
- **Existencia por depósito:** una fila lógica por empresa, producto y depósito (CENTRAL o CDE), con cantidad disponible.
- **Lote de importación:** empresa, actor, fecha, archivo, estado, resumen y errores.
- **Detalle de importación:** fila/registro procesado, código de producto, datos normalizados y resultado.

La estructura definitiva, restricciones, índices, RLS y estrategia de compatibilidad con `catalog_items.payload` e `inventory_current` se definirán después de verificar el libro real y el respaldo/restauración DEMO. Este documento no prescribe todavía migraciones SQL.

## 8. Decisiones confirmadas y pendientes

### 8.1 Alcance del archivo — confirmado por el usuario

El usuario indicó que el archivo puede incluir artículos nuevos, pero nunca contiene menos artículos que la lista habitual. Para el diseño esto se interpreta como un archivo que representa el catálogo completo vigente de la empresa, con posibilidad de altas.

- Los artículos nuevos que aparezcan se incorporan al catálogo de esa empresa al confirmar una importación válida.
- Los artículos ya existentes que aparezcan se actualizan con los datos del archivo.
- La ausencia de un artículo no debe causar borrado automático, baja ni puesta a cero. Aunque el archivo sea completo según la regla comunicada, se conserva esta protección para evitar pérdidas por errores de exportación o cambios accidentales.
- Si en una futura operación el usuario necesita retirar artículos, se diseñará una acción explícita de baja/inactivación, separada de la importación.
- La importación no altera pedidos anteriores.

### 8.2 Pendientes de verificación

1. **Celdas vacías:** el archivo inspeccionado no tiene celdas vacías en los campos numéricos; falta definir cómo tratar vacíos en futuras versiones del libro.
2. **Campos de empaque:** confirmar significado comercial de `Envases`, `Master` e `Inner`.
3. **Campos obligatorios para artículo nuevo:** confirmar si además de código y descripción se exige algún otro campo.
4. **Ceros de precio:** el libro contiene 299 artículos con precio 0 en las tres listas; confirmar si representan artículos sin precio o una condición comercial válida.

## 9. Pruebas de aceptación necesarias

- Libro válido con códigos alfanuméricos y códigos con ceros iniciales.
- Artículo nuevo con código y descripción, aunque otros campos opcionales estén vacíos o en cero: se crea una sola vez en la empresa correcta.
- Precio cero en las tres listas: se conserva como valor válido.
- `Envases`, `Master` e `Inner`: se preservan sin tratarlos como unidades de empaque ni usarlos en cálculos.
- Artículo existente: se actualizan catálogo, precios y saldos sin duplicarlo.
- Artículo ausente del archivo: no se borra, no se inactiva y no se pone a cero automáticamente.
- Stock CENTRAL y CDE distintos; comprobar que no se mezclan.
- Tres precios distintos; comprobar que se conservan en la lista correcta.
- Código duplicado: el lote se bloquea y señala filas.
- Stock negativo o valor no numérico: el lote se bloquea y señala celda.
- Encabezados alias equivalentes: se aceptan si no hay ambigüedad.
- Dos alias para el mismo campo: lote bloqueado.
- Error de publicación: rollback total, sin actualización parcial.
- Usuario vendedor: no puede publicar.
- Admin empresa: solo puede importar en su empresa.
- Superadmin: puede seleccionar empresa autorizada y operar en el contexto elegido.
- Pedidos anteriores y posteriores a la importación: permanecen sin cambios por el proceso de importación.
- Guardar pedido: no cambia ningún saldo ni crea movimiento de salida.

## 10. Próximo paso seguro

La estructura, encabezados, tipos numéricos y unicidad de códigos del archivo real ya fueron inspeccionados. El siguiente paso es cerrar el significado de los campos de empaque, los precios en cero y los campos obligatorios de artículos nuevos; después se preparará el diseño SQL separado para revisión.

**Estado de ejecución:** no se modificó código de aplicación, no se ejecutó SQL, no se importaron datos, no se modificó Supabase, no se tocó producción y no se publicó.

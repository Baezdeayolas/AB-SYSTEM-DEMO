# ETAPA 2D-7 — DISEÑO TÉCNICO DEL CATÁLOGO, PRECIOS, STOCK E IMPORTACIONES

**Entorno:** AB SYSTEM DEMO exclusivamente  
**Rama:** `work/ab-system-multempresa-ui`  
**Estado:** propuesta de modelo para revisión; no es migración ejecutable.  
**No autoriza:** SQL, cambios de frontend, importación real, despliegue, merge ni modificación de producción.

## 1. Objetivo y decisiones de base

Definir un modelo multiempresa que reciba el Excel real `ListaPrecios_6571.xlsx`, conserve el historial de importación y mantenga separados catálogo, precios y saldos por depósito.

Decisiones funcionales ya confirmadas:
- Una importación válida puede incorporar artículos nuevos y actualizar los existentes.
- Código de artículo y descripción son los únicos campos obligatorios para un artículo nuevo.
- Los precios 0 son válidos y deben conservarse.
- `Envases`, `Master` e `Inner` se preservan como valores de origen, sin interpretarlos como unidades de empaque ni utilizarlos en cálculos.
- CENTRAL y CDE son saldos separados y visibles.
- Para mostrar disponibilidad de referencia en un pedido se puede sumar CENTRAL + CDE, sin alterar los saldos.
- Crear, guardar o editar un pedido no descuenta, reserva ni mueve stock.
- Los artículos ausentes del Excel no se borran, inactivan ni ponen a cero automáticamente.
- La importación no modifica pedidos históricos ni sus precios/cantidades/totales.

## 2. Modelo lógico propuesto

### 2.1 `catalog_items` — identidad y ficha del artículo

Mantener inicialmente la tabla legacy y su `payload` JSONB durante la transición. Incorporar `company_id` para segmentación multiempresa, después de preflight y backfill verificado.

Campos lógicos objetivo:
- `company_id`: empresa propietaria, FK a `companies`.
- `code`: código de artículo como texto; no convertir a número.
- `payload`: datos descriptivos y de compatibilidad del producto.
- `updated_at`: última actualización.

Datos a preservar en `payload` (sin semántica nueva): código de fábrica, código de barra, descripción, agrupaciones 1–3 y valores originales de `Envases`, `Master`, `Inner`. Los códigos de fábrica y barra se conservan como texto, incluidos ceros iniciales. El código de artículo y descripción son obligatorios; código de fábrica y barra no son obligatorios según el Excel real.

Restricción objetivo: unicidad `(company_id, code)`. La PK actual global sobre `code` no puede retirarse hasta diseñar y probar una transición segura; no aplicar ambos modelos de unicidad a ciegas.

### 2.2 `company_product_prices` — listas de precios

Tabla normalizada propuesta para precios por artículo y empresa:

| Campo lógico | Regla |
|---|---|
| `company_id` | Obligatorio, FK a `companies` |
| `product_code` | Código texto del artículo |
| `price_list` | Valores permitidos: 1, 2 o 3 |
| `price` | Numérico no negativo; cero válido |
| `updated_at` | Fecha/hora de actualización |
| `source_batch_id` | Lote que produjo el valor, nullable solo si se justifica para backfill |

Clave única objetivo: `(company_id, product_code, price_list)`. Cada Excel actualiza las tres listas del artículo. Un cero explícito reemplaza el precio anterior por cero. Un valor inválido bloquea el lote. Un campo vacío en una futura versión no debe convertirse silenciosamente en cero; su tratamiento se definirá explícitamente antes de activar esa versión del parser.

### 2.3 `company_stock` — saldo vigente por depósito

Tabla normalizada propuesta:

| Campo lógico | Regla |
|---|---|
| `company_id` | Obligatorio, FK a `companies` |
| `product_code` | Código texto del artículo |
| `warehouse_code` | Solo `CENTRAL` o `CDE` inicialmente |
| `quantity` | Numérico no negativo |
| `updated_at` | Fecha/hora de última actualización |
| `source_batch_id` | Lote Excel que produjo el saldo |

Clave única: `(company_id, product_code, warehouse_code)`. La importación actualiza CENTRAL y CDE de forma independiente. No consolidar ambos depósitos en una sola columna persistida.

**Importante:** el libro real trae ambas columnas en las 9.536 filas, con valores numéricos y ceros explícitos. Para un lote válido, cero significa saldo cero. Si en una versión futura falta una columna completa o una celda queda vacía, el proceso debe detenerse o aplicar una política aprobada por campo; nunca asumir que vacío equivale a cero.

### 2.4 `catalog_import_batches` — cabecera de importación

Una fila por intento de importación:
- `id` UUID.
- `company_id` empresa destino.
- `created_by` usuario que inició la carga.
- `created_at` fecha/hora.
- `file_name` nombre original del archivo.
- `file_fingerprint` huella del contenido para detectar reenvíos idénticos, si se implementa.
- `status`: `uploaded`, `validating`, `ready`, `published`, `rejected` o `failed`.
- Conteos: filas leídas, válidas, nuevas, existentes, errores y advertencias.
- `published_at` y resumen final, cuando corresponda.

El lote pertenece siempre a una empresa; la empresa no se deduce del nombre del archivo ni de un dato editable enviado por el navegador. Se valida contra la sesión y permisos backend.

### 2.5 `catalog_import_batch_rows` — detalle y diagnóstico

Una fila por registro Excel procesado, con referencia al lote y número de fila de origen. Debe permitir revisar errores sin exponer innecesariamente información personal.

Campos conceptuales: `batch_id`, `row_number`, `product_code`, `status`, `error_codes`, `normalized_payload` y marcas temporales. Evitar duplicar información sensible o almacenar el libro completo dentro de JSONB.

El detalle conserva suficiente evidencia para explicar por qué una fila fue aceptada o rechazada. La retención y limpieza de lotes antiguos se definirán antes de producción.

### 2.6 Historial de cambios de stock

Se mantiene como requisito de auditoría un historial append-only para cambios de stock, con empresa, artículo, depósito, cantidad anterior/nueva, diferencia, actor, fecha, motivo y lote de origen.

Para importaciones, cada cambio publicado puede registrar el saldo anterior y el nuevo saldo. No generar un movimiento si el valor no cambió, salvo que una política de auditoría decida registrar también las observaciones sin cambio. Las correcciones futuras se registran como nuevos eventos; no se edita el historial.

Este historial es distinto de una salida física o facturación. El pedido comercial no genera evento de stock. Una futura salida física requerirá un flujo separado y explícito.

## 3. Mapeo del Excel real

Una hoja `Sheet0`; encabezados efectivos en fila 5; datos desde fila 6. Mapeo lógico:

| Excel | Campo lógico |
|---|---|
| `Cód.Artículo` | `catalog_items.code` |
| `Cód.Fábrica` | payload `factory_code` |
| `Cód.Barra` | payload `barcode` |
| `Agrup.1` / `Agrup.2` / `Agrup.3` | payload `group_1` / `group_2` / `group_3` |
| `Descripción` | payload `description` |
| `Envases` / `Master` / `Inner` | valores de origen sin semántica operativa asignada |
| `CENTRAL` | `company_stock.warehouse_code = CENTRAL` |
| `CDE` | `company_stock.warehouse_code = CDE` |
| `1` / `2` / `3` | `company_product_prices.price_list = 1/2/3` |

Normalizar encabezados (Unicode/diacríticos, mayúsculas y separadores) y aceptar alias documentados. Si dos encabezados se mapean al mismo campo lógico, bloquear por ambigüedad. Los códigos siempre se leen como texto.

## 4. Proceso de importación atómica

1. Resolver empresa activa y comprobar que el actor es `company_admin` o `superadmin_global` autorizado.
2. Recibir el archivo y crear el lote en estado `uploaded`.
3. Analizar hoja, encabezados, tipos y filas sin tocar datos vigentes.
4. Validar: código y descripción; códigos duplicados; números finitos/no negativos para stock y precios; compatibilidad de encabezados; precios cero válidos.
5. Generar previsualización con artículos nuevos/existentes, conteos, diferencias de stock por CENTRAL/CDE, diferencias de precios, advertencias y errores.
6. Permitir confirmar solo a un administrador autorizado de la empresa.
7. Publicar en una transacción indivisible: ficha, precios, saldos, historial de cambios y estado del lote. Si una parte falla, rollback de todo.
8. Devolver resumen y dejar el lote consultable para auditoría.

El archivo no se escribe directamente sobre tablas vigentes durante la lectura. No debe existir un estado donde catálogo se actualizó pero stock o precios no.

## 5. Reglas de upsert y ausencia de artículos

- Código nuevo + descripción válida: insertar artículo.
- Código existente: actualizar campos incluidos y válidos según política de columnas.
- Cero explícito en precio: guardar cero.
- Cero explícito en CENTRAL/CDE: guardar saldo cero para ese depósito.
- Artículo no presente en el archivo: conservarlo sin cambios; no borrar, inactivar ni poner en cero.
- Código repetido dentro del archivo: rechazar el lote completo y señalar filas duplicadas.
- No modificar pedidos, propietarios, precios históricos ni totales guardados en pedidos.
- No aplicar descuento/reserva por pedidos.

Debe definirse antes de implementar si un campo opcional vacío en una fila existente conserva el valor anterior o lo reemplaza por NULL/vacío. El Excel inspeccionado no tiene vacíos en campos numéricos, pero el parser debe distinguir vacío, cero e inválido.

## 6. Seguridad multiempresa y RLS

- Toda tabla de este modelo lleva `company_id` directo o lo deriva de una FK cuyo acceso esté protegido de forma equivalente.
- RLS filtra por empresa activa y membership válida; admin empresa administra su empresa, vendedor solo lectura operativa autorizada, superadmin según contexto global aprobado.
- No confiar en `company_id`, `created_by`, `status` ni permisos enviados por frontend.
- La función de publicación valida actor, empresa y estado del lote dentro del backend.
- Sustituir coordinadamente las políticas permisivas legacy `USING (true)`; añadir políticas nuevas sin retirar las antiguas no aísla datos.
- Revocar permisos SQL objeto por objeto tras inventariar consumidores. No usar REVOKE masivo ni cambiar defaults internos de Supabase.
- No habilitar tablas ni frontend antes de probar JWT de superadmin, admin de empresa, vendedor y usuario sin membership.

## 7. Compatibilidad con tablas legacy

- `catalog_items.payload` contiene hoy datos usados por frontend; conservarlo durante transición.
- `inventory_current` está limitado a `id = 1` y no segmenta empresa; no debe seguir siendo fuente multiempresa.
- No borrar ni renombrar `sc`, `sd`, `p1`, `p2`, `p3` ni retirar `inventory_current` en el primer lote.
- Antes de decidir cuál es la fuente de lectura durante transición, localizar todos los escritores y lectores, incluidos procesos externos y Edge Functions.
- Definir una única fuente canónica y un adaptador de compatibilidad temporal para el frontend; evitar que JSONB y tablas normalizadas se actualicen por separado.
- La transición de claves primarias globales a unicidad por empresa requiere un plan separado, porque las PK actuales usan `code` global.

## 8. Índices y restricciones a evaluar

Objetivos conceptuales (no SQL):
- FK e índice por `company_id` en todas las tablas empresariales.
- Índice único `(company_id, code)` para productos.
- Índice único `(company_id, product_code, price_list)` para precios.
- Índice único `(company_id, product_code, warehouse_code)` para stock.
- Índices por `(company_id, created_at DESC)` en lotes.
- Índice por `(batch_id, row_number)` en filas de importación.
- Checks de precio/stock finitos y no negativos; lista y depósito dentro de valores permitidos.

Los índices y constraints definitivos se preparan después de validar compatibilidad con PK/FK legacy, volumen y estrategia de backfill.

## 9. Pruebas de aceptación

1. Dos empresas pueden tener el mismo código de artículo sin compartir ficha, precio ni stock.
2. Admin de empresa A no puede consultar ni publicar datos de empresa B.
3. Vendedor no puede importar ni publicar.
4. Superadmin opera solo dentro del contexto permitido y auditado.
5. Código alfanumérico y ceros iniciales se conservan.
6. Artículo nuevo con solo código y descripción se incorpora.
7. Precio cero se conserva.
8. Envases/Master/Inner se preservan sin cálculos derivados.
9. CENTRAL y CDE permanecen separados y cada uno acepta cero.
10. Artículo ausente del Excel no cambia.
11. Duplicados, negativos, infinito, texto numérico inválido o encabezados ambiguos bloquean publicación.
12. Error durante publicación revierte ficha, precios, stock, auditoría y estado final del lote.
13. Importación repetida del mismo archivo no crea duplicados; la política de reintento queda idempotente.
14. Crear/editar pedido no cambia saldo ni historial de stock.
15. Pedidos existentes conservan íntegramente sus valores históricos.

## 10. Decisiones todavía necesarias antes del SQL

1. **Campos opcionales vacíos en artículos existentes:** conservar valor anterior o reemplazarlo por NULL/vacío. No aplica a los ceros explícitos.
2. **Significado de `sd`:** la revisión de frontend no demostró su significado en todos los consumidores. No inferir equivalencia con CDE hasta completar inventario y compatibilidad.
3. **Fuente canónica y convivencia temporal:** cerrar la lista de todos los procesos que leen/escriben `catalog_items.payload` e `inventory_current`.
4. **Respaldo/restauración DEMO:** evidencia de backup y restauración de prueba antes del primer lote mutante.
5. **Retención de lotes y filas:** definir período y política de limpieza/auditoría.

## 11. Secuencia siguiente

1. Completar inventario de consumidores y escritores de catálogo/inventario en todo el repositorio DEMO y servicios asociados.
2. Confirmar respaldo/restauración DEMO.
3. Diseñar preflight SQL de solo lectura para claves, duplicados, FKs, tamaños y compatibilidad de datos.
4. Preparar por separado el primer lote SQL aditivo, su verificación y rollback, para revisión del usuario.
5. No cambiar RLS ni frontend hasta que esquema, backfill y pruebas JWT estén aprobados.

## 12. Registro de ejecución

Este documento es diseño. No se ejecutó SQL, no se modificó Supabase, no se importó el Excel, no se cambió código de aplicación, no se modificó producción y no se publicó.
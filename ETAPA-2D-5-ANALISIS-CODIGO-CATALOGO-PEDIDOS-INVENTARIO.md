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
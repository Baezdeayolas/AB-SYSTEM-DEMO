# ETAPA 2D-3 — INFORME DE PREFLIGHT Y CRITERIOS DE MIGRACIÓN

**Entorno:** AB SYSTEM DEMO / Supabase DEMO exclusivamente  
**Rama:** `work/ab-system-multempresa-ui`  
**Estado:** PREFLIGHT 2D-2 COMPLETADO — DISEÑO PREVIO, SIN CAMBIOS DE DATOS

## 1. Alcance y seguridad

Este documento consolida los resultados comunicados por el usuario de los bloques A-I de `ETAPA-2D-2-PREFLIGHT-DATOS-JSONB-SOLO-LECTURA.sql`. Las consultas fueron de solo lectura. No se ejecutaron DDL, DML, GRANT ni REVOKE. No se modificó Supabase.

Los resultados corresponden únicamente a Supabase DEMO. No aplicar este análisis a producción.

## 2. Resultados confirmados

| Área | Resultado |
|---|---|
| `catalog_clients` | 4 filas; payload JSONB raíz `object`; 8 claves en cada objeto |
| `catalog_items` | 5 filas; payload JSONB raíz `object`; 11 claves en cada objeto |
| `catalog_import_rows` | 0 filas |
| `inventory_current` | 1 fila; `items` es un array JSONB con 0 elementos |
| `orders` | 1 fila; payload raíz `object`; 12 claves |
| Pedido histórico | `legacy_source = archive`; `owner_id` no es NULL |
| Propietarios de pedidos | 1 propietario distinto para 1 pedido |
| Duplicados de códigos | Ninguno detectado en `catalog_items` ni `catalog_clients` |
| Duplicados de clave de importación | Ninguno detectado; la tabla está vacía |
| Empresa | 1 empresa DEMO |
| Membresías | 1 `company_admin` activo y 1 `seller` activo |
| `seller_assignments` | 1 fila |

## 3. Interpretación y límites

1. La muestra de productos y clientes es pequeña y presenta uniformidad en el número de claves JSONB. El preflight contó claves, pero no identificó ni validó los nombres, tipos o significado de cada clave.
2. El pedido histórico tiene propietario asignado, pero estos resultados no demuestran que ese propietario sea miembro activo de la empresa Ko’ẽju. Tampoco identifican de forma fiable quién creó originalmente el pedido.
3. No asignar `company_id` al pedido histórico hasta verificar la relación entre su `owner_id` y la membresía empresarial. Si no se puede demostrar, detener el backfill y definir una resolución explícita; no adivinar.
4. El array `inventory_current.items` está vacío. Esto confirma que esa fila no contiene elementos en su array, pero no demuestra por sí solo que la aplicación no mantenga cantidades o cálculos de stock en otras fuentes o en el payload de productos.
5. La uniformidad del número de claves JSONB no garantiza que todos los valores sean válidos ni que no existan diferencias semánticas.
6. La tabla `catalog_import_rows` vacía significa que no hay filas históricas en esa tabla que migrar en este momento.

## 4. Criterios obligatorios para el diseño de migración

### 4.1 Catálogos
- Antes de añadir `company_id` a productos y clientes, identificar todos los consumidores de `catalog_items` y `catalog_clients` en frontend, scripts, funciones, triggers y servicios.
- Definir claves únicas por empresa, por ejemplo `(company_id, code)`, conservando los códigos actuales.
- No convertir los catálogos a un nuevo formato JSONB hasta documentar los campos realmente usados por la aplicación.

### 4.2 Pedidos
- Conservar `id`, `owner_id`, `legacy_id`, `legacy_source`, `payload` y `updated_at` del pedido existente.
- Los pedidos nuevos deben registrar `company_id`, `owner_id` y `created_by` conforme a la política de identidad ya acordada.
- El backfill histórico de `company_id` requiere comprobar que el propietario pertenece a la empresa destino.
- `created_by` histórico puede quedar NULL cuando el actor original no sea verificable; no inferirlo a partir de `owner_id`.
- Mantener la restricción única existente `(owner_id, legacy_source, legacy_id)` salvo evidencia concreta de conflicto y una decisión documentada.

### 4.3 Inventario
- No crear existencias ficticias ni poblar automáticamente el inventario a partir de supuestos.
- Antes de diseñar tablas de movimientos, rastrear cómo la aplicación obtiene, calcula, importa y actualiza el stock.
- El futuro inventario debe quedar aislado por empresa y registrar movimientos auditables y transaccionales.

### 4.4 Autorización
- RLS y validaciones backend deben aplicar el aislamiento por empresa; el frontend no es una frontera de seguridad.
- El vendedor solo debe consultar sus pedidos; el administrador de empresa puede consultar los pedidos de su empresa; el superadmin global conserva el alcance global acordado.
- La selección de vendedor debe basarse en membresías activas `seller` de la misma empresa, nunca en etiquetas estáticas ni UUID introducido libremente.

## 5. Próxima fase propuesta: 2D-4 — verificación de relaciones y mapeo

Antes de redactar cualquier migración mutante, completar estas verificaciones de solo lectura:

1. Verificar si el `owner_id` del pedido histórico corresponde a un usuario con membresía activa en Ko’ẽju, sin exponer UUID en los resultados compartidos.
2. Inspeccionar de forma segura la estructura y tipos de campos JSONB que consume la aplicación, sin revelar valores sensibles.
3. Rastrear la fuente real del stock y los flujos de importación/actualización.
4. Preparar una matriz de mapeo por tabla: columna actual, columna objetivo, origen del dato, regla de backfill, validación y tratamiento de excepciones.
5. Revisar el plan de pruebas RLS bajo identidades de superadmin, administrador de empresa y vendedor.

## 6. Puerta de aprobación

Este informe no autoriza cambios en Supabase. Cualquier script que modifique estructura, datos, políticas o privilegios deberá presentarse completo para revisión y recibir aprobación explícita antes de que el usuario lo ejecute manualmente en Supabase DEMO.

**No autorizado:** producción, migraciones automáticas, cambios de permisos masivos, publicación o merge de ramas.

**Conclusión:** el preflight 2D-2 está completo. La base DEMO es pequeña, pero el pedido histórico requiere verificación de pertenencia empresarial y el origen del stock debe rastrearse antes de diseñar el backfill.
# ETAPA 2D-24 — Auditoría de integración frontend y esquema AB SYSTEM DEMO

**Estado:** inspección de código y diseño; no ejecutado en Supabase  
**Rama:** `work/adaptacion-multiempresa-v1`  
**Alcance:** exclusivamente `AB-SYSTEM-DEMO` y su Supabase DEMO  
**Ko’ẽju producción:** fuera de alcance; no modificar

## 1. Resultado ejecutivo

La aplicación frontend ya fue adaptada para trabajar con contexto de empresa, catálogo y clientes por `company_id`, pedidos por empresa, asignaciones de vendedores y saldos independientes CENTRAL/CDE. Sin embargo, el esquema de inventario que consume el frontend corresponde al Lote 2D-22 y debe existir en Supabase antes de que el inicio de sesión pueda completar la carga de datos.

El código no debe publicarse ni probarse contra una base que no tenga todas las tablas, RPC, políticas y membresías requeridas. La revisión del repositorio no equivale a una validación de la base activa.

## 2. Componentes inspeccionados

- `index.html`: interfaz de acceso, selector de empresa, catálogo, clientes, pedidos, stock, administración y navegación.
- `cloud-sync-demo.js`: autenticación, contexto multiempresa, carga de datos, pedidos, stock, importación Excel y administración.
- `data-demo.js`: datos sintéticos para el acceso público de demostración.
- `sql/ETAPA-2D-21-MIGRACION-MULTIEMPRESA-DEMO-CONSOLIDADA-DRAFT.sql`: borrador consolidado de esquema, claves, RLS y permisos.
- `sql/ETAPA-2D-22-INVENTARIO-CENTRAL-CDE-IMPORTACION-EXCEL.sql`: esquema y RPC de inventario por depósito e importación.
- `supabase/functions/admin-users/index.ts`: función de servidor para administración global.
- `supabase/config.toml`: configuración de la Edge Function.

## 3. Dependencias reales del frontend

### Inicio de sesión y empresas

El frontend llama a `ab_is_global_superadmin()`. Para usuarios ordinarios consulta membresías activas y después carga empresas activas. El selector de empresa se muestra a superadministradores globales o a usuarios con más de una empresa.

El cambio de empresa limpia el carrito, pedidos, catálogo, clientes y vendedor antes de cargar el nuevo contexto.

### Datos comerciales

La función `loadData()` consulta:

- `catalog_items` filtrado por `company_id`.
- `catalog_clients` filtrado por `company_id`.
- `inventory_location_balances` filtrado por `company_id`.
- `company_memberships` para obtener vendedores activos.
- `seller_assignments` filtrado por empresa y, para vendedores, por el usuario autenticado.

Los pedidos se consultan en `orders` filtrando por `company_id`. La inserción guarda `company_id`, `owner_id`, `created_by` y un payload con cliente, vendedor y líneas.

### Stock CENTRAL/CDE

El frontend lee `inventory_location_balances` y llama a `ab_set_inventory_location_balance(uuid,text,text,numeric,text,text,text)` para ajustes manuales. CENTRAL y CDE se guardan como filas separadas.

La importación Excel llama a `ab_import_company_catalog_v2(uuid,text,jsonb)`. Cada fila enviada contiene `code`, `payload`, `stock_central` y `stock_cde`.

### Importación

La vista previa identifica artículos nuevos y existentes. La aplicación no elimina los artículos ausentes del archivo. La RPC 2D-22 actualiza el payload existente combinando campos, y aplica los dos saldos de depósito por separado.

La carga se procesa en lotes. Si un lote falla después de otros exitosos, los anteriores ya pueden haber quedado confirmados; el mensaje de interfaz lo advierte. Esto debe considerarse en la prueba y en la guía operativa.

### Demostración pública

El botón **Ver demostración** no consulta los datos de Supabase. Carga exclusivamente los cinco productos y cuatro clientes sintéticos de `data-demo.js`, oculta funciones de escritura y opera en solo lectura.

Por tanto, el catálogo real reutilizado desde Ko’ẽju no aparece automáticamente en el modo público actual. El modo autenticado sí carga el catálogo de la empresa seleccionada. Cualquier futura exposición pública del catálogo real debe ser una decisión separada y usar únicamente datos aprobados para exposición pública.

## 4. Dependencias SQL y diferencias que deben validarse

1. El frontend espera `inventory_location_balances` y `inventory_location_movements`; el preflight ya compartido consultó `inventory_current`, pero no verificó expresamente la existencia o ausencia de las nuevas tablas.
2. El frontend espera las RPC `ab_set_inventory_location_balance` y `ab_import_company_catalog_v2`. Ambas están definidas en el archivo 2D-22.
3. El archivo 2D-22 crea las filas iniciales de CENTRAL y CDE con cantidad cero. No convierte el antiguo saldo genérico en CENTRAL ni en CDE, ni copia cantidades antiguas de `payload.sc` o `payload.sd` a los nuevos saldos. La primera importación completa del Excel aprobado establece los saldos por depósito.
4. El archivo 2D-22 termina en `COMMIT`. A diferencia de los borradores que terminan en `ROLLBACK`, ejecutarlo sí persiste cambios. No ejecutarlo hasta tener respaldo restaurable, precondiciones verificadas, revisión completa y aprobación específica.
5. El archivo 2D-21 todavía busca `companies.code = 'KOEJU'` para el backfill. No está adaptado a la decisión ABDEMO y termina en `ROLLBACK`. No ejecutarlo.
6. El frontend requiere una membresía `company_admin` para importar catálogo/clientes y ajustar stock. Los resultados actuales indican que DEMO2 solo tiene una membresía seller. No se debe elevar ni reemplazar una cuenta sin confirmar qué usuario debe administrar AB SYSTEM DEMO.
7. La Edge Function `admin-users` valida el JWT y consulta `global_roles` antes de usar la clave de servicio en el servidor. La función no debe desplegarse hasta que la tabla, políticas, rol global y configuración hayan sido verificados en el proyecto DEMO.

## 5. Identidad de empresa: decisión aún pendiente de cerrar

Los resultados de Supabase muestran dos filas empresariales diferentes:

- `DEMO2`: empresa llamada EMPRESA DEMO, activa, con una membresía seller y sin filas comerciales asociadas.
- `KOEJU`: empresa llamada Ko’ẽju, activa, con los catálogos y registros comerciales actuales, y membresías company_admin/seller.

El documento 2D-23 propone transformar la fila KOEJU a AB SYSTEM DEMO conservando su UUID, lo que preservaría directamente las relaciones de las 9.541 filas de catálogo, 3.498 clientes y demás registros. La alternativa es usar el UUID de DEMO2 y copiar los datos aprobados desde KOEJU, manteniendo KOEJU como origen. Esta segunda alternativa requiere más validaciones y una estrategia de anonimización para clientes.

No cambiar códigos, nombres, UUID, membresías ni asignaciones hasta cerrar expresamente cuál de las dos filas será la empresa destino. Ko’ẽju producción no se toca bajo ninguna alternativa.

## 6. Privacidad y contenido de demostración

El payload de clientes contiene campos de nombre, identificación, teléfono, ubicación y datos de deuda/saldos. No deben copiarse sin anonimización a una demostración pública. La estrategia debe generar registros sintéticos que conserven la forma de los campos necesarios para probar la aplicación.

Los payloads completos de productos pueden preservarse según la autorización del propietario, sujetos a revisión de campos internos/confidenciales. El pedido existente debe permanecer fuera de la demo pública hasta revisar y anonimizar sus referencias.

## 7. Secuencia segura recomendada

1. Resolver qué UUID de empresa será AB SYSTEM DEMO: el de KOEJU con datos existentes o el de DEMO2 vacío.
2. Identificar mediante un proceso seguro qué cuenta autorizada será administradora de la empresa destino; no compartir contraseñas, tokens ni claves.
3. Completar preflight de tablas, funciones, políticas, triggers, grants y dependencias, incluyendo las dos tablas y RPC de inventario CENTRAL/CDE.
4. Obtener y verificar un respaldo completo y restaurable del proyecto Supabase DEMO.
5. Preparar la migración de identidad y datos con validaciones de conteos, membresías, pedidos, vendedores y referencias.
6. Preparar anonimización de clientes y decidir el tratamiento del pedido histórico.
7. Revisar y aprobar el Lote 2D-21 adaptado y luego el Lote 2D-22. No cambiar `ROLLBACK` a `COMMIT` ni ejecutar scripts sin aprobación explícita.
8. Después de la migración, importar el Excel completo aprobado y conciliar cantidades CENTRAL/CDE por separado.
9. Probar con dos empresas de prueba, usuarios de roles distintos y pruebas negativas de aislamiento.
10. Solo después, revisar modo público, despliegue y publicación con autorizaciones independientes.

## 8. Estado y límites

- No se ejecutó SQL ni se modificó Supabase.
- No se modificó Ko’ẽju producción.
- No se modificó el frontend ni se publicó la aplicación.
- No se fusionó la rama ni se abrió un PR.
- Los archivos 2D-21 y 2D-22 siguen sin autorización de ejecución.

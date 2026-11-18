# ETAPA 2D-23 — Plan de transformación de empresa inicial a AB SYSTEM DEMO

**Estado:** auditoría técnica inicial; preparación, no ejecución  
**Rama:** `work/adaptacion-multiempresa-v1`  
**Destino previsto:** Supabase DEMO existente  
**Ko’ẽju producción:** fuera de alcance, no modificar

## Decisión vigente

La empresa inicial de la plataforma será **AB SYSTEM DEMO**. Se aprovechará el catálogo y los registros comerciales ya existentes en la base DEMO. La fila empresarial actualmente identificada como `KOEJU` se transformará en una empresa de demostración, conservando sus relaciones multiempresa.

El código objetivo sugerido es `ABDEMO`, pendiente de verificar contra las restricciones y referencias existentes. No se cambiará todavía el valor en la base.

## Hallazgos confirmados

1. El archivo `sql/ETAPA-2D-21-MIGRACION-MULTIEMPRESA-DEMO-CONSOLIDADA-DRAFT.sql` contiene un backfill que busca exactamente `public.companies.code = 'KOEJU'`.
2. El backfill usa ese `company_id` para asignar filas sin empresa en `catalog_items`, `catalog_clients`, `catalog_import_rows`, `orders` y `seller_assignments`.
3. El borrador valida que los propietarios de pedidos y las asignaciones tengan membresías de vendedor activas en la empresa KOEJU. Este mapeo no puede suponerse correcto sin consultar los datos actuales.
4. El consolidado 2D-21 terminaba con `COMMIT`, pese a estar descrito en comentarios como borrador que no persiste. Se corrigió el cierre a `ROLLBACK` y se añadieron advertencias explícitas de que el backfill todavía no está adaptado a ABDEMO.
5. El lote 2D-22 depende de las tablas, funciones y políticas creadas por el esquema multiempresa. No debe ejecutarse por separado antes de 2D-21.
6. La app tiene un modo público de solo lectura con datos estáticos en `data-demo.js`; actualmente usa ejemplos sintéticos. El modo público no carga automáticamente los registros reales de Supabase.

## Datos que deben preservarse y tratarse

- **Productos:** conservar los registros y atributos comerciales existentes.
- **Clientes:** conservar registros/códigos y campos necesarios para las pruebas privadas. Antes de habilitar la demo a prospectos, anonimizar nombres personales, teléfonos, domicilios, RUC/identificadores y otros datos que identifiquen a clientes reales.
- **Pedidos:** inspeccionar y anonimizar referencias a clientes/vendedores antes de mostrarlos públicamente. No inferir que el pedido actual sea apto para exposición.
- **Perfiles y membresías:** revisar identidad, rol, estado y relación de cada perfil. No reutilizar contraseñas ni asumir que los perfiles actuales deben convertirse en cuentas públicas.
- **Stock:** no asignar cantidades a CENTRAL/CDE por inferencia. Validar el origen y significado de cada campo; mantener depósitos separados.
- **Ko’ẽju producción:** no leer ni modificar datos productivos como parte de esta transformación.

## Próximas tareas técnicas

1. Ejecutar un preflight estrictamente de solo lectura en el Supabase DEMO actual para obtener el esquema real de `companies`, restricciones, referencias a `companies.code`, conteos por tabla y membresías resumidas.
2. Verificar respaldo completo y restaurable del proyecto DEMO. Los CSV parciales no sustituyen un respaldo restaurable.
3. Definir el nombre visible, código definitivo y estado de la empresa inicial AB SYSTEM DEMO.
4. Preparar migración transaccional que actualice la fila empresarial existente sin recrearla ni perder su UUID; así se conservan los `company_id` y relaciones ya asociados.
5. Adaptar el backfill para que utilice el UUID verificado de la empresa DEMO, y no una identidad de Ko’ẽju codificada.
6. Crear una estrategia de anonimización reversible solo desde el respaldo privado, nunca desde la demo pública.
7. Adaptar el modo de demostración pública para cargar datos de la empresa DEMO desde una vía de solo lectura y con datos anonimizados; no exponer claves privilegiadas en frontend.
8. Ejecutar pruebas de aislamiento con una segunda empresa ficticia, incluyendo productos y clientes con códigos repetidos.
9. Probar pedidos, importación Excel y depósitos CENTRAL/CDE. Guardar un pedido no debe descontar ni reservar stock; importar Excel puede agregar/actualizar artículos pero no eliminar los ausentes.

## Controles de seguridad

- 2D-21 permanece en `ROLLBACK`.
- No ejecutar 2D-21 ni 2D-22 por ahora.
- No borrar empresas, tablas, clientes, productos, pedidos ni perfiles.
- No cambiar RLS, grants, claves, credenciales ni configuración productiva.
- No fusionar a `main`, abrir PR ni publicar hasta tener las pruebas completas y autorización.
- Cualquier ejecución SQL futura requiere mostrar el script completo, explicar el efecto y recibir aprobación específica.

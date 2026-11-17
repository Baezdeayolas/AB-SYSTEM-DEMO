# AB SYSTEM DEMO

Entorno independiente para construir y validar la plataforma común AB SYSTEM antes de cualquier cambio en producción.

## Componentes actuales en la rama de trabajo

- `index.html`: estructura DEMO con acceso, cabecera comercial, paneles de búsqueda, pedido, archivo, resumen, stock y administración.
- `cloud-sync-demo.js`: autenticación Supabase DEMO, lectura de catálogo/clientes, asignaciones de vendedor y guardado/consulta básica de pedidos.
- `data-demo.js`: catálogo y clientes ficticios de respaldo.
- `style.css`: estilos de referencia y adaptaciones.
- `service-worker.js`: caché independiente de DEMO.

## Estado de validación

La reconstrucción de estructura y navegación está en curso en la rama `work/ab-system-multempresa-ui`. No se considera lista para publicar.

Pendiente de verificar en un entorno de prueba:
- Compatibilidad de las consultas con las columnas reales de Supabase DEMO.
- Inicio/cierre de sesión y perfiles `admin` / `seller`.
- Lectura de catálogo, clientes y asignaciones.
- Guardado y lectura de pedidos, incluidas las políticas RLS.
- Flujo completo en móvil y escritorio y comparación visual con Ko'eju.
- Generación/compartir PDF y escáner, que todavía son marcadores pendientes.
- Alta de clientes, edición de pedidos, gestión real de stock y selector multiempresa.

No se ha ejecutado una prueba integral de navegador ni una auditoría de RLS. La existencia de código para una función no implica que haya sido validada.

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
- Pedidos nuevos guardados con `company_id`; crear pedidos no modifica `inventory_current`.
- Contrato frontend preparado para el esquema empresarial; la migración SQL queda pendiente de revisión del preflight y de una restauración de respaldo.

**No aplicar todavía la migración ni publicar esta rama.** Antes se debe revisar el inventario de claves foráneas/índices y probar la migración en una copia aislada. Esta etapa tampoco completa todavía la paridad funcional con Ko'eju (PDF, edición/reutilización de pedidos, importación Excel y administración de usuarios).


### Bloqueos antes de probar o publicar esta adaptación

- El frontend ya consulta `company_id` en tablas comerciales y `created_by` al guardar pedidos; esas columnas todavía no están confirmadas en el esquema activo.
- El guardado identifica al vendedor mediante la asignación de la empresa: `owner_id` es el usuario vendedor y `created_by` es quien creó el pedido.
- Falta diseñar y aprobar el lote SQL completo, incluyendo claves compuestas, políticas RLS, validación de vendedor/membresía y rollback.
- Falta probar la migración en una restauración independiente de DEMO. El respaldo actual del proyecto nuevo todavía no tiene restauración comprobada.
- La adaptación funcional completa de Ko'eju (PDF, edición/reutilización de pedidos, importación Excel y administración) se realizará después de validar esta base multiempresa.


### Corrección de la iteración actual

Se corrigió un defecto funcional: el selector de empresa se mostraba, pero no tenía conectado el evento que cambiaba el contexto. Ahora el cambio activa la recarga de catálogo, clientes, vendedores y pedidos; si la carga falla, se restaura el contexto anterior. También se evita el doble envío de pedidos y se completa el total del archivo.

**Validación pendiente:** no se ejecutaron pruebas de navegador ni pruebas con JWT/RLS. La aplicación sigue sin ser compatible con el esquema Supabase activo hasta que se apruebe y ejecute una migración verificada que añada y proteja las relaciones empresariales. No publicar ni probar contra datos reales todavía.

**Identidad de empresas pendiente de confirmar:** la empresa existente en DEMO figura con código `KOEJU`. La empresa `DEMO` para pruebas de prospectos debe ser una empresa separada; no cambiar el código ni reasignar los registros existentes por suposición.

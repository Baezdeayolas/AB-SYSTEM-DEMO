# Análisis de impacto del frontend — transición multiempresa DEMO

**Rama:** `work/ab-system-multempresa-ui`  
**Estado:** inspección estática; no se ejecutaron pruebas de navegador ni cambios funcionales.

## Hallazgos de `cloud-sync-demo.js`

1. El cliente Supabase carga `catalog_items` y `catalog_clients` sin filtrar por empresa:
   - `db.from('catalog_items').select('code,payload')`
   - `db.from('catalog_clients').select('code,payload')`
   En el modelo multiempresa, RLS debe aplicar el aislamiento y el frontend debe consultar con un contexto empresarial explícito validado en servidor. Un filtro en JavaScript no es seguridad.

2. Los pedidos se consultan con `orders.select(...)` sin `company_id`; se insertan con `owner_id`, `legacy_id`, `legacy_source`, `payload`, `updated_at`. La futura escritura debe asociar la empresa validada por backend/RLS y conservar `owner_id`.

3. El perfil actual se lee desde `profiles.role` y solo acepta `admin` o `seller`. La aplicación no reconoce `superadmin_global` ni membresías por empresa. No se debe ampliar este chequeo de frontend como sustituto de la autorización del backend.

4. Las asignaciones de vendedor se consultan solo por `user_id`; el modelo multiempresa debe incluir `company_id` y validar la membresía activa.

5. La vista de stock es expresamente ficticia: renderiza `Stock ficticio` desde `items.sc`. No consulta saldos reales ni registra movimientos. No debe presentarse como inventario real hasta implementar el backend transaccional.

6. El encabezado de `index.html` muestra una empresa estática “EMPRESA DEMO”; no existe selector real ni vista global consolidada.

7. El panel administrativo es un placeholder. PDF y escáner también son placeholders.

## Cambios de aplicación requeridos después de aprobar el esquema

- Resolver membresías y empresas disponibles al iniciar sesión.
- Para superadmin, ofrecer vista global y selector de empresa; para usuarios de empresa, restringir el selector a membresías activas.
- Mantener un `activeCompanyId` solo como estado de UI; cada operación debe comprobar permisos en RLS/backend.
- Limpiar carrito, cliente seleccionado, vendedor y datos temporales al cambiar de empresa.
- Incluir empresa en consultas/escrituras donde corresponda, sin confiar en un ID enviado por el cliente.
- Añadir `company_id` a los pedidos y asignaciones; conservar payloads y propietario.
- Sustituir el stock ficticio por saldos reales y una función transaccional de movimientos.
- Ocultar opciones administrativas según permisos del backend, pero validar todas las acciones en servidor.
- Añadir pruebas de regresión para login, catálogo, clientes, pedido, archivo, cambio de empresa y sesión expirada.

## Bloqueos antes de codificar

- Falta confirmar cuál de los dos perfiles actuales corresponde al usuario propietario/superadmin y cuál debe ser administrador o vendedor de Ko’ẽju.
- Falta decidir si un usuario puede pertenecer a varias empresas.
- Falta esquema final aprobado, RLS y método seguro de bootstrap global.
- Falta definir reglas de stock/unidades y probar transacciones.

## Estado de seguridad

La inspección del JavaScript es estática y no certifica seguridad. No se modificó el frontend en esta etapa para evitar conectar una UI multiempresa a un backend que todavía no aplica aislamiento.


## Decisión de identidad de pedidos (definida)

Se separan propietario comercial y actor que registra:
- Vendedor: `owner_id = auth.uid()` y `created_by = auth.uid()`.
- Administrador que registra por un vendedor: `owner_id = UUID del vendedor seleccionado` y `created_by = auth.uid()` del administrador.
- Superadministrador: opera dentro de la empresa seleccionada y conserva el mismo criterio de propietario/actor.

El selector debe obtener UUIDs de membresías activas `seller` en la empresa seleccionada, nunca de nombres libres. RLS/backend debe volver a validar la membresía del propietario en esa empresa. Los vendedores solo leen pedidos donde `owner_id = auth.uid()`; no se concede acceso por `created_by`.

Cambios de esquema necesarios antes de activar este flujo: `orders.company_id` y `orders.created_by`. Para pedidos históricos, `created_by` podrá quedar NULL si el actor original no es verificable. Detalle en `IDENTIDAD-VENDEDORES-Y-PEDIDOS.md`.

**Bloqueo de despliegue:** las tablas de membresía ya existen, pero todavía no tienen políticas RLS que permitan consultarlas desde la aplicación. Las tablas comerciales tampoco tienen aún `company_id`, y `orders` no tiene `created_by`. Por tanto, no se debe activar todavía el nuevo flujo en el cliente ni permitir que el código vuelva silenciosamente al guardado legado.

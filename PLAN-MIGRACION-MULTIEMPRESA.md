# Plan de migración multiempresa — AB SYSTEM DEMO

Estado: borrador técnico para revisión. **NO EJECUTAR DIRECTAMENTE.** No es una migración SQL lista para producción.

## 1. Alcance y límites

- Destino exclusivo: proyecto Supabase DEMO asociado a `AB-SYSTEM-DEMO`.
- No modificar el repositorio Ko'eju de producción ni su proyecto Supabase.
- No copiar datos, usuarios, clientes, vendedores, pedidos ni credenciales de producción.
- Este documento no ejecuta SQL, no modifica tablas y no concede permisos.
- La migración real requerirá inspeccionar el esquema completo, adaptar nombres/tipos y recibir aprobación expresa antes de ejecutarla.

## 2. Decisiones funcionales confirmadas

1. Existe un superadministrador global que puede consultar todas las empresas.
2. El superadministrador dispone de dos contextos: vista global consolidada y vista individual de una empresa.
3. Cada empresa tiene administradores y vendedores limitados a su empresa.
4. Productos, clientes, pedidos e inventario pertenecen a una empresa.
5. Cada empresa administra existencias independientes.
6. Cada entrada, salida o ajuste de inventario genera un movimiento histórico inmutable desde la aplicación.
7. Los vendedores solo operan con los permisos y asignaciones autorizados.
8. El selector de empresa es contexto de interfaz, nunca una prueba de autorización.

## 3. Modelo objetivo propuesto

### 3.1 Empresas y membresías

**companies**
- `id uuid primary key`
- `code text unique not null`
- `name text not null`
- `status text not null` (valores controlados, por ejemplo `active` y `suspended`)
- `created_at timestamptz not null`
- `updated_at timestamptz not null`

**global_roles**
- `user_id uuid not null references auth.users(id)`
- `role text not null` (inicialmente solo `superadmin_global`)
- `created_at timestamptz not null`
- Clave primaria propuesta: (`user_id, role`)
- Escritura reservada a un proceso administrativo de confianza; no habrá autoasignación desde el cliente.

**company_memberships**
- `id uuid primary key`
- `company_id uuid not null references companies(id)`
- `user_id uuid not null references auth.users(id)`
- `role text not null` (solo `company_admin` o `seller`)
- `status text not null` (por ejemplo `active` o `suspended`)
- `created_at timestamptz not null`
- Restricción única propuesta: (`company_id, user_id`)

Un usuario podrá pertenecer a más de una empresa únicamente si el superadministrador lo autoriza. Su rol será evaluado por empresa mediante la membresía activa.

### 3.2 Catálogos

**catalog_items**
- Mantener el contenido actual de `code`, `payload` y `updated_at` durante la transición.
- Añadir `company_id uuid not null` después de asignar los registros existentes a una empresa DEMO.
- La clave única objetivo será (`company_id, code`), no `code` global.
- Verificar primero si otras tablas o código dependen de la PK actual `code`.

**catalog_clients**
- Mismo criterio: `company_id` y unicidad (`company_id, code`).
- Los códigos de clientes podrán repetirse en empresas distintas.

**catalog_import_rows**
- Añadir `company_id`.
- Revisar si la clave actual (`import_id, catalog_type, code`) debe convertirse en (`company_id, import_id, catalog_type, code`).
- Toda importación debe validar que el usuario puede administrar el catálogo de esa empresa.

### 3.3 Pedidos

**orders**
- Conservar `id`, `owner_id`, `legacy_id`, `legacy_source`, `payload` y `updated_at` durante una etapa de compatibilidad.
- Añadir `company_id uuid not null`.
- Agregar una FK a `companies(id)`.
- Revisar la restricción única actual (`owner_id, legacy_source, legacy_id`) y evaluar si `company_id` debe formar parte de ella.
- Antes de normalizar `order_items), inspeccionar el formato real de `payload` y las funciones de edición, archivo e importación.
- El pedido debe conservar una instantánea de precios, descripciones y descuentos aplicados al confirmarse, si el formato actual no lo hace ya.

### 3.4 Inventario independiente por empresa

No se debe conservar el modelo de inventario único `id = 1` como autoridad multiempresa.

Modelo normalizado recomendado:

**inventory_current**
- `company_id uuid not null references companies(id)`
- `product_code text not null`
- `quantity numeric not null` (precisión y reglas de unidades por confirmar)
- `updated_at timestamptz not null`
- Clave primaria propuesta: (`company_id, product_code`)

**inventory_movements**
- `id uuid primary key`
- `company_id uuid not null references companies(id)`
- `product_code text not null`
- `movement_type text not null` (entrada, salida, ajuste)
- `quantity_delta numeric not null` (con signo o convención única documentada)
- `quantity_before numeric not null`
- `quantity_after numeric not null`
- `reason text`
- `created_by uuid not null references auth.users(id)`
- `created_at timestamptz not null`
- `source_type text` y `source_id` opcionales para vincular pedidos, recepciones o importaciones.

Toda modificación de stock deberá ejecutarse en una transacción del backend: validar membresía y permisos, bloquear/actualizar la fila de existencias, calcular antes/después y registrar el movimiento. No permitir que el navegador escriba directamente cantidades arbitrarias ni que edite o borre movimientos históricos. Las correcciones se harán con un nuevo movimiento de ajuste.

La FK compuesta hacia el catálogo (`company_id, product_code`) se añadirá cuando se confirme la nueva clave única de `catalog_items`. Esto evita asociar existencias de una empresa con productos de otra.

**Migración del JSONB actual:** antes de transformar `inventory_current.items`, inspeccionar su estructura y todos sus consumidores. Conservar una copia de respaldo DEMO y validar que cada artículo se pueda convertir sin pérdida. No asumir un formato JSON no verificado.

### 3.5 Vendedores y auditoría

**seller_assignments**
- Añadir `company_id`.
- Verificar que la asignación coincida con una membresía activa de rol vendedor.
- Rediseñar su clave primaria si un usuario puede tener distintas asignaciones por empresa.

**audit_logs** (propuesta)
- Registrar acciones administrativas relevantes: alta/suspensión de empresa, cambios de membresía/rol, importaciones y ajustes de inventario.
- Campos sugeridos: `id`, `company_id` nullable para acciones globales, `actor_user_id`, `action`, `entity_type`, `entity_id`, `metadata` limitada y `created_at`.
- No registrar contraseñas, tokens, claves API ni secretos.
- La escritura debe venir de backend confiable; la bitácora no debe ser editable por usuarios ordinarios.

## 4. Autorización y RLS

La política final se redactará por tabla y por operación (SELECT, INSERT, UPDATE, DELETE). No se debe sustituir por una única política genérica sin probar sus efectos.

Reglas obligatorias:

- Una fila comercial solo es visible si el usuario tiene una membresía activa en su `company_id`, o si tiene la asignación global protegida de superadministrador.
- Un administrador de empresa solo puede crear, modificar y borrar datos de su empresa.
- Un vendedor solo puede realizar las operaciones autorizadas en su empresa y sus asignaciones.
- La vista global del superadministrador debe consultar a través de autorización de backend/RLS; no debe basarse en quitar filtros en el navegador.
- INSERT y UPDATE validan la empresa tanto en `USING` como en `WITH CHECK`, según corresponda.
- Cambiar el `company_id` de una fila para moverla entre empresas no será una operación permitida a usuarios ordinarios.
- Los helpers de RLS deben evitar recursión, usar nombres de objetos calificados y tener `search_path` seguro si son `SECURITY DEFINER`.
- Restringir EXECUTE de funciones privilegiadas a los roles estrictamente necesarios.
- Revisar grants SQL junto con RLS. RLS no sustituye los privilegios SQL y no protege operaciones como TRUNCATE.
- Mantener claves `service_role` exclusivamente en backend seguro; nunca en archivos frontend.
- El rol global no debe guardarse como un valor que el usuario pueda editar en `profiles` ni en metadatos modificables por el cliente.

No se propone todavía SQL de políticas ejecutables porque faltan confirmar el esquema final, la propiedad de objetos, las dependencias y el método confiable de asignación inicial del superadministrador.

## 5. Fases de migración

### Fase 0 — inspección previa
1. Obtener DDL exacto de las siete tablas actuales.
2. Revisar todas las constraints, índices, triggers, vistas, funciones, grants y propietarios.
3. Identificar todas las consultas y escrituras del frontend y backend.
4. Inspeccionar ejemplos sintéticos de `payload` de catálogo, clientes, pedidos e inventario.
5. Confirmar la semántica de cantidades, unidades, descuentos y movimientos.
6. Definir la identidad del superadministrador mediante un procedimiento administrativo fuera del cliente.

### Fase 1 — crear estructura base
1. Preparar respaldo y procedimiento de reversión en DEMO.
2. Crear `companies`, `global_roles` y `company_memberships`.
3. Crear una empresa DEMO inicial y usuarios de prueba sintéticos.
4. Verificar relaciones, restricciones e índices.
5. No otorgar acceso global hasta probar el mecanismo de autorización.

### Fase 2 — asignar empresa a los datos existentes
1. Añadir `company_id` nullable temporalmente a las tablas comerciales.
2. Asignar todos los registros existentes de DEMO a la empresa inicial.
3. Comprobar conteos antes/después y detectar filas huérfanas.
4. Cambiar a NOT NULL y añadir claves foráneas/índices solo después de validar.
5. Migrar el JSONB de inventario mediante un proceso verificado y reversible.

### Fase 3 — seguridad
1. Implementar helpers de membresía y superadmin.
2. Activar políticas por operación y tabla.
3. Reducir grants innecesarios, especialmente privilegios destructivos y permisos de roles públicos.
4. Revisar EXECUTE de funciones y propietarios.
5. Probar con sesiones reales de usuarios de prueba; no usar solo consultas como postgres para validar RLS.

### Fase 4 — aplicación
1. Implementar selector de empresa y vista global.
2. Mostrar siempre el contexto de empresa activa.
3. Vaciar/reinicializar carrito, cliente y estado temporal al cambiar de empresa.
4. Asociar todas las escrituras con la empresa autorizada en backend.
5. Implementar movimientos de inventario transaccionales e historial de solo inserción.
6. Adaptar importaciones, pedidos, archivos, resúmenes y reportes.

### Fase 5 — pruebas y aprobación
1. Probar dos empresas ficticias y usuarios distintos para cada rol.
2. Intentar leer y modificar registros de la otra empresa.
3. Manipular manualmente `company_id` en peticiones y comprobar denegación.
4. Intentar autoasignarse roles o membresías privilegiadas.
5. Probar altas, bajas, suspensión, cambio de empresa y sesiones vencidas.
6. Probar consistencia de existencias e historial ante operaciones concurrentes y fallidas.
7. Validar móvil/escritorio y regresión de las funciones actuales.
8. Publicar solo después de aprobación expresa.

## 6. Matriz de pruebas de aceptación

| Actor | Empresa A | Empresa B | Vista global |
| --- | --- | --- | --- |
| Superadmin global | Acceso autorizado | Acceso autorizado | Sí |
| Admin A | Administrar | Denegado | No |
| Vendedor A | Según permisos | Denegado | No |
| Admin B | Denegado | Administrar | No |
| Vendedor B | Denegado | Según permisos | No |
| Sin membresía | Denegado | Denegado | No |

Pruebas adicionales:
- Los códigos de producto/cliente pueden repetirse entre empresas sin colisión.
- No se puede registrar un movimiento para un producto de otra empresa.
- Una salida no puede dejar existencias negativas salvo que se apruebe explícitamente esa regla de negocio.
- Un movimiento histórico no puede editarse ni borrarse desde la aplicación.
- Una operación fallida no puede dejar actualizado el stock sin su movimiento correspondiente, ni crear un movimiento sin actualizar el stock.
- El superadmin solo obtiene acceso global por la asignación protegida, nunca por cambiar datos del navegador.

## 7. Datos que faltan antes del SQL definitivo

- DDL exacto y completo de las tablas existentes, incluidas restricciones y defaults.
- Estructura real de `inventory_current.items` y ejemplos de `payload` (sin datos personales).
- Dependencias del código sobre claves primarias actuales y nombres de columnas.
- Confirmación de si un usuario puede pertenecer a varias empresas.
- Reglas exactas para stock negativo, unidades, ajustes y anulaciones.
- Método seguro y aprobado para identificar y asignar el primer superadministrador global.

## 8. Estado

- Diseño y plan de migración documentados; pendientes de revisión.
- No se ejecutó SQL.
- No se modificó Supabase DEMO.
- No se modificó Ko'eju de producción ni su Supabase.
- No se abrió ni fusionó un pull request.
- No se publicó en GitHub Pages.

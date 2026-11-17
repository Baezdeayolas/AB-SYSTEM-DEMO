# Etapa 2B — Plan consolidado de corrección de seguridad (V2)

**Proyecto:** AB SYSTEM DEMO (Ko’ẽju como primera empresa)
**Rama:** `work/ab-system-multempresa-ui`
**Estado:** documento de planificación y revisión; NO ejecutar cambios todavía
**Base:** resultados de auditoría de solo lectura compartidos por el usuario

## 1. Alcance, límites y autoridad

- Alcance exclusivo de Supabase DEMO (`druugcvqxxanhtdkqnjd.supabase.co`).
- No modificar Ko’ẽju producción ni su proyecto Supabase.
- Este documento no contiene una migración ejecutable ni autoriza SQL de escritura.
- No ejecutar `GRANT`, `REVOKE`, `ALTER`, `CREATE`, `DROP`, migraciones ni cambios RLS hasta que el script completo sea presentado y aprobado explícitamente.
- Los resultados reflejan el estado observado durante esta auditoría; deben revalidarse inmediatamente antes de cualquier cambio.
- No se han ejecutado cambios en Supabase como parte de esta tarea.

## 2. Resumen ejecutivo

La auditoría confirma que las tres funciones centrales de autorización multiempresa tienen una configuración estática razonable, pero las tablas comerciales todavía conservan políticas y privilegios del modelo anterior de una sola empresa.

Los riesgos prioritarios son:

1. Políticas de lectura `USING (true)` en clientes, productos e inventario.
2. Políticas de pedidos que no validan pertenencia a `company_id`.
3. Privilegios amplios de tabla para `anon` y `authenticated`, incluidos `TRUNCATE`, `TRIGGER` y `REFERENCES`.
4. ACL predeterminadas amplias para objetos futuros en `public`.
5. Funciones heredadas `create_demo_profile()` e `is_demo_admin()` con permisos de ejecución para `anon`; `create_demo_profile()` también para `PUBLIC`.
6. Modelo de inventario actual con un único registro (`id = 1`), incompatible con inventarios separados por empresa.

## 3. Hallazgos de funciones y triggers (bloques A–E y G)

### 3.1 Funciones centrales multiempresa

Se inspeccionaron:

- `public.ab_has_company_access(p_company_id uuid)`
- `public.ab_is_company_admin(p_company_id uuid)`
- `public.ab_is_global_superadmin()`

Las tres son SQL `STABLE SECURITY DEFINER`, pertenecen a `postgres`, tienen `search_path` vacío y conceden `EXECUTE` a `authenticated` y `service_role` (además del propietario). No se observó concesión a `anon` ni a `PUBLIC` en sus ACL efectivas.

Su lógica comprueba empresas activas y membresías activas; `ab_is_company_admin` exige `company_admin`, mientras que las otras reconocen `superadmin_global` según su propósito.

**Pendiente:** pruebas funcionales bajo sesiones/JWT reales, incluidos usuario anónimo, vendedor, administrador de empresa, superadministrador y usuario suspendido. `ab_is_global_superadmin()` no consulta un estado de suspensión de cuenta; si se requiere suspensión global, diseñar ese control explícitamente.

### 3.2 Funciones heredadas

`public.create_demo_profile()`:

- Es `plpgsql SECURITY DEFINER`, propiedad de `postgres`, con `search_path` vacío.
- Inserta `profiles(id, role)` con rol inicial `seller` usando `ON CONFLICT (id) DO NOTHING`.
- Su ACL observada incluye `PUBLIC`, `anon`, `authenticated`, `service_role` y `postgres`.

`public.is_demo_admin()`:

- Es SQL `STABLE SECURITY DEFINER`, propiedad de `postgres`, con `search_path` vacío.
- Comprueba `profiles.id = auth.uid()` y `role = 'admin'`.
- Su ACL observada incluye `anon`, `authenticated`, `service_role` y `postgres`.

Estas funciones heredadas no deben ser la autoridad de autorización multiempresa. Revisar todas sus dependencias y flujos antes de ajustar ACL o reemplazar lógica. La ejecución de una función trigger no debe confundirse con una llamada RPC ordinaria desde el cliente.

### 3.3 Trigger de creación de perfiles

Se confirmó el trigger:

- Tabla: `auth.users`
- Nombre: `on_demo_user_created`
- Evento: `AFTER INSERT`
- Función: `public.create_demo_profile()`

Debe conservarse el alta automática de perfiles o sustituirse por un flujo probado equivalente. No eliminar el trigger ni cambiar su función de forma aislada.

### 3.4 Dependencias y búsqueda textual

- El bloque D no devolvió filas en la consulta de dependencias catalogadas ejecutada. Esto no demuestra ausencia de dependencias dinámicas ni referencias no registradas por PostgreSQL.
- El bloque G corregido encontró cinco funciones con referencias textuales a las tablas/helpers buscados: las tres `ab_*`, `create_demo_profile()` e `is_demo_admin()`.
- La búsqueda textual no es un inventario exhaustivo de consumidores: también deben revisarse frontend, vistas, políticas, triggers, procesos externos y SQL dinámico.

## 4. Hallazgos de políticas RLS (bloque F)

Todas las políticas compartidas eran `PERMISSIVE` y aplicables a `authenticated`.

| Tabla | Política observada | Problema |
|---|---|---|
| `catalog_clients` | `demo_clients_read`, SELECT `USING (true)` | Lectura global entre empresas |
| `catalog_items` | `demo_items_read`, SELECT `USING (true)` | Lectura global entre empresas |
| `inventory_current` | `demo_inventory_read`, SELECT `USING (true)` | Lectura global y modelo de inventario único |
| `catalog_import_rows` | `demo_imports_admin_all`, `is_demo_admin()` | Autoridad heredada, sin `company_id`/aislamiento observado |
| `orders` | SELECT/INSERT/UPDATE/DELETE basados en `owner_id` o `is_demo_admin()` | No valida empresa ni membership activa |
| `profiles` | lectura propia o `is_demo_admin()`; UPDATE admin | Modelo heredado; revisar necesidad de lectura administrativa amplia |
| `seller_assignments` | ALL admin; SELECT propio o admin | Asignaciones heredadas, no vinculadas de forma demostrada a empresa |

Las políticas `PERMISSIVE` se combinan mediante OR. Por tanto, añadir otra política permisiva más estricta no neutraliza una política existente con `USING (true)`. El reemplazo debe retirar o modificar explícitamente las reglas antiguas, después de validar que no se rompe el servicio.

## 5. Hallazgos de privilegios de tablas y valores predeterminados

### 5.1 Privilegios de objetos existentes

La auditoría previa reportó para `anon` y `authenticated` privilegios `DELETE`, `INSERT`, `REFERENCES`, `SELECT`, `TRIGGER`, `TRUNCATE` y `UPDATE` sobre:

- `catalog_clients`
- `catalog_import_rows`
- `catalog_items`
- `inventory_current`
- `orders`
- `seller_assignments`

`service_role` también aparecía con privilegios amplios. La existencia de grants no demuestra por sí sola que todas las operaciones sean exitosas, ya que intervienen RLS, constraints y otros controles. Sin embargo, `TRUNCATE` no está sujeto a RLS y estos grants deben reducirse al mínimo necesario.

En `companies`, `company_memberships` y `global_roles` no se observaron grants para `anon` ni `authenticated` en la consulta agregada compartida; `service_role` sí aparecía.

### 5.2 Privilegios predeterminados

La consulta I previa mostró ACL predeterminadas en `public` para roles creadores `postgres` y `supabase_admin`: grants amplios a `anon`, `authenticated` y `service_role` sobre tablas, secuencias y funciones futuras.

Estos valores predeterminados afectan objetos futuros creados por el rol correspondiente; no modifican retroactivamente objetos existentes. La corrección deberá revisar los `ALTER DEFAULT PRIVILEGES` de cada rol creador, sin revocar indiscriminadamente permisos necesarios.

### 5.3 Secuencias — validación todavía incompleta

El bloque H del inventario terminó con `Success. No rows returned`. Una consulta previa a `information_schema.role_usage_grants` también devolvió cero filas. Estos resultados no prueban que no existan secuencias ni constituyen una inspección concluyente de ACL.

**Acción pendiente antes de diseñar grants:** ejecutar una consulta específica de solo lectura sobre `pg_class`/`pg_namespace` que enumere secuencias de `public`, sus propietarios y `relacl`, y revisar las ACL predeterminadas para secuencias. No inferir inexistencia a partir de resultados vacíos.

## 6. Modelo multiempresa requerido

### 6.1 Empresas y memberships

- `companies` identifica cada empresa y su estado.
- `company_memberships` relaciona usuario, empresa, rol y estado.
- `global_roles` contiene el rol `superadmin_global`, protegido en backend.
- Roles de empresa: `company_admin` y `seller`.
- El selector de empresa del frontend es contexto de interfaz, nunca una autoridad de seguridad.

### 6.2 Pedidos e identidad

Conservar la semántica acordada:

- Pedido creado por vendedor: `owner_id = auth.uid()` y `created_by = auth.uid()`.
- Pedido creado por administrador en nombre de vendedor: `owner_id = UUID real del vendedor seleccionado` y `created_by = auth.uid()` del administrador.
- Vendedor: consulta únicamente pedidos propios de su empresa.
- Administrador de empresa: consulta pedidos de su empresa.
- Superadministrador global: puede consultar todas las empresas.
- El vendedor elegido debe tener membership activa `seller` en la misma empresa; backend/RLS debe validar esa condición.
- No permitir suplantación de `owner_id` por parte del vendedor.
- No conceder lectura de un pedido a un usuario solo porque sea `created_by`; la propiedad se define mediante `owner_id` y el alcance de empresa.

Se requiere `orders.company_id uuid NOT NULL` con FK a `companies`. Incorporar `created_by uuid` con FK a `auth.users`; en backfill histórico puede ser NULL cuando el actor original no sea verificable, pero los pedidos nuevos deben registrar el actor. Conservar el unique existente `(owner_id, legacy_source, legacy_id)` salvo que un análisis de colisiones justifique otro cambio.

### 6.3 Catálogos e inventario

- `catalog_items`, `catalog_clients` y `catalog_import_rows` necesitan alcance de empresa y estrategia de backfill.
- Los códigos de productos y clientes deben ser únicos dentro de cada empresa, no globalmente, si esa es la regla comercial aprobada.
- `inventory_current` hoy está limitado por `id = 1`; requiere rediseño para inventario por empresa y producto.
- Los movimientos de inventario deben ser append-only: empresa, producto, tipo de movimiento, cantidad anterior/nueva, actor, fecha/hora y motivo.
- Entradas, salidas y ajustes deben ser transaccionales. Corregir movimientos mediante un nuevo ajuste, no editar el historial silenciosamente.

## 7. Plan de corrección por fases

### Fase 0 — Cerrar inventario

1. Obtener ACL directa de secuencias existentes.
2. Revalidar grants de tablas, grants por columna, funciones, vistas y ACL predeterminadas.
3. Identificar llamadas del frontend a tablas/RPC y flujos de importación, login, pedidos e inventario.
4. Confirmar qué tareas legítimas requieren `service_role` y asegurar que nunca se exponga en navegador.

**Salida requerida:** matriz objeto × rol × operación, incluyendo secuencias y rutinas.

### Fase 1 — Diseñar privilegios mínimos

1. Definir acceso nulo por defecto para `anon` a datos comerciales privados.
2. Definir grants precisos para `authenticated`; no conceder `TRUNCATE`, `TRIGGER` o `REFERENCES` salvo necesidad demostrada.
3. Reservar `service_role` para backend confiable.
4. Corregir ACL predeterminadas de `postgres` y `supabase_admin` para que objetos nuevos no reciban permisos generales automáticamente.
5. Ajustar EXECUTE de funciones heredadas solo después de revisar trigger, llamadas y dependencias.

**Salida requerida:** script de permisos mínimo con consultas de verificación antes/después y plan de reversión.

### Fase 2 — Migración del esquema comercial

1. Añadir `company_id` a tablas comerciales y definir FKs.
2. Diseñar backfill determinista hacia la empresa Ko’ẽju; detectar filas ambiguas antes de asignarlas.
3. Revisar PK/UNIQUE existentes y posibles colisiones antes de cambiar restricciones.
4. Añadir `created_by` a pedidos y mantener `owner_id`.
5. Rediseñar inventario por empresa/producto y crear historial append-only.
6. Añadir índices por `company_id` y claves de consulta según patrones reales.

**Salida requerida:** migración revisada, consultas de validación de datos y rollback documentado.

### Fase 3 — Sustituir RLS

1. Diseñar políticas por empresa usando las funciones `ab_*` y validaciones específicas de rol.
2. Retirar explícitamente políticas `USING (true)` y políticas heredadas que otorguen acceso global.
3. Pedidos: validar empresa y `owner_id`; para altas por administrador, validar membership activa del vendedor propietario.
4. Catálogos e inventario: limitar lectura/escritura a la empresa autorizada.
5. Separar permisos de `profiles` y membresías para no permitir escalamiento de rol desde el cliente.
6. Revisar funciones `SECURITY DEFINER`, propietario, `search_path`, ACL y validación de identidad.

**Salida requerida:** matriz RLS y pruebas negativas/positivas con al menos dos empresas.

### Fase 4 — Pruebas funcionales

Probar con sesiones reales y JWT distintos:

- usuario anónimo;
- vendedor de empresa A;
- administrador de empresa A;
- usuario de empresa B;
- superadministrador global;
- usuario/membership suspendidos.

Probar SELECT, INSERT, UPDATE y DELETE permitidos y denegados; intentos de falsificar `company_id`, `owner_id`, `created_by` y rol; trigger de alta de usuario; importación; pedidos; cambio de empresa; inventario y concurrencia.

**Criterio de aceptación:** ninguna lectura o escritura entre empresas no autorizada; no hay escalamiento de privilegios; los flujos legítimos siguen funcionando.

### Fase 5 — Frontend DEMO

Solo después de completar esquema, grants, RLS y pruebas se podrá modificar `index.html` y `cloud-sync-demo.js` para memberships, selector de empresa, selector real de vendedores y operaciones multiempresa. Si el esquema no está listo, bloquear guardado multiempresa; no recurrir silenciosamente al modelo legacy.

## 8. Matriz de prioridades

| Prioridad | Hallazgo | Acción | Bloqueante para frontend multiempresa |
|---|---|---|---|
| P0 | `USING (true)` en catálogos e inventario | Reemplazar con políticas por empresa | Sí |
| P0 | Pedidos sin `company_id` ni autorización por empresa | Migrar esquema y RLS | Sí |
| P0 | Grants amplios, incluido `TRUNCATE` | Definir y aplicar mínimo privilegio | Sí |
| P1 | ACL predeterminadas amplias | Corregir defaults por rol creador | Sí |
| P1 | Funciones heredadas con EXECUTE para anon/PUBLIC | Revisar dependencias y ajustar con seguridad | Antes de cierre de seguridad |
| P1 | Inventario con una sola fila | Rediseñar por empresa/producto y movimientos | Sí |
| P2 | Pruebas reales con JWT | Construir matriz de pruebas | Sí |
| P2 | ACL de secuencias no concluyentes | Consulta directa de catálogo | Antes de grants finales |

## 9. Criterios de no-regresión

- No romper el trigger `on_demo_user_created` ni el alta automática de perfiles.
- No cambiar la identidad de pedidos ni la unicidad histórica sin análisis.
- No permitir al vendedor elegir arbitrariamente otro `owner_id`.
- No confiar en `profiles.role` o en valores del navegador para autorizar superadministración.
- Al cambiar empresa, limpiar carrito, cliente, vendedor y estado temporal.
- Mantener datos históricos y precios/payloads de pedidos.
- No activar `FORCE ROW LEVEL SECURITY` de forma indiscriminada; revisar primero funciones y tareas administrativas.
- No tocar producción.

## 10. Estado de aprobación

| Actividad | Estado |
|---|---|
| Inventario de funciones y ACL (A–C) | Revisado |
| Dependencias catalogadas (D) | Sin filas en la consulta ejecutada; no exhaustivo |
| Trigger de alta (E) | Confirmado |
| Políticas RLS (F) | Hallazgos críticos identificados |
| Búsqueda textual de funciones (G) | Cinco funciones identificadas |
| ACL de secuencias (H) | No concluyente; falta consulta directa |
| Grants y ACL predeterminadas de tablas/objetos | Hallazgos previos documentados; revalidar antes de cambios |
| Script de corrección | No preparado |
| Ejecución en Supabase DEMO | No autorizada / no realizada |
| Cambios de frontend multiempresa | Bloqueados hasta backend/RLS y pruebas |

**Este documento es un plan de trabajo. No ejecutar SQL ni realizar cambios en Supabase basándose únicamente en este documento.**
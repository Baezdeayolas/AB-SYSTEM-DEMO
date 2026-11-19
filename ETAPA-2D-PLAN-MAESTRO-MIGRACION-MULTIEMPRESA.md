# Etapa 2D — plan maestro de migración multiempresa (DEMO)

**Estado: DISEÑO CONSOLIDADO PARA REVISIÓN. BLOQUEADO PARA EJECUCIÓN.**

Ámbito exclusivo: repositorio `Baezdeayolas/AB-SYSTEM-DEMO`, rama `work/ab-system-multempresa-ui`, y Supabase DEMO `druugcvqxxanhtdkqnjd.supabase.co`. Ko’ẽju producción, su repositorio y su Supabase quedan fuera de alcance. Este documento no autoriza ejecutar SQL, modificar permisos, publicar ni fusionar ramas.

## 1. Decisión ejecutiva

La auditoría confirma que el backend DEMO todavía utiliza un modelo de una sola empresa. Las tablas comerciales no contienen `company_id`; `inventory_current` está limitado a un único registro (`id = 1`); las políticas legacy permiten lecturas globales de catálogos e inventario; y los privilegios SQL efectivos de `anon` y `authenticated` son amplios en siete tablas legacy. Por tanto, no es seguro habilitar multiempresa con cambios parciales de interfaz o añadiendo políticas nuevas sin retirar coordinadamente las políticas permisivas antiguas.

**Ruta elegida:** completar el diseño de datos y autorización, preparar migración con respaldo y validaciones, ejecutar por lotes pequeños en DEMO con aprobación explícita del SQL completo, probar con usuarios/JWT de cada rol y solo entonces adaptar/habilitar el frontend.

## 2. Evidencia consolidada de la auditoría

### 2.1 Tablas y columnas actuales

| Tabla | Estructura relevante confirmada |
|---|---|
| `catalog_clients` | `code text NOT NULL` PK; `payload jsonb NOT NULL`; `updated_at timestamptz NOT NULL`. Sin `company_id`. |
| `catalog_items` | `code text NOT NULL` PK; `payload jsonb NOT NULL`; `updated_at timestamptz NOT NULL`. Sin `company_id`. |
| `catalog_import_rows` | PK `(import_id, catalog_type, code)`; `payload jsonb`; `created_at timestamptz`. Sin `company_id`. |
| `inventory_current` | PK `id`; CHECK `id = 1`; `items jsonb`; `imported_at`; `imported_by`. Un único inventario global. |
| `orders` | `id`; `owner_id NOT NULL`; `legacy_id NOT NULL`; `legacy_source NOT NULL`; `payload jsonb`; `updated_at`. Sin `company_id` ni `created_by`. |
| `profiles` | `id`; `role` con CHECK legacy `admin/seller`; `seller_label`; `created_at`. |
| `seller_assignments` | PK `user_id`; `seller_label`; `created_at`. Sin `company_id`. |
| `companies` | `id`, `code` único, `name`, `status`, fechas. |
| `company_memberships` | `id`, `company_id`, `user_id`, `role`, `status`, `created_at`; unique `(company_id,user_id)`. |
| `global_roles` | PK `(user_id,role)`; CHECK permite `superadmin_global`. |

### 2.2 Políticas RLS confirmadas

- `catalog_clients`, `catalog_items` e `inventory_current` tienen políticas SELECT para `authenticated` con `USING (true)`: habilitan lectura global de filas.
- Las políticas administrativas legacy de catálogos, importaciones, inventario y asignaciones usan `is_demo_admin()` y no segmentan por empresa.
- `orders` usa `owner_id = auth.uid() OR is_demo_admin()` para SELECT/DELETE/UPDATE e INSERT.
- `profiles` permite lectura propia o admin y actualización administrativa.
- `seller_assignments` permite lectura propia o admin y administración legacy.
- RLS está activo en las tablas inspeccionadas, pero `FORCE ROW LEVEL SECURITY` está desactivado. No activar FORCE indiscriminadamente.
- Las políticas permisivas se combinan mediante OR. Una política nueva de empresa no neutraliza una política antigua `USING (true)`.

### 2.3 Privilegios efectivos y funciones

- `anon` y `authenticated` tienen `DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE` sobre las siete tablas legacy: `catalog_clients`, `catalog_import_rows`, `catalog_items`, `inventory_current`, `orders`, `profiles`, `seller_assignments`.
- `anon` y `authenticated` no mostraron esos privilegios en `companies`, `company_memberships` y `global_roles` en el inventario consultado.
- `TRUNCATE` no está protegido por RLS; su concesión a roles cliente es un riesgo que debe corregirse objeto por objeto y después de identificar consumidores.
- `service_role`, `postgres` y `supabase_admin` mostraron privilegios amplios; no modificarlos mediante revocaciones genéricas.
- Los helpers `ab_is_global_superadmin()`, `ab_has_company_access(uuid)` y `ab_is_company_admin(uuid)` son `SECURITY DEFINER`, `STABLE`, propiedad de `postgres`, con `search_path` vacío; EXECUTE está permitido a `authenticated` y `service_role`, no a `anon`.
- `is_demo_admin()` tiene EXECUTE para `anon` además de otros roles; revisar su retirada individual de `anon` solo cuando se confirme el reemplazo y las dependencias.
- `create_demo_profile()` tiene EXECUTE amplio y es invocada por el trigger `on_demo_user_created` en `auth.users`. No eliminar ni alterar la función o trigger sin probar el alta de usuarios.
- Las ACL predeterminadas para futuros objetos de creadores `postgres` y `supabase_admin` son amplias. Son defaults, no prueba de permisos efectivos actuales. No cambiar defaults de roles gestionados por Supabase sin identificar el impacto.
- El bloque de membresías de roles mostró membresías de `authenticator`, `supabase_realtime_admin` y roles administrativos internos. No modificarlas.

### 2.4 Triggers, vistas, dependencias y restricciones

- Trigger identificado: `auth.users` AFTER INSERT → `public.create_demo_profile()`. Crea perfil `seller` si no existe.
- No se encontraron vistas ni vistas materializadas en `public`; el bloque de dependencias de vistas devolvió `Success. No rows returned`.
- Las claves foráneas de membresías y roles globales apuntan a `companies` y `auth.users`. `orders.owner_id` apunta a `auth.users`.
- No hay FKs desde las tablas comerciales legacy hacia `companies`.
- PK de productos y clientes usa solo `code`, por lo que la unicidad es global.
- PK de importaciones usa `(import_id,catalog_type,code)`.
- `orders` tiene UNIQUE `(owner_id,legacy_source,legacy_id)`; conservar hasta demostrar necesidad y estrategia de reemplazo.
- Todas las restricciones reportadas aparecen validadas.

## 3. Modelo de datos objetivo

### 3.1 Fuente canónica de autorización

- `global_roles`: autoridad exclusiva para `superadmin_global`.
- `company_memberships`: autoridad para rol y estado del usuario dentro de cada empresa (`company_admin` o `seller`).
- `companies.status` y `company_memberships.status` deben estar activos para autorizar operaciones ordinarias.
- `profiles.role` y `seller_assignments` se consideran compatibilidad legacy; no serán fuente de autorización multiempresa.
- El frontend nunca será autoridad: toda consulta y mutación debe quedar validada por RLS y/o funciones backend seguras.

### 3.2 Entidades comerciales

| Tabla | Objetivo |
|---|---|
| `catalog_clients` | Agregar `company_id NOT NULL` con FK a `companies`; unicidad de `(company_id, code)`. |
| `catalog_items` | Agregar `company_id NOT NULL` con FK a `companies`; unicidad de `(company_id, code)`. |
| `catalog_import_rows` | Agregar `company_id NOT NULL` con FK a `companies`; revisar clave única incluyendo empresa e `import_id`. |
| `orders` | Agregar `company_id NOT NULL` con FK a `companies` y `created_by` FK a `auth.users`; conservar `owner_id` como vendedor propietario. |
| `inventory_current` | Reemplazar modelo de fila única por inventario por empresa; no definir el cambio final hasta inspeccionar el JSONB y el proceso de importación. |
| `seller_assignments` | Mantener temporalmente por compatibilidad hasta migrar todos sus consumidores a `company_memberships`; luego evaluar retiro en una etapa separada. |

Para pedidos nuevos, `created_by` debe ser obligatorio mediante un mecanismo de backend/DB validado. Para históricos cuyo actor no pueda demostrarse, permitir `created_by NULL` durante el backfill, documentando esa limitación; no inventar el actor.

### 3.3 Identidad y propiedad de pedidos

- Pedido creado por vendedor: `owner_id = auth.uid()` y `created_by = auth.uid()`.
- Pedido creado por administrador en nombre de vendedor: `owner_id = UUID del vendedor seleccionado` y `created_by = auth.uid()` del administrador.
- El vendedor seleccionado debe tener membership activa `seller` en la misma empresa.
- El vendedor solo puede consultar sus pedidos (`owner_id`). El administrador de empresa puede consultar todos los pedidos de su empresa. El superadministrador global puede operar en contexto global o en una empresa seleccionada, según la política explícita.
- No autorizar lectura solo por `created_by`.
- No aceptar UUID de vendedor arbitrario ni confiar en filtros del navegador.

### 3.4 Inventario

- Inventario separado por empresa.
- Cada movimiento de stock debe registrar empresa, artículo, tipo de movimiento, cantidad anterior/nueva, cantidad de cambio, usuario, fecha/hora y motivo.
- Movimientos append-only; corregir mediante un nuevo ajuste, no editar el historial.
- Escritura de stock transaccional para evitar actualizaciones parciales o carreras.
- No convertir el JSONB actual a filas ni diseñar tablas definitivas hasta inspeccionar datos representativos ficticios/anonimizados y localizar el importador real.

## 4. Plan de migración por fases

### Fase 0 — preparación y respaldo (bloqueante)

1. Confirmar que el trabajo sigue en rama DEMO y que la URL Supabase corresponde al proyecto DEMO.
2. Obtener respaldo exportable de esquema y datos DEMO y comprobar que se puede restaurar en un entorno separado.
3. Registrar conteos de filas, claves, duplicados, tamaños y muestras anonimizadas de JSONB para catálogos, inventario y pedidos.
4. Localizar todos los consumidores: HTML/JS, importadores, Edge Functions, RPC, tareas programadas y scripts externos.
5. No continuar si no hay restauración comprobada o si se detecta un consumidor no inventariado.

### Fase 1 — esquema aditivo y backfill controlado

1. Añadir columnas inicialmente nullable y FK/índices de forma compatible, sin retirar las PK/UNIQUE antiguas.
2. Asignar los datos legacy de Ko’ẽju DEMO a `company_id = c8c4f6bf-a941-48a2-be99-6322b4ac19fd` solo después de verificar conteos y que todos los datos actuales pertenecen a esa empresa.
3. Backfill de `orders.company_id`; no inferir `created_by` cuando no exista evidencia.
4. Definir clave/índice compuesto por empresa y código; comprobar duplicados por empresa antes de imponer restricciones.
5. Migrar inventario por empresa preservando snapshot, importador y auditoría; el formato final depende de inspección del JSONB.
6. Validar conteos, huérfanos, duplicados y consistencia antes de aplicar `NOT NULL`.

### Fase 2 — autorización multiempresa

1. Diseñar políticas por tabla para `superadmin_global`, `company_admin` y `seller`.
2. Sustituir las políticas legacy en una operación coordinada; eliminar explícitamente las políticas SELECT `USING (true)` al activar aislamiento.
3. Mantener políticas separadas para SELECT/INSERT/UPDATE/DELETE, evitando `ALL` cuando no sea necesario.
4. Validar `company_id` contra empresa activa y membership activa.
5. Restringir operaciones administrativas a `ab_is_company_admin(company_id)` y acceso ordinario a `ab_has_company_access(company_id)`, complementando con regla de propiedad para pedidos.
6. Limitar altas/cambios de membership y `global_roles` a un flujo backend autorizado; un usuario no puede elevar su propio rol.
7. Preparar GRANT/REVOKE específicos por objeto y función solo después de cerrar dependencias; retirar TRUNCATE/TRIGGER/REFERENCES de roles cliente donde no sean necesarios.
8. No cambiar ACL predeterminadas de `supabase_admin` ni roles internos.

### Fase 3 — pruebas de seguridad y funcionalidad

Ejecutar con sesiones/JWT reales y datos de dos empresas de prueba:

- Superadmin global: puede seleccionar contexto y consultar lo permitido globalmente.
- Admin empresa A: ve y administra solo empresa A; no puede leer ni modificar empresa B.
- Vendedor A: ve solo sus pedidos y datos permitidos de empresa A; no puede suplantar a otro vendedor.
- Usuario sin membership: no accede a datos comerciales.
- Usuario suspendido o empresa suspendida: acceso denegado según política.
- `anon`: sin acceso a datos privados ni helpers privados.
- Admin crea pedido para vendedor activo de su empresa; se persisten `owner_id` del vendedor y `created_by` del admin.
- Se rechaza vendedor de otra empresa, membership suspendida o empresa incorrecta.
- Se rechaza modificación de `company_id`, `owner_id` o `created_by` para escapar del ámbito permitido.
- Se verifica que no sea posible ejecutar TRUNCATE con roles cliente.
- Se prueba el trigger de alta de usuario y la posterior asignación de membership.
- Se prueba importación e inventario con rollback ante error.

### Fase 4 — adaptación del frontend DEMO

Solo después de aprobar Fase 2 y Fase 3:

1. Resolver membresías y empresas disponibles al iniciar sesión.
2. Añadir selector de empresa para usuarios con más de una empresa; cambiar empresa limpia carrito, cliente, vendedor y estado temporal.
3. Sustituir vendedores hardcodeados por memberships activas `seller` de la empresa.
4. Enviar `company_id` y `created_by` desde el flujo de pedido, pero validarlos en servidor; no confiar en valores del cliente.
5. Filtrar visualmente catálogo, clientes, pedidos e inventario por contexto, manteniendo RLS como control efectivo.
6. Mantener mensajes claros cuando falte contexto o membership: bloquear guardado, sin fallback al modelo legacy.
7. No tocar producción ni publicar durante esta fase.

### Fase 5 — aceptación DEMO

- Todos los casos de prueba pasan.
- Conteos y muestras coinciden con el respaldo y el backfill.
- No hay lectura/escritura cruzada entre empresas.
- No hay permisos excesivos de roles cliente en objetos de negocio.
- Restauración probada y plan de reversión documentado.
- Revisión final del usuario antes de cualquier publicación o despliegue.

## 5. Bloqueos todavía abiertos

1. No se ha demostrado respaldo/restauración de Supabase DEMO.
2. Falta inspeccionar datos JSONB representativos y el importador real de inventario.
3. Falta inventario completo de consumidores fuera del archivo frontend ya revisado.
4. Falta validar políticas/triggers/funciones adicionales de todos los procesos de importación y pedidos.
5. No se han ejecutado pruebas con JWT para los cuatro perfiles de seguridad.
6. No existe todavía SQL de migración y RLS completo aprobado; no debe generarse como un único script ciego.

Estos bloqueos impiden declarar la aplicación multiempresa terminada o segura. El plan permite avanzar de forma ordenada, pero no sustituye las comprobaciones pendientes.

## 6. Reglas de ejecución y aprobación

- Cada lote SQL se entregará completo, con explicación, lista de objetos afectados, preflight, verificaciones posteriores y reversión.
- El usuario revisará y aprobará explícitamente cada script antes de ejecutarlo manualmente en Supabase DEMO.
- No ejecutar SQL desde esta etapa ni afirmar que se ejecutó.
- No aplicar `REVOKE ALL` masivo ni modificar objetos internos gestionados por Supabase.
- No cambiar ni publicar Ko’ẽju producción.
- No abrir/mergear PR, fusionar ramas ni publicar GitHub Pages sin autorización explícita.

## 7. Próxima tarea concreta

Preparar un inventario de consumidores de datos en todo el repositorio DEMO y un paquete de inspección de datos de solo lectura (conteos, duplicados por código, claves legacy y estructura de JSONB sin exponer datos personales). Con esos resultados se podrá redactar el primer lote SQL aditivo y su rollback para revisión. No iniciar el cambio de RLS antes de que el backfill esté verificado.

## 8. Registro de estado

- Auditoría 2C.3 bloques A–G recibida del usuario; los bloques de vistas y dependencias devolvieron `Success. No rows returned`.
- Políticas, columnas, trigger, constraints y privilegios descritos en este documento provienen de resultados compartidos por el usuario durante la auditoría.
- No se han aplicado cambios SQL en Supabase DEMO como parte de esta etapa.
- Documento preparado en rama `work/ab-system-multempresa-ui`; no implica merge ni publicación.
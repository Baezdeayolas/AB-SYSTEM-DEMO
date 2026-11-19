# Etapa 2C.3 — plan de corrección por objeto y dependencias

**Estado: DISEÑO / BLOQUEADO PARA EJECUCIÓN. No contiene SQL ejecutable.**

Ámbito exclusivo: Supabase DEMO y rama `work/ab-system-multempresa-ui`. No modificar Ko’ẽju producción, su Supabase ni publicar.

## 1. Resultado de la inspección del código

Se revisó `cloud-sync-demo.js` en la rama de trabajo. El código actual:
- Consulta `catalog_items` con `select('code,payload')` y `catalog_clients` con `select('code,payload')`.
- Consulta `seller_assignments` filtrando por `user_id`.
- Lee `profiles.role` y acepta únicamente `admin` o `seller`.
- Para el rol `admin`, construye una lista fija de vendedores DEMO; para `seller`, usa `seller_assignments`.
- Lee pedidos con `select('id,legacy_id,legacy_source,payload,updated_at')`.
- Inserta pedidos en `orders` con `owner_id`, `legacy_id`, `legacy_source`, `payload` y `updated_at`.
- No envía `company_id` ni `created_by` al guardar pedidos.
- No contiene selector real de empresa ni resolución de `company_memberships`.

Esto confirma que el frontend todavía opera con el modelo legacy de una sola empresa. La interfaz no está lista para usar el modelo multiempresa y no debe habilitarse mediante cambios aislados de RLS.

## 2. Dependencias por tabla

| Tabla | Dependencia actual observada | Bloqueo antes de endurecer |
|---|---|---|
| `catalog_items` | Lectura directa de `code,payload`; el frontend usa propiedades del payload para catálogo y precios | Definir empresa propietaria de cada fila y migrar consulta a filtro/contexto de empresa validado por RLS |
| `catalog_clients` | Lectura directa de `code,payload`; selector usa propiedades del payload | Igual que catálogo; eliminar lectura global y validar acceso por empresa |
| `catalog_import_rows` | No se encontró referencia en el archivo frontend inspeccionado | Identificar importadores, RPC, funciones, triggers o procesos externos antes de quitar permisos |
| `inventory_current` | El panel de stock mostrado usa el catálogo y stock ficticio (`sc`); no se encontró lectura directa de esta tabla en `cloud-sync-demo.js` | Identificar importador y formato JSONB; no aplicar aún grants/RLS ni cambiar estructura |
| `orders` | Lectura directa y alta desde `cloud-sync-demo.js`; propiedad se asigna a `user.id` | Definir empresa, actor creador, vendedor propietario y backfill; el código actual no cumple la regla de admin que crea para vendedor |
| `profiles` | Lectura del propio perfil; rol decide comportamiento de la interfaz | Mantener lectura propia y evitar que el cliente pueda modificar rol; validar roles por membresías y helper backend |
| `seller_assignments` | Lectura propia; vendedores del admin son hardcodeados | Sustituir lista fija por memberships activas `seller` de la empresa; verificar otros consumidores antes de retirar |
| `companies` | No hay consulta en el código inspeccionado | Implementar contexto de empresa solo después de que RLS y memberships estén validados |
| `company_memberships` | No hay consulta en el código inspeccionado | Convertirla en fuente de membresía y roles por empresa, con políticas específicas |
| `global_roles` | No hay consulta en el código inspeccionado | El superadmin global debe validarse con helper protegido, nunca desde datos enviados por el cliente |

## 3. Orden de corrección recomendado

### 2C.3-A — no tocar todavía ACL heredadas
- No revocar en bloque privilegios de tablas o funciones.
- No cambiar defaults de `postgres` ni `supabase_admin` sin inventario de objetos futuros y rol creador elegido.
- No cambiar permisos de `service_role` ni roles internos de Supabase.
- No alterar el trigger `on_demo_user_created` ni eliminar `create_demo_profile()`.

### 2C.3-B — resolver políticas RLS legacy
- `catalog_clients` y `catalog_items` tienen políticas SELECT permisivas `USING (true)` para `authenticated`; esas políticas permiten lectura global y no pueden coexistir como permisivas con un diseño que pretende aislar empresas.
- Las políticas administrativas legacy usan `is_demo_admin()`. Debe definirse una transición a `ab_is_company_admin(company_id)` y `ab_has_company_access(company_id)` después de añadir `company_id` y validar membresías.
- `orders` debe pasar de `owner_id OR is_demo_admin()` a reglas de empresa y propiedad; preservar la regla de que el vendedor ve solo pedidos propios y el admin de empresa ve los de su empresa.
- `profiles` debe seguir protegiendo el rol. El rol de empresa procede de `company_memberships`; el rol global procede de `global_roles`.
- `seller_assignments` no debe ser fuente de autorización multiempresa una vez que memberships sean la fuente canónica.
- `catalog_import_rows` e `inventory_current` requieren localizar y validar sus procesos de escritura antes de rediseñar sus políticas.

### 2C.3-C — permisos SQL

Solo después de completar la revisión de consumidores:
- `anon`: objetivo sin privilegios de tablas de negocio y sin EXECUTE de helpers privados.
- `authenticated`: privilegios de tabla mínimos para los flujos comprobados; RLS por empresa en todas las operaciones.
- `service_role`: mantener fuera del navegador; no cambiar permisos gestionados por Supabase sin necesidad demostrada.
- `is_demo_admin()`: retirar EXECUTE de `anon` solo después de verificar si alguna ruta pública lo necesita; las políticas actuales lo usan en contexto autenticado.
- `create_demo_profile()`: no revocar ni modificar sin comprobar el comportamiento del trigger de alta de usuarios y su ejecución efectiva.
- Helpers `ab_*`: mantener EXECUTE para `authenticated` y `service_role` según uso, sin conceder a `anon`; probar antes y después con JWT.
- `TRUNCATE`, `TRIGGER` y `REFERENCES`: no conceder a `anon` ni `authenticated` en tablas de negocio salvo justificación extraordinaria y documentada.

### 2C.3-D — migración multiempresa y aplicación
- Añadir `company_id` a entidades comerciales según el diseño aprobado, con backfill de la empresa DEMO existente.
- Añadir `created_by` a pedidos y preservar `owner_id` como propietario/vendedor responsable.
- El admin debe seleccionar un vendedor desde memberships activas `seller` de su empresa; no usar UUID libre ni lista fija.
- Un pedido de vendedor debe registrar `owner_id = auth.uid()` y `created_by = auth.uid()`.
- Un pedido creado por admin para vendedor debe registrar `owner_id = UUID del vendedor elegido` y `created_by = auth.uid()` del admin.
- Validar en backend/RLS que el vendedor elegido tenga membership activa en la misma empresa.
- Añadir índices por `company_id` y revisar unicidad de códigos por empresa; revisar constraint actual de pedidos antes de alterarlo.
- Cambiar lecturas/escrituras frontend solo después de que el esquema y RLS estén listos. No confiar en filtros del navegador como control de seguridad.

## 4. Bloqueos que impiden un script seguro

1. No se ha completado la búsqueda de todas las referencias en archivos frontend, procesos de importación, Edge Functions, vistas, triggers y RPC.
2. No se han recibido definiciones completas de todas las políticas, triggers y funciones que consumen las tablas legacy.
3. No se ha inspeccionado la forma real de los JSONB con un conjunto representativo de datos ficticios.
4. No se ha definido el proceso de importación de inventario ni su atomicidad.
5. No se han ejecutado pruebas JWT para superadmin, admin de empresa, vendedor y usuario sin membresía.
6. No existe evidencia de un respaldo/restauración probado de Supabase DEMO.

Por estos bloqueos no es seguro generar ni ejecutar un `REVOKE`/`GRANT` definitivo todavía.

## 5. Pruebas obligatorias antes de aprobar cambios

- Inicio de sesión como admin y seller de DEMO.
- Lectura de catálogo/clientes sin acceso a datos de otra empresa.
- Lectura de pedidos: seller solo propios; admin de empresa todos los de su empresa.
- Alta de pedido por vendedor y alta por admin en nombre de vendedor.
- Rechazo de `company_id` ajeno y vendedor sin membership activa.
- Rechazo de autoasignación de `company_admin` o `superadmin_global`.
- Comprobación de que `anon` no puede leer/escribir tablas privadas ni invocar helpers privados.
- Comprobación de que no se puede ejecutar TRUNCATE como `anon`/`authenticated`.
- Prueba del trigger de creación de perfil tras alta de usuario.
- Pruebas de inventario/importación y restauración desde respaldo.

## 6. Próxima acción concreta

El siguiente trabajo seguro es completar un inventario de consumidores en todo el repositorio y recopilar las definiciones de políticas, triggers y funciones que afectan a las siete tablas legacy. Con esa evidencia se prepara un paquete de cambios dividido por tabla, cada uno con preflight, script exacto, verificación posterior y reversión.

**No ejecutar cambios SQL con este documento.** La aprobación debe ser posterior a la entrega del script completo y de la lista exacta de objetos afectados.
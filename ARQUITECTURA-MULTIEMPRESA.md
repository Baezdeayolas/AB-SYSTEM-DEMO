# Arquitectura objetivo — AB SYSTEM multiempresa

Estado: diseño técnico preparado a partir del esquema y las políticas inspeccionadas en Supabase DEMO. **No es una migración ejecutada ni una certificación completa de seguridad.**

## 1. Alcance y límites

- Una sola aplicación AB SYSTEM servirá a varias empresas.
- La cuenta propietaria tendrá el rol de Superadministrador global y podrá operar en todas las empresas.
- Cada empresa tendrá administradores, vendedores y datos independientes.
- Esta especificación aplica exclusivamente a `AB-SYSTEM-DEMO` y su proyecto Supabase DEMO.
- Ko'eju de producción, su repositorio, su proyecto Supabase y sus datos quedan expresamente fuera de alcance.
- No se deben copiar usuarios, clientes, vendedores, pedidos, credenciales ni secretos de producción a DEMO.
- Este documento no autoriza ejecutar SQL, alterar tablas, cambiar políticas ni publicar. Esas acciones requieren revisión y autorización separada.

## 2. Roles y alcance funcional

| Rol | Alcance previsto |
| --- | --- |
| `superadmin_global` | Todas las empresas; crear, suspender y administrar empresas, membresías y configuración global. |
| `company_admin` | Una empresa; administrar sus usuarios y operaciones, sin acceso a otras empresas. |
| `seller` | Una empresa; operar pedidos y consultar únicamente los datos y asignaciones autorizados. |

El rol global no debe residir en un campo editable desde el navegador ni depender del `profiles.role` actual. La autorización global debe comprobarse en el backend con una asignación protegida y políticas RLS explícitas.

## 3. Esquema DEMO observado

La consulta de metadatos compartida mostró estas tablas y columnas:

| Tabla | Columnas observadas |
| --- | --- |
| `profiles` | `id uuid`, `role text`, `seller_label text`, `created_at timestamptz` |
| `seller_assignments` | `user_id uuid`, `seller_label text`, `created_at timestamptz` |
| `catalog_items` | `code text`, `payload jsonb`, `updated_at timestamptz` |
| `catalog_clients` | `code text`, `payload jsonb`, `updated_at timestamptz` |
| `catalog_import_rows` | `import_id text`, `catalog_type text`, `code text`, `payload jsonb`, `created_at timestamptz` |
| `inventory_current` | `id integer`, `items jsonb`, `imported_at timestamptz`, `imported_by uuid` |
| `orders` | `id uuid`, `owner_id uuid`, `legacy_id text`, `legacy_source text`, `payload jsonb`, `updated_at timestamptz` |

Esta lista describe las columnas observadas; no confirma claves primarias, índices, restricciones únicas, claves foráneas, valores por defecto, triggers ni todas las funciones. Esos elementos deben inspeccionarse antes de redactar SQL ejecutable.

### Hallazgos de RLS y políticas observadas

- RLS aparece activado en las siete tablas consultadas; `relforcerowsecurity` aparece como `false` en todas.
- `orders`: SELECT, UPDATE y DELETE se limitan a `owner_id = auth.uid()` o a `is_demo_admin()`; INSERT valida esa misma condición con `WITH CHECK`.
- `profiles`: SELECT permite el perfil propio o el acceso administrativo; UPDATE exige `is_demo_admin()` tanto en `USING` como en `WITH CHECK`.
- `seller_assignments`: lectura propia o administrativa; gestión completa mediante la política administrativa.
- `catalog_items`, `catalog_clients` e `inventory_current`: lectura para cualquier usuario autenticado; escritura administrativa según las políticas mostradas.
- `catalog_import_rows`: política de gestión administrativa.
- La función `public.is_demo_admin()` es SQL, `STABLE`, `SECURITY DEFINER`, con `search_path = ''`; consulta `profiles` para comprobar `role = 'admin'` del usuario de `auth.uid()`.
- Se observó permiso EXECUTE de `is_demo_admin()` para `anon`, `authenticated`, `postgres` y `service_role`.
- En `profiles`, los grants consultados muestran permisos SQL amplios para `anon`, `authenticated` y `service_role`, además de permisos administrativos para `postgres`. Los grants no sustituyen a RLS; deben revisarse y reducirse al mínimo necesario en una fase separada.
- Las políticas mostradas no ofrecen a un usuario ordinario una política de UPDATE sobre perfiles. Aun así, no se debe concluir que toda la superficie de modificación de roles está auditada: faltan triggers, otras funciones, privilegios efectivos heredados y flujos administrativos.

### Consecuencias para el diseño

1. El catálogo y el inventario son actualmente compartidos entre usuarios autenticados; esto no satisface el aislamiento multiempresa.
2. Las tablas comerciales observadas todavía no contienen `company_id`.
3. `orders.owner_id` identifica al propietario del pedido, pero no reemplaza una pertenencia explícita a empresa.
4. `inventory_current` almacena un documento JSONB con un identificador entero; se debe decidir cómo separar inventarios por empresa sin asumir que la estructura actual soporta varias filas.
5. `profiles.role` y `is_demo_admin()` representan el modelo administrativo actual de una sola DEMO. No deben reutilizarse sin adaptación como autoridad global.

## 4. Modelo de datos objetivo

Tablas nuevas propuestas:

### `companies`
- Identificador estable.
- Nombre visible y código único.
- Estado (activa/suspendida).
- Fechas de creación y actualización.
- Metadatos operativos no sensibles.

### `global_roles`
- Relación entre usuario y rol global.
- El rol `superadmin_global` se asigna solo mediante un proceso confiable de backend/migración administrativa.
- Ninguna política o pantalla permite que un usuario se autoasigne este rol.
- Escrituras restringidas a un proceso privilegiado y auditado.

### `company_memberships`
- Identificador de membresía.
- `company_id` y `user_id`.
- Rol dentro de la empresa: `company_admin` o `seller`.
- Estado de la membresía y fechas.
- Restricción única para evitar membresías duplicadas del mismo usuario en la misma empresa.

Cambios previstos en entidades existentes:

- Añadir `company_id` obligatorio a `orders`, `catalog_items`, `catalog_clients`, `catalog_import_rows` y a la estructura de inventario que se apruebe.
- Vincular `seller_assignments` a una empresa y validar que el usuario tenga membresía en ella.
- Mantener `profiles` como datos de perfil/autenticación, no como fuente de autoridad global.
- Evaluar si `inventory_current` se convierte en una tabla con una fila por empresa o si se normaliza en registros de inventario por artículo y empresa. La decisión depende de los usos reales del JSONB y del código de importación.

Los nombres y columnas son el modelo objetivo, no una orden para ejecutar DDL. Antes de migrar deben verificarse constraints, índices, triggers, funciones, vistas, dependencias y formatos reales de `payload`.

## 5. Reglas de autorización y aislamiento

1. Toda fila comercial pertenece exactamente a una empresa.
2. La empresa activa seleccionada en la interfaz es solo contexto visual; no constituye autorización.
3. El backend valida que el usuario tenga membresía activa en la empresa solicitada.
4. Las políticas RLS validan `company_id` en SELECT, INSERT, UPDATE y DELETE.
5. Un `company_admin` solo administra la empresa de su membresía.
6. Un `seller` solo opera dentro de su empresa y según las asignaciones permitidas.
7. Un `superadmin_global` accede a varias empresas mediante una comprobación global explícita, protegida y auditada.
8. Las funciones `SECURITY DEFINER` deben usar un `search_path` seguro, nombres de objetos calificados, permisos EXECUTE mínimos y revisión de propietario.
9. Las funciones auxiliares de RLS deben evitar recursión de políticas y no confiar en valores de rol o empresa enviados libremente por el navegador.
10. No colocar claves `service_role`, contraseñas ni secretos en archivos frontend.
11. Las operaciones de cambio de empresa, alta de usuarios, cambio de roles y suspensión deben quedar registradas en una bitácora apropiada.
12. Considerar `FORCE ROW LEVEL SECURITY` cuando corresponda, entendiendo sus efectos sobre propietarios, migraciones y procesos privilegiados; no activarlo indiscriminadamente.

## 6. Migración propuesta por fases

### Fase 0 — completar inventario técnico
- Inspeccionar claves primarias, índices, constraints, defaults, triggers, vistas y funciones.
- Inspeccionar grants efectivos y propietarios de tablas/funciones.
- Revisar el formato de `payload` de pedidos, artículos, clientes e inventario usando solo datos ficticios DEMO.
- Identificar todos los lugares del frontend/backend que leen o escriben las siete tablas.
- Confirmar cómo se crean perfiles y cómo se asignan los roles actuales.

### Fase 1 — preparar migración reversible
- Crear un plan de respaldo y reversión específico de DEMO.
- Crear `companies`, `global_roles` y `company_memberships`.
- Crear una empresa inicial DEMO y membresías de prueba.
- Añadir `company_id` inicialmente nullable donde sea necesario.
- Asignar los registros DEMO existentes a la empresa inicial.
- Verificar conteos, relaciones y ausencia de registros sin empresa.
- Solo después de validar, aplicar NOT NULL, constraints e índices apropiados.

### Fase 2 — políticas RLS
- Implementar helpers de autorización revisados para membresía y rol global.
- Aplicar políticas por operación y tabla.
- Reducir grants a los mínimos necesarios y revisar EXECUTE de funciones.
- Probar las políticas con sesiones reales de los roles de prueba.
- No depender de que la interfaz filtre filas.

### Fase 3 — aplicación
- Añadir selector de empresa solo para usuarios con más de una membresía o superadmin.
- Mostrar empresa activa de forma clara.
- Cargar y guardar datos con el contexto autorizado.
- Mantener el diseño visual y navegación de la matriz Ko'eju.
- Evitar que un cambio de empresa conserve accidentalmente el carrito, cliente o datos de la empresa anterior.

### Fase 4 — validación y publicación
- Probar dos empresas ficticias, un superadmin global, dos administradores y vendedores de cada empresa.
- Ejecutar pruebas negativas de lectura y escritura cruzadas.
- Probar pedidos, catálogo, clientes, inventario, importaciones y asignaciones.
- Verificar login, recarga, sesión expirada y cambio de empresa.
- Revisar móvil y escritorio.
- Publicar solo después de aprobación expresa y validación satisfactoria.

## 7. Matriz mínima de pruebas de aislamiento

| Actor | Empresa A | Empresa B |
| --- | --- | --- |
| Superadmin global | Leer y administrar según permiso global | Leer y administrar según permiso global |
| Admin A | Administrar | Denegado |
| Vendedor A | Operar según asignación | Denegado |
| Admin B | Denegado | Administrar |
| Vendedor B | Denegado | Operar según asignación |
| Usuario sin membresía | Denegado | Denegado |

Pruebas negativas obligatorias:
- Cambiar manualmente el `company_id` en una petición.
- Intentar leer identificadores conocidos de otra empresa.
- Intentar INSERT/UPDATE asignando otra empresa.
- Intentar cambiar el propio rol o crear una membresía privilegiada.
- Intentar ejecutar funciones administrativas con sesión anónima o usuario ordinario.
- Confirmar que el superadmin global obtiene acceso solo mediante su asignación protegida.

## 8. Riesgos y decisiones pendientes

- No se ha inspeccionado el SQL completo de constraints, triggers, índices, vistas ni todas las funciones.
- No se han probado sesiones reales de cada rol ni ataques de acceso cruzado.
- No se ha confirmado la estructura interna de los JSONB ni las dependencias del inventario.
- Los grants amplios observados y el EXECUTE de `anon` en `is_demo_admin()` requieren una revisión de mínimo privilegio; no se deben revocar a ciegas sin comprobar dependencias.
- La condición `rls_forced = false` no demuestra por sí sola una falla; deben revisarse propietarios y roles que pueden omitir RLS.
- El estado de GitHub Pages y el funcionamiento integral de la aplicación siguen pendientes de pruebas.

## 9. Criterios de aceptación

- Una sola aplicación y una interfaz coherente con Ko'eju.
- Cada empresa tiene datos y usuarios aislados.
- La autorización está aplicada en backend/RLS, no solo en frontend.
- El superadmin global está protegido contra autoasignación y escalamiento de privilegios.
- Las pruebas negativas de acceso cruzado fallan de forma segura.
- Las operaciones principales funcionan con datos ficticios DEMO.
- Hay plan de reversión probado.
- No se modifica producción ni se publican cambios sin aprobación explícita.

## 10. Estado actual

- Este documento es el diseño de referencia para la próxima etapa.
- No se ejecutó ninguna migración SQL.
- No se modificó el proyecto Supabase DEMO.
- No se modificó Ko'eju de producción ni su Supabase.
- La implementación multiempresa, las pruebas de aislamiento y la publicación siguen pendientes.

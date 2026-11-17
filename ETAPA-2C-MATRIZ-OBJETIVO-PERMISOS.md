# Etapa 2C.2 — matriz objetivo de permisos (DEMO)

**Estado: DISEÑO PARA REVISIÓN. No ejecutar SQL.**

Ámbito exclusivo: Supabase DEMO (`druugcvqxxanhtdkqnjd.supabase.co`), rama `work/ab-system-multempresa-ui`. Esta matriz define el objetivo funcional; no autoriza `GRANT`, `REVOKE`, cambios de RLS ni migraciones. Ko’ẽju producción queda fuera de alcance.

## 1. Principios

1. Los privilegios SQL habilitan operaciones sobre objetos; RLS limita filas. Se necesitan ambas capas.
2. Las políticas permisivas se combinan mediante OR. Añadir una política nueva no neutraliza una política permisiva antigua como `USING (true)`.
3. `TRUNCATE` no está protegido por RLS. No debe concederse a roles de usuario de la aplicación.
4. `service_role` es exclusivamente backend confiable. Su clave nunca debe estar en navegador, aplicación móvil ni repositorio.
5. No se revocan privilegios de `postgres`, `supabase_admin` ni roles internos administrados por Supabase sin identificar antes su función y dependencia.
6. Las ACL predeterminadas se revisan por separado de los privilegios efectivos de objetos existentes.

## 2. Matriz objetivo por rol

| Rol | Esquema `public` | Tablas de negocio | Funciones de aplicación | Restricciones |
|---|---|---|---|---|
| `anon` | `USAGE` solo si una ruta pública documentada lo requiere; sin `CREATE` | Sin acceso a datos privados. Solo lectura pública explícita si el producto la incorpora y revisa | Sin `EXECUTE` en helpers privados ni funciones `SECURITY DEFINER`; excepción solo documentada | Sin `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES` ni `TRIGGER` |
| `authenticated` | `USAGE`; sin `CREATE` | Solo `SELECT`/`INSERT`/`UPDATE`/`DELETE` que requiera cada flujo y que esté protegido por RLS; no conceder privilegios por comodidad | `EXECUTE` únicamente en RPC/helpers requeridos por el cliente autenticado | Sin `TRUNCATE`, `TRIGGER` ni `CREATE`; no acceso cruzado entre empresas |
| `service_role` | Mantener los permisos requeridos por Supabase y los procesos backend | Acceso backend según necesidad operativa; no usarlo desde cliente | Solo procesos backend que lo requieran | Clave secreta fuera del cliente; auditar cada uso que omita RLS |
| `postgres` | Mantener administración | Mantener propiedad y administración | Mantener administración | No modificar como parte de una limpieza genérica |
| `supabase_admin` y roles internos | Mantener permisos administrados por Supabase | No alterar sin identificar dependencias | No alterar sin identificar dependencias | No aplicar cambios masivos a roles gestionados |

**Nota:** `USAGE` en `public` no concede por sí mismo acceso a filas. Los privilegios de tabla y las políticas RLS deben evaluarse conjuntamente.

## 3. Objetivo por objeto existente

| Objeto | `anon` | `authenticated` | Requisito RLS/funcional |
|---|---|---|---|
| `catalog_clients` | Sin acceso | Lectura y escrituras solo según flujo autorizado | Eliminar la lectura global `USING (true)`; acceso por empresa y rol cuando exista `company_id` |
| `catalog_items` | Sin acceso | Lectura y escrituras solo según flujo autorizado | Eliminar la lectura global `USING (true)`; catálogo aislado por empresa |
| `catalog_import_rows` | Sin acceso | Sin acceso directo salvo que un flujo autenticado lo necesite | Operaciones de importación restringidas a administradores autorizados |
| `inventory_current` | Sin acceso | Lectura/escritura solo mediante flujo autorizado | Inventario separado por empresa; cambios transaccionales y auditables |
| `orders` | Sin acceso | CRUD limitado por propiedad/empresa y reglas de rol | Vendedor ve sus pedidos; admin de empresa ve los de su empresa; superadmin global según contexto |
| `profiles` | Sin acceso | Lectura del propio perfil; modificación solo por flujo administrativo autorizado | No permitir que un usuario cambie su propio rol |
| `seller_assignments` | Sin acceso | Lectura propia si sigue siendo necesaria; administración restringida | Revisar si se reemplaza por `company_memberships` como fuente de asignación |
| `companies` | Sin acceso | Lectura de empresas a las que el usuario tiene acceso, según diseño RLS | No permitir que un usuario se agregue a una empresa |
| `company_memberships` | Sin acceso | Lectura limitada a membresías propias y a administración de la empresa | Altas/cambios de membresía mediante flujo administrativo validado |
| `global_roles` | Sin acceso | Lectura solo mediante helper seguro si es imprescindible; sin escritura directa | Solo proceso administrativo controlado puede asignar `superadmin_global` |

Esta tabla es una guía de diseño, no una orden para conceder todos los verbos indicados. Para cada tabla se debe confirmar el flujo real, las columnas, las políticas y las dependencias antes de generar SQL.

## 4. Funciones identificadas

| Función | `anon` | `authenticated` | Tratamiento propuesto |
|---|---|---|---|
| `ab_is_global_superadmin()` | No | Sí | Mantener `EXECUTE` autenticado; comprobar llamadas reales y mantener `search_path` seguro |
| `ab_has_company_access(uuid)` | No | Sí | Mantener `EXECUTE` autenticado; validar empresa activa y membresía activa |
| `ab_is_company_admin(uuid)` | No | Sí | Mantener `EXECUTE` autenticado; validar rol y empresa activa |
| `is_demo_admin()` | No | Solo si las políticas/flujo legacy todavía lo requieren | Revisar sustitución gradual por autorización multiempresa; no revocar hasta confirmar dependencias |
| `create_demo_profile()` | No invocable directamente | No invocable directamente salvo necesidad probada | Es función de trigger `AFTER INSERT auth.users`; preservar trigger y comprobar que la ejecución del trigger siga funcionando antes de cualquier cambio ACL |

Las funciones `SECURITY DEFINER` deben conservar `search_path` seguro, referencias calificadas y propietario controlado. La reducción de `EXECUTE` se hará individualmente, nunca con un `REVOKE` global.

## 5. ACL predeterminadas

El inventario mostró defaults amplios para creadores `postgres` y `supabase_admin`: funciones con `EXECUTE` para `anon`/`authenticated`, secuencias con `SELECT`/`UPDATE`/`USAGE` y tablas con privilegios amplios, incluido `TRUNCATE`.

Objetivo de diseño:
- Para objetos nuevos de negocio creados por roles de migración controlados: no conceder automáticamente privilegios de escritura a `anon`.
- Para `authenticated`: conceder solo los privilegios mínimos requeridos por la aplicación y complementar con RLS.
- Para funciones: no conceder `EXECUTE` público por defecto cuando no sea necesario.
- Para secuencias: no conceder acceso a roles de cliente salvo que una secuencia concreta y un flujo legítimo lo requieran.
- No alterar defaults de `supabase_admin` hasta identificar qué objetos administra y cómo Supabase depende de ellos.

Antes de preparar SQL se debe decidir qué rol será el creador de objetos de aplicación y aplicar defaults solo a ese creador y a objetos dentro del alcance.

## 6. Dependencias y decisiones pendientes

1. Confirmar desde el código de la aplicación qué tablas y operaciones usa cada pantalla y proceso.
2. Identificar si `seller_assignments` sigue en uso o puede quedar como compatibilidad temporal.
3. Revisar las políticas RLS actuales y diseñar reemplazos; las políticas antiguas permisivas deben retirarse o hacerse restrictivas en un cambio coordinado.
4. Definir la estrategia de migración de datos a `company_id` antes de restringir `orders` y catálogos.
5. Probar con JWT reales: superadmin global, admin de empresa, vendedor y usuario autenticado sin membresía.
6. Verificar el trigger de `auth.users` y el flujo de creación de perfiles antes de tocar ACL de `create_demo_profile()`.

## 7. Siguiente entregable

Preparar un documento de corrección por objeto y un SQL de previsualización/validación. El SQL de cambio se entregará completo, con explicación de cada sentencia y lista de objetos afectados, y requerirá aprobación explícita antes de ejecutarse manualmente en Supabase DEMO.

## 8. Registro de evidencia

- Bloques A–E del inventario 2C ejecutados manualmente por el usuario.
- `public_sequence_count = 0`.
- `anon` y `authenticated` tienen privilegios amplios sobre las siete tablas legacy inventariadas, incluido `TRUNCATE`; RLS está activo, pero no protege `TRUNCATE`.
- `companies`, `company_memberships` y `global_roles` no muestran privilegios para `anon` ni `authenticated` en las comprobaciones realizadas.
- No se han aplicado correcciones de permisos.
- Las membresías de `authenticator` y `supabase_realtime_admin` se consideran internas; no se propone modificarlas.

---

**Advertencia:** el resultado de la auditoría no basta para aplicar cambios de forma segura. Esta matriz debe contrastarse con el código y las dependencias de la aplicación antes de generar el script ejecutable.
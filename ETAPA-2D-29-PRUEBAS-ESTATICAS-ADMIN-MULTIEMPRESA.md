# ETAPA 2D-29 — Pruebas estáticas y administración de membresías

**Rama:** `work/adaptacion-multiempresa-v1`
**Entorno:** exclusivamente AB-SYSTEM-DEMO.
**Estado:** revisión estática realizada; GitHub Actions release candidate aprobado; pruebas reales de Supabase pendientes.

## Cambios adicionales

- Se agregó la acción para quitar un usuario de una empresa sin eliminar su cuenta de autenticación. Así podrá conservar acceso a otras empresas.
- Se impide quitar o degradar al último administrador activo de una empresa.
- Las invitaciones ya no sobrescriben el rol global existente del perfil cuando un usuario pertenece a más de una empresa.
- La asignación de membresías de una invitación se realiza en el servidor después de validar al superadministrador global.
- La interfaz aclara que suspender/reactivar empresas conserva el historial.

## Pruebas incorporadas

Se añadieron:
- `tests/admin-users-guards.test.mjs`: verificaciones de regresión para autorización global, validación de empresa, estados permitidos, retiro de membresías, protección del último administrador y preservación de perfiles.
- `.github/workflows/validate-admin.yml`: ejecuta `node --check`, los tests de Node y `deno check` de la Edge Function al actualizar la rama o abrir un PR hacia main.
- `tests/sql-inventory-migration.test.mjs`: comprueba que 2D-21 no recrea el inventario legacy, que 2D-22 usa las tablas/RPC por depósito y que ambos borradores terminan en `ROLLBACK`.
- `.github/workflows/validate-release-candidate.yml`: ejecuta los controles de integración y el test de seguridad de las migraciones.

## Comprobaciones realizadas durante esta revisión

- El archivo frontend `cloud-sync-demo.js` pasó la comprobación de sintaxis JavaScript con el motor V8.
- Pasaron 14 comprobaciones estáticas sobre los guardas y las conexiones frontend/backend de administración.
- Se revisaron los bloques de creación, suspensión/reactivación, invitación, cambio de rol/estado y retiro de membresía.
- Después de cambiar o retirar una membresía, el catálogo de vendedores de la empresa activa se vuelve a cargar para evitar que quede visible un vendedor que ya perdió acceso.
- No se realizó ninguna operación de escritura en Supabase ni se eliminó ningún usuario o empresa.

## Límites importantes

- Las comprobaciones estáticas no sustituyen una ejecución de GitHub Actions ni una prueba de integración contra Supabase.
- GitHub Actions workflow `Validate AB SYSTEM release candidate`, ejecución #124, terminó con `success`: sintaxis JS, `deno check`, existencia de migración y wiring frontend/backend. La nueva suite de regresión SQL se ejecutó en GitHub Actions y pasó correctamente en la ejecución #125 (release candidate) y en la ejecución de administración correspondiente. Los tests son estáticos: no ejecutan el SQL contra PostgreSQL ni sustituyen las pruebas reales de RLS/JWT.
- La Edge Function necesita desplegarse en el proyecto DEMO antes de que la interfaz administrativa funcione en el sitio publicado.
- No existe todavía una migración aplicada y verificada de la base multiempresa; el README conserva las advertencias sobre 2D-21/2D-22 y respaldo restaurable.
- La empresa con datos no se debe borrar físicamente. Se suspende para conservar pedidos, productos y movimientos.
- Quitar una membresía no borra la cuenta Auth; solo retira su pertenencia a esa empresa.

## No realizado

- No se fusionó la rama a `main`.
- No se publicó la aplicación.
- No se desplegó la Edge Function.
- No se ejecutó SQL ni se copiaron datos.
- Ko’ẽju producción permanece intacto.

## Estado de publicación en GitHub

La rama fue reconciliada mediante un commit de merge con `main`: comparación actual `ahead 266 / behind 0`, PR #2 reporta `mergeable=true`. El PR sigue en borrador y no se fusionó. La migración de inventario se separó de la migración base. 2D-21 ya no crea tablas legacy `inventory_balances`/`inventory_movements`; 2D-22 valida la estructura base y las tablas por depósito, y permanece en `ROLLBACK`. GitHub Actions release candidate #141 y el workflow de administración #28 terminaron en `success` sobre el mismo commit `ccbc1522ea087caa90b49e818c23342196cb24aa`. Falta probar PostgreSQL real, RLS/JWT, desplegar `admin-users` y verificar el superadministrador.

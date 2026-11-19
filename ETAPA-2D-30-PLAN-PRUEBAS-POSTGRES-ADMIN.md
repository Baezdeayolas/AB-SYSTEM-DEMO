# ETAPA 2D-30 — Plan de pruebas PostgreSQL para protecciones administrativas

**Estado:** plan de integración pendiente. No ejecutar contra Supabase AB-SYSTEM-DEMO ni Ko'eju producción.
**Entorno requerido:** restauración aislada y verificable de AB-SYSTEM-DEMO, sin conexiones de usuarios reales.
**Parche relacionado:** `sql/ETAPA-2D-29-PROTECCION-ULTIMO-ADMIN-Y-EMPRESAS-DRAFT.sql`.

## Alcance

Validar comportamiento real de los triggers de PostgreSQL. Las pruebas Node del repositorio son estáticas: verifican que el borrador contenga las guardas previstas, pero no ejecutan SQL ni demuestran el comportamiento de PostgreSQL, RLS o concurrencia.

## Preparación obligatoria

1. Crear una restauración aislada de la base DEMO y verificar que puede restaurarse.
2. Usar una empresa de prueba dedicada y usuarios Auth sintéticos, nunca usuarios reales.
3. Crear dos membresías `company_admin` activas en esa empresa y al menos un vendedor.
4. Confirmar que existe `trg_company_memberships_guard_identity`.
5. Ejecutar el parche únicamente en esa restauración, después de revisar el preflight y cambiar temporalmente el cierre a `ROLLBACK` para el ensayo.
6. Registrar SQLSTATE, resultado y conteos antes/después de cada caso.

## Casos de regresión

| Caso | Operación | Resultado esperado |
|---|---|---|
| A | Eliminar el único administrador activo | Rechazado con SQLSTATE `23514` |
| B | Suspender al único administrador activo | Rechazado con SQLSTATE `23514` |
| C | Cambiar el rol del único administrador activo a `seller` | Rechazado con SQLSTATE `23514` |
| D | Retirar uno de dos administradores activos | Permitido; queda exactamente uno activo |
| E | Retirar después al administrador restante | Rechazado con SQLSTATE `23514` |
| F | Degradar o suspender ambos administradores en una sola sentencia | La sentencia completa se revierte; queda al menos uno activo |
| G | Dos sesiones concurrentes intentan retirar cada una un administrador distinto | No pueden confirmar ambas; la empresa conserva al menos uno activo |
| H | Eliminar una empresa con rol autenticado o privilegiado | Rechazado con SQLSTATE `55000` |
| I | Ejecutar TRUNCATE sobre companies | Rechazado con SQLSTATE `55000` |
| J | Suspender una empresa mediante UPDATE de status | Permitido; se conservan empresa, membresías y datos vinculados |

## Comprobaciones de integridad posteriores

- Comparar conteos de empresas, membresías, productos, clientes, pedidos e inventario antes/después.
- Confirmar que no se modificó `company_id` ni `user_id` de membresías.
- Confirmar que no se borraron empresas ni filas comerciales.
- Verificar que la política RLS sigue limitando cada usuario a su empresa.
- Repetir A–J después de restaurar la base de prueba para demostrar que el resultado es reproducible.

## Bloqueo conocido antes de aplicar

La auditoría encontró que `DEMO2` no tiene un `company_admin` activo. El preflight del parche abortará mientras exista alguna empresa sin administrador activo. Primero se debe asignar un administrador autorizado a DEMO2 y volver a verificar el inventario de membresías.

## Criterio de aprobación

No aprobar ni convertir el borrador en migración aplicable hasta que todos los casos A–J pasen en una restauración aislada, se verifique la integridad de datos y se revise el comportamiento de los triggers con la versión real de PostgreSQL 17 usada por el proyecto.

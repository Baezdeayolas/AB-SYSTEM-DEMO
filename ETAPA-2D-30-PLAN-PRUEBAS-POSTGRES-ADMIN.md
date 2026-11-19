# ETAPA 2D-30 — Plan de pruebas PostgreSQL para protecciones administrativas

**Estado:** casos A–J aprobados en PostgreSQL 17 desechable (GitHub Actions, run #173); restauración completa de la base pendiente.
**No ejecutar contra:** Supabase AB-SYSTEM-DEMO activo ni Ko'eju producción.
**Parche relacionado:** sql/ETAPA-2D-29-PROTECCION-ULTIMO-ADMIN-Y-EMPRESAS-DRAFT.sql.

## Situación del entorno

- Proyecto AB-SYSTEM-DEMO: PostgreSQL 17.12, organización actualmente en plan Free.
- No existen ramas de desarrollo Supabase.
- La clonación/restauración oficial a un proyecto nuevo requiere plan pago y backups físicos habilitados. Una rama estándar aplica migraciones, pero no copia los datos de producción.
- No se creará una rama ni proyecto Supabase de pago sin revisar y aceptar el costo.
- Paso sin costo completado: los triggers reales pasaron A–J en un contenedor PostgreSQL 17 desechable de GitHub Actions, con un esquema fixture mínimo que reproduce las tablas y el trigger de identidad requeridos por el parche. Run #173: 10/10 casos aprobados.
- Esta prueba fixture no equivale a restaurar la base completa y no valida RLS, Auth, funciones de negocio ni conteos reales de todas las tablas.

## Preparación obligatoria

1. Completado: ejecutar el workflow de integración PostgreSQL en un servicio efímero postgres:17; A–J pasaron.
2. Crear tablas companies y company_memberships, roles de prueba y el trigger de identidad requerido por el preflight.
3. Cargar el parche 2D-29 en esa base efímera, convirtiendo su cierre ROLLBACK a COMMIT únicamente dentro del proceso automatizado y desechable.
4. Ejecutar los casos A–J y registrar SQLSTATE, resultado y conteos.
5. Para una prueba integral posterior, obtener una restauración de respaldo de AB-SYSTEM-DEMO en un proyecto independiente o entorno local. Confirmar primero el plan/costo, el punto de backup y el aislamiento de integraciones externas.
6. Antes de cualquier restauración, revisar extensiones y automatizaciones con efectos externos (pg_cron, pg_net, webhooks, wrappers) para evitar que la copia contacte sistemas reales.

## Casos de regresión

| Caso | Operación | Resultado esperado |
|---|---|---|
| A | Eliminar el único administrador activo | Rechazado con SQLSTATE 23514 |
| B | Suspender al único administrador activo | Rechazado con SQLSTATE 23514 |
| C | Cambiar el rol del único administrador activo a seller | Rechazado con SQLSTATE 23514 |
| D | Retirar uno de dos administradores activos | Permitido; queda exactamente uno activo |
| E | Retirar después al administrador restante | Rechazado con SQLSTATE 23514 |
| F | Retirar todos los administradores en una sentencia masiva | La sentencia completa se revierte; quedan dos activos |
| G | Dos sesiones concurrentes retiran administradores distintos | No pueden confirmar ambas; queda al menos uno activo |
| H | Eliminar físicamente una empresa | Rechazado con SQLSTATE 55000 |
| I | Ejecutar TRUNCATE sobre companies CASCADE | Rechazado con SQLSTATE 55000 |
| J | Suspender una empresa mediante UPDATE de status | Permitido; se conservan membresías |

## Comprobaciones para la restauración integral

- Comparar conteos de empresas, membresías, productos, clientes, pedidos e inventario antes/después.
- Confirmar que no se modificó company_id ni user_id de membresías.
- Confirmar que no se borraron empresas ni filas comerciales.
- Verificar RLS con usuarios de prueba de empresas distintas.
- Usar usuarios Auth sintéticos; no importar identidades reales para pruebas destructivas.
- Repetir A–J después de restaurar para demostrar reproducibilidad.

## Bloqueo de membresía

La auditoría de solo lectura confirma que DEMO2 tiene una membresía activa, cero company_admin activos y un miembro activo no administrador. El parche aborta si cualquier empresa carece de administrador activo. El responsable debe identificar qué cuenta autorizada debe recibir el rol; no se asignará el permiso por inferencia.

## Criterio de aprobación

No aprobar ni convertir el borrador en migración aplicable hasta que A–J pasen en PostgreSQL 17 real, se complete una restauración integral aislada para validar RLS e integridad global, DEMO2 tenga un administrador autorizado, todas las empresas pasen el preflight y exista aprobación explícita para el siguiente cambio.

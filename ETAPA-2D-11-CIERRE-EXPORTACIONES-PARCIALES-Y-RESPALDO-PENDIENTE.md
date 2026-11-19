# ETAPA 2D-11 — Cierre de exportaciones parciales y respaldo pendiente

Fecha: 2026-11-17
Proyecto: Supabase DEMO de AB-SYSTEM
Rama de documentación: `work/ab-system-multempresa-ui`

## 1. Alcance y seguridad

Este documento registra las exportaciones y consultas de solo lectura realizadas desde el panel de Supabase usando un teléfono móvil.

- No se ejecutaron operaciones DDL ni DML.
- No se modificaron tablas, datos, permisos, políticas RLS, funciones ni triggers.
- No se realizaron cambios en producción.
- No se ejecutó `pg_dump` ni se probó una restauración.
- El usuario informó que guardó los 10 CSV de tablas en una carpeta del celular. No se inspeccionaron directamente todos los archivos; su integridad individual queda pendiente de verificación.

## 2. Exportaciones de datos de tablas

El usuario informó haber descargado los CSV de las diez tablas de `public` y haberlos organizado en una carpeta.

| Archivo previsto | Resultado observado o informado |
|---|---|
| `DEMO_catalog_items.csv` | Descarga observada; 5 filas de artículos en el resultado. El CSV mostrado tenía columnas `code`, `payload`, `updated_at`. Se observó texto con mojibake al visualizar acentos; conservar el original sin editar y verificar codificación al restaurar. |
| `DEMO_catalog_clients.csv` | Usuario informó descarga; auditoría previa estimaba 4 registros. No se inspeccionó el archivo directamente. |
| `DEMO_catalog_import_rows.csv` | Consulta devolvió `Success. No rows returned`; se informó descarga CSV. |
| `DEMO_companies.csv` | Consulta mostró 1 empresa activa con código `KOEJU`; usuario informó descarga. |
| `DEMO_company_memberships.csv` | Consulta mostró 2 membresías activas (un `company_admin` y un `seller`); usuario informó descarga. |
| `DEMO_global_roles.csv` | Consulta mostró 1 rol `superadmin_global`; usuario informó descarga. |
| `DEMO_inventory_current.csv` | Consulta mostró 1 fila con `id=1`, `items=[]` e `imported_by=NULL`; usuario informó descarga. |
| `DEMO_orders.csv` | Consulta mostró 1 pedido histórico `archive`; usuario informó descarga. Contiene datos de pedido y referencias a usuario/cliente, por lo que debe mantenerse privado. |
| `DEMO_profiles.csv` | Usuario informó descarga; no compartió filas ni se inspeccionó el archivo. Auditoría previa estimaba 2 registros. |
| `DEMO_seller_assignments.csv` | Usuario informó descarga; no compartió filas ni se inspeccionó el archivo. Auditoría previa estimaba 1 registro. |

Las cantidades aproximadas previas de estadísticas de tablas no son conteos exactos. Los resultados de consultas individuales son evidencia más directa solo para las tablas cuyos resultados se compartieron.

## 3. Exportaciones de documentación de estructura

El usuario informó haber descargado los siguientes resultados CSV:

- `DEMO_estructura_columnas.csv` — columnas y tipos de datos de tablas públicas.
- `DEMO_restricciones_relaciones.csv` — restricciones y relaciones.
- `DEMO_indices.csv` — índices de `public`.
- `DEMO_politicas_RLS.csv` — políticas visibles en `pg_policies` para `public`.
- `DEMO_funciones_definiciones.csv` — definiciones de funciones de `public`.
- `DEMO_triggers_definiciones.csv` — triggers no internos en esquemas `public` y `auth`, junto con definiciones de funciones ejecutadas.
- `DEMO_permisos_tablas.csv` — permisos visibles mediante `information_schema.role_table_grants` para `anon`, `authenticated` y `service_role`.
- `DEMO_permisos_funciones.csv` — permisos visibles mediante `information_schema.role_routine_grants` para esos roles.
- `DEMO_extensiones.csv` — extensiones instaladas.

Verificación adicional:
- La consulta corregida de secuencias en `public` devolvió `Success. No rows returned` para los roles `anon`, `authenticated` y `service_role`.
- La consulta de `pg_publication_tables` para `supabase_realtime` devolvió `Success. No rows returned`.
- Una primera consulta de `role_usage_grants` falló porque se solicitó una columna inexistente (`sequence_schema`). Se corrigió usando catálogos de PostgreSQL; la consulta corregida no encontró secuencias públicas.

El usuario informó haber descargado los resultados de estructura, pero no se inspeccionaron los archivos CSV directamente. Su contenido y legibilidad deben verificarse antes de considerarlos evidencia completa.

## 4. Límites de estas exportaciones

Los CSV son copias parciales de datos y extractos de metadatos. No constituyen por sí solos un respaldo completo y restaurable de PostgreSQL.

Entre otros elementos, todavía debe prepararse y verificarse un respaldo lógico apropiado que incluya el esquema, restricciones, índices, funciones, triggers, políticas, grants y demás objetos necesarios. También deben tratarse por separado los objetos de Storage y cualquier proceso externo que escriba en la base.

Las consultas de catálogo dependen de los privilegios y visibilidad del rol que las ejecuta; un resultado vacío no demuestra necesariamente que no exista configuración fuera del alcance de la consulta.

## 5. Bloqueos obligatorios antes de cualquier cambio mutante

1. Obtener una exportación lógica completa con herramientas apropiadas (`pg_dump`/herramientas Supabase) y conservarla fuera del proyecto.
2. Confirmar que la exportación incluye los objetos requeridos y que puede leerse sin errores.
3. Probar la restauración en un proyecto separado, nunca sobre producción ni sobre la única DEMO disponible.
4. Verificar datos, funciones, triggers, permisos, RLS y comportamiento de la aplicación después de la restauración.
5. Inventariar escritores externos y dependencias que no puedan detectarse mediante consultas al catálogo.
6. Realizar un preflight actualizado y una revisión del plan exacto de cambios.
7. Obtener aprobación explícita del usuario sobre el script mutante completo antes de ejecutarlo manualmente.

## 6. Estado de cierre

**Completado:** exportaciones parciales informadas por el usuario y consultas de inventario/documentación de solo lectura.

**Pendiente:** verificar físicamente todos los archivos, respaldo lógico completo, copia separada de Storage cuando corresponda, prueba de restauración y cierre de bloqueos.

**Decisión:** no autorizar todavía DDL, DML, cambios de grants/RLS, backfill, importaciones, modificaciones de frontend dependientes del nuevo esquema, despliegues ni cambios en producción.

## 7. Próximo paso recomendado desde el celular

Conservar la carpeta de CSV en dos ubicaciones privadas y seguras. No compartir públicamente los archivos porque pueden contener datos de clientes, pedidos e identificadores de usuarios. Cuando se disponga de una computadora y de una persona administradora autorizada, realizar el respaldo lógico y la prueba de restauración siguiendo un procedimiento separado. No pegar contraseñas, tokens ni cadenas de conexión en el chat.
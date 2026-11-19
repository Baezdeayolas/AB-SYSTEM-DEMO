# ETAPA 2D-16 — Lote 3: políticas RLS por empresa

**Estado:** borrador de revisión; no ejecutado.  
**Dependencia:** Lotes 1 y 2 aplicados y verificados en AB-SYSTEM-DEMO.

## Archivo

`sql/ETAPA-2D-16-LOTE-3-RLS-POR-EMPRESA-DRAFT.sql`

## Qué propone

- Retirar todas las políticas anteriores en las tablas incluidas y crear reglas explícitas por empresa. Esto es necesario porque las políticas PERMISSIVE se combinan con OR; una regla antigua `USING (true)` mantendría el acceso global.
- Catálogos: miembros activos leen; administradores de empresa/superadmin escriben.
- Importaciones: solo administrador de empresa/superadmin.
- Pedidos: vendedor lee y actualiza los propios; admin de empresa ve los de su empresa; superadmin global ve todas las empresas.
- Alta de pedidos: exige `created_by = auth.uid()` y `owner_id` con membership seller activa en la misma empresa. El admin puede crear en nombre del vendedor.
- Memberships y global_roles: escritura reservada al superadmin global para evitar escalamiento de roles.
- Perfiles: lectura propia; el cliente no puede cambiar `profiles.role`.
- `seller_assignments`: compatibilidad transitoria, lectura propia/admin y escritura administrativa.
- `inventory_current`: se retiran políticas de acceso de cliente mientras se diseña inventario normalizado por empresa, ya que la tabla actual es un singleton global sin `company_id`.

## Advertencias importantes de revisión

1. Este lote reemplaza todas las policies de las tablas enumeradas. Antes de habilitar COMMIT, comprobar que no haya consumidores legítimos adicionales.
2. Las policies no sustituyen los GRANT/REVOKE. Un lote de privilegios mínimos debe retirar a `anon`/cliente permisos peligrosos como TRUNCATE, TRIGGER y REFERENCES, con matriz de operaciones y verificación.
3. No se cambia el trigger `on_demo_user_created` ni `create_demo_profile()`.
4. Las policies de UPDATE de pedidos no hacen inmutables `company_id`, `owner_id` o `created_by`. Antes de activar edición de pedidos, añadir trigger/backend de inmutabilidad o política equivalente y probarla.
5. La lectura de perfiles de otros vendedores se deja cerrada; el frontend debe obtener vendedores desde memberships y mostrar etiquetas sin necesitar exponer perfiles privados.
6. La política de inventory_current bloquea acceso cliente a la tabla legacy. No aplicar hasta confirmar que el flujo de stock no depende de lectura directa desde un cliente autenticado.
7. Las reglas de administrador/superadmin dependen de helpers `ab_*` previamente auditados. Requieren pruebas reales con JWT para cada rol y empresa.

## Seguridad y reversión

El script:
- exige columnas `company_id` no nulas y helpers existentes;
- elimina todas las policies previas de las tablas indicadas, para evitar OR accidental;
- crea las políticas nuevas y verifica que no queden expresiones abiertas `true`;
- termina en `ROLLBACK`, por lo que ejecutar el borrador literalmente no persiste cambios.

No autoriza ejecución. Antes de cambiar el cierre a COMMIT se requiere respaldo/restauración probada, revisión del inventario de consumidores y aprobación expresa del propietario. No ejecutar en Ko'eju histórico/producción.


## Corrección de revisión — 2026-11-17

Se reforzó el borrador SQL para corregir dos riesgos detectados:
- La policy de INSERT de pedidos ahora exige siempre un vendedor propietario activo en la misma empresa, también para el superadministrador global.
- Se agregaron triggers de protección para impedir cambios ordinarios a la identidad/empresa del pedido y a la identidad de la membresía. El administrador de empresa puede gestionar vendedores de su empresa, pero no crear administradores ni cambiar roles; los cambios de rol quedan reservados al superadministrador global.

El archivo SQL sigue terminando en ROLLBACK. Esta corrección es un borrador para revisión, no una migración ejecutada ni una prueba de RLS/JWT. El inventario se prepara en el Lote 5 y los privilegios por defecto/secuencias/funciones en el Lote 6.


## Correcciones técnicas adicionales — 2026-11-17

La revisión estática encontró y corrigió un error de delimitadores dollar-quote en las funciones PL/pgSQL del borrador. También se agregó un trigger que exige que toda asignación de vendedor corresponda a una membresía seller activa de la misma empresa. La protección de pedidos permite que Auth establezca created_by en NULL únicamente durante una eliminación administrativa ejecutada por los roles privilegiados postgres/service_role/supabase_auth_admin; los usuarios de la aplicación no pueden cambiar el creador.

Estas correcciones son de código y todavía no se han ejecutado contra Supabase. El SQL continúa terminando en ROLLBACK.

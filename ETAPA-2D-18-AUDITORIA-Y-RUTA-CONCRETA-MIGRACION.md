# ETAPA 2D-18 — Auditoría de migración y ruta de ejecución

Fecha: 2026-11-17  
Repositorio: `Baezdeayolas/AB-SYSTEM-DEMO`  
Rama: `work/adaptacion-multiempresa-v1`

## Decisión ejecutiva

**No ejecutar todavía los Lotes 1–4 existentes.** Son borradores de trabajo, no una migración aprobada. La revisión encontró bloqueos funcionales y de seguridad que deben corregirse antes de convertirlos en scripts ejecutables.

La migración seguirá siendo exclusivamente sobre el proyecto Supabase `AB-SYSTEM-DEMO`. Ko’ẽju histórico/producción permanece intacto. No se ejecutó SQL en Supabase, no se publicó ni se fusionó la rama.

## Avance real ya comprobado

Se hizo una restauración local del respaldo `AB-SYSTEM-DEMO.backup` en un clúster PostgreSQL aislado:

- 10 tablas públicas.
- 5 funciones públicas.
- 15 políticas RLS.
- 7 claves foráneas.
- 17 filas recuperadas en las 10 tablas públicas.
- 2 UUID ficticios en `auth.users`, creados únicamente para satisfacer las FKs durante la prueba local.

La estructura y los datos públicos se recuperaron. Los dos registros Auth locales no son cuentas ni credenciales reales. La prueba no valida Auth/Storage de Supabase, sesiones JWT ni el comportamiento efectivo de RLS.

## Hallazgos que impiden ejecutar los borradores actuales

### 1. Inventario multiempresa no está resuelto

`inventory_current` sigue siendo una tabla singleton con `id = 1` y un JSONB global. El Lote 1 la deja intacta y el Lote 3 elimina sus políticas de acceso para clientes. Esto evita exponer el inventario global, pero no entrega todavía inventario por empresa ni un flujo de actualización utilizable.

La decisión de arquitectura ya establece inventario por empresa/producto y movimientos append-only. Falta convertir esa decisión en tablas, restricciones, operaciones transaccionales y cambios de frontend. Los pedidos seguirán sin descontar ni reservar stock: esa regla funcional se conserva.

**Consecuencia:** no declarar terminada la migración multiempresa mientras el inventario siga siendo global o inaccesible para los flujos autorizados.

### 2. Lote 3: los pedidos permiten cambios de pertenencia

La policy `orders_update_company_owner` valida acceso sobre la fila anterior y la nueva, pero no hace inmutables `company_id`, `owner_id`, `created_by`, `legacy_source` y `legacy_id`. Un vendedor podría intentar modificar campos que definen la pertenencia/identidad del pedido.

Debe agregarse una protección de backend (trigger o función controlada) que impida cambiar esas columnas después de crear el pedido, con un procedimiento administrativo explícito si en el futuro se necesita transferirlo.

Además, la rama de superadministrador en `orders_insert_company` omite la comprobación de que `owner_id` sea un vendedor activo de la empresa indicada. El superadministrador puede operar globalmente, pero la relación pedido-vendedor-empresa debe seguir siendo válida.

### 3. Gestión de membresías no coincide con la arquitectura

El diseño establece que el administrador de empresa gestione usuarios de su propia empresa. El Lote 3 solo permite INSERT/UPDATE/DELETE de `company_memberships` al superadministrador global.

Hay que definir un flujo seguro para que `company_admin` gestione membresías dentro de su empresa, sin poder asignarse a sí mismo el rol global, elevarse a administrador ni crear membresías en otra empresa. Los cambios de rol deben validarse en backend y tener límites claros.

### 4. Lote 4 no completa el mínimo de privilegios

El Lote 4 revoca/grant privilegios de tabla, pero declara expresamente que no modifica:
- privilegios por defecto (default privileges);
- secuencias;
- EXECUTE de funciones;
- permisos de `service_role`.

La auditoría previa detectó default ACL amplias para `postgres` y `supabase_admin`, además de funciones con EXECUTE para PUBLIC/anon. Por tanto, el Lote 4 no puede presentarse como cierre de seguridad. Se necesita un lote separado que inventaríe y corrija ACL por rol/objeto sin romper funciones usadas por triggers ni procesos de Supabase.

### 5. El borrado masivo de policies necesita inventario final

El Lote 3 elimina todas las policies de diez tablas y las reemplaza. Antes de hacerlo, debe guardarse el inventario exacto de policies, funciones referenciadas y comportamiento esperado por operación. Las policies antiguas permisivas sí deben neutralizarse porque PostgreSQL combina policies permissive con OR, pero no se deben descartar policies válidas sin una matriz de equivalencia.

### 6. Mapeo de perfiles y vendedores debe ser explícito

La copia DEMO contiene dos perfiles, dos membresías, un rol global y una asignación de vendedor. Los conteos no bastan para decidir qué persona debe ser `company_admin`, cuál debe ser `seller`, ni qué vendedor corresponde al pedido histórico.

Antes del backfill, se debe validar la correspondencia entre:
- `profiles.id`;
- `company_memberships.user_id/role/status`;
- `global_roles.user_id/role`;
- `seller_assignments.user_id`;
- `orders.owner_id`.

No se deben inferir identidades o roles a partir de los conteos ni modificar UUID de Auth.

## Ruta concreta de migración

### Etapa A — corregir el diseño antes de tocar Supabase
1. Definir inventario por empresa/producto y movimientos.
2. Definir reglas de inmutabilidad y transferencia de pedidos.
3. Completar la matriz de quién puede crear/editar/suspender membresías.
4. Completar la matriz de privilegios de tablas, secuencias, funciones y default ACL.
5. Ajustar los lotes SQL para reflejar esas decisiones.

### Etapa B — migración aditiva de datos DEMO
1. Verificar precondiciones y correspondencia de membresías.
2. Añadir `company_id` inicialmente nullable a catálogos, importaciones, pedidos y asignaciones.
3. Asociar los datos existentes a la empresa ya confirmada `KOEJU`, sin cambiar su código ni borrar filas.
4. Validar conteos, filas sin empresa, propietarios de pedidos y asignaciones.
5. Añadir claves/índices por empresa.
6. Aplicar claves compuestas solo después de comprobar dependencias de FK.
7. Mantener el ID de pedido como PK y la unicidad legacy acotada por empresa.

### Etapa C — inventario
1. Crear modelo de saldos por empresa/producto y movimientos append-only.
2. Migrar el stock de origen únicamente después de identificar la fuente vigente y reconciliar cantidades.
3. Mantener la creación de pedidos separada de los movimientos de inventario.
4. Actualizar importación/lectura de stock para operar con la empresa activa.
5. No exponer el singleton legacy a usuarios autenticados.

### Etapa D — seguridad
1. Crear/validar helpers SECURITY DEFINER con search_path seguro y EXECUTE mínimo.
2. Aplicar policies por tabla y operación, con aislamiento por company_id.
3. Proteger campos de pertenencia de pedidos.
4. Permitir administración de membresías solo dentro de la empresa al company_admin y reservar global_roles al superadmin.
5. Corregir grants de tablas, columnas, secuencias, funciones y default ACL.
6. Probar JWT reales para superadmin, company_admin, seller y usuario sin membresía; incluir pruebas negativas entre dos empresas.

### Etapa E — aplicación y aceptación
1. Actualizar frontend y flujos de importación/inventario para el modelo final.
2. Probar cambio de empresa, catálogo, clientes, asignaciones y pedidos.
3. Confirmar que un pedido no factura, no reserva ni descuenta stock.
4. Probar dos empresas sintéticas con códigos repetidos en catálogos.
5. Confirmar aislamiento cruzado mediante consultas directas/RLS, no solo filtros del navegador.
6. Recién después autorizar publicación DEMO. Ko’ẽju producción queda fuera de esta etapa.

## Criterio para declarar lista la migración

No basta con que los SQL terminen sin errores. Se exige:
- cero filas comerciales sin empresa;
- claves y unicidad por empresa verificadas;
- inventario aislado por empresa;
- policies y grants probados con JWT de cada rol;
- ninguna lectura/escritura cruzada;
- pedidos con pertenencia inmutable;
- importación de stock por empresa;
- rollback documentado y practicable;
- frontend probado en móvil.

## Estado

- Respaldo DEMO: restauración local de esquema y datos públicos comprobada.
- Respaldo Ko’ẽju histórico: generado y legible por `pg_restore --list`, pero su restauración local no se ha probado.
- Lotes SQL 1–4: borradores; **no ejecutar en Supabase**.
- SQL en Supabase: no ejecutado.
- Ko’ẽju producción: sin cambios.
- Publicación/merge: no realizados.

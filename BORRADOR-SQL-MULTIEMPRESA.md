# Borrador SQL de migración — AB SYSTEM DEMO

> **NO EJECUTAR. BORRADOR PARA REVISIÓN.**  
> Este archivo no es una migración lista para pegar en Supabase. No se ha probado contra el proyecto y deliberadamente no contiene políticas RLS finales, grants/revokes ni asignación de superadministrador. La ejecución requiere revisión del DDL real, respaldo DEMO y autorización explícita.

## 1. Objetivo

Crear la base multiempresa con Ko’ẽju como primera empresa DEMO, conservando registros actuales. El esquema debe soportar códigos repetidos en distintas empresas y mantener los pedidos vinculados a su propietario.

## 2. Parámetros que aún deben resolverse

- UUID del usuario que será superadministrador global: **pendiente de identificación segura**. No introducirlo desde el navegador ni inferirlo por email.
- Mapeo de los dos perfiles actuales a membresías de Ko’ẽju: **pendiente de confirmación**.
- Confirmar si un mismo usuario podrá pertenecer a varias empresas: el diseño lo permite.
- Revisar todas las dependencias de las PK actuales antes de sustituirlas.
- Confirmar si se conservará `inventory_current` como tabla histórica/compatibilidad o se reemplazará por completo tras adaptar el frontend.

## 3. Esquema objetivo (referencia, no script de ejecución)

### 3.1 Empresas

```sql
CREATE TABLE public.companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'suspended')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

Primera fila prevista: código `KOEJU`, nombre `Ko’ẽju`, estado `active`. No crear duplicados si el código ya existe; comprobar antes de insertar.

### 3.2 Membresías por empresa

```sql
CREATE TABLE public.company_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('company_admin', 'seller')),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'suspended')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, user_id),
  UNIQUE (company_id, id)
);
```

La membresía identifica el rol dentro de una empresa. El rol `admin` actual de `profiles` no se debe convertir automáticamente en `superadmin_global`. El mapeo a `company_admin` requiere confirmar a qué empresa y persona corresponde cada perfil.

### 3.3 Rol global separado

```sql
CREATE TABLE public.global_roles (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('superadmin_global')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role)
);
```

No crear políticas que permitan a `authenticated` insertar o modificar esta tabla. El alta inicial del superadmin debe realizarse mediante un procedimiento privilegiado y auditado, después de verificar la identidad. Nunca aceptar `role` o `user_id` de un formulario público como autorización.

### 3.4 Ámbito de empresa en tablas existentes

Columnas objetivo:

- `catalog_items.company_id uuid NOT NULL REFERENCES companies(id)`
- `catalog_clients.company_id uuid NOT NULL REFERENCES companies(id)`
- `catalog_import_rows.company_id uuid NOT NULL REFERENCES companies(id)`
- `orders.company_id uuid NOT NULL REFERENCES companies(id)`
- `seller_assignments.company_id uuid NOT NULL REFERENCES companies(id)` (con rediseño de PK)

Durante una migración real, las columnas se agregarían primero como nullable, se haría el backfill a Ko’ẽju y se validarían huérfanos antes de imponer NOT NULL.

Claves lógicas finales previstas:

- `catalog_items`: UNIQUE (`company_id`, `code`)
- `catalog_clients`: UNIQUE (`company_id`, `code`)
- `catalog_import_rows`: UNIQUE (`company_id`, `import_id`, `catalog_type`, `code`)
- `orders`: revisar la unicidad actual; posible UNIQUE (`company_id`, `owner_id`, `legacy_source`, `legacy_id`) según semántica de negocio.
- `seller_assignments`: clave que permita varias asignaciones por usuario y empresa, por ejemplo UNIQUE (`company_id`, `user_id`, `seller_label`) solo si esa es la regla real.

**Advertencia sobre PK:** hoy `catalog_items.code` y `catalog_clients.code` son PK. No basta con crear un índice único nuevo: hay que revisar FKs entrantes y código consumidor antes de cambiar la PK. El cambio de PK no se incluye como instrucción ejecutable en este borrador.

## 4. Inventario: diseño recomendado

El inventario JSONB actual contiene un array vacío y está limitado por CHECK a `id = 1`. No es un modelo multiempresa. La estructura normalizada propuesta es:

```sql
CREATE TABLE public.inventory_balances (
  company_id uuid NOT NULL REFERENCES public.companies(id),
  product_code text NOT NULL,
  quantity numeric(18,3) NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (company_id, product_code)
);

CREATE TABLE public.inventory_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  product_code text NOT NULL,
  movement_type text NOT NULL
    CHECK (movement_type IN ('entry', 'exit', 'adjustment')),
  quantity_delta numeric(18,3) NOT NULL CHECK (quantity_delta <> 0),
  quantity_before numeric(18,3) NOT NULL,
  quantity_after numeric(18,3) NOT NULL,
  reason text NOT NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  source_type text,
  source_id text,
  CHECK (quantity_after = quantity_before + quantity_delta),
  CHECK (quantity_before >= 0 AND quantity_after >= 0)
);
```

Este es un modelo ilustrativo. Antes de adoptarlo deben confirmarse unidades, precisión decimal, regla de stock negativo, catálogo de movimientos, FK compuesta a producto y estrategia de concurrencia. Las escrituras deberán pasar por una función transaccional segura que bloquee la fila de saldo y registre saldo anterior/nuevo. Usuarios de aplicación no tendrán UPDATE/DELETE sobre movimientos.

## 5. Orden de migración propuesto

1. Hacer backup de Supabase DEMO y verificar restauración.
2. Inspeccionar dependencias, FKs entrantes, índices, vistas, funciones, triggers y grants.
3. Crear `companies`, `company_memberships` y `global_roles`.
4. Crear Ko’ẽju con código estable `KOEJU`.
5. Confirmar y crear membresías de los dos perfiles existentes; no inferir su identidad.
6. Agregar `company_id` nullable a tablas comerciales.
7. Asignar a Ko’ẽju los 5 productos, 4 clientes, 1 pedido y cualquier fila de importación (actualmente cero).
8. Validar conteos y que no queden filas sin empresa.
9. Resolver PK/UNIQUE y FKs con plan de compatibilidad.
10. Crear inventario normalizado y funciones transaccionales; la tabla actual tiene array vacío, conservarla durante la transición.
11. Implementar RLS por tabla y operación, helpers de membresía y superadmin; revisar grants y EXECUTE.
12. Adaptar frontend/backend para enviar contexto de empresa, siempre validado por RLS.
13. Ejecutar pruebas negativas con dos empresas ficticias.
14. Solo después de aprobación separada, desplegar DEMO.

## 6. Validaciones obligatorias antes y después

- Conteos antes/después: productos 5, clientes 4, pedidos 1, importaciones 0; perfiles 2 y asignaciones 1 sin pérdida.
- Cero filas comerciales con `company_id IS NULL`.
- Cero referencias a empresas inexistentes.
- Las claves repetidas en empresas distintas se aceptan; duplicadas dentro de una empresa se rechazan.
- El pedido conserva su `owner_id`, `legacy_id`, `legacy_source` y `payload`.
- Un vendedor de Ko’ẽju no puede leer ni escribir datos de una segunda empresa.
- Un administrador de Ko’ẽju no puede administrar la segunda empresa.
- Un usuario sin membresía no accede a ninguna empresa.
- Solo la cuenta asignada por procedimiento confiable obtiene superadmin global.
- Una operación de stock fallida no deja saldo ni movimiento parcial.
- Los movimientos históricos no pueden actualizarse ni borrarse por usuarios de aplicación.

## 7. Reversión

No se debe improvisar un rollback mediante DROP. El plan debe usar backup verificado y pasos de reversión específicos para cada fase. Mantener columnas/tablas antiguas durante la transición; no eliminar `inventory_current` hasta demostrar que ningún cliente ni versión publicada depende de ella. Si se habilita escritura multiempresa, detener escrituras y restaurar desde backup o aplicar compensaciones revisadas; no borrar datos nuevos automáticamente.

## 8. Elementos expresamente no incluidos

- No incluye ejecución en Supabase.
- No incluye cambios de RLS o grants listos para aplicar.
- No incluye asignación del usuario superadmin.
- No incluye sustitución de PK existentes.
- No incluye alteración de producción.
- No incluye publicación ni merge.

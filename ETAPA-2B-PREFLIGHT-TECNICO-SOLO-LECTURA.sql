# Etapa 2B — preflight técnico adicional (solo lectura)

> **SEGURO PARA INSPECCIÓN: SOLO SELECT.** Ejecutar exclusivamente en Supabase DEMO. No contiene DDL, DML, GRANT ni REVOKE. Ejecutar cada bloque por separado y compartir sus resultados. No pegarlo en producción.

Este paquete completa lo que todavía no está confirmado: definición exacta de columnas/constraints/índices, triggers, vistas, funciones que podrían depender de las tablas, grants por tabla/columna/secuencia, y privilegios por defecto.

## A. Columnas, tipos, defaults y nullabilidad

```sql
select table_name, ordinal_position, column_name, data_type, udt_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in ('catalog_items','catalog_clients','catalog_import_rows','orders','seller_assignments','inventory_current','profiles','companies','company_memberships','global_roles')
order by table_name, ordinal_position;
```

## B. Constraints y claves exactas

```sql
select c.conrelid::regclass as tabla, c.conname, c.contype, c.convalidated, pg_get_constraintdef(c.oid, true) as definicion
from pg_constraint c
where c.conrelid in (
  'public.catalog_items'::regclass, 'public.catalog_clients'::regclass,
  'public.catalog_import_rows'::regclass, 'public.orders'::regclass,
  'public.seller_assignments'::regclass, 'public.inventory_current'::regclass,
  'public.profiles'::regclass, 'public.companies'::regclass,
  'public.company_memberships'::regclass, 'public.global_roles'::regclass
)
order by tabla::text, c.contype, c.conname;
```

## C. Índices actuales

```sql
select schemaname, tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in ('catalog_items','catalog_clients','catalog_import_rows','orders','seller_assignments','inventory_current','profiles','companies','company_memberships','global_roles')
order by tablename, indexname;
```

## D. Triggers y funciones invocadas por triggers

```sql
select n.nspname as schema_name, c.relname as tabla, t.tgname as trigger_name,
       pg_get_triggerdef(t.oid, true) as definicion,
       pn.nspname as function_schema, p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as function_arguments
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
join pg_proc p on p.oid = t.tgfoid
join pg_namespace pn on pn.oid = p.pronamespace
where not t.tgisinternal
  and n.nspname = 'public'
  and c.relname in ('catalog_items','catalog_clients','catalog_import_rows','orders','seller_assignments','inventory_current','profiles','companies','company_memberships','global_roles')
order by c.relname, t.tgname;
```

## E. Vistas y vistas materializadas que podrían depender del esquema

```sql
select schemaname, viewname, definition
from pg_views
where schemaname = 'public'
  and (definition ilike '%catalog_items%' or definition ilike '%catalog_clients%'
       or definition ilike '%catalog_import_rows%' or definition ilike '%orders%'
       or definition ilike '%seller_assignments%' or definition ilike '%inventory_current%'
       or definition ilike '%company_memberships%' or definition ilike '%global_roles%')
order by viewname;
```

## F. Funciones SQL/PLpgSQL que mencionan tablas objetivo

```sql
select n.nspname as schema_name, p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       l.lanname as language, p.prosecdef as security_definer,
       p.proconfig as function_settings,
       pg_get_userbyid(p.proowner) as owner,
       p.proacl as acl,
       left(p.prosrc, 5000) as source_excerpt
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_language l on l.oid = p.prolang
where n.nspname = 'public'
  and (p.prosrc ilike any (array[
    '%catalog_items%', '%catalog_clients%', '%catalog_import_rows%',
    '%orders%', '%seller_assignments%', '%inventory_current%',
    '%company_memberships%', '%global_roles%'
  ]))
order by p.proname;
```

## G. Grants de tabla y columna

```sql
select table_name, grantee, privilege_type, is_grantable
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('catalog_items','catalog_clients','catalog_import_rows','orders','seller_assignments','inventory_current','profiles','companies','company_memberships','global_roles')
order by table_name, grantee, privilege_type;
```

```sql
select table_name, column_name, grantee, privilege_type, is_grantable
from information_schema.role_column_grants
where table_schema = 'public'
  and table_name in ('catalog_items','catalog_clients','catalog_import_rows','orders','seller_assignments','inventory_current','profiles','companies','company_memberships','global_roles')
order by table_name, column_name, grantee, privilege_type;
```

## H. Secuencias y privilegios sobre ellas

```sql
select sequence_schema, sequence_name, grantee, privilege_type, is_grantable
from information_schema.role_usage_grants
where object_type = 'SEQUENCE' and sequence_schema = 'public'
order by sequence_name, grantee, privilege_type;
```

## I. Privilegios por defecto del esquema public

```sql
select pg_get_userbyid(d.defaclrole) as owner_role,
       n.nspname as schema_name, d.defaclobjtype as object_type,
       d.defaclacl as default_acl
from pg_default_acl d
left join pg_namespace n on n.oid = d.defaclnamespace
where n.nspname = 'public' or d.defaclnamespace = 0
order by owner_role, object_type;
```

## J. RLS habilitado/forzado y propietarios

```sql
select n.nspname as schema_name, c.relname as table_name,
       pg_get_userbyid(c.relowner) as owner,
       c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r','p')
  and c.relname in ('catalog_items','catalog_clients','catalog_import_rows','orders','seller_assignments','inventory_current','profiles','companies','company_memberships','global_roles')
order by c.relname;
```

## Importante

- No enviar contraseñas, tokens, claves API ni valores secretos. Las consultas no solicitan credenciales.
- En el bloque F, si aparece código interno sensible que prefieras no compartir, comparte solo nombre, argumentos, lenguaje, `security_definer`, `function_settings` y owner; podemos pedir después el cuerpo puntual de las funciones relevantes.
- Las consultas de `information_schema` y catálogos reflejan lo visible para el rol que ejecuta la consulta. Ejecutar como propietario/rol administrativo del proyecto DEMO para obtener el inventario completo.
- Este paquete no cambia nada. Los resultados servirán para redactar SQL de migración exacto y separado en fases.

## Estado

Creado para cerrar la inspección técnica previa. No ejecutar cambios de Supabase ni frontend basándose únicamente en estos resultados; falta revisar los consumidores y preparar pruebas RLS con JWT.
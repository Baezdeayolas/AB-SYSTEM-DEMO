# Etapa 2B — inventario de funciones, ACL y dependencias (solo lectura)

> **Solo inspección.** Ejecutar exclusivamente en Supabase DEMO, bloque por bloque. Contiene únicamente consultas `SELECT`. No contiene DDL, DML, `GRANT` ni `REVOKE`. No pegar en producción.

Este paquete complementa el preflight A–J. Busca documentar funciones expuestas, privilegios efectivos de ejecución, funciones `SECURITY DEFINER`, dependencias catalogadas y políticas RLS antes de diseñar cualquier cambio de permisos.

## A. Funciones del esquema public: identidad, seguridad y ACL

```sql
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  pg_get_userbyid(p.proowner) as owner,
  l.lanname as language,
  p.prosecdef as security_definer,
  p.provolatile as volatility,
  p.proconfig as function_settings,
  coalesce(p.proacl, acldefault('f', p.proowner)) as effective_acl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_language l on l.oid = p.prolang
where n.nspname = 'public'
order by p.proname, identity_arguments;
```

## B. Privilegios EXECUTE desglosados por función y beneficiario

```sql
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  coalesce(grantee.rolname, 'PUBLIC') as grantee,
  x.privilege_type,
  x.is_grantable,
  pg_get_userbyid(p.proowner) as function_owner,
  p.prosecdef as security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as x
left join pg_roles grantee on grantee.oid = x.grantee
where n.nspname = 'public'
order by p.proname, identity_arguments, grantee;
```

## C. Funciones SECURITY DEFINER y configuración

```sql
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  pg_get_userbyid(p.proowner) as owner,
  l.lanname as language,
  p.proconfig as function_settings,
  p.proacl as acl,
  pg_get_functiondef(p.oid) as full_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_language l on l.oid = p.prolang
where n.nspname = 'public'
  and p.prosecdef
order by p.proname, identity_arguments;
```

Revisar especialmente `search_path`, validación de `auth.uid()`, validación de empresa/membership, SQL dinámico, y si la función devuelve datos que el invocador no debería conocer. No compartir secretos si alguna definición los contuviera.

## D. Dependencias catalogadas entre funciones y objetos

```sql
select distinct
  pn.nspname as function_schema,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  d.refclassid::regclass as referenced_catalog,
  case
    when d.refclassid = 'pg_class'::regclass then d.refobjid::regclass::text
    when d.refclassid = 'pg_proc'::regclass then d.refobjid::regprocedure::text
    else d.refobjid::text
  end as referenced_object,
  d.deptype as dependency_type
from pg_depend d
join pg_proc p on d.classid = 'pg_proc'::regclass and d.objid = p.oid
join pg_namespace pn on pn.oid = p.pronamespace
where pn.nspname = 'public'
  and d.refclassid in ('pg_class'::regclass, 'pg_proc'::regclass)
order by function_schema, function_name, identity_arguments, referenced_object;
```

**Limitación:** PostgreSQL no registra todas las dependencias de referencias dentro de cuerpos PL/pgSQL o SQL dinámico. Por eso este bloque debe combinarse con revisión de definiciones y búsqueda de texto; una salida vacía no prueba ausencia de dependencias.

## E. Funciones referenciadas por triggers, incluidos triggers fuera de public

```sql
select
  tn.nspname as trigger_table_schema,
  tc.relname as trigger_table,
  t.tgname as trigger_name,
  pg_get_triggerdef(t.oid, true) as trigger_definition,
  fn.nspname as function_schema,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as function_arguments,
  pg_get_userbyid(p.proowner) as function_owner,
  p.prosecdef as security_definer,
  p.proconfig as function_settings,
  p.proacl as function_acl
from pg_trigger t
join pg_class tc on tc.oid = t.tgrelid
join pg_namespace tn on tn.oid = tc.relnamespace
join pg_proc p on p.oid = t.tgfoid
join pg_namespace fn on fn.oid = p.pronamespace
where not t.tgisinternal
  and (tn.nspname in ('public', 'auth') or fn.nspname = 'public')
order by trigger_table_schema, trigger_table, trigger_name;
```

Este bloque debe confirmar el trigger `on_demo_user_created` asociado a `auth.users` y la función `public.create_demo_profile()` si siguen presentes.

## F. Políticas RLS completas en tablas objetivo

```sql
select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual as using_expression,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'catalog_items','catalog_clients','catalog_import_rows','orders',
    'seller_assignments','inventory_current','profiles',
    'companies','company_memberships','global_roles'
  )
order by tablename, policyname;
```

## G. Funciones que contienen referencias textuales a tablas y helpers conocidos

```sql
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  l.lanname as language,
  p.prosecdef as security_definer,
  p.proconfig as function_settings,
  pg_get_userbyid(p.proowner) as owner,
  p.proacl as acl,
  left(pg_get_functiondef(p.oid), 12000) as definition_excerpt
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
join pg_language l on l.oid = p.prolang
where n.nspname in ('public', 'auth')
  and (
    pg_get_functiondef(p.oid) ilike any (array[
      '%catalog_items%', '%catalog_clients%', '%catalog_import_rows%',
      '%inventory_current%', '%orders%', '%seller_assignments%',
      '%company_memberships%', '%global_roles%', '%companies%',
      '%is_demo_admin%', '%ab_has_company_access%',
      '%ab_is_company_admin%', '%ab_is_global_superadmin%',
      '%create_demo_profile%'
    ])
  )
order by schema_name, function_name, identity_arguments;
```

## H. ACL de secuencias existentes

```sql
select
  n.nspname as schema_name,
  c.relname as sequence_name,
  pg_get_userbyid(c.relowner) as owner,
  coalesce(c.relacl, acldefault('S', c.relowner)) as effective_acl
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'S'
order by c.relname;
```

## Instrucciones para compartir resultados

1. Ejecutar cada bloque por separado en Supabase DEMO.
2. Compartir primero A y B; después C y E para revisar las funciones sensibles y el trigger de alta de usuarios.
3. Compartir D, F, G y H para cerrar dependencias, RLS y secuencias.
4. Si las definiciones de funciones muestran datos sensibles, no compartirlos; informar nombre y configuración y se solicitará solo el fragmento necesario.
5. Si un bloque devuelve error, compartir el error exacto y no improvisar cambios.

## Límites

- Todas las consultas son de lectura; no ejecutar ningún `GRANT`, `REVOKE`, `ALTER`, `CREATE`, `DROP`, `INSERT`, `UPDATE` ni `DELETE`.
- Los catálogos muestran lo visible para el rol que ejecuta la consulta. Ejecutar como rol administrativo de Supabase DEMO para obtener una inspección completa.
- Las dependencias de PL/pgSQL y SQL dinámico pueden no aparecer en `pg_depend`; revisar también el texto de las funciones y el código de la aplicación.
- No aplicar cambios de permisos hasta aprobar un script completo y sus verificaciones.

## Estado

Inventario adicional preparado. Pendiente de ejecución manual por el usuario en Supabase DEMO. No se ha modificado Supabase ni producción.
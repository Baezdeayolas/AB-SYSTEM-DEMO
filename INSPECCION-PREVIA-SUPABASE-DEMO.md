# Inspección técnica previa a migración — Supabase DEMO

**Solo lectura.** Ejecutar cada consulta en el SQL Editor del proyecto Supabase DEMO. No ejecutar en producción. No contiene DDL, INSERT, UPDATE, DELETE, GRANT ni REVOKE.

Al compartir resultados, ocultar correos, UUID de usuarios, teléfonos, RUC, nombres reales, tokens y cualquier dato personal. Para JSONB, compartir únicamente tipos, claves y estructura; no pegar registros completos.

## 1. Confirmar definición exacta de las siete tablas

```sql
SELECT
  c.table_name,
  c.ordinal_position,
  c.column_name,
  c.data_type,
  c.udt_name,
  c.is_nullable,
  c.column_default
FROM information_schema.columns c
WHERE c.table_schema = 'public'
  AND c.table_name IN (
    'catalog_clients',
    'catalog_import_rows',
    'catalog_items',
    'inventory_current',
    'orders',
    'profiles',
    'seller_assignments'
  )
ORDER BY c.table_name, c.ordinal_position;
```

## 2. Constraints, claves primarias, únicas y foráneas

```sql
SELECT
  tc.table_name,
  tc.constraint_name,
  tc.constraint_type,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name,
  cc.check_clause
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu
  ON tc.constraint_schema = kcu.constraint_schema
 AND tc.constraint_name = kcu.constraint_name
 AND tc.table_name = kcu.table_name
LEFT JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_schema = ccu.constraint_schema
 AND tc.constraint_name = ccu.constraint_name
LEFT JOIN information_schema.check_constraints cc
  ON tc.constraint_schema = cc.constraint_schema
 AND tc.constraint_name = cc.constraint_name
WHERE tc.table_schema = 'public'
  AND tc.table_name IN (
    'catalog_clients',
    'catalog_import_rows',
    'catalog_items',
    'inventory_current',
    'orders',
    'profiles',
    'seller_assignments'
  )
ORDER BY tc.table_name, tc.constraint_type, tc.constraint_name, kcu.ordinal_position;
```

## 3. Índices completos

```sql
SELECT
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
    'catalog_clients',
    'catalog_import_rows',
    'catalog_items',
    'inventory_current',
    'orders',
    'profiles',
    'seller_assignments'
  )
ORDER BY tablename, indexname;
```

## 4. Triggers de tablas públicas y Auth

```sql
SELECT
  event_object_schema,
  event_object_table,
  trigger_name,
  event_manipulation,
  action_timing,
  action_statement
FROM information_schema.triggers
WHERE event_object_schema IN ('public', 'auth')
ORDER BY event_object_schema, event_object_table, trigger_name;
```

## 5. Vistas y vistas materializadas que dependen de tablas actuales

```sql
SELECT
  schemaname,
  viewname,
  definition
FROM pg_views
WHERE schemaname = 'public'
ORDER BY viewname;
```

Revisar la definición antes de compartirla y ocultar cualquier literal que parezca dato personal o secreto.

## 6. Forma del JSONB de inventario sin revelar datos

Esta consulta devuelve tipos y claves superiores del documento `items`, no valores de inventario:

```sql
SELECT
  jsonb_typeof(items) AS items_type,
  CASE
    WHEN jsonb_typeof(items) = 'object'
      THEN (SELECT jsonb_agg(key ORDER BY key) FROM jsonb_object_keys(items) AS key)
    WHEN jsonb_typeof(items) = 'array'
      THEN (
        SELECT jsonb_agg(DISTINCT jsonb_typeof(value))
        FROM jsonb_array_elements(items) AS value
      )
    ELSE NULL
  END AS top_level_structure,
  jsonb_array_length(items) FILTER (WHERE jsonb_typeof(items) = 'array') AS array_length,
  imported_at IS NOT NULL AS has_imported_at,
  imported_by IS NOT NULL AS has_imported_by
FROM public.inventory_current;
```

Si `items` es un objeto JSON, inspeccionar las claves de un elemento sin exponer sus valores requiere conocer primero la estructura. No compartir el contenido completo de `items`.

## 7. Forma de payload de productos, clientes y pedidos

Las siguientes consultas devuelven únicamente claves de objeto y tipo JSON; no devuelven valores:

```sql
SELECT
  'catalog_items' AS source,
  jsonb_typeof(payload) AS payload_type,
  (SELECT jsonb_agg(key ORDER BY key)
   FROM jsonb_object_keys(payload) AS key) AS payload_keys
FROM public.catalog_items
WHERE jsonb_typeof(payload) = 'object'
LIMIT 5;
```

```sql
SELECT
  'catalog_clients' AS source,
  jsonb_typeof(payload) AS payload_type,
  (SELECT jsonb_agg(key ORDER BY key)
   FROM jsonb_object_keys(payload) AS key) AS payload_keys
FROM public.catalog_clients
WHERE jsonb_typeof(payload) = 'object'
LIMIT 5;
```

```sql
SELECT
  'orders' AS source,
  jsonb_typeof(payload) AS payload_type,
  (SELECT jsonb_agg(key ORDER BY key)
   FROM jsonb_object_keys(payload) AS key) AS payload_keys
FROM public.orders
WHERE jsonb_typeof(payload) = 'object'
LIMIT 5;
```

Si una tabla contiene cero filas o payloads que no son objetos, informar ese resultado; no sustituirlo por datos inventados.

## 8. Conteos para verificar futura migración

```sql
SELECT 'catalog_items' AS table_name, count(*) AS row_count FROM public.catalog_items
UNION ALL
SELECT 'catalog_clients', count(*) FROM public.catalog_clients
UNION ALL
SELECT 'catalog_import_rows', count(*) FROM public.catalog_import_rows
UNION ALL
SELECT 'inventory_current', count(*) FROM public.inventory_current
UNION ALL
SELECT 'orders', count(*) FROM public.orders
UNION ALL
SELECT 'profiles', count(*) FROM public.profiles
UNION ALL
SELECT 'seller_assignments', count(*) FROM public.seller_assignments;
```

Los conteos son metadatos operativos. Confirmar que corresponden exclusivamente al entorno DEMO.

## 9. Qué resultados compartir primero

Para continuar con seguridad, compartir en este orden:
1. Resultado de la consulta 1 (columnas exactas).
2. Resultado de la consulta 2 (constraints).
3. Resultado de la consulta 6 (forma de inventario).
4. Resultados de la consulta 7 (claves JSONB, sin valores).
5. Resultado de la consulta 8 (conteos DEMO).

Las consultas 3, 4 y 5 pueden enviarse después si hay dependencias o triggers adicionales.

## 10. Límites

- No ejecutar ninguna migración basándose solo en este documento.
- No pegar credenciales, JWT, claves API, datos personales ni payloads completos.
- No ejecutar estas consultas en Ko'eju de producción.
- El resultado de estas consultas no sustituye pruebas de RLS con sesiones reales.

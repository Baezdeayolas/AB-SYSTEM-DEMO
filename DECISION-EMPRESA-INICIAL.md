# Decisión de arquitectura: empresa inicial de AB SYSTEM DEMO

**Estado:** confirmada por el usuario  
**Fecha de registro:** 2026-11-17  
**Entorno:** exclusivamente AB SYSTEM DEMO

## Decisión

La primera empresa que representará los datos comerciales actuales de la base DEMO será **Ko’ẽju**.

## Alcance de la asignación inicial

Durante la futura migración, y únicamente después de aprobar y ejecutar un plan de migración revisado, los registros comerciales existentes de DEMO se asociarán a la empresa Ko’ẽju:

- 5 registros de `catalog_items`
- 4 registros de `catalog_clients`
- 1 registro de `orders`
- 0 registros de `catalog_import_rows`
- 1 fila contenedora de `inventory_current`, cuyo array `items` está vacío

Los perfiles y asignaciones de vendedores requieren un mapeo explícito de membresías. No se debe asignar automáticamente a todos los usuarios ni inferir roles o permisos a partir de los conteos.

## Reglas que se mantienen

1. Ko’ẽju será la primera empresa, no la única empresa ni un privilegio global.
2. Se podrán registrar otras empresas independientes en AB SYSTEM.
3. Los productos y clientes podrán repetir códigos entre empresas; la unicidad será por empresa.
4. Los pedidos conservarán su propietario y se asociarán también a la empresa correspondiente.
5. El superadministrador global será una identidad/atribución separada de los roles de cada empresa y estará protegido en backend/RLS.
6. El inventario se implementará por empresa y producto, con historial append-only de movimientos y operaciones transaccionales.
7. Los registros existentes se conservarán. No se borrarán ni reinicializarán tablas para facilitar la migración.

## Próximo trabajo autorizado

Preparar y revisar en la rama `work/ab-system-multempresa-ui` el diseño técnico y un borrador SQL de migración para DEMO, con:
- esquema objetivo y claves compuestas por empresa;
- mapeo propuesto de los datos actuales a Ko’ẽju;
- estrategia de membresías para los dos perfiles existentes, pendiente de confirmar sus identidades y funciones;
- inventario normalizado y movimientos;
- políticas RLS y permisos;
- validaciones previas/posteriores y plan de reversión.

## Límites de ejecución

Esta confirmación **no autoriza ejecutar SQL ni modificar Supabase**. No ejecutar migraciones, DDL, DML, GRANT, REVOKE ni cambios de políticas sin mostrar antes el script completo y recibir aprobación explícita para ejecutarlo.

No modificar producción, no abrir/fusionar PR y no publicar sin autorización explícita.

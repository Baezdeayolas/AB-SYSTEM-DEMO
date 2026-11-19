# ETAPA 2D-17 — Lote 4: privilegios mínimos de tablas

**Estado:** borrador de revisión; no ejecutado.  
**Dependencia:** Lotes 1, 2 y 3 aplicados y probados en AB-SYSTEM-DEMO.

## Archivo

`sql/ETAPA-2D-17-LOTE-4-PRIVILEGIOS-MINIMOS-DRAFT.sql`

## Propuesta

- Retirar privilegios de tabla a `PUBLIC`, `anon` y `authenticated` en las diez tablas auditadas.
- Conceder a `authenticated` solo los verbos necesarios para que RLS aplique las reglas de empresa.
- `profiles`: solo SELECT.
- `inventory_current`: sin acceso directo de cliente mientras siga siendo una fila global legacy sin `company_id`.
- Mantener sin cambios `service_role`, funciones, secuencias y ACL predeterminadas.

## Guardas

- comprueba existencia de roles;
- aborta si detecta privilegios por columna que requieren tratamiento explícito;
- al final comprueba que `anon` y `PUBLIC` no conserven privilegios de tabla en los objetos incluidos;
- incluye policies de escritura de empresas reservadas al superadmin global;
- termina en `ROLLBACK`.

## No incluido

No corrige todavía ACL predeterminadas para objetos futuros, ACL de secuencias, EXECUTE de funciones ni grants de otros objetos. Se deben tratar en un lote aparte, porque la auditoría previa mostró permisos heredados amplios y es necesario identificar roles creadores y dependencias.

No ejecutar hasta restauración de respaldo probada, aplicación y pruebas de Lotes 1-3, revisión de ACL por columna y aprobación explícita. No ejecutar en Ko'eju histórico/producción.


## Corrección de auditoría — 2026-11-17

Se corrigió la verificación final para identificar correctamente los privilegios concedidos a PUBLIC. La revisión confirma que este lote sigue siendo insuficiente para cerrar la seguridad: no corrige ACL por defecto, secuencias ni EXECUTE de funciones. Esos permisos requieren un lote independiente con inventario y pruebas de dependencias; no se revocarán a ciegas.

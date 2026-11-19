# ETAPA 2D-20 — Lote 6: ACL de funciones, secuencias y privilegios por defecto

**Destino:** AB-SYSTEM-DEMO exclusivamente.  
**Estado:** borrador de revisión; termina en ROLLBACK.

## Qué corrige

El Lote 4 reduce privilegios de tablas, pero no cerraba la superficie de funciones ni los privilegios por defecto. Este lote:
- revoca EXECUTE de anon/PUBLIC en helpers y RPCs;
- deja los helpers de autorización y RPCs comerciales disponibles a authenticated;
- impide invocar directamente funciones legacy y funciones de trigger;
- revoca privilegios actuales de secuencias en public a PUBLIC/anon/authenticated;
- endurece default privileges de tablas y secuencias en public para objetos futuros creados por postgres y supabase_admin;
- revoca EXECUTE por defecto a anon/authenticated en public y a PUBLIC globalmente para funciones creadas por esos dos roles.

## Alcance que requiere atención

La revocación global de EXECUTE por defecto a PUBLIC para funciones nuevas creadas por postgres/supabase_admin afecta todos los esquemas de esos creadores, no solamente public. Se incluye porque PostgreSQL no permite neutralizar un grant global de EXECUTE a PUBLIC mediante un revoke limitado a un esquema.

Antes de habilitar COMMIT se debe revisar si hay procesos de Supabase que dependan de que esos roles creen funciones nuevas ejecutables por PUBLIC. El lote aborta si el ejecutor no tiene autoridad para modificar los default privileges de ambos roles.

## Dependencias

Requiere Lotes 3 y 5, porque verifica las funciones de triggers y RPCs que estos crean. Mantiene los grants directos preexistentes de service_role; no revoca privilegios a service_role.

## Validaciones

El preflight exige roles anon, authenticated y service_role, además de todas las funciones esperadas. La verificación final exige que las funciones enumeradas no tengan EXECUTE para PUBLIC ni anon.

## No ejecutado

No se modificó ningún ACL de Supabase. El archivo sigue terminando en ROLLBACK y requiere revisión explícita antes de aplicar.

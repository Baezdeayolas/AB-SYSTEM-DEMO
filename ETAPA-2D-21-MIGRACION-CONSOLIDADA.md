# ETAPA 2D-21 — Migración multiempresa DEMO consolidada

**Rama:** `work/adaptacion-multiempresa-v1`  
**Archivo SQL:** `sql/ETAPA-2D-21-MIGRACION-MULTIEMPRESA-DEMO-CONSOLIDADA-DRAFT.sql`  
**Estado:** ensayo consolidado; termina en `ROLLBACK`.

## Objetivo

Evitar que el usuario tenga que ejecutar seis lotes por separado. Este archivo reúne en una única transacción los cambios de:
1. esquema empresarial y backfill a KOEJU;
2. claves compuestas y unicidad por empresa;
3. RLS, triggers de protección y asignaciones;
4. grants mínimos de tablas;
5. inventario normalizado y RPC de importación;
6. ACL de funciones, secuencias y default privileges.

## Resultado esperado si el ensayo pasa

- Los datos actuales quedan asociados a la empresa KOEJU.
- Los códigos de productos/clientes pueden repetirse entre empresas.
- Los pedidos mantienen su UUID como PK y la unicidad legacy queda dentro de cada empresa.
- Los vendedores y administradores quedan limitados a su empresa.
- Los pedidos no descuentan ni reservan stock.
- El inventario se consulta por empresa/producto y mantiene historial de movimientos.
- La importación masiva actualiza o crea artículos, pero nunca elimina los que no aparecen en el archivo.
- Los privilegios de tablas, funciones y secuencias se reducen según los roles definidos.

## Límites y condiciones de seguridad

- Solo para el proyecto Supabase AB-SYSTEM-DEMO.
- No ejecutar en Ko’ẽju histórico/producción.
- El archivo finaliza en ROLLBACK; por diseño no persiste cambios.
- No cambiar ROLLBACK por COMMIT sin revisar el resultado del ensayo y aprobar expresamente.
- La revocación global del EXECUTE por defecto a PUBLIC para funciones futuras creadas por postgres/supabase_admin afecta todos los esquemas de esos creadores. Está documentada en el Lote 6 y requiere aceptar ese alcance.
- La migración aborta si no existe exactamente una empresa KOEJU, si pedidos/asignaciones no pertenecen a vendedores activos, si inventory_current no está vacío como se documentó o si payload.sc no es numérico/no negativo.
- No modifica datos ni esquema de Ko’ẽju de producción.

## Validación estática realizada

Se consolidó el contenido de los seis lotes y se verificó automáticamente:
- una sola instrucción BEGIN y una sola ROLLBACK final;
- ningún COMMIT;
- delimitadores dollar-quote balanceados;
- ninguna función PL/pgSQL con apertura AS $ simple;
- seis funciones nuevas de trigger/RPC incluidas.

Esta validación es estática. **No equivale a ejecutar el SQL en PostgreSQL ni a probar RLS con JWT.** No se ha ejecutado en Supabase ni en una copia local del esquema completo.

## Lo que falta para autorizar la ejecución real

1. Ensayar este único archivo en el SQL Editor del proyecto AB-SYSTEM-DEMO y revisar el resultado completo.
2. Si el ensayo pasa, revisar la salida de verificación y el alcance de default privileges.
3. Con autorización explícita, cambiar únicamente el ROLLBACK final por COMMIT y ejecutar una sola vez.
4. Probar acceso con sesiones reales de superadmin, company_admin, seller y usuario sin membresía, incluyendo intentos cruzados entre dos empresas.
5. Conectar el parser/selector de Excel del frontend con `ab_import_company_catalog`; la RPC ya está preparada, la interfaz de importación aún no.

No se publicó ni se fusionó la rama. No se modificó Supabase.

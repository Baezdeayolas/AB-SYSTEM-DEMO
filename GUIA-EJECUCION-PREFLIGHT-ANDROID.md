# Guía — ejecutar el preflight AB SYSTEM DEMO desde Android

**Objetivo:** obtener únicamente metadatos del esquema y conteos de la base DEMO existente.  
**Importante:** no ejecutar en Ko’ẽju producción.

## Antes de comenzar
- Confirmar que el proyecto abierto en Supabase sea el proyecto DEMO independiente.
- No compartir contraseñas, claves API, tokens ni capturas que los muestren.
- El SQL de esta guía es de solo lectura: contiene consultas SELECT y no modifica tablas ni registros.

## Pasos desde el celular
1. Abrir el panel de Supabase e ingresar al proyecto AB-SYSTEM-DEMO.
2. En el menú del proyecto, abrir **SQL Editor**.
3. Elegir **New query**.
4. En otra pestaña, abrir el archivo [preflight ABDEMO](sql/ETAPA-2D-23-PREFLIGHT-ABDEMO-SOLO-LECTURA.sql).
5. Copiar todo el contenido del archivo y volver al SQL Editor.
6. Pegar el contenido completo en la consulta nueva.
7. Revisar el nombre del proyecto antes de ejecutar: debe ser el DEMO, nunca Ko’ẽju producción.
8. Pulsar **Run**.
9. Revisar los resultados de las consultas 1 a 7. Si el panel muestra varias tablas de resultados, recorrerlas todas.
10. Compartir aquí los resultados o capturas. Este preflight devuelve estructura, restricciones, índices, identificadores técnicos de empresa, resumen de membresías y conteos; no consulta nombres, teléfonos ni domicilios de clientes.

## Si aparece un error
- No intentar corregir ni ejecutar migraciones por cuenta propia.
- Copiar el texto exacto del error y decir qué consulta (1 a 7) estaba ejecutándose.
- Si una consulta falla, compartir también los resultados anteriores que sí aparecieron.

## Qué haremos con los resultados
Verificar el esquema real, el código y UUID de la empresa inicial, las restricciones, las membresías y las cantidades actuales. Después prepararemos una migración específica para AB SYSTEM DEMO. No se aplicará ningún cambio hasta revisar el SQL completo y contar con aprobación expresa.

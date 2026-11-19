# ETAPA 2D-28 — Endurecimiento de administración multiempresa

**Estado:** cambios de código preparados en la rama de desarrollo; pendientes de pruebas y despliegue.
**Alcance:** exclusivamente `AB-SYSTEM-DEMO`.
**Ko’ẽju producción:** no se modificó.

## Cambios realizados

1. La creación de empresas desde la interfaz ahora llama a la Edge Function protegida `admin-users`, en vez de insertar directamente desde el navegador.
2. La activación y suspensión de empresas también pasan por la Edge Function.
3. La Edge Function valida nuevamente que el solicitante tenga el rol `superadmin_global` antes de ejecutar estas acciones con privilegios de servidor.
4. El servidor valida nombre, código y estado; normaliza el código a mayúsculas y devuelve un conflicto claro si ya existe.
5. Al suspender la empresa activa, el frontend vuelve a cargar el contexto y limpia los datos de la empresa anterior antes de mostrar otra empresa disponible.
6. La validación SQL de duplicados del importador ahora contempla espacios externos, mayúsculas/minúsculas y equivalencias Unicode NFKC, alineándose con la validación del frontend. El código original se conserva al almacenarlo.

## Commits

- Frontend y recarga del contexto: `d1473c313012158ebf6099866f97bfae6c295ac3`
- Edge Function de administración: `e13e5711d7cdf1a9dc1b41b7c2d0da1cc2c4aafe`
- Validación duplicados en importador SQL: `3e2ace9602de559e79b90a14e14098d250f74436`

## Verificación pendiente

- No hay ejecuciones de GitHub Actions asociadas a estos commits.
- No se ejecutó compilación TypeScript/Deno ni prueba de navegador.
- La Edge Function modificada todavía requiere despliegue aprobado en el proyecto Supabase DEMO.
- Las migraciones SQL y la copia de catálogo/clientes no se ejecutaron.
- No se realizaron cambios en Supabase ni se publicó la aplicación.

## Próxima secuencia segura

1. Revisar y probar la Edge Function en un entorno de prueba.
2. Con aprobación específica, desplegar `admin-users` en Supabase AB-SYSTEM-DEMO.
3. Probar creación, suspensión/reactivación e invitaciones con una cuenta superadministradora autorizada.
4. Continuar con respaldo restaurable, migración multiempresa y carga de datos sintéticos antes de cualquier publicación.

**Reglas preservadas:** Ko’ẽju producción permanece fuera de alcance; los pedidos no descuentan stock; CENTRAL y CDE permanecen separados; los productos ausentes del Excel no se eliminan.

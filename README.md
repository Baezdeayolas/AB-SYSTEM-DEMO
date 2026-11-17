# AB SYSTEM DEMO

Entorno independiente para construir y validar la plataforma común AB SYSTEM antes de cualquier cambio en producción.

## Componentes actuales en la rama de trabajo

- `index.html`: estructura DEMO con acceso, cabecera comercial, paneles de búsqueda, pedido, archivo, resumen, stock y administración.
- `cloud-sync-demo.js`: autenticación Supabase DEMO, lectura de catálogo/clientes, asignaciones de vendedor y guardado/consulta básica de pedidos.
- `data-demo.js`: catálogo y clientes ficticios de respaldo.
- `style.css`: estilos de referencia y adaptaciones.
- `service-worker.js`: caché independiente de DEMO.

## Estado de validación

La reconstrucción de estructura y navegación está en curso en la rama `work/ab-system-multempresa-ui`. No se considera lista para publicar.

Pendiente de verificar en un entorno de prueba:
- Compatibilidad de las consultas con las columnas reales de Supabase DEMO.
- Inicio/cierre de sesión y perfiles `admin` / `seller`.
- Lectura de catálogo, clientes y asignaciones.
- Guardado y lectura de pedidos, incluidas las políticas RLS.
- Flujo completo en móvil y escritorio y comparación visual con Ko'eju.
- Generación/compartir PDF y escáner, que todavía son marcadores pendientes.
- Alta de clientes, edición de pedidos, gestión real de stock y selector multiempresa.

No se ha ejecutado una prueba integral de navegador ni una auditoría de RLS. La existencia de código para una función no implica que haya sido validada.

## Arquitectura multiempresa

La arquitectura objetivo está documentada en `ARQUITECTURA-MULTIEMPRESA.md`. La matriz visual y su estado se describen en `MATRIZ-AB-SYSTEM.md`. El selector de empresa y los roles globales todavía no están implementados.

## Seguridad y límites

- No importar clientes, vendedores, precios, pedidos ni credenciales reales de Ko'eju.
- No copiar scripts de producción ni secretos al frontend.
- No modificar el repositorio ni Supabase de producción.
- No ejecutar migraciones en Supabase DEMO hasta contrastar el esquema existente.
- Mantener RLS y validar los permisos en backend; los filtros del navegador no son una barrera de seguridad.
- No fusionar ni publicar esta rama hasta completar las pruebas de autenticación, permisos, aislamiento entre empresas y comparación visual.

## Datos DEMO

Los catálogos de Supabase DEMO (`catalog_items` y `catalog_clients`) reemplazan los datos ficticios de respaldo al iniciar sesión, siempre que las consultas y sus columnas coincidan con el esquema configurado. Este entorno debe utilizar exclusivamente datos sintéticos.

# AB SYSTEM DEMO

Entorno independiente para construir y validar la plataforma común AB SYSTEM antes de cualquier cambio en producción.

## Componentes actuales
- `index.html`: acceso y estructura comercial DEMO actual.
- `cloud-sync-demo.js`: autenticación y conexión exclusiva al Supabase DEMO.
- `data-demo.js`: catálogo ficticio de respaldo.
- `style.css`: estilos de referencia y adaptaciones actuales.
- `service-worker.js`: caché independiente de DEMO.

## Trabajo en curso
La estructura actual de `index.html` todavía no replica la navegación y los paneles de Ko'eju. La reconstrucción visual y funcional está pendiente; no debe considerarse terminada por tener una hoja de estilos similar.

La arquitectura multiempresa objetivo está documentada en `ARQUITECTURA-MULTIEMPRESA.md`. La matriz visual y su estado se describen en `MATRIZ-AB-SYSTEM.md`.

## Seguridad
- No importar clientes, vendedores, precios, pedidos ni credenciales reales de Ko'eju.
- No copiar scripts de producción ni secretos al frontend.
- No modificar el repositorio ni Supabase de producción.
- Mantener RLS y validar los permisos en backend.
- No publicar la nueva versión hasta completar pruebas de autenticación, permisos, aislamiento entre empresas y comparación visual.

## Datos DEMO
Los catálogos de Supabase DEMO (`catalog_items` y `catalog_clients`) reemplazan los datos ficticios de respaldo al iniciar sesión. Este entorno debe utilizar exclusivamente datos sintéticos.

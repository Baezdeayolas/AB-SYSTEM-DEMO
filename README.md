# AB SYSTEM DEMO

Primera versión de la plataforma de demostración comercial, separada de la aplicación principal.

## Componentes
- `index.html`: pantalla de acceso y panel comercial.
- `cloud-sync-demo.js`: autenticación y conexión exclusiva al proyecto Supabase DEMO.
- `data-demo.js`: catálogo ficticio de respaldo.
- `style.css`: interfaz adaptable a móviles y escritorio.
- `service-worker.js`: caché independiente de DEMO.

## Seguridad
- No importar clientes, vendedores, precios ni pedidos reales de Ko’ẽju.
- No configurar claves `service_role` ni secretos en el navegador.
- Las tablas deben conservar RLS activado.
- No habilitar publicación hasta completar pruebas de autenticación, permisos y sincronización.

## Datos DEMO
Los catálogos de Supabase (`catalog_items` y `catalog_clients`) reemplazan los datos ficticios de respaldo al iniciar sesión.

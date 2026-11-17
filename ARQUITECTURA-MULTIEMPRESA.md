# Arquitectura objetivo — AB SYSTEM multiempresa

Estado: propuesta de diseño para DEMO. No representa una migración ejecutada ni una auditoría de RLS.

## Decisiones confirmadas
- AB SYSTEM tendrá una sola interfaz y una sola plataforma.
- La cuenta del propietario será Superadministrador global.
- Cada empresa tendrá sus propios administradores, vendedores y datos.
- Ko'eju de producción y su Supabase quedan fuera de este trabajo.
- Las pruebas se realizan únicamente con datos ficticios en AB-SYSTEM-DEMO.

## Roles y alcance
| Rol | Alcance |
| --- | --- |
| superadmin_global | Todas las empresas; crear y administrar empresas, membresías y configuración global. |
| company_admin | Una empresa; administrar usuarios y operaciones de esa empresa. |
| seller | Una empresa y únicamente los vendedores/asignaciones que tenga autorizados. |

El rol global no debe inferirse de un campo editable por el navegador. Debe verificarse en el backend mediante una asignación global protegida.

## Modelo de datos objetivo (pendiente de contrastar con el esquema real)
- companies: empresas, estado y datos básicos.
- global_roles: asignaciones globales de usuarios, reservada al backend.
- company_memberships: relación usuario-empresa y rol dentro de esa empresa.
- seller_assignments: asignaciones de vendedor vinculadas a empresa y usuario.
- orders: cada pedido pertenece obligatoriamente a una empresa.
- catalog_items, catalog_clients, inventory_current y catalog_import_rows: cada registro pertenece obligatoriamente a una empresa.

Las tablas existentes deben revisarse antes de cualquier ALTER/CREATE. No ejecutar este modelo como SQL hasta confirmar columnas, claves, relaciones, políticas y funciones actuales.

## Reglas de aislamiento
1. Toda consulta de negocio se limita a la empresa activa y autorizada.
2. El backend obtiene la empresa permitida desde la sesión/membresía validada; no confía únicamente en un company_id enviado por el cliente.
3. RLS debe cubrir SELECT, INSERT, UPDATE y DELETE en cada tabla de negocio.
4. Un administrador de empresa no puede leer ni modificar otra empresa.
5. Un vendedor solo accede a su empresa y a sus asignaciones.
6. El superadministrador global accede a varias empresas mediante una política explícita y auditada.
7. No colocar service_role ni secretos en archivos frontend.

## Orden de implementación
1. Reconstruir la estructura HTML y navegación de Ko'eju en DEMO, manteniendo los controladores y datos DEMO independientes.
2. Añadir selector de empresa y un estado visible de empresa activa.
3. Inspeccionar el esquema Supabase DEMO y diseñar migración compatible.
4. Implementar empresas, membresías y roles en DEMO.
5. Aplicar RLS y probar con dos empresas ficticias, un superadmin, dos administradores y vendedores.
6. Probar intentos cruzados de lectura/escritura y confirmar que no hay fuga de datos.
7. Comparar capturas móvil/escritorio y revisar el flujo completo antes de publicar.

## Criterios para considerar lista la DEMO
- La interfaz sigue la matriz Ko'eju en estructura, navegación, densidad y estilo.
- Login, catálogo, clientes, pedidos, archivo, stock y administración funcionan con datos DEMO.
- Cambiar de empresa cambia el contexto y nunca mezcla datos.
- Los permisos se hacen cumplir por RLS, no solo por filtros de interfaz.
- Pruebas negativas confirman el aislamiento entre empresas.
- Ningún cambio toca el repositorio ni Supabase de producción.

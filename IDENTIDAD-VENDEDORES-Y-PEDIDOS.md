# Identidad de vendedores y propiedad de pedidos

Estado: especificación para implementar en DEMO. No ejecuta SQL ni cambia permisos.

## Objetivo

Separar tres conceptos: actor (usuario autenticado que realiza la operación), propietario comercial (vendedor responsable, orders.owner_id) y empresa (company_id).

## Fuente de identidad del vendedor

La identidad debe salir de una membresía activa, nunca de un nombre escrito ni de un UUID enviado libremente por el navegador.

1. Obtener las membresías activas del usuario en la empresa seleccionada desde company_memberships.
2. Para un administrador, listar usuarios con membresía activa seller en esa misma empresa.
3. Resolver el nombre visible mediante profiles.seller_label; usar un texto neutro si está vacío.
4. En el selector HTML, usar company_memberships.user_id como valor y el nombre como etiqueta.
5. Antes de guardar, backend/RLS vuelve a validar que el usuario seleccionado tenga membresía activa seller en el mismo company_id.

La lista del navegador solo facilita la selección; nunca autoriza la operación.

## Reglas de creación de pedidos

### Vendedor autenticado
- owner_id = auth.uid().
- created_by = auth.uid().
- company_id debe corresponder a una membresía seller activa del usuario.
- No puede suplantar a otro vendedor.

### Administrador de empresa que registra en nombre de un vendedor
- owner_id = UUID del vendedor seleccionado.
- created_by = auth.uid() del administrador que actuó.
- company_id es la empresa de la membresía activa del administrador.
- Backend verifica que el vendedor seleccionado tenga membresía activa seller en esa misma empresa.

### Superadministrador global
- Opera en el contexto de una empresa seleccionada.
- owner_id sigue siendo el vendedor real seleccionado cuando el pedido se registra a nombre de un vendedor.
- created_by = auth.uid().
- Backend valida que la empresa esté activa y que el propietario sea vendedor de esa empresa.

## Cambios de esquema requeridos

- Añadir orders.company_id uuid NOT NULL con FK a companies(id).
- Añadir orders.created_by uuid con FK a auth.users(id). En el backfill histórico puede ser NULL si no se puede reconstruir el actor original. Para pedidos nuevos debe ser obligatorio mediante política/función/trigger.
- Conservar orders.owner_id y su FK actual.
- Conservar payload y el precio histórico de cada línea.
- Revisar la unicidad actual de pedidos antes de cambiarla.

## Lectura de pedidos

- Vendedor: solo filas de su empresa con owner_id = auth.uid().
- Administrador: todas las filas de su empresa.
- Superadministrador global: todas las empresas activas, sujeto a política global.
- No conceder al vendedor acceso por created_by = auth.uid(); registrar un pedido para un vendedor no cambia su propietario comercial.

## Edición y eliminación

- Un vendedor solo modifica/elimina sus propios pedidos, sujeto al estado del pedido.
- Un administrador gestiona pedidos de su empresa.
- El superadministrador gestiona según reglas globales.
- Toda modificación sensible registra actor y fecha; no confiar en campos de auditoría enviados por el cliente.

## Interfaz

- El selector guarda UUID como valor y muestra nombre como texto.
- Para vendedor, selector fijado a su propia identidad o no visible.
- Para administrador, selector muestra solo vendedores activos de su empresa.
- Al cambiar de empresa, limpiar vendedor, cliente, carrito y estado temporal.
- Si membresías o created_by no están disponibles, bloquear el guardado multiempresa; nunca volver silenciosamente al comportamiento antiguo.

## Criterios de aceptación

1. Admin crea pedido para Vendedor A: owner_id=A y created_by=admin.
2. Vendedor A ve el pedido; Vendedor B no.
3. Admin de otra empresa no ve ni modifica el pedido.
4. UUID de vendedor de otra empresa falla en backend/RLS.
5. Vendedor no puede asignar otro owner_id.
6. Pedidos históricos conservan valores y no se atribuye falsamente su actor original.
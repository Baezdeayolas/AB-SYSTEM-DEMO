# Decisión de arquitectura: empresa inicial de AB SYSTEM DEMO

**Estado:** actualizada y confirmada por el usuario  
**Fecha de actualización:** 2026-11-18  
**Entorno:** exclusivamente AB SYSTEM DEMO  
**Esta decisión sustituye la decisión anterior que identificaba a Ko’ẽju como empresa inicial.**

## Decisión

La empresa que representará los datos comerciales de demostración será **AB SYSTEM DEMO**. La empresa que actualmente figura con código `KOEJU` en la base DEMO se convertirá en esta empresa de demostración, conservando su catálogo y aprovechando sus registros de clientes como base de demostración.

Esto no convierte a Ko’ẽju producción en parte de AB SYSTEM. Ko’ẽju conserva su repositorio, su Supabase y su operación independientes. No se copiarán credenciales, perfiles de acceso ni dependencias de producción.

## Conservación y tratamiento de datos

- **Productos:** conservar los registros y campos del catálogo existente, incluidos códigos, descripciones, categorías, códigos de barras y listas de precios, sujeto a revisión de que no contengan datos confidenciales de proveedores.
- **Clientes:** conservar la estructura, códigos y campos comerciales útiles para que la DEMO tenga un catálogo de clientes representativo. Antes de exponer la DEMO a terceros, anonimizar nombres identificables de personas, teléfonos, direcciones particulares, RUC/identificadores personales y cualquier otro dato que permita identificar a clientes reales. No publicar ni habilitar acceso público a datos personales reales.
- **Pedidos:** revisar y anonimizar los datos de clientes, vendedores y cualquier referencia identificable. Conservar únicamente registros que sean apropiados como ejemplos de demostración.
- **Usuarios, perfiles y membresías:** no reutilizar credenciales ni identidades de Ko’ẽju. Mapear los perfiles existentes manualmente y crear accesos DEMO propios.
- **Inventario:** conservar cantidades solo si su procedencia y significado se verifican. Los saldos CENTRAL y CDE se mantienen separados; no inferir cantidades de una estructura legacy vacía.

## Alcance de la asignación inicial

El diagnóstico previo registró en la base DEMO:
- 5 filas de `catalog_items`;
- 4 filas de `catalog_clients`;
- 1 fila de `orders`;
- 0 filas de `catalog_import_rows`;
- 1 fila contenedora de `inventory_current`, con array `items` vacío;
- 2 perfiles y 1 asignación de vendedor, cuyo mapeo requiere revisión explícita.

Estos conteos son históricos y deben volver a verificarse en la base actual antes de cualquier cambio.

## Reglas que se mantienen

1. AB SYSTEM DEMO es una empresa normal dentro de la arquitectura multiempresa, no un privilegio global.
2. Se podrán registrar otras empresas independientes.
3. Los productos y clientes podrán repetir códigos entre empresas; la unicidad será por empresa.
4. Los pedidos conservarán su propietario y se asociarán también a la empresa correspondiente.
5. El superadministrador global será una identidad/atribución separada de los roles de cada empresa y estará protegido en backend/RLS.
6. El inventario se implementará por empresa, producto y depósito, con historial de movimientos y operaciones transaccionales.
7. Guardar un pedido no factura, no reserva y no descuenta existencias.
8. Importar un catálogo puede crear o actualizar productos, pero nunca eliminar los productos ausentes del archivo.
9. Ko’ẽju producción y su base de datos no se modificarán.

## Trabajo autorizado

1. Auditar el código, la rama y el esquema actual de AB SYSTEM DEMO.
2. Adaptar la identidad inicial de empresa de `KOEJU` a `ABDEMO` o a un código DEMO estable, revisando todas las dependencias antes de elegir el valor definitivo.
3. Preparar una migración revisable que conserve los registros válidos, anonimice los datos personales de clientes/pedidos destinados a demostración y mantenga las relaciones multiempresa.
4. Adaptar documentación, datos de muestra y frontend para que la DEMO no dependa de Ko’ẽju.
5. Probar aislamiento entre AB SYSTEM DEMO y una segunda empresa ficticia.

## Límites de ejecución

Esta decisión autoriza el trabajo de auditoría y preparación de cambios en la rama de desarrollo. **No autoriza ejecutar SQL ni modificar la base Supabase, borrar datos, cambiar permisos/RLS, fusionar a `main` ni publicar.**

Antes de cualquier operación sobre Supabase:
- verificar y documentar un respaldo restaurable;
- confirmar el proyecto destino y su identificador;
- mostrar el SQL completo y explicar sus efectos;
- recibir aprobación explícita para ejecutar ese SQL;
- comprobar los resultados y probar aislamiento entre empresas.

No modificar Ko’ẽju producción ni su repositorio bajo ninguna circunstancia.

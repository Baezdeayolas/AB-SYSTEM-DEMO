# ETAPA 2D-12 — Correcciones de frontend multiempresa y estado de avance

Fecha: 2026-11-17  
Repositorio: `Baezdeayolas/AB-SYSTEM-DEMO`  
Rama: `work/adaptacion-multiempresa-v1`

## 1. Correcciones realizadas

En `cloud-sync-demo.js`:

1. Se conectó el evento `change` de `#company-select` con `switchCompany()`. Antes el selector se renderizaba, pero cambiar su valor no ejecutaba el cambio de contexto.
2. Durante el cambio se deshabilita temporalmente el selector para evitar cambios concurrentes.
3. Si la carga de la empresa nueva falla, se restaura la empresa anterior y se intenta recargar su información.
4. Se evita el doble envío del mismo pedido deshabilitando el botón durante el guardado.
5. El resumen del archivo calcula y muestra la suma de los importes de los pedidos cargados.

Se actualizó `README.md` para reflejar estos cambios y los bloqueos que siguen vigentes.

## 2. Reglas funcionales conservadas

- Crear un pedido no factura, no descuenta stock y no reserva existencias.
- `owner_id` representa al vendedor al que pertenece el pedido.
- `created_by` representa al usuario que registró el pedido.
- El selector de empresa es contexto de interfaz; la autorización real debe imponerse mediante RLS y validaciones backend.
- Los datos de Ko’ẽju producción y su proyecto Supabase no se modifican.

## 3. Estado del respaldo DEMO

En esta etapa se generaron respaldos lógicos custom del esquema `public` de los dos proyectos Supabase y se verificó que ambos archivos pueden enumerarse mediante `pg_restore --list`.

- `AB-SYSTEM-DEMO.backup`: generado y listado verificado.
- `KOEJU-HISTORICO.backup`: generado y listado verificado.

Ambos se copiaron a la carpeta privada de respaldos del usuario en Google Drive. **No se ha probado una restauración** y estos archivos son respaldos del esquema `public`; no se deben presentar como una restauración validada ni como copia integral de Auth/Storage.

## 4. Bloqueos que siguen abiertos

1. El esquema activo todavía no tiene `company_id` en las tablas comerciales ni `created_by` en `orders`; el frontend adaptado no puede ejecutarse correctamente contra ese esquema.
2. No se ha probado restauración en un entorno aislado. La cuenta tiene límite de dos proyectos Supabase y no se debe pedir crear un tercero ni modificar los proyectos existentes para simularlo.
3. La empresa existente en DEMO aparece con código `KOEJU`. Debe preservarse esa identidad. La empresa `DEMO` para prospectos debe crearse como una empresa separada, después de verificar el destino de los cinco artículos/clientes de prueba.
4. Faltan pruebas de RLS/JWT para superadministrador, administrador, vendedor y usuario sin membresía.
5. Falta revisar constraints, índices, claves foráneas y políticas antiguas permisivas antes de diseñar la migración.
6. Falta inventariar escritores externos, Edge Functions, webhooks y trabajos programados.
7. Faltan las funciones completas de paridad con Ko’ẽju: importación Excel, PDF, edición/reutilización de pedidos y administración de usuarios.

## 5. Decisión de seguridad

No se ejecutó SQL ni se modificó Supabase. No se importaron datos. No se publicó ni fusionó la rama. No se modificó Ko’ẽju producción.

La siguiente entrega técnica debe ser un **preflight SQL de solo lectura** que compruebe el estado real de claves, restricciones, índices, políticas, datos y pertenencia de la empresa antes de redactar un lote mutante. El lote mutante solo se preparará cuando se resuelvan los bloqueos y se pueda revisar el script completo con rollback.

# Administración global AB SYSTEM DEMO

La interfaz incorpora:
- acceso público de demostración en solo lectura con datos sintéticos;
- selección de empresa después de validar credenciales;
- alta y suspensión/reactivación de empresas para el superadministrador;
- invitación por correo y asignación de vendedores o administradores;
- cambio de rol y estado de membresías.

## Función segura requerida

La interfaz usa la función Supabase Edge Function `admin-users`. Su código está en
`supabase/functions/admin-users/index.ts`. La función valida el JWT del usuario y
comprueba el rol `superadmin_global` en `public.global_roles` antes de usar
`SUPABASE_SERVICE_ROLE_KEY` en el servidor. La clave de servicio nunca se incluye
en archivos del navegador.

Para habilitar invitaciones y administración de membresías, desplegar esta función
en el proyecto DEMO `druugcvqxxanhtdkqnjd` desde un entorno autorizado con Supabase CLI:

```bash
supabase functions deploy admin-users --project-ref druugcvqxxanhtdkqnjd
```

Supabase proporciona las variables de entorno del proyecto a la función. Confirmar
que la plantilla de invitación por correo esté configurada en Authentication > Email
Templates y que el proveedor de correo permita enviar invitaciones.

## Límites

- Todo lo anterior pertenece exclusivamente a AB-SYSTEM-DEMO.
- No ejecutar migraciones ni desplegar sobre el proyecto histórico de Ko'eju.
- El modo público usa únicamente `data-demo.js`; no lee datos reales y no guarda cambios.
- La selección de empresa ocurre luego de autenticar, porque publicar el listado de
  empresas a usuarios anónimos revelaría información interna.
- El alta de empresa se protege mediante RLS; las altas de usuarios y membresías
  se ejecutan en la función de servidor.

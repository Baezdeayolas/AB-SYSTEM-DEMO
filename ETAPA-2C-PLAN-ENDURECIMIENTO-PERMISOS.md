# Etapa 2C — plan de endurecimiento de permisos (DEMO)

**Estado: PREPARACIÓN. No ejecutar cambios SQL todavía.**
Ámbito exclusivo: Supabase DEMO (`druugcvqxxanhtdkqnjd.supabase.co`) y rama `work/ab-system-multempresa-ui`. No modificar Ko’ẽju producción.

## 1. Hallazgos confirmados

- La inspección de secuencias en `public` devolvió cero objetos (`public_sequence_count = 0`).
- Las ACL predeterminadas registradas para creadores `postgres` y `supabase_admin` incluyen `anon` y `authenticated` con EXECUTE en funciones, SELECT/UPDATE/USAGE en secuencias y privilegios amplios en tablas, incluido TRUNCATE.
- Esas ACL son predeterminadas para objetos futuros; no prueban por sí solas los permisos efectivos de cada objeto existente.
- RLS no reemplaza los privilegios SQL y no protege operaciones como TRUNCATE.
- No se ha ejecutado ningún cambio de permisos como parte de esta inspección.

## 2. Objetivo

Reducir privilegios innecesarios sin romper Supabase, las funciones de autenticación, las operaciones legítimas de la aplicación ni las tareas administrativas.

## 3. Orden obligatorio de trabajo

### 2C.1 — Inventario de privilegios efectivos

Consultar, en modo solo lectura:
- privilegios efectivos por tabla/vista y rol (`anon`, `authenticated`, `service_role`);
- privilegios efectivos por función, identificando SECURITY DEFINER, propietario y EXECUTE;
- privilegios USAGE/CREATE del esquema `public`;
- políticas RLS existentes y su combinación permisiva/restrictiva;
- objetos internos o gestionados por Supabase que no deben alterarse.

Salida requerida: matriz objeto × rol × privilegio, separando permisos directos, permisos heredados y ACL predeterminadas.

### 2C.2 — Matriz objetivo

- `anon`: sin acceso a tablas/funciones de negocio salvo endpoints públicos expresamente justificados.
- `authenticated`: solo privilegios mínimos necesarios; el acceso a filas queda limitado por políticas RLS multiempresa.
- `service_role`: mantener únicamente los permisos requeridos por procesos backend confiables; nunca exponer su clave al cliente.
- `postgres` y roles administrados: conservar capacidades administrativas necesarias.
- Funciones `SECURITY DEFINER`: EXECUTE solo para roles que realmente las necesiten; `search_path` seguro y referencias calificadas.

Esta matriz es una meta de diseño, no una instrucción para aplicar REVOKE masivos.

### 2C.3 — Diseño de corrección

Preparar SQL separado y revisable para:
1. ajustar ACL predeterminadas por rol creador y tipo de objeto;
2. ajustar privilegios actuales únicamente en objetos identificados;
3. preservar funciones necesarias de Supabase/Auth y flujos de la aplicación;
4. verificar permisos después de cada cambio.

No usar `REVOKE ALL ON ALL TABLES/FUNCTIONS IN SCHEMA public` ni cambios globales indiscriminados.

### 2C.4 — Aprobación y ejecución controlada

Antes de ejecutar cualquier DDL/GRANT/REVOKE, entregar el script completo, explicar cada sentencia, enumerar objetos afectados y proponer comprobaciones posteriores. Esperar aprobación explícita del usuario. Ejecutar únicamente en Supabase DEMO.

## 4. Criterios para cerrar Etapa 2C

- ACL predeterminadas justificadas y de mínimo privilegio.
- Privilegios efectivos existentes revisados por objeto y rol.
- Ninguna política permisiva amplia que anule el aislamiento previsto.
- Funciones centrales de autorización operativas.
- Pruebas con JWT de superadmin, admin de empresa, vendedor y usuario sin membresía.
- Sin cambios en producción.

## 5. Lo que todavía no se debe hacer

- No añadir aún `company_id` a tablas comerciales ni migrar datos hasta cerrar inventario de dependencias y diseño de backfill.
- No modificar frontend para simular aislamiento multiempresa.
- No cambiar ACL de objetos gestionados por Supabase sin identificar su función.
- No ejecutar el borrador SQL multiempresa anterior.

## 6. Próximo entregable inmediato

Un inventario SQL exclusivamente de lectura que reporte privilegios efectivos actuales de tablas/vistas, funciones y esquema `public`. Ese resultado permitirá diseñar correcciones concretas en lugar de aplicar permisos genéricos.

## 7. Registro de seguridad

Los bloques A, B y C de `ETAPA-2B-VERIFICACION-SECUENCIAS-ACL-SOLO-LECTURA.sql` se ejecutaron manualmente por el usuario. El bloque C confirmó cero secuencias en `public`. No se ha aplicado ninguna corrección de ACL.
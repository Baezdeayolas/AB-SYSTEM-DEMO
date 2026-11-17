# Matriz visual oficial — AB SYSTEM

## Regla para todos los futuros proyectos
La interfaz de AB SYSTEM en Ko'eju es la referencia visual canónica. Los proyectos nuevos deben reutilizar la hoja visual y sus patrones de interfaz, sin crear una identidad alternativa.

## Elementos que deben conservarse
- Paleta, tipografías y jerarquías tipográficas originales.
- Encabezado, campos compactos, bordes, botones, paneles y estados.
- Imagen de fondo original `Icons/ventafondo.jpg` y sus tratamientos visuales.
- Navegación, densidad, espaciado y comportamiento adaptable a móvil/escritorio.
- Componentes coherentes con la interfaz de referencia.

## Separación obligatoria
La matriz visual no implica reutilizar lógica, datos, usuarios, credenciales ni bases de datos de otro proyecto. Cada proyecto conserva su propio backend, permisos, datos y funciones.

## Implementación actual en DEMO
- `style.css`: hoja de estilos de referencia original más adaptadores de estructura DEMO.
- `index.html`: estructura funcional de DEMO, con acceso y controles propios.
- Fondo: recurso visual original alojado en el repositorio de Ko'eju.
- Supabase: proyecto DEMO independiente; no modificar.
- Rama de trabajo: `demo-inicial`; PR #1 permanece sin fusionar.

## Criterio de aceptación
No declarar un futuro proyecto como clon terminado hasta comparar capturas en móvil y escritorio con la matriz, comprobar tipografía, colores, fondo, dimensiones, encabezado, controles y navegación.

# Matriz visual oficial — AB SYSTEM

## Regla para todos los futuros proyectos
La interfaz de AB SYSTEM en Ko'eju es la referencia visual canónica. Los proyectos nuevos reutilizan su estructura, navegación, hoja visual y patrones de interfaz, sin crear una identidad alternativa.

## Elementos que deben conservarse
- Paleta, tipografías y jerarquías tipográficas originales.
- Encabezado compacto con vendedor, cliente y estado de conexión.
- Selector de precio M1/M2/M3, estado del pedido y condición de venta.
- Paneles Buscar, Pedido, Archivo, Resumen, Stock y Administración.
- Navegación inferior, contador del pedido y barra inferior de total/acciones.
- Componentes, densidad, espaciado y comportamiento adaptable a móvil/escritorio.
- Imagen de fondo y tratamientos visuales originales cuando correspondan.

## Separación obligatoria
La matriz visual no implica reutilizar lógica, datos, usuarios, credenciales ni bases de datos de otro proyecto. Cada entorno conserva su propio backend, permisos, datos y funciones. La DEMO utiliza exclusivamente su Supabase y datos ficticios.

## Estado verificado
- PR #1 de DEMO fue fusionado a `main`.
- La rama de trabajo para la siguiente etapa es `work/ab-system-multempresa-ui`.
- `index.html` de DEMO todavía conserva una estructura genérica distinta de Ko'eju.
- `style.css` contiene estilos de referencia, pero los estilos por sí solos no convierten una estructura HTML distinta en una réplica.
- Supabase DEMO permanece independiente. No se ha ejecutado una migración multiempresa.
- La configuración de GitHub Pages debe verificarse por separado antes de afirmar qué rama publica.

## Criterio de aceptación
No declarar un futuro proyecto como clon terminado hasta comparar capturas en móvil y escritorio con la matriz, comprobar tipografía, colores, fondo, dimensiones, encabezado, controles, navegación y funcionamiento de cada panel.

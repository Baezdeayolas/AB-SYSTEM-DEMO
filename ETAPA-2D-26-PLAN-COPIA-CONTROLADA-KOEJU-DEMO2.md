# ETAPA 2D-26 — Plan de copia controlada KOEJU -> DEMO2

**Estado:** diseño técnico; pendiente de validación, respaldo restaurable y aprobación de ejecución.  
**Destino:** exclusivamente Supabase AB-SYSTEM-DEMO.  
**Rama:** `work/adaptacion-multiempresa-v1`.

## Decisión confirmada
DEMO2 será AB SYSTEM DEMO y conservará su UUID actual. KOEJU dentro de esta base será el origen histórico y permanecerá intacta. Ko’ẽju de producción no forma parte de este trabajo.

## Tratamiento
| Datos | Origen KOEJU | Destino DEMO2 |
|---|---|---|
| Productos (diagnóstico: 9.541) | Conservar intactos | Copiar código y payload JSONB completo |
| Clientes (diagnóstico: 3.498) | Conservar intactos | Crear registros sintéticos; no copiar PII ni datos financieros |
| Historial de importación (9.536) | Conservar | No copiar inicialmente |
| Pedido histórico (1) | Conservar | No copiar inicialmente |
| Usuarios, perfiles, membresías y asignaciones | Conservar | No copiar identidades; configurar acceso DEMO propio |
| Inventario legacy singleton | Conservar | No copiar ni inferir cantidades |
| Inventario CENTRAL/CDE | Verificar | Saldos propios, cargados con Excel aprobado |

Los conteos son del diagnóstico anterior y se deben revalidar con ETAPA 2D-25 antes de cualquier escritura.

## Productos
La copia futura insertará en DEMO2 el `code` y el objeto `payload` completo de cada producto KOEJU. No reconstruirá los campos manualmente. Antes se comprobarán códigos duplicados, payloads válidos, claves únicas por empresa y triggers de inventario. No se permitirá un UPSERT que sobrescriba productos DEMO existentes sin autorización.

## Clientes sintéticos
El frontend debe inspeccionarse para identificar los campos realmente requeridos. Se crearán códigos nuevos y estables, nombres ficticios y valores sintéticos para identificación, teléfono, ubicación y campos financieros. No se derivarán valores ficticios de los datos reales ni se trasladarán deudas/saldos.

## Inventario y pedidos
No copiar `inventory_current`, saldos legacy, pedidos ni asignaciones. CENTRAL y CDE serán saldos independientes. La primera importación Excel aprobada establecerá cantidades. Guardar un pedido no factura, reserva ni descuenta stock.

## Acceso administrativo
El diagnóstico previo indica que DEMO2 tiene una membresía seller, no company_admin. Se requiere una cuenta autorizada propia de AB SYSTEM DEMO. No reutilizar cuentas ni credenciales KOEJU. Nunca compartir claves, contraseñas o tokens.

## Pasos obligatorios
1. Ejecutar solo el SQL 2D-25 de lectura.
2. Revisar campos de clientes consumidos por frontend y definir generador sintético.
3. Obtener respaldo completo de Supabase DEMO y verificar restauración; CSV no basta.
4. Auditar políticas, triggers, funciones, grants y dependencias.
5. Preparar un ensayo transaccional con `ROLLBACK`, conteos y comprobación de que KOEJU queda intacta.
6. Presentar el SQL completo y solicitar autorización específica antes de cualquier escritura persistente.
7. Probar aislamiento entre empresas y roles antes de publicación.

No ejecutar todavía 2D-21 ni 2D-22. No cambiar esquema, datos, roles, RLS, rama principal ni publicar sin autorización separada.

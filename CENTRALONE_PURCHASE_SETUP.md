# Integración Central One — José Recargas

Esta rama prepara la compra automática de Free Fire sin modificar `main` ni reemplazar la función existente `rapid-handler`.

## Archivos agregados

- `supabase/migrations/202611260001_centralone_purchase_schema.sql`: agrega el mapeo de los seis paquetes de diamantes, referencias del proveedor, idempotencia y funciones protegidas para reservar y reintegrar saldo.
- `supabase/functions/centralone-purchase/index.ts`: nueva Edge Function con acciones `validate`, `purchase` y `sync`.

## Importante

Esto todavía NO está habilitado en producción. La página de compra del cliente aún debe invocar la nueva función y conservar el mismo código de pedido al reintentar. No hagas compras reales hasta terminar esa conexión y las pruebas.

## Despliegue manual pendiente

1. En Supabase, abrir SQL Editor y ejecutar el archivo de migración completo.
2. En Edge Functions, crear la función `centralone-purchase` y pegar el contenido de `index.ts`.
3. Confirmar que estén configurados `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` y `CENTRALONE_API_KEY` como secrets de la función. Nunca colocar estas claves en el frontend.
4. La función debe conservar la verificación JWT activada.
5. Conectar el frontend del cliente a `centralone-purchase` usando las acciones:
   - `validate`: { action, product_id, player_id }
   - `purchase`: { action, product_id, player_id, code, player_name, customer_phone }
   - `sync`: { action, order_id }

## Reglas de seguridad previstas

- Solo paquetes `d1` a `d6` pueden comprarse por esta integración.
- Se valida el ID antes de descontar saldo.
- La reserva local y el débito del cliente ocurren en una transacción SQL.
- El mismo código de pedido produce la misma clave de idempotencia en Central One.
- Los errores de red ambiguos dejan el pedido pendiente; no se reintenta con otra clave ni se reintegra por timeout.
- El reintegro solo ocurre tras consultar a Central One y confirmar el estado terminal y la liberación del dinero.
- Esta primera versión contempla una sola línea por pedido (paquetes de diamantes). No habilitar otros productos ni cantidades múltiples.

## Estado

Preparación en rama separada. No desplegado, no fusionado a `main`, sin compras ejecutadas.

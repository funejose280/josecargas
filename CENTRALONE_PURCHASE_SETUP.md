# Integración Central One — José Recargas

## Estado de esta rama

La tienda cliente ya está conectada al checkout nuevo para paquetes Free Fire d1–d6. La migración SQL fue ejecutada en Supabase y el mapeo de seis productos fue confirmado por el administrador.

Esta rama todavía no está fusionada a `main`, y la Edge Function `centralone-purchase` todavía debe desplegarse en Supabase. No se debe habilitar el checkout público antes de completar esos dos pasos.

## Archivos

- `supabase/migrations/202611260001_centralone_purchase_schema.sql`: columnas de mapeo, claves de idempotencia y RPCs seguras de débito/reintegro.
- `supabase/functions/centralone-purchase/index.ts`: Edge Function con acciones `validate`, `purchase` y `sync`.
- `public/index.html`: checkout cliente conectado a la función; permite un único paquete de diamantes por pedido.

## Paso 1 — Desplegar primero la Edge Function

En Supabase → Edge Functions, crear una función llamada exactamente `centralone-purchase` y pegar el contenido de `supabase/functions/centralone-purchase/index.ts`.

Mantener activada la verificación JWT. Configurar los secretos de servidor:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `CENTRALONE_API_KEY`

No colocar ninguna de estas claves en el HTML ni pedirle al cliente que las envíe. La llave de Central One debe tener, como mínimo, los alcances `catalog:read`, `orders:write` y `orders:read`. `player/validate` usa `catalog:read`.

## Paso 2 — Comprobación sin gastar saldo

Antes de publicar el checkout, probar únicamente la acción `validate` con un ID real de Free Fire:

```json
{
  "action": "validate",
  "product_id": "d3",
  "player_id": "ID_REAL_DEL_JUGADOR"
}
```

La respuesta debe ser `ok: true` y `status: "valid"`. `invalid` significa que el ID no corresponde; `unverified` significa que Central One no pudo comprobarlo y esta integración bloquea la compra por seguridad. Esta validación no crea pedidos ni mueve saldo.

No probar la acción `purchase` con datos ficticios: Central One no ofrece un entorno de pruebas con saldo ficticio y cada pedido real mueve saldo.

## Paso 3 — Publicar el checkout

Cuando la función esté desplegada y la validación responda correctamente, abrir el Pull Request de esta rama hacia `main` y fusionarlo. Vercel publicará el checkout actualizado desde `main`.

## Comportamiento de compra

- Solo se admiten productos `d1` a `d6`, una unidad por pedido.
- El servidor valida el ID antes de descontar el saldo del cliente.
- La reserva local y el débito de la billetera del cliente se hacen en una única transacción SQL.
- Cada intento tiene un código persistente. Reintentar el mismo pedido usa la misma clave de idempotencia; nunca crea una segunda orden.
- Si Central One confirma el pedido, se conserva el código mientras esté en proceso. Al volver a consultar con el mismo código, la función sincroniza el estado de la orden existente.
- Los errores de red o desconocidos quedan pendientes; no se reintegra ni se crea otra orden a ciegas.
- El reintegro al cliente solo se hace cuando Central One informa que el dinero fue devuelto y la orden/línea está en estado terminal.
- No se muestra el costo mayorista al cliente.
- Esta primera versión no habilita otros productos, cantidades múltiples ni pedidos con varias líneas.

## Seguimiento

La acción `sync` recibe `{ "action": "sync", "order_id": ID_LOCAL }` y consulta `GET /orders/{id}`. La acción `purchase` con el mismo código también vuelve a consultar una orden que ya existe, en lugar de crear otra.

## No hacer

- No sobrescribir la Edge Function existente `rapid-handler`.
- No desactivar JWT.
- No compartir ni pegar claves en el chat.
- No fusionar el checkout a producción antes de desplegar y validar la Edge Function.
- No lanzar compras de prueba: cualquier `purchase` crea un pedido de saldo real.

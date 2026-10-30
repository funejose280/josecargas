# Actualización de puntos sin teléfono

1. En Supabase, abrí **SQL Editor** y ejecutá completo `ACTUALIZAR_PUNTOS_SIN_TELEFONO.sql`.
2. Publicá el contenido de la carpeta `public` en Vercel (o reemplazá el proyecto por este ZIP y desplegalo).
3. Los clientes nuevos crean su cuenta con correo, contraseña e ID de jugador; ya no se pide teléfono.
4. Las cuentas existentes se vinculan automáticamente usando el `player_id` que quedó guardado en los metadatos de Auth. No hace falta borrar ni recrear cuentas.
5. Los puntos siguen sumándose cuando el pedido pasa a **entregado/completado**: 1 punto por cada $1.000, según la configuración de puntos ya instalada.
6. Al llegar a 50 puntos o 5 compras completadas aparece **Solicitar código de descuento**. Las solicitudes quedan en Supabase, tabla `discount_code_requests`, para que José las revise. El código se carga en esa tabla al aprobar/entregar la solicitud.

**Importante:** para encontrar las compras anteriores, el ID de jugador guardado en la cuenta debe ser el mismo ID usado en esos pedidos. Los pedidos antiguos no se modifican ni se eliminan. Los pedidos nuevos hechos con sesión iniciada también guardan el usuario de la cuenta.

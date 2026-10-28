# José Recargas — activar el botón Nuevo pedido

1. En Supabase, abrí **SQL Editor** y creá una consulta nueva.
2. Abrí `ADMIN_PEDIDOS_SUPABASE.sql` y copiá su contenido en la consulta. Antes de ejecutarlo, reemplazá **todas** las apariciones de `admin@tudominio.com` por el correo exacto del administrador en Supabase Authentication → Users.
3. Ejecutá el SQL. Debe terminar sin errores. No compartas claves secretas.
4. Publicá los archivos de este ZIP en el mismo proyecto de Vercel, conservando la carpeta `public` y reemplazando `public/admin.html` por esta versión.
5. Abrí `https://josecargas.vercel.app/admin.html`, cerrá sesión si hace falta, volvé a entrar y recargá la página.
6. En “Registrar pedido de WhatsApp”, completá cliente, teléfono, ID de jugador (6–15 dígitos), producto e importe, y pulsá “Guardar nuevo pedido”.
7. Confirmá que el pedido aparezca en la tabla con estado **Pendiente**.

## Notas
- Este formulario es para registrar manualmente los pedidos recibidos directamente por WhatsApp. No importa automáticamente mensajes de WhatsApp.
- Los pedidos creados desde el formulario usan la misma tabla `public.pedidos`, por lo que aparecen junto a los pedidos existentes.
- El correo del administrador debe coincidir exactamente. No pongas contraseñas ni la clave `service_role` en archivos públicos.
- Si tu archivo SQL ya tenía el correo administrador corregido, mantené ese mismo correo en la nueva sección de la política de inserción.

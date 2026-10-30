# Corregir puntos que no aparecen en la página

1. En Supabase, abrí **SQL Editor** y ejecutá todo el archivo `SOLUCION_PUNTOS_NO_APARECEN.sql`.
2. Publicá en Vercel la carpeta `public` de este ZIP, reemplazando los archivos anteriores.
3. En la web, cerrá sesión, volvé a iniciar sesión y abrí **Mi cuenta / Mis puntos**. Tocá **Actualizar mis puntos**.

La corrección hace que la página busque el saldo por el ID de jugador guardado en la cuenta, aunque no se haya creado la fila de asociación en `customer_accounts`. Lee el mismo registro de `customer_loyalty` que consulta el panel de administración y no reinicia ni borra puntos, pedidos o cuentas.

Si sigue sin aparecer, comprobá que el ID de jugador guardado al crear la cuenta sea el mismo que figura en la columna `player_id` de `customer_loyalty`.

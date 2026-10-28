# Panel privado de pedidos — José Recargas

El panel gaming está en `public/admin.html`. Cuando publiques el proyecto, se abre en `https://TU-DOMINIO/admin.html`.

## Configuración inicial (necesaria una sola vez)

1. En Supabase, entrá a **Authentication → Users** y creá un usuario administrador con tu correo y una contraseña segura.
2. Abrí `ADMIN_PEDIDOS_SUPABASE.sql` y reemplazá las dos apariciones de `admin@tudominio.com` por el correo exacto del usuario creado.
3. En Supabase abrí **SQL Editor → New query**, pegá el archivo ya editado y ejecutalo.
4. Publicá el proyecto actualizado y entrá a `https://TU-DOMINIO/admin.html`. Iniciá sesión con ese correo y contraseña.
5. Buscá por código de pedido, ID de jugador o nombre; elegí un estado y presioná **Guardar**.

## Seguridad

- No agregues una clave `service_role` al HTML ni la compartas.
- Solo el correo configurado en las políticas SQL puede listar pedidos y actualizar estados desde este panel.
- La clave pública (publishable/anon) puede estar en el navegador; la autorización real depende de las políticas RLS de Supabase.
- Si el panel indica que no tiene permisos, verificá que usaste el correo exacto en el SQL y que ejecutaste el SQL después de reemplazarlo.
- Si el proyecto ya está publicado, subí `admin.html` a la carpeta pública y conservá el resto de los archivos.

# Cuentas de clientes y puntos

1. En Supabase > SQL Editor, ejecutá `CUENTAS_CLIENTES_Y_PUNTOS.sql`.
2. En Supabase > Authentication > URL Configuration, asegurate de que la URL del sitio incluya `https://josecargas.vercel.app` y que la URL de redirección permitida incluya ese dominio.
3. Publicá `public/index.html` actualizado en Vercel (el resto de archivos estáticos se conserva).
4. Abrí la tienda y pulsá **Mi cuenta / Mis puntos**. Para crear cuenta se pide correo, contraseña de al menos 10 caracteres, ID de jugador y teléfono.
5. Si Supabase exige confirmar correo, abrí el correo de confirmación y después iniciá sesión.

## Cómo se vinculan puntos anteriores
La cuenta solo queda vinculada automáticamente si el ID de jugador y el teléfono coinciden con los datos ya guardados en `customer_loyalty`. Si el teléfono no estaba guardado en los pedidos, el cliente podrá crear la cuenta, pero no verá puntos hasta corregir/validar la asociación en la base de datos.

## Seguridad
- Nunca uses la clave `service_role` en el navegador. El HTML usa solo la clave pública existente.
- La consulta de puntos requiere sesión autenticada y devuelve solo el resumen de la cuenta asociada.
- Activá confirmación de correo en Supabase Auth para verificar que el usuario controla el email.

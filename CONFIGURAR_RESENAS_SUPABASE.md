## Configurar reseñas y fotos de comprobación

En Supabase abrí **SQL Editor**, pegá y ejecutá el contenido completo del archivo `SUPABASE_RESEÑAS.sql` incluido en este proyecto. Ese SQL agrega `player_id` y `photo_urls` a la tabla `resenas` y configura el bucket público `review-photos` para que las fotos adjuntas a reseñas se puedan mostrar a otros clientes.

El verificador de ID está ahora arriba de la página y la misma cuenta verificada habilita la compra y la reseña. Los clientes pueden adjuntar hasta 3 imágenes del lobby o del saldo de diamantes (JPG, PNG, WEBP o GIF, máximo 5 MB por imagen). Las fotos quedan visibles junto a la reseña publicada.

**Privacidad:** pedí a los clientes que no suban capturas con contraseñas, datos personales, correos ni información privada. Las fotos del bucket son públicas porque las reseñas deben ser visibles para todos.

La página usa la URL y la clave pública de Supabase que ya estaban configuradas. Nunca pongas una clave `service_role` en el frontend.

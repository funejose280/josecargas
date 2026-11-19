# Actualizar la billetera de José Recargas

La base de datos ya tiene las tablas `wallets`, `wallet_topup_requests` y `wallet_transactions` creadas en una primera versión. Por eso, **no** hay que volver a ejecutar el SQL inicial antiguo ni borrar tablas.

## Pasos

1. En Supabase, abrir **SQL Editor** y crear una consulta nueva.
2. Abrir `BILLETERA_JOSE_RECARGAS.sql` de este proyecto, copiar todo su contenido y pegarlo en el editor.
3. Ejecutarlo una sola vez. El script agrega las columnas faltantes y crea las funciones con los nombres que invocan `public/index.html` y `public/admin.html`.
4. Confirmar que el resultado final muestra las tres tablas (`wallets`, `wallet_topup_requests`, `wallet_transactions`).
5. No publicar todavía ni aceptar dinero real hasta probar con una cuenta cliente y una carga de prueba de importe pequeño.

El script conserva `proof_url` y `type` si existen; agrega `proof_path` y `kind` para compatibilidad con el frontend. No borra pedidos, catálogo, reseñas, puntos ni movimientos.

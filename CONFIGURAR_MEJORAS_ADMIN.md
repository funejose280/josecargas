# Activar mejoras del panel José Recargas

1. Abrí `CATALOGO_Y_CLIENTES_SUPABASE.sql` en Supabase SQL Editor.
2. Reemplazá `admin@tudominio.com` por el correo exacto de tu usuario administrador, en las dos políticas.
3. Ejecutá el SQL. Crea catálogo y descuentos, no borra pedidos.
4. Publicá el contenido de `public/` en el mismo proyecto Vercel, conservando todos los demás archivos.
5. Entrá a `/admin.html` y recargá. Podrás buscar por cliente/teléfono/ID/código, ver ventas, cargar costos, editar precios y activar/desactivar/agotar productos.

## Importante
- Las ventas cuentan solo pedidos con estado `entregado` o `completado` y usan `created_at` como fecha. La ganancia aparece como `Costo pendiente` cuando no se puede asociar un producto a su costo. Los costos iniciales están en cero y deben completarse.
- Historial por cliente: buscá el teléfono, nombre o ID en la búsqueda del panel para ver las compras registradas de ese cliente.
- Los descuentos se guardan por teléfono, pero todavía no se descuentan automáticamente del checkout público; hace falta integrar esa regla en la creación del pedido para evitar inconsistencias.
- La administración de precios/stock se guarda en `product_catalog`. Para reflejarlo en el escaparate público se requiere aplicar el puente de catálogo en `index.html`; esta versión de panel administra la tabla, no debe considerarse sincronización completa hasta conectar ese puente.

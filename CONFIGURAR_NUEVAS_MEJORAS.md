# Activar clientes frecuentes, estadísticas y alertas — José Recargas

## 1. Configurar puntos de fidelidad
1. Abrí Supabase → SQL Editor.
2. Abrí `CLIENTES_FRECUENTES_ANALITICAS_ALERTAS.sql`.
3. Reemplazá **todas** las apariciones de `admin@tudominio.com` por el correo exacto con el que entrás al panel administrador.
4. Ejecutá el SQL. Crea las tablas de puntos y un trigger que acredita puntos una sola vez cuando un pedido pasa a `entregado` o `completado`. También procesa pedidos ya entregados que existían al instalarlo.
5. Publicá los archivos de `public/` en el proyecto de Vercel y entrá a `/admin.html`.

## 2. Regla de puntos
- 1 punto por cada $1.000 ARS del total de un pedido entregado (redondeo hacia abajo).
- El cliente se identifica primero por ID de jugador; para pedidos sin ID, se usa teléfono y, como último recurso, el código del pedido.
- Descuentos automáticos en el siguiente pedido: 5% al alcanzar 50 puntos o 5 compras; 10% al alcanzar 100 puntos o 10 compras. Se aplica al finalizar la compra por ID de jugador, después de cualquier cupón que el cliente haya ingresado.
- El checkout consulta una función de Supabase que devuelve únicamente el porcentaje de beneficio, no el historial ni los puntos exactos del cliente. Si no ejecutaste el SQL, la compra seguirá funcionando pero no aplicará el descuento de fidelidad.

## 3. Estadísticas y ganancias
- Las ventas y ganancias se calculan con pedidos `entregado` o `completado`, agrupados por la fecha de creación del pedido.
- Cargá el costo real de cada producto en la sección de catálogo del panel.
- La ganancia es una estimación: total efectivamente cobrado del pedido menos costo registrado por producto y cantidad. Así se tiene en cuenta el descuento aplicado. Si no se reconoce un producto o falta su costo, el panel avisa que faltan costos/productos por asociar.
- Las estadísticas, los productos y los clientes más vendidos se calculan con los últimos 500 pedidos cargados por el panel. Si el negocio supera ese volumen, conviene agregar reportes agregados en SQL para cubrir todo el historial.

## 4. Alertas de pedidos nuevos
- Con el panel abierto y sesión iniciada, consulta pedidos nuevos cada 30 segundos y muestra una alerta con sonido.
- Presioná **Activar notificaciones del navegador** y aceptá el permiso para recibir notificaciones del sistema. El navegador puede requerir que el panel permanezca abierto.

## 5. Diseño móvil
El panel ajusta estadísticas, tablas desplazables, formularios y alertas a pantallas pequeñas. Probalo desde el navegador del teléfono en `/admin.html`.

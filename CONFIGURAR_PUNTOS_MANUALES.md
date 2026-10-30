# Ajuste manual de puntos en el panel

1. En Supabase, abrí **SQL Editor** y ejecutá `ADMIN_PUNTOS_MANUALES.sql`.
2. Antes de ejecutarlo, reemplazá `admin@tudominio.com` por el mismo correo exacto del administrador que configuraste en `CLIENTES_FRECUENTES_ANALITICAS_ALERTAS.sql`.
3. Publicá la carpeta `public` en Vercel, incluyendo el `admin.html` actualizado.
4. Entrá a `/admin.html`, iniciá sesión y buscá la sección **Programa de puntos**.
5. Elegí el cliente, escribí una cantidad positiva para sumar o negativa para restar y presioná **Guardar puntos**.

El ajuste no cambia el número de compras, el total gastado ni el historial. No permite que el saldo quede negativo. El motivo es informativo y no se guarda en una tabla de auditoría.

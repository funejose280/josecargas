# José Recargas — verificador de ID Free Fire (LATAM)

## Integración FFINFO (SiamBhau)

El endpoint configurado por defecto es `https://siambhau69.eu.cc/freefireinfo/bhau`.
La solicitud del servidor envía `uid`, `region=SAC` y `key` como parámetros requeridos por la documentación del proveedor. La respuesta se interpreta desde `basicInfo` para obtener nombre, nivel, ID y región.

**Por seguridad, la clave no está escrita dentro del ZIP ni del HTML público.** Configurala en Vercel:

1. Abrí el proyecto en Vercel.
2. Entrá a **Settings → Environment Variables**.
3. Creá `FFINFO_API_KEY` y pegá tu clave personal.
4. Creá/verificá `FFINFO_API_URL` con valor `https://siambhau69.eu.cc/freefireinfo/bhau`.
5. Creá/verificá `FFINFO_REGION` con valor `SAC`.
6. Confirmá `FFINFO_ID_PARAM=uid` y `FFINFO_TIMEOUT_SECONDS=10`.
7. Guardá y hacé un nuevo Deploy.

No guardes la clave en `public/index.html` ni en variables `VITE_*`/`NEXT_PUBLIC_*`.

## Verificar

Probá `https://TU-SITIO.vercel.app/api/verify-id?uid=ID_DE_PRUEBA` usando un ID real de Free Fire LATAM. Para diagnóstico técnico temporal: agregá `&debug=1`. No compartas públicamente la respuesta de diagnóstico si incluye datos internos.

## Archivos

- `public/index.html`: interfaz del verificador.
- `app.py`: endpoint de servidor `/api/verify-id` y proxy seguro hacia FFINFO.
- `ffapi/`: verificador integrado de respaldo si no se configura `FFINFO_API_KEY`.
- `requirements.txt` y `pyproject.toml`: dependencias y configuración.

La clave debe configurarse como variable de entorno en el hosting; no se incluye en este archivo comprimido.

## Seguimiento de pedidos compartido

Para que los clientes puedan ver el estado desde cualquier teléfono o PC:

1. En Supabase abrí **SQL Editor → New query**.
2. Copiá y ejecutá todo el contenido de `PEDIDOS_SUPABASE.sql`.
3. Los nuevos pedidos se guardarán con estado `pendiente` y un código `JR-XXXXXX`.
4. Para actualizar un pedido, abrí **Table Editor → pedidos**, buscá el código y cambiá `status` a `proceso`, `entregado` o `cancelado`. El campo `updated_at` se actualiza automáticamente.
5. El cliente entra a “Estado del pedido”, ingresa su código y consulta el estado actualizado.

Estados admitidos: `pendiente`, `proceso`, `entregado`, `completado` y `cancelado`. En la web, `completado` también se muestra como “Entregado”. No habilites políticas públicas de lectura o actualización directa sobre la tabla `pedidos`.


## Historial de compras para clientes

La página incluye el botón **Historial de compras**. El cliente debe verificar primero su ID de Free Fire en el verificador principal y después tocar **Ver mi historial**. La web consulta hasta 50 pedidos de ese ID mediante la función `consultar_historial_pedidos`.

Si ya habías ejecutado el SQL anterior, volvé a ejecutar el bloque final de `PEDIDOS_SUPABASE.sql` que crea `consultar_historial_pedidos`; no borra pedidos existentes. Para una protección fuerte de privacidad, la consulta debe asociarse a una sesión autenticada del cliente en el servidor: la verificación visual del ID en el navegador por sí sola no es un control de acceso del lado de la base de datos.

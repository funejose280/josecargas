# Billetera de José Recargas

Esta versión agrega:
- Billetera por cuenta de cliente.
- Solicitud de carga manual con comprobante privado.
- Alias de transferencia: `jose280`.
- Aprobación/rechazo desde `public/admin.html`.
- Historial de movimientos y saldo.
- Pago con saldo desde el checkout. El servidor vuelve a calcular el precio usando `product_catalog`, comprueba disponibilidad y descuenta el saldo en una única transacción.

## Instalación

1. En Supabase, abrí el proyecto `qtpffmacnknczxdtlnua`.
2. Entrá a **SQL Editor** → **New query**.
3. Abrí `BILLETERA_JOSE_RECARGAS.sql`, copiá todo el contenido y ejecutalo una sola vez.
4. Confirmá que aparezca `Success`.
5. Publicá el contenido actualizado de la carpeta `public` en el mismo proyecto de Vercel, conservando el resto de archivos del repositorio.
6. Iniciá sesión en `https://josecargas.vercel.app/admin.html` con `funejose280@gmail.com` para revisar las solicitudes.

## Cómo funciona

- El cliente debe registrarse o iniciar sesión desde **Mi cuenta / Mis puntos**.
- En **Mi billetera**, indica el importe, transfiere al alias `jose280` y adjunta el comprobante.
- La solicitud queda pendiente. El saldo no cambia hasta que el administrador la aprueba.
- La aprobación se hace desde el panel de administración. El sistema bloquea solicitudes ya procesadas para evitar acreditaciones duplicadas.
- El cliente puede usar **PAGAR CON MI SALDO** en el checkout. El pago se permite solo para productos que existan en `product_catalog` y estén activos/disponibles. El importe se calcula en Supabase, no se confía en el precio enviado por el navegador.

## Importante

- Los comprobantes quedan en un bucket privado, no en una carpeta pública.
- El correo administrador configurado en las funciones de billetera es `funejose280@gmail.com`.
- El pago con billetera usa los precios vigentes de `product_catalog`. No aplica cupones ni descuentos adicionales del checkout en esta primera versión.
- No compartas nunca la clave `service_role`. La clave pública del frontend no reemplaza las políticas RLS.
- Este paquete modifica los archivos de la tienda y el panel, pero no puede ejecutar el SQL ni publicar en Vercel por vos. La activación real ocurre después de completar los pasos anteriores.

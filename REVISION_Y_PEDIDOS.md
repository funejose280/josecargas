# Revisión técnica y seguimiento de pedidos

## Cambios realizados
- Seguimiento de pedidos con validación del formato `JR-XXXXXX` y mensajes de error claros.
- Estados visibles: Pendiente, En proceso, Entregado y Cancelado.
- Integración de guardado/consulta de pedidos con Supabase para consultar desde distintos dispositivos.
- Los clientes pueden crear pedidos pendientes y consultar el estado mediante una función SQL por código; no se habilita lectura pública directa de la tabla.
- Se conserva el guardado local como respaldo cuando no se ha configurado el seguimiento compartido.
- Validación sintáctica de los scripts JavaScript del HTML y compilación de los módulos Python completadas sin errores.

## Paso obligatorio para activar el seguimiento compartido
Ejecutá `PEDIDOS_SUPABASE.sql` en Supabase → SQL Editor → New query. Hasta que se ejecute ese SQL, el sitio no podrá guardar/consultar órdenes en la base compartida y usará el respaldo local.

## Cómo actualizar estados de pedidos
En Supabase → Table Editor → `pedidos`, abrí la fila por su `code` y cambiá `status` por uno de estos valores exactos:
- `pendiente`
- `proceso`
- `entregado`
- `cancelado`

`completado` también se interpreta como entregado en la web por compatibilidad.

## Alcance
Se corrigieron los problemas detectados en el código y se validó la sintaxis de JavaScript/Python. No es posible garantizar que se hayan eliminado todos los errores de producción sin probar el sitio desplegado, las credenciales/ políticas de Supabase reales y el proveedor externo de verificación de ID.

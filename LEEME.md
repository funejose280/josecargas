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

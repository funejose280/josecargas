# Activar las reseñas públicas de José Recargas

El apartado visual ya está integrado. Para que una reseña quede guardada y la puedan ver otros clientes desde sus dispositivos, hay que conectarlo a una base de datos compartida. Este ZIP usa Supabase.

## 1. Crear el proyecto
1. Entrá a https://supabase.com/ y creá una cuenta/proyecto.
2. Guardá la contraseña de la base de datos en un lugar seguro.
3. Esperá a que el proyecto termine de crearse.

## 2. Crear la tabla
1. Dentro del proyecto, abrí **SQL Editor**.
2. Elegí **New query**.
3. Abrí el archivo `SUPABASE_RESEÑAS.sql` incluido en este ZIP, copiá todo su contenido y pegalo en el editor.
4. Presioná **Run**. Debe ejecutarse sin errores.

## 3. Copiar las credenciales públicas
En Supabase, abrí **Project Settings → API** (o la sección **Connect** según la interfaz).
Copiá la URL del proyecto y la clave pública **anon / publishable**. La clave pública está pensada para el navegador y queda protegida por las políticas RLS creadas en el SQL.

**Nunca pongas la clave `service_role` en el HTML ni la compartas.**

## 4. Pegar las credenciales en la página
Abrí `public/index.html` y buscá estas dos líneas cerca del final:

```js
const SUPABASE_URL = 'PEGAR_URL_DE_TU_PROYECTO_SUPABASE';
const SUPABASE_ANON_KEY = 'PEGAR_CLAVE_PUBLICA_ANON_SUPABASE';
```

Reemplazá los textos de ejemplo por los valores de tu proyecto, manteniendo las comillas. Ejemplo de formato para la URL: `https://abcdefgh.supabase.co`. No uses valores inventados; copiá los tuyos desde Supabase.

## 5. Publicar la versión actualizada
Volvé a subir los archivos del ZIP al repositorio que usa tu sitio y hacé un nuevo deploy en Vercel. Si tu proyecto está conectado a GitHub, reemplazá/subí los archivos al repositorio y esperá que termine el deploy.

## 6. Probar
Abrí la web publicada, bajá hasta **Reseñas de clientes**, publicá una reseña de prueba y recargá la página. Luego abrí la web en otro navegador o celular: la reseña debe aparecer allí también.

## Importante
- Las reseñas son públicas y no requieren inicio de sesión.
- Esta versión permite que cualquier visitante publique; para evitar spam, revisá las reseñas y más adelante se puede añadir moderación o CAPTCHA.
- Mientras no configures Supabase y publiques de nuevo, la página mostrará que falta conectar la base de datos. No se simula que las reseñas hayan quedado guardadas.

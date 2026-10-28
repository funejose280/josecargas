-- José Recargas: permisos para el panel privado de pedidos.
-- IMPORTANTE: antes de ejecutar, reemplazá admin@tudominio.com por el correo EXACTO
-- del usuario administrador que creaste en Supabase > Authentication > Users.
-- No pongas aquí la contraseña ni una clave service_role.

-- Cambiá este correo en las dos políticas indicadas abajo.
GRANT SELECT ON TABLE public.pedidos TO authenticated;
GRANT UPDATE (status) ON TABLE public.pedidos TO authenticated;

DROP POLICY IF EXISTS "Admin puede ver pedidos" ON public.pedidos;
CREATE POLICY "Admin puede ver pedidos"
ON public.pedidos FOR SELECT TO authenticated
USING ((auth.jwt() ->> 'email') = 'admin@tudominio.com');

DROP POLICY IF EXISTS "Admin puede actualizar estado de pedidos" ON public.pedidos;
CREATE POLICY "Admin puede actualizar estado de pedidos"
ON public.pedidos FOR UPDATE TO authenticated
USING ((auth.jwt() ->> 'email') = 'admin@tudominio.com')
WITH CHECK (
  (auth.jwt() ->> 'email') = 'admin@tudominio.com'
  AND status IN ('pendiente','proceso','entregado','completado','cancelado')
);


-- Permitir al administrador crear pedidos manuales recibidos por WhatsApp.
-- Reemplazá admin@tudominio.com por el correo real del administrador en esta política.
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS customer_phone text;
GRANT INSERT (code, status, total, player_id, player_name, products, customer_phone) ON TABLE public.pedidos TO authenticated;
DROP POLICY IF EXISTS "Admin puede crear pedidos manuales" ON public.pedidos;
CREATE POLICY "Admin puede crear pedidos manuales"
ON public.pedidos FOR INSERT TO authenticated
WITH CHECK (
  (auth.jwt() ->> 'email') = 'admin@tudominio.com'
  AND status = 'pendiente'
  AND code ~ '^JR-[A-Z0-9]{6}$'
  AND total >= 0
  AND player_id ~ '^[0-9]{6,15}$'
  AND jsonb_typeof(products) = 'array'
);

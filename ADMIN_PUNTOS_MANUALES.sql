-- Permite que el administrador ajuste manualmente el saldo de puntos.
-- IMPORTANTE: reemplazá admin@tudominio.com por el mismo correo administrador
-- que configuraste en CLIENTES_FRECUENTES_ANALITICAS_ALERTAS.sql.
-- Ejecutar en Supabase > SQL Editor > New query.

GRANT UPDATE (points, updated_at) ON public.customer_loyalty TO authenticated;
DROP POLICY IF EXISTS "Admin ajusta puntos manualmente" ON public.customer_loyalty;
CREATE POLICY "Admin ajusta puntos manualmente"
ON public.customer_loyalty
FOR UPDATE TO authenticated
USING ((auth.jwt()->>'email') = 'admin@tudominio.com')
WITH CHECK ((auth.jwt()->>'email') = 'admin@tudominio.com');

-- El panel solo actualiza el saldo points y updated_at.
-- customer_key, compras, total gastado e historial no se modifican.

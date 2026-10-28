-- José Recargas: catálogo administrable y descuentos por teléfono. Ejecutar en Supabase SQL Editor.
CREATE TABLE IF NOT EXISTS public.product_catalog (
 id text PRIMARY KEY, name text NOT NULL, price numeric(12,2) NOT NULL DEFAULT 0 CHECK(price>=0),
 cost numeric(12,2) NOT NULL DEFAULT 0 CHECK(cost>=0), active boolean NOT NULL DEFAULT true,
 available boolean NOT NULL DEFAULT true, updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.product_catalog ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.product_catalog TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.product_catalog TO authenticated;
DROP POLICY IF EXISTS "Catalogo publico visible" ON public.product_catalog;
CREATE POLICY "Catalogo publico visible" ON public.product_catalog FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "Admin administra catalogo" ON public.product_catalog;
CREATE POLICY "Admin administra catalogo" ON public.product_catalog FOR ALL TO authenticated
USING ((auth.jwt()->>'email')='admin@tudominio.com') WITH CHECK ((auth.jwt()->>'email')='admin@tudominio.com');
CREATE TABLE IF NOT EXISTS public.customer_discounts (
 phone text PRIMARY KEY, customer_name text NOT NULL, percent integer NOT NULL CHECK(percent BETWEEN 1 AND 50), created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.customer_discounts ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.customer_discounts TO authenticated;
DROP POLICY IF EXISTS "Admin administra descuentos" ON public.customer_discounts;
CREATE POLICY "Admin administra descuentos" ON public.customer_discounts FOR ALL TO authenticated
USING ((auth.jwt()->>'email')='admin@tudominio.com') WITH CHECK ((auth.jwt()->>'email')='admin@tudominio.com');
-- Semillas iniciales: precios base actuales. Podés editar precio/costo desde el panel.
INSERT INTO public.product_catalog(id,name,price,cost,active,available) VALUES
('d1','110 Diamantes',1400,0,true,true),('d2','341 Diamantes',4000,0,true,true),('d3','572 Diamantes',6500,0,true,true),('d4','1.166 Diamantes',12500,0,true,true),('d5','2.398 Diamantes',23000,0,true,true),('d6','6.160 Diamantes',57000,0,true,true),
('c1','Membresía Semanal',3000,0,true,true),('c2','Membresía Mensual',14000,0,true,true),('c3','Pase Booyah',2100,0,true,true),('frag','Fragmentos Evolutivos',70,0,true,true),('box','Cajas Evolutivas',400,0,true,true)
ON CONFLICT(id) DO NOTHING;
-- Reemplazá admin@tudominio.com en las políticas por el correo administrador exacto.


-- Consulta pública limitada: solo devuelve el porcentaje asociado al teléfono exacto; no expone nombre ni otros datos.
CREATE OR REPLACE FUNCTION public.jr_customer_discount_percent(p_phone text)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((
    SELECT cd.percent
    FROM public.customer_discounts cd
    WHERE regexp_replace(COALESCE(cd.phone, ''), '[^0-9]', '', 'g') = regexp_replace(COALESCE(p_phone, ''), '[^0-9]', '', 'g')
      AND regexp_replace(COALESCE(p_phone, ''), '[^0-9]', '', 'g') <> ''
    LIMIT 1
  ), 0);
$$;
REVOKE ALL ON FUNCTION public.jr_customer_discount_percent(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.jr_customer_discount_percent(text) TO anon, authenticated;

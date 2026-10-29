-- José Recargas: cuentas de cliente y consulta privada de puntos.
-- Ejecutar en Supabase > SQL Editor. No borra pedidos ni puntos existentes.
CREATE TABLE IF NOT EXISTS public.customer_accounts (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  player_id text NOT NULL,
  phone text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.customer_accounts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.customer_accounts FROM anon, authenticated;
GRANT SELECT ON public.customer_accounts TO authenticated;
DROP POLICY IF EXISTS "Cliente ve su asociación" ON public.customer_accounts;
CREATE POLICY "Cliente ve su asociación" ON public.customer_accounts FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- Al crear una cuenta, solo vincula los puntos si coinciden ID de jugador y teléfono guardados.
CREATE OR REPLACE FUNCTION public.jr_link_customer_account()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_player text; v_phone text;
BEGIN
  v_player := NULLIF(trim(NEW.raw_user_meta_data->>'player_id'), '');
  v_phone := NULLIF(trim(NEW.raw_user_meta_data->>'phone'), '');
  IF v_player IS NOT NULL AND v_phone IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.customer_loyalty cl
    WHERE cl.player_id = v_player
      AND regexp_replace(COALESCE(cl.phone,''), '[^0-9]', '', 'g') = regexp_replace(v_phone, '[^0-9]', '', 'g')
      AND regexp_replace(v_phone, '[^0-9]', '', 'g') <> ''
  ) THEN
    INSERT INTO public.customer_accounts(user_id, player_id, phone)
    VALUES (NEW.id, v_player, v_phone)
    ON CONFLICT (user_id) DO UPDATE SET player_id=EXCLUDED.player_id, phone=EXCLUDED.phone;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_jr_link_customer_account ON auth.users;
CREATE TRIGGER trg_jr_link_customer_account AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.jr_link_customer_account();

-- Retorna solo el resumen de la cuenta autenticada, nunca acepta un ID arbitrario del cliente.
CREATE OR REPLACE FUNCTION public.jr_my_loyalty_summary()
RETURNS TABLE(linked boolean, points integer, purchase_count integer, total_spent numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT true, cl.points, cl.purchase_count, cl.total_spent
  FROM public.customer_accounts ca
  JOIN public.customer_loyalty cl ON cl.player_id = ca.player_id
    AND regexp_replace(COALESCE(cl.phone,''), '[^0-9]', '', 'g') = regexp_replace(ca.phone, '[^0-9]', '', 'g')
  WHERE ca.user_id = auth.uid()
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.jr_my_loyalty_summary() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.jr_my_loyalty_summary() TO authenticated;

-- El cliente puede confirmar su correo mediante el flujo de Supabase Auth.
-- Si ya existía una cuenta antes de ejecutar este SQL, el trigger no la procesa retroactivamente.

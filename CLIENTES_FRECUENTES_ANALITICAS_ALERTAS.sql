-- José Recargas: puntos de fidelidad y datos de clientes frecuentes.
-- Ejecutar una sola vez en Supabase > SQL Editor.
-- Reemplazá admin@tudominio.com por el correo exacto del usuario administrador.
-- Regla: 1 punto cada $1.000 ARS, solo al pasar un pedido a entregado/completado.
ALTER TABLE public.pedidos ADD COLUMN IF NOT EXISTS customer_phone text;

CREATE TABLE IF NOT EXISTS public.customer_loyalty (
  customer_key text PRIMARY KEY,
  customer_name text,
  player_id text,
  phone text,
  points integer NOT NULL DEFAULT 0 CHECK (points >= 0),
  total_spent numeric(12,2) NOT NULL DEFAULT 0 CHECK (total_spent >= 0),
  purchase_count integer NOT NULL DEFAULT 0 CHECK (purchase_count >= 0),
  last_purchase_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.loyalty_transactions (
  order_code text PRIMARY KEY,
  customer_key text NOT NULL,
  points_awarded integer NOT NULL DEFAULT 0,
  amount numeric(12,2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.customer_loyalty ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_transactions ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.customer_loyalty TO authenticated;
GRANT SELECT ON public.loyalty_transactions TO authenticated;
DROP POLICY IF EXISTS "Admin consulta clientes frecuentes" ON public.customer_loyalty;
CREATE POLICY "Admin consulta clientes frecuentes" ON public.customer_loyalty
  FOR SELECT TO authenticated USING ((auth.jwt()->>'email') = 'admin@tudominio.com');
DROP POLICY IF EXISTS "Admin consulta movimientos de puntos" ON public.loyalty_transactions;
CREATE POLICY "Admin consulta movimientos de puntos" ON public.loyalty_transactions
  FOR SELECT TO authenticated USING ((auth.jwt()->>'email') = 'admin@tudominio.com');

CREATE OR REPLACE FUNCTION public.award_jose_recargas_points()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key text;
  v_points integer;
  v_inserted integer;
BEGIN
  IF NEW.status NOT IN ('entregado','completado') THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status IN ('entregado','completado') THEN
    RETURN NEW;
  END IF;

  v_key := COALESCE(NULLIF(NEW.player_id, ''), NULLIF(NEW.customer_phone, ''), NULLIF(NEW.code, ''));
  IF v_key IS NULL THEN
    RETURN NEW;
  END IF;
  v_points := GREATEST(0, FLOOR(COALESCE(NEW.total, 0) / 1000)::integer);

  INSERT INTO public.loyalty_transactions(order_code, customer_key, points_awarded, amount)
  VALUES (NEW.code, v_key, v_points, COALESCE(NEW.total, 0))
  ON CONFLICT (order_code) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 0 THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.customer_loyalty
    (customer_key, customer_name, player_id, phone, points, total_spent, purchase_count, last_purchase_at, updated_at)
  VALUES
    (v_key, COALESCE(NULLIF(NEW.player_name, ''), 'Cliente'), NEW.player_id, NEW.customer_phone,
     v_points, COALESCE(NEW.total, 0), 1, COALESCE(NEW.updated_at, NEW.created_at, now()), now())
  ON CONFLICT (customer_key) DO UPDATE SET
    customer_name = COALESCE(NULLIF(EXCLUDED.customer_name, 'Cliente'), public.customer_loyalty.customer_name),
    player_id = COALESCE(EXCLUDED.player_id, public.customer_loyalty.player_id),
    phone = COALESCE(EXCLUDED.phone, public.customer_loyalty.phone),
    points = public.customer_loyalty.points + EXCLUDED.points,
    total_spent = public.customer_loyalty.total_spent + EXCLUDED.total_spent,
    purchase_count = public.customer_loyalty.purchase_count + 1,
    last_purchase_at = GREATEST(COALESCE(public.customer_loyalty.last_purchase_at, '-infinity'::timestamptz), EXCLUDED.last_purchase_at),
    updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_award_jose_recargas_points ON public.pedidos;
CREATE TRIGGER trg_award_jose_recargas_points
AFTER INSERT OR UPDATE ON public.pedidos
FOR EACH ROW EXECUTE FUNCTION public.award_jose_recargas_points();

-- Los pedidos entregados antes de instalar esta mejora también suman puntos una sola vez.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT code, status, total, player_id, player_name, customer_phone, created_at, updated_at
    FROM public.pedidos
    WHERE status IN ('entregado','completado') AND code IS NOT NULL
  LOOP
    INSERT INTO public.loyalty_transactions(order_code, customer_key, points_awarded, amount)
    VALUES (r.code, COALESCE(NULLIF(r.player_id,''), NULLIF(r.customer_phone,''), r.code),
            GREATEST(0, FLOOR(COALESCE(r.total,0)/1000)::integer), COALESCE(r.total,0))
    ON CONFLICT (order_code) DO NOTHING;
    IF FOUND THEN
      INSERT INTO public.customer_loyalty
        (customer_key, customer_name, player_id, phone, points, total_spent, purchase_count, last_purchase_at, updated_at)
      VALUES
        (COALESCE(NULLIF(r.player_id,''), NULLIF(r.customer_phone,''), r.code), COALESCE(NULLIF(r.player_name,''),'Cliente'), r.player_id, r.customer_phone,
         GREATEST(0, FLOOR(COALESCE(r.total,0)/1000)::integer), COALESCE(r.total,0), 1, COALESCE(r.updated_at,r.created_at,now()), now())
      ON CONFLICT (customer_key) DO UPDATE SET
        customer_name = COALESCE(NULLIF(EXCLUDED.customer_name,'Cliente'), public.customer_loyalty.customer_name),
        player_id = COALESCE(EXCLUDED.player_id, public.customer_loyalty.player_id),
        phone = COALESCE(EXCLUDED.phone, public.customer_loyalty.phone),
        points = public.customer_loyalty.points + EXCLUDED.points,
        total_spent = public.customer_loyalty.total_spent + EXCLUDED.total_spent,
        purchase_count = public.customer_loyalty.purchase_count + 1,
        last_purchase_at = GREATEST(COALESCE(public.customer_loyalty.last_purchase_at, '-infinity'::timestamptz), EXCLUDED.last_purchase_at),
        updated_at = now();
    END IF;
  END LOOP;
END;
$$;

-- Este SQL no aplica automáticamente descuentos en la compra: solo registra puntos y estadísticas.

-- El checkout consulta solo el porcentaje de beneficio del ID ingresado.
-- No devuelve nombre, teléfono, puntos exactos ni historial al público.
CREATE OR REPLACE FUNCTION public.jr_loyalty_discount_percent(p_player_id text)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN COALESCE(points,0) >= 100 OR COALESCE(purchase_count,0) >= 10 THEN 10
    WHEN COALESCE(points,0) >= 50 OR COALESCE(purchase_count,0) >= 5 THEN 5
    ELSE 0
  END
  FROM public.customer_loyalty
  WHERE player_id = p_player_id
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.jr_loyalty_discount_percent(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.jr_loyalty_discount_percent(text) TO anon, authenticated;

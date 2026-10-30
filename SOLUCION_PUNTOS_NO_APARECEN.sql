-- José Recargas: corrige la lectura de puntos en "Mis puntos".
-- Ejecutar una sola vez en Supabase > SQL Editor.
-- No borra ni modifica pedidos, puntos ni cuentas.

CREATE OR REPLACE FUNCTION public.jr_my_loyalty_summary()
RETURNS TABLE(linked boolean, points integer, purchase_count integer, total_spent numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  WITH my_player AS (
    SELECT COALESCE(
      (SELECT NULLIF(trim(ca.player_id), '')
       FROM public.customer_accounts ca
       WHERE ca.user_id = auth.uid()),
      (SELECT NULLIF(trim(u.raw_user_meta_data->>'player_id'), '')
       FROM auth.users u WHERE u.id = auth.uid())
    ) AS player_id
  ), matching_loyalty AS (
    SELECT cl.points, cl.purchase_count, cl.total_spent
    FROM public.customer_loyalty cl
    CROSS JOIN my_player mp
    WHERE mp.player_id IS NOT NULL
      AND regexp_replace(COALESCE(cl.player_id, ''), '[^0-9]', '', 'g') =
          regexp_replace(mp.player_id, '[^0-9]', '', 'g')
    ORDER BY cl.updated_at DESC NULLS LAST
    LIMIT 1
  )
  SELECT
    EXISTS (SELECT 1 FROM matching_loyalty),
    COALESCE((SELECT ml.points FROM matching_loyalty ml), 0)::integer,
    COALESCE((SELECT ml.purchase_count FROM matching_loyalty ml), 0)::integer,
    COALESCE((SELECT ml.total_spent FROM matching_loyalty ml), 0)::numeric;
$$;
REVOKE ALL ON FUNCTION public.jr_my_loyalty_summary() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.jr_my_loyalty_summary() TO authenticated;

-- Mantiene la solicitud de descuento alineada con el mismo ID de jugador
-- y con el saldo que ve el cliente en la página.
CREATE OR REPLACE FUNCTION public.jr_request_discount_code()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_player text;
  v_points integer;
  v_count integer;
  v_id bigint;
BEGIN
  SELECT COALESCE(
    (SELECT NULLIF(trim(ca.player_id), '') FROM public.customer_accounts ca WHERE ca.user_id = auth.uid()),
    (SELECT NULLIF(trim(u.raw_user_meta_data->>'player_id'), '') FROM auth.users u WHERE u.id = auth.uid())
  ) INTO v_player;

  IF v_player IS NULL THEN
    RAISE EXCEPTION 'No encontramos el ID de jugador asociado a tu cuenta. Contactá a José para vincularlo.';
  END IF;

  SELECT cl.points, cl.purchase_count
    INTO v_points, v_count
  FROM public.customer_loyalty cl
  WHERE regexp_replace(COALESCE(cl.player_id, ''), '[^0-9]', '', 'g') =
        regexp_replace(v_player, '[^0-9]', '', 'g')
  ORDER BY cl.updated_at DESC NULLS LAST
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Todavía no encontramos compras completadas para tu ID de jugador.';
  END IF;

  IF COALESCE(v_points,0) < 50 AND COALESCE(v_count,0) < 5 THEN
    RAISE EXCEPTION 'Necesitás 50 puntos o 5 compras completadas para solicitar un código.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.discount_code_requests WHERE user_id = auth.uid() AND status = 'pendiente') THEN
    RAISE EXCEPTION 'Ya tenés una solicitud pendiente. José te avisará cuando esté lista.';
  END IF;

  INSERT INTO public.discount_code_requests(user_id, player_id, points, purchase_count)
  VALUES (auth.uid(), v_player, COALESCE(v_points,0), COALESCE(v_count,0))
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('request_id',v_id,'status','pendiente');
END;
$$;
REVOKE ALL ON FUNCTION public.jr_request_discount_code() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.jr_request_discount_code() TO authenticated;

NOTIFY pgrst, 'reload schema';

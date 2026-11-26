-- José Recargas · Integración segura Central One
-- Preparación de esquema. Ejecutar en Supabase SQL Editor después de revisar el respaldo.
-- No realiza compras ni llama a Central One.

ALTER TABLE public.product_catalog
  ADD COLUMN IF NOT EXISTS centralone_product_id text,
  ADD COLUMN IF NOT EXISTS centralone_sku text,
  ADD COLUMN IF NOT EXISTS supplier_cost_usd numeric(12,4);

UPDATE public.product_catalog SET
  centralone_product_id='e7d8be5d-de17-4731-a3a0-9c6554c5ca78',
  centralone_sku='C1-1VV8KDEM', supplier_cost_usd=0.6439
WHERE id='d1';
UPDATE public.product_catalog SET
  centralone_product_id='bb0a8212-916e-4c9a-ad22-170fa9732734',
  centralone_sku='C1-XRYZEHKP', supplier_cost_usd=1.9318
WHERE id='d2';
UPDATE public.product_catalog SET
  centralone_product_id='0cbc02a5-2e65-41d3-899e-917abd1a2dd1',
  centralone_sku='C1-VV2BJ3S8', supplier_cost_usd=3.2663
WHERE id='d3';
UPDATE public.product_catalog SET
  centralone_product_id='afad588d-54f9-4227-9c0b-9889a9135370',
  centralone_sku='C1-6K7C1XZG', supplier_cost_usd=6.0671
WHERE id='d4';
UPDATE public.product_catalog SET
  centralone_product_id='72b92180-b858-41fc-8e9d-bc402c16db80',
  centralone_sku='C1-1Y48D5A7', supplier_cost_usd=12.0413
WHERE id='d5';
UPDATE public.product_catalog SET
  centralone_product_id='e839259e-79e5-474e-b6e8-0c83f876ac6a',
  centralone_sku='C1-NRND5B5N', supplier_cost_usd=30.6463
WHERE id='d6';

ALTER TABLE public.pedidos
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS centralone_order_id text,
  ADD COLUMN IF NOT EXISTS centralone_idempotency_key text,
  ADD COLUMN IF NOT EXISTS centralone_status text NOT NULL DEFAULT 'not_submitted',
  ADD COLUMN IF NOT EXISTS centralone_response jsonb,
  ADD COLUMN IF NOT EXISTS supplier_cost_usd numeric(12,4),
  ADD COLUMN IF NOT EXISTS wallet_refund_amount numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS wallet_refunded_at timestamptz,
  ADD COLUMN IF NOT EXISTS supplier_last_checked_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS pedidos_centralone_idempotency_uidx
  ON public.pedidos(centralone_idempotency_key)
  WHERE centralone_idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS pedidos_centralone_order_uidx
  ON public.pedidos(centralone_order_id)
  WHERE centralone_order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS pedidos_user_created_idx
  ON public.pedidos(user_id, created_at DESC);

-- Reserva el saldo del cliente y crea el pedido local en una única transacción.
-- Solo la Edge Function con service_role puede ejecutarla.
CREATE OR REPLACE FUNCTION public.jr_c1_reserve_order(
  p_user_id uuid,
  p_code text,
  p_player_id text,
  p_player_name text,
  p_product_id text,
  p_customer_phone text,
  p_idempotency_key text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_product record;
  v_wallet_balance numeric(12,2);
  v_order_id bigint;
  v_existing public.pedidos%ROWTYPE;
BEGIN
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'Usuario inválido'; END IF;
  IF p_code !~ '^JR-[A-Z0-9]{6}$' THEN RAISE EXCEPTION 'Código de pedido inválido'; END IF;
  IF p_player_id !~ '^[0-9]{6,15}$' THEN RAISE EXCEPTION 'ID de jugador inválido'; END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 OR length(p_idempotency_key) > 255
     OR p_idempotency_key !~ '^[A-Za-z0-9_-]+$' THEN
    RAISE EXCEPTION 'Clave de idempotencia inválida';
  END IF;

  SELECT * INTO v_existing FROM public.pedidos
  WHERE centralone_idempotency_key=p_idempotency_key
  FOR UPDATE;
  IF FOUND THEN
    IF v_existing.user_id <> p_user_id
       OR v_existing.player_id <> p_player_id
       OR NOT EXISTS (
          SELECT 1 FROM jsonb_array_elements(v_existing.products) item
          WHERE item->>'id'=p_product_id
       ) THEN
      RAISE EXCEPTION 'La clave de compra ya fue usada con otros datos';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'created',false,'order_id',v_existing.id,'code',v_existing.code,
      'total',v_existing.total,'supplier_status',v_existing.centralone_status,
      'centralone_order_id',v_existing.centralone_order_id
    );
  END IF;

  SELECT id,name,price,centralone_product_id,centralone_sku,supplier_cost_usd
    INTO v_product
  FROM public.product_catalog
  WHERE id=p_product_id AND active=true AND available=true
    AND centralone_product_id IS NOT NULL AND supplier_cost_usd IS NOT NULL
  FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Este producto no está habilitado para compra automática'; END IF;

  INSERT INTO public.wallets(user_id,balance)
  VALUES(p_user_id,0) ON CONFLICT(user_id) DO NOTHING;
  SELECT balance INTO v_wallet_balance
  FROM public.wallets WHERE user_id=p_user_id FOR UPDATE;
  IF v_wallet_balance < v_product.price THEN
    RAISE EXCEPTION 'Saldo insuficiente';
  END IF;

  IF EXISTS (SELECT 1 FROM public.pedidos WHERE code=p_code) THEN
    RAISE EXCEPTION 'El código del pedido ya existe';
  END IF;

  INSERT INTO public.pedidos(
    code,status,total,player_id,player_name,products,customer_phone,user_id,
    centralone_idempotency_key,centralone_status,supplier_cost_usd
  ) VALUES (
    p_code,'proceso',v_product.price,p_player_id,p_player_name,
    jsonb_build_array(jsonb_build_object(
      'id',v_product.id,'name',v_product.name,'quantity',1,'price',v_product.price
    )),
    p_customer_phone,p_user_id,p_idempotency_key,'submitting',v_product.supplier_cost_usd
  ) RETURNING id INTO v_order_id;

  UPDATE public.wallets
  SET balance=balance-v_product.price,updated_at=now()
  WHERE user_id=p_user_id;

  INSERT INTO public.wallet_transactions(user_id,type,kind,amount,reference_id,description)
  VALUES(p_user_id,'purchase','purchase',-v_product.price,v_order_id::text,
         'Compra Central One · '||p_code);

  RETURN jsonb_build_object(
    'ok',true,'created',true,'order_id',v_order_id,'code',p_code,
    'total',v_product.price,'new_balance',v_wallet_balance-v_product.price,
    'centralone_product_id',v_product.centralone_product_id,
    'centralone_sku',v_product.centralone_sku,
    'supplier_cost_usd',v_product.supplier_cost_usd
  );
END;
$$;

-- Guarda el resultado del proveedor sin liberar saldo ante errores de red o estados inciertos.
CREATE OR REPLACE FUNCTION public.jr_c1_record_supplier_result(
  p_order_id bigint,
  p_centralone_order_id text,
  p_supplier_status text,
  p_response jsonb DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_supplier_status NOT IN ('created','confirmed','processing','completed',
       'partially_completed','failed','cancelled','refunded','unknown','submitting') THEN
    RAISE EXCEPTION 'Estado de Central One no permitido';
  END IF;
  UPDATE public.pedidos
  SET centralone_order_id=COALESCE(p_centralone_order_id,centralone_order_id),
      centralone_status=p_supplier_status,
      centralone_response=COALESCE(p_response,centralone_response),
      supplier_last_checked_at=now(),
      status=CASE
        WHEN p_supplier_status='completed' THEN 'entregado'
        WHEN p_supplier_status IN ('failed','cancelled','refunded') THEN 'cancelado'
        ELSE 'proceso'
      END
  WHERE id=p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pedido inexistente'; END IF;
END;
$$;

-- Reintegra una sola vez y únicamente ante estado terminal confirmado por Central One.
CREATE OR REPLACE FUNCTION public.jr_c1_refund_customer(p_order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order public.pedidos%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM public.pedidos WHERE id=p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pedido inexistente'; END IF;
  IF v_order.centralone_status NOT IN ('failed','cancelled','refunded') THEN
    RAISE EXCEPTION 'Central One todavía no confirmó un estado que permita reintegrar';
  END IF;
  IF v_order.wallet_refunded_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok',true,'already_refunded',true,
      'amount',v_order.wallet_refund_amount);
  END IF;
  IF v_order.user_id IS NULL THEN RAISE EXCEPTION 'Pedido sin usuario asociado; requiere revisión manual'; END IF;

  INSERT INTO public.wallets(user_id,balance)
  VALUES(v_order.user_id,0) ON CONFLICT(user_id) DO NOTHING;
  UPDATE public.wallets
  SET balance=balance+v_order.total,updated_at=now()
  WHERE user_id=v_order.user_id;

  INSERT INTO public.wallet_transactions(user_id,type,kind,amount,reference_id,description)
  VALUES(v_order.user_id,'refund','refund',v_order.total,v_order.id::text,
         'Reintegro Central One · '||v_order.code);

  UPDATE public.pedidos
  SET wallet_refund_amount=v_order.total,wallet_refunded_at=now(),
      status='cancelado',updated_at=now()
  WHERE id=v_order.id;

  RETURN jsonb_build_object('ok',true,'already_refunded',false,'amount',v_order.total);
END;
$$;

REVOKE ALL ON FUNCTION public.jr_c1_reserve_order(uuid,text,text,text,text,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.jr_c1_record_supplier_result(bigint,text,text,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.jr_c1_refund_customer(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.jr_c1_reserve_order(uuid,text,text,text,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.jr_c1_record_supplier_result(bigint,text,text,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.jr_c1_refund_customer(bigint) TO service_role;

-- Comprobación de mapeo: deben aparecer seis filas con producto Central One.
SELECT id,name,centralone_sku,centralone_product_id,supplier_cost_usd
FROM public.product_catalog
WHERE id IN ('d1','d2','d3','d4','d5','d6')
ORDER BY id;

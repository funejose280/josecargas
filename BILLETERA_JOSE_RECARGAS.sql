-- Migración compatible con las tablas ya creadas en José Recargas.
-- No borra tablas ni movimientos existentes. Ejecutar una sola vez.

-- 1) Completar columnas que usa la tienda y el panel.
ALTER TABLE public.wallet_topup_requests
  ADD COLUMN IF NOT EXISTS proof_path text,
  ADD COLUMN IF NOT EXISTS user_email text,
  ADD COLUMN IF NOT EXISTS admin_note text,
  ADD COLUMN IF NOT EXISTS reviewed_by text;

-- Si la tabla anterior guardaba el comprobante como proof_url, conservar ese dato.
UPDATE public.wallet_topup_requests
SET proof_path = proof_url
WHERE proof_path IS NULL AND proof_url IS NOT NULL;

ALTER TABLE public.wallet_transactions
  ADD COLUMN IF NOT EXISTS kind text;

-- Mantener compatibilidad con la columna type creada en la primera versión.
UPDATE public.wallet_transactions
SET kind = type
WHERE kind IS NULL AND type IS NOT NULL;

-- Las tablas existentes deben conservar ambas columnas sincronizadas.
CREATE OR REPLACE FUNCTION public.jr_sync_wallet_transaction_kind()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.kind IS NULL AND NEW.type IS NOT NULL THEN NEW.kind := NEW.type; END IF;
  IF NEW.type IS NULL AND NEW.kind IS NOT NULL THEN NEW.type := NEW.kind; END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS jr_wallet_transaction_kind_sync ON public.wallet_transactions;
CREATE TRIGGER jr_wallet_transaction_kind_sync
BEFORE INSERT OR UPDATE ON public.wallet_transactions
FOR EACH ROW EXECUTE FUNCTION public.jr_sync_wallet_transaction_kind();

CREATE INDEX IF NOT EXISTS wallet_topup_user_created_idx
  ON public.wallet_topup_requests(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS wallet_transactions_user_created_idx
  ON public.wallet_transactions(user_id, created_at DESC);

-- 2) Permisos de lectura: cliente propio; administrador puede revisar todas las solicitudes.
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_topup_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "jr_wallet_admin_read_topups" ON public.wallet_topup_requests;
CREATE POLICY "jr_wallet_admin_read_topups"
ON public.wallet_topup_requests FOR SELECT TO authenticated
USING (auth.uid() = user_id OR lower(coalesce(auth.jwt()->>'email','')) = 'funejose280@gmail.com');

DROP POLICY IF EXISTS "jr_wallet_admin_read_transactions" ON public.wallet_transactions;
CREATE POLICY "jr_wallet_admin_read_transactions"
ON public.wallet_transactions FOR SELECT TO authenticated
USING (auth.uid() = user_id OR lower(coalesce(auth.jwt()->>'email','')) = 'funejose280@gmail.com');

-- Los clientes no pueden editar saldo, aprobar cargas ni insertar movimientos directamente.
REVOKE ALL ON public.wallets FROM anon, authenticated;
GRANT SELECT ON public.wallets TO authenticated;
REVOKE ALL ON public.wallet_transactions FROM anon, authenticated;
GRANT SELECT ON public.wallet_transactions TO authenticated;
REVOKE ALL ON public.wallet_topup_requests FROM anon, authenticated;
GRANT SELECT, INSERT ON public.wallet_topup_requests TO authenticated;

-- 3) Bucket privado para comprobantes y políticas de acceso.
INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES ('wallet-proofs','wallet-proofs',false,5242880,
        ARRAY['image/jpeg','image/png','image/webp','application/pdf'])
ON CONFLICT (id) DO UPDATE SET public=false, file_size_limit=5242880,
  allowed_mime_types=ARRAY['image/jpeg','image/png','image/webp','application/pdf'];

DROP POLICY IF EXISTS "jr_wallet_proof_upload_own" ON storage.objects;
CREATE POLICY "jr_wallet_proof_upload_own" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id='wallet-proofs' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS "jr_wallet_proof_read_own_admin" ON storage.objects;
CREATE POLICY "jr_wallet_proof_read_own_admin" ON storage.objects
FOR SELECT TO authenticated
USING (bucket_id='wallet-proofs' AND (
  (storage.foldername(name))[1] = (SELECT auth.uid())::text OR
  lower(coalesce(auth.jwt()->>'email','')) = 'funejose280@gmail.com'
));

-- 4) Solicitud de carga: el cliente solo puede pedir una carga para sí mismo.
CREATE OR REPLACE FUNCTION public.jr_request_wallet_topup(p_amount numeric, p_proof_path text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_id uuid;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN RAISE EXCEPTION 'Iniciá sesión'; END IF;
  IF p_amount IS NULL OR p_amount < 100 OR p_amount > 1000000 THEN
    RAISE EXCEPTION 'El importe debe ser de $100 a $1.000.000';
  END IF;
  IF p_proof_path IS NULL OR split_part(p_proof_path,'/',1) <> (SELECT auth.uid())::text THEN
    RAISE EXCEPTION 'Comprobante inválido';
  END IF;
  INSERT INTO public.wallet_topup_requests(user_id,amount,proof_path,user_email,status)
  VALUES ((SELECT auth.uid()),p_amount,p_proof_path,(SELECT auth.jwt()->>'email'),'pending')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.jr_request_wallet_topup(numeric,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.jr_request_wallet_topup(numeric,text) TO authenticated;

-- 5) Aprobación/rechazo: funciones exactas que invoca public/admin.html.
CREATE OR REPLACE FUNCTION public.jr_admin_approve_wallet_topup(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE r public.wallet_topup_requests%ROWTYPE;
BEGIN
  IF lower(coalesce((SELECT auth.jwt()->>'email'),'')) <> 'funejose280@gmail.com' THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;
  SELECT * INTO r FROM public.wallet_topup_requests WHERE id=p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud inexistente'; END IF;
  IF r.status <> 'pending' THEN RAISE EXCEPTION 'La solicitud ya fue procesada'; END IF;
  INSERT INTO public.wallets(user_id,balance) VALUES (r.user_id,0) ON CONFLICT(user_id) DO NOTHING;
  UPDATE public.wallets SET balance=balance+r.amount, updated_at=now() WHERE user_id=r.user_id;
  INSERT INTO public.wallet_transactions(user_id,type,kind,amount,reference_id,description)
  VALUES(r.user_id,'topup','topup',r.amount,r.id,'Carga de saldo aprobada');
  UPDATE public.wallet_topup_requests
  SET status='approved', reviewed_by=(SELECT auth.jwt()->>'email'), reviewed_at=now()
  WHERE id=r.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.jr_admin_reject_wallet_topup(p_request_id uuid, p_note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_status text;
BEGIN
  IF lower(coalesce((SELECT auth.jwt()->>'email'),'')) <> 'funejose280@gmail.com' THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;
  SELECT status INTO v_status FROM public.wallet_topup_requests WHERE id=p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Solicitud inexistente'; END IF;
  IF v_status <> 'pending' THEN RAISE EXCEPTION 'La solicitud ya fue procesada'; END IF;
  UPDATE public.wallet_topup_requests
  SET status='rejected', admin_note=left(coalesce(p_note,''),500),
      reviewed_by=(SELECT auth.jwt()->>'email'), reviewed_at=now()
  WHERE id=p_request_id;
END;
$$;
REVOKE ALL ON FUNCTION public.jr_admin_approve_wallet_topup(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.jr_admin_reject_wallet_topup(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.jr_admin_approve_wallet_topup(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.jr_admin_reject_wallet_topup(uuid,text) TO authenticated;

-- 6) Pago desde saldo. Total y disponibilidad se calculan en Supabase, no en el navegador.
CREATE OR REPLACE FUNCTION public.jr_wallet_pay_order(
  p_code text, p_player_id text, p_player_name text,
  p_products jsonb, p_customer_phone text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_user uuid := (SELECT auth.uid());
  v_balance numeric(12,2);
  v_total numeric(12,2) := 0;
  v_item jsonb;
  v_product record;
  v_qty integer;
  v_order_id bigint;
  v_order_products jsonb := '[]'::jsonb;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Iniciá sesión para pagar con tu billetera'; END IF;
  IF coalesce(length(trim(p_code)),0) < 5 OR coalesce(length(trim(p_player_id)),0) < 6 THEN
    RAISE EXCEPTION 'Datos del pedido inválidos';
  END IF;
  IF jsonb_typeof(p_products) <> 'array' OR jsonb_array_length(p_products)=0 THEN
    RAISE EXCEPTION 'El pedido no tiene productos';
  END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_products) LOOP
    v_qty := greatest(1,least(100,coalesce((v_item->>'quantity')::integer,1)));
    SELECT id,name,price INTO v_product FROM public.product_catalog
    WHERE id = CASE WHEN v_item->>'id' LIKE 'evo-%' THEN substring(v_item->>'id' FROM 5) ELSE v_item->>'id' END
      AND active=true AND available=true;
    IF NOT FOUND THEN RAISE EXCEPTION 'Un producto ya no está disponible para pagar con saldo'; END IF;
    v_total := v_total + (v_product.price*v_qty);
    v_order_products := v_order_products || jsonb_build_array(
      jsonb_build_object('id',v_item->>'id','name',v_product.name,'quantity',v_qty,'price',v_product.price*v_qty));
  END LOOP;
  IF v_total <= 0 OR v_total > 1000000 THEN RAISE EXCEPTION 'Total inválido'; END IF;
  INSERT INTO public.wallets(user_id,balance) VALUES(v_user,0) ON CONFLICT(user_id) DO NOTHING;
  SELECT balance INTO v_balance FROM public.wallets WHERE user_id=v_user FOR UPDATE;
  IF v_balance < v_total THEN RAISE EXCEPTION 'Saldo insuficiente. Tu saldo actual es $%',to_char(v_balance,'FM999G999G990D00'); END IF;
  IF EXISTS(SELECT 1 FROM public.pedidos WHERE code=p_code) THEN RAISE EXCEPTION 'El código del pedido ya existe'; END IF;
  INSERT INTO public.pedidos(code,status,total,player_id,player_name,products,customer_phone)
  VALUES(p_code,'pendiente',v_total,p_player_id,p_player_name,v_order_products,p_customer_phone)
  RETURNING id INTO v_order_id;
  UPDATE public.wallets SET balance=balance-v_total,updated_at=now() WHERE user_id=v_user;
  INSERT INTO public.wallet_transactions(user_id,type,kind,amount,description)
  VALUES(v_user,'purchase','purchase',-v_total,'Compra José Recargas · '||p_code);
  RETURN jsonb_build_object('ok',true,'order_id',v_order_id,'code',p_code,'total',v_total,'new_balance',v_balance-v_total);
END;
$$;
REVOKE ALL ON FUNCTION public.jr_wallet_pay_order(text,text,text,jsonb,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.jr_wallet_pay_order(text,text,text,jsonb,text) TO authenticated;

-- 7) Verificación rápida: deben existir las tres tablas y las funciones principales.
SELECT 'wallets' AS objeto, to_regclass('public.wallets')::text AS existe
UNION ALL SELECT 'wallet_topup_requests', to_regclass('public.wallet_topup_requests')::text
UNION ALL SELECT 'wallet_transactions', to_regclass('public.wallet_transactions')::text;

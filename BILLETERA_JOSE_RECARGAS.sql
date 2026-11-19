-- Billetera José Recargas: cargas manuales con comprobante y aprobación del administrador.
-- Ejecutar una sola vez en Supabase SQL Editor del proyecto qtpffmacnknczxdtlnua.

create extension if not exists pgcrypto;

create table if not exists public.wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance numeric(12,2) not null default 0 check (balance >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.wallet_topup_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount numeric(12,2) not null check (amount >= 100 and amount <= 1000000),
  proof_path text not null,
  user_email text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('topup','purchase','refund','adjustment')),
  amount numeric(12,2) not null check (amount <> 0),
  reference_id uuid,
  description text not null,
  created_at timestamptz not null default now()
);

create index if not exists wallet_topup_user_created_idx on public.wallet_topup_requests(user_id, created_at desc);
create index if not exists wallet_transactions_user_created_idx on public.wallet_transactions(user_id, created_at desc);

-- Crear billetera automáticamente para cuentas nuevas y existentes.
create or replace function public.jr_create_wallet_for_user()
returns trigger language plpgsql security definer set search_path = public
as $$ begin
  insert into public.wallets(user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end; $$;
drop trigger if exists jr_auth_user_wallet on auth.users;
create trigger jr_auth_user_wallet after insert on auth.users
for each row execute function public.jr_create_wallet_for_user();
insert into public.wallets(user_id) select id from auth.users on conflict (user_id) do nothing;

alter table public.wallets enable row level security;
alter table public.wallet_topup_requests enable row level security;
alter table public.wallet_transactions enable row level security;

drop policy if exists "wallet_read_own" on public.wallets;
create policy "wallet_read_own" on public.wallets for select to authenticated using (auth.uid() = user_id);
drop policy if exists "wallet_topup_read_own" on public.wallet_topup_requests;
create policy "wallet_topup_read_own" on public.wallet_topup_requests for select to authenticated using (auth.uid() = user_id or lower(coalesce(auth.jwt()->>'email','')) = 'funejose280@gmail.com');
drop policy if exists "wallet_topup_insert_own" on public.wallet_topup_requests;
create policy "wallet_topup_insert_own" on public.wallet_topup_requests for insert to authenticated with check (auth.uid() = user_id and status = 'pending' and reviewed_at is null and reviewed_by is null);
drop policy if exists "wallet_transactions_read_own" on public.wallet_transactions;
create policy "wallet_transactions_read_own" on public.wallet_transactions for select to authenticated using (auth.uid() = user_id or lower(coalesce(auth.jwt()->>'email','')) = 'funejose280@gmail.com');

alter table public.wallet_topup_requests add column if not exists user_email text;

-- El cliente nunca puede editar wallets, topups ni transacciones directamente.
revoke all on public.wallets from anon, authenticated;
grant select on public.wallets to authenticated;
revoke all on public.wallet_topup_requests from anon, authenticated;
grant select, insert on public.wallet_topup_requests to authenticated;
revoke all on public.wallet_transactions from anon, authenticated;
grant select on public.wallet_transactions to authenticated;

-- Bucket privado: comprobantes no públicos.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('wallet-proofs','wallet-proofs',false,5242880,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public=false, file_size_limit=5242880, allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf'];

drop policy if exists "wallet_proof_upload_own" on storage.objects;
create policy "wallet_proof_upload_own" on storage.objects for insert to authenticated
with check (bucket_id='wallet-proofs' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "wallet_proof_read_own_or_admin" on storage.objects;
create policy "wallet_proof_read_own_or_admin" on storage.objects for select to authenticated
using (bucket_id='wallet-proofs' and ((storage.foldername(name))[1] = auth.uid()::text or lower(coalesce(auth.jwt()->>'email','')) = 'funejose280@gmail.com'));

create or replace function public.jr_request_wallet_topup(p_amount numeric, p_proof_path text)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Iniciá sesión'; end if;
  if p_amount is null or p_amount < 100 or p_amount > 1000000 then raise exception 'El importe debe ser de $100 a $1.000.000'; end if;
  if p_proof_path is null or split_part(p_proof_path,'/',1) <> auth.uid()::text then raise exception 'Comprobante inválido'; end if;
  insert into public.wallet_topup_requests(user_id,amount,proof_path,user_email)
  values(auth.uid(),p_amount,p_proof_path,auth.jwt()->>'email') returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.jr_request_wallet_topup(numeric,text) from public, anon;
grant execute on function public.jr_request_wallet_topup(numeric,text) to authenticated;

create or replace function public.jr_admin_approve_wallet_topup(p_request_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare r public.wallet_topup_requests%rowtype;
begin
  if lower(coalesce(auth.jwt()->>'email','')) <> 'funejose280@gmail.com' then
    raise exception 'No autorizado';
  end if;
  select * into r from public.wallet_topup_requests where id=p_request_id for update;
  if not found then raise exception 'Solicitud inexistente'; end if;
  if r.status <> 'pending' then raise exception 'La solicitud ya fue procesada'; end if;
  insert into public.wallets(user_id,balance) values (r.user_id,0) on conflict (user_id) do nothing;
  update public.wallets set balance=balance+r.amount, updated_at=now() where user_id=r.user_id;
  insert into public.wallet_transactions(user_id,kind,amount,reference_id,description)
  values(r.user_id,'topup',r.amount,r.id,'Carga de saldo aprobada');
  update public.wallet_topup_requests set status='approved', reviewed_by=auth.jwt()->>'email', reviewed_at=now() where id=r.id;
end; $$;

create or replace function public.jr_admin_reject_wallet_topup(p_request_id uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public
as $$
declare r public.wallet_topup_requests%rowtype;
begin
  if lower(coalesce(auth.jwt()->>'email','')) <> 'funejose280@gmail.com' then
    raise exception 'No autorizado';
  end if;
  select * into r from public.wallet_topup_requests where id=p_request_id for update;
  if not found then raise exception 'Solicitud inexistente'; end if;
  if r.status <> 'pending' then raise exception 'La solicitud ya fue procesada'; end if;
  update public.wallet_topup_requests set status='rejected', admin_note=left(coalesce(p_note,''),500), reviewed_by=auth.jwt()->>'email', reviewed_at=now() where id=r.id;
end; $$;

revoke all on function public.jr_admin_approve_wallet_topup(uuid) from public, anon;
revoke all on function public.jr_admin_reject_wallet_topup(uuid,text) from public, anon;
grant execute on function public.jr_admin_approve_wallet_topup(uuid) to authenticated;
grant execute on function public.jr_admin_reject_wallet_topup(uuid,text) to authenticated;

-- Compra atómica desde saldo: el servidor verifica el saldo, registra el pedido y descuenta una sola vez.
-- El total se calcula en servidor desde product_catalog; no acepta precios enviados por el navegador.
create or replace function public.jr_wallet_pay_order(
  p_code text, p_player_id text, p_player_name text,
  p_products jsonb, p_customer_phone text default null
) returns jsonb language plpgsql security definer set search_path = public
as $$
declare v_user uuid := auth.uid(); v_balance numeric(12,2); v_total numeric(12,2) := 0;
  v_item jsonb; v_product record; v_qty integer; v_order_id bigint; v_order_products jsonb := '[]'::jsonb;
begin
  if v_user is null then raise exception 'Iniciá sesión para pagar con tu billetera'; end if;
  if coalesce(length(trim(p_code)),0) < 5 or coalesce(length(trim(p_player_id)),0) < 6 then raise exception 'Datos del pedido inválidos'; end if;
  if jsonb_typeof(p_products) <> 'array' or jsonb_array_length(p_products)=0 then raise exception 'El pedido no tiene productos'; end if;
  -- Precio calculado en servidor: solo artículos del catálogo activo/disponible.
  for v_item in select value from jsonb_array_elements(p_products) loop
    v_qty := greatest(1, least(100, coalesce((v_item->>'quantity')::integer,1)));
    select id, name, price into v_product from public.product_catalog
      where id = case when v_item->>'id' like 'evo-%' then substring(v_item->>'id' from 5) else v_item->>'id' end
        and active = true and available = true;
    if not found then raise exception 'Un producto ya no está disponible para pagar con saldo'; end if;
    v_total := v_total + (v_product.price * v_qty);
    v_order_products := v_order_products || jsonb_build_array(jsonb_build_object('id',v_item->>'id','name',v_product.name,'quantity',v_qty,'price',v_product.price*v_qty));
  end loop;
  if v_total <= 0 or v_total > 1000000 then raise exception 'Total inválido'; end if;
  insert into public.wallets(user_id,balance) values(v_user,0) on conflict(user_id) do nothing;
  select balance into v_balance from public.wallets where user_id=v_user for update;
  if v_balance < v_total then raise exception 'Saldo insuficiente. Tu saldo actual es $%', to_char(v_balance,'FM999G999G990D00'); end if;
  if exists(select 1 from public.pedidos where code=p_code) then raise exception 'El código del pedido ya existe'; end if;
  insert into public.pedidos(code,status,total,player_id,player_name,products,customer_phone)
  values(p_code,'pendiente',v_total,p_player_id,p_player_name,v_order_products,p_customer_phone)
  returning id into v_order_id;
  update public.wallets set balance=balance-v_total, updated_at=now() where user_id=v_user;
  insert into public.wallet_transactions(user_id,kind,amount,description)
  values(v_user,'purchase',-v_total,'Compra José Recargas · '||p_code);
  return jsonb_build_object('ok',true,'order_id',v_order_id,'code',p_code,'total',v_total,'new_balance',v_balance-v_total);
end; $$;
revoke all on function public.jr_wallet_pay_order(text,text,text,jsonb,text) from public, anon;
grant execute on function public.jr_wallet_pay_order(text,text,text,jsonb,text) to authenticated;

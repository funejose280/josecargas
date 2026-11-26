import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CENTRALONE_API_KEY = Deno.env.get("CENTRALONE_API_KEY");
const CENTRALONE_BASE = "https://portal.centraloneglobal.com/api/v1";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
function fail(message: string, status = 400) {
  return reply({ ok: false, error: message }, status);
}
async function co(path: string, init: RequestInit = {}) {
  if (!CENTRALONE_API_KEY) throw new Error("Falta configurar CENTRALONE_API_KEY");
  return await fetch(CENTRALONE_BASE + path, {
    ...init,
    headers: {
      Authorization: `Bearer ${CENTRALONE_API_KEY}`,
      Accept: "application/json",
      ...(init.body ? { "Content-Type": "application/json" } : {}),
      ...(init.headers || {}),
    },
  });
}
function target(playerId: string) {
  return { player_id: playerId };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return fail("Método no permitido", 405);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) return fail("Iniciá sesión para continuar", 401);

    const authClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await authClient.auth.getUser(token);
    if (authError || !authData.user) return fail("Sesión inválida o vencida", 401);

    const db = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const body = await req.json();
    const action = body?.action;
    const userId = authData.user.id;

    if (action === "validate") {
      const productId = String(body.product_id || "");
      const playerId = String(body.player_id || "").trim();
      if (!/^d[1-6]$/.test(productId) || !/^\d{6,15}$/.test(playerId)) {
        return fail("Producto o ID de jugador inválido");
      }
      const { data: product, error } = await db.from("product_catalog")
        .select("id,centralone_product_id,active,available")
        .eq("id", productId).maybeSingle();
      if (error || !product?.active || !product?.available || !product.centralone_product_id) {
        return fail("El producto no está disponible para compra automática", 409);
      }
      const response = await co("/player/validate", {
        method: "POST",
        body: JSON.stringify({
          product_id: product.centralone_product_id,
          target_payload: target(playerId),
        }),
      });
      const result = await response.json().catch(() => ({}));
      if (!response.ok) return reply({ ok: false, provider: result }, response.status);
      return reply({ ok: true, status: result.status, player: result.player || null });
    }

    if (action === "purchase") {
      const productId = String(body.product_id || "");
      const playerId = String(body.player_id || "").trim();
      const code = String(body.code || "").trim().toUpperCase();
      const playerName = String(body.player_name || "").trim().slice(0, 100);
      const phone = String(body.customer_phone || "").trim().slice(0, 40) || null;

      if (!/^d[1-6]$/.test(productId) || !/^\d{6,15}$/.test(playerId) || !/^JR-[A-Z0-9]{6}$/.test(code)) {
        return fail("Datos de compra inválidos");
      }

      const { data: product, error: productError } = await db.from("product_catalog")
        .select("id,name,price,active,available,centralone_product_id,supplier_cost_usd")
        .eq("id", productId).maybeSingle();
      if (productError || !product?.active || !product?.available || !product.centralone_product_id) {
        return fail("El producto ya no está disponible", 409);
      }

      // La validación ocurre antes de descontar el saldo.
      const validationResponse = await co("/player/validate", {
        method: "POST",
        body: JSON.stringify({
          product_id: product.centralone_product_id,
          target_payload: target(playerId),
        }),
      });
      const validation = await validationResponse.json().catch(() => ({}));
      if (!validationResponse.ok || validation.status === "invalid") {
        return reply({
          ok: false,
          error: validation.status === "invalid"
            ? "El ID de jugador no es válido para este producto"
            : "No se pudo validar el ID. No se descontó saldo.",
          validation,
        }, 422);
      }
      if (validation.status !== "valid") {
        return reply({
          ok: false,
          error: "Central One no pudo verificar la cuenta. Por seguridad no se realizó el cobro.",
          validation,
        }, 409);
      }

      // La clave permanece igual en todos los reintentos del mismo código.
      const idempotencyKey = `JR_${code.replace(/-/g, "_")}`;
      const { data: reservation, error: reserveError } = await db.rpc("jr_c1_reserve_order", {
        p_user_id: userId,
        p_code: code,
        p_player_id: playerId,
        p_player_name: playerName || validation.player?.name || "",
        p_product_id: productId,
        p_customer_phone: phone,
        p_idempotency_key: idempotencyKey,
      });
      if (reserveError) return fail(reserveError.message, 409);

      // Si ya se registró una orden de Central One, nunca se crea otra.
      const { data: localOrder, error: localError } = await db.from("pedidos")
        .select("id,centralone_order_id,centralone_status,centralone_idempotency_key")
        .eq("id", reservation.order_id).eq("user_id", userId).single();
      if (localError || !localOrder) return fail("No se pudo recuperar el pedido reservado", 500);

      if (localOrder.centralone_order_id) {
        // Reutilizar el mismo código consulta la orden existente; nunca crea una segunda compra.
        try {
          const existingResponse = await co(`/orders/${encodeURIComponent(localOrder.centralone_order_id)}`);
          const existingBody = await existingResponse.json().catch(() => ({}));
          if (existingResponse.ok && existingBody.order) {
            const existingOrder = existingBody.order;
            await db.rpc("jr_c1_record_supplier_result", {
              p_order_id: localOrder.id,
              p_centralone_order_id: existingOrder.id,
              p_supplier_status: existingOrder.status || "unknown",
              p_response: existingBody,
            });
            const terminal = ["failed", "cancelled"].includes(existingOrder.status) ||
              (Array.isArray(existingOrder.items) && existingOrder.items.some((item: any) =>
                ["failed", "cancelled", "refunded"].includes(item.status)));
            let refunded = false;
            if (existingOrder.refund?.refunded === true && terminal) {
              const { data: refundResult, error: refundError } = await db.rpc("jr_c1_refund_customer", {
                p_order_id: localOrder.id,
              });
              if (!refundError) refunded = !!refundResult?.ok;
            }
            return reply({
              ok: true, refunded, order_id: localOrder.id, code,
              supplier_status: existingOrder.status || "unknown",
              message: refunded ? "Central One confirmó el fallo y el saldo fue reintegrado."
                : existingOrder.status === "completed" ? "Recarga completada."
                : "Este pedido ya existe y sigue en seguimiento. No se creó otra compra.",
            });
          }
        } catch (_syncError) {
          // Si no se puede consultar, se conserva el pedido y su misma clave.
        }
        return reply({
          ok: false, pending: true, order_id: localOrder.id, code,
          supplier_status: localOrder.centralone_status,
          error: "El pedido ya fue enviado. No se creó otra compra; volvé a consultar usando este mismo código.",
        }, 202);
      }

      // POST repetido con la misma Idempotency-Key devuelve la misma orden, sin doble cobro.
      let providerResponse: Response;
      try {
        providerResponse = await co("/orders", {
          method: "POST",
          headers: { "Idempotency-Key": idempotencyKey },
          body: JSON.stringify({
            items: [{
              catalog_item_id: product.centralone_product_id,
              quantity: 1,
              target_payload: target(playerId),
              expected_unit_price: Number(product.supplier_cost_usd),
            }],
            note: `José Recargas ${code}`,
          }),
        });
      } catch (_networkError) {
        // Estado incierto: mantener el saldo reservado localmente. El cliente reintenta con el mismo código.
        return reply({
          ok: false, pending: true, order_id: localOrder.id, code,
          error: "No se pudo confirmar la respuesta de Central One. No vuelvas a comprar con otro código; reintentá este mismo pedido.",
        }, 202);
      }

      const providerBody = await providerResponse.json().catch(() => ({}));
      if (!providerResponse.ok || !providerBody.order?.id) {
        const providerCode = providerBody?.error?.code || providerBody?.code || "";
        // Solo reintegrar ante códigos documentados que confirman rechazo sin crear una orden.
        // Errores nuevos/desconocidos quedan pendientes para conciliación; nunca liberar saldo a ciegas.
        const definitiveRejections = new Set([
          "invalid_request",
          "invalid_player",
          "not_eligible",
          "quantity_not_supported",
          "price_changed",
          "out_of_stock",
          "not_found",
        ]);
        const definiteNoOrder = providerResponse.status >= 400 &&
          providerResponse.status < 500 &&
          definitiveRejections.has(providerCode);
        if (definiteNoOrder) {
          await db.rpc("jr_c1_record_supplier_result", {
            p_order_id: localOrder.id,
            p_centralone_order_id: null,
            p_supplier_status: "failed",
            p_response: providerBody,
          });
          await db.rpc("jr_c1_refund_customer", { p_order_id: localOrder.id });
          return reply({
            ok: false, refunded: true, order_id: localOrder.id,
            error: providerBody?.error?.message_es || "Central One rechazó el pedido. El saldo fue reintegrado.",
          }, 422);
        }
        return reply({
          ok: false, pending: true, order_id: localOrder.id, code,
          error: "Central One no confirmó el resultado. El saldo queda protegido y el pedido no se repetirá con otra clave.",
          provider: providerBody,
        }, 202);
      }

      const providerOrder = providerBody.order;
      await db.rpc("jr_c1_record_supplier_result", {
        p_order_id: localOrder.id,
        p_centralone_order_id: providerOrder.id,
        p_supplier_status: providerOrder.status || "confirmed",
        p_response: providerBody,
      });

      return reply({
        ok: true, order_id: localOrder.id, code,
        supplier_status: providerOrder.status || "confirmed",
        message: "Pedido enviado a Central One. La entrega se confirmará al actualizar el estado.",
      });
    }

    if (action === "sync") {
      const orderId = Number(body.order_id);
      if (!Number.isSafeInteger(orderId) || orderId <= 0) return fail("Pedido inválido");
      const { data: localOrder, error } = await db.from("pedidos")
        .select("id,user_id,centralone_order_id,centralone_status")
        .eq("id", orderId).eq("user_id", userId).single();
      if (error || !localOrder) return fail("No se encontró el pedido", 404);
      if (!localOrder.centralone_order_id) {
        return reply({ ok: true, pending: true, status: localOrder.centralone_status,
          message: "El envío aún no tiene confirmación de Central One. Reintentá consultar más tarde." }, 202);
      }

      const response = await co(`/orders/${encodeURIComponent(localOrder.centralone_order_id)}`);
      const providerBody = await response.json().catch(() => ({}));
      if (!response.ok || !providerBody.order) {
        return reply({ ok: false, error: "No se pudo consultar el estado en Central One." }, 502);
      }
      const order = providerBody.order;
      await db.rpc("jr_c1_record_supplier_result", {
        p_order_id: localOrder.id,
        p_centralone_order_id: order.id,
        p_supplier_status: order.status || "unknown",
        p_response: providerBody,
      });

      let refunded = false;
      const refundConfirmed = order.refund?.refunded === true;
      const terminal = ["failed", "cancelled"].includes(order.status) ||
        (Array.isArray(order.items) && order.items.some((item: any) =>
          ["failed", "cancelled", "refunded"].includes(item.status)));
      if (refundConfirmed && terminal) {
        const { data: refundResult, error: refundError } = await db.rpc("jr_c1_refund_customer", {
          p_order_id: localOrder.id,
        });
        if (!refundError) refunded = !!refundResult?.ok;
      }

      return reply({
        ok: true, order_id: localOrder.id, supplier_status: order.status,
        refunded,
        message: refunded ? "Central One confirmó el fallo y el saldo fue reintegrado."
          : order.status === "completed" ? "Recarga completada."
          : "El pedido continúa en seguimiento. No realices otra compra mientras esté en proceso.",
      });
    }

    return fail("Acción no reconocida");
  } catch (error) {
    console.error("centralone-purchase:", error);
    return fail("Error interno. No compartas claves ni datos sensibles.", 500);
  }
});

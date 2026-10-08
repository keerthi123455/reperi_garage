// booking-api — the only way the app prices, pays for and creates bookings.
//
// POST { action: "quote",   items: [serviceKey...], pickup_drop?, fleet_request_id? }
//   → the server's price breakdown (what the payment screen shows)
// POST { action: "create",  items, pickup_drop?, vehicle_id?, payment_method: "online"|"cod",
//        options?: { label?, inspection?, claim? }, fleet_request_id? }
//   → online: a Razorpay order for the server-computed amount
//   → cod:    the booking, created immediately
// POST { action: "confirm", razorpay_order_id, razorpay_payment_id, razorpay_signature }
//   → verifies the payment and creates the booking (idempotent — safe to retry)
// POST { action: "status",  intent_id }
//   → current state of a checkout (for "finishing your booking…" retries)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {
  adminClient,
  ApiError,
  buildQuote,
  corsHeaders,
  createIntent,
  createRazorpayOrder,
  errorResponse,
  finalizeIntent,
  getUser,
  json,
  loadSettings,
  publicQuote,
  verifyCheckoutSignature,
} from "../_shared/booking.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  try {
    const body = await req.json().catch(() => {
      throw new ApiError("invalid_json", "Invalid request.");
    }) as Record<string, unknown>;
    const db = adminClient();
    const settings = await loadSettings(db);

    switch (body.action) {
      case "quote": {
        const quote = await buildQuote(db, body, settings);
        return json(publicQuote(quote));
      }

      case "create": {
        const user = await getUser(req, db);
        const { intent, quote } = await createIntent(db, user, body, settings);

        if (intent.payment_method === "cod") {
          const result = await finalizeIntent(db, intent.id, null, settings);
          return json({ intent_id: intent.id, ...result, quote: publicQuote(quote) });
        }

        const order = await createRazorpayOrder(intent);
        const { error } = await db
          .from("payment_intents")
          .update({ razorpay_order_id: order.orderId })
          .eq("id", intent.id);
        if (error) throw error;

        return json({
          intent_id: intent.id,
          order_id: order.orderId,
          key_id: order.keyId, // public key — safe to expose
          amount_paise: intent.amount * 100,
          currency: "INR",
          quote: publicQuote(quote),
        });
      }

      case "confirm": {
        const orderId = typeof body.razorpay_order_id === "string" ? body.razorpay_order_id : "";
        const paymentId = typeof body.razorpay_payment_id === "string" ? body.razorpay_payment_id : "";
        const signature = typeof body.razorpay_signature === "string" ? body.razorpay_signature : "";
        if (!orderId || !paymentId || !signature) {
          throw new ApiError("invalid_payment", "Missing payment details.");
        }
        if (!(await verifyCheckoutSignature(orderId, paymentId, signature))) {
          throw new ApiError("invalid_signature", "We couldn't verify this payment.", 400);
        }
        const { data: intent, error } = await db
          .from("payment_intents")
          .select("id")
          .eq("razorpay_order_id", orderId)
          .maybeSingle();
        if (error) throw error;
        if (!intent) throw new ApiError("not_found", "We couldn't find this order.", 404);

        const result = await finalizeIntent(db, intent.id as string, paymentId, settings);
        return json({ intent_id: intent.id, ...result });
      }

      case "status": {
        const user = await getUser(req, db);
        const intentId = typeof body.intent_id === "string" ? body.intent_id : "";
        if (!intentId) throw new ApiError("invalid_request", "Missing intent.");
        const { data, error } = await db
          .from("payment_intents")
          .select("id,user_id,status,booking_table,booking_id,razorpay_payment_id")
          .eq("id", intentId)
          .maybeSingle();
        if (error) throw error;
        if (!data || (data.user_id && data.user_id !== user?.id)) {
          throw new ApiError("not_found", "Booking not found.", 404);
        }
        // A paid checkout whose booking failed earlier gets another try.
        if (data.status === "failed" && data.razorpay_payment_id) {
          const result = await finalizeIntent(db, intentId, data.razorpay_payment_id as string, settings);
          return json({ intent_id: intentId, ...result });
        }
        return json({
          intent_id: intentId,
          status: data.status === "booked" ? "booked" : "pending",
          booking_table: data.booking_table,
          booking_id: data.booking_id,
        });
      }

      default:
        throw new ApiError("invalid_action", "Unknown action.");
    }
  } catch (err) {
    return errorResponse(err);
  }
});

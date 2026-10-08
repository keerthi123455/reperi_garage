// razorpay-webhook — backup path that creates the booking even if the
// customer's phone dies (or loses signal) right after paying.
//
// Razorpay Dashboard → Settings → Webhooks → Add:
//   URL:    https://<project-ref>.supabase.co/functions/v1/razorpay-webhook
//   Secret: same value as the RAZORPAY_WEBHOOK_SECRET function secret
//   Events: payment.captured, order.paid

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, finalizeIntent, json, loadSettings, verifyWebhookSignature } from "../_shared/booking.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const raw = await req.text();
  const signature = req.headers.get("x-razorpay-signature") ?? "";
  try {
    if (!signature || !(await verifyWebhookSignature(raw, signature))) {
      return json({ error: "invalid_signature" }, 400);
    }
  } catch (err) {
    console.error("Webhook secret not configured:", err);
    return json({ error: "not_configured" }, 500);
  }

  // deno-lint-ignore no-explicit-any
  let event: Record<string, any>;
  try {
    event = JSON.parse(raw);
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const type = event?.event as string | undefined;
  if (type !== "payment.captured" && type !== "order.paid") {
    return json({ ok: true, ignored: type ?? "unknown" });
  }

  const payment = event?.payload?.payment?.entity ?? {};
  const orderId: string | undefined = payment.order_id ?? event?.payload?.order?.entity?.id;
  const paymentId: string | undefined = payment.id;
  if (!orderId || !paymentId) return json({ ok: true, ignored: "no_order" });

  try {
    const db = adminClient();
    const { data: intent, error } = await db
      .from("payment_intents")
      .select("id,status")
      .eq("razorpay_order_id", orderId)
      .maybeSingle();
    if (error) throw error;
    // Orders from older app versions (created by create-razorpay-order)
    // have no intent — the app saves those bookings itself.
    if (!intent) return json({ ok: true, ignored: "no_intent" });
    if (intent.status === "booked") return json({ ok: true, status: "booked" });

    const settings = await loadSettings(db);
    const result = await finalizeIntent(db, intent.id as string, paymentId, settings);
    return json({ ok: true, ...result });
  } catch (err) {
    // Non-2xx makes Razorpay retry later, which is what we want here.
    console.error("Webhook booking failed:", err);
    return json({ error: "booking_failed" }, 500);
  }
});

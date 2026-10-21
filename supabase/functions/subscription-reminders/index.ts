// subscription-reminders — daily push: "renew your monthly wash plan".
//
// Run every day at 9:00 AM IST by pg_cron (see
// supabase/monthly_wash_app_renewal.sql). For every active monthly wash plan
// that ends in 2 days, tomorrow or today (IST calendar days) and hasn't been
// renewed, the customer gets one push. Opening the vehicle dashboard shows
// the blue "RENEW AND PAY" button.
//
// Protected by the `cron_secret` row in app_settings (sent as x-cron-secret).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, istDaysUntil, json, RENEW_WINDOW_DAYS } from "../_shared/booking.ts";

const ONESIGNAL_APP_ID = "6bc39a67-c05a-4ba4-b950-9ccfc8e9b9b6";
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY") ?? "";

async function sendPush(externalId: string, title: string, body: string, data: Record<string, unknown>) {
  if (!ONESIGNAL_REST_API_KEY) {
    console.error("ONESIGNAL_REST_API_KEY is not set — skipping send");
    return false;
  }
  const res = await fetch("https://api.onesignal.com/notifications", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Key ${ONESIGNAL_REST_API_KEY}` },
    body: JSON.stringify({
      app_id: ONESIGNAL_APP_ID,
      include_aliases: { external_id: [externalId] },
      target_channel: "push",
      headings: { en: title },
      contents: { en: body },
      data,
    }),
  });
  const out = await res.json().catch(() => null);
  if (!res.ok || !out?.id) {
    console.error("OneSignal send did not create a message", { externalId, status: res.status, response: out });
    return false;
  }
  return true;
}

function endLabel(iso: string): string {
  return new Date(iso).toLocaleDateString("en-IN", {
    timeZone: "Asia/Kolkata", weekday: "short", day: "numeric", month: "short",
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const db = adminClient();

  // Only pg_cron (which knows the secret) may run this.
  const { data: secretRow } = await db.from("app_settings").select("value").eq("key", "cron_secret").maybeSingle();
  const secret = typeof secretRow?.value === "string" ? secretRow.value : "";
  if (!secret || req.headers.get("x-cron-secret") !== secret) return json({ error: "forbidden" }, 403);

  try {
    // Plans ending within the next 3 days (a bit wider; filtered by IST day below).
    const until = new Date(Date.now() + (RENEW_WINDOW_DAYS + 2) * 86_400_000).toISOString();
    const since = new Date(Date.now() - 2 * 86_400_000).toISOString();
    const { data: plans, error } = await db
      .from("monthlywash_table")
      .select("id,user_id,vehicle_id,plan_title,end_date,status,created_at")
      .eq("status", "active")
      .gte("end_date", since)
      .lte("end_date", until)
      .limit(2000);
    if (error) throw error;

    const due = (plans ?? []).filter((p) => {
      if (!p.user_id || !p.end_date) return false;
      const d = istDaysUntil(p.end_date as string);
      return d >= 0 && d <= RENEW_WINDOW_DAYS;
    });

    // Skip plans already renewed, or where the car already has a newer plan.
    const ids = due.map((p) => String(p.id));
    const vehicleIds = [...new Set(due.map((p) => p.vehicle_id).filter(Boolean).map(String))];
    const renewedFrom = new Set<string>();
    const newestByVehicle = new Map<string, string>();
    if (ids.length) {
      const { data: kids } = await db.from("monthlywash_table").select("renewed_from_id").in("renewed_from_id", ids);
      (kids ?? []).forEach((k) => renewedFrom.add(String(k.renewed_from_id)));
    }
    if (vehicleIds.length) {
      const { data: all } = await db
        .from("monthlywash_table")
        .select("id,vehicle_id,created_at")
        .in("vehicle_id", vehicleIds)
        .order("created_at", { ascending: false });
      for (const r of all ?? []) {
        const v = String(r.vehicle_id);
        if (!newestByVehicle.has(v)) newestByVehicle.set(v, String(r.id));
      }
    }

    let sent = 0;
    for (const p of due) {
      const id = String(p.id);
      if (renewedFrom.has(id)) continue;
      if (p.vehicle_id && newestByVehicle.get(String(p.vehicle_id)) !== id) continue;

      const d = istDaysUntil(p.end_date as string);
      const plan = String(p.plan_title ?? "monthly wash plan");
      const title = d === 0 ? "Your wash plan ends today" : d === 1 ? "Your wash plan ends tomorrow" : "Your wash plan ends in 2 days";
      const body = d === 0
        ? `Your ${plan} ends today. Renew now so your daily washes don't stop — tap RENEW AND PAY in the app.`
        : `Your ${plan} ends on ${endLabel(p.end_date as string)}. Renew now to keep your daily washes going — tap RENEW AND PAY in the app.`;
      const ok = await sendPush(`customer_${p.user_id}`, title, body, {
        type: "subscription_renewal",
        subscriptionId: id,
        vehicleId: p.vehicle_id,
      });
      if (ok) sent++;
    }

    return json({ ok: true, due: due.length, sent });
  } catch (err) {
    console.error("subscription-reminders failed:", err);
    return json({ error: "failed" }, 500);
  }
});

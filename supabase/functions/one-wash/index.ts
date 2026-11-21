// one-wash — the "₹1 Car Wash" first-vehicle coupon messages (push + email).
//
// Called by the database through pg_net, never by the app
// (supabase/migrations/20261121000000_one_wash_coupon.sql):
//   { event: "issued",   user_id }   new customer added their first vehicle
//   { event: "redeemed", user_id }   their code was used on a booking
//
// Each message goes out once: the function stamps issued_notified_at /
// redeemed_notified_at in one_wash_coupons BEFORE sending, so a repeat call
// (or anyone else hitting this URL) sends nothing. What OneSignal / the
// mail server answered is saved in one_wash_coupons.notify_log.
//
// Push  — OneSignal, external id customer_<user id> (same as every other push).
// Email — the same SMTP account your Supabase Auth emails (signup / login
//         codes) already use. Copy it from Dashboard → Authentication →
//         Emails → SMTP Settings into these secrets:
//           SMTP_HOST   e.g. smtp.resend.com · smtp-relay.brevo.com · smtp.gmail.com
//           SMTP_PORT   465 (Edge Functions can't open 25 / 587, so those become 465)
//           SMTP_USER   the SMTP username
//           SMTP_PASS   the SMTP password / API key
//           SMTP_FROM   e.g. Reperi <no-reply@reperi.in>  (your "Sender email")
//         Without them it still sends the push; notify_log says email was skipped.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.10.1";
import { issuedMessage, type Message, redeemedMessage } from "./messages.ts";

const ONESIGNAL_APP_ID = "6bc39a67-c05a-4ba4-b950-9ccfc8e9b9b6";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type Event = "issued" | "redeemed";

interface OneWashRow {
  user_id: string;
  code: string;
  wash_price: number;
  booking_table: string | null;
  booking_id: string | null;
  notify_log: Record<string, unknown> | null;
}

function reply(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function errText(e: unknown): string {
  const msg = e instanceof Error
    ? e.message
    : e && typeof e === "object" && "message" in e
    ? String((e as { message: unknown }).message) // PostgREST errors are plain objects
    : String(e);
  return msg.slice(0, 300);
}

// ── Push (OneSignal) ───────────────────────────────────────────────────
async function sendPush(userId: string, m: Message, data: Record<string, unknown>): Promise<string> {
  const key = Deno.env.get("ONESIGNAL_REST_API_KEY") ?? "";
  if (!key) return "skipped: ONESIGNAL_REST_API_KEY not set";
  try {
    const res = await fetch("https://api.onesignal.com/notifications", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Key ${key}` },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        include_aliases: { external_id: [`customer_${userId}`] },
        target_channel: "push",
        headings: { en: m.pushTitle },
        contents: { en: m.pushBody },
        data,
      }),
    });
    const json = await res.json().catch(() => null);
    if (res.ok && json?.id) return `sent ${json.id}`;
    // e.g. the customer never allowed notifications — expected, not fatal.
    return `not sent: ${res.status} ${JSON.stringify(json?.errors ?? json ?? "").slice(0, 200)}`;
  } catch (e) {
    return `failed: ${errText(e)}`;
  }
}

// ── Email (SMTP — same account as Supabase Auth emails) ────────────────
async function sendEmail(to: string | null, m: Message): Promise<string> {
  const host = Deno.env.get("SMTP_HOST") ?? "";
  const user = Deno.env.get("SMTP_USER") ?? "";
  const pass = Deno.env.get("SMTP_PASS") ?? "";
  if (!host || !user || !pass) return "skipped: SMTP_HOST / SMTP_USER / SMTP_PASS not set";
  if (!to) return "skipped: customer has no email";

  let port = Number(Deno.env.get("SMTP_PORT") ?? "465");
  if (!Number.isInteger(port) || port <= 0) port = 465;
  if (port === 25 || port === 587) port = 465; // blocked for Edge Functions
  const from = Deno.env.get("SMTP_FROM") || user;

  try {
    const transporter = nodemailer.createTransport({
      host,
      port,
      secure: port === 465, // implicit TLS on 465; other ports upgrade with STARTTLS
      auth: { user, pass },
      connectionTimeout: 15_000,
      greetingTimeout: 15_000,
      socketTimeout: 20_000,
    });
    const info = await transporter.sendMail({ from, to, subject: m.subject, html: m.html, text: m.text });
    return `sent ${info.messageId ?? ""}`.trim();
  } catch (e) {
    return `failed: ${errText(e)}`;
  }
}

// ── Who the customer is ────────────────────────────────────────────────
async function customer(db: SupabaseClient, userId: string): Promise<{ email: string | null; firstName: string }> {
  let email: string | null = null;
  let meta: Record<string, unknown> = {};
  try {
    const { data } = await db.auth.admin.getUserById(userId);
    email = data?.user?.email?.trim() || null;
    meta = (data?.user?.user_metadata ?? {}) as Record<string, unknown>;
  } catch (e) {
    console.error("one-wash: auth user lookup failed", errText(e));
  }
  const { data: p } = await db.from("profiles").select("*").eq("id", userId).maybeSingle();
  const profile = (p ?? {}) as Record<string, unknown>;
  if (!email && typeof profile["email"] === "string") email = (profile["email"] as string).trim() || null;
  const full = String(profile["full_name"] ?? profile["name"] ?? meta["full_name"] ?? meta["name"] ?? "").trim();
  const first = full && full.toLowerCase() !== "unknown" ? full.split(/\s+/)[0] : "";
  return { email, firstName: first.slice(0, 40) };
}

/** "Express Wash (car) or Quick Wash (bike)" */
async function washNames(db: SupabaseClient, keys: string[]): Promise<string> {
  if (!keys.length) return "";
  const { data } = await db.from("services").select("key,name,vehicle_type").in("key", keys);
  const rows = (data ?? []) as Array<{ key: string; name?: string; vehicle_type?: string }>;
  const names = keys
    .map((k) => rows.find((r) => r.key === k))
    .filter((r): r is { key: string; name?: string; vehicle_type?: string } => !!r?.name)
    .map((r) => `${r.name}${r.vehicle_type === "car" || r.vehicle_type === "bike" ? ` (${r.vehicle_type})` : ""}`);
  if (names.length <= 1) return names[0] ?? "";
  return `${names.slice(0, -1).join(", ")} or ${names[names.length - 1]}`;
}

/** The services this customer's code works on (from their coupon, else the current setting). */
async function eligibleKeys(db: SupabaseClient, code: string): Promise<string[]> {
  const { data: c } = await db.from("coupons").select("service_keys").eq("code", code).maybeSingle();
  const fromCoupon = (c as { service_keys?: string[] | null } | null)?.service_keys;
  if (Array.isArray(fromCoupon) && fromCoupon.length) return fromCoupon;
  const { data: cfg } = await db.from("one_wash").select("eligible_services").eq("id", 1).maybeSingle();
  const fromCfg = (cfg as { eligible_services?: string[] | null } | null)?.eligible_services;
  return Array.isArray(fromCfg) ? fromCfg : [];
}

/** Stamps the row so this message can only go out once. Null = already sent / nothing to send. */
async function claim(db: SupabaseClient, userId: string, event: Event): Promise<OneWashRow | null> {
  const now = new Date().toISOString();
  const q = event === "issued"
    ? db.from("one_wash_coupons").update({ issued_notified_at: now })
      .eq("user_id", userId).is("issued_notified_at", null).is("redeemed_at", null)
    : db.from("one_wash_coupons").update({ redeemed_notified_at: now })
      .eq("user_id", userId).is("redeemed_notified_at", null).not("redeemed_at", "is", null);
  const { data, error } = await q.select("user_id,code,wash_price,booking_table,booking_id,notify_log");
  if (error) throw error;
  return ((data ?? []) as OneWashRow[])[0] ?? null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return reply({ ok: false, error: "method_not_allowed" }, 405);

  let event: Event;
  let userId: string;
  try {
    const body = (await req.json()) as Record<string, unknown>;
    if (body.event !== "issued" && body.event !== "redeemed") throw new Error("bad event");
    if (typeof body.user_id !== "string" || !UUID_RE.test(body.user_id)) throw new Error("bad user_id");
    event = body.event;
    userId = body.user_id.toLowerCase();
  } catch {
    return reply({ ok: false, error: "bad_request" }, 400);
  }

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set");
    const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

    const row = await claim(db, userId, event);
    if (!row) return reply({ ok: true, skipped: "nothing to send (already sent, or no such code)" });

    const who = await customer(db, userId);
    let message: Message;
    let data: Record<string, unknown>;
    if (event === "issued") {
      const washes = await washNames(db, await eligibleKeys(db, row.code));
      message = issuedMessage({ code: row.code, price: row.wash_price, firstName: who.firstName, washes });
      data = { type: "one_wash", code: row.code };
    } else {
      message = redeemedMessage({ code: row.code, price: row.wash_price, firstName: who.firstName, bookingId: row.booking_id });
      data = { type: "booking", bookingId: row.booking_id, table: row.booking_table };
    }

    const [push, email] = await Promise.all([sendPush(userId, message, data), sendEmail(who.email, message)]);
    const log = {
      ...(row.notify_log ?? {}),
      [event]: { at: new Date().toISOString(), push, email, to: who.email },
    };
    const { error: logErr } = await db.from("one_wash_coupons").update({ notify_log: log }).eq("user_id", userId);
    if (logErr) console.error("one-wash: notify_log not saved", logErr.message);

    console.log(`one-wash ${event} ${row.code}: push=${push} · email=${email}`);
    return reply({ ok: true, event, code: row.code, push, email });
  } catch (e) {
    console.error("one-wash error:", e);
    return reply({ ok: false, error: errText(e) }, 500);
  }
});

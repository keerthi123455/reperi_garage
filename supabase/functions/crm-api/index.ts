// crm-api — data for the internal REPERI CRM dashboard (web/crm.html).
//
// Who can use it: anyone signed in with Supabase Auth whose CONFIRMED email
// ends in @trustkon.com (override with the CRM_ALLOWED_DOMAIN secret).
// Everything is read with the service role here, so the dashboard never
// depends on the public anon key or on RLS for the operational tables.
//
// POST { action: "snapshot", from: ISO, to: ISO }
//   → every booking/claim/wash/fleet/payment row created in [from, to),
//     plus everything still OPEN regardless of when it was created,
//     plus partners, customers and test-account markers.
// POST { action: "detail", table, id }
//   → one row with its progress updates, chats and cancellation info.
// POST { action: "doc", path }
//   → a 5-minute signed URL for a claim document (insurance-documents).
// POST { action: "resolve_quote", id, price, note, image?: base64 JPEG, removeImage? }
//   → sends a ReperiResolve price (text + amount + optional photo) to the
//     customer. Shows in their app; the DB webhook sends the push.
// POST { action: "resolve_assign", id, admin_id }   (admin_id null = unassign)
// POST { action: "inspection_assign", table, id, partner_id }   (partner_id null = unassign)
//   → picks the expert (a delivery partner) for an inspection visit.
// POST { action: "inspection_photos", paths: [...] }
//   → 5-minute signed URLs for inspection photos (thumbnails in the CRM).
// POST { action: "invoice_issue", table, id, lines?, reason? }
//   → makes the booking's bill now, or overrides it with the given lines
//     [{name, amount (incl. GST), gst: 18|5, free?, note?}]. The old bill is
//     kept as 'replaced'; the customer is notified and sees the new one.
// POST { action: "qr_list" } / { action: "qr_add", label, image: data URL, activate? }
//      { action: "qr_activate", id } / { action: "qr_delete", id }
//   → the payment QR shown when garages / delivery partners / washers
//     collect payment (supabase/payment_collection.sql). One is "in use".
// POST { action: "assign", table, id, role: garage|delivery|washer, to, reason? }
//   → changes who a booking is assigned to (logged in assignment_log, the new
//     person is notified).
// POST { action: "rules_get" } / { action: "rules_save", op, ... }
//   → the automatic assignment rules: pools + members, which pool each
//     service uses, default fleet garage, garage per fleet company.
// POST { action: "me" }
//   → { email } — used by the page to confirm access after sign-in.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2";
import { cleanLines, isInvoiceTable, issueInvoice } from "../_shared/invoice.ts";

const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

const ALLOWED_DOMAIN = (Deno.env.get("CRM_ALLOWED_DOMAIN") ?? "trustkon.com").toLowerCase().replace(/^@/, "");
const MAX_ROWS = 5000;
const MAX_RANGE_DAYS = 400;

// OTP codes are never sent to the browser, even to staff.
const HIDDEN_COLUMNS = ["pickup_otp_code", "return_otp_code"];

function db(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

async function requireStaff(req: Request, client: SupabaseClient): Promise<User> {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new HttpError(401, "sign_in_required", "Please sign in.");
  const { data, error } = await client.auth.getUser(token);
  const user = data?.user;
  if (error || !user) throw new HttpError(401, "sign_in_required", "Your session has expired. Please sign in again.");
  const email = (user.email ?? "").toLowerCase();
  if (!email.endsWith("@" + ALLOWED_DOMAIN)) {
    throw new HttpError(403, "not_staff", `Only @${ALLOWED_DOMAIN} accounts can open the CRM.`);
  }
  if (!user.email_confirmed_at && !user.confirmed_at) {
    throw new HttpError(403, "not_confirmed", "Please confirm your email address first.");
  }
  return user;
}

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

function strip(rows: Row[]): Row[] {
  for (const r of rows) for (const c of HIDDEN_COLUMNS) delete r[c];
  return rows;
}

/** Runs a query; on failure records the error and returns [] so one
 *  missing table/column never takes the whole dashboard down. */
async function safe(
  errors: Record<string, string>,
  name: string,
  // deno-lint-ignore no-explicit-any
  run: () => PromiseLike<{ data: any; error: any }>,
): Promise<Row[]> {
  try {
    const { data, error } = await run();
    if (error) {
      errors[name] = error.message ?? String(error);
      return [];
    }
    return strip((data ?? []) as Row[]);
  } catch (e) {
    errors[name] = e instanceof Error ? e.message : String(e);
    return [];
  }
}

function mergeById(...lists: Row[][]): Row[] {
  const seen = new Map<string, Row>();
  for (const list of lists) for (const r of list) seen.set(String(r.id), r);
  return [...seen.values()].sort((a, b) => String(b.created_at ?? "").localeCompare(String(a.created_at ?? "")));
}

function parseRange(body: Row): { from: string; to: string } {
  const now = new Date();
  const to = body.to ? new Date(body.to) : now;
  const from = body.from ? new Date(body.from) : new Date(to.getTime() - 30 * 86400000);
  if (isNaN(from.getTime()) || isNaN(to.getTime()) || from >= to) {
    throw new HttpError(400, "bad_range", "Invalid date range.");
  }
  if ((to.getTime() - from.getTime()) / 86400000 > MAX_RANGE_DAYS) {
    throw new HttpError(400, "bad_range", `Pick a range of ${MAX_RANGE_DAYS} days or less.`);
  }
  return { from: from.toISOString(), to: to.toISOString() };
}

async function snapshot(client: SupabaseClient, body: Row) {
  const { from, to } = parseRange(body);
  const errors: Record<string, string> = {};
  // Open work older than this is still shown (stuck jobs are what you most
  // need to see), but we don't scan the whole history for it.
  const openSince = new Date(Date.now() - 180 * 86400000).toISOString();

  const inRange = (table: string) =>
    safe(errors, table, () =>
      client.from(table).select("*").gte("created_at", from).lt("created_at", to)
        .order("created_at", { ascending: false }).limit(MAX_ROWS));

  const [
    bookingsR, bookingsOpen,
    pollutionR, pollutionOpen,
    inspectionR, inspectionOpen,
    claimsR, claimsOpen,
    fleetR, fleetOpen,
    monthlyR, monthlyActive,
    washLog, detailing, cancellations,
    intentsR, intentsStuck,
    admins, deliveryPartners, washers,
    reviewOverrides, chatReports, unreadChats,
    offerR, offerOpen,
    resolveR, resolveOpen,
    addonsR, addonsOpen,
  ] = await Promise.all([
    inRange("bookings"),
    safe(errors, "bookings_open", () =>
      client.from("bookings").select("*").gte("created_at", openSince)
        .or("booking_status.is.null,booking_status.not.in.(Delivered,delivered,completed,Completed,cancelled,canceled)")
        .limit(MAX_ROWS)),
    inRange("pollution_booking"),
    safe(errors, "pollution_open", () =>
      client.from("pollution_booking").select("*").gte("created_at", openSince)
        .or("delivery_stage.is.null,delivery_stage.neq.delivered").limit(MAX_ROWS)),
    inRange("inspection_booking"),
    safe(errors, "inspection_open", () =>
      client.from("inspection_booking").select("*").gte("created_at", openSince)
        .or("delivery_stage.is.null,delivery_stage.neq.delivered").limit(MAX_ROWS)),
    inRange("claim_table"),
    safe(errors, "claims_open", () =>
      client.from("claim_table").select("*").gte("created_at", openSince)
        .or("claim_status.is.null,claim_status.not.in.(Delivered,delivered,rejected,Rejected)").limit(MAX_ROWS)),
    inRange("fleet_pickup_requests"),
    safe(errors, "fleet_open", () =>
      client.from("fleet_pickup_requests").select("*").gte("created_at", openSince)
        .or("status.is.null,status.neq.Completed").limit(MAX_ROWS)),
    inRange("monthlywash_table"),
    safe(errors, "monthly_active", () =>
      client.from("monthlywash_table").select("*").eq("status", "active").limit(MAX_ROWS)),
    inRange("service_history"),
    inRange("detailing_bookings"),
    inRange("booking_cancellations"),
    inRange("payment_intents"),
    safe(errors, "payment_intents_stuck", () =>
      client.from("payment_intents").select("*").in("status", ["failed", "processing"])
        .gte("created_at", openSince).limit(MAX_ROWS)),
    safe(errors, "admin", () => client.from("admin").select("id,username,vehicle,address,latitude,longitude")),
    safe(errors, "delivery_partners", () => client.from("delivery_partners").select("*")),
    safe(errors, "washers", () => client.from("washers").select("*")),
    safe(errors, "review_overrides", () => client.from("review_overrides").select("customer_email,role,member_ref")),
    inRange("chat_reports"),
    safe(errors, "booking_chats_unread", () =>
      client.from("booking_chats").select("id,booking_id,created_at")
        .eq("sender", "consumer").eq("is_read_by_admin", false).gte("created_at", openSince).limit(MAX_ROWS)),
    // Apartment offer washes (₹1 / ₹199 / ₹999) — their own table.
    inRange("offer_bookings"),
    safe(errors, "offer_bookings_open", () =>
      client.from("offer_bookings").select("*").gte("created_at", openSince)
        .or("booking_status.is.null,booking_status.not.in.(Delivered,delivered,completed,Completed,cancelled,canceled)")
        .limit(MAX_ROWS)),
    // ReperiResolve requests (photos/video of a problem → we send a price).
    inRange("resolve_requests"),
    safe(errors, "resolve_requests_open", () =>
      client.from("resolve_requests").select("*").gte("created_at", openSince)
        .in("status", ["Submitted", "Quoted", "Accepted"]).limit(MAX_ROWS)),
    // Add-ons garages asked for on a booking (customer approves & pays / rejects).
    inRange("addon_services"),
    safe(errors, "addon_services_open", () =>
      client.from("addon_services").select("*").gte("created_at", openSince)
        .in("status", ["Requested", "Approved"]).limit(MAX_ROWS)),
  ]);

  const bookings = mergeById(bookingsR, bookingsOpen);
  const pollution = mergeById(pollutionR, pollutionOpen);
  const inspection = mergeById(inspectionR, inspectionOpen);
  const claims = mergeById(claimsR, claimsOpen);
  const fleet = mergeById(fleetR, fleetOpen);
  const monthly = mergeById(monthlyR, monthlyActive);
  const intents = mergeById(intentsR, intentsStuck);
  const offer = mergeById(offerR, offerOpen);
  const resolve = mergeById(resolveR, resolveOpen);
  const addons = mergeById(addonsR, addonsOpen);

  // Customers and vehicles referenced by any row.
  const userIds = new Set<string>();
  const vehicleIds = new Set<string>();
  for (const list of [bookings, pollution, inspection, claims, monthly, detailing, cancellations, intents, offer, resolve, addons]) {
    for (const r of list) {
      if (r.user_id) userIds.add(String(r.user_id));
      if (r.vehicle_id) vehicleIds.add(String(r.vehicle_id));
    }
  }
  const chunk = <T,>(arr: T[], n: number) => {
    const out: T[][] = [];
    for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
    return out;
  };
  const profileLists = await Promise.all(
    chunk([...userIds], 200).map((ids) =>
      safe(errors, "profiles", () => client.from("profiles").select("id,name,email,phone").in("id", ids))),
  );
  const vehicleLists = await Promise.all(
    chunk([...vehicleIds], 200).map((ids) =>
      safe(errors, "vehicles", () =>
        client.from("vehicles").select("id,user_id,vehicle_type,car_brand,car_model,car_number").in("id", ids))),
  );

  // Totals (cheap head counts).
  const countOf = async (table: string, sinceIso?: string) => {
    try {
      let q = client.from(table).select("id", { count: "exact", head: true });
      if (sinceIso) q = q.gte("created_at", sinceIso).lt("created_at", to);
      const { count, error } = await q;
      if (error) {
        errors[`count_${table}`] = error.message;
        return null;
      }
      return count ?? 0;
    } catch (e) {
      errors[`count_${table}`] = e instanceof Error ? e.message : String(e);
      return null;
    }
  };
  const [totalProfiles, totalVehicles, newVehicles] = await Promise.all([
    countOf("profiles"),
    countOf("vehicles"),
    countOf("vehicles", from),
  ]);

  // Test traffic: App Store / Play review accounts and the partners they route to.
  const reviewEmails = [...new Set(reviewOverrides.map((r) => String(r.customer_email).toLowerCase()))];
  const reviewUsers = reviewEmails.length
    ? await safe(errors, "review_users", () => client.from("profiles").select("id,email").in("email", reviewEmails))
    : [];
  const reviewPartners = {
    admin: reviewOverrides.filter((r) => r.role === "admin").map((r) => String(r.member_ref)),
    delivery: reviewOverrides.filter((r) => r.role === "delivery").map((r) => String(r.member_ref)),
    washer: reviewOverrides.filter((r) => r.role === "washer").map((r) => String(r.member_ref)),
  };

  return {
    generated_at: new Date().toISOString(),
    range: { from, to },
    bookings,
    offer,
    resolve,
    addons,
    pollution,
    inspection,
    claims,
    fleet,
    monthly,
    wash_log: washLog,
    detailing,
    cancellations,
    payment_intents: intents,
    partners: { admins, delivery: deliveryPartners, washers },
    customers: profileLists.flat(),
    vehicles: vehicleLists.flat(),
    totals: { profiles: totalProfiles, vehicles: totalVehicles, new_vehicles: newVehicles },
    chat_reports: chatReports,
    unread_chats: unreadChats,
    test: { user_ids: reviewUsers.map((r) => String(r.id)), emails: reviewEmails, partners: reviewPartners },
    errors,
  };
}

const DETAIL_TABLES = new Set([
  "bookings", "pollution_booking", "inspection_booking", "claim_table",
  "fleet_pickup_requests", "monthlywash_table", "detailing_bookings", "offer_bookings", "resolve_requests",
  "addon_services",
]);

async function detail(client: SupabaseClient, body: Row) {
  const table = String(body.table ?? "");
  const id = String(body.id ?? "");
  if (!DETAIL_TABLES.has(table) || !id) throw new HttpError(400, "bad_request", "Unknown record.");
  const errors: Record<string, string> = {};
  const rows = await safe(errors, table, () => client.from(table).select("*").eq("id", id).limit(1));
  if (!rows.length) throw new HttpError(404, "not_found", "Record not found.");

  const extra: Record<string, Row[]> = {};
  if (table === "bookings") {
    [extra.updates, extra.chats, extra.addons] = await Promise.all([
      safe(errors, "booking_updates", () =>
        client.from("booking_updates").select("*").eq("booking_id", id).order("created_at")),
      safe(errors, "booking_chats", () =>
        client.from("booking_chats").select("id,message,sender,created_at").eq("booking_id", id).order("created_at")),
      safe(errors, "addon_services", () =>
        client.from("addon_services").select("*").eq("booking_id", id).order("created_at")),
    ]);
  } else if (table === "claim_table") {
    extra.updates = await safe(errors, "claim_table_updates", () =>
      client.from("claim_table_updates").select("*").eq("claim_id", id).order("created_at"));
  } else if (table === "monthlywash_table") {
    extra.washes = await safe(errors, "service_history", () =>
      client.from("service_history").select("*").eq("subscription_id", id).order("created_at"));
  } else if (table === "fleet_pickup_requests") {
    extra.chats = await safe(errors, "fleet_chat_messages", () =>
      client.from("fleet_chat_messages").select("id,message,sender_type,sender_name,created_at")
        .eq("request_id", id).order("created_at"));
    (extra as Record<string, unknown>).inspection21 = await inspection21Info(client, rows[0]);
  }
  if (isInvoiceTable(table)) {
    extra.invoices = await safe(errors, "invoices", () =>
      client.from("invoices").select("*").eq("booking_table", table).eq("booking_id", id)
        .order("created_at", { ascending: false }));
  }
  const intent = await safe(errors, "payment_intents", () =>
    client.from("payment_intents").select("id,status,amount,payment_method,razorpay_order_id,razorpay_payment_id,error,created_at")
      .eq("booking_table", table).eq("booking_id", id).limit(1));
  if (ASSIGN_TABLES.has(table)) extra.assignments = await assignmentHistory(client, table, id);
  return { row: rows[0], ...extra, intent: intent[0] ?? null, errors };
}

// ReperiResolve: staff send the customer a price, a note and (optionally) a
// photo. The photo goes in the customer's own folder of the private
// resolve-media bucket so their app can open it.
async function resolveQuote(client: SupabaseClient, body: Row, user: User) {
  const id = String(body.id ?? "");
  const price = Number(body.price);
  // Always added to the customer's note when a price is sent from the CRM.
  const DISCLAIMER =
    "The offered price is the best estimate our partner can provide by visual inspection of images, but prices may vary by 20%.";
  const typed = String(body.note ?? "").replace(DISCLAIMER, "").trim().slice(0, 1800);
  const note = typed ? `${typed}\n\n${DISCLAIMER}` : DISCLAIMER;
  if (!id) throw new HttpError(400, "bad_request", "Missing request.");
  if (!Number.isFinite(price) || price <= 0 || price > 10_000_000) {
    throw new HttpError(400, "bad_price", "Enter a valid price.");
  }
  const { data: row, error } = await client.from("resolve_requests")
    .select("id,user_id,status,quote_image_path").eq("id", id).maybeSingle();
  if (error) throw error;
  if (!row) throw new HttpError(404, "not_found", "Request not found.");
  if (row.status === "Closed" || row.status === "Cancelled") {
    throw new HttpError(400, "closed", "This request is closed.");
  }

  let imagePath: string | null = (row.quote_image_path as string | null) ?? null;
  if (body.removeImage) imagePath = null;
  const b64 = typeof body.image === "string" ? body.image.replace(/^data:[^,]+,/, "") : "";
  if (b64) {
    const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    if (bytes.length > 8 * 1024 * 1024) throw new HttpError(400, "too_big", "Image is too large (max 8 MB).");
    imagePath = `${row.user_id}/quotes/${id}-${Date.now()}.jpg`;
    const { error: upErr } = await client.storage.from("resolve-media")
      .upload(imagePath, bytes, { contentType: "image/jpeg", upsert: true });
    if (upErr) throw upErr;
  }

  const { data: updated, error: updErr } = await client.from("resolve_requests").update({
    quoted_price: price,
    quote_note: note || null,
    quote_image_path: imagePath,
    quoted_by: user.email ?? null,
    // Re-sending a price after the customer accepted puts it back to "Quoted"
    // so they can accept the new one.
    status: "Quoted",
    accepted_at: null,
  }).eq("id", id).select("*").single();
  if (updErr) throw updErr;
  return { row: updated };
}

// ReperiResolve: hand a request to a garage (it then shows in that garage's
// app, where they can see the customer's photos and send a price).
async function resolveAssign(client: SupabaseClient, body: Row) {
  const id = String(body.id ?? "");
  if (!id) throw new HttpError(400, "bad_request", "Missing request.");
  const raw = body.admin_id === null || body.admin_id === undefined ? "" : String(body.admin_id).trim();
  let adminId: string | null = null;
  if (raw) {
    const { data: admin, error } = await client.from("admin").select("id").eq("id", raw).maybeSingle();
    if (error) throw error;
    if (!admin) throw new HttpError(400, "bad_garage", "That garage doesn't exist.");
    adminId = String(admin.id);
  }
  const { data, error } = await client.from("resolve_requests")
    .update({ assigned_to_admin_id: adminId, assigned_at: adminId ? new Date().toISOString() : null })
    .eq("id", id).select("*").single();
  if (error) throw error;
  return { row: data };
}

// Inspection visits (Doorstep Car Inspection in `bookings`, Vehicle Health
// Check in `inspection_booking`): staff pick the expert from the delivery
// partners. The DB trigger notifies the customer and the partner.
const INSPECTION_TABLES = new Set(["bookings", "inspection_booking"]);

async function inspectionAssign(client: SupabaseClient, body: Row) {
  const table = String(body.table ?? "");
  const id = String(body.id ?? "");
  if (!INSPECTION_TABLES.has(table) || !id) throw new HttpError(400, "bad_request", "Unknown inspection.");
  const raw = body.partner_id === null || body.partner_id === undefined ? "" : String(body.partner_id).trim();

  const { data: row, error } = await client.from(table)
    .select("id,inspection_stage,delivery_partner_id").eq("id", id).maybeSingle();
  if (error) throw error;
  if (!row || !row.inspection_stage) throw new HttpError(404, "not_found", "Inspection not found.");
  if (row.inspection_stage === "completed") {
    throw new HttpError(400, "completed", "This inspection is already completed.");
  }

  let partnerId: number | null = null;
  if (raw) {
    const { data: partner, error: pErr } = await client.from("delivery_partners")
      .select("id").eq("id", raw).maybeSingle();
    if (pErr) throw pErr;
    if (!partner) throw new HttpError(400, "bad_partner", "That delivery partner doesn't exist.");
    partnerId = Number(partner.id);
  }
  if (String(row.delivery_partner_id ?? "") === String(partnerId ?? "")) return { row };

  // New (or no) expert → the visit starts again for them.
  const update = partnerId === null
    ? {
      delivery_partner_id: null, inspection_stage: "assigning", inspection_assigned_at: null,
      inspection_on_the_way_at: null, inspection_analyzing_at: null,
    }
    : {
      delivery_partner_id: partnerId, inspection_stage: "assigned", inspection_assigned_at: new Date().toISOString(),
      inspection_on_the_way_at: null, inspection_analyzing_at: null,
    };
  const { data, error: uErr } = await client.from(table).update(update).eq("id", id).select("*").single();
  if (uErr) throw uErr;
  return { row: strip([data as Row])[0] };
}

async function inspectionPhotos(client: SupabaseClient, body: Row) {
  const paths = (Array.isArray(body.paths) ? body.paths : [])
    .map((p: unknown) => String(p ?? "").replace(/^\/+/, ""))
    .filter((p: string) => p && !p.includes("..") && /^(bookings|inspection_booking)\//.test(p))
    .slice(0, 60);
  if (!paths.length) return { urls: {} };
  const { data, error } = await client.storage.from("inspection-photos").createSignedUrls(paths, 300);
  if (error) throw error;
  const urls: Record<string, string> = {};
  for (const d of data ?? []) if (d.path && d.signedUrl) urls[d.path] = d.signedUrl;
  return { urls };
}

async function signedDoc(client: SupabaseClient, body: Row) {
  const path = String(body.path ?? "").replace(/^\/+/, "");
  if (!path || path.includes("..")) throw new HttpError(400, "bad_request", "Invalid document.");
  if (/^https?:\/\//i.test(path)) return { url: path };
  const bucket = body.bucket === "booking-images" || body.bucket === "subscription-services" ||
      body.bucket === "resolve-media" || body.bucket === "inspection-photos" || body.bucket === "invoices" ||
      body.bucket === "fleet-quotations"
    ? String(body.bucket)
    : "insurance-documents";
  const { data, error } = await client.storage.from(bucket).createSignedUrl(path, 300);
  if (error || !data?.signedUrl) throw new HttpError(404, "not_found", "Document not found.");
  return { url: data.signedUrl };
}

// ── Assignments: override on one booking + the automatic rules ─────────
// supabase/assignments.sql. Every change is written to assignment_log.

const ASSIGN_COLS = { garage: "assigned_to_admin_id", delivery: "delivery_partner_id", washer: "washer_id" } as const;
type AssignRole = keyof typeof ASSIGN_COLS;
const ASSIGN_TABLES = new Set([
  "bookings", "offer_bookings", "pollution_booking", "inspection_booking",
  "claim_table", "monthlywash_table", "fleet_pickup_requests",
]);
const ONESIGNAL_APP_ID = "6bc39a67-c05a-4ba4-b950-9ccfc8e9b9b6";

async function pushTo(externalId: string, title: string, message: string, data: Row) {
  const key = Deno.env.get("ONESIGNAL_REST_API_KEY") ?? "";
  if (!key) return;
  try {
    await fetch("https://api.onesignal.com/notifications", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Key ${key}` },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        include_aliases: { external_id: [externalId] },
        target_channel: "push",
        headings: { en: title },
        contents: { en: message },
        data,
      }),
    });
  } catch (e) {
    console.error("assignment push failed", e);
  }
}

/** Display name for a garage / delivery partner / washer id. */
async function personName(client: SupabaseClient, role: AssignRole, id: string | null): Promise<string | null> {
  if (!id) return null;
  if (role === "garage") {
    const { data } = await client.from("admin").select("username").eq("id", id).maybeSingle();
    return (data?.username as string) ?? null;
  }
  const table = role === "delivery" ? "delivery_partners" : "washers";
  const { data } = await client.from(table).select("*").eq("id", id).maybeSingle();
  if (!data) return null;
  return String(data.name ?? data.full_name ?? data.email ?? data.username ?? `#${id}`);
}

async function logChange(client: SupabaseClient, entry: Row) {
  const { error } = await client.from("assignment_log").insert(entry);
  if (error) console.error("assignment_log insert failed", error);
}

/** Change the garage / delivery partner / washer on one booking. */
async function assignOverride(client: SupabaseClient, body: Row, user: User) {
  const table = String(body.table ?? "");
  const id = String(body.id ?? "");
  const role = String(body.role ?? "") as AssignRole;
  if (!ASSIGN_TABLES.has(table) || !id) throw new HttpError(400, "bad_request", "Unknown booking.");
  if (!(role in ASSIGN_COLS)) throw new HttpError(400, "bad_request", "Choose garage, delivery partner or washer.");
  const col = ASSIGN_COLS[role];
  const to = body.to === null || body.to === "" || body.to === undefined ? null : String(body.to);
  const reason = String(body.reason ?? "").trim().slice(0, 300) || null;

  const { data: row, error } = await client.from(table).select("*").eq("id", id).maybeSingle();
  if (error) throw error;
  if (!row) throw new HttpError(404, "not_found", "Booking not found.");
  if (!(col in row)) throw new HttpError(400, "not_used", "This booking type doesn't have that role.");
  if (role === "delivery" && row.inspection_stage) {
    throw new HttpError(400, "inspection", "This is an inspection visit — change the expert in the Inspection visit box.");
  }

  const from = row[col] == null ? null : String(row[col]);
  if (from === to) return { ok: true, unchanged: true };

  // Check the new person exists.
  let toName: string | null = null;
  if (to) {
    toName = await personName(client, role, to);
    if (!toName) throw new HttpError(404, "not_found", "That person was not found.");
  }
  const fromName = await personName(client, role, from);

  const value = to === null ? null : role === "garage" ? to : Number(to);
  const patch: Row = { [col]: value };
  if (role === "garage" && "assigned_at" in row) patch.assigned_at = new Date().toISOString();
  const { error: upErr } = await client.from(table).update(patch).eq("id", id);
  if (upErr) throw upErr;

  await logChange(client, {
    booking_table: table, booking_id: id, role,
    from_id: from, to_id: to, from_name: fromName, to_name: toName,
    reason, changed_by: user.email ?? "crm",
  });

  // Tell the new person.
  if (to) {
    const what = String(row.package_name ?? row.vehicle_model ?? row.plan_title ?? "A booking");
    const data = { type: "assignment", table, id };
    if (role === "delivery") await pushTo(`delivery_${to}`, "New trip assigned to you", `${what} — open your dashboard for details.`, data);
    else if (role === "washer") await pushTo(`washer_${to}`, "New wash assigned to you", `${what} — open your dashboard for details.`, data);
    else await pushTo("admin", "Booking assigned to your garage", `${what} has been assigned to ${toName}.`, data);
  }
  return { ok: true, from, to, toName };
}

async function assignmentHistory(client: SupabaseClient, table: string, id: string) {
  const { data } = await client.from("assignment_log").select("*")
    .eq("booking_table", table).eq("booking_id", id).order("created_at", { ascending: false }).limit(50);
  return data ?? [];
}

// ── Automatic rules ──
async function rulesGet(client: SupabaseClient) {
  const [pools, members, services, admins, delivery, washers, setting, fleetRules, fleetReqs, log] = await Promise.all([
    client.from("assignment_pools").select("*").order("role").order("key"),
    client.from("assignment_pool_members").select("*").order("position").order("member_ref"),
    client.from("services").select("key,name,booking_name,category,active,booking_table,admin_pool,delivery_pool,washer_pool").order("sort_order"),
    client.from("admin").select("id,username,vehicle").order("username"),
    client.from("delivery_partners").select("*").order("id"),
    client.from("washers").select("*").order("id"),
    client.from("app_settings").select("value").eq("key", "fleet_default_admin_id").maybeSingle(),
    client.from("fleet_garage_rules").select("*"),
    client.from("fleet_pickup_requests").select("fleet_user_id,company_name,username,created_at").order("created_at", { ascending: false }).limit(2000),
    client.from("assignment_log").select("*").eq("role", "rule").order("created_at", { ascending: false }).limit(30),
  ]);
  for (const r of [pools, members, services, admins, delivery, washers]) if (r.error) throw r.error;
  // One row per fleet company that has ever sent a request.
  const fleets = new Map<string, Row>();
  for (const f of fleetReqs.data ?? []) {
    const k = String(f.fleet_user_id ?? "");
    if (k && !fleets.has(k)) fleets.set(k, { fleet_user_id: k, company_name: f.company_name, username: f.username });
  }
  const label = (p: Row) => String(p.name ?? p.full_name ?? p.email ?? p.username ?? `#${p.id}`);
  return {
    pools: pools.data, members: members.data, services: services.data,
    people: {
      garage: (admins.data ?? []).map((a) => ({ id: String(a.id), name: String(a.username), extra: a.vehicle ?? null })),
      delivery: (delivery.data ?? []).map((d) => ({ id: String(d.id), name: label(d), extra: null })),
      washer: (washers.data ?? []).map((w) => ({ id: String(w.id), name: label(w), extra: null })),
    },
    fleetDefault: setting.data ? String(setting.data.value ?? "").replace(/"/g, "") : null,
    fleetRules: fleetRules.data ?? [],
    fleets: [...fleets.values()],
    log: log.data ?? [],
  };
}

const POOL_ROLES = new Set(["admin", "delivery", "washer"]);

async function rulesSave(client: SupabaseClient, body: Row, user: User) {
  const op = String(body.op ?? "");
  const who = user.email ?? "crm";
  const note = async (text: string) =>
    logChange(client, { booking_table: "rules", booking_id: "-", role: "rule", reason: text.slice(0, 300), changed_by: who });

  switch (op) {
    case "pool_create": {
      const key = String(body.key ?? "").trim().toLowerCase().replace(/[^a-z0-9_]/g, "_");
      const role = String(body.role ?? "");
      if (!/^[a-z0-9_]{3,40}$/.test(key)) throw new HttpError(400, "bad_key", "Use 3–40 letters, numbers or _ for the pool name.");
      if (!POOL_ROLES.has(role)) throw new HttpError(400, "bad_role", "Choose garage, delivery or washer.");
      const { error } = await client.from("assignment_pools").insert({
        key, role, batch_size: Math.max(1, Math.min(50, Number(body.batch_size) || 1)),
        description: String(body.description ?? "").trim().slice(0, 200) || null,
      });
      if (error) throw error.code === "23505" ? new HttpError(400, "exists", "A pool with that name already exists.") : error;
      await note(`Created pool ${key}`);
      break;
    }
    case "pool_update": {
      const key = String(body.key ?? "");
      const patch: Row = {};
      if (typeof body.active === "boolean") patch.active = body.active;
      if (body.batch_size !== undefined) patch.batch_size = Math.max(1, Math.min(50, Number(body.batch_size) || 1));
      if (body.description !== undefined) patch.description = String(body.description ?? "").trim().slice(0, 200) || null;
      const { error } = await client.from("assignment_pools").update(patch).eq("key", key);
      if (error) throw error;
      await note(`Pool ${key}: ${JSON.stringify(patch)}`);
      break;
    }
    case "member_add": {
      const pool = String(body.pool ?? "");
      const ref = String(body.member ?? "");
      const { data: p } = await client.from("assignment_pools").select("role").eq("key", pool).maybeSingle();
      if (!p) throw new HttpError(404, "not_found", "Pool not found.");
      const role = p.role === "admin" ? "garage" : (p.role as AssignRole);
      const name = await personName(client, role, ref);
      if (!name) throw new HttpError(404, "not_found", "That person was not found.");
      const { data: last } = await client.from("assignment_pool_members").select("position").eq("pool_key", pool)
        .order("position", { ascending: false }).limit(1);
      const { error } = await client.from("assignment_pool_members").upsert({
        pool_key: pool, member_ref: ref, label: name, active: true, position: Number(last?.[0]?.position ?? 0) + 1,
      });
      if (error) throw error;
      await note(`Added ${name} to ${pool}`);
      break;
    }
    case "member_update": {
      const pool = String(body.pool ?? "");
      const ref = String(body.member ?? "");
      if (body.remove === true) {
        const { error } = await client.from("assignment_pool_members").delete().eq("pool_key", pool).eq("member_ref", ref);
        if (error) throw error;
        await note(`Removed ${ref} from ${pool}`);
      } else if (typeof body.active === "boolean") {
        const { error } = await client.from("assignment_pool_members").update({ active: body.active })
          .eq("pool_key", pool).eq("member_ref", ref);
        if (error) throw error;
        await note(`${body.active ? "Turned on" : "Turned off"} ${ref} in ${pool}`);
      } else if (body.move === "up" || body.move === "down") {
        // Re-number the pool in its current order, then swap.
        const { data: list, error } = await client.from("assignment_pool_members").select("member_ref,position")
          .eq("pool_key", pool).order("position").order("member_ref");
        if (error) throw error;
        const refs = (list ?? []).map((m) => String(m.member_ref));
        const i = refs.indexOf(ref);
        const j = body.move === "up" ? i - 1 : i + 1;
        if (i >= 0 && j >= 0 && j < refs.length) {
          [refs[i], refs[j]] = [refs[j], refs[i]];
          for (let k = 0; k < refs.length; k++) {
            await client.from("assignment_pool_members").update({ position: k + 1 }).eq("pool_key", pool).eq("member_ref", refs[k]);
          }
          await note(`Moved ${ref} ${body.move} in ${pool}`);
        }
      }
      break;
    }
    case "service_pool": {
      const key = String(body.service ?? "");
      const field = String(body.field ?? "");
      if (!["admin_pool", "delivery_pool", "washer_pool"].includes(field)) throw new HttpError(400, "bad_request", "Unknown field.");
      const value = body.value === null || body.value === "" ? null : String(body.value);
      if (value && !value.includes("{vehicle}")) {
        const { data: p } = await client.from("assignment_pools").select("key").eq("key", value).maybeSingle();
        if (!p) throw new HttpError(404, "not_found", "Pool not found.");
      }
      const { error } = await client.from("services").update({ [field]: value }).eq("key", key);
      if (error) throw error;
      await note(`Service ${key}: ${field} → ${value ?? "none"}`);
      break;
    }
    case "fleet_default": {
      const id = String(body.admin_id ?? "");
      const name = await personName(client, "garage", id);
      if (!name) throw new HttpError(404, "not_found", "Garage not found.");
      const { error } = await client.from("app_settings").upsert({ key: "fleet_default_admin_id", value: id });
      if (error) throw error;
      await note(`Default fleet garage → ${name}`);
      break;
    }
    case "fleet_rule": {
      const fleetId = String(body.fleet_user_id ?? "");
      if (!fleetId) throw new HttpError(400, "bad_request", "Missing fleet.");
      if (body.admin_id === null || body.admin_id === "") {
        const { error } = await client.from("fleet_garage_rules").delete().eq("fleet_user_id", fleetId);
        if (error) throw error;
        await note(`Fleet ${body.company_name ?? fleetId} → default garage`);
      } else {
        const id = String(body.admin_id);
        const name = await personName(client, "garage", id);
        if (!name) throw new HttpError(404, "not_found", "Garage not found.");
        const { error } = await client.from("fleet_garage_rules").upsert({
          fleet_user_id: fleetId, admin_id: id, company_name: body.company_name ?? null,
          updated_by: who, updated_at: new Date().toISOString(),
        });
        if (error) throw error;
        await note(`Fleet ${body.company_name ?? fleetId} → ${name}`);
      }
      break;
    }
    default:
      throw new HttpError(400, "invalid_action", "Unknown change.");
  }
  return await rulesGet(client);
}

// ── Fleet 21-point inspection report (supabase/fleet_inspection.sql) ──
// Like the fleet, the CRM can open the report only once the bill is paid.
async function inspection21Info(client: SupabaseClient, row: Row) {
  const photos = Object.keys((row.inspection21_photos ?? {}) as Row).length;
  const info: Row = {
    status: row.inspection21_status ?? null,
    photos,
    paid: row.payment_status === "paid",
    error: row.inspection21_error ?? null,
    summary: row.inspection21_summary ?? null,
    url: null,
  };
  if (info.paid && row.inspection21_status === "ready" && row.inspection21_pdf_path) {
    const { data } = await client.storage.from("fleet-inspections").createSignedUrl(String(row.inspection21_pdf_path), 600);
    info.url = data?.signedUrl ?? null;
  }
  return info;
}

/** Make the report again (e.g. after a failure). */
async function inspection21Retry(client: SupabaseClient, body: Row) {
  const id = String(body.id ?? "");
  const { data: row } = await client.from("fleet_pickup_requests").select("id,inspection21_photos").eq("id", id).maybeSingle();
  if (!row) throw new HttpError(404, "not_found", "Request not found.");
  if (Object.keys((row.inspection21_photos ?? {}) as Row).length < 21) {
    throw new HttpError(400, "not_ready", "All 21 photos aren't in yet.");
  }
  const { data: s } = await client.from("app_settings").select("value").eq("key", "cron_secret").maybeSingle();
  await client.from("fleet_pickup_requests").update({ inspection21_status: "processing", inspection21_error: null }).eq("id", id);
  const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/fleet-inspection`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-inspection-secret": typeof s?.value === "string" ? s.value : "" },
    body: JSON.stringify({ action: "generate", id }),
  });
  if (!res.ok) throw new HttpError(502, "failed", "Couldn't start the report. Is the fleet-inspection function deployed?");
  return { ok: true };
}

// ── Payment QR (UPI collection at the door / garage) ──────────────────
const QR_BUCKET = "payment-qr";

async function qrList(client: SupabaseClient) {
  const { data, error } = await client.from("payment_qr_codes").select("*").order("created_at", { ascending: false });
  if (error) throw error;
  return { qrs: data ?? [] };
}

async function qrAdd(client: SupabaseClient, body: Row, user: User) {
  const label = String(body.label ?? "").trim().slice(0, 80);
  if (!label) throw new HttpError(400, "bad_request", "Give the QR a name, e.g. the bank account.");
  const m = typeof body.image === "string" ? body.image.match(/^data:(image\/(png|jpeg|webp));base64,(.+)$/) : null;
  if (!m) throw new HttpError(400, "bad_image", "Choose a PNG or JPG image of the QR.");
  const bytes = Uint8Array.from(atob(m[3]), (c) => c.charCodeAt(0));
  if (bytes.length > 5 * 1024 * 1024) throw new HttpError(400, "too_big", "Image is too large (max 5 MB).");
  const path = `qr-${Date.now()}.${m[2] === "jpeg" ? "jpg" : m[2]}`;
  const { error: upErr } = await client.storage.from(QR_BUCKET).upload(path, bytes, { contentType: m[1] });
  if (upErr) throw upErr;
  const url = client.storage.from(QR_BUCKET).getPublicUrl(path).data.publicUrl;

  const { data: current } = await client.from("payment_qr_codes").select("id").eq("active", true).limit(1);
  const makeActive = body.activate === true || !current?.length;
  if (makeActive && current?.length) {
    const { error } = await client.from("payment_qr_codes").update({ active: false }).eq("active", true);
    if (error) throw error;
  }
  const { error } = await client.from("payment_qr_codes").insert({
    label, image_path: path, image_url: url, active: makeActive, created_by: user.email ?? null,
  });
  if (error) throw error;
  return await qrList(client);
}

async function qrActivate(client: SupabaseClient, body: Row) {
  const id = String(body.id ?? "");
  const { data: row } = await client.from("payment_qr_codes").select("id").eq("id", id).maybeSingle();
  if (!row) throw new HttpError(404, "not_found", "QR not found.");
  const { error: offErr } = await client.from("payment_qr_codes").update({ active: false }).eq("active", true);
  if (offErr) throw offErr;
  const { error } = await client.from("payment_qr_codes").update({ active: true }).eq("id", id);
  if (error) throw error;
  return await qrList(client);
}

async function qrDelete(client: SupabaseClient, body: Row) {
  const id = String(body.id ?? "");
  const { data: row } = await client.from("payment_qr_codes").select("*").eq("id", id).maybeSingle();
  if (!row) throw new HttpError(404, "not_found", "QR not found.");
  if (row.active) throw new HttpError(400, "in_use", "This QR is in use. Pick another one first.");
  await client.storage.from(QR_BUCKET).remove([String(row.image_path)]);
  const { error } = await client.from("payment_qr_codes").delete().eq("id", id);
  if (error) throw error;
  return await qrList(client);
}

// ── Yellow Board: Quotations + Washing (fleet_services.sql) ─────────
// The fleet lists their own in the app. CRM lists ALL of them here.

async function fleetQuotationList(client: SupabaseClient, body: Row) {
  const status = typeof body.status === "string" ? String(body.status) : "";
  let q = client.from("fleet_quotation_requests")
    .select("id,fleet_user_id,company_name,username,vehicle_brand,vehicle_model,description,photo_path,status,price,assigned_to_admin_id,fleet_booking_id,created_at,accepted_at,priced_at")
    .order("created_at", { ascending: false }).limit(300);
  if (status === "pending") q = q.eq("status", "pending");
  else if (status === "priced") q = q.eq("status", "priced");
  else if (status === "accepted") q = q.eq("status", "accepted");
  const { data, error } = await q;
  if (error) throw error;
  // signed urls for the photos
  const rows = (data ?? []) as Row[];
  const urls: Record<string, string> = {};
  const paths = rows.map((r) => String(r.photo_path ?? "")).filter(Boolean);
  if (paths.length) {
    const { data: signed } = await client.storage.from("fleet-quotations").createSignedUrls(paths, 300);
    for (const s of signed ?? []) if (s.path && s.signedUrl) urls[s.path] = s.signedUrl;
  }
  return { quotations: rows.map((r) => ({ ...r, photo_url: urls[String(r.photo_path ?? "")] ?? null })) };
}

/** CRM sets the price on a quotation → fleet sees "priced". */
async function fleetQuotationPrice(client: SupabaseClient, body: Row, user: User) {
  const id = String(body.id ?? "");
  const price = Math.round(Number(body.price));
  if (!id) throw new HttpError(400, "bad_request", "Missing quotation.");
  if (!Number.isFinite(price) || price < 1) throw new HttpError(400, "bad_request", "Enter a valid price.");
  const { data: row, error: rErr } = await client.from("fleet_quotation_requests")
    .select("id,status,fleet_user_id").eq("id", id).maybeSingle();
  if (rErr) throw rErr;
  if (!row) throw new HttpError(404, "not_found", "Quotation not found.");
  if (!(row.status === "pending" || row.status === "priced")) {
    throw new HttpError(409, "wrong_state", "This quotation already moved on.");
  }
  const { error } = await client.from("fleet_quotation_requests").update({
    status: "priced",
    price,
    priced_at: new Date().toISOString(),
    priced_by: user.email ?? null,
    has_unread_update: true,
    latest_update_type: "PRICED",
  }).eq("id", id);
  if (error) throw error;
  return { ok: true };
}

/** CRM assigns a garage to an ACCEPTED quotation → creates a fleet_pickup_requests row. */
async function fleetQuotationAssignGarage(client: SupabaseClient, body: Row, user: User) {
  const id = String(body.id ?? "");
  const adminId = typeof body.admin_id === "string" ? body.admin_id.trim() : "";
  if (!id || !adminId) throw new HttpError(400, "bad_request", "Pick a garage.");
  const { data: q, error: qErr } = await client.from("fleet_quotation_requests")
    .select("*").eq("id", id).maybeSingle();
  if (qErr) throw qErr;
  if (!q) throw new HttpError(404, "not_found", "Quotation not found.");
  if (q.status !== "accepted") throw new HttpError(409, "wrong_state", "The fleet hasn't accepted this quotation yet.");

  // Pick a delivery partner from the fleet rotation.
  const { data: partnerText } = await client.rpc("next_pool_member", { p_pool: "delivery_fleet" });
  const partnerId = partnerText && Number.isInteger(Number(partnerText)) ? Number(partnerText) : null;
  const now = new Date().toISOString();
  const vehicleModel = String(q.vehicle_model ?? q.vehicle_brand ?? "Vehicle");

  // Create the fleet pickup row. No photo-url (no photo of the whole car yet;
  // delivery partner takes the 21 inspection photos at pickup).
  const { data: ins, error: iErr } = await client.from("fleet_pickup_requests").insert({
    fleet_user_id: q.fleet_user_id,
    company_name: q.company_name,
    username: q.username,
    vehicle_model: vehicleModel,
    car_number: "SET AT PICKUP",
    vehicle_photo_url: q.photo_path ? `quotation:${q.photo_path}` : null,
    status: "Pending",
    // The quote price is NOT the bill — it is kept as a reference only.
    // The garage builds the actual bill via add-ons, which the fleet
    // pays by Razorpay or Cash on Delivery.
    quoted_amount: q.price,
    quotation_id: id,
    assigned_to_admin_id: adminId,
    assigned_at: now,
    ...(partnerId !== null ? { delivery_partner_id: partnerId, delivery_stage: "assigned", stage_assigned_at: now } : {}),
  }).select("id").single();
  if (iErr) throw iErr;

  await client.from("fleet_quotation_requests").update({
    status: "assigned",
    assigned_to_admin_id: adminId,
    fleet_booking_id: ins.id,
    has_unread_update: true,
    latest_update_type: "GARAGE ASSIGNED",
  }).eq("id", id);

  await logChange(client, {
    booking_table: "fleet_quotation_requests", booking_id: id, role: "garage",
    from_id: null, to_id: adminId,
    reason: `Garage assigned by ${user.email ?? "staff"}. Created booking ${ins.id}.`,
    changed_by: user.email ?? null,
  });

  return { ok: true, fleet_booking_id: ins.id };
}

/** CRM declines a quotation (customer won't pay — stop it here). */
async function fleetQuotationDecline(client: SupabaseClient, body: Row) {
  const id = String(body.id ?? "");
  if (!id) throw new HttpError(400, "bad_request", "Missing quotation.");
  const { error } = await client.from("fleet_quotation_requests").update({
    status: "declined",
    declined_at: new Date().toISOString(),
    declined_reason: String(body.reason ?? "").slice(0, 300) || null,
    has_unread_update: true,
    latest_update_type: "DECLINED",
  }).eq("id", id);
  if (error) throw error;
  return { ok: true };
}

async function fleetWashingList(client: SupabaseClient, body: Row) {
  const paid = body.paid === true;
  let q = client.from("fleet_washing_requests")
    .select("id,fleet_user_id,company_name,username,vehicle_brand,vehicle_model,car_number,vehicle_photo_path,washer_id,amount,payment_status,status,created_at,assigned_at,paid_at")
    .order("created_at", { ascending: false }).limit(300);
  if (paid) q = q.eq("payment_status", "paid");
  const { data, error } = await q;
  if (error) throw error;
  return { washes: data ?? [] };
}

/** CRM assigns a washer and (optionally) adjusts the price. */
async function fleetWashingAssign(client: SupabaseClient, body: Row, user: User) {
  const id = String(body.id ?? "");
  const washerId = body.washer_id === null || body.washer_id === "" ? null :
    (Number.isInteger(Number(body.washer_id)) ? Number(body.washer_id) : null);
  if (!id) throw new HttpError(400, "bad_request", "Missing wash.");
  const { data: row, error: rErr } = await client.from("fleet_washing_requests")
    .select("*").eq("id", id).maybeSingle();
  if (rErr) throw rErr;
  if (!row) throw new HttpError(404, "not_found", "Wash not found.");

  const update: Row = {};
  if (washerId !== row.washer_id) {
    update.washer_id = washerId;
    update.assigned_at = washerId !== null ? new Date().toISOString() : null;
    update.status = washerId !== null ? "assigned" : "pending";
  }
  if (body.amount !== undefined && body.amount !== null && body.amount !== "") {
    const amount = Math.round(Number(body.amount));
    if (!Number.isFinite(amount) || amount < 1) throw new HttpError(400, "bad_request", "Enter a valid price.");
    // Changing the price after a Razorpay order was opened would charge the
    // wrong amount, so clear the order.
    if (row.payment_status !== "paid" && amount !== Number(row.amount)) {
      update.amount = amount;
      update.razorpay_order_id = null;
      update.has_unread_update = true;
      update.latest_update_type = "PRICE CHANGED";
    }
  }
  if (!Object.keys(update).length) return { ok: true };

  const { error } = await client.from("fleet_washing_requests").update(update).eq("id", id);
  if (error) throw error;

  await logChange(client, {
    booking_table: "fleet_washing_requests", booking_id: id,
    role: washerId !== row.washer_id ? "washer" : "rule",
    from_id: row.washer_id == null ? null : String(row.washer_id),
    to_id: washerId == null ? null : String(washerId),
    reason: `${washerId !== row.washer_id ? "Washer changed" : "Price changed"} by ${user.email ?? "staff"}.`,
    changed_by: user.email ?? null,
  });
  return { ok: true };
}

// ── Yellow Board: outstanding Cash on Delivery balances ──────────────
// Rolled up per fleet account (fleet_user_id). "Outstanding" = fleet
// picked Cash on Delivery for a bill that isn't paid yet.

async function fleetCodSummary(client: SupabaseClient) {
  // Pull every unpaid fleet bill that's on COD, roll up per fleet.
  const { data, error } = await client.from("fleet_pickup_requests")
    .select("fleet_user_id,company_name,username,total_amount")
    .eq("payment_method", "cash")
    .eq("payment_status", "awaiting_payment");
  if (error) throw error;
  const by: Record<string, Row> = {};
  for (const r of (data ?? []) as Row[]) {
    const key = String(r.fleet_user_id ?? "");
    if (!by[key]) by[key] = {
      fleet_user_id: r.fleet_user_id,
      company_name: r.company_name ?? r.username ?? `Fleet #${key}`,
      username: r.username ?? null,
      cod_amount: 0,
      bills: 0,
    };
    by[key].cod_amount = Number(by[key].cod_amount) + Math.round(Number(r.total_amount ?? 0));
    by[key].bills = Number(by[key].bills) + 1;
  }
  const summary = Object.values(by).sort((a, b) => Number(b.cod_amount) - Number(a.cod_amount));
  return { summary };
}

async function fleetCodDetail(client: SupabaseClient, body: Row) {
  const fleetUserId = String(body.fleet_user_id ?? "");
  if (!fleetUserId) throw new HttpError(400, "bad_request", "Missing fleet.");
  const { data, error } = await client.from("fleet_pickup_requests")
    .select("id,vehicle_model,car_number,total_amount,created_at,payment_method,payment_status,cash_collected_at,quoted_amount")
    .eq("fleet_user_id", fleetUserId)
    .eq("payment_method", "cash")
    .order("created_at", { ascending: false }).limit(200);
  if (error) throw error;
  return { bills: data ?? [] };
}

/** CRM marks a cash bill collected (payment_status flips to paid). */
async function fleetMarkCollected(client: SupabaseClient, body: Row, user: User) {
  const id = String(body.id ?? "");
  if (!id) throw new HttpError(400, "bad_request", "Missing bill.");
  const { data: row, error: rErr } = await client.from("fleet_pickup_requests")
    .select("id,payment_status,payment_method,total_amount").eq("id", id).maybeSingle();
  if (rErr) throw rErr;
  if (!row) throw new HttpError(404, "not_found", "Bill not found.");
  if (row.payment_method !== "cash") throw new HttpError(400, "not_cod", "This bill is not on Cash on Delivery.");
  if (row.payment_status === "paid") return { ok: true };

  const now = new Date().toISOString();
  const { error } = await client.from("fleet_pickup_requests").update({
    payment_status: "paid",
    cash_collected_at: now,
    cash_collected_by: user.email ?? null,
    has_unread_update: true,
    latest_update_type: "CASH COLLECTED",
  }).eq("id", id);
  if (error) throw error;
  return { ok: true };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const client = db();
    const user = await requireStaff(req, client);
    const body = (await req.json().catch(() => ({}))) as Row;
    switch (body.action) {
      case "me":
        return json({ email: user.email });
      case "snapshot":
        return json(await snapshot(client, body));
      case "detail":
        return json(await detail(client, body));
      case "doc":
        return json(await signedDoc(client, body));
      case "resolve_quote":
        return json(await resolveQuote(client, body, user));
      case "resolve_assign":
        return json(await resolveAssign(client, body));
      case "inspection_assign":
        return json(await inspectionAssign(client, body));
      case "inspection_photos":
        return json(await inspectionPhotos(client, body));
      case "assign":
        return json(await assignOverride(client, body, user));
      case "rules_get":
        return json(await rulesGet(client));
      case "rules_save":
        return json(await rulesSave(client, body, user));
      case "inspection21_retry":
        return json(await inspection21Retry(client, body));
      case "qr_list":
        return json(await qrList(client));
      case "qr_add":
        return json(await qrAdd(client, body, user));
      case "qr_activate":
        return json(await qrActivate(client, body));
      case "qr_delete":
        return json(await qrDelete(client, body));
      case "quotation_list":
        return json(await fleetQuotationList(client, body));
      case "quotation_price":
        return json(await fleetQuotationPrice(client, body, user));
      case "quotation_assign_garage":
        return json(await fleetQuotationAssignGarage(client, body, user));
      case "quotation_decline":
        return json(await fleetQuotationDecline(client, body));
      case "washing_list":
        return json(await fleetWashingList(client, body));
      case "washing_assign":
        return json(await fleetWashingAssign(client, body, user));
      case "fleet_cod_summary":
        return json(await fleetCodSummary(client));
      case "fleet_cod_detail":
        return json(await fleetCodDetail(client, body));
      case "fleet_mark_collected":
        return json(await fleetMarkCollected(client, body, user));
      case "invoice_issue": {
        const table = String(body.table ?? "");
        const id = String(body.id ?? "");
        if (!isInvoiceTable(table) || !id) throw new HttpError(400, "bad_request", "This booking type has no bill.");
        let lines;
        if (body.lines !== undefined && body.lines !== null) {
          try {
            lines = cleanLines(body.lines);
          } catch (e) {
            throw new HttpError(400, "bad_lines", e instanceof Error ? e.message : String(e));
          }
        }
        const reason = String(body.reason ?? "").trim().slice(0, 500) || null;
        const invoice = await issueInvoice(client, { table, id, lines, reason, createdBy: user.email ?? "crm" });
        return json({ invoice });
      }
      default:
        throw new HttpError(400, "invalid_action", "Unknown action.");
    }
  } catch (err) {
    if (err instanceof HttpError) return json({ error: err.code, message: err.message }, err.status);
    console.error("crm-api error:", err);
    // Staff-only tool: show the real reason so problems can be fixed quickly.
    const detail = err && typeof err === "object" && "message" in err ? String((err as { message: unknown }).message) : String(err);
    return json({ error: "unexpected", message: `Something went wrong: ${detail}`.slice(0, 300) }, 500);
  }
});

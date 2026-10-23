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
// POST { action: "me" }
//   → { email } — used by the page to confirm access after sign-in.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2";

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
  }
  const intent = await safe(errors, "payment_intents", () =>
    client.from("payment_intents").select("id,status,amount,payment_method,razorpay_order_id,razorpay_payment_id,error,created_at")
      .eq("booking_table", table).eq("booking_id", id).limit(1));
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
      body.bucket === "resolve-media" || body.bucket === "inspection-photos"
    ? String(body.bucket)
    : "insurance-documents";
  const { data, error } = await client.storage.from(bucket).createSignedUrl(path, 300);
  if (error || !data?.signedUrl) throw new HttpError(404, "not_found", "Document not found.");
  return { url: data.signedUrl };
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

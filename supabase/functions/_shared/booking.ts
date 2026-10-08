// Shared server-side booking logic for the `booking-api` and
// `razorpay-webhook` Edge Functions.
//
// The app never decides a price or who gets a booking any more:
//   1. quote   — prices a cart from the `services` table
//   2. create  — snapshots the cart into `payment_intents`, then either
//                opens a Razorpay order (online) or books straight away (COD)
//   3. confirm — after Razorpay checkout, verifies the signature and creates
//                the booking + assignments (the webhook does the same thing
//                as a backup if the phone never comes back)
//
// Everything that writes uses the service-role client, so RLS on the
// booking tables doesn't get in the way and the app can't fake any of it.

import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2";

// ── HTTP helpers ───────────────────────────────────────────────────────

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** An error whose `code` and `message` are safe to show the app. */
export class ApiError extends Error {
  constructor(
    public code: string,
    message: string,
    public status = 400,
    public extra: Record<string, unknown> = {},
  ) {
    super(message);
  }
}

export function errorResponse(err: unknown): Response {
  if (err instanceof ApiError) {
    return json({ error: err.code, message: err.message, ...err.extra }, err.status);
  }
  console.error("Unexpected error:", err);
  return json(
    { error: "unexpected", message: "Something went wrong on our side. Please try again." },
    500,
  );
}

// ── Clients ────────────────────────────────────────────────────────────

export function adminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

/** The signed-in customer, or null for anon / fleet callers. */
export async function getUser(req: Request, db: SupabaseClient): Promise<User | null> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;
  const { data, error } = await db.auth.getUser(token);
  if (error || !data?.user) return null; // the anon key itself isn't a user
  return data.user;
}

// ── Types ──────────────────────────────────────────────────────────────

export type BookingTable =
  | "bookings"
  | "pollution_booking"
  | "inspection_booking"
  | "claim_table"
  | "monthlywash_table";

type PickupMode = "optional" | "none" | "included" | "locked";

export interface ServiceRow {
  key: string;
  name: string;
  booking_name: string | null;
  screens: string[];
  price: number | null;
  active: boolean;
  is_addon: boolean;
  bookable: boolean;
  booking_table: BookingTable | null;
  vehicle_required: boolean;
  pickup_mode: PickupMode;
  allow_cod: boolean;
  admin_pool: string | null;
  delivery_pool: string | null;
  washer_pool: string | null;
  details: Record<string, unknown>;
}

const SERVICE_COLUMNS =
  "key,name,booking_name,screens,price,active,is_addon,bookable,booking_table," +
  "vehicle_required,pickup_mode,allow_cod,admin_pool,delivery_pool,washer_pool,details";

export interface Settings {
  pickupDropFee: number;
  reviewOverrideEnabled: boolean;
  serviceArea: { lat: number; lng: number; radius_km: number } | null;
}

export interface QuoteLine {
  key: string | null;
  name: string;
  amount: number;
}

export interface Quote {
  kind: "service" | "fleet";
  lines: QuoteLine[];
  subtotal: number;
  pickupMode: PickupMode;
  pickupFee: number; // the fee if pickup applies
  pickupDrop: boolean; // effective (after mode rules)
  pickupFeeCharged: number;
  total: number;
  allowCod: boolean;
  vehicleRequired: boolean;
  bookingTable: BookingTable | null;
  bookingName: string;
  services: ServiceRow[];
  primary: ServiceRow | null;
  fleetRequestId: string | null;
}

export interface QuoteInput {
  items?: unknown;
  pickup_drop?: unknown;
  fleet_request_id?: unknown;
}

// ── Settings ───────────────────────────────────────────────────────────

export async function loadSettings(db: SupabaseClient): Promise<Settings> {
  const { data, error } = await db.from("app_settings").select("key,value");
  if (error) throw error;
  const map = new Map<string, unknown>((data ?? []).map((r) => [r.key as string, r.value]));
  const fee = Number(map.get("pickup_drop_fee") ?? 100);
  const area = map.get("service_area") as Settings["serviceArea"] | undefined;
  return {
    pickupDropFee: Number.isFinite(fee) && fee >= 0 ? Math.round(fee) : 100,
    reviewOverrideEnabled: map.get("review_override_enabled") === true,
    serviceArea:
      area && typeof area.lat === "number" && typeof area.lng === "number" &&
        typeof area.radius_km === "number"
        ? area
        : null,
  };
}

// ── Formatting ─────────────────────────────────────────────────────────

/** ₹1,23,456 — Indian digit grouping, same as the app shows. */
export function rupees(amount: number): string {
  const s = Math.round(amount).toString();
  if (s.length <= 3) return `₹${s}`;
  const last3 = s.slice(-3);
  const rest = s.slice(0, -3).replace(/\B(?=(\d{2})+(?!\d))/g, ",");
  return `₹${rest},${last3}`;
}

// ── Quote ──────────────────────────────────────────────────────────────

function parseItems(raw: unknown): string[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new ApiError("invalid_items", "Pick a package to continue.");
  }
  if (raw.length > 10) throw new ApiError("invalid_items", "Too many items in one booking.");
  const keys = raw.map((k) => (typeof k === "string" ? k.trim() : ""));
  if (keys.some((k) => !/^[a-z0-9_]{1,64}$/.test(k))) {
    throw new ApiError("invalid_items", "That package isn't available.");
  }
  return [...new Set(keys)];
}

/** fleet_pickup_requests.id — accepts an integer id or a uuid. */
function parseFleetRequestId(raw: unknown): string | null {
  if (raw === undefined || raw === null || raw === "") return null;
  const id = String(raw).trim();
  if (!/^\d{1,18}$/.test(id) && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) {
    throw new ApiError("invalid_request", "Invalid fleet request.");
  }
  return id;
}

export async function loadServicesByKeys(
  db: SupabaseClient,
  keys: string[],
): Promise<ServiceRow[]> {
  const { data, error } = await db.from("services").select(SERVICE_COLUMNS).in("key", keys);
  if (error) throw error;
  const byKey = new Map(((data ?? []) as unknown as ServiceRow[]).map((r) => [r.key, r]));
  return keys.map((k) => byKey.get(k)).filter((r): r is ServiceRow => !!r);
}

export async function buildQuote(
  db: SupabaseClient,
  input: QuoteInput,
  settings: Settings,
): Promise<Quote> {
  const fleetRequestId = parseFleetRequestId(input.fleet_request_id);
  if (fleetRequestId !== null) return await buildFleetQuote(db, fleetRequestId);

  const keys = parseItems(input.items);
  const services = await loadServicesByKeys(db, keys);
  if (services.length !== keys.length) {
    throw new ApiError("service_unavailable", "This package is no longer available. Please go back and pick again.");
  }
  for (const s of services) {
    if (!s.active || !s.bookable || !s.booking_table) {
      throw new ApiError("service_unavailable", `${s.name} can't be booked online right now.`);
    }
    if (s.price === null) {
      throw new ApiError("not_payable", `${s.name} is priced after inspection — please contact us.`);
    }
  }

  const mains = services.filter((s) => !s.is_addon);
  const addons = services.filter((s) => s.is_addon);
  if (mains.length > 1) {
    throw new ApiError("one_package_only", "Please book one package at a time.");
  }
  const primary = mains[0] ?? null;
  if (primary) {
    for (const a of addons) {
      if (!a.screens.some((sc) => primary.screens.includes(sc))) {
        throw new ApiError("invalid_addon", `${a.name} can't be added to ${primary.name}.`);
      }
    }
  }
  const tables = new Set(services.map((s) => s.booking_table));
  if (tables.size !== 1) throw new ApiError("invalid_items", "These packages can't be booked together.");

  const route = primary ?? addons[0];
  const pickupMode = route.pickup_mode;
  const wantsPickup = input.pickup_drop === true;
  const pickupDrop =
    pickupMode === "included" || pickupMode === "locked" ? true : pickupMode === "optional" ? wantsPickup : false;
  const pickupFeeCharged =
    (pickupMode === "optional" && pickupDrop) || pickupMode === "locked" ? settings.pickupDropFee : 0;

  const lines: QuoteLine[] = services.map((s) => ({ key: s.key, name: s.name, amount: s.price as number }));
  const subtotal = lines.reduce((sum, l) => sum + l.amount, 0);

  let bookingName = primary
    ? primary.booking_name || primary.name
    : (addons[0].details?.["addons_only_booking_name"] as string | undefined) ?? addons[0].name;
  for (const a of addons) {
    const suffix = a.details?.["booking_suffix"];
    if (primary && typeof suffix === "string") bookingName += suffix;
  }

  return {
    kind: "service",
    lines,
    subtotal,
    pickupMode,
    pickupFee: settings.pickupDropFee,
    pickupDrop,
    pickupFeeCharged,
    total: subtotal + pickupFeeCharged,
    allowCod: services.every((s) => s.allow_cod),
    vehicleRequired: services.some((s) => s.vehicle_required),
    bookingTable: route.booking_table,
    bookingName,
    services,
    primary,
    fleetRequestId: null,
  };
}

async function buildFleetQuote(db: SupabaseClient, requestId: string): Promise<Quote> {
  const { data: req, error } = await db
    .from("fleet_pickup_requests")
    .select("id,company_name,total_amount,bill_items,payment_status")
    .eq("id", requestId)
    .maybeSingle();
  if (error) throw error;
  if (!req) throw new ApiError("not_found", "Fleet request not found.", 404);
  if (req.payment_status === "paid") throw new ApiError("already_paid", "This request is already paid.", 409);
  const total = Math.round(Number(req.total_amount ?? 0));
  if (!Number.isFinite(total) || total <= 0) {
    throw new ApiError("not_payable", "The garage hasn't added charges to this request yet.");
  }
  const items = Array.isArray(req.bill_items) ? req.bill_items as Array<Record<string, unknown>> : [];
  const lines: QuoteLine[] = items.length
    ? items.map((i) => ({ key: null, name: String(i["name"] ?? ""), amount: Math.round(Number(i["price"] ?? 0)) }))
    : [{ key: null, name: "Fleet service", amount: total }];
  return {
    kind: "fleet",
    lines,
    subtotal: total,
    pickupMode: "none",
    pickupFee: 0,
    pickupDrop: false,
    pickupFeeCharged: 0,
    total,
    allowCod: false,
    vehicleRequired: false,
    bookingTable: null,
    bookingName: `Fleet Service — ${req.company_name ?? ""}`.trim(),
    services: [],
    primary: null,
    fleetRequestId: requestId,
  };
}

/** What the app gets back for a quote. */
export function publicQuote(q: Quote) {
  return {
    kind: q.kind,
    lines: q.lines.map((l) => ({ key: l.key, name: l.name, amount: l.amount, display: rupees(l.amount) })),
    subtotal: q.subtotal,
    pickup_mode: q.pickupMode,
    pickup_fee: q.pickupFee,
    pickup_drop: q.pickupDrop,
    pickup_fee_charged: q.pickupFeeCharged,
    total: q.total,
    total_display: rupees(q.total),
    allow_cod: q.allowCod,
    vehicle_required: q.vehicleRequired,
    booking_name: q.bookingName,
  };
}

// ── Create (snapshot the cart) ─────────────────────────────────────────

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface Address {
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  name: string | null;
}

async function defaultAddress(db: SupabaseClient, userId: string): Promise<Address | null> {
  const { data, error } = await db
    .from("user_addresses")
    .select("name,address,latitude,longitude,is_default,created_at")
    .eq("user_id", userId)
    .order("is_default", { ascending: false })
    .order("created_at", { ascending: true })
    .limit(1);
  if (error) throw error;
  const a = data?.[0];
  if (!a) return null;
  return {
    address: a.address ?? null,
    latitude: a.latitude === null || a.latitude === undefined ? null : Number(a.latitude),
    longitude: a.longitude === null || a.longitude === undefined ? null : Number(a.longitude),
    name: a.name ?? null,
  };
}

function distanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function cleanText(raw: unknown, max: number): string | null {
  if (typeof raw !== "string") return null;
  // deno-lint-ignore no-control-regex -- stripping control characters is the point
  const t = raw.replace(/[\u0000-\u001f\u007f]/g, " ").trim();
  return t ? t.slice(0, max) : null;
}

const CLAIM_DOC_RE: Record<string, RegExp> = {
  rc: /^rc-copies\/claim-[A-Za-z0-9_-]{6,80}-rc\.pdf$/,
  license: /^driving-licenses\/claim-[A-Za-z0-9_-]{6,80}-license\.pdf$/,
  aadhaar: /^aadhaar\/claim-[A-Za-z0-9_-]{6,80}-aadhaar\.pdf$/,
  pan: /^pan\/claim-[A-Za-z0-9_-]{6,80}-pan\.pdf$/,
  insurance: /^insurance-copies\/claim-[A-Za-z0-9_-]{6,80}-insurance\.pdf$/,
  photo: /^damage-photos\/claim-[A-Za-z0-9_-]{6,80}-damage\.jpg$/,
};

/** Validates the per-table extra fields the booking needs. */
function validateOptions(quote: Quote, raw: unknown): Record<string, unknown> {
  const o = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const out: Record<string, unknown> = {};

  const label = cleanText(o["label"], 80);
  if (label) out.label = label;

  if (quote.bookingTable === "inspection_booking") {
    const insp = (o["inspection"] ?? {}) as Record<string, unknown>;
    const condition = cleanText(insp["condition"], 60);
    const slotDate = cleanText(insp["slot_date"], 10);
    const slotTime = cleanText(insp["slot_time"], 40);
    if (!condition || !slotDate || !slotTime || !/^\d{4}-\d{2}-\d{2}$/.test(slotDate)) {
      throw new ApiError("invalid_options", "Please pick the vehicle condition and a pickup slot.");
    }
    const today = new Date(Date.now() + 5.5 * 3600 * 1000).toISOString().slice(0, 10); // IST date
    if (slotDate < today) throw new ApiError("invalid_options", "That pickup slot is in the past.");
    out.inspection = { condition, slot_date: slotDate, slot_time: slotTime };
  }

  if (quote.bookingTable === "claim_table") {
    const c = (o["claim"] ?? {}) as Record<string, unknown>;
    const description = cleanText(c["description"], 2000);
    if (!description) throw new ApiError("invalid_options", "Please describe the damage.");
    const docs: Record<string, string> = {};
    for (const [field, re] of Object.entries(CLAIM_DOC_RE)) {
      const v = typeof c[field] === "string" ? (c[field] as string) : "";
      if (!re.test(v)) throw new ApiError("invalid_options", "Some claim documents are missing — please upload them again.");
      docs[field] = v;
    }
    out.claim = { description, ...docs };
  }
  return out;
}

export interface CreateInput extends QuoteInput {
  vehicle_id?: unknown;
  payment_method?: unknown;
  options?: unknown;
}

export interface Intent {
  id: string;
  kind: "service" | "fleet";
  user_id: string | null;
  customer_email: string | null;
  vehicle_id: string | null;
  items: Array<{ key: string; name: string; price: number }>;
  options: Record<string, unknown>;
  pickup_drop: boolean;
  pickup_fee: number;
  subtotal: number;
  amount: number;
  payment_method: "online" | "cod";
  status: "created" | "processing" | "booked" | "failed";
  razorpay_order_id: string | null;
  razorpay_payment_id: string | null;
  booking_table: string | null;
  booking_id: string | null;
}

export async function createIntent(
  db: SupabaseClient,
  user: User | null,
  input: CreateInput,
  settings: Settings,
): Promise<{ intent: Intent; quote: Quote }> {
  const quote = await buildQuote(db, input, settings);
  const method = input.payment_method === "cod" ? "cod" : "online";
  if (method === "cod" && !quote.allowCod) {
    throw new ApiError("cod_not_allowed", "This booking can only be paid online.");
  }

  const options: Record<string, unknown> = validateOptions(quote, input.options);
  let vehicleId: string | null = null;

  if (quote.kind === "service") {
    if (!user) throw new ApiError("sign_in_required", "Please sign in again to book.", 401);

    const rawVehicle = typeof input.vehicle_id === "string" ? input.vehicle_id.trim() : "";
    if (rawVehicle) {
      if (!UUID_RE.test(rawVehicle)) throw new ApiError("invalid_vehicle", "That vehicle couldn't be found.");
      const { data: v, error } = await db
        .from("vehicles")
        .select("id,vehicle_type")
        .eq("id", rawVehicle)
        .eq("user_id", user.id)
        .maybeSingle();
      if (error) throw error;
      if (!v) throw new ApiError("invalid_vehicle", "That vehicle couldn't be found on your account.");
      vehicleId = v.id;
      options.vehicle_type = v.vehicle_type ?? null;
    } else if (quote.vehicleRequired) {
      throw new ApiError("vehicle_required", "Add a vehicle to book this service.");
    }

    const address = await defaultAddress(db, user.id);
    if (!address || !address.address || address.latitude === null || address.longitude === null) {
      throw new ApiError("address_required", "Add a pickup address to continue.");
    }
    if (settings.serviceArea) {
      const km = distanceKm(settings.serviceArea.lat, settings.serviceArea.lng, address.latitude, address.longitude);
      if (km > settings.serviceArea.radius_km) {
        throw new ApiError("out_of_service_area", "We are not operational in your area yet! Try a different pickup address.");
      }
    }
    options.address = address;

    // Snapshot who the customer is, so the webhook can book without them.
    const { data: profile } = await db.from("profiles").select("*").eq("id", user.id).maybeSingle();
    const meta = (user.user_metadata ?? {}) as Record<string, unknown>;
    options.customer = {
      name: (profile?.full_name ?? profile?.name ?? meta["full_name"] ?? meta["name"] ?? "Unknown") as string,
      phone: (profile?.phone || user.phone || meta["phone"] || null) as string | null,
    };
  } else {
    options.fleet_request_id = quote.fleetRequestId;
  }

  const row = {
    kind: quote.kind,
    user_id: user?.id ?? null,
    customer_email: user?.email?.trim().toLowerCase() ?? null,
    vehicle_id: vehicleId,
    items: quote.kind === "service"
      ? quote.services.map((s) => ({ key: s.key, name: s.name, price: s.price as number }))
      : quote.lines.map((l) => ({ key: "fleet", name: l.name, price: l.amount })),
    options: { ...options, booking_name: quote.bookingName },
    pickup_drop: quote.pickupDrop,
    pickup_fee: quote.pickupFeeCharged,
    subtotal: quote.subtotal,
    amount: quote.total,
    payment_method: method,
    booking_table: quote.kind === "fleet" ? "fleet_pickup_requests" : quote.bookingTable,
  };
  const { data, error } = await db.from("payment_intents").insert(row).select("*").single();
  if (error) throw error;
  return { intent: data as Intent, quote };
}

// ── Razorpay ───────────────────────────────────────────────────────────

export async function createRazorpayOrder(intent: Intent): Promise<{ orderId: string; keyId: string }> {
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const secret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!keyId || !secret) throw new Error("RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET not set");
  const res = await fetch("https://api.razorpay.com/v1/orders", {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${keyId}:${secret}`)}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      amount: intent.amount * 100, // paise
      currency: "INR",
      receipt: `int_${intent.id.replace(/-/g, "").slice(0, 32)}`,
      notes: { intent_id: intent.id, kind: intent.kind },
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body?.id) {
    console.error("Razorpay order failed", res.status, body);
    throw new ApiError("payment_unavailable", "Couldn't start the payment. Please try again.", 502);
  }
  return { orderId: body.id as string, keyId };
}

async function hmacHex(secret: string, message: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
  ]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(message));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Razorpay checkout signature: HMAC_SHA256(order_id + "|" + payment_id, key_secret). */
export async function verifyCheckoutSignature(orderId: string, paymentId: string, signature: string): Promise<boolean> {
  const secret = Deno.env.get("RAZORPAY_KEY_SECRET");
  if (!secret) throw new Error("RAZORPAY_KEY_SECRET not set");
  return safeEqual(await hmacHex(secret, `${orderId}|${paymentId}`), signature);
}

/** Razorpay webhook signature: HMAC_SHA256(raw body, webhook secret). */
export async function verifyWebhookSignature(rawBody: string, signature: string): Promise<boolean> {
  const secret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");
  if (!secret) throw new Error("RAZORPAY_WEBHOOK_SECRET not set");
  return safeEqual(await hmacHex(secret, rawBody), signature);
}

// ── Assignment ─────────────────────────────────────────────────────────

/** 'garage_{vehicle}' → garage_four_wheeler / garage_two_wheeler / garage_any. */
function resolvePool(pool: string, vehicleType: unknown): string {
  if (!pool.includes("{vehicle}")) return pool;
  const vt = vehicleType === "two_wheeler" || vehicleType === "four_wheeler" ? vehicleType : "any";
  return pool.replace("{vehicle}", vt);
}

async function assign(
  db: SupabaseClient,
  role: "admin" | "delivery" | "washer",
  pool: string,
  intent: Intent,
  settings: Settings,
): Promise<string | null> {
  // App Store review account → its fixed demo partner, but only for roles
  // this service actually uses (same as the app's old override).
  if (settings.reviewOverrideEnabled && intent.customer_email) {
    const { data, error } = await db
      .from("review_overrides")
      .select("member_ref")
      .eq("customer_email", intent.customer_email)
      .eq("role", role)
      .maybeSingle();
    if (error) throw error;
    if (data?.member_ref) return data.member_ref as string;
  }

  const resolved = resolvePool(pool, intent.options["vehicle_type"]);
  const { data, error } = await db.rpc("next_pool_member", { p_pool: resolved });
  if (error) throw error;
  if (data) return data as string;

  // A vehicle-type garage pool with nobody in it falls back to all
  // garages rather than leaving the booking invisible to every admin.
  if (role === "admin" && resolved !== "garage_any" && pool.includes("{vehicle}")) {
    const { data: fallback, error: e2 } = await db.rpc("next_pool_member", { p_pool: "garage_any" });
    if (e2) throw e2;
    return (fallback as string | null) ?? null;
  }
  return null;
}

const toInt = (v: string | null) => (v === null ? null : Number.isInteger(Number(v)) ? Number(v) : null);

// ── Finalize (create the booking) ──────────────────────────────────────

export interface BookingResult {
  status: "booked" | "pending";
  booking_table?: string | null;
  booking_id?: string | null;
}

/**
 * Turns a paid (or COD) intent into exactly one booking row. Safe to call
 * any number of times from confirm, the webhook, and app retries — only
 * one caller ever gets past claim_payment_intent at a time, and an
 * already-booked intent just returns its booking.
 */
export async function finalizeIntent(
  db: SupabaseClient,
  intentId: string,
  paymentId: string | null,
  settings: Settings,
): Promise<BookingResult> {
  const { data: claimed, error: claimErr } = await db.rpc("claim_payment_intent", {
    p_intent: intentId,
    p_payment_id: paymentId,
  });
  if (claimErr) throw claimErr;
  const intent = (claimed as Intent[] | null)?.[0];

  if (!intent) {
    const { data: current, error } = await db
      .from("payment_intents")
      .select("status,booking_table,booking_id")
      .eq("id", intentId)
      .maybeSingle();
    if (error) throw error;
    if (!current) throw new ApiError("not_found", "Booking not found.", 404);
    if (current.status === "booked") {
      return { status: "booked", booking_table: current.booking_table, booking_id: current.booking_id };
    }
    return { status: "pending" };
  }

  try {
    const bookingId = await insertBooking(db, intent, settings);
    const { error } = await db
      .from("payment_intents")
      .update({ status: "booked", booking_id: bookingId, error: null })
      .eq("id", intent.id);
    if (error) throw error;
    return { status: "booked", booking_table: intent.booking_table, booking_id: bookingId };
  } catch (err) {
    const message = err instanceof Error ? err.message : JSON.stringify(err);
    console.error(`Booking save failed for intent ${intent.id}:`, message);
    await db.from("payment_intents").update({ status: "failed", error: message.slice(0, 500) }).eq("id", intent.id);
    throw new ApiError(
      "booking_save_failed",
      intent.payment_method === "online"
        ? "Your payment went through, but we couldn't save your booking yet. Tap retry — you won't be charged again."
        : "We couldn't save your booking. Please try again.",
      500,
      { intent_id: intent.id, payment_id: intent.razorpay_payment_id },
    );
  }
}

async function existingBookingFor(db: SupabaseClient, table: string, paymentId: string): Promise<string | null> {
  const column = table === "monthlywash_table" ? "payment_id" : "razorpay_payment_id";
  const { data, error } = await db.from(table).select("id").eq(column, paymentId).limit(1);
  if (error) throw error;
  return data?.[0]?.id !== undefined ? String(data[0].id) : null;
}

async function insertBooking(db: SupabaseClient, intent: Intent, settings: Settings): Promise<string> {
  const online = intent.payment_method === "online";
  const paymentId = intent.razorpay_payment_id;
  if (online && !paymentId) throw new Error("Missing payment id for an online intent");

  // ── Fleet "Pay Now" ──
  if (intent.kind === "fleet") {
    const requestId = String(intent.options["fleet_request_id"]);
    const { error } = await db
      .from("fleet_pickup_requests")
      .update({ payment_status: "paid", razorpay_order_id: intent.razorpay_order_id, razorpay_payment_id: paymentId })
      .eq("id", requestId);
    if (error) throw error;
    return requestId;
  }

  const table = intent.booking_table as BookingTable;
  // A crash between inserting and marking the intent booked must not
  // produce a second booking on retry.
  if (online && paymentId) {
    const existing = await existingBookingFor(db, table, paymentId);
    if (existing) return existing;
  }

  const keys = intent.items.map((i) => i.key);
  const services = await loadServicesByKeys(db, keys); // routing as configured now
  const route = services.find((s) => !s.is_addon) ?? services[0];
  if (!route) throw new Error("Services for this booking no longer exist");

  const adminRef = route.admin_pool ? await assign(db, "admin", route.admin_pool, intent, settings) : null;
  const deliveryRef = intent.pickup_drop && route.delivery_pool
    ? await assign(db, "delivery", route.delivery_pool, intent, settings)
    : null;
  const washerRef = route.washer_pool ? await assign(db, "washer", route.washer_pool, intent, settings) : null;

  const addr = (intent.options["address"] ?? {}) as Address;
  const customer = (intent.options["customer"] ?? {}) as { name?: string; phone?: string | null };
  const label = intent.options["label"] as string | undefined;
  const fmt = route.details?.["booking_label_format"];
  const bookingName = label && typeof fmt === "string"
    ? fmt.replace("{label}", label)
    : (intent.options["booking_name"] as string) ?? route.name;
  const price = rupees(intent.subtotal);
  const vehicle = intent.vehicle_id ? { vehicle_id: intent.vehicle_id } : {};
  const pickupDropAddress = {
    pickup_address: addr.address ?? "Not specified",
    pickup_latitude: addr.latitude ?? null,
    pickup_longitude: addr.longitude ?? null,
    pickup_address_name: addr.name ?? null,
    dropoff_address: addr.address ?? "Not specified",
    dropoff_latitude: addr.latitude ?? null,
    dropoff_longitude: addr.longitude ?? null,
    dropoff_address_name: addr.name ?? null,
  };
  const customerCols = { customer_name: customer.name ?? "Unknown", customer_phone: customer.phone ?? null };
  const rzpIds = online
    ? { razorpay_order_id: intent.razorpay_order_id, razorpay_payment_id: paymentId }
    : {};
  const rzpIdsOrCod = online
    ? { razorpay_order_id: intent.razorpay_order_id, razorpay_payment_id: paymentId }
    : { razorpay_order_id: "COD", razorpay_payment_id: "COD" };

  let row: Record<string, unknown>;
  switch (table) {
    case "bookings": {
      row = {
        user_id: intent.user_id,
        ...vehicle,
        package_name: bookingName,
        package_price: price,
        ...(route.pickup_mode === "none" ? {} : { pickupdrop: intent.pickup_drop ? "yes" : "no" }),
        ...(deliveryRef ? { delivery_partner_id: toInt(deliveryRef) } : {}),
        ...(washerRef ? { washer_id: toInt(washerRef) } : {}),
        ...rzpIds,
        payment_status: online ? "paid" : "cod",
        ...pickupDropAddress,
        ...customerCols,
        assigned_to_admin_id: adminRef,
      };
      break;
    }
    case "pollution_booking": {
      row = {
        user_id: intent.user_id,
        ...vehicle,
        price,
        ...rzpIdsOrCod,
        ...pickupDropAddress,
        delivery_partner_id: toInt(deliveryRef),
        pickupdrop: "yes",
        status: "booked",
        ...customerCols,
      };
      break;
    }
    case "inspection_booking": {
      const insp = (intent.options["inspection"] ?? {}) as Record<string, string>;
      row = {
        user_id: intent.user_id,
        ...vehicle,
        ...rzpIdsOrCod,
        ...pickupDropAddress,
        delivery_partner_id: toInt(deliveryRef),
        pickupdrop: "yes",
        status: "booked",
        vehicle_condition: insp.condition ?? null,
        vehicle_type: (route.details?.["vehicle_type_label"] as string) ?? null,
        package_price: price,
        slot_date: insp.slot_date ?? null,
        slot_time: insp.slot_time ?? null,
        ...customerCols,
      };
      break;
    }
    case "claim_table": {
      const c = (intent.options["claim"] ?? {}) as Record<string, string>;
      row = {
        user_id: intent.user_id,
        ...vehicle,
        assigned_to_admin_id: adminRef,
        claim_status: "submitted",
        damage_description: c.description,
        rc_copy_url: c.rc,
        driving_license_url: c.license,
        owner_aadhaar_url: c.aadhaar,
        owner_pan_url: c.pan,
        insurance_copy_url: c.insurance,
        damage_photo_url: c.photo,
        has_unread_update: true,
        created_at: new Date().toISOString(),
        delivery_partner_id: toInt(deliveryRef),
        pickupdrop: "yes",
        ...pickupDropAddress,
        package_price: price,
        payment_status: online ? "paid" : "cod",
        ...rzpIds,
        ...customerCols,
      };
      break;
    }
    case "monthlywash_table": {
      const days = Number(route.details?.["duration_days"] ?? 30);
      const start = new Date();
      const end = new Date(start.getTime() + days * 24 * 3600 * 1000);
      row = {
        user_id: intent.user_id,
        ...vehicle,
        plan_type: (route.details?.["plan_type"] as string) ?? null,
        plan_title: bookingName,
        price: intent.subtotal,
        status: "active",
        start_date: start.toISOString(),
        end_date: end.toISOString(),
        payment_id: online ? paymentId : "COD",
        order_id: online ? intent.razorpay_order_id : "COD",
        pickup_address: addr.address ?? null,
        pickup_latitude: addr.latitude ?? null,
        pickup_longitude: addr.longitude ?? null,
        pickup_address_name: addr.name ?? null,
        ...(washerRef ? { washer_id: toInt(washerRef) } : {}),
      };
      break;
    }
    default:
      throw new Error(`Unknown booking table: ${table}`);
  }

  const { data, error } = await db.from(table).insert(row).select("id").single();
  if (error) throw error;
  return String(data.id);
}

// Bills (tax invoices) for every booking type — collected from what the
// customer was actually charged, then drawn as a PDF (invoice_pdf.ts),
// stored in the private `invoices` bucket and recorded in `invoices`.
//
// Used by:
//   invoice-api  — automatic bill when a job is marked done (DB trigger)
//   crm-api      — staff download / override ("issue new bill")
//
// Prices in the database already include GST; nothing here changes them.

import {
  computeTotals,
  formatIstDate,
  GST_PICKUP,
  GST_SERVICE,
  type InvoiceDoc,
  type InvoiceLine,
  invoiceNumber,
  renderInvoicePdf,
} from "./invoice_pdf.ts";

// deno-lint-ignore no-explicit-any
type Db = any;
// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

export const INVOICE_TABLES = [
  "bookings",
  "offer_bookings",
  "pollution_booking",
  "inspection_booking",
  "claim_table",
  "monthlywash_table",
  "fleet_pickup_requests",
] as const;
export type InvoiceTable = typeof INVOICE_TABLES[number];

export function isInvoiceTable(t: string): t is InvoiceTable {
  return (INVOICE_TABLES as readonly string[]).includes(t);
}

const ONESIGNAL_APP_ID = "6bc39a67-c05a-4ba4-b950-9ccfc8e9b9b6";

/** "₹1,099" / "1099" / 1099 → 1099 (rupees). */
function money(v: unknown): number {
  if (typeof v === "number") return isFinite(v) ? v : 0;
  const n = Number(String(v ?? "").replace(/[^0-9.\-]/g, ""));
  return isFinite(n) ? n : 0;
}

function titleCase(s: string): string {
  const t = String(s ?? "").trim();
  if (!t || t !== t.toUpperCase()) return t;
  return t.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase());
}

interface Collected {
  lines: InvoiceLine[];
  paidOnline: number;
  userId: string | null;
  vehicleId: string | null;
  customerName: string;
  customerPhone: string | null;
  vehicle: string;
  regNo: string;
  garage: string | null;
  title: string;
  statusText: string;
  serviceName: string;
}

/** The checkout that created this booking (items, pickup fee, coupon). */
async function intentFor(db: Db, table: string, id: string): Promise<Row | null> {
  const { data } = await db.from("payment_intents").select("*")
    .eq("booking_table", table).eq("booking_id", id).eq("status", "booked")
    .order("created_at", { ascending: false }).limit(1);
  return (data ?? [])[0] ?? null;
}

/** Booked items + pickup & drop + coupon, from the checkout. */
function linesFromIntent(intent: Row): InvoiceLine[] {
  const lines: InvoiceLine[] = [];
  const items = Array.isArray(intent.items) ? intent.items : [];
  items.forEach((i: Row, n: number) => {
    lines.push({
      name: titleCase(String(i.name ?? "Service")),
      amount: money(i.price),
      gst: GST_SERVICE,
      note: n === 0 ? "Booked package" : "Booked add-on",
    });
  });
  const fee = money(intent.pickup_fee);
  if (fee > 0) lines.push({ name: "Pickup & Drop", amount: fee, gst: GST_PICKUP, note: "Doorstep pickup and drop" });
  const c = (intent.options ?? {})["coupon"] as Row | undefined;
  const off = money(c?.discount);
  if (c?.code && off > 0) {
    lines.push({ name: `Coupon ${String(c.code).toUpperCase()}`, amount: -off, gst: GST_SERVICE });
  }
  return lines;
}

async function collect(db: Db, table: InvoiceTable, id: string): Promise<Collected> {
  const { data: row, error } = await db.from(table).select("*").eq("id", id).maybeSingle();
  if (error) throw error;
  if (!row) throw new Error("Booking not found");

  const userId = row.user_id ? String(row.user_id) : null;
  const vehicleId = row.vehicle_id ? String(row.vehicle_id) : null;
  let lines: InvoiceLine[] = [];
  let paidOnline = 0;
  let garage: string | null = null;
  let title = "Your service bill";
  let serviceName = "";

  const intent = table === "fleet_pickup_requests" ? null : await intentFor(db, table, id);
  const intentOnline = intent && intent.payment_method === "online" ? money(intent.amount) : 0;

  switch (table) {
    case "bookings": {
      if (row.assigned_to_admin_id) {
        const { data: a } = await db.from("admin").select("username").eq("id", row.assigned_to_admin_id).maybeSingle();
        garage = a?.username ?? null;
      }
      if (intent) {
        lines = linesFromIntent(intent);
        paidOnline = intentOnline;
      } else {
        // ReperiResolve repair booking (made from an accepted CRM price).
        const { data: rr } = await db.from("resolve_requests").select("quoted_price,pickup_fee,categories")
          .eq("booking_id", String(id)).limit(1);
        const r = (rr ?? [])[0];
        if (r && r.quoted_price != null) {
          const cats = Array.isArray(r.categories) ? r.categories.join(", ") : "";
          lines.push({ name: `Repair${cats ? ` — ${cats}` : ""}`, amount: money(r.quoted_price), gst: GST_SERVICE, note: "ReperiResolve price" });
          const fee = money(r.pickup_fee);
          if (fee > 0) lines.push({ name: "Pickup & Drop", amount: fee, gst: GST_PICKUP, note: "Doorstep pickup and drop" });
        } else {
          lines.push({ name: titleCase(row.package_name ?? "Service"), amount: money(row.package_price), gst: GST_SERVICE, note: "Booked package" });
        }
        if (String(row.payment_status ?? "").toLowerCase() === "paid") paidOnline = money(row.package_price);
      }
      // Everything the garage added: paid add-ons, and ₹0 ones as FREE.
      const { data: addons } = await db.from("addon_services")
        .select("package_name,price,status,razorpay_payment_id,created_at")
        .eq("booking_id", id).in("status", ["Paid", "Free"]).order("created_at");
      for (const a of addons ?? []) {
        const amt = money(a.price);
        lines.push({
          name: titleCase(a.package_name ?? "Add-on"),
          amount: amt,
          gst: GST_SERVICE,
          note: "Added by garage",
          free: amt === 0,
        });
        if (amt > 0 && a.razorpay_payment_id) paidOnline += amt;
      }
      const name = String(row.package_name ?? "");
      if (row.inspection_stage) title = "Your inspection bill";
      else if (row.washer_id || /wash/i.test(name)) title = "Your wash bill";
      serviceName = titleCase(name || "your service");
      break;
    }
    case "offer_bookings": {
      lines = intent
        ? linesFromIntent(intent)
        : [{ name: titleCase(row.package_name ?? "Offer wash"), amount: money(row.package_price), gst: GST_SERVICE }];
      paidOnline = intent ? intentOnline : (String(row.payment_status ?? "").toLowerCase() === "paid" ? money(row.package_price) : 0);
      title = "Your wash bill";
      serviceName = titleCase(row.package_name ?? "your wash");
      break;
    }
    case "pollution_booking": {
      lines = intent
        ? linesFromIntent(intent)
        : [{ name: "Pollution Check (PUC)", amount: money(row.price), gst: GST_SERVICE }];
      paidOnline = intent ? intentOnline : (row.razorpay_payment_id && row.razorpay_payment_id !== "COD" ? money(row.price) : 0);
      title = "Your PUC bill";
      serviceName = "Pollution Check";
      break;
    }
    case "inspection_booking": {
      const label = `Vehicle Health Check${row.vehicle_type ? ` (${row.vehicle_type})` : ""}`;
      lines = intent ? linesFromIntent(intent) : [{ name: label, amount: money(row.package_price), gst: GST_SERVICE }];
      paidOnline = intent ? intentOnline : (row.razorpay_payment_id && row.razorpay_payment_id !== "COD" ? money(row.package_price) : 0);
      title = "Your inspection bill";
      serviceName = label;
      break;
    }
    case "claim_table": {
      if (row.assigned_to_admin_id) {
        const { data: a } = await db.from("admin").select("username").eq("id", row.assigned_to_admin_id).maybeSingle();
        garage = a?.username ?? null;
      }
      lines = intent ? linesFromIntent(intent) : [{ name: "Claim Assistance", amount: money(row.package_price), gst: GST_SERVICE }];
      paidOnline = intent ? intentOnline : (String(row.payment_status ?? "").toLowerCase() === "paid" ? money(row.package_price) : 0);
      title = "Your claim bill";
      serviceName = "Claim Assistance";
      break;
    }
    case "monthlywash_table": {
      const name = titleCase(row.plan_title ?? "Monthly Wash Plan");
      const from = row.start_date ? formatIstDate(row.start_date) : "";
      const to = row.end_date ? formatIstDate(row.end_date) : "";
      lines = intent
        ? linesFromIntent(intent)
        : [{ name, amount: money(row.price), gst: GST_SERVICE }];
      if (lines[0] && from && to) lines[0].note = `${from} – ${to}`;
      paidOnline = intent ? intentOnline : (row.payment_id && row.payment_id !== "COD" ? money(row.price) : 0);
      title = "Your wash plan bill";
      serviceName = name;
      break;
    }
    case "fleet_pickup_requests": {
      const items = Array.isArray(row.bill_items) ? row.bill_items : [];
      lines = items.map((i: Row) => ({ name: titleCase(String(i.name ?? "Service")), amount: money(i.price), gst: GST_SERVICE }));
      if (!lines.length) lines = [{ name: "Fleet service", amount: money(row.total_amount), gst: GST_SERVICE }];
      paidOnline = String(row.payment_status ?? "").toLowerCase() === "paid" ? money(row.total_amount) : 0;
      title = "Your fleet service bill";
      serviceName = "your fleet service";
      break;
    }
  }

  // Customer + vehicle
  let customerName = String(row.customer_name ?? row.company_name ?? "").trim();
  let customerPhone: string | null = row.customer_phone ? String(row.customer_phone) : null;
  if (userId && (!customerName || !customerPhone)) {
    const { data: p } = await db.from("profiles").select("name,phone").eq("id", userId).maybeSingle();
    customerName = customerName || String(p?.name ?? "");
    customerPhone = customerPhone || (p?.phone ? String(p.phone) : null);
  }
  let vehicle = "", regNo = "";
  if (vehicleId) {
    const { data: v } = await db.from("vehicles").select("car_brand,car_model,car_number").eq("id", vehicleId).maybeSingle();
    if (v) {
      vehicle = [v.car_brand, v.car_model].filter(Boolean).join(" ");
      regNo = String(v.car_number ?? "").toUpperCase();
    }
  }

  return {
    lines,
    paidOnline,
    userId,
    vehicleId,
    customerName: customerName || "Customer",
    customerPhone,
    vehicle,
    regNo,
    garage,
    title,
    statusText: "Service completed",
    serviceName,
  };
}

/** Lines the CRM sends for an override, cleaned up. */
export function cleanLines(raw: unknown): InvoiceLine[] {
  const list = Array.isArray(raw) ? raw : [];
  const lines: InvoiceLine[] = [];
  for (const r of list.slice(0, 40)) {
    const name = String((r as Row)?.name ?? "").trim().slice(0, 120);
    if (!name) continue;
    const free = !!(r as Row)?.free;
    const amount = free ? 0 : Math.round(money((r as Row)?.amount) * 100) / 100;
    if (Math.abs(amount) > 10_000_000) throw new Error(`Price too large for "${name}"`);
    const gst = Number((r as Row)?.gst) === GST_PICKUP ? GST_PICKUP : GST_SERVICE;
    const note = String((r as Row)?.note ?? "").trim().slice(0, 80) || undefined;
    lines.push({ name, amount, gst, free: free || amount === 0, note });
  }
  if (!lines.length) throw new Error("Add at least one item.");
  return lines;
}

export interface IssueOptions {
  table: InvoiceTable;
  id: string;
  /** Override from the CRM; otherwise collected automatically. */
  lines?: InvoiceLine[];
  reason?: string | null;
  createdBy: string; // 'auto' or the staff email
  /** Automatic runs do nothing if a bill already exists. */
  onlyIfMissing?: boolean;
  notify?: boolean;
}

export async function issueInvoice(db: Db, o: IssueOptions): Promise<Row> {
  const { data: current } = await db.from("invoices").select("*")
    .eq("booking_table", o.table).eq("booking_id", String(o.id)).eq("status", "issued").limit(1);
  const existing = (current ?? [])[0] as Row | undefined;
  if (existing && o.onlyIfMissing) return existing;

  const c = await collect(db, o.table, String(o.id));
  const lines = o.lines ?? c.lines;
  const totals = computeTotals(lines);
  const now = new Date();

  // Unique number: same minute + same vehicle (e.g. a quick override) gets -2, -3…
  const suffixId = c.vehicleId ?? `${o.table === "fleet_pickup_requests" ? "F" : "B"}${o.id}`;
  const base = invoiceNumber(now, suffixId);
  let invoiceNo = base;
  for (let n = 2; n < 50; n++) {
    const { data: clash } = await db.from("invoices").select("id").eq("invoice_no", invoiceNo).limit(1);
    if (!clash?.length) break;
    invoiceNo = `${base}-${n}`;
  }

  const doc: InvoiceDoc = {
    invoiceNo,
    issuedAt: now.toISOString(),
    title: c.title,
    statusText: c.statusText,
    customerName: c.customerName,
    customerPhone: c.customerPhone,
    vehicle: c.vehicle,
    regNo: c.regNo,
    bookingRef: `#${o.id}`,
    serviceDate: formatIstDate(now.toISOString()),
    garage: c.garage,
    lines,
    paidOnline: c.paidOnline,
    replacesNo: existing?.invoice_no ?? null,
  };
  const pdf = await renderInvoicePdf(doc);
  const folder = c.userId ?? (o.table === "fleet_pickup_requests" ? "fleet" : "no-user");
  const path = `${folder}/${invoiceNo.replace(/[^A-Za-z0-9-]/g, "")}.pdf`;
  const { error: upErr } = await db.storage.from("invoices")
    .upload(path, pdf, { contentType: "application/pdf", upsert: true });
  if (upErr) throw upErr;

  // Replace the current bill (kept for the record), then add the new one.
  if (existing) {
    const { error } = await db.from("invoices").update({ status: "replaced", replaced_at: now.toISOString() })
      .eq("id", existing.id);
    if (error) throw error;
  }
  const { data: inserted, error: insErr } = await db.from("invoices").insert({
    invoice_no: invoiceNo,
    booking_table: o.table,
    booking_id: String(o.id),
    user_id: c.userId,
    vehicle_id: c.vehicleId,
    status: "issued",
    lines,
    total: totals.total,
    taxable: totals.taxable,
    paid_online: Math.min(c.paidOnline, totals.total),
    pdf_path: path,
    created_by: o.createdBy,
    reason: o.reason ?? null,
    replaces_invoice_no: existing?.invoice_no ?? null,
  }).select("*").single();
  if (insErr) {
    // Put the old one back so the customer always has a bill.
    if (existing) await db.from("invoices").update({ status: "issued", replaced_at: null }).eq("id", existing.id);
    throw insErr;
  }

  if (o.notify !== false && c.userId) {
    const auto = o.createdBy === "auto";
    const title = auto
      ? (o.table === "bookings" && c.garage ? "Service done ✅ — your bill is ready" : "Done ✅ — your bill is ready")
      : "Your updated bill is ready";
    const body = auto
      ? `${c.garage && o.table === "bookings" ? `${c.garage} finished ${c.serviceName}` : `${c.serviceName} is done`}. Tap to download your bill.`
      : `We've updated the bill for ${c.serviceName}. Tap to download it.`;
    await sendPush(`customer_${c.userId}`, title, body, {
      type: "invoice",
      invoiceId: inserted.id,
      bookingTable: o.table,
      bookingId: String(o.id),
    }).catch((e) => console.error("invoice push failed", e));
  }
  return inserted;
}

async function sendPush(externalId: string, title: string, body: string, data: Row) {
  const key = Deno.env.get("ONESIGNAL_REST_API_KEY") ?? "";
  if (!key) return;
  await fetch("https://api.onesignal.com/notifications", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Key ${key}` },
    body: JSON.stringify({
      app_id: ONESIGNAL_APP_ID,
      include_aliases: { external_id: [externalId] },
      target_channel: "push",
      headings: { en: title },
      contents: { en: body },
      data,
    }),
  });
}

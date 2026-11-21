// obd-report — "OBD REPORT" on inspection visits in the delivery dashboard.
//
// The expert photographs the OBD scanner's screens, types what the customer
// says is wrong, and taps MAKE REPORT. Claude reads the photos and writes a
// "Reperi Scan — Vehicle OBD-II Health Report"; this function draws it as a
// PDF (same layout as the Tata Harrier sample) for the expert to download or
// send to the customer on WhatsApp.
//
// Called from web/deliverydashboard.html with the expert's own login
// (Authorization: Bearer <access token>). Every action checks that the
// booking is an inspection visit assigned to this expert.
//
//   POST { action: "statuses" }                       report status of this expert's visits
//   POST { action: "get", table, id }                 photos, complaint, report summary
//   POST { action: "photo_add", table, id, image }    image = base64 JPEG/PNG (data URL ok)
//   POST { action: "photo_remove", table, id, path }
//   POST { action: "generate", table, id, complaint } starts the report (≈1 min, poll "get")
//   POST { action: "download", table, id }            10-minute PDF link (saves to the phone)
//   POST { action: "share", table, id }               30-day link + WhatsApp text + number
//
// Secrets: ANTHROPIC_API_KEY (already set for ask-ai-chat / fleet-inspection).
// Optional: OBD_REPORT_MODEL (default claude-sonnet-5-5).
// Tables: supabase/migrations/20261122000000_obd_reports.sql

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { analyse } from "./analyse.ts";
import { renderReportPdf } from "./pdf.ts";

const BUCKET = "obd-reports";
const TABLES = new Set(["bookings", "inspection_booking"]);
const MAX_PHOTOS = 16;
const MAX_PHOTO_BYTES = 6 * 1024 * 1024;
const SHARE_SECONDS = 30 * 24 * 3600; // WhatsApp link works for 30 days
const STUCK_MS = 6 * 60 * 1000; // a "processing" older than this can be restarted

const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) { super(message); }
}

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;
type Partner = { id: number; email: string; label: string };

function db(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

/** The signed-in delivery partner (same lookup the dashboard does: by email). */
async function requirePartner(req: Request, client: SupabaseClient): Promise<Partner> {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new HttpError(401, "sign_in_required", "Please sign in again.");
  const { data, error } = await client.auth.getUser(token);
  const email = data?.user?.email;
  if (error || !email) throw new HttpError(401, "sign_in_required", "Your session has expired. Please sign in again.");
  const { data: p } = await client.from("delivery_partners").select("*").eq("email", email).maybeSingle();
  if (!p) throw new HttpError(403, "not_partner", "No delivery partner profile found for this account.");
  const name = String(p.name ?? p.full_name ?? "").trim();
  return { id: Number(p.id), email, label: name ? `${name} (${email})` : email };
}

/** The inspection visit — only if it's assigned to this expert. */
async function requireVisit(client: SupabaseClient, partner: Partner, body: Row): Promise<{ table: string; id: string; row: Row }> {
  const table = String(body.table ?? "");
  const id = String(body.id ?? "").trim();
  if (!TABLES.has(table) || !id) throw new HttpError(400, "bad_request", "Unknown inspection.");
  const { data: row, error } = await client.from(table).select("*").eq("id", id).maybeSingle();
  if (error) throw error;
  if (!row || String(row.delivery_partner_id ?? "") !== String(partner.id)) {
    throw new HttpError(404, "not_found", "This inspection isn't assigned to you.");
  }
  if (!row.inspection_stage) throw new HttpError(400, "not_inspection", "OBD reports are only for inspection visits.");
  return { table, id, row };
}

async function reportRow(client: SupabaseClient, table: string, id: string): Promise<Row | null> {
  const { data, error } = await client.from("obd_reports").select("*")
    .eq("booking_table", table).eq("booking_id", id).maybeSingle();
  if (error) throw error;
  return data;
}

/** "Tata Harrier", "KA 03 MX 4821" and the customer — from the booking (and its vehicle). */
async function visitInfo(client: SupabaseClient, row: Row) {
  let brand = String(row.car_brand ?? row.vehicle_brand ?? "").trim();
  let model = String(row.car_model ?? row.vehicle_model ?? "").trim();
  let plate = String(row.car_number ?? row.vehicle_number ?? row.registration_number ?? "").trim();
  if (row.vehicle_id && (!brand || !plate)) {
    const { data: v } = await client.from("vehicles").select("car_brand,car_model,car_number").eq("id", row.vehicle_id).maybeSingle();
    if (v) {
      brand ||= String(v.car_brand ?? "").trim();
      model ||= String(v.car_model ?? "").trim();
      plate ||= String(v.car_number ?? "").trim();
    }
  }
  let name = String(row.customer_name ?? "").trim();
  let phone = String(row.customer_phone ?? "").trim();
  if ((!name || name === "Unknown" || !phone) && row.user_id) {
    const { data: p } = await client.from("profiles").select("*").eq("id", row.user_id).maybeSingle();
    if (p) {
      if (!name || name === "Unknown") name = String(p.name ?? p.full_name ?? "").trim();
      phone ||= String(p.phone ?? "").trim();
    }
  }
  const vehicle = [brand, model].filter(Boolean).join(" ") ||
    (row.vehicle_type ? `${row.vehicle_type}` : "") || String(row.package_name ?? "Vehicle");
  return { vehicle, plate: plate.toUpperCase(), name: name && name !== "Unknown" ? name : "", phone };
}

/** 98450 12345 / +91… / 0… → "919845012345" for wa.me, or null. */
function waNumber(raw: string): string | null {
  let d = String(raw ?? "").replace(/\D/g, "");
  if (d.length === 11 && d.startsWith("0")) d = d.slice(1);
  if (d.length === 10) d = "91" + d;
  return /^\d{11,15}$/.test(d) ? d : null;
}

function istDates(d = new Date()) {
  const ist = new Date(d.getTime() + 330 * 60 * 1000);
  const long = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
  const day = ist.getUTCDate(), mo = ist.getUTCMonth(), yr = ist.getUTCFullYear();
  const ymd = `${String(yr).slice(2)}${String(mo + 1).padStart(2, "0")}${String(day).padStart(2, "0")}`;
  return { long: `${day} ${long[mo]} ${yr}`, short: `${day} ${long[mo].slice(0, 3)} ${yr}`, ymd };
}

function mediaTypeOf(b: Uint8Array): string | null {
  if (b[0] === 0xff && b[1] === 0xd8) return "image/jpeg";
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
  if (b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 && b[8] === 0x57 && b[9] === 0x45) return "image/webp";
  return null;
}

function toBase64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

/** What the sheet in the dashboard shows. */
async function view(client: SupabaseClient, table: string, id: string, row: Row) {
  const rep = await reportRow(client, table, id);
  const info = await visitInfo(client, row);
  const paths: string[] = rep?.photo_paths ?? [];
  let photos: Array<{ path: string; url: string | null }> = [];
  if (paths.length) {
    const { data } = await client.storage.from(BUCKET).createSignedUrls(paths, 900);
    photos = paths.map((p) => ({ path: p, url: data?.find((d) => d.path === p)?.signedUrl ?? null }));
  }
  let status = rep?.status ?? "draft";
  // A run that died (e.g. the function was stopped) shows as failed so it can be retried.
  if (status === "processing" && rep && Date.now() - Date.parse(rep.updated_at) > STUCK_MS) status = "failed";
  const s = (rep?.summary ?? null) as Row | null;
  return {
    status,
    error: status === "failed" ? (rep?.error ?? "That took too long. Please try again.") : null,
    complaint: rep?.customer_complaint ?? "",
    photos,
    report: status === "ready" && s
      ? {
        report_no: rep?.report_no, overall_score: s.overall_score, verdict_headline: s.verdict_headline, verdict: s.verdict,
        components: s.components ?? [], findings: (s.findings ?? []).length, fault_codes: s.fault_codes ?? [],
        generated_at: rep?.generated_at, whatsapp_opened_at: rep?.whatsapp_opened_at,
      }
      : null,
    customer: { name: info.name, phone: info.phone, wa: waNumber(info.phone) },
    vehicle: info.plate ? `${info.vehicle} · ${info.plate}` : info.vehicle,
    max_photos: MAX_PHOTOS,
  };
}

/** Creates the draft row the first time it's needed. */
async function ensureRow(client: SupabaseClient, table: string, id: string, partner: Partner): Promise<Row> {
  const existing = await reportRow(client, table, id);
  if (existing) return existing;
  const { data, error } = await client.from("obd_reports").upsert(
    { booking_table: table, booking_id: id, partner_id: partner.id, partner_email: partner.email },
    { onConflict: "booking_table,booking_id" },
  ).select("*").single();
  if (error) throw error;
  return data;
}

/** Photos or complaint changed after a report → it has to be made again. */
const backToDraft = (rep: Row) => (rep.status === "ready" || rep.status === "failed" ? { status: "draft", error: null } : {});

async function generate(client: SupabaseClient, repId: string, table: string, id: string, row: Row, partner: Partner) {
  const { data: rep } = await client.from("obd_reports").select("*").eq("id", repId).single();
  const paths: string[] = rep?.photo_paths ?? [];
  const photos: Array<{ bytes: Uint8Array; mediaType: string }> = [];
  for (const p of paths) {
    const { data: blob, error } = await client.storage.from(BUCKET).download(p);
    if (error || !blob) { console.error("photo download failed", p, error); continue; }
    const bytes = new Uint8Array(await blob.arrayBuffer());
    const mt = mediaTypeOf(bytes);
    if (mt) photos.push({ bytes, mediaType: mt });
  }
  if (!photos.length) throw new Error("The photos couldn't be read. Add them again.");

  const info = await visitInfo(client, row);
  const report = await analyse({
    apiKey: Deno.env.get("ANTHROPIC_API_KEY") ?? "",
    model: Deno.env.get("OBD_REPORT_MODEL") || "claude-sonnet-5-5",
    photos: photos.map((p) => ({ base64: toBase64(p.bytes), mediaType: p.mediaType })),
    complaint: String(rep?.customer_complaint ?? ""),
    vehicleHint: [info.vehicle, info.plate].filter(Boolean).join(" · "),
  });
  if (report.not_obd) {
    throw new Error(`These photos don't look like OBD scanner screens${report.not_obd_reason ? `: ${report.not_obd_reason}` : "."} Take a clear photo of each scanner screen and try again.`);
  }

  const dates = istDates();
  const tail = info.plate.replace(/[^A-Z0-9]/g, "").slice(-4) || id.replace(/[^A-Za-z0-9]/g, "").slice(-4);
  const reportNo = `OBD-${dates.ymd}-${tail}`;
  const vehicleTitle = report.vehicle_name
    ? report.vehicle_name.replace(/, (.+)$/, " ($1)")
    : info.vehicle;
  const pdf = await renderReportPdf({
    report, reportNo, scanDate: dates.long, shortDate: dates.short, vehicleTitle,
    registration: info.plate, customerName: info.name, complaint: String(rep?.customer_complaint ?? ""),
    expert: partner.label, photos,
  });

  const pdfPath = `${table}/${id}/report-${Date.now()}.pdf`;
  const { error: upErr } = await client.storage.from(BUCKET).upload(pdfPath, pdf, { contentType: "application/pdf", upsert: true });
  if (upErr) throw upErr;
  if (rep?.pdf_path) await client.storage.from(BUCKET).remove([String(rep.pdf_path)]);

  const { error } = await client.from("obd_reports").update({
    status: "ready", report_no: reportNo, pdf_path: pdfPath, error: null, generated_at: new Date().toISOString(),
    summary: { ...report, vehicle_title: vehicleTitle },
  }).eq("id", repId);
  if (error) throw error;
}

function pdfFileName(rep: Row): string {
  const v = String((rep.summary as Row | null)?.vehicle_title ?? "Vehicle").replace(/\(.*\)/, "").trim();
  return `Reperi-Scan-${v}-${rep.report_no ?? "report"}`.replace(/[^A-Za-z0-9-]+/g, "-").replace(/-+/g, "-") + ".pdf";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  try {
    const client = db();
    const partner = await requirePartner(req, client);
    const body = (await req.json().catch(() => ({}))) as Row;

    if (body.action === "statuses") {
      const { data, error } = await client.from("obd_reports")
        .select("booking_table,booking_id,status,generated_at,whatsapp_opened_at,updated_at")
        .eq("partner_id", partner.id).order("updated_at", { ascending: false }).limit(300);
      if (error) throw error;
      const out: Row = {};
      for (const r of data ?? []) out[`${r.booking_table}::${r.booking_id}`] = {
        status: r.status === "processing" && Date.now() - Date.parse(r.updated_at) > STUCK_MS ? "failed" : r.status,
        generated_at: r.generated_at, whatsapp_opened_at: r.whatsapp_opened_at,
      };
      return json({ reports: out });
    }

    const { table, id, row } = await requireVisit(client, partner, body);

    switch (body.action) {
      case "get":
        return json(await view(client, table, id, row));

      case "photo_add": {
        const rep = await ensureRow(client, table, id, partner);
        if (rep.status === "processing" && Date.now() - Date.parse(rep.updated_at) < STUCK_MS) {
          throw new HttpError(409, "busy", "The report is being made. Wait a moment.");
        }
        const paths: string[] = rep.photo_paths ?? [];
        if (paths.length >= MAX_PHOTOS) throw new HttpError(400, "too_many", `You can add up to ${MAX_PHOTOS} photos.`);
        const b64 = String(body.image ?? "").replace(/^data:[^,]+,/, "");
        let bytes: Uint8Array;
        try { bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)); } catch { throw new HttpError(400, "bad_image", "That photo couldn't be read."); }
        const mt = mediaTypeOf(bytes);
        if (!mt || mt === "image/webp") throw new HttpError(400, "bad_image", "Send the photo as JPG or PNG.");
        if (bytes.length > MAX_PHOTO_BYTES) throw new HttpError(400, "too_big", "That photo is too large.");
        const path = `${table}/${id}/photos/${Date.now()}-${crypto.randomUUID().slice(0, 8)}.${mt === "image/png" ? "png" : "jpg"}`;
        const { error: upErr } = await client.storage.from(BUCKET).upload(path, bytes, { contentType: mt });
        if (upErr) throw upErr;
        const { error } = await client.from("obd_reports")
          .update({ photo_paths: [...paths, path], partner_id: partner.id, partner_email: partner.email, ...backToDraft(rep) })
          .eq("id", rep.id);
        if (error) throw error;
        return json(await view(client, table, id, row));
      }

      case "photo_remove": {
        const rep = await reportRow(client, table, id);
        const path = String(body.path ?? "");
        if (!rep || !(rep.photo_paths ?? []).includes(path)) return json(await view(client, table, id, row));
        const { error } = await client.from("obd_reports")
          .update({ photo_paths: (rep.photo_paths as string[]).filter((p) => p !== path), ...backToDraft(rep) })
          .eq("id", rep.id);
        if (error) throw error;
        await client.storage.from(BUCKET).remove([path]);
        return json(await view(client, table, id, row));
      }

      case "generate": {
        const rep = await ensureRow(client, table, id, partner);
        if (!(rep.photo_paths ?? []).length) throw new HttpError(400, "no_photos", "Add at least 1 photo of the scanner screen.");
        if (rep.status === "processing" && Date.now() - Date.parse(rep.updated_at) < STUCK_MS) {
          return json(await view(client, table, id, row), 202); // already running
        }
        const complaint = String(body.complaint ?? "").trim().slice(0, 1500);
        const { error } = await client.from("obd_reports").update({
          status: "processing", error: null, customer_complaint: complaint, partner_id: partner.id, partner_email: partner.email,
        }).eq("id", rep.id);
        if (error) throw error;

        // Answer now; the slow part (Claude + PDF, ~1 minute) runs in the background.
        const work = generate(client, rep.id, table, id, row, partner).catch(async (e) => {
          console.error("obd report failed:", e);
          const msg = String(e instanceof Error ? e.message : e);
          await client.from("obd_reports").update({
            status: "failed",
            error: msg.startsWith("These photos") || msg.startsWith("The photos")
              ? msg.slice(0, 400)
              : `Couldn't make the report (${msg.slice(0, 200)}). Please try again.`,
          }).eq("id", rep.id);
        });
        // deno-lint-ignore no-explicit-any
        const rt = (globalThis as any).EdgeRuntime;
        if (rt?.waitUntil) rt.waitUntil(work);
        else await work;
        return json(await view(client, table, id, row), 202);
      }

      case "download":
      case "share": {
        const rep = await reportRow(client, table, id);
        if (!rep || rep.status !== "ready" || !rep.pdf_path) throw new HttpError(409, "not_ready", "Make the report first.");
        const share = body.action === "share";
        const { data, error } = await client.storage.from(BUCKET)
          .createSignedUrl(String(rep.pdf_path), share ? SHARE_SECONDS : 600, { download: pdfFileName(rep) });
        if (error || !data?.signedUrl) throw error ?? new Error("Couldn't make the link.");
        if (!share) return json({ url: data.signedUrl, file_name: pdfFileName(rep) });

        const info = await visitInfo(client, row);
        const wa = waNumber(info.phone);
        if (!wa) throw new HttpError(400, "no_phone", "This booking has no customer phone number.");
        const s = rep.summary as Row;
        const first = info.name.split(/\s+/)[0];
        const text = [
          `Hi${first ? ` ${first}` : ""}, here is the Reperi Scan report for your ${String(s?.vehicle_title ?? info.vehicle).replace(/\s*\(.*\)/, "")}${info.plate ? ` (${info.plate})` : ""}.`,
          "",
          `Overall score: ${Number(s?.overall_score ?? 0).toFixed(1)}/10 - ${s?.verdict_headline ?? ""}`.trim(),
          "",
          `Download the full report (PDF): ${data.signedUrl}`,
          "(This link works for 30 days.)",
          "",
          "- Team Reperi",
        ].join("\n");
        await client.from("obd_reports").update({ whatsapp_opened_at: new Date().toISOString() }).eq("id", rep.id);
        return json({ wa, text, url: data.signedUrl });
      }

      default:
        throw new HttpError(400, "bad_request", "Unknown action.");
    }
  } catch (err) {
    if (err instanceof HttpError) return json({ error: err.code, message: err.message }, err.status);
    console.error("obd-report error:", err);
    const msg = err && typeof err === "object" && "message" in err ? String((err as { message: unknown }).message) : String(err);
    return json({ error: "unexpected", message: `Something went wrong: ${msg}`.slice(0, 300) }, 500);
  }
});

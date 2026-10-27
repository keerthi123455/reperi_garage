// fleet-inspection — the 21-point inspection report for fleet pickups.
//
// POST { action: "generate", id }      header x-inspection-secret = app_settings.cron_secret
//   Called by the database when the delivery partner uploads the 21st photo
//   (supabase/fleet_inspection.sql). Answers straight away, then in the
//   background: Claude (Haiku) checks every photo for scratches / dents /
//   cracks → PDF → private `fleet-inspections` bucket → the request row.
// POST { action: "download", id, fleet_user_id }
//   The fleet app's "Download report (PDF)". Only once the bill is paid.
//   Returns a 10-minute link.
//
// Needs the ANTHROPIC_API_KEY secret (the same one ask-ai-chat uses).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, corsHeaders, json } from "../_shared/booking.ts";
import { analysePhotos, mediaTypeOf, type Photo, renderInspectionPdf, SHOTS } from "../_shared/fleet_inspection.ts";

const BUCKET = "fleet-inspections";
type Db = ReturnType<typeof adminClient>;

function istStamp(iso: string | null | undefined): string {
  const d = iso ? new Date(iso) : new Date();
  const ist = new Date(d.getTime() + 330 * 60 * 1000);
  const m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const h = ist.getUTCHours();
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${ist.getUTCDate()} ${m[ist.getUTCMonth()]} ${ist.getUTCFullYear()}, ${h12}:${String(ist.getUTCMinutes()).padStart(2, "0")} ${h < 12 ? "AM" : "PM"}`;
}

function reportNo(id: string, plate: string): string {
  const d = new Date(Date.now() + 330 * 60 * 1000);
  const ymd = `${String(d.getUTCFullYear()).slice(2)}${String(d.getUTCMonth() + 1).padStart(2, "0")}${String(d.getUTCDate()).padStart(2, "0")}`;
  const tail = plate.replace(/[^A-Z0-9]/gi, "").slice(-4).toUpperCase() || String(id).slice(-4);
  return `INS-${ymd}-${tail}-${String(id).replace(/[^A-Za-z0-9]/g, "").slice(-6)}`;
}

async function generate(db: Db, id: string) {
  const { data: row, error } = await db.from("fleet_pickup_requests").select("*").eq("id", id).maybeSingle();
  if (error) throw error;
  if (!row) throw new Error("Request not found");
  const paths = (row.inspection21_photos ?? {}) as Record<string, string>;

  const photos: Photo[] = [];
  let lastAt: string | null = null;
  for (const s of SHOTS) {
    const path = paths[String(s.n)];
    if (!path) continue;
    const { data: blob, error: dErr } = await db.storage.from(BUCKET).download(path);
    if (dErr || !blob) {
      console.error(`photo ${s.n} download failed`, dErr);
      continue;
    }
    const bytes = new Uint8Array(await blob.arrayBuffer());
    photos.push({ n: s.n, bytes, mediaType: mediaTypeOf(bytes) });
    const m = path.match(/-(\d{13})\./);
    if (m) {
      const t = new Date(Number(m[1])).toISOString();
      if (!lastAt || t > lastAt) lastAt = t;
    }
  }
  if (photos.length < 21) throw new Error(`Only ${photos.length} of 21 photos could be read`);

  const result = await analysePhotos(Deno.env.get("ANTHROPIC_API_KEY") ?? "", photos);
  const plate = String(row.car_number ?? "").toUpperCase();
  const no = reportNo(String(row.id), plate);
  const pdf = await renderInspectionPdf({
    reportNo: no,
    company: String(row.company_name ?? ""),
    vehicle: String(row.vehicle_model ?? "Vehicle"),
    plate,
    takenAt: istStamp(lastAt ?? row.created_at),
    result,
    photos,
  });

  const pdfPath = `${row.id}/report-${Date.now()}.pdf`;
  const { error: upErr } = await db.storage.from(BUCKET).upload(pdfPath, pdf, { contentType: "application/pdf", upsert: true });
  if (upErr) throw upErr;

  const { error: uErr } = await db.from("fleet_pickup_requests").update({
    inspection21_status: "ready",
    inspection21_pdf_path: pdfPath,
    inspection21_summary: {
      report_no: no,
      ok: result.ok, minor: result.minor, major: result.major, unclear: result.unclear,
      overall: result.overall, summary: result.summary, items: result.items,
    },
    inspection21_error: null,
    inspection21_at: new Date().toISOString(),
  }).eq("id", row.id);
  if (uErr) throw uErr;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const db = adminClient();
  try {
    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const id = String(body.id ?? "").trim();
    if (!id) return json({ error: "bad_request", message: "Missing request." }, 400);

    if (body.action === "generate") {
      const { data: s } = await db.from("app_settings").select("value").eq("key", "cron_secret").maybeSingle();
      const secret = typeof s?.value === "string" ? s.value : "";
      if (!secret || req.headers.get("x-inspection-secret") !== secret) return json({ error: "forbidden" }, 403);

      // Answer now; do the slow part (Claude + PDF) in the background.
      const work = generate(db, id).catch(async (e) => {
        console.error("fleet inspection failed:", e);
        await db.from("fleet_pickup_requests").update({
          inspection21_status: "failed",
          inspection21_error: String(e instanceof Error ? e.message : e).slice(0, 300),
        }).eq("id", id);
      });
      // deno-lint-ignore no-explicit-any
      const rt = (globalThis as any).EdgeRuntime;
      if (rt?.waitUntil) rt.waitUntil(work);
      else await work;
      return json({ ok: true, started: true }, 202);
    }

    if (body.action === "download") {
      const { data: row, error } = await db.from("fleet_pickup_requests")
        .select("id,fleet_user_id,payment_status,inspection21_status,inspection21_pdf_path,inspection21_summary,car_number")
        .eq("id", id).maybeSingle();
      if (error) throw error;
      if (!row || String(row.fleet_user_id ?? "") !== String(body.fleet_user_id ?? "")) {
        return json({ error: "not_found", message: "Report not found." }, 404);
      }
      if (row.payment_status !== "paid") {
        return json({ error: "unpaid", message: "The report unlocks once the service bill is paid." }, 403);
      }
      if (row.inspection21_status !== "ready" || !row.inspection21_pdf_path) {
        return json({ error: "not_ready", message: "The report isn't ready yet. Please try again in a few minutes." }, 409);
      }
      const no = String((row.inspection21_summary as Record<string, unknown> | null)?.report_no ?? `inspection-${row.id}`);
      const { data, error: sErr } = await db.storage.from(BUCKET)
        .createSignedUrl(String(row.inspection21_pdf_path), 600, { download: `${no.replace(/[^A-Za-z0-9-]/g, "")}.pdf` });
      if (sErr || !data?.signedUrl) throw sErr ?? new Error("Could not sign");
      return json({ url: data.signedUrl });
    }

    return json({ error: "invalid_action" }, 400);
  } catch (e) {
    console.error("fleet-inspection error:", e);
    return json({ error: "unexpected", message: "Something went wrong. Please try again." }, 500);
  }
});

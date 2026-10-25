// invoice-api — makes the bill (PDF) automatically when a job is done.
//
// Called by the invoice_auto_issue DB trigger (supabase/invoices.sql) when:
//   bookings            garage MARK AS DONE / wash or inspection completed / delivered
//   offer_bookings      wash completed
//   pollution_booking   delivered back
//   inspection_booking  inspection completed
//   claim_table         garage marked done / delivered back
//   monthlywash_table   plan bought (each renewal is a new row → its own bill)
//   fleet_pickup_requests completed
//
// POST { action: "auto" | "refresh", table, id, quiet? }
//   header x-invoice-secret = app_settings.cron_secret
//   auto    → creates the bill if the booking doesn't have one yet, stores the
//             PDF in the private `invoices` bucket and pushes "your bill is ready".
//   refresh → remakes an automatic bill (an add-on was paid after it was made);
//             a bill changed by hand in the CRM is left alone.
//   quiet   → no push (old bookings billed by the safety net's backfill).
// Called from supabase/bills_everywhere.sql (job finished, add-on paid, and
// the 10-minute safety net).
//
// Customers download their own bills straight from storage (RLS); the CRM
// downloads / overrides through crm-api.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, json } from "../_shared/booking.ts";
import { isInvoiceTable, issueInvoice } from "../_shared/invoice.ts";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const db = adminClient();

  const { data: secretRow } = await db.from("app_settings").select("value").eq("key", "cron_secret").maybeSingle();
  const secret = typeof secretRow?.value === "string" ? secretRow.value : "";
  if (!secret || req.headers.get("x-invoice-secret") !== secret) return json({ error: "forbidden" }, 403);

  try {
    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const action = body.action;
    if (action !== "auto" && action !== "refresh") return json({ error: "invalid_action" }, 400);
    const table = String(body.table ?? "");
    const id = String(body.id ?? "");
    if (!isInvoiceTable(table) || !id) return json({ error: "bad_request" }, 400);
    const notify = body.quiet !== true;

    if (action === "refresh") {
      const { data: cur } = await db.from("invoices").select("created_by")
        .eq("booking_table", table).eq("booking_id", id).eq("status", "issued").maybeSingle();
      if (cur && cur.created_by !== "auto") return json({ ok: true, skipped: "changed_in_crm" });
      const inv = await issueInvoice(db, { table, id, createdBy: "auto", notify, updated: !!cur });
      return json({ ok: true, invoice_no: inv.invoice_no });
    }

    const inv = await issueInvoice(db, { table, id, createdBy: "auto", onlyIfMissing: true, notify });
    return json({ ok: true, invoice_no: inv.invoice_no });
  } catch (err) {
    console.error("invoice-api error:", err);
    const message = err && typeof err === "object" && "message" in err ? String((err as { message: unknown }).message) : String(err);
    return json({ error: "unexpected", message: message.slice(0, 300) }, 500);
  }
});

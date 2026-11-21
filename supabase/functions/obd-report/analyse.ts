// Reads the OBD scanner photos + the customer's complaint with Claude and
// returns the report as plain data (the PDF is drawn from this in pdf.ts).
// Claude must answer through the `write_obd_report` tool, so the shape is
// always the same.

export interface Component { name: string; score: number; basis: string }
export interface Monitor { scanner_label: string; meaning: string; status: "OK" | "INCOMPLETE" | "FAIL" | "N/A" }
export interface FaultCode { code: string; description: string; type: string; severity: "high" | "medium" | "low" }
export interface LiveRow { parameter: string; reading: string; assessment: string }
export interface Mode6Row { test: string; measured: string; limits: string; result: string }
export interface Finding { title: string; detail: string }

export interface ObdReport {
  not_obd: boolean;
  not_obd_reason: string;
  vehicle_name: string;
  fuel: string;
  vin: string;
  calibration_id: string;
  scan_tool: string;
  engine_state: string;
  overall_score: number;
  verdict_headline: string;
  verdict: string;
  components: Component[];
  monitors_note: string;
  monitors: Monitor[];
  mil: "ON" | "OFF" | "UNKNOWN";
  codes_found: number | null;
  fault_codes: FaultCode[];
  live_data_title: string;
  live_data: LiveRow[];
  mode6: Mode6Row[];
  mode6_note: string;
  findings: Finding[];
  limitations: string;
}

export interface AnalyseInput {
  apiKey: string;
  model: string;
  photos: Array<{ base64: string; mediaType: string }>;
  complaint: string;
  vehicleHint: string; // from the booking, e.g. "Tata Harrier · KA 03 MX 4821"
}

const SYSTEM = `You are the senior diagnostic technician at REPERI, a doorstep car-care company in Bengaluru, India. A Reperi expert visited a customer's car, plugged in a generic OBD-II scanner (usually a KONNWEI KW310, which reads the ENGINE ECU ONLY) and photographed its screens. You also get what the customer says is wrong with the car.

Write the "Reperi Scan — Vehicle OBD-II Health Report" by calling the write_obd_report tool. The customer and the garage both read it.

READ THE PHOTOS CAREFULLY
- Transcribe values exactly as shown (codes, monitor status, live data, Mode 6 values, VIN, calibration ID). If a digit is unclear, add "(as read)". Never invent a reading that is not visible. Leave a list empty if that screen wasn't photographed.
- The KW310 shows petrol-engine labels for readiness monitors. On a diesel, the ECU reports different systems in the same slots; give the diesel meaning (e.g. Catalyst Mon → NMHC / oxidation catalyst, Htd Catalyst → NOx / SCR aftertreatment, Sec Air System → Boost pressure, Oxygen Sens Mon → Exhaust gas sensor, Oxygen Sens Htr → Particulate filter (DPF), EGR System → EGR / VVT, Evap / A/C Refrig → not used on diesel). Work out petrol vs diesel from the vehicle, the readings (e.g. lean equivalence ratio at idle, high throttle-flap opening) and the monitors.
- Convert units Indians use: show km next to miles, °C next to °F where the scanner mislabels them.
- Assess each live-data value against normal ranges for that engine state (idle / warm / driving).

RATE THE CAR
- Component scores are whole numbers 1-10: 9-10 healthy, 6-8 not fully verified or near a limit, 5 and below needs attention.
- Always include the customer's complaint as its own component. If OBD can't see it (e.g. steering, AC, noises, suspension), rate it 5 or lower and say it needs a physical test.
- overall_score (one decimal) is your honest overall judgement, not a plain average; an open complaint or a stored code must pull it down.
- verdict_headline: 3-8 words ending with a full stop, e.g. "Healthy, with one open complaint." verdict: 2-4 plain sentences on what the scan shows and what needs follow-up.

FINDINGS
- 2-6 numbered findings, most important first. Start with the customer's complaint. Give practical next steps a mechanic can follow (what to test, what readings point to which part), not just "visit a garage". Mention when fault memory was cleared recently, low fuel, values near a limit, incomplete monitors (and the drive needed to complete them).

STYLE
- Plain English for an Indian car owner. Short sentences. No markdown, no emojis. Use "-" not fancy symbols.
- limitations: say a generic OBD-II scanner reads only the engine ECU (not power steering, AC/HVAC, ABS, airbag or body modules, nor purely mechanical faults), that values were transcribed from photos and may have small reading errors, and that scores are an informed assessment, not a certified inspection.

If the photos are clearly NOT an OBD scanner's screen (or are unreadable), set not_obd = true and explain why in not_obd_reason; fill the rest as best you can.`;

const str = { type: "string" };
const TOOL = {
  name: "write_obd_report",
  description: "Write the Reperi Scan OBD-II health report.",
  input_schema: {
    type: "object",
    properties: {
      not_obd: { type: "boolean", description: "true if the photos are not readable OBD scanner screens" },
      not_obd_reason: str,
      vehicle_name: { type: "string", description: "e.g. 'Tata Harrier, 2.0 L Kryotec diesel'" },
      fuel: { type: "string", enum: ["petrol", "diesel", "cng", "hybrid", "electric", "unknown"] },
      vin: { type: "string", description: "VIN as read, or ''" },
      calibration_id: { type: "string", description: "as read, or ''" },
      scan_tool: { type: "string", description: "e.g. 'KONNWEI KW310 generic OBD-II (engine ECU only)'" },
      engine_state: { type: "string", description: "e.g. 'Warm idle, ~861 rpm, vehicle stationary'" },
      overall_score: { type: "number", minimum: 0, maximum: 10 },
      verdict_headline: str,
      verdict: str,
      components: {
        type: "array", minItems: 3, maxItems: 14,
        items: { type: "object", required: ["name", "score", "basis"], properties: { name: str, score: { type: "integer", minimum: 1, maximum: 10 }, basis: str } },
      },
      monitors_note: { type: "string", description: "e.g. the petrol-label note for diesels, or ''" },
      monitors: {
        type: "array",
        items: {
          type: "object", required: ["scanner_label", "meaning", "status"],
          properties: { scanner_label: str, meaning: str, status: { type: "string", enum: ["OK", "INCOMPLETE", "FAIL", "N/A"] } },
        },
      },
      mil: { type: "string", enum: ["ON", "OFF", "UNKNOWN"], description: "check-engine light" },
      codes_found: { type: ["integer", "null"], description: "number of fault codes the scanner shows, null if not photographed" },
      fault_codes: {
        type: "array",
        items: {
          type: "object", required: ["code", "description", "type", "severity"],
          properties: {
            code: str, description: str,
            type: { type: "string", enum: ["stored", "pending", "permanent", "unknown"] },
            severity: { type: "string", enum: ["high", "medium", "low"] },
          },
        },
      },
      live_data_title: { type: "string", description: "e.g. 'Live data at idle'" },
      live_data: {
        type: "array",
        items: { type: "object", required: ["parameter", "reading", "assessment"], properties: { parameter: str, reading: str, assessment: str } },
      },
      mode6: {
        type: "array",
        items: { type: "object", required: ["test", "measured", "limits", "result"], properties: { test: str, measured: str, limits: str, result: str } },
      },
      mode6_note: str,
      findings: {
        type: "array", minItems: 1, maxItems: 6,
        items: { type: "object", required: ["title", "detail"], properties: { title: str, detail: str } },
      },
      limitations: str,
    },
    required: [
      "not_obd", "vehicle_name", "fuel", "scan_tool", "engine_state", "overall_score", "verdict_headline",
      "verdict", "components", "monitors", "mil", "fault_codes", "live_data", "mode6", "findings", "limitations",
    ],
  },
};

const s = (v: unknown, max = 600) => (typeof v === "string" ? v.trim().slice(0, max) : "");
const arr = (v: unknown) => (Array.isArray(v) ? v : []);

/** Makes whatever came back safe to draw (types, lengths, ranges). */
export function normalizeReport(raw: Record<string, unknown>): ObdReport {
  const score = Number(raw.overall_score);
  const status = (v: unknown): Monitor["status"] => {
    const t = String(v ?? "").toUpperCase();
    return t === "OK" || t === "INCOMPLETE" || t === "FAIL" ? t : "N/A";
  };
  const sev = (v: unknown): FaultCode["severity"] => (v === "high" || v === "low" ? v : "medium");
  const mil = String(raw.mil ?? "").toUpperCase();
  const codes = raw.codes_found === null || raw.codes_found === undefined ? null : Number(raw.codes_found);
  return {
    not_obd: raw.not_obd === true,
    not_obd_reason: s(raw.not_obd_reason, 300),
    vehicle_name: s(raw.vehicle_name, 120),
    fuel: s(raw.fuel, 20) || "unknown",
    vin: s(raw.vin, 60),
    calibration_id: s(raw.calibration_id, 60),
    scan_tool: s(raw.scan_tool, 120) || "Generic OBD-II scanner (engine ECU only)",
    engine_state: s(raw.engine_state, 160),
    overall_score: Number.isFinite(score) ? Math.round(Math.min(10, Math.max(0, score)) * 10) / 10 : 0,
    verdict_headline: s(raw.verdict_headline, 120),
    verdict: s(raw.verdict, 900),
    components: arr(raw.components).slice(0, 14).map((c: Record<string, unknown>) => ({
      name: s(c?.name, 60),
      score: Math.min(10, Math.max(1, Math.round(Number(c?.score) || 1))),
      basis: s(c?.basis, 220),
    })).filter((c) => c.name),
    monitors_note: s(raw.monitors_note, 300),
    monitors: arr(raw.monitors).slice(0, 16).map((m: Record<string, unknown>) => ({
      scanner_label: s(m?.scanner_label, 40), meaning: s(m?.meaning, 80), status: status(m?.status),
    })).filter((m) => m.scanner_label),
    mil: mil === "ON" || mil === "OFF" ? mil : "UNKNOWN",
    codes_found: codes !== null && Number.isFinite(codes) ? Math.max(0, Math.round(codes)) : null,
    fault_codes: arr(raw.fault_codes).slice(0, 20).map((f: Record<string, unknown>) => ({
      code: s(f?.code, 12).toUpperCase(), description: s(f?.description, 200), type: s(f?.type, 12) || "unknown", severity: sev(f?.severity),
    })).filter((f) => f.code),
    live_data_title: s(raw.live_data_title, 60) || "Live data",
    live_data: arr(raw.live_data).slice(0, 30).map((r: Record<string, unknown>) => ({
      parameter: s(r?.parameter, 60), reading: s(r?.reading, 60), assessment: s(r?.assessment, 140),
    })).filter((r) => r.parameter),
    mode6: arr(raw.mode6).slice(0, 25).map((r: Record<string, unknown>) => ({
      test: s(r?.test, 70), measured: s(r?.measured, 30), limits: s(r?.limits, 40), result: s(r?.result, 40),
    })).filter((r) => r.test),
    mode6_note: s(raw.mode6_note, 250),
    findings: arr(raw.findings).slice(0, 6).map((f: Record<string, unknown>) => ({
      title: s(f?.title, 120), detail: s(f?.detail, 900),
    })).filter((f) => f.title),
    limitations: s(raw.limitations, 900) ||
      "This report uses a generic OBD-II scanner, which reads only the engine control unit. Values were transcribed from photographs of the scanner screen and may contain small reading errors. Component scores are an informed assessment, not a certified inspection.",
  };
}

export async function analyse(input: AnalyseInput): Promise<ObdReport> {
  if (!input.apiKey) throw new Error("ANTHROPIC_API_KEY is not set for the obd-report function.");
  const content: Array<Record<string, unknown>> = [];
  input.photos.forEach((p, i) => {
    content.push({ type: "text", text: `Scanner photo ${i + 1}:` });
    content.push({ type: "image", source: { type: "base64", media_type: p.mediaType, data: p.base64 } });
  });
  content.push({
    type: "text",
    text: [
      `Vehicle on the booking: ${input.vehicleHint || "not given"}`,
      `What the customer says is wrong: ${input.complaint || "No specific complaint - routine check."}`,
      "Write the report with the write_obd_report tool.",
    ].join("\n"),
  });

  const body = JSON.stringify({
    model: input.model,
    max_tokens: 8000,
    system: SYSTEM,
    tools: [TOOL],
    tool_choice: { type: "tool", name: TOOL.name },
    messages: [{ role: "user", content }],
  });

  let lastErr = "";
  for (let attempt = 1; attempt <= 3; attempt++) {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "content-type": "application/json", "x-api-key": input.apiKey, "anthropic-version": "2023-06-01" },
      body,
      signal: AbortSignal.timeout(180_000),
    });
    const json = await res.json().catch(() => null) as Record<string, unknown> | null;
    if (res.ok && json) {
      const block = arr(json.content).find((b: Record<string, unknown>) => b?.type === "tool_use" && b?.name === TOOL.name);
      if (!block) throw new Error("The AI didn't return a report. Please try again.");
      return normalizeReport((block as { input: Record<string, unknown> }).input ?? {});
    }
    lastErr = `${res.status} ${JSON.stringify((json as { error?: unknown } | null)?.error ?? json ?? "").slice(0, 300)}`;
    // Busy / rate limited → wait and retry. Anything else won't fix itself.
    if (res.status !== 429 && res.status !== 529 && res.status < 500) break;
    await new Promise((r) => setTimeout(r, 4000 * attempt));
  }
  throw new Error(`AI request failed: ${lastErr}`);
}

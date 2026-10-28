// Fleet 21-point inspection: the 21 photo spots, the Claude (Haiku) check of
// each photo for scratches / dents / cracks, and the PDF report.
// Used by the fleet-inspection Edge Function. See supabase/fleet_inspection.sql.

import { PDFDocument, type PDFFont, type PDFImage, type PDFPage, rgb, type RGB } from "npm:pdf-lib@1.17.1";
import fontkit from "npm:@pdf-lib/fontkit@1.1.1";
import { MANROPE_BOLD, MANROPE_EXTRABOLD, MANROPE_MEDIUM } from "./invoice_fonts.ts";

/** The 21 photos, in order — same list as web/deliverydashboard.html. */
export const SHOTS: { n: number; area: string }[] = [
  { n: 1, area: "Front" },
  { n: 2, area: "Front-left corner" },
  { n: 3, area: "Left side" },
  { n: 4, area: "Rear-left corner" },
  { n: 5, area: "Rear" },
  { n: 6, area: "Rear-right corner" },
  { n: 7, area: "Right side" },
  { n: 8, area: "Front-right corner" },
  { n: 9, area: "Bonnet / hood" },
  { n: 10, area: "Roof" },
  { n: 11, area: "Windscreen" },
  { n: 12, area: "Rear glass" },
  { n: 13, area: "Front bumper (close-up)" },
  { n: 14, area: "Rear bumper (close-up)" },
  { n: 15, area: "Front-left wheel & tyre" },
  { n: 16, area: "Rear-left wheel & tyre" },
  { n: 17, area: "Rear-right wheel & tyre" },
  { n: 18, area: "Front-right wheel & tyre" },
  { n: 19, area: "Dashboard & odometer" },
  { n: 20, area: "Front seats" },
  { n: 21, area: "Rear seats / cargo area" },
];

export type Severity = "none" | "minor" | "major" | "unclear";

export interface Finding {
  n: number;
  area: string;
  severity: Severity;
  findings: string;
}

export interface InspectionResult {
  items: Finding[];
  ok: number;
  minor: number;
  major: number;
  unclear: number;
  overall: "Good" | "Fair" | "Poor";
  summary: string;
}

export interface Photo {
  n: number;
  bytes: Uint8Array;
  mediaType: "image/jpeg" | "image/png" | "image/webp";
}

export function mediaTypeOf(bytes: Uint8Array): Photo["mediaType"] {
  if (bytes[0] === 0x89 && bytes[1] === 0x50) return "image/png";
  if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[8] === 0x57) return "image/webp";
  return "image/jpeg";
}

function toBase64(bytes: Uint8Array): string {
  let bin = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

// ── Claude ─────────────────────────────────────────────────────────────
const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const MODEL = "claude-haiku-4-5-20251001";

const SYSTEM = `You are a careful vehicle damage inspector for Reperi, a vehicle service company in India.
You look at photos taken by our pickup partner when collecting a fleet vehicle, and record visible
exterior and interior damage: scratches, dents, cracks, chips, broken or missing parts, rust, tears,
and tyre wear or damage. Only report what you can actually see in the photo. Do not guess.
Severity:
- "none": no visible damage.
- "minor": small cosmetic damage (light scratches, scuffs, small chips, light tyre wear).
- "major": dents, cracks, broken/missing parts, deep scratches through paint, torn upholstery, a bald or damaged tyre.
- "unclear": the photo is too dark, blurry, or doesn't show the area.
Write findings in plain English, at most 20 words, naming the exact place (e.g. "Dent on rear-left door, paint intact").
For the dashboard photo, also note the odometer reading and any warning lights if readable.`;

async function claude(apiKey: string, content: unknown[], maxTokens: number): Promise<string> {
  const res = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: maxTokens,
      system: SYSTEM,
      messages: [{ role: "user", content }],
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`Claude ${res.status}: ${JSON.stringify(body).slice(0, 300)}`);
  const text = (body?.content ?? []).filter((c: { type: string }) => c.type === "text").map((c: { text: string }) => c.text).join("");
  return text;
}

function parseJson<T>(text: string, open: "[" | "{"): T | null {
  const close = open === "[" ? "]" : "}";
  const a = text.indexOf(open);
  const b = text.lastIndexOf(close);
  if (a < 0 || b <= a) return null;
  try {
    return JSON.parse(text.slice(a, b + 1)) as T;
  } catch {
    return null;
  }
}

const SEVERITIES = new Set(["none", "minor", "major", "unclear"]);

/** Checks a batch of photos in one Claude call. */
async function checkBatch(apiKey: string, photos: Photo[]): Promise<Finding[]> {
  const content: unknown[] = [];
  for (const p of photos) {
    const area = SHOTS[p.n - 1]?.area ?? `Photo ${p.n}`;
    content.push({ type: "text", text: `Photo ${p.n} — ${area}:` });
    content.push({ type: "image", source: { type: "base64", media_type: p.mediaType, data: toBase64(p.bytes) } });
  }
  content.push({
    type: "text",
    text: `Inspect each photo above. Reply with ONLY a JSON array, one object per photo, in this exact form:
[{"n": <photo number>, "severity": "none"|"minor"|"major"|"unclear", "findings": "<what you see, max 20 words>"}]
If there is no damage, findings should say so briefly, e.g. "No visible damage".`,
  });
  const text = await claude(apiKey, content, 1800);
  const arr = parseJson<{ n: number; severity: string; findings: string }[]>(text, "[") ?? [];
  return photos.map((p) => {
    const hit = arr.find((x) => Number(x?.n) === p.n);
    const sev = SEVERITIES.has(String(hit?.severity)) ? (hit!.severity as Severity) : "unclear";
    return {
      n: p.n,
      area: SHOTS[p.n - 1]?.area ?? `Photo ${p.n}`,
      severity: sev,
      findings: clean(String(hit?.findings ?? "Could not be checked automatically")).slice(0, 160),
    };
  });
}

function overallOf(minor: number, major: number): InspectionResult["overall"] {
  if (major >= 3) return "Poor";
  if (major > 0 || minor >= 4) return "Fair";
  return "Good";
}

/** All 21 photos → findings + a short written summary. */
export async function analysePhotos(apiKey: string, photos: Photo[]): Promise<InspectionResult> {
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY is not set");
  const sorted = [...photos].sort((a, b) => a.n - b.n);
  // 3 calls of 7 photos, side by side — faster and well inside size limits.
  const batches: Photo[][] = [];
  for (let i = 0; i < sorted.length; i += 7) batches.push(sorted.slice(i, i + 7));
  const results = (await Promise.all(batches.map((b) => checkBatch(apiKey, b)))).flat();

  const count = (s: Severity) => results.filter((r) => r.severity === s).length;
  const minor = count("minor"), major = count("major"), unclear = count("unclear");
  const ok = count("none");
  const overall = overallOf(minor, major);

  // Short written summary (text only — cheap). Falls back to a plain one.
  let summary = "";
  try {
    const list = results.map((r) => `${r.n}. ${r.area}: ${r.severity} — ${r.findings}`).join("\n");
    const text = await claude(apiKey, [{
      type: "text",
      text: `These are the findings for a fleet vehicle at pickup:\n${list}\n\nWrite a 2–3 sentence summary of the vehicle's condition for the fleet owner. Mention the most important damage first. Plain text only, no lists, no headings.`,
    }], 300);
    summary = clean(text).trim().slice(0, 600);
  } catch (e) {
    console.error("summary failed", e);
  }
  if (!summary) {
    summary = major + minor === 0
      ? "No visible damage was found in the 21 photos taken at pickup."
      : `${major} area${major === 1 ? "" : "s"} with major damage and ${minor} with minor damage were found in the 21 photos taken at pickup.`;
  }
  return { items: results, ok, minor, major, unclear, overall, summary };
}

// ── PDF ────────────────────────────────────────────────────────────────
/** Keep only characters the embedded font has. */
function clean(s: string): string {
  return s
    .replace(/[→⇒]/g, "->").replace(/[←]/g, "<-").replace(/[≈]/g, "~").replace(/[×✕✖]/g, "x")
    .replace(/[‘’‚]/g, "'").replace(/[“”]/g, '"')
    .replace(/[^\x20-\x7E -ÿ–—…•₹\n]/g, "");
}

const C = {
  navy: rgb(2 / 255, 43 / 255, 87 / 255),
  yellow: rgb(253 / 255, 240 / 255, 3 / 255),
  ink: rgb(0.09, 0.1, 0.11),
  mut: rgb(0.37, 0.38, 0.41),
  line: rgb(0.89, 0.88, 0.85),
  soft: rgb(0.965, 0.96, 0.945),
  green: rgb(0.09, 0.5, 0.24), greenBg: rgb(0.89, 0.965, 0.91),
  amber: rgb(0.54, 0.35, 0), amberBg: rgb(1, 0.957, 0.76),
  red: rgb(0.85, 0.23, 0.25), redBg: rgb(0.99, 0.91, 0.91),
  blue: rgb(0.1, 0.31, 0.71), blueBg: rgb(0.9, 0.93, 1),
  grey: rgb(0.6, 0.6, 0.62), greyBg: rgb(0.94, 0.94, 0.95),
  white: rgb(1, 1, 1),
};

const SEV_STYLE: Record<Severity, { label: string; fg: RGB; bg: RGB }> = {
  none: { label: "OK", fg: C.green, bg: C.greenBg },
  minor: { label: "Minor", fg: C.amber, bg: C.amberBg },
  major: { label: "Major", fg: C.red, bg: C.redBg },
  unclear: { label: "Unclear", fg: C.grey, bg: C.greyBg },
};

interface Fonts { med: PDFFont; bold: PDFFont; xbold: PDFFont }

const W = 595.28, H = 841.89, M = 36;

function b64(s: string): Uint8Array {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function wrap(text: string, font: PDFFont, size: number, width: number): string[] {
  const words = clean(text).split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let line = "";
  for (const w of words) {
    const t = line ? `${line} ${w}` : w;
    if (font.widthOfTextAtSize(t, size) <= width) {
      line = t;
    } else {
      if (line) lines.push(line);
      // A single very long word: cut it.
      let word = w;
      while (font.widthOfTextAtSize(word, size) > width && word.length > 1) {
        let k = word.length;
        while (k > 1 && font.widthOfTextAtSize(word.slice(0, k), size) > width) k--;
        lines.push(word.slice(0, k));
        word = word.slice(k);
      }
      line = word;
    }
  }
  if (line) lines.push(line);
  return lines.length ? lines : [""];
}

export interface ReportDoc {
  reportNo: string;
  company: string;
  vehicle: string;
  plate: string;
  takenAt: string;     // already formatted (IST)
  result: InspectionResult;
  photos: Photo[];
}

export async function renderInspectionPdf(doc: ReportDoc): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const f: Fonts = {
    med: await pdf.embedFont(b64(MANROPE_MEDIUM), { subset: true }),
    bold: await pdf.embedFont(b64(MANROPE_BOLD), { subset: true }),
    xbold: await pdf.embedFont(b64(MANROPE_EXTRABOLD), { subset: true }),
  };
  pdf.setTitle(`Reperi 21-point inspection ${doc.reportNo}`);
  pdf.setAuthor("TRUSTKON TECHNOLOGIES LLP");
  pdf.setCreator("reperi.in");

  // Embed each photo once (used as a thumbnail and on the photo pages).
  const images = new Map<number, PDFImage>();
  for (const p of doc.photos) {
    try {
      const img = p.mediaType === "image/png" ? await pdf.embedPng(p.bytes) : await pdf.embedJpg(p.bytes);
      images.set(p.n, img);
    } catch (e) {
      console.error(`photo ${p.n} could not be embedded`, e);
    }
  }

  const r = doc.result;
  let page = pdf.addPage([W, H]);
  let y = H - M;

  const text = (pg: PDFPage, s: string, x: number, yy: number, size: number, font: PDFFont, color: RGB = C.ink) =>
    pg.drawText(clean(s), { x, y: yy, size, font, color });
  const rightText = (pg: PDFPage, s: string, xr: number, yy: number, size: number, font: PDFFont, color: RGB = C.ink) =>
    pg.drawText(clean(s), { x: xr - font.widthOfTextAtSize(clean(s), size), y: yy, size, font, color });

  const header = (pg: PDFPage) => {
    pg.drawCircle({ x: M + 11, y: H - M - 9, size: 11, color: C.yellow });
    text(pg, "REPERI", M + 30, H - M - 15, 16, f.xbold, C.navy);
    rightText(pg, "21-POINT INSPECTION", W - M, H - M - 8, 9, f.bold, C.mut);
    rightText(pg, `Report no. ${doc.reportNo}`, W - M, H - M - 21, 9, f.med, C.mut);
    pg.drawRectangle({ x: M, y: H - M - 32, width: W - 2 * M, height: 2.5, color: C.navy });
  };
  const footer = (pg: PDFPage, i: number) => {
    text(pg, "TRUSTKON TECHNOLOGIES LLP · reperi.in", M, 20, 8, f.med, C.mut);
    rightText(pg, `Page ${i}`, W - M, 20, 8, f.med, C.mut);
  };

  header(page);
  y = H - M - 62;
  text(page, "Vehicle condition at pickup", M, y, 20, f.xbold, C.navy);
  y -= 22;
  const meta: [string, string][] = [
    ["Vehicle", `${doc.vehicle}${doc.plate ? ` · ${doc.plate}` : ""}`],
    ["Fleet", doc.company || "—"],
    ["Photos taken", doc.takenAt],
    ["Taken by", "Reperi pickup partner"],
  ];
  meta.forEach(([k, v], i) => {
    const x = M + (i % 2) * ((W - 2 * M) / 2);
    const yy = y - Math.floor(i / 2) * 15;
    text(page, `${k}: `, x, yy, 9.5, f.bold, C.ink);
    text(page, v.slice(0, 48), x + f.bold.widthOfTextAtSize(`${k}: `, 9.5), yy, 9.5, f.med, C.ink);
  });
  y -= 44;

  // Summary boxes
  const boxes: [string, string, RGB, RGB][] = [
    [String(r.ok), "NO DAMAGE", C.green, C.greenBg],
    [String(r.minor), "MINOR", C.amber, C.amberBg],
    [String(r.major), "MAJOR", C.red, C.redBg],
    [r.overall, "OVERALL", C.blue, C.blueBg],
  ];
  const bw = (W - 2 * M - 3 * 8) / 4;
  boxes.forEach(([v, l, fg, bg], i) => {
    const x = M + i * (bw + 8);
    page.drawRectangle({ x, y: y - 44, width: bw, height: 50, color: bg });
    const vw = f.xbold.widthOfTextAtSize(v, 20);
    text(page, v, x + (bw - vw) / 2, y - 18, 20, f.xbold, fg);
    const lw = f.bold.widthOfTextAtSize(l, 8);
    text(page, l, x + (bw - lw) / 2, y - 34, 8, f.bold, fg);
  });
  y -= 62;

  // Summary paragraph
  const sumLines = wrap(`Summary: ${r.summary}`, f.med, 10, W - 2 * M - 20);
  const sumH = sumLines.length * 14 + 16;
  page.drawRectangle({ x: M, y: y - sumH, width: W - 2 * M, height: sumH, color: C.soft });
  sumLines.forEach((ln, i) => text(page, ln, M + 10, y - 18 - i * 14, 10, i === 0 ? f.med : f.med, C.ink));
  y -= sumH + 18;

  // Table of all 21 areas
  const cols = { n: M + 6, thumb: M + 26, area: M + 80, find: M + 205, sev: W - M - 58 };
  const findW = cols.sev - cols.find - 10;
  const tableHeader = () => {
    page.drawRectangle({ x: M, y: y - 20, width: W - 2 * M, height: 20, color: C.navy });
    text(page, "#", cols.n, y - 14, 8.5, f.bold, C.white);
    text(page, "Photo", cols.thumb, y - 14, 8.5, f.bold, C.white);
    text(page, "Area", cols.area, y - 14, 8.5, f.bold, C.white);
    text(page, "Findings", cols.find, y - 14, 8.5, f.bold, C.white);
    text(page, "Severity", cols.sev, y - 14, 8.5, f.bold, C.white);
    y -= 20;
  };
  let pageNo = 1;
  tableHeader();
  for (const it of r.items) {
    const lines = wrap(it.findings, f.med, 8.5, findW);
    const areaLines = wrap(it.area, f.bold, 8.5, cols.find - cols.area - 8);
    const rowH = Math.max(36, Math.max(lines.length, areaLines.length) * 11 + 12);
    if (y - rowH < 40) {
      footer(page, pageNo);
      page = pdf.addPage([W, H]);
      pageNo++;
      header(page);
      y = H - M - 50;
      tableHeader();
    }
    const top = y;
    text(page, String(it.n), cols.n, top - 14, 8.5, f.bold, C.mut);
    const img = images.get(it.n);
    if (img) {
      const s = Math.min(46 / img.width, 28 / img.height);
      page.drawImage(img, { x: cols.thumb, y: top - 6 - img.height * s, width: img.width * s, height: img.height * s });
    }
    areaLines.forEach((ln, i) => text(page, ln, cols.area, top - 14 - i * 11, 8.5, f.bold, C.ink));
    lines.forEach((ln, i) => text(page, ln, cols.find, top - 14 - i * 11, 8.5, f.med, C.ink));
    const st = SEV_STYLE[it.severity];
    const pw = f.bold.widthOfTextAtSize(st.label, 8) + 12;
    page.drawRectangle({ x: cols.sev, y: top - 18, width: pw, height: 13, color: st.bg });
    text(page, st.label, cols.sev + 6, top - 14.5, 8, f.bold, st.fg);
    y -= rowH;
    page.drawLine({ start: { x: M, y }, end: { x: W - M, y }, thickness: 0.6, color: C.line });
  }
  y -= 14;
  const note = wrap(
    "AI-assisted assessment from photos taken at pickup. Hidden damage, or damage too small to see in a photo, may not be listed. All 21 photos follow.",
    f.med, 8, W - 2 * M,
  );
  if (y - note.length * 11 < 40) {
    footer(page, pageNo);
    page = pdf.addPage([W, H]);
    pageNo++;
    header(page);
    y = H - M - 50;
  }
  note.forEach((ln, i) => text(page, ln, M, y - i * 11, 8, f.med, C.mut));
  footer(page, pageNo);

  // Photo pages: 2 × 3 per page
  const gap = 14;
  const tileW = (W - 2 * M - gap) / 2;
  const imgH = 170;
  const tileH = imgH + 64;
  for (let i = 0; i < SHOTS.length; i++) {
    if (i % 6 === 0) {
      page = pdf.addPage([W, H]);
      pageNo++;
      header(page);
      text(page, "Photos taken at pickup", M, H - M - 56, 13, f.xbold, C.navy);
    }
    const k = i % 6;
    const x = M + (k % 2) * (tileW + gap);
    const top = H - M - 70 - Math.floor(k / 2) * (tileH + 12);
    const shot = SHOTS[i];
    const it = r.items.find((x) => x.n === shot.n);
    page.drawRectangle({ x, y: top - imgH, width: tileW, height: imgH, color: C.soft });
    const img = images.get(shot.n);
    if (img) {
      const s = Math.min(tileW / img.width, imgH / img.height);
      const w = img.width * s, h = img.height * s;
      page.drawImage(img, { x: x + (tileW - w) / 2, y: top - imgH + (imgH - h) / 2, width: w, height: h });
    } else {
      text(page, "Photo not available", x + 10, top - imgH / 2, 9, f.med, C.mut);
    }
    text(page, `${shot.n} · ${shot.area}`, x, top - imgH - 15, 9.5, f.bold, C.ink);
    if (it) {
      const st = SEV_STYLE[it.severity];
      const pw = f.bold.widthOfTextAtSize(st.label, 8) + 12;
      page.drawRectangle({ x: x + tileW - pw, y: top - imgH - 19, width: pw, height: 13, color: st.bg });
      text(page, st.label, x + tileW - pw + 6, top - imgH - 15.5, 8, f.bold, st.fg);
      wrap(it.findings, f.med, 8.5, tileW).slice(0, 3)
        .forEach((ln, j) => text(page, ln, x, top - imgH - 29 - j * 11, 8.5, f.med, C.mut));
    }
    if (k === 5 || i === SHOTS.length - 1) footer(page, pageNo);
  }

  return await pdf.save();
}

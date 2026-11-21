// Draws the "Reperi Scan — Vehicle OBD-II Health Report" PDF in the same
// layout as the Tata Harrier sample: yellow top band, logo + title, navy
// score box + verdict, then tables (details, component ratings with bars,
// fault codes, readiness monitors, live data, Mode 6), findings, limits,
// scanner photos, and a navy footer on every page.

import { PDFDocument, type PDFFont, type PDFImage, type PDFPage, rgb, StandardFonts } from "npm:pdf-lib@1.17.1";
import { REPERI_LOGO_JPEG_BASE64 } from "./logo.ts";
import type { ObdReport } from "./analyse.ts";

export interface PdfInput {
  report: ObdReport;
  reportNo: string;
  scanDate: string; // "20 October 2026"
  shortDate: string; // "20 Oct 2026"
  vehicleTitle: string; // header line, e.g. "Tata Harrier (2.0 Kryotec diesel)"
  registration: string;
  customerName: string;
  complaint: string;
  expert: string;
  photos: Array<{ bytes: Uint8Array; mediaType: string }>;
}

const hex = (h: string) => rgb(parseInt(h.slice(1, 3), 16) / 255, parseInt(h.slice(3, 5), 16) / 255, parseInt(h.slice(5, 7), 16) / 255);
const C = {
  navy: hex("#0B2A6F"), yellow: hex("#FFD400"), green: hex("#1E9E5A"), amber: hex("#E8A317"), red: hex("#D64545"),
  track: hex("#E3E7EE"), zebra: hex("#F3F5F8"), line: hex("#DCE1E9"), text: hex("#1B1E24"), gray: hex("#5F6672"),
  soft: hex("#F1F3F6"), white: rgb(1, 1, 1), na: hex("#7A818C"),
};
const PAGE_W = 595.28, PAGE_H = 841.89, M = 42, W = PAGE_W - 2 * M;
const FOOT_H = 32, BOTTOM = FOOT_H + 26;

type Cell = { text: string; bold?: boolean; color?: ReturnType<typeof rgb>; score?: number };
type Col = { title: string; w: number };

const scoreColor = (n: number) => (n >= 8 ? C.green : n >= 6 ? C.amber : C.red);
const statusColor = (s: string) => {
  const t = s.toUpperCase();
  if (t.startsWith("INCOMPLETE") || t.includes("NEAR")) return C.amber;
  if (t.startsWith("OK") || t.startsWith("PASS")) return C.green;
  if (t.startsWith("FAIL")) return C.red;
  return C.na;
};

export async function renderReportPdf(input: PdfInput): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  doc.setTitle(`Reperi Scan - ${input.vehicleTitle} - ${input.reportNo}`);
  doc.setAuthor("Reperi by Trustkon Technologies");
  doc.setCreator("Reperi Scan");
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const logo = await doc.embedJpg(Uint8Array.from(atob(REPERI_LOGO_JPEG_BASE64), (c) => c.charCodeAt(0)));

  // ── Text helpers (standard PDF fonts only know Western characters) ──
  const okChar = new Map<string, boolean>();
  const MAP: Record<string, string> = {
    "‘": "'", "’": "'", "“": '"', "”": '"', "→": "->", "←": "<-", "≈": "~",
    "≤": "<=", "≥": ">=", "₹": "Rs.", "✓": "OK", "✔": "OK", "✗": "x", " ": " ",
    "−": "-", "‑": "-", "‐": "-", "μ": "u", "′": "'", "″": '"', " ": " ", " ": " ",
  };
  const clean = (t: string) => {
    let out = "";
    for (const ch of String(t ?? "").replace(/[\r\t]+/g, " ")) {
      const c = MAP[ch] ?? ch;
      if (c.length > 1 || c === "\n") { out += c; continue; }
      if (!okChar.has(c)) {
        try { font.encodeText(c); okChar.set(c, true); } catch { okChar.set(c, false); }
      }
      out += okChar.get(c) ? c : "?";
    }
    return out;
  };
  const wrap = (text: string, f: PDFFont, size: number, width: number): string[] => {
    const lines: string[] = [];
    for (const para of clean(text).split("\n")) {
      let line = "";
      for (const word of para.split(/ +/)) {
        if (!word) continue;
        const tryLine = line ? `${line} ${word}` : word;
        if (f.widthOfTextAtSize(tryLine, size) <= width) { line = tryLine; continue; }
        if (line) lines.push(line);
        // A single word wider than the column (e.g. a VIN) is cut by characters.
        let w = word;
        while (f.widthOfTextAtSize(w, size) > width && w.length > 1) {
          let n = w.length;
          while (n > 1 && f.widthOfTextAtSize(w.slice(0, n), size) > width) n--;
          lines.push(w.slice(0, n));
          w = w.slice(n);
        }
        line = w;
      }
      lines.push(line);
    }
    return lines.length ? lines : [""];
  };

  // ── Pages ──
  let page!: PDFPage;
  let y = 0;
  let pageNo = 0;
  const newPage = () => {
    page = doc.addPage([PAGE_W, PAGE_H]);
    pageNo++;
    page.drawRectangle({ x: 0, y: PAGE_H - 13, width: PAGE_W, height: 13, color: C.yellow });
    page.drawRectangle({ x: 0, y: 0, width: PAGE_W, height: FOOT_H, color: C.navy });
    page.drawText(clean(`Reperi Scan  |  Generic OBD-II report (engine ECU only)  |  ${input.shortDate}`), {
      x: M, y: 12, size: 7.8, font, color: C.white,
    });
    const pn = `Page ${pageNo}`;
    page.drawText(pn, { x: PAGE_W - M - font.widthOfTextAtSize(pn, 7.8), y: 12, size: 7.8, font, color: C.white });
    y = PAGE_H - 46;
  };
  const ensure = (h: number) => { if (y - h < BOTTOM) newPage(); };
  const roundRect = (x: number, yTop: number, w: number, h: number, r: number, color: ReturnType<typeof rgb>) => {
    const p = `M ${r} 0 H ${w - r} Q ${w} 0 ${w} ${r} V ${h - r} Q ${w} ${h} ${w - r} ${h} H ${r} Q 0 ${h} 0 ${h - r} V ${r} Q 0 0 ${r} 0 Z`;
    page.drawSvgPath(p, { x, y: yTop, color });
  };

  // Keeps a heading together with the start of what follows (no heading
  // stranded at the bottom of a page).
  const heading = (t: string, keepWith = 110) => {
    ensure(38 + keepWith);
    y -= 12;
    page.drawText(clean(t), { x: M, y: y - 14, size: 14.5, font: bold, color: C.navy });
    y -= 26;
  };
  const paragraph = (t: string, size = 9.6, color = C.text, f: PDFFont = font, gap = 4) => {
    const lh = size * 1.38;
    for (const line of wrap(t, f, size, W)) {
      ensure(lh);
      page.drawText(line, { x: M, y: y - size, size, font: f, color });
      y -= lh;
    }
    y -= gap;
  };

  const table = (cols: Col[], rows: Cell[][]) => {
    const size = 8.6, lh = 11.4, pad = 6;
    const widths = cols.map((c) => c.w * W);
    const xs = widths.map((_, i) => M + widths.slice(0, i).reduce((a, b) => a + b, 0));
    const drawHeader = () => {
      const h = lh + pad * 2;
      page.drawRectangle({ x: M, y: y - h, width: W, height: h, color: C.navy });
      cols.forEach((c, i) => page.drawText(clean(c.title), { x: xs[i] + pad, y: y - pad - size, size, font: bold, color: C.white }));
      y -= h;
    };
    ensure(lh * 3 + pad * 4);
    drawHeader();
    rows.forEach((row, r) => {
      const cellLines = row.map((cell, i) =>
        cell.score !== undefined ? [""] : wrap(cell.text, cell.bold ? bold : font, size, widths[i] - pad * 2));
      const h = Math.max(...cellLines.map((l) => l.length)) * lh + pad * 2;
      if (y - h < BOTTOM) { newPage(); drawHeader(); }
      page.drawRectangle({
        x: M, y: y - h, width: W, height: h, color: r % 2 ? C.zebra : C.white, borderColor: C.line, borderWidth: 0.6,
      });
      for (let i = 1; i < cols.length; i++) {
        page.drawLine({ start: { x: xs[i], y }, end: { x: xs[i], y: y - h }, thickness: 0.6, color: C.line });
      }
      row.forEach((cell, i) => {
        if (cell.score !== undefined) {
          const barW = Math.max(40, widths[i] - pad * 2 - 34), barH = 11, by = y - h / 2 - barH / 2;
          page.drawRectangle({ x: xs[i] + pad, y: by, width: barW, height: barH, color: C.track });
          page.drawRectangle({ x: xs[i] + pad, y: by, width: barW * cell.score / 10, height: barH, color: scoreColor(cell.score) });
          page.drawText(`${cell.score}/10`, { x: xs[i] + pad + barW + 8, y: by + 1.5, size: 8.8, font: bold, color: scoreColor(cell.score) });
          return;
        }
        const lines = cellLines[i];
        let ty = y - (h - lines.length * lh) / 2 - size + 0.5;
        for (const line of lines) {
          page.drawText(line, { x: xs[i] + pad, y: ty, size, font: cell.bold ? bold : font, color: cell.color ?? C.text });
          ty -= lh;
        }
      });
      y -= h;
    });
    y -= 6;
  };
  const note = (t: string) => { if (t) paragraph(t, 7.8, C.gray, font, 2); };

  // ── Page 1 header ──
  const r = input.report;
  newPage();
  const top = y + 6;
  page.drawImage(logo, { x: M, y: top - 82, width: 82, height: 82 });
  page.drawText("REPERI SCAN", { x: M + 98, y: top - 30, size: 27, font: bold, color: C.navy });
  page.drawText("Vehicle OBD-II Health Report", { x: M + 98, y: top - 48, size: 11.5, font: bold, color: C.navy });
  const sub = wrap(`${input.vehicleTitle} · Scan date: ${input.scanDate}`, font, 10, W - 98)[0];
  page.drawText(sub, { x: M + 98, y: top - 64, size: 10, font, color: C.gray });
  y = top - 100;

  // Score box + verdict
  const boxW = 112, gap = 14, vx = M + boxW + gap, vw = W - boxW - gap, vsize = 9.6, vlh = 13.2;
  const head = clean(r.verdict_headline ? `Verdict: ${r.verdict_headline}` : "Verdict:");
  const restWords = clean(r.verdict).split(/ +/).filter(Boolean);
  // First line starts with the bold headline; the rest is regular text.
  const vlines: Array<Array<{ t: string; b: boolean }>> = [];
  {
    let line: Array<{ t: string; b: boolean }> = [];
    let lineW = 0;
    const push = (word: string, b: boolean) => {
      const f = b ? bold : font;
      const piece = (line.length ? " " : "") + word;
      const pw = f.widthOfTextAtSize(piece, vsize);
      if (line.length && lineW + pw > vw - 24) {
        vlines.push(line);
        line = [{ t: word, b }];
        lineW = f.widthOfTextAtSize(word, vsize);
        return;
      }
      line.push({ t: piece, b });
      lineW += pw;
    };
    head.split(/ +/).forEach((w) => push(w, true));
    restWords.forEach((w) => push(w, false));
    if (line.length) vlines.push(line);
  }
  const vh = Math.max(84, vlines.length * vlh + 22);
  roundRect(M, y, boxW, vh, 8, C.navy);
  const sc = r.overall_score.toFixed(1);
  page.drawText(sc, { x: M + boxW / 2 - bold.widthOfTextAtSize(sc, 30) / 2, y: y - vh / 2 + 2, size: 30, font: bold, color: C.yellow });
  page.drawText("OVERALL / 10", { x: M + boxW / 2 - bold.widthOfTextAtSize("OVERALL / 10", 7.6) / 2, y: y - vh / 2 - 18, size: 7.6, font: bold, color: C.white });
  page.drawRectangle({ x: vx, y: y - vh, width: vw, height: vh, color: C.soft });
  let ly = y - (vh - vlines.length * vlh) / 2 - vsize + 1;
  for (const line of vlines) {
    let lx = vx + 12;
    for (const seg of line) {
      const f = seg.b ? bold : font;
      page.drawText(seg.t, { x: lx, y: ly, size: vsize, font: f, color: C.text });
      lx += f.widthOfTextAtSize(seg.t, vsize);
    }
    ly -= vlh;
  }
  y -= vh + 6;

  // ── Vehicle & scan details ──
  heading("Vehicle & scan details");
  const details: Cell[][] = [];
  const add = (k: string, v: string) => { if (v && v.trim()) details.push([{ text: k, bold: true }, { text: v }]); };
  add("Vehicle", r.vehicle_name || input.vehicleTitle);
  add("Registration", input.registration);
  add("Customer", input.customerName);
  add("Customer's complaint", input.complaint || "No specific complaint - routine check");
  add("VIN (as read from scanner)", r.vin ? `${r.vin} - verify against the RC / chassis plate` : "");
  add("Calibration ID", r.calibration_id ? `${r.calibration_id} (as read)` : "");
  add("Scan tool", r.scan_tool);
  add("Engine state at scan", r.engine_state);
  add("Report no.", input.reportNo);
  add("Inspected by", input.expert);
  table([{ title: "Item", w: 0.36 }, { title: "Value", w: 0.64 }], details);

  // ── Component ratings ──
  if (r.components.length) {
    heading("Component ratings");
    table(
      [{ title: "Component", w: 0.3 }, { title: "Score", w: 0.32 }, { title: "Basis", w: 0.38 }],
      r.components.map((c) => [{ text: c.name, bold: true }, { text: "", score: c.score }, { text: c.basis }]),
    );
    note("Ratings: 9-10 healthy, 6-8 not fully verified or near a limit, 5 and below needs attention. Scores reflect only what this scan and the owner's description show; they are not a substitute for a physical inspection.");
  }

  // ── Fault codes ──
  if (r.fault_codes.length) {
    heading("Fault codes");
    const sevColor = (s: string) => (s === "high" ? C.red : s === "low" ? C.green : C.amber);
    const sevText = (s: string) => (s === "high" ? "Fix soon" : s === "low" ? "Low" : "Check");
    table(
      [{ title: "Code", w: 0.14 }, { title: "What it means", w: 0.56 }, { title: "Type", w: 0.14 }, { title: "Priority", w: 0.16 }],
      r.fault_codes.map((f) => [
        { text: f.code, bold: true }, { text: f.description },
        { text: f.type.charAt(0).toUpperCase() + f.type.slice(1) },
        { text: sevText(f.severity), bold: true, color: sevColor(f.severity) },
      ]),
    );
  }

  // ── Readiness monitors ──
  const count = (s: string) => r.monitors.filter((m) => m.status === s).length;
  const summaryLine = [
    r.mil !== "UNKNOWN" ? `MIL ${r.mil}` : "",
    r.codes_found !== null ? `Codes found ${r.codes_found}` : "",
    r.monitors.length ? `Monitors OK ${count("OK")}` : "",
    count("INCOMPLETE") ? `Incomplete ${count("INCOMPLETE")}` : "",
    count("FAIL") ? `Failed ${count("FAIL")}` : "",
    count("N/A") ? `N/A ${count("N/A")}` : "",
  ].filter(Boolean).join(" · ");
  if (r.monitors.length) {
    heading("Readiness monitors");
    if (r.monitors_note) paragraph(r.monitors_note, 9.2, C.text, font, 6);
    table(
      [{ title: "Scanner label", w: 0.3 }, { title: r.fuel === "diesel" ? "Diesel meaning" : "Meaning", w: 0.44 }, { title: "Status", w: 0.26 }],
      r.monitors.map((m) => [{ text: m.scanner_label, bold: true }, { text: m.meaning }, { text: m.status, bold: true, color: statusColor(m.status) }]),
    );
  }
  if (summaryLine) paragraph(`Summary: ${summaryLine}`, 8.8, C.text, bold, 4);

  // ── Live data ──
  if (r.live_data.length) {
    heading(r.live_data_title || "Live data");
    table(
      [{ title: "Parameter", w: 0.3 }, { title: "Reading", w: 0.3 }, { title: "Assessment", w: 0.4 }],
      r.live_data.map((d) => [{ text: d.parameter, bold: true }, { text: d.reading }, { text: d.assessment }]),
    );
  }

  // ── Mode 6 ──
  if (r.mode6.length) {
    heading("On-board test results (Mode 6)");
    table(
      [{ title: "Test", w: 0.39 }, { title: "Measured", w: 0.15 }, { title: "Limits", w: 0.22 }, { title: "Result", w: 0.24 }],
      r.mode6.map((t) => [{ text: t.test, bold: true }, { text: t.measured }, { text: t.limits }, { text: t.result, color: statusColor(t.result) }]),
    );
    note(r.mode6_note);
  }

  // ── Findings ──
  if (r.findings.length) {
    heading("Findings & recommendations", 70);
    r.findings.forEach((f, i) => {
      ensure(40);
      const t = wrap(`${i + 1}. ${f.title}`, bold, 10.4, W);
      for (const line of t) {
        page.drawText(line, { x: M, y: y - 10.4, size: 10.4, font: bold, color: C.navy });
        y -= 14;
      }
      y -= 1;
      paragraph(f.detail, 9.4, C.text, font, 8);
    });
  }

  // ── Scope & limitations ──
  heading("Scope & limitations", 60);
  paragraph(r.limitations, 9.4, C.text, font, 4);

  // ── Scanner photos ──
  const imgs: PDFImage[] = [];
  for (const p of input.photos) {
    try {
      if (p.mediaType === "image/png") imgs.push(await doc.embedPng(p.bytes));
      else if (p.mediaType === "image/jpeg") imgs.push(await doc.embedJpg(p.bytes));
    } catch (e) {
      console.error("photo not embedded", e);
    }
  }
  if (imgs.length) {
    heading("Scanner photos (as taken)", 180);
    const perRow = 3, gapP = 10, cw = (W - gapP * (perRow - 1)) / perRow, maxH = 170;
    for (let i = 0; i < imgs.length; i += perRow) {
      const rowImgs = imgs.slice(i, i + perRow);
      const dims = rowImgs.map((im) => im.scaleToFit(cw, maxH));
      const rowH = Math.max(...dims.map((d) => d.height)) + 16;
      ensure(rowH + 4);
      rowImgs.forEach((im, j) => {
        const d = dims[j];
        const x = M + j * (cw + gapP) + (cw - d.width) / 2;
        page.drawImage(im, { x, y: y - d.height, width: d.width, height: d.height });
        page.drawRectangle({ x, y: y - d.height, width: d.width, height: d.height, borderColor: C.line, borderWidth: 0.8 });
        const cap = `Photo ${i + j + 1}`;
        page.drawText(cap, { x: M + j * (cw + gapP) + cw / 2 - font.widthOfTextAtSize(cap, 7.8) / 2, y: y - d.height - 11, size: 7.8, font, color: C.gray });
      });
      y -= rowH + 4;
    }
  }

  return await doc.save();
}

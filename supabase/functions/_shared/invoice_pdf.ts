// Reperi bill (tax invoice) — maths + PDF drawing. No database access here;
// invoice.ts collects the data and calls renderInvoicePdf().
//
// Prices in the database already INCLUDE GST. The bill only splits them:
//   taxable = price ÷ (1 + rate)      e.g. ₹199 @ 18% → ₹168.64 + ₹30.36
//   CGST = SGST = half of the GST     (Karnataka, intra-state)
// Pickup & drop is 5% (2.5% + 2.5%); everything else 18% (9% + 9%).
// Nothing in the database is changed by any of this.

import { PDFDocument, type PDFFont, type PDFPage, rgb, type RGB } from "npm:pdf-lib@1.17.1";
import fontkit from "npm:@pdf-lib/fontkit@1.1.1";
import { MANROPE_BOLD, MANROPE_EXTRABOLD, MANROPE_MEDIUM } from "./invoice_fonts.ts";

export const SELLER = {
  name: "TRUSTKON TECHNOLOGIES LLP",
  tagline: "Legal billing entity for the reperi.in brand",
  gstin: "29ABAFT4948H1ZS",
  address: "T4B507 SriramSymphonye, Bangalore 560062",
  phone: "7022149521",
  placeOfSupply: "Karnataka (CGST + SGST)",
};

export const GST_SERVICE = 18;
export const GST_PICKUP = 5;

export interface InvoiceLine {
  name: string;
  /** Rupees, GST included. 0 = FREE. Negative = discount. */
  amount: number;
  /** 18 or 5 (percent). */
  gst: number;
  /** Shown under the name, e.g. "Added by garage". */
  note?: string;
  free?: boolean;
}

export interface InvoiceDoc {
  invoiceNo: string;
  issuedAt: string; // ISO
  title: string; // "Your service bill"
  statusText: string; // "Service completed"
  customerName: string;
  customerPhone?: string | null;
  vehicle: string;
  regNo: string;
  bookingRef: string;
  serviceDate: string;
  garage?: string | null;
  lines: InvoiceLine[];
  paidOnline: number;
  replacesNo?: string | null;
}

export interface GstGroup {
  rate: number;
  gross: number;
  taxable: number;
  cgst: number;
  sgst: number;
}

const r2 = (x: number) => Math.round((x + Number.EPSILON) * 100) / 100;

export function computeTotals(lines: InvoiceLine[]) {
  const byRate = new Map<number, number>();
  for (const l of lines) {
    if (!l.amount) continue;
    byRate.set(l.gst, (byRate.get(l.gst) ?? 0) + l.amount);
  }
  const groups: GstGroup[] = [...byRate.entries()]
    .filter(([, gross]) => gross > 0)
    .sort((a, b) => b[0] - a[0])
    .map(([rate, gross]) => {
      const taxable = r2(gross / (1 + rate / 100));
      const tax = r2(gross - taxable); // so taxable + tax is exactly the price
      const cgst = r2(tax / 2);
      return { rate, gross: r2(gross), taxable, cgst, sgst: r2(tax - cgst) };
    });
  const total = r2(lines.reduce((s, l) => s + (l.amount || 0), 0));
  const charges = r2(lines.reduce((s, l) => s + (l.amount > 0 ? l.amount : 0), 0));
  const discounts = r2(lines.reduce((s, l) => s + (l.amount < 0 ? -l.amount : 0), 0));
  const taxable = r2(groups.reduce((s, g) => s + g.taxable, 0));
  return { groups, total, charges, discounts, taxable };
}

/** T-REPERI-26-27-<DDMMYYYY><h><mm><vehicle id> — Indian time, 12-hour clock. */
export function invoiceNumber(at: Date, vehicleId: string): string {
  const ist = new Date(at.getTime() + 330 * 60000);
  const y = ist.getUTCFullYear();
  const m = ist.getUTCMonth() + 1;
  const d = ist.getUTCDate();
  const fyStart = m >= 4 ? y : y - 1; // financial year: April → March
  const fy = `${String(fyStart % 100).padStart(2, "0")}-${String((fyStart + 1) % 100).padStart(2, "0")}`;
  const h24 = ist.getUTCHours();
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  const mm = String(ist.getUTCMinutes()).padStart(2, "0");
  const date = `${String(d).padStart(2, "0")}${String(m).padStart(2, "0")}${y}`;
  return `T-REPERI-${fy}-${date}${h12}${mm}${vehicleId}`;
}

export function formatIstDate(iso: string, withTime = false): string {
  const at = new Date(iso);
  if (isNaN(at.getTime())) return "";
  const ist = new Date(at.getTime() + 330 * 60000);
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  let s = `${ist.getUTCDate()} ${months[ist.getUTCMonth()]} ${ist.getUTCFullYear()}`;
  if (withTime) {
    const h = ist.getUTCHours();
    s += `, ${h % 12 === 0 ? 12 : h % 12}:${String(ist.getUTCMinutes()).padStart(2, "0")} ${h >= 12 ? "PM" : "AM"}`;
  }
  return s;
}

const inr = (n: number, decimals = false) => {
  const neg = n < 0;
  const v = Math.abs(n);
  const [whole, frac] = (decimals ? v.toFixed(2) : String(Math.round(v))).split(".");
  // Indian grouping: 1,23,45,678
  const last3 = whole.slice(-3);
  const rest = whole.slice(0, -3).replace(/\B(?=(\d{2})+(?!\d))/g, ",");
  const grouped = rest ? `${rest},${last3}` : last3;
  return `${neg ? "−" : ""}₹${grouped}${frac !== undefined ? "." + frac : ""}`;
};

// ── Drawing ───────────────────────────────────────────────────────────────
const C = {
  page: rgb(0.969, 0.965, 0.949),
  card: rgb(1, 1, 1),
  ink: rgb(0.086, 0.082, 0.067),
  mut: rgb(0.48, 0.475, 0.46),
  faint: rgb(0.6, 0.6, 0.58),
  line: rgb(0.925, 0.92, 0.9),
  gold: rgb(0.725, 0.541, 0.071),
  goldSoft: rgb(1, 0.965, 0.84),
  yellow: rgb(0.992, 0.941, 0.012),
  navy: rgb(0.008, 0.169, 0.341),
  green: rgb(0.122, 0.667, 0.349),
  greenSoft: rgb(0.91, 0.965, 0.933),
  thanks: rgb(1, 0.976, 0.878),
  thanksLine: rgb(0.953, 0.886, 0.635),
};

const W = 420;
const M = 18; // page margin
const P = 14; // card padding
const CW = W - M * 2; // card width

interface Fonts {
  med: PDFFont;
  bold: PDFFont;
  xbold: PDFFont;
}

class Painter {
  y = 0;
  constructor(public page: PDFPage | null, public H: number, public f: Fonts) {}

  get dry() {
    return this.page === null;
  }

  text(s: string, x: number, top: number, size: number, font: PDFFont, color: RGB, spacing = 0) {
    if (this.dry) return;
    if (!spacing) {
      this.page!.drawText(s, { x, y: this.H - top - size * 0.8, size, font, color });
      return;
    }
    let cx = x;
    for (const ch of s) {
      this.page!.drawText(ch, { x: cx, y: this.H - top - size * 0.8, size, font, color });
      cx += font.widthOfTextAtSize(ch, size) + spacing;
    }
  }

  width(s: string, size: number, font: PDFFont, spacing = 0) {
    return font.widthOfTextAtSize(s, size) + (spacing ? spacing * (s.length - 1) : 0);
  }

  rightText(s: string, right: number, top: number, size: number, font: PDFFont, color: RGB) {
    this.text(s, right - this.width(s, size, font), top, size, font, color);
  }

  /** Word-wraps; returns the height used. */
  wrap(s: string, x: number, top: number, maxW: number, size: number, font: PDFFont, color: RGB, lh = 1.3) {
    const words = String(s).split(/\s+/).filter(Boolean);
    const lines: string[] = [];
    let cur = "";
    for (const w of words) {
      const tryLine = cur ? cur + " " + w : w;
      if (this.width(tryLine, size, font) <= maxW) {
        cur = tryLine;
        continue;
      }
      if (cur) lines.push(cur);
      // A single word longer than the line (e.g. the invoice number): split it.
      let word = w;
      while (this.width(word, size, font) > maxW) {
        let cut = word.length - 1;
        while (cut > 1 && this.width(word.slice(0, cut), size, font) > maxW) cut--;
        lines.push(word.slice(0, cut));
        word = word.slice(cut);
      }
      cur = word;
    }
    if (cur) lines.push(cur);
    if (!lines.length) lines.push("");
    lines.forEach((l, i) => this.text(l, x, top + i * size * lh, size, font, color));
    return lines.length * size * lh;
  }

  roundRect(x: number, top: number, w: number, h: number, r: number, fill?: RGB, border?: RGB, bw = 1) {
    if (this.dry) return;
    r = Math.min(r, w / 2, h / 2);
    const path = `M ${r} 0 H ${w - r} Q ${w} 0 ${w} ${r} V ${h - r} Q ${w} ${h} ${w - r} ${h} H ${r} Q 0 ${h} 0 ${h - r} V ${r} Q 0 0 ${r} 0 Z`;
    this.page!.drawSvgPath(path, {
      x,
      y: this.H - top,
      color: fill,
      borderColor: border,
      borderWidth: border ? bw : 0,
    });
  }

  circle(cx: number, cy: number, r: number, fill?: RGB, border?: RGB, bw = 1, opacity = 1) {
    if (this.dry) return;
    this.page!.drawCircle({
      x: cx,
      y: this.H - cy,
      size: r,
      color: fill,
      borderColor: border,
      borderWidth: border ? bw : 0,
      opacity,
      borderOpacity: opacity,
    });
  }

  line(x1: number, top: number, x2: number, color: RGB, t = 1, dash = false) {
    if (this.dry) return;
    this.page!.drawLine({
      start: { x: x1, y: this.H - top },
      end: { x: x2, y: this.H - top },
      thickness: t,
      color,
      dashArray: dash ? [3, 3] : undefined,
    });
  }

  /** Tick mark drawn as lines (the font has no ✓). */
  tick(x: number, top: number, s: number, color: RGB) {
    if (this.dry) return;
    const p = this.page!;
    p.drawLine({ start: { x, y: this.H - top - s * 0.55 }, end: { x: x + s * 0.35, y: this.H - top - s * 0.9 }, thickness: 1.4, color });
    p.drawLine({ start: { x: x + s * 0.35, y: this.H - top - s * 0.9 }, end: { x: x + s, y: this.H - top - s * 0.15 }, thickness: 1.4, color });
  }

  /** Yellow disc + navy spanner (same mark as the app). */
  logo(x: number, top: number, size: number) {
    if (this.dry) return;
    const r = size / 2;
    const cx = x + r, cy = top + r;
    this.circle(cx, cy, r, C.yellow, rgb(1, 1, 1), size * 0.05);
    // Spanner in a 100×100 box, rotated 45°, scaled to 62% of the disc.
    const s = (size * 0.62) / 100;
    const ang = Math.PI / 4;
    const tr = (px: number, py: number): [number, number] => {
      const dx = px - 50, dy = py - 50;
      const rx = dx * Math.cos(ang) - dy * Math.sin(ang);
      const ry = dx * Math.sin(ang) + dy * Math.cos(ang);
      return [cx + rx * s, cy + ry * s];
    };
    const poly = (pts: [number, number][], color: RGB) => {
      const t = pts.map(([px, py]) => tr(px, py));
      const d = t.map(([px, py], i) => `${i ? "L" : "M"} ${px - cx} ${py - cy}`).join(" ") + " Z";
      this.page!.drawSvgPath(d, { x: cx, y: this.H - cy, color });
    };
    const [hx, hy] = tr(50, 22);
    this.circle(hx, hy, 17 * s, C.navy);
    poly([[43, 34], [57, 34], [56, 44], [44, 44]], C.navy);
    poly([[44, 40], [56, 40], [56, 91], [53, 94], [47, 94], [44, 91]], C.navy);
    poly([[43.5, 0], [56.5, 0], [56.5, 19], [53, 25], [47, 25], [43.5, 19]], C.yellow);
  }
}

function layout(p: Painter, doc: InvoiceDoc) {
  const f = p.f;
  const totals = computeTotals(doc.lines);
  let y = M;

  // Header: logo + REPERI / reperi.in, TAX INVOICE on the right.
  p.logo(M, y, 34);
  p.text("REPERI", M + 42, y + 4, 15, f.xbold, C.ink, 3.2);
  p.text("reperi.in", M + 42, y + 22, 8.5, f.bold, C.gold);
  p.rightText("TAX INVOICE", W - M, y + 12, 9, f.xbold, C.gold);
  y += 50;

  p.text("REPERI · SERVICE BILL", M, y, 8.5, f.xbold, C.gold, 1.2);
  y += 16;
  p.text(doc.title, M, y, 21, f.xbold, C.ink);
  const st = doc.statusText;
  const stW = p.width(st, 9, f.xbold);
  p.circle(W - M - stW - 8, y + 11, 3, C.green);
  p.text(st, W - M - stW, y + 7, 9, f.xbold, C.green);
  y += 30;
  y += p.wrap(`Invoice ${doc.invoiceNo}`, M, y, CW, 9.5, f.bold, C.mut);
  y += p.wrap(`Issued ${formatIstDate(doc.issuedAt, true)}`, M, y, CW, 9.5, f.med, C.mut);
  y += 10;

  // Dark total card.
  const paidOnline = Math.min(Math.max(doc.paidOnline, 0), totals.total);
  const cash = Math.max(0, Math.round((totals.total - paidOnline) * 100) / 100);
  const payText = paidOnline > 0 && cash > 0
    ? `Paid online ${inr(paidOnline)}  ·  Cash ${inr(cash)}`
    : paidOnline > 0
    ? `Paid online ${inr(paidOnline)}`
    : totals.total > 0
    ? `Payable in cash ${inr(cash)}`
    : "Nothing to pay";
  const cardTop = y;
  const cardH = 120;
  p.roundRect(M, cardTop, CW, cardH, 16, C.ink);
  // Decorative ring, kept fully inside the card.
  p.circle(M + CW - 52, cardTop + 60, 30, undefined, C.gold, 12, 0.22);
  p.text("Total amount", M + P, cardTop + P, 10, f.med, rgb(0.85, 0.84, 0.8));
  const big = inr(totals.total);
  p.text(big, M + P, cardTop + P + 16, 32, f.xbold, rgb(1, 1, 1));
  p.text("INR", M + P + p.width(big, 32, f.xbold) + 6, cardTop + P + 34, 10, f.bold, rgb(0.75, 0.74, 0.7));
  // Payment pill
  const pillY = cardTop + P + 60;
  const pw = p.width(payText, 9.5, f.xbold) + 30;
  p.roundRect(M + P, pillY, pw, 20, 10, C.yellow);
  p.tick(M + P + 9, pillY + 5, 9, C.ink);
  p.text(payText, M + P + 22, pillY + 5.5, 9.5, f.xbold, C.ink);
  const incl = "Prices include GST · No extra tax";
  const iw = p.width(incl, 8.5, f.bold) + 28;
  p.roundRect(M + P, pillY + 25, iw, 17, 8.5, undefined, rgb(0.6, 0.6, 0.58), 0.8);
  p.tick(M + P + 8, pillY + 29, 8, rgb(1, 1, 1));
  p.text(incl, M + P + 20, pillY + 29.5, 8.5, f.bold, rgb(0.92, 0.92, 0.9));
  y = cardTop + cardH + 12;

  // Bill details
  {
    const top = y;
    const fields: [string, string][] = [
      ["CUSTOMER NAME", doc.customerName || "—"],
      ["VEHICLE", doc.vehicle || "—"],
      ["REGISTRATION NO.", doc.regNo || "—"],
      ["BOOKING NO.", doc.bookingRef],
      ["SERVICE DATE", doc.serviceDate || "—"],
      doc.garage ? ["GARAGE", doc.garage] : ["PHONE", doc.customerPhone || "—"],
    ];
    const colW = (CW - P * 2 - 14) / 2;
    const measure = (draw: boolean) => {
      let cy = top + P;
      if (draw) p.text("Bill details", M + P, cy, 12, f.xbold, C.ink);
      cy += 22;
      for (let i = 0; i < fields.length; i += 2) {
        let rowH = 0;
        for (let j = 0; j < 2 && i + j < fields.length; j++) {
          const [k, v] = fields[i + j];
          const x = M + P + j * (colW + 14);
          if (draw) p.text(k, x, cy, 7.5, f.xbold, C.faint, 0.6);
          const hv = draw
            ? p.wrap(v, x, cy + 11, colW, 10.5, f.bold, C.ink)
            : measureWrap(p, v, colW, 10.5, f.bold);
          rowH = Math.max(rowH, 11 + hv);
        }
        cy += rowH + 8;
      }
      return cy - top + P - 8;
    };
    const h = measure(false);
    p.roundRect(M, top, CW, h, 14, C.card);
    measure(true);
    y = top + h + 12;
  }

  // Billed by
  {
    const top = y;
    const measure = (draw: boolean) => {
      let cy = top + P;
      if (draw) p.text("BILLED BY · REPERI.IN", M + P, cy, 7.5, f.xbold, C.faint, 0.6);
      cy += 13;
      if (draw) p.text(SELLER.name, M + P, cy, 12.5, f.xbold, C.ink);
      cy += 17;
      if (draw) p.text(SELLER.tagline, M + P, cy, 9, f.med, C.mut);
      cy += 16;
      const gw = p.width(SELLER.gstin, 10.5, f.xbold) + 20;
      if (draw) {
        p.roundRect(M + P, cy, gw, 34, 9, undefined, C.line, 1);
        p.text("GSTIN", M + P + 10, cy + 6, 7.5, f.xbold, C.faint, 0.6);
        p.text(SELLER.gstin, M + P + 10, cy + 17, 10.5, f.xbold, C.ink);
      }
      cy += 42;
      cy += draw
        ? p.wrap(SELLER.address, M + P, cy, CW - P * 2, 9.5, f.med, C.mut)
        : measureWrap(p, SELLER.address, CW - P * 2, 9.5, f.med);
      cy += 2;
      if (draw) p.text(`Phone: +91 ${SELLER.phone}`, M + P, cy, 9.5, f.med, C.mut);
      cy += 13;
      return cy - top + P - 4;
    };
    const h = measure(false);
    p.roundRect(M, top, CW, h, 14, C.card);
    measure(true);
    y = top + h + 12;
  }

  // Services performed
  {
    const top = y;
    const items = doc.lines.filter((l) => l.amount >= 0);
    const nameW = CW - P * 2 - 40 - 80;
    const measure = (draw: boolean) => {
      let cy = top + P;
      if (draw) {
        p.text("Services performed", M + P, cy, 12, f.xbold, C.ink);
        p.rightText(`${items.length} item${items.length === 1 ? "" : "s"}`, M + CW - P, cy + 2, 9, f.med, C.faint);
      }
      cy += 22;
      for (const l of items) {
        if (draw) p.line(M + P, cy, M + CW - P, C.line, 0.8);
        cy += 9;
        const rowTop = cy;
        let h = draw
          ? p.wrap(l.name, M + P + 40, rowTop, nameW, 11, f.xbold, C.ink)
          : measureWrap(p, l.name, nameW, 11, f.xbold);
        if (l.note) {
          h += draw
            ? p.wrap(l.note, M + P + 40, rowTop + h, nameW, 8.5, f.med, C.faint)
            : measureWrap(p, l.note, nameW, 8.5, f.med);
        }
        if (draw) {
          p.roundRect(M + P, rowTop - 2, 30, 30, 9, C.goldSoft);
          const initial = (l.name.trim()[0] || "•").toUpperCase();
          p.text(initial, M + P + 15 - p.width(initial, 12, f.xbold) / 2, rowTop + 7, 12, f.xbold, C.gold);
          const free = l.free || l.amount === 0;
          if (free) {
            p.rightText("FREE", M + CW - P, rowTop + 1, 12, f.xbold, C.green);
          } else {
            p.rightText(inr(l.amount), M + CW - P, rowTop + 1, 11.5, f.xbold, C.ink);
          }
        }
        cy = rowTop + Math.max(h, 30) + 8;
      }
      return cy - top + P - 8;
    };
    const h = measure(false);
    p.roundRect(M, top, CW, h, 14, C.card);
    measure(true);
    y = top + h + 12;
  }

  // Payment summary
  {
    const top = y;
    const L = M + P, R = M + CW - P;
    const discounts = doc.lines.filter((l) => l.amount < 0);
    const measure = (draw: boolean) => {
      let cy = top + P;
      const row = (k: string, v: string, bold = false, color = C.ink) => {
        if (draw) {
          p.text(k, L, cy, 9.5, f.med, C.mut);
          p.rightText(v, R, cy, 9.5, bold ? f.xbold : f.bold, color);
        }
        cy += 15;
      };
      if (draw) p.text("Payment summary", L, cy, 12, f.xbold, C.ink);
      cy += 22;
      row("Services (incl. GST)", inr(totals.charges, true));
      for (const d of discounts) row(d.name, inr(d.amount, true), false, C.green);
      cy += 4;
      if (draw) p.text("GST already included in the prices", L, cy, 9, f.xbold, C.ink);
      cy += 15;
      for (const g of totals.groups) {
        row(`Taxable value @ ${g.rate}% GST`, inr(g.taxable, true));
        row(`CGST @ ${g.rate / 2}% (included)`, inr(g.cgst, true));
        row(`SGST @ ${g.rate / 2}% (included)`, inr(g.sgst, true));
      }
      if (draw) p.line(L, cy - 2, R, C.line, 0.8, true);
      cy += 3;
      row("Total taxable value", inr(totals.taxable, true));
      cy += 4;
      if (draw) p.line(L, cy, R, C.ink, 1.3);
      cy += 10;
      if (draw) {
        p.text("Total", L, cy, 14, f.xbold, C.ink);
        p.text("Inclusive of GST", L, cy + 18, 8, f.med, C.faint);
        p.rightText(inr(totals.total), R, cy - 2, 22, f.xbold, C.ink);
      }
      cy += 34;
      row("Place of supply", SELLER.placeOfSupply, true);
      return cy - top + P - 6;
    };
    const h = measure(false);
    p.roundRect(M, top, CW, h, 14, C.card);
    measure(true);
    y = top + h + 12;
  }

  // Thank-you note
  {
    const top = y;
    const hasFree = doc.lines.some((l) => l.free || l.amount === 0);
    const msg = hasFree
      ? "Items marked FREE were done at no charge by your garage."
      : "We hope your vehicle feels as good as new.";
    const h = P + 14 + measureWrap(p, msg, CW - P * 2, 9.5, f.med) + P - 2;
    p.roundRect(M, top, CW, h, 14, C.thanks, C.thanksLine, 1);
    p.text("Thank you for choosing REPERI!", M + P, top + P, 10.5, f.xbold, C.ink);
    p.wrap(msg, M + P, top + P + 15, CW - P * 2, 9.5, f.med, C.mut);
    y = top + h + 14;
  }

  // Footer
  const foot = [
    `reperi.in · Operated by ${SELLER.name} · GSTIN ${SELLER.gstin}`,
    `${SELLER.address} · +91 ${SELLER.phone}`,
    doc.replacesNo ? `This bill replaces ${doc.replacesNo}.` : "",
    "Computer-generated invoice — no signature needed.",
  ].filter(Boolean);
  for (const t of foot) {
    const h = measureWrap(p, t, CW, 8, f.med);
    // centred, line by line
    const words = t;
    if (!p.dry) {
      const w = p.width(words, 8, f.med);
      if (w <= CW) p.text(words, M + (CW - w) / 2, y, 8, f.med, C.faint);
      else p.wrap(words, M, y, CW, 8, f.med, C.faint);
    }
    y += h + 2;
  }
  y += M - 4;
  return y;
}

function measureWrap(p: Painter, s: string, maxW: number, size: number, font: PDFFont, lh = 1.3) {
  const dry = new Painter(null, 0, p.f);
  return dry.wrap(s, 0, 0, maxW, size, font, C.ink, lh);
}

function b64(s: string): Uint8Array {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export async function renderInvoicePdf(doc: InvoiceDoc): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  pdf.registerFontkit(fontkit);
  const fonts: Fonts = {
    med: await pdf.embedFont(b64(MANROPE_MEDIUM), { subset: true }),
    bold: await pdf.embedFont(b64(MANROPE_BOLD), { subset: true }),
    xbold: await pdf.embedFont(b64(MANROPE_EXTRABOLD), { subset: true }),
  };
  pdf.setTitle(`Reperi bill ${doc.invoiceNo}`);
  pdf.setAuthor(SELLER.name);
  pdf.setCreator("reperi.in");

  // Pass 1 measures the height, pass 2 draws on a page of exactly that size.
  const H = Math.ceil(layout(new Painter(null, 0, fonts), doc));
  const page = pdf.addPage([W, H]);
  page.drawRectangle({ x: 0, y: 0, width: W, height: H, color: C.page });
  layout(new Painter(page, H, fonts), doc);
  return await pdf.save();
}

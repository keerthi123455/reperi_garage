// Push + email wording for the ₹1 Car Wash code (one-wash function).
// Pure functions — no network — so they're easy to preview and test.

/** ₹1,23,456 — Indian digit grouping, same as the app shows. */
export function rupees(amount: number): string {
  const s = Math.round(amount).toString();
  if (s.length <= 3) return `₹${s}`;
  const last3 = s.slice(-3);
  const rest = s.slice(0, -3).replace(/\B(?=(\d{2})+(?!\d))/g, ",");
  return `₹${rest},${last3}`;
}

function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

export interface Message {
  pushTitle: string;
  pushBody: string;
  subject: string;
  html: string;
  text: string;
}

export interface IssuedInput {
  code: string;
  price: number; // rupees the wash costs with the code
  firstName: string; // "" if unknown
  washes: string; // "Express Wash (car) or Quick Wash (bike)" — "" if unknown
}

export interface RedeemedInput {
  code: string;
  price: number;
  firstName: string;
  bookingId: string | null;
}

// ── Shared email frame (dark + gold, like the app) ─────────────────────
function frame(preheader: string, inner: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark light">
<title>Reperi</title>
</head>
<body style="margin:0;padding:0;background:#0f0f0f;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${esc(preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0f0f0f;">
  <tr><td align="center" style="padding:24px 12px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
           style="max-width:520px;background:#151515;border:1px solid #3a3220;border-radius:16px;">
      <tr><td style="padding:28px 28px 8px 28px;font-family:Arial,Helvetica,sans-serif;">
        <div style="font-size:13px;letter-spacing:4px;font-weight:bold;color:#D4A017;">REPERI</div>
        <div style="height:3px;width:40px;background:#D4A017;margin-top:8px;border-radius:2px;"></div>
      </td></tr>
      ${inner}
      <tr><td style="padding:20px 28px 28px 28px;font-family:Arial,Helvetica,sans-serif;
                     font-size:12px;line-height:18px;color:#8a8a8a;border-top:1px solid #262626;">
        Reperi by Trustkon Technologies ·
        <a href="https://reperi.in" style="color:#D4A017;text-decoration:none;">reperi.in</a>
      </td></tr>
    </table>
  </td></tr>
</table>
</body>
</html>`;
}

function codeBox(code: string): string {
  return `<tr><td align="center" style="padding:20px 28px 4px 28px;">
    <table role="presentation" cellpadding="0" cellspacing="0" border="0"
           style="border:2px dashed #D4A017;border-radius:12px;background:#1d1a12;">
      <tr><td align="center" style="padding:14px 28px;font-family:'Courier New',Courier,monospace;
                     font-size:32px;font-weight:bold;letter-spacing:8px;color:#ffffff;">${esc(code)}</td></tr>
    </table>
    <div style="font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#8a8a8a;padding-top:8px;">Your coupon code</div>
  </td></tr>`;
}

// ── 1. Code issued (first vehicle added) ──────────────────────────────
export function issuedMessage(i: IssuedInput): Message {
  const price = rupees(i.price);
  // The customer-facing line, exactly as specified.
  const headline = `Congratulations you have unlocked the ${price} Car wash on your next booking with us`;
  const hi = i.firstName ? `Hi ${i.firstName},` : "Hi,";
  const what = i.washes ? `Book ${i.washes}` : "Book a wash";

  const inner = `
      <tr><td style="padding:16px 28px 0 28px;font-family:Arial,Helvetica,sans-serif;color:#e8e8e8;">
        <div style="font-size:15px;line-height:22px;color:#bdbdbd;">${esc(hi)}</div>
        <div style="font-size:24px;line-height:32px;font-weight:bold;color:#ffffff;padding-top:10px;">
          ${esc(headline)} 🎉
        </div>
      </td></tr>
      ${codeBox(i.code)}
      <tr><td style="padding:16px 28px 4px 28px;font-family:Arial,Helvetica,sans-serif;
                     font-size:14px;line-height:22px;color:#d6d6d6;">
        <div style="font-weight:bold;color:#D4A017;padding-bottom:6px;">How to use it</div>
        1. Open the Reperi app and ${esc(what.charAt(0).toLowerCase() + what.slice(1))}.<br>
        2. On the payment screen, tap <b>Apply coupon</b> and enter <b>${esc(i.code)}</b>.<br>
        3. Your wash costs just <b>${esc(price)}</b>.
      </td></tr>
      <tr><td style="padding:8px 28px 8px 28px;font-family:Arial,Helvetica,sans-serif;
                     font-size:12px;line-height:18px;color:#8a8a8a;">
        This code works only on your Reperi account and can be used once.
      </td></tr>`;

  const text = [
    hi,
    "",
    `${headline}!`,
    "",
    `Your coupon code: ${i.code}`,
    "",
    "How to use it:",
    `1. Open the Reperi app and ${what.charAt(0).toLowerCase() + what.slice(1)}.`,
    `2. On the payment screen, tap "Apply coupon" and enter ${i.code}.`,
    `3. Your wash costs just ${price}.`,
    "",
    "This code works only on your Reperi account and can be used once.",
    "",
    "Reperi by Trustkon Technologies · https://reperi.in",
  ].join("\n");

  return {
    pushTitle: `${price} Car Wash unlocked 🎉`,
    pushBody: `${headline}. Use code ${i.code} at checkout.`,
    subject: `Congratulations! You've unlocked the ${price} Car Wash 🎉`,
    html: frame(`${headline}. Your code: ${i.code}`, inner),
    text,
  };
}

// ── 2. Code used on a booking ──────────────────────────────────────────
export function redeemedMessage(r: RedeemedInput): Message {
  const price = rupees(r.price);
  const hi = r.firstName ? `Hi ${r.firstName},` : "Hi,";
  const line = `Code ${r.code} has been applied and your ${price} Car wash has been added to your bookings.`;
  const ref = r.bookingId ? `Booking ref: #${r.bookingId}` : "";

  const inner = `
      <tr><td style="padding:16px 28px 0 28px;font-family:Arial,Helvetica,sans-serif;color:#e8e8e8;">
        <div style="font-size:15px;line-height:22px;color:#bdbdbd;">${esc(hi)}</div>
        <div style="font-size:24px;line-height:32px;font-weight:bold;color:#ffffff;padding-top:10px;">
          Your ${esc(price)} Car Wash is booked ✅
        </div>
        <div style="font-size:15px;line-height:23px;color:#d6d6d6;padding-top:12px;">${esc(line)}</div>
        <div style="font-size:15px;line-height:23px;color:#d6d6d6;padding-top:8px;">
          You can track it under your bookings in the Reperi app.
        </div>
        ${ref ? `<div style="font-size:13px;color:#8a8a8a;padding-top:12px;">${esc(ref)}</div>` : ""}
        <div style="height:16px;line-height:16px;">&nbsp;</div>
      </td></tr>`;

  const text = [
    hi,
    "",
    `Your ${price} Car Wash is booked.`,
    "",
    line,
    "You can track it under your bookings in the Reperi app.",
    ...(ref ? ["", ref] : []),
    "",
    "Reperi by Trustkon Technologies · https://reperi.in",
  ].join("\n");

  return {
    pushTitle: `${price} Car Wash booked ✅`,
    pushBody: `Code ${r.code} applied — your ${price} Car wash has been added to your bookings.`,
    subject: `Your ${price} Car Wash is booked ✅`,
    html: frame(line, inner),
    text,
  };
}

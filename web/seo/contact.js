/* Reperi contact numbers — set in the CRM ("Contact numbers" tab).
 * The pages ship with fallback numbers in the HTML (so they work without
 * JavaScript and Google sees a number); this swaps in whatever the CRM
 * says, from the public app_settings rows contact_phone / contact_whatsapp.
 * Only links marked data-track="call|whatsapp" or data-contact="call|whatsapp"
 * are touched, plus any [data-phone-text] label.
 */
(function () {
  var SUPABASE_URL = "https://rmvxqjyoqfinbrpubsvp.supabase.co";
  // Public anon key (same one the app ships with) — read-only, RLS-limited.
  var ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtdnhxanlvcWZpbmJycHVic3ZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcyMzQyNDcsImV4cCI6MjA5MjgxMDI0N30.NAxb2XnicLSaBoA4kpTFmmutT68Z2ksu-T-P_NUxy5E";
  var CACHE = "reperi_contact_v1";

  function digits(v) { return String(v == null ? "" : v).replace(/\D/g, ""); }
  function intl(v) {
    var d = digits(v);
    if (d.length === 11 && d.charAt(0) === "0") d = d.slice(1);
    if (d.length === 10) d = "91" + d;
    return d.length >= 11 ? d : "";
  }
  function pretty(d) {
    return d.length === 12 && d.indexOf("91") === 0 ? "+91 " + d.slice(2, 7) + " " + d.slice(7) : "+" + d;
  }

  function apply(c) {
    var phone = intl(c.contact_phone), wa = intl(c.contact_whatsapp);
    if (phone) {
      document.querySelectorAll('a[data-track="call"], a[data-contact="call"]').forEach(function (a) {
        a.setAttribute("href", "tel:+" + phone);
      });
      document.querySelectorAll("[data-phone-text]").forEach(function (el) { el.textContent = pretty(phone); });
    }
    if (wa) {
      document.querySelectorAll('a[data-track="whatsapp"], a[data-contact="whatsapp"]').forEach(function (a) {
        var h = a.getAttribute("href") || "";
        a.setAttribute("href", /wa\.me\/\d+/.test(h) ? h.replace(/wa\.me\/\d+/, "wa.me/" + wa) : "https://wa.me/" + wa);
      });
    }
  }

  function run() {
    try { var cached = JSON.parse(sessionStorage.getItem(CACHE) || "null"); if (cached) apply(cached); } catch (e) {}
    fetch(SUPABASE_URL + "/rest/v1/app_settings?select=key,value&key=in.(contact_phone,contact_whatsapp)", {
      headers: { apikey: ANON_KEY, Authorization: "Bearer " + ANON_KEY },
    })
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (rows) {
        var c = {};
        (rows || []).forEach(function (r) { c[r.key] = r.value; });
        if (!c.contact_phone && !c.contact_whatsapp) return;
        apply(c);
        try { sessionStorage.setItem(CACHE, JSON.stringify(c)); } catch (e) {}
      })
      .catch(function () { /* keep the numbers already in the page */ });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run);
  else run();
})();

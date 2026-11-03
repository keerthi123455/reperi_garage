/* Reperi live prices — set in the CRM ("Prices" tab, Supabase services).
 * Pages ship with the prices from the last build (for Google and as a
 * fallback); this replaces them with the current ones on load, so a price
 * change in the CRM shows on reperi.in without rebuilding anything.
 *   [data-price-key="svc_essential"]      one package's price
 *   [data-from-keys="a,b,c"]              lowest price among those packages
 *   <meta name="reperi:title-from">       same, for the "from ₹…" in the title
 */
(function () {
  var SUPABASE_URL = "https://rmvxqjyoqfinbrpubsvp.supabase.co";
  var ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJtdnhxanlvcWZpbmJycHVic3ZwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcyMzQyNDcsImV4cCI6MjA5MjgxMDI0N30.NAxb2XnicLSaBoA4kpTFmmutT68Z2ksu-T-P_NUxy5E"; // public, read-only
  var CACHE = "reperi_prices_v1";

  function rupees(n) { return "₹" + Number(n).toLocaleString("en-IN", { maximumFractionDigits: 0 }); }
  function splitKeys(v) { return String(v || "").split(",").map(function (k) { return k.trim(); }).filter(Boolean); }
  function lowest(keys, prices) {
    var best = null;
    keys.forEach(function (k) { var p = prices[k]; if (typeof p === "number" && p > 0 && (best === null || p < best)) best = p; });
    return best;
  }

  function apply(prices) {
    document.querySelectorAll("[data-price-key]").forEach(function (el) {
      var k = el.getAttribute("data-price-key");
      if (!(k in prices)) return;
      el.textContent = typeof prices[k] === "number" ? rupees(prices[k]) : "Get a quote";
    });
    document.querySelectorAll("[data-from-keys]").forEach(function (el) {
      var p = lowest(splitKeys(el.getAttribute("data-from-keys")), prices);
      if (p !== null) el.textContent = rupees(p);
    });
    var meta = document.querySelector('meta[name="reperi:title-from"]');
    if (meta) {
      var p = lowest(splitKeys(meta.getAttribute("content")), prices);
      if (p !== null) document.title = document.title.replace(/₹[\d,]+/, rupees(p));
    }
  }

  function run() {
    var keys = {};
    document.querySelectorAll("[data-price-key]").forEach(function (el) { keys[el.getAttribute("data-price-key")] = 1; });
    document.querySelectorAll("[data-from-keys]").forEach(function (el) { splitKeys(el.getAttribute("data-from-keys")).forEach(function (k) { keys[k] = 1; }); });
    var list = Object.keys(keys).filter(function (k) { return /^[a-z0-9_]+$/.test(k); });
    if (!list.length) return;
    try { var cached = JSON.parse(sessionStorage.getItem(CACHE) || "null"); if (cached) apply(cached); } catch (e) {}
    fetch(SUPABASE_URL + "/rest/v1/services?select=key,price&key=in.(" + list.join(",") + ")", {
      headers: { apikey: ANON_KEY, Authorization: "Bearer " + ANON_KEY },
    })
      .then(function (r) { return r.ok ? r.json() : []; })
      .then(function (rows) {
        if (!rows || !rows.length) return;
        var prices = {};
        rows.forEach(function (r) { prices[r.key] = r.price == null ? null : Number(r.price); });
        apply(prices);
        try {
          var all = JSON.parse(sessionStorage.getItem(CACHE) || "{}") || {};
          Object.keys(prices).forEach(function (k) { all[k] = prices[k]; });
          sessionStorage.setItem(CACHE, JSON.stringify(all));
        } catch (e) {}
      })
      .catch(function () { /* keep the prices already in the page */ });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run);
  else run();
})();

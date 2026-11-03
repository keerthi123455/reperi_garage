/* Reperi tracking — paste your IDs here (empty = that tool is off).
 *   GA4_ID              Google Analytics 4  → "G-XXXXXXXXXX"
 *   GOOGLE_ADS_ID       Google Ads tag      → "AW-XXXXXXXXXX"
 *   GOOGLE_ADS_LEAD     conversion label for WhatsApp / Call / Book taps
 *                       → "AW-XXXXXXXXXX/AbCdEfGhIjk"
 *   META_PIXEL_ID       Meta (Facebook/Instagram) Pixel → "1234567890123456"
 * Used on every SEO page and on the app's index.html.
 */
window.REPERI_TRACKING = {
  GA4_ID: "G-PZ2KDWSG0P", // GA4 "Reperi website" stream
  GOOGLE_ADS_ID: "AW-18552640139", // Google Ads tag
  GOOGLE_ADS_LEAD: "AW-18552640139/gz0FCPel9bAdEIuly45F", // "Lead - WhatsApp / Call / Book"
  META_PIXEL_ID: "1714040313717368", // "Reperi website" dataset
};

(function () {
  var c = window.REPERI_TRACKING || {};

  // Google tag (GA4 + Google Ads share one gtag.js)
  var gId = c.GA4_ID || c.GOOGLE_ADS_ID;
  if (gId) {
    var s = document.createElement("script");
    s.async = true;
    s.src = "https://www.googletagmanager.com/gtag/js?id=" + gId;
    document.head.appendChild(s);
    window.dataLayer = window.dataLayer || [];
    window.gtag = function () { window.dataLayer.push(arguments); };
    gtag("js", new Date());
    if (c.GA4_ID) gtag("config", c.GA4_ID);
    if (c.GOOGLE_ADS_ID) gtag("config", c.GOOGLE_ADS_ID);
  }

  // Meta Pixel
  if (c.META_PIXEL_ID) {
    !function (f, b, e, v, n, t, s) {
      if (f.fbq) return; n = f.fbq = function () { n.callMethod ? n.callMethod.apply(n, arguments) : n.queue.push(arguments); };
      if (!f._fbq) f._fbq = n; n.push = n; n.loaded = !0; n.version = "2.0"; n.queue = [];
      t = b.createElement(e); t.async = !0; t.src = v; s = b.getElementsByTagName(e)[0]; s.parentNode.insertBefore(t, s);
    }(window, document, "script", "https://connect.facebook.net/en_US/fbevents.js");
    fbq("init", c.META_PIXEL_ID);
    fbq("track", "PageView");
  }

  // Every WhatsApp / Call / Book tap counts as a lead.
  document.addEventListener("click", function (e) {
    var a = e.target.closest && e.target.closest("[data-track]");
    if (!a) return;
    var kind = a.getAttribute("data-track"); // whatsapp | call | book
    var page = location.pathname;
    if (window.gtag) {
      gtag("event", kind === "book" ? "generate_lead" : "contact", { method: kind, page_path: page });
      if (c.GOOGLE_ADS_LEAD) gtag("event", "conversion", { send_to: c.GOOGLE_ADS_LEAD });
    }
    if (window.fbq) fbq("track", kind === "book" ? "Lead" : "Contact", { content_name: kind, page: page });
  }, true);
})();

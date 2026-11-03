#!/usr/bin/env python3
"""Builds Reperi's SEO pages + Google Ads files.

    python3 seo/build.py

Writes (inside web/, so `flutter build web` copies them to the site):
  web/<slug>/index.html      one landing page per service group (seo/pages.py)
  web/services/index.html    hub listing every service
  web/sitemap.xml, web/robots.txt
And for Google Ads Editor (not published):
  seo/ads/google_ads_keywords.csv, google_ads_ads.csv, google_ads_negatives.csv

Prices come from the live Supabase `services` table when this machine can
reach it, otherwise from the repo's SQL. Re-run after changing prices.
"""
import csv
import datetime as dt
import html
import json
import sys
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalog  # noqa: E402
from pages import PAGES  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "web"
ADS = ROOT / "seo" / "ads"

# ── Business details (edit here) ────────────────────────────────────────
SITE = "https://reperi.in"
BRAND = "Reperi"
COMPANY = "Trustkon Technologies LLP"
CITY = "Bengaluru"
PHONE = "+919180605225"          # fallback; live number comes from the CRM (Contact numbers)
PHONE_DISPLAY = "+91 91806 05225"
WHATSAPP = "919353094672"        # fallback; live number comes from the CRM
EMAIL = "admin@trustkon.com"
PLAY_URL = "https://play.google.com/store/apps/details?id=com.reperi.autocare.app"
APP_STORE_URL = ""               # paste the App Store link to show the iPhone button
BOOK_URL = "/"                   # the Reperi web app
LOGO = "/seo/reperi-logo-512.png"
OG_IMAGE = "/seo/og-reperi.png"

TODAY = dt.date.today().isoformat()
esc = html.escape


def rupees(n):
    s = str(int(round(n)))
    if len(s) <= 3:
        return f"₹{s}"
    head, tail = s[:-3], s[-3:]
    groups = []
    while len(head) > 2:
        groups.insert(0, head[-2:])
        head = head[:-2]
    if head:
        groups.insert(0, head)
    return "₹" + ",".join(groups) + "," + tail


def wa_link(text):
    return f"https://wa.me/{WHATSAPP}?text={quote(text)}"


def packages_for(page, cat):
    out = []
    for k in page["keys"]:
        s = cat.get(k)
        if not s or s.get("active") is False:
            continue
        out.append(s)
    return out


def page_price(page, cat):
    """Starting price for the page's title / ads ("price_keys" if set)."""
    keys = page.get("price_keys") or page["keys"]
    return from_price(packages_for({"keys": keys}, cat))


def from_keys(page, cat):
    """Keys whose lowest live price is the page's "From" price (prices.js)."""
    keys = [k for k in (page.get("price_keys") or page["keys"]) if k in cat and cat[k].get("active") is not False]
    main = [k for k in keys if not cat[k].get("is_addon") and cat[k].get("price")]
    return ",".join(main or [k for k in keys if cat[k].get("price")])


def from_price(pkgs):
    main = [p["price"] for p in pkgs if p.get("price") and not p.get("is_addon")]
    anyp = [p["price"] for p in pkgs if p.get("price")]
    vals = main or anyp
    return min(vals) if vals else None


def fill(text, price):
    return text.replace("{from}", rupees(price) if price else "")


# ── Shared HTML pieces ──────────────────────────────────────────────────
def head(title, description, path, extra_ld, title_keys=""):
    url = SITE + path
    ld = {
        "@context": "https://schema.org",
        "@graph": [
            {
                "@type": "Organization",
                "@id": f"{SITE}/#org",
                "name": BRAND,
                "alternateName": ["Reperi Car Care", "Reperi by Trustkon"],
                "url": SITE + "/",
                "logo": SITE + LOGO,
                "email": EMAIL,
                "telephone": PHONE,
                "parentOrganization": {"@type": "Organization", "name": COMPANY},
                "contactPoint": {
                    "@type": "ContactPoint",
                    "telephone": PHONE,
                    "contactType": "customer service",
                    "areaServed": "IN",
                },
            },
            {"@type": "WebSite", "@id": f"{SITE}/#website", "url": SITE + "/", "name": BRAND, "publisher": {"@id": f"{SITE}/#org"}},
            *extra_ld,
        ],
    }
    return f"""<!doctype html>
<html lang="en-IN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)}</title>
<meta name="description" content="{esc(description)}">
<link rel="canonical" href="{url}">
<meta name="theme-color" content="#FDF003">
<link rel="icon" href="/favicon-48.png?v=3" sizes="48x48" type="image/png">
<link rel="icon" href="/favicon-192.png?v=3" sizes="192x192" type="image/png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png?v=3">
<meta property="og:type" content="website">
<meta property="og:site_name" content="{BRAND}">
<meta property="og:title" content="{esc(title)}">
<meta property="og:description" content="{esc(description)}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{SITE}{OG_IMAGE}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:locale" content="en_IN">
<meta name="twitter:card" content="summary_large_image">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@500;700;800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/seo/site.css?v=1">
<script type="application/ld+json">{json.dumps(ld, ensure_ascii=False)}</script>
<script src="/seo/track.js?v=1" defer></script>
<script src="/seo/contact.js?v=1" defer></script>
<script src="/seo/prices.js?v=1" defer></script>
{f'<meta name="reperi:title-from" content="{title_keys}">' if title_keys else ""}
</head>
<body>
<header class="top">
  <a class="brand" href="/services/" aria-label="Reperi — all services">
    <img src="/icons/Icon-192.png" width="40" height="40" alt="Reperi logo — blue spanner on yellow">
    <span>REPERI</span>
  </a>
  <nav>
    <a href="/services/">All services</a>
    <a class="btn btn-navy btn-sm" href="{BOOK_URL}" data-track="book">Book now</a>
  </nav>
</header>
"""


def footer(service_name=None):
    wa_text = f"Hi Reperi, I'd like to book {service_name}." if service_name else "Hi Reperi, I'd like to book a service."
    ios = f'<a href="{APP_STORE_URL}" data-track="book">App Store</a>' if APP_STORE_URL else ""
    return f"""
<footer class="foot">
  <div class="wrap foot-grid">
    <div>
      <div class="brand foot-brand"><img src="/icons/Icon-192.png" width="36" height="36" alt=""><span>REPERI</span></div>
      <p>Car and bike care at your doorstep in {CITY}.<br>Reperi™ is a brand of {COMPANY}.</p>
    </div>
    <div>
      <b>Contact</b>
      <a href="tel:{PHONE}" data-track="call"><span data-phone-text>{PHONE_DISPLAY}</span></a>
      <a href="{wa_link(wa_text)}" data-track="whatsapp">WhatsApp us</a>
      <a href="mailto:{EMAIL}">{EMAIL}</a>
    </div>
    <div>
      <b>Get the app</b>
      <a href="{PLAY_URL}" data-track="book">Google Play</a>{ios}
      <a href="{BOOK_URL}" data-track="book">Book online</a>
    </div>
    <div>
      <b>Company</b>
      <a href="/services/">All services</a>
      <a href="/service-partners.html">Partner with us</a>
      <a href="/support.html">Support</a>
      <a href="/privacy-policy.html">Privacy</a>
      <a href="/terms.html">Terms</a>
    </div>
  </div>
  <p class="wrap copy">© {dt.date.today().year} {COMPANY}. All rights reserved.</p>
</footer>
<div class="sticky">
  <a class="btn btn-wa" href="{wa_link(wa_text)}" data-track="whatsapp">WhatsApp</a>
  <a class="btn btn-ghost" href="tel:{PHONE}" data-track="call">Call</a>
  <a class="btn btn-navy" href="{BOOK_URL}" data-track="book">Book now</a>
</div>
</body>
</html>
"""


def card(p):
    price = rupees(p["price"]) if p.get("price") else (p.get("price_label") or "Get a quote")
    suffix = (p.get("details") or {}).get("price_suffix", "")
    feats = [f for f in (p.get("features") or []) if isinstance(f, str)]
    shown, more = feats[:5], len(feats) - 5
    lis = "".join(f"<li>{esc(f)}</li>" for f in shown)
    if more > 0:
        lis += f'<li class="more">+ {more} more</li>'
    meta = " · ".join(x for x in [p.get("duration") or "", "Add-on" if p.get("is_addon") else ""] if x)
    tag = p.get("tagline") or p.get("description") or ""
    return f"""<article class="pkg">
  <h3>{esc(p['name'])}</h3>
  <p class="price"><span data-price-key="{esc(p['key'])}">{esc(price)}</span><small>{esc(suffix)}</small></p>
  {f'<p class="meta">{esc(meta)}</p>' if meta else ''}
  {f'<p class="tag">{esc(tag)}</p>' if tag else ''}
  <ul>{lis}</ul>
</article>"""


def build_page(page, cat, by_slug):
    pkgs = packages_for(page, cat)
    price = page_price(page, cat)
    path = f"/{page['slug']}/"
    title = fill(page["title"], price).replace(" —  |", " |")
    desc = page["description"]
    prices = [p["price"] for p in pkgs if p.get("price")]
    service_ld = {
        "@type": "Service",
        "@id": f"{SITE}{path}#service",
        "name": page["h1"],
        "serviceType": page["nav"],
        "provider": {"@id": f"{SITE}/#org"},
        "areaServed": {"@type": "City", "name": CITY},
        "url": SITE + path,
        "description": desc,
    }
    if prices:
        service_ld["offers"] = {
            "@type": "AggregateOffer",
            "priceCurrency": "INR",
            "lowPrice": min(prices),
            "highPrice": max(prices),
            "offerCount": len(prices),
        }
    crumbs = {
        "@type": "BreadcrumbList",
        "itemListElement": [
            {"@type": "ListItem", "position": 1, "name": "Reperi", "item": SITE + "/"},
            {"@type": "ListItem", "position": 2, "name": "Services", "item": SITE + "/services/"},
            {"@type": "ListItem", "position": 3, "name": page["nav"], "item": SITE + path},
        ],
    }
    faq_html = "".join(
        f"<details><summary>{esc(q)}</summary><p>{esc(a)}</p></details>" for q, a in page["faqs"]
    )
    related = "".join(
        f'<a class="rel" href="/{s}/">{esc(by_slug[s]["nav"])}<span>›</span></a>'
        for s in page["related"] if s in by_slug
    )
    wa_text = f"Hi Reperi, I'd like to book {page['nav']}."
    fk = from_keys(page, cat)
    from_html = (f'<p class="from">From <b data-from-keys="{fk}">{rupees(price)}</b></p>'
                 if price else '<p class="from"><b>Custom quote</b></p>')
    body = f"""
<main>
<section class="hero">
  <div class="wrap">
    <nav class="crumbs"><a href="/services/">Services</a> › {esc(page['nav'])}</nav>
    <h1>{esc(page['h1'])}</h1>
    <p class="lead">{esc(page['lead'])}</p>
    {from_html}
    <div class="ctas">
      <a class="btn btn-navy" href="{BOOK_URL}" data-track="book">Book now</a>
      <a class="btn btn-wa" href="{wa_link(wa_text)}" data-track="whatsapp">WhatsApp us</a>
      <a class="btn btn-ghost" href="tel:{PHONE}" data-track="call">Call <span data-phone-text>{PHONE_DISPLAY}</span></a>
    </div>
    <ul class="trust">
      <li>Upfront prices</li><li>Doorstep or pickup &amp; drop</li><li>You approve every extra</li><li>Live updates in the app</li>
    </ul>
  </div>
</section>

<section class="wrap block">
  <h2>Packages &amp; prices</h2>
  <div class="grid">{''.join(card(p) for p in pkgs)}</div>
  <p class="note">Prices in {CITY}. Final price for your vehicle is shown in the app before you pay.</p>
</section>

<section class="wrap block">
  <h2>How it works</h2>
  <ol class="steps">
    <li><b>Book in a minute</b><span>Pick the package and a time slot in the Reperi app or on reperi.in.</span></li>
    <li><b>We come to you</b><span>Our team comes to your parking spot or picks up the vehicle, as the service needs.</span></li>
    <li><b>Done, with proof</b><span>Updates, photos and the bill land in the app. Extras happen only if you approve them.</span></li>
  </ol>
</section>

<section class="wrap block">
  <h2>Questions people ask</h2>
  <div class="faq">{faq_html}</div>
</section>

<section class="wrap block">
  <h2>More from Reperi</h2>
  <div class="rels">{related}<a class="rel" href="/services/">All services<span>›</span></a></div>
</section>

<section class="cta-band">
  <div class="wrap">
    <h2>Ready when you are</h2>
    <p>Book {esc(page['nav'].lower())} in {CITY} with Reperi.</p>
    <div class="ctas">
      <a class="btn btn-navy" href="{BOOK_URL}" data-track="book">Book now</a>
      <a class="btn btn-wa" href="{wa_link(wa_text)}" data-track="whatsapp">WhatsApp us</a>
    </div>
  </div>
</section>
</main>
"""
    out = WEB / page["slug"] / "index.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    tk = fk if price and "{from}" in page["title"] else ""
    out.write_text(head(title, desc, path, [service_ld, crumbs], tk) + body + footer(page["nav"].lower()))
    return price, len(pkgs)


def build_hub(cat):
    groups = [
        ("Servicing & repairs", ["car-service-at-home-bengaluru", "car-ac-service-bengaluru", "car-engine-diagnostics-obd-scan-bengaluru", "wheel-alignment-balancing-bengaluru", "car-headlight-bulb-replacement-bengaluru", "car-dent-scratch-repair-bengaluru"]),
        ("Inspection & expert help", ["doorstep-car-inspection-bengaluru", "second-opinion-car-repair-bengaluru", "vehicle-health-check-used-car-inspection-bengaluru", "roadside-assistance-bengaluru"]),
        ("Washing & detailing", ["car-wash-at-home-bengaluru", "monthly-car-wash-subscription-bengaluru", "car-detailing-polishing-bengaluru", "ceramic-coating-bengaluru", "ppf-paint-protection-film-bengaluru"]),
        ("Bikes & scooters", ["bike-service-at-home-bengaluru", "bike-wash-at-home-bengaluru"]),
        ("Paperwork & business", ["car-insurance-claim-assistance-bengaluru", "pollution-check-puc-bengaluru", "fleet-maintenance-bengaluru"]),
    ]
    by_slug = {p["slug"]: p for p in PAGES}
    sections = []
    for title, slugs in groups:
        tiles = []
        for s in slugs:
            p = by_slug[s]
            price = page_price(p, cat)
            tiles.append(
                f'<a class="tile" href="/{s}/"><b>{esc(p["nav"])}</b>'
                + (f'<span>From <span data-from-keys="{from_keys(p, cat)}">{rupees(price)}</span></span></a>'
                 if price else '<span>Custom quote</span></a>')
            )
        sections.append(f'<section class="wrap block"><h2>{esc(title)}</h2><div class="tiles">{"".join(tiles)}</div></section>')
    missing = set(by_slug) - {s for _, ss in groups for s in ss}
    assert not missing, f"add these to a hub group: {missing}"
    ld = {
        "@type": "ItemList",
        "itemListElement": [
            {"@type": "ListItem", "position": i + 1, "url": f"{SITE}/{p['slug']}/", "name": p["nav"]}
            for i, p in enumerate(PAGES)
        ],
    }
    body = f"""
<main>
<section class="hero">
  <div class="wrap">
    <h1>Car &amp; bike care at your doorstep in {CITY}</h1>
    <p class="lead">Servicing, washing, detailing, inspections, roadside help and more — booked in one app, with upfront prices and live updates.</p>
    <div class="ctas">
      <a class="btn btn-navy" href="{BOOK_URL}" data-track="book">Book now</a>
      <a class="btn btn-wa" href="{wa_link("Hi Reperi, I'd like to book a service.")}" data-track="whatsapp">WhatsApp us</a>
      <a class="btn btn-ghost" href="{PLAY_URL}" data-track="book">Get the app</a>
    </div>
  </div>
</section>
{''.join(sections)}
</main>
"""
    out = WEB / "services" / "index.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        head(f"All Services — Car & Bike Care at Home in {CITY} | Reperi",
             f"Every Reperi service in {CITY}: car service, AC, wash, monthly wash, detailing, ceramic coating, PPF, dent repair, inspections, roadside help, bike service and more.",
             "/services/", [ld])
        + body + footer()
    )


def build_sitemap():
    urls = ["/", "/services/"] + [f"/{p['slug']}/" for p in PAGES] + [
        "/service-partners.html", "/support.html", "/privacy-policy.html", "/terms.html",
    ]
    items = "".join(f"  <url><loc>{SITE}{u}</loc><lastmod>{TODAY}</lastmod></url>\n" for u in urls)
    (WEB / "sitemap.xml").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + items + "</urlset>\n"
    )
    (WEB / "robots.txt").write_text(
        "# Reperi — reperi.in\n"
        "# Staff dashboards are kept out of Google with an X-Robots-Tag: noindex\n"
        "# header (see _headers), so they stay crawlable here on purpose.\n"
        "User-agent: *\nAllow: /\n\n"
        f"Sitemap: {SITE}/sitemap.xml\n"
    )


# ── Google Ads Editor files ─────────────────────────────────────────────
NEGATIVES = [
    "job", "jobs", "salary", "vacancy", "hiring", "course", "training", "institute", "diploma",
    "free", "diy", "how to", "youtube", "video", "pdf", "manual", "toy", "games", "kit",
    "second hand parts", "scrap", "olx", "quikr", "spare parts wholesale", "franchise",
    "bus", "truck", "lorry", "tractor", "helicopter",
]
BRAND_KEYWORDS = ["[reperi]", "reperi app", "reperi car", "reperi bangalore", "reperi.in", "[trustkon]"]
BRAND_AD = {
    "headlines": ["Reperi — Official Site", "Reperi Car & Bike Care", "Book on the Reperi App", "Doorstep Service, Bengaluru", "Car Service, Wash & More", "Upfront Prices", "Live Updates in the App", "Pickup & Drop Available"],
    "descriptions": ["Official Reperi site. Car & bike service, wash, detailing and roadside help.", "Book in a minute. Upfront prices and every extra approved by you first.", "Reperi is a brand of Trustkon Technologies LLP, Bengaluru.", "Doorstep or pickup & drop across Bengaluru. Download the Reperi app."],
}


def kw_row(campaign, group, kw, url):
    if kw.startswith("[") and kw.endswith("]"):
        return [campaign, group, kw[1:-1], "Exact", url]
    return [campaign, group, kw, "Phrase", url]


def check_ad(group, ad, price):
    problems = []
    hs = [fill(h, price) for h in ad["headlines"]][:15]
    ds = [fill(d, price) for d in ad["descriptions"]][:4]
    for h in hs:
        if len(h) > 30:
            problems.append(f"{group}: headline too long ({len(h)}): {h}")
    for d in ds:
        if len(d) > 90:
            problems.append(f"{group}: description too long ({len(d)}): {d}")
    if len(hs) < 3 or len(ds) < 2:
        problems.append(f"{group}: needs ≥3 headlines and ≥2 descriptions")
    return hs, ds, problems


def build_ads(cat):
    ADS.mkdir(parents=True, exist_ok=True)
    services_c, brand_c = "Reperi | Search | Services", "Reperi | Search | Brand"
    kw_rows, ad_rows, problems = [], [], []
    for p in PAGES:
        price = page_price(p, cat)
        url = f"{SITE}/{p['slug']}/"
        group = p["nav"]
        for kw in p["keywords"]:
            kw_rows.append(kw_row(services_c, group, kw, url))
        hs, ds, pr = check_ad(group, p["ads"], price)
        problems += pr
        ad_rows.append([services_c, group, "Responsive search ad", url, "services", p["slug"].split("-")[0]]
                       + hs + [""] * (15 - len(hs)) + ds + [""] * (4 - len(ds)))
    for kw in BRAND_KEYWORDS:
        kw_rows.append(kw_row(brand_c, "Brand", kw, f"{SITE}/services/"))
    hs, ds, pr = check_ad("Brand", BRAND_AD, None)
    problems += pr
    ad_rows.append([brand_c, "Brand", "Responsive search ad", f"{SITE}/services/", "services", "reperi"]
                   + hs + [""] * (15 - len(hs)) + ds + [""] * (4 - len(ds)))

    with open(ADS / "google_ads_keywords.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Campaign", "Ad group", "Keyword", "Criterion Type", "Final URL"])
        w.writerows(kw_rows)
    with open(ADS / "google_ads_ads.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Campaign", "Ad group", "Ad type", "Final URL", "Path 1", "Path 2"]
                   + [f"Headline {i}" for i in range(1, 16)] + [f"Description {i}" for i in range(1, 5)])
        w.writerows(ad_rows)
    with open(ADS / "google_ads_negatives.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Campaign", "Keyword", "Criterion Type"])
        for n in NEGATIVES:
            w.writerow([services_c, n, "Campaign Negative Phrase"])
    return len(kw_rows), len(ad_rows), problems


def main():
    cat = catalog.load()
    by_slug = {p["slug"]: p for p in PAGES}
    print(f"catalog: {len(cat)} services")
    for page in PAGES:
        price, n = build_page(page, cat, by_slug)
        missing = [k for k in page["keys"] if k not in cat]
        print(f"  /{page['slug']}/  {n} packages, from {rupees(price) if price else '—'}"
              + (f"  (missing: {missing})" if missing else ""))
    build_hub(cat)
    build_sitemap()
    kws, ads, problems = build_ads(cat)
    print(f"ads: {kws} keywords, {ads} responsive search ads")
    for pr in problems:
        print("  ! " + pr)
    if problems:
        sys.exit(1)


if __name__ == "__main__":
    main()

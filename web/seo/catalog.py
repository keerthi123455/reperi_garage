"""Reads Reperi's service catalog.

1. Live: the `services` table through Supabase REST (anon key, read-only) —
   used when this runs on a machine that can reach Supabase.
2. Fallback: the `insert into public.services (...) values (...)` rows in the
   repo's SQL files.

Returns {key: {name, category, vehicle_type, tagline, description, price,
price_label, duration, features: [...], details: {...}, active, bookable,
is_addon}}.
"""
import json
import os
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUPABASE_URL = "https://rmvxqjyoqfinbrpubsvp.supabase.co"
SQL_FILES = [
    "supabase/migrations/20261009000000_server_catalog.sql",
    "supabase/other_services.sql",
    "supabase/lighting_services.sql",
    "supabase/offer_apartment_booking.sql",
]
COLS = "key,name,category,vehicle_type,tagline,description,price,price_label,duration,features,details,active,bookable,is_addon"


def _anon_key():
    if os.environ.get("SUPABASE_ANON_KEY"):
        return os.environ["SUPABASE_ANON_KEY"]
    for p in (ROOT / "lib").rglob("*.dart"):
        m = re.search(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", p.read_text(errors="ignore"))
        if m:
            return m.group(0)
    return None


def load_live():
    key = _anon_key()
    if not key:
        return None
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/services?select={COLS}&order=sort_order",
        headers={"apikey": key, "Authorization": f"Bearer {key}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            rows = json.load(r)
    except Exception as e:  # offline / blocked → use the SQL files
        print(f"  (live catalog not reachable: {e.__class__.__name__}) — using repo SQL")
        return None
    return {r["key"]: r for r in rows}


# ── SQL fallback ────────────────────────────────────────────────────────
def _value(s, i):
    """Parse one SQL literal starting at s[i]. Returns (value, next_index)."""
    while s[i] in " \t\r\n":
        i += 1
    if s[i] == "'":
        j, out = i + 1, []
        while True:
            if s[j] == "'" and s[j + 1:j + 2] == "'":
                out.append("'"); j += 2
            elif s[j] == "'":
                j += 1; break
            else:
                out.append(s[j]); j += 1
        text = "".join(out)
        cast = re.match(r"::(\w+(\[\])?)", s[j:])
        if cast:
            j += cast.end()
            if cast.group(1) == "jsonb":
                return json.loads(text), j
        return text, j
    if s.startswith("array[", i):
        depth, j = 0, i + 5
        while True:
            if s[j] == "[":
                depth += 1
            elif s[j] == "]":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        inner = s[i + 6:j]
        items = re.findall(r"'((?:[^']|'')*)'", inner)
        j += 1
        cast = re.match(r"::\w+(\[\])?", s[j:])
        if cast:
            j += cast.end()
        return [x.replace("''", "'") for x in items], j
    m = re.match(r"(null|true|false|-?\d+(\.\d+)?)", s[i:], re.I)
    tok = m.group(1).lower()
    j = i + m.end()
    if tok == "null":
        return None, j
    if tok in ("true", "false"):
        return tok == "true", j
    return (float(tok) if "." in tok else int(tok)), j


def _rows(sql):
    for m in re.finditer(r"insert\s+into\s+public\.services\s*\(([^)]*)\)\s*values", sql, re.I):
        cols = [c.strip() for c in m.group(1).split(",")]
        i = m.end()
        while True:
            while sql[i] in " \t\r\n,":
                i += 1
            if sql.startswith("--", i):
                i = sql.index("\n", i)
                continue
            if sql[i] != "(":
                break
            i += 1
            vals = []
            while True:
                v, i = _value(sql, i)
                vals.append(v)
                while sql[i] in " \t\r\n":
                    i += 1
                if sql[i] == ",":
                    i += 1
                    continue
                if sql[i] == ")":
                    i += 1
                    break
                raise ValueError(f"unexpected {sql[i:i+30]!r}")
            yield dict(zip(cols, vals))


def load_sql():
    out = {}
    for f in SQL_FILES:
        p = ROOT / f
        if not p.exists():
            continue
        for row in _rows(p.read_text()):
            row.setdefault("active", True)
            out.setdefault(row["key"], row)
    return out


def apply_price_file(cat):
    """seo/live_prices.csv (key,price — exported from Supabase with
    `select key, price from services where active = true order by key;`)
    overrides the SQL-file prices. Used when the live API isn't reachable."""
    p = ROOT / "seo" / "live_prices.csv"
    if not p.exists():
        return cat
    import csv
    n = 0
    with open(p, newline="") as f:
        for row in csv.DictReader(f):
            k = (row.get("key") or "").strip()
            if k in cat:
                v = (row.get("price") or "").strip().lower()
                cat[k]["price"] = None if v in ("", "null") else (float(v) if "." in v else int(v))
                n += 1
    print(f"  prices from seo/live_prices.csv ({n} services)")
    return cat


def load():
    return load_live() or apply_price_file(load_sql())


if __name__ == "__main__":
    cat = load()
    print(len(cat), "services")
    for k, v in cat.items():
        print(f"{k:28} {str(v.get('price')):>6}  {v.get('category')!s:24} {v.get('name')}")

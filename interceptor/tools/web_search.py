#!/usr/bin/env python3
# Local web_search tool — DuckDuckGo + page fetch, no API key.
# Adapted from louchi1984-coder/deepcodex (MIT license).
import argparse, html, json, re, sys, urllib.error, urllib.parse, urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ddg_search

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
BLOCKED = ("reuters.com", "wsj.com", "nytimes.com", "zhihu.com")


def norm(v): return re.sub(r"\s+", " ", v or "").strip()

def html_to_text(v):
    v = re.sub(r"<script\b[^>]*>[\s\S]*?</script>", " ", v or "", flags=re.I)
    v = re.sub(r"<style\b[^>]*>[\s\S]*?</style>", " ", v, flags=re.I)
    v = re.sub(r"</(h[1-6]|p|li|tr|div|section|article|br)>", "\n", v, flags=re.I)
    v = re.sub(r"<[^>]+>", " ", v)
    return norm(html.unescape(v))

def decode_body(raw, headers):
    ct = headers.get("content-type", "")
    m = re.search(r"charset=([^;\s]+)", ct, re.I)
    cands = ([m.group(1)] if m else []) + ["utf-8", "gb18030", "latin-1"]
    for cs in cands:
        try: return raw.decode(cs, errors="replace")
        except LookupError: continue
    return raw.decode("utf-8", errors="replace")

def page_title(text):
    m = re.search(r"<title[^>]*>(.*?)</title>", text or "", re.I|re.S)
    return norm(html.unescape(re.sub(r"<[^>]+>", " ", m.group(1)))) if m else ""

def fetch_page(url, max_chars):
    host = urllib.parse.urlparse(url).netloc.lower()
    if any(d in host for d in BLOCKED):
        return {"fetched": False, "fetch_error": "blocked_domain"}
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": UA,
            "Accept": "text/html,application/xhtml+xml,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        })
        with urllib.request.urlopen(req, timeout=15) as r:
            raw = r.read(1_000_000)
            decoded = decode_body(raw, r.headers)
            ct = r.headers.get("content-type", "")
            text = html_to_text(decoded) if "html" in ct or "<html" in decoded[:1000].lower() else norm(decoded)
            return {"fetched": True, "status": r.status, "page_title": page_title(decoded), "excerpt": text[:max_chars]}
    except urllib.error.HTTPError as e:
        return {"fetched": False, "fetch_error": f"HTTP {e.code}"}
    except Exception as e:
        return {"fetched": False, "fetch_error": str(e)[:300]}

def extract_date(v):
    for pat in [r"\b20\d{2}[-/.年]\d{1,2}[-/.月]\d{1,2}日?\b",
                r"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+20\d{2}\b",
                r"\b20\d{2}\b"]:
        m = re.search(pat, v or "", re.I)
        if m: return m.group(0)
    return ""

def run(query, count, fetch_top, excerpt_chars):
    base = ddg_search.search(query, count)
    results = base.get("results", [])
    for i, r in enumerate(results):
        r["source"] = urllib.parse.urlparse(r.get("url", "")).netloc
        r["date"] = extract_date(f"{r.get('title','')} {r.get('snippet','')}")
        if i < fetch_top:
            r.update(fetch_page(r.get("url", ""), excerpt_chars))
            if not r.get("date"):
                r["date"] = extract_date(f"{r.get('page_title','')} {r.get('excerpt','')}")
        else:
            r["fetched"] = False
    return {
        "ok": bool(base.get("ok")),
        "query": query,
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "engine": base.get("engine"),
        "attempts": base.get("attempts", []),
        "results": results,
    }

def main():
    p = argparse.ArgumentParser()
    p.add_argument("query")
    p.add_argument("legacy_count", nargs="?", type=int)
    p.add_argument("-n", "--count", type=int, default=None)
    p.add_argument("--fetch-top", type=int, default=0)
    p.add_argument("--excerpt-chars", type=int, default=2500)
    a = p.parse_args()
    count = a.count if a.count is not None else a.legacy_count
    count = max(1, min(count or 5, 10))
    fetch_top = max(0, min(a.fetch_top, count))
    print(json.dumps(run(a.query, count, fetch_top, a.excerpt_chars), ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()

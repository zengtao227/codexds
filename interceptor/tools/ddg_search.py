#!/usr/bin/env python3
# DuckDuckGo search via urllib — no API key needed.
# Adapted from louchi1984-coder/deepcodex (MIT license).
import html, json, re, sys, urllib.parse, urllib.request

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"

def decode(v): return html.unescape(re.sub(r"<[^>]+>", " ", v or "")).strip()
def norm(v): return re.sub(r"\s+", " ", v or "").strip()

def norm_url(v):
    v = html.unescape(v or "")
    try:
        p = urllib.parse.urlparse(v)
        q = urllib.parse.parse_qs(p.query)
        if "uddg" in q: return urllib.parse.unquote(q["uddg"][0])
        if v.startswith("//"): return "https:" + v
        if v.startswith("/"): return urllib.parse.urljoin("https://duckduckgo.com", v)
        return v
    except Exception: return v

def is_ad(title, url):
    return "duckduckgo.com/y.js" in (url or "").lower()

def fetch(url, data=None, timeout=15):
    req = urllib.request.Request(url, data=data, headers={
        "User-Agent": UA, "Accept": "text/html,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    })
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read()
        cs = r.headers.get_content_charset() or "utf-8"
        return raw.decode(cs, errors="replace"), r.status

def is_challenge(t):
    t = (t or "").lower()
    return "unfortunately, bots use duckduckgo too" in t or "anomaly-modal" in t

def parse_lite(text, count):
    links = re.findall(r'<a[^>]*class=[\'"]result-link[\'"][^>]*href=[\'"]([^\'"]+)[\'"][^>]*>(.*?)</a>', text, re.I|re.S)
    snips = re.findall(r'<td[^>]*class=[\'"]result-snippet[\'"][^>]*>(.*?)</td>', text, re.I|re.S)
    results, seen = [], set()
    for i, (url, title) in enumerate(links):
        u, t = norm_url(url), norm(decode(title))
        if not u or u in seen or is_ad(t, u): continue
        seen.add(u)
        results.append({"title": t, "url": u, "snippet": norm(decode(snips[i] if i < len(snips) else ""))})
        if len(results) >= count: break
    return results

def parse_html(text, count):
    links = re.findall(r'<a[^>]*class=[\'"]result__a[\'"][^>]*href=[\'"]([^\'"]+)[\'"][^>]*>(.*?)</a>', text, re.I|re.S)
    snips = re.findall(r'<a[^>]*class=[\'"]result__snippet[\'"][^>]*>(.*?)</a>', text, re.I|re.S)
    results, seen = [], set()
    for i, (url, title) in enumerate(links):
        u, t = norm_url(url), norm(decode(title))
        if not u or u in seen or is_ad(t, u): continue
        seen.add(u)
        results.append({"title": t, "url": u, "snippet": norm(decode(snips[i] if i < len(snips) else ""))})
        if len(results) >= count: break
    return results

def search(query, count):
    data = urllib.parse.urlencode({"q": query}).encode()
    attempts = []
    for name, url, d, parser in [
        ("ddg-lite-post", "https://lite.duckduckgo.com/lite/", data, parse_lite),
        ("ddg-html-post", "https://html.duckduckgo.com/html/", data, parse_html),
        ("ddg-html-get",  "https://html.duckduckgo.com/html/?" + urllib.parse.urlencode({"q": query}), None, parse_html),
    ]:
        try:
            text, status = fetch(url, d)
            if is_challenge(text):
                attempts.append({"engine": name, "status": status, "error": "anti-bot"}); continue
            results = parser(text, count)
            attempts.append({"engine": name, "status": status, "results": len(results)})
            if results:
                return {"ok": True, "query": query, "engine": name, "results": results, "attempts": attempts}
        except Exception as e:
            attempts.append({"engine": name, "error": str(e)[:300]})
    return {"ok": False, "query": query, "results": [], "attempts": attempts}

if __name__ == "__main__":
    q = sys.argv[1] if len(sys.argv) > 1 else ""
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    print(json.dumps(search(q, max(1, min(n, 10))), ensure_ascii=False, indent=2))

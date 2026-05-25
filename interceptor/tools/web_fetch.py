#!/usr/bin/env python3
# Local web_fetch tool — extracts readable text from a URL.
# Adapted from louchi1984-coder/deepcodex (MIT license).
import json, re, sys, urllib.error, urllib.request

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def html_to_text(raw):
    text = raw.decode("utf-8", errors="replace")
    text = re.sub(r"<script[^>]*>[\s\S]*?</script>", " ", text, flags=re.I)
    text = re.sub(r"<style[^>]*>[\s\S]*?</style>", " ", text, flags=re.I)
    text = re.sub(r"</(h[1-6]|p|li|tr|div|section|article|br)>", "\n", text, flags=re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    for ent, ch in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", '"'), ("&#39;", "'")]:
        text = text.replace(ent, ch)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    if len(text) > 20000:
        text = text[:20000] + f"\n\n[truncated {len(text)-20000} chars]"
    return text


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "URL required"}))
        sys.exit(1)
    url = sys.argv[1]
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "Codex-Interceptor-WebFetch/1.0",
            "Accept": "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.8",
        })
        with urllib.request.urlopen(req, timeout=15) as r:
            raw = r.read()
        print(json.dumps({"ok": True, "url": url, "status": r.status, "text": html_to_text(raw)}))
    except urllib.error.HTTPError as e:
        print(json.dumps({"ok": False, "url": url, "status": e.code, "error": str(e)}))
    except Exception as e:
        print(json.dumps({"ok": False, "url": url, "error": str(e)}))


if __name__ == "__main__":
    main()

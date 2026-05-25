#!/usr/bin/env node
/**
 * codexds tool interceptor
 *
 * Sits between Codex and Moon Bridge. Intercepts web_search / web_fetch
 * (hosted tools DeepSeek doesn't support), executes them locally via Python,
 * then feeds results back so Codex sees a seamless response.
 *
 * Also detects DeepSeek fake tool calls and improves context compaction.
 */

import http from "node:http";
import zlib from "node:zlib";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const MB_URL    = (process.env.MB_URL || "http://127.0.0.1:38440").replace(/\/$/, "");
const PORT      = Number(process.env.INTERCEPTOR_PORT || 8383);
const MAX_LOOPS = 8;

const TOOLS_DIR   = resolve(__dirname, "tools");
const SEARCH_PY   = resolve(TOOLS_DIR, "web_search.py");
const FETCH_PY    = resolve(TOOLS_DIR, "web_fetch.py");

const HOSTED = new Set(["web_search", "web_search_preview", "web_fetch"]);

const FAKE_TOOL_RE = [
    /I(?:'ve| have) (?:searched?|look(?:ed)? up) (?:for )?["']?[^"'\n]{3,60}["']?/i,
    /Based on (?:my |the )?(?:web )?search/i,
    /(?:search results?|web search) (?:show|reveal|indicate)/i,
];

const WEB_SEARCH_DEF = {
    type: "function",
    name: "web_search",
    description: "Search the web using DuckDuckGo. Returns ranked results with snippets.",
    parameters: {
        type: "object",
        properties: {
            query: { type: "string" },
            count: { type: "integer", default: 5 },
        },
        required: ["query"],
    },
};

const WEB_FETCH_DEF = {
    type: "function",
    name: "web_fetch",
    description: "Fetch and extract readable text from a URL.",
    parameters: {
        type: "object",
        properties: { url: { type: "string" } },
        required: ["url"],
    },
};

const COMPACT_SUFFIX = `\n\nCONTEXT CHECKPOINT: Produce a structured handoff summary covering:
1. Active task and current progress
2. Files edited (path + key change)
3. Commands run and their output
4. Decisions made and why
5. Exact next action the resuming model should take first
Be concise and specific — the next model must not re-discover anything.`;

// ── Python execution ──────────────────────────────────────────────────────────

function pythonBins() {
    return process.platform === "win32"
        ? ["python", "py", "python3"]
        : ["python3", "python"];
}

function execPython(script, args, ms = 30_000) {
    const bins = pythonBins();
    return new Promise((resolve) => {
        let i = 0;
        const errs = [];
        const next = () => {
            const bin = bins[i++];
            if (!bin) {
                resolve(JSON.stringify({ ok: false, error: "python unavailable", attempts: errs }));
                return;
            }
            execFile(bin, [script, ...args], { timeout: ms, maxBuffer: 4 * 1024 * 1024 }, (err, stdout) => {
                const out = String(stdout || "").trim();
                if (out) { resolve(out); return; }
                errs.push({ bin, error: err?.message || "no output" });
                next();
            });
        };
        next();
    });
}

async function executeTool(name, argsJson) {
    const a = (() => { try { return JSON.parse(argsJson || "{}"); } catch { return {}; } })();
    if (name === "web_search" || name === "web_search_preview") {
        const q = String(a.query || "");
        const n = String(Math.max(1, Math.min(Number(a.count) || 5, 10)));
        return execPython(SEARCH_PY, [q, "-n", n, "--fetch-top", "2"]);
    }
    if (name === "web_fetch") {
        return execPython(FETCH_PY, [String(a.url || "")]);
    }
    return JSON.stringify({ error: `unknown tool: ${name}` });
}

// ── Request body ──────────────────────────────────────────────────────────────

function readBody(req) {
    return new Promise((ok, fail) => {
        const chunks = [];
        const enc = req.headers["content-encoding"] || "";
        let src = req;
        if (enc.includes("gzip"))    src = req.pipe(zlib.createGunzip());
        else if (enc.includes("br")) src = req.pipe(zlib.createBrotliDecompress());
        src.on("data", c => chunks.push(c));
        src.on("end", () => ok(Buffer.concat(chunks).toString("utf8")));
        src.on("error", fail);
    });
}

// ── Tool rewriting ────────────────────────────────────────────────────────────

function rewriteTools(body) {
    if (!Array.isArray(body.tools)) return { body, hasHosted: false };
    let hasHosted = false;
    const tools = body.tools.map(t => {
        if (!HOSTED.has(t.type)) return t;
        hasHosted = true;
        if (t.type === "web_fetch") return WEB_FETCH_DEF;
        return WEB_SEARCH_DEF;
    });
    return { body: { ...body, tools }, hasHosted };
}

// ── Compaction detection ──────────────────────────────────────────────────────

function isCompact(body) {
    return body?.tool_choice === "none" && Array.isArray(body?.input) && body.input.length > 2;
}

function injectCompact(body) {
    const idx = body.input.findIndex(i => i.role === "system");
    const inp = [...body.input];
    if (idx >= 0) {
        const c = typeof inp[idx].content === "string" ? inp[idx].content : "";
        inp[idx] = { ...inp[idx], content: c + COMPACT_SUFFIX };
    } else {
        inp.unshift({ role: "system", content: COMPACT_SUFFIX.trim() });
    }
    return { ...body, input: inp };
}

// ── Moon Bridge request ───────────────────────────────────────────────────────

function mbPost(path, body, authHeader) {
    const json = JSON.stringify(body);
    const u = new URL(MB_URL);
    return new Promise((ok, fail) => {
        const req = http.request({
            hostname: u.hostname,
            port: u.port || 38440,
            path,
            method: "POST",
            headers: {
                "content-type": "application/json",
                "content-length": Buffer.byteLength(json),
                "accept": "text/event-stream",
                "authorization": authHeader || "Bearer codexds-local",
            },
        }, ok);
        req.on("error", fail);
        req.write(json);
        req.end();
    });
}

// ── SSE collection ────────────────────────────────────────────────────────────

function collectSSE(mbRes) {
    return new Promise((ok, fail) => {
        let buf = "";
        let completed = null;
        const events = [];

        mbRes.on("data", chunk => {
            buf += chunk.toString("utf8");
            const lines = buf.split("\n");
            buf = lines.pop();
            for (const line of lines) {
                if (!line.startsWith("data: ")) continue;
                const raw = line.slice(6).trim();
                if (raw === "[DONE]") continue;
                try {
                    const ev = JSON.parse(raw);
                    events.push(ev);
                    if (ev.type === "response.completed") completed = ev.response;
                } catch { /* skip */ }
            }
        });
        mbRes.on("end", () => ok({ events, completed }));
        mbRes.on("error", fail);
    });
}

function getFunctionCalls(completed) {
    return (completed?.output || []).filter(i => i.type === "function_call");
}

function getTextOutput(completed) {
    return (completed?.output || [])
        .filter(i => i.type === "message")
        .flatMap(i => (i.content || []).filter(p => p.type === "output_text" || p.type === "text").map(p => p.text || ""))
        .join("");
}

function isFakeTool(text, fcs) {
    if (fcs.length > 0) return false;
    return FAKE_TOOL_RE.some(r => r.test(text));
}

// ── Follow-up request builder ─────────────────────────────────────────────────

function buildFollowUp(body, completed, results) {
    const inp = [...(body.input || [])];
    for (const fc of (completed?.output || [])) {
        if (fc.type === "function_call") {
            inp.push({ type: "function_call", call_id: fc.call_id, name: fc.name, arguments: fc.arguments });
        }
    }
    for (const { callId, result } of results) {
        inp.push({ type: "function_call_output", call_id: callId, output: result });
    }
    return { ...body, input: inp };
}

// ── Stream to client ──────────────────────────────────────────────────────────

function streamEvents(res, events) {
    res.writeHead(200, {
        "content-type": "text/event-stream",
        "cache-control": "no-cache",
        "connection": "keep-alive",
        "access-control-allow-origin": "*",
    });
    for (const ev of events) res.write(`data: ${JSON.stringify(ev)}\n\n`);
    res.write("data: [DONE]\n\n");
    res.end();
}

// ── Transparent proxy ─────────────────────────────────────────────────────────

function proxyDirect(body, reqHeaders, reqPath, res) {
    return new Promise((ok, fail) => {
        mbPost(reqPath, body, reqHeaders.authorization).then(mbRes => {
            res.writeHead(mbRes.statusCode, {
                "content-type": mbRes.headers["content-type"] || "text/event-stream",
                "cache-control": "no-cache",
                "connection": "keep-alive",
                "access-control-allow-origin": "*",
            });
            mbRes.pipe(res);
            mbRes.on("end", ok);
            mbRes.on("error", fail);
        }).catch(fail);
    });
}

// ── Main handler ──────────────────────────────────────────────────────────────

async function handle(req, res) {
    const url = req.url || "/";
    const isResponses = url.includes("/responses");

    // Non-responses paths → transparent proxy
    if (!isResponses) {
        const u = new URL(MB_URL);
        const proxy = http.request(
            { hostname: u.hostname, port: u.port || 38440, path: url, method: req.method, headers: req.headers },
            mbRes => { res.writeHead(mbRes.statusCode, mbRes.headers); mbRes.pipe(res); }
        );
        req.pipe(proxy);
        proxy.on("error", err => { if (!res.headersSent) { res.writeHead(502); res.end(JSON.stringify({ error: err.message })); } });
        return;
    }

    let body;
    try {
        body = JSON.parse(await readBody(req));
    } catch {
        res.writeHead(400); res.end(JSON.stringify({ error: "invalid json" })); return;
    }

    if (isCompact(body)) body = injectCompact(body);

    const { body: rw, hasHosted } = rewriteTools(body);

    // No hosted tools → stream directly
    if (!hasHosted) {
        return proxyDirect(rw, req.headers, url, res);
    }

    // Tool execution loop
    let cur = rw;
    let fakeRetried = false;

    for (let loop = 0; loop < MAX_LOOPS; loop++) {
        let mbRes;
        try { mbRes = await mbPost(url, cur, req.headers.authorization); }
        catch (err) { res.writeHead(502); res.end(JSON.stringify({ error: `Moon Bridge: ${err.message}` })); return; }

        const { events, completed } = await collectSSE(mbRes);
        if (!completed) { streamEvents(res, events); return; }

        const fcs = getFunctionCalls(completed);
        const localFcs = fcs.filter(fc => fc.name === "web_search" || fc.name === "web_search_preview" || fc.name === "web_fetch");
        const text = getTextOutput(completed);

        // Fake tool call detection (one retry only)
        if (!fakeRetried && isFakeTool(text, fcs)) {
            fakeRetried = true;
            console.error("[interceptor] fake tool call detected, retrying");
            cur = {
                ...cur,
                input: [...(cur.input || []), {
                    role: "user",
                    content: "Please call the web_search or web_fetch functions directly instead of describing what you would search for.",
                }],
            };
            continue;
        }

        if (localFcs.length === 0) { streamEvents(res, events); return; }

        console.error(`[interceptor] executing tools: ${localFcs.map(f => f.name).join(", ")}`);
        const results = await Promise.all(localFcs.map(async fc => ({
            callId: fc.call_id,
            result: await executeTool(fc.name, fc.arguments),
        })));

        cur = buildFollowUp(cur, completed, results);
    }

    res.writeHead(500);
    res.end(JSON.stringify({ error: "max tool loops reached" }));
}

// ── Start ─────────────────────────────────────────────────────────────────────

http.createServer((req, res) => {
    handle(req, res).catch(err => {
        console.error("[interceptor] error:", err.message);
        if (!res.headersSent) { res.writeHead(500); res.end(JSON.stringify({ error: err.message })); }
    });
}).listen(PORT, "127.0.0.1", () => {
    console.log(`[interceptor] :${PORT} → Moon Bridge ${MB_URL}`);
});

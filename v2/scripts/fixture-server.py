#!/usr/bin/env python3
"""Local HTTP server for the example app: its smoke test
(apps/example/src/smoke/SmokeTest.tsx) and its demo screens.

Serves the committed fixtures (apps/example/fixtures/) with header-dependent
responses, chosen Cache-Control, throttled bodies, and per-path request
counts so the app can tell a cache hit from a fetch.

Routes (<name> is free, so each scenario gets its own URL and cache entry):

  /photo/<name>.jpg            600x400 JPEG
  /large/<name>.jpg            3000x2000 JPEG
  /slow/photo/<name>.jpg       the same two, sent slowly (progress events,
  /slow/large/<name>.jpg         and a load still running when JS reacts)
  /text.png /logo.svg          Live Text image; SVG
  /anim.gif /anim.png /anim.webp   animated GIF, APNG, WebP
  /anim-large.gif              1500x1000 animated GIF (two frames)
  /accept/png                  200 only if `Accept` allows image/png, else 406
  /not-an-image/<name>         200 with HTML; the load fails as `decode`
  /ua/<name>.jpg               403 for OkHttp's default User-Agent (as some CDNs)
  /cookie/set                  200 with Set-Cookie, for the app's `fetch`
  /cookie/photo/<name>.jpg     200 only if that cookie comes back, else 403
  /cache/fresh/<name>.jpg      Cache-Control: max-age=3600
  /cache/nostore/<name>.jpg    Cache-Control: no-store
  /cache/revalidate/<name>.jpg Cache-Control: no-cache + ETag (304 when matched)
  /__hits?path=<path>          JSON {"count", "conditional", "aborted"} for that path
  /__hits?prefix=<prefix>      the same, summed over every path under prefix
  /__ping                      200, for the smoke scripts' readiness check

`aborted` counts responses the client closed mid-body (a cancelled load).
Only slow bodies are still being written when that happens, so it is
meaningful for /slow/ paths only.

Loopback by default; Android reaches it through `adb reverse`. `--host
0.0.0.0` serves the LAN too, for a physical iPhone.

Usage: python3 scripts/fixture-server.py [--port 8765] [--host 127.0.0.1] [--log <file>]
"""

import argparse
import json
import pathlib
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

FIXTURES = pathlib.Path(__file__).resolve().parent.parent / "apps/example/fixtures"
ETAG = '"fixture-v1"'
# A session cookie as a login endpoint would set one.
COOKIE = "turboimage_smoke=1"

# /slow/ pacing: the large photo takes ~2 s, long enough to cancel mid-flight.
SLOW_CHUNK = 4096
SLOW_PAUSE_S = 0.02


def fixture(name):
    return (FIXTURES / name).read_bytes()


PHOTO = (fixture("photo-600x400.jpg"), "image/jpeg")
LARGE = (fixture("photo-3000x2000.jpg"), "image/jpeg")
EXACT = {
    "/text.png": (fixture("text-600x400.png"), "image/png"),
    "/logo.svg": (fixture("logo.svg"), "image/svg+xml"),
    "/anim.gif": (fixture("anim-120x120.gif"), "image/gif"),
    "/anim-large.gif": (fixture("anim-1500x1000.gif"), "image/gif"),
    "/anim.png": (fixture("anim-100x100.png"), "image/png"),
    "/anim.webp": (fixture("anim-160x120.webp"), "image/webp"),
}
CACHE_HEADERS = {
    "/cache/fresh/": {"Cache-Control": "max-age=3600"},
    "/cache/nostore/": {"Cache-Control": "no-store"},
    "/cache/revalidate/": {"Cache-Control": "no-cache", "ETag": ETAG},
}

NOT_AN_IMAGE = b"<!doctype html><title>Not found</title><p>This page is not an image.</p>\n"

hits_lock = threading.Lock()
# path -> {"count": requests seen, "conditional": of those, with If-None-Match,
#          "aborted": of those, closed by the client before the body was sent}
hits = {}
EMPTY_HITS = {"count": 0, "conditional": 0, "aborted": 0}
log_file = None


def accepts_png(accept):
    """Whether an Accept header allows image/png (no q-value arithmetic)."""
    types = [part.split(";")[0].strip() for part in (accept or "*/*").split(",")]
    return any(t in ("image/png", "image/*", "*/*") for t in types)


class Handler(BaseHTTPRequestHandler):
    # Keep-alive, like a real image host; every response carries a length.
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        url = urlsplit(self.path)
        path = url.path
        if path == "/__ping":
            return self.reply(200, b"ok", "text/plain")
        if path == "/__hits":
            query = parse_qs(url.query)
            counts = dict(EMPTY_HITS)
            with hits_lock:
                if "prefix" in query:
                    prefix = query["prefix"][0]
                    matching = [v for k, v in hits.items() if k.startswith(prefix)]
                else:
                    matching = [hits.get(query.get("path", [""])[0], EMPTY_HITS)]
                for entry in matching:
                    for key in counts:
                        counts[key] += entry[key]
            return self.reply(200, json.dumps(counts).encode(), "application/json")

        validator = self.headers.get("If-None-Match")
        with hits_lock:
            entry = hits.setdefault(path, dict(EMPTY_HITS))
            entry["count"] += 1
            entry["conditional"] += validator is not None

        if path in EXACT:
            return self.reply(200, *EXACT[path])
        if path.startswith("/not-an-image/"):
            return self.reply(200, NOT_AN_IMAGE, "text/html; charset=utf-8")
        if path == "/accept/png":
            if accepts_png(self.headers.get("Accept")):
                return self.reply(200, *EXACT["/text.png"])
            return self.reply(406, b"", "text/plain")
        if path.startswith("/ua/"):
            if self.headers.get("User-Agent", "").startswith("okhttp/"):
                return self.reply(403, b"", "text/plain")
            return self.reply(200, *PHOTO)
        if path == "/cookie/set":
            return self.reply(200, b"ok", "text/plain", {"Set-Cookie": f"{COOKIE}; Path=/cookie"})
        if path.startswith("/cookie/photo/"):
            sent = [c.strip() for c in self.headers.get("Cookie", "").split(";")]
            if COOKIE in sent:
                return self.reply(200, *PHOTO)
            return self.reply(403, b"", "text/plain")
        for prefix, headers in CACHE_HEADERS.items():
            if path.startswith(prefix):
                if "ETag" in headers and validator == ETAG:
                    return self.reply(304, b"", None, headers)
                return self.reply(200, *PHOTO, headers)
        slow = path.startswith("/slow/")
        kind = path[len("/slow") :] if slow else path
        if kind.startswith("/photo/"):
            return self.reply(200, *PHOTO, slow=slow)
        if kind.startswith("/large/"):
            return self.reply(200, *LARGE, slow=slow)
        return self.reply(404, b"", "text/plain")

    def reply(self, status, body, content_type, headers=None, slow=False):
        self.send_response(status)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        if content_type:
            self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            if not slow:
                self.wfile.write(body)
                return
            for start in range(0, len(body), SLOW_CHUNK):
                self.wfile.write(body[start : start + SLOW_CHUNK])
                self.wfile.flush()
                time.sleep(SLOW_PAUSE_S)
        except (BrokenPipeError, ConnectionResetError):
            # A cancelled load closed the connection; expected, not an error.
            self.close_connection = True
            with hits_lock:
                hits[urlsplit(self.path).path]["aborted"] += 1

    def log_message(self, fmt, *args):
        if log_file is None:
            return
        validator = self.headers.get("If-None-Match") if self.headers else None
        with hits_lock:
            log_file.write(f"{time.strftime('%H:%M:%S')} {fmt % args} If-None-Match={validator}\n")
            log_file.flush()


def main():
    global log_file
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--log", type=pathlib.Path)
    args = parser.parse_args()
    if args.log:
        args.log.parent.mkdir(parents=True, exist_ok=True)
        log_file = args.log.open("w")
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()

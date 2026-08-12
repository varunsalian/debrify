#!/usr/bin/env python3
"""Fault-injecting live-IPTV origin for the resilience plan's test matrix.

Phase 0 of design/plans/IPTV_FLAWLESS_PLAYBACK_PLAN.md. This is the thing
`python -m http.server` is NOT: a finite file re-served from byte zero models
nothing about a live origin. This server loops a real transport stream at a
paced bitrate and injects the failures the recovery layers must survive:

    /live/ok.ts                      endless well-behaved stream
    /live/ok2.ts                     second identity of the same (zap target)
    /live/eof.ts?after=15            CLEAN EOF after N seconds (proper chunked
                                     terminator — the polite server close)
    /live/drop.ts?after=15           premature close mid-chunk after N seconds
                                     (no terminator — the rude server close)
    /live/stall.ts?after=15&hold=120 streams N seconds, then goes silent with
                                     the socket held open (the wedge case)
    /live/status/403.ts              immediate HTTP error; any code works —
                                     429 and 503 carry `Retry-After: 5`
    /live/authflip.ts?plays=2        first N connects stream fine, every later
                                     connect gets 403 (expiring signed URL)
    /hls/ok.m3u8                     live HLS, 4s segments, sliding window
    /hls/stale.m3u8?after=30         same, but the playlist stops advancing
                                     its media sequence after N seconds
    /playlist.m3u                    all of the above as an M3U — add THIS
                                     one URL as an IPTV source in Debrify and
                                     every fault becomes a channel

Usage:
    python3 tool/iptv_fault_server.py --source /path/to/sample.ts
    python3 tool/iptv_fault_server.py --source sample.ts --port 8899 --kbps 4000

Then add  http://<this-machine's-LAN-IP>:8899/playlist.m3u  as an M3U source.

The source must be a raw MPEG-TS file (a Debrify DVR recording works, or:
`ffmpeg -i anything.mp4 -c copy -f mpegts sample.ts`). It is looped forever,
188-byte aligned; PAT/PMT repeat throughout a normal TS so mid-file joins
decode after a moment, exactly like joining a real live stream mid-GOP.
Timestamps jump backward at the loop seam — that is a feature for our
purposes (a discontinuity the players must ride through), not a bug.

Stdlib only. Dev tool: never ship, never bind beyond the LAN.
"""

import argparse
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

TS_PACKET = 188
TICK_SECONDS = 0.25
HLS_SEGMENT_SECONDS = 4
HLS_WINDOW = 5

SOURCE = b""
KBPS = 4000
START = time.monotonic()

# /live/authflip.ts connect counters, keyed by path+query so distinct
# `plays=` variants count independently.
_authflip_lock = threading.Lock()
_authflip_counts: dict[str, int] = {}

# Stale-HLS epochs, keyed by path+query: `after=30` counts from the FIRST
# request for that playlist, not server startup — otherwise a server that
# has been up 30s serves an already-stale playlist and the "plays, then
# freezes" measurement is invalid.
_hls_epoch_lock = threading.Lock()
_hls_epochs: dict[str, float] = {}


def fill_source(offset: int, length: int) -> bytes:
    """`length` bytes of looped source starting at `offset`, wrapping as many
    times as needed — a short source must still fill a full segment/tick or
    it fabricates EOF/stall results."""
    out = bytearray()
    offset %= len(SOURCE)
    while len(out) < length:
        chunk = SOURCE[offset : offset + (length - len(out))]
        if not chunk:
            offset = 0
            continue
        out += chunk
        offset = (offset + len(chunk)) % len(SOURCE)
    return bytes(out)


def lan_ip() -> str:
    """Best-effort LAN address for the printed playlist URL."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return "127.0.0.1"


def aligned(n: int) -> int:
    return (n // TS_PACKET) * TS_PACKET


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # ── plumbing ──────────────────────────────────────────────────────────

    def log_message(self, fmt, *args):  # quieter default log line
        sys.stderr.write("[%s] %s\n" % (self.address_string(), fmt % args))

    def _query(self) -> dict:
        return parse_qs(urlparse(self.path).query)

    def _qint(self, key: str, default: int) -> int:
        try:
            return int(self._query().get(key, [default])[0])
        except ValueError:
            return default

    def _bytes_per_tick(self) -> int:
        return max(TS_PACKET, aligned(int(KBPS * 1000 / 8 * TICK_SECONDS)))

    def _stream_headers(self):
        self.send_response(200)
        self.send_header("Content-Type", "video/mp2t")
        # No Content-Length: byte flow until the fault says otherwise —
        # exactly how Xtream-style origins serve live TS.
        self.send_header("Connection", "close")

    def _source_iter(self, start_offset: int = 0):
        """Endless paced iterator over the looped source."""
        offset = aligned(start_offset) % len(SOURCE)
        per_tick = self._bytes_per_tick()
        while True:
            yield fill_source(offset, per_tick)
            offset = (offset + per_tick) % len(SOURCE)
            time.sleep(TICK_SECONDS)

    # ── endpoints ─────────────────────────────────────────────────────────

    def do_GET(self):  # noqa: N802 (BaseHTTPRequestHandler contract)
        path = urlparse(self.path).path
        try:
            if path == "/playlist.m3u":
                self._serve_playlist()
            elif path in ("/live/ok.ts", "/live/ok2.ts"):
                self._serve_endless()
            elif path == "/live/eof.ts":
                self._serve_finite(clean=True)
            elif path == "/live/drop.ts":
                self._serve_finite(clean=False)
            elif path == "/live/stall.ts":
                self._serve_stall()
            elif path.startswith("/live/status/"):
                self._serve_status(path)
            elif path == "/live/authflip.ts":
                self._serve_authflip()
            elif path in ("/hls/ok.m3u8", "/hls/stale.m3u8"):
                self._serve_hls_playlist(stale=path.endswith("stale.m3u8"))
            elif path.startswith("/hls/seg-") and path.endswith(".ts"):
                self._serve_hls_segment(path)
            else:
                self.send_error(404)
        except (BrokenPipeError, ConnectionResetError):
            pass  # client zapped away — the normal end of every live request

    def _serve_playlist(self):
        host = self.headers.get("Host", f"{lan_ip()}:{self.server.server_port}")
        base = f"http://{host}"
        channels = [
            ("OK endless", "/live/ok.ts"),
            ("OK endless 2 (zap target)", "/live/ok2.ts"),
            ("Clean EOF after 15s", "/live/eof.ts?after=15"),
            ("Premature drop after 15s", "/live/drop.ts?after=15"),
            ("Stall after 15s", "/live/stall.ts?after=15&hold=120"),
            ("HTTP 401", "/live/status/401.ts"),
            ("HTTP 403", "/live/status/403.ts"),
            ("HTTP 404", "/live/status/404.ts"),
            ("HTTP 429 +Retry-After", "/live/status/429.ts"),
            ("HTTP 503 +Retry-After", "/live/status/503.ts"),
            ("Auth flips dead after 2 plays", "/live/authflip.ts?plays=2"),
            ("HLS OK", "/hls/ok.m3u8"),
            ("HLS playlist goes stale after 30s", "/hls/stale.m3u8?after=30"),
        ]
        body_lines = ["#EXTM3U"]
        for name, ep in channels:
            body_lines.append(f'#EXTINF:-1 group-title="Fault Lab",{name}')
            body_lines.append(base + ep)
        body = ("\n".join(body_lines) + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "audio/x-mpegurl")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _serve_endless(self):
        self._stream_headers()
        self.end_headers()
        for chunk in self._source_iter():
            self.wfile.write(chunk)
            self.wfile.flush()

    def _serve_finite(self, clean: bool):
        """Chunked transfer so 'ended on purpose' and 'connection died' are
        distinguishable on the wire: clean sends the terminating 0-chunk,
        drop closes the socket mid-stream without one."""
        after = self._qint("after", 15)
        self.send_response(200)
        self.send_header("Content-Type", "video/mp2t")
        self.send_header("Transfer-Encoding", "chunked")
        self.send_header("Connection", "close")
        self.end_headers()
        deadline = time.monotonic() + after
        for chunk in self._source_iter():
            if time.monotonic() >= deadline:
                if clean:
                    self.wfile.write(b"0\r\n\r\n")
                else:
                    # A genuinely mid-chunk disconnect: claim a full chunk,
                    # deliver half, close. The client sees the connection
                    # die INSIDE a chunk body, not between chunks.
                    self.wfile.write(
                        b"%x\r\n" % len(chunk) + chunk[: len(chunk) // 2]
                    )
                self.wfile.flush()
                return
            self.wfile.write(b"%x\r\n" % len(chunk) + chunk + b"\r\n")
            self.wfile.flush()

    def _serve_stall(self):
        after = self._qint("after", 15)
        hold = self._qint("hold", 120)
        self._stream_headers()
        self.end_headers()
        deadline = time.monotonic() + after
        for chunk in self._source_iter():
            self.wfile.write(chunk)
            self.wfile.flush()
            if time.monotonic() >= deadline:
                break
        time.sleep(hold)  # socket open, zero bytes — the wedge

    def _serve_status(self, path: str):
        try:
            code = int(path.rsplit("/", 1)[1].removesuffix(".ts"))
        except ValueError:
            self.send_error(404)
            return
        self.send_response(code)
        if code in (429, 503):
            self.send_header("Retry-After", "5")
        self.send_header("Content-Length", "0")
        self.send_header("Connection", "close")
        self.end_headers()

    def _serve_authflip(self):
        plays = self._qint("plays", 2)
        with _authflip_lock:
            n = _authflip_counts.get(self.path, 0) + 1
            _authflip_counts[self.path] = n
        if n > plays:
            self.send_response(403)
            self.send_header("Content-Length", "0")
            self.send_header("Connection", "close")
            self.end_headers()
            return
        self._serve_endless()

    # ── HLS ───────────────────────────────────────────────────────────────

    def _hls_sequence(self, stale: bool) -> int:
        # Elapsed counts from this playlist's FIRST request, so `after=N`
        # means "N seconds after the player tuned", not "after server start".
        with _hls_epoch_lock:
            epoch = _hls_epochs.setdefault(self.path, time.monotonic())
        elapsed = time.monotonic() - epoch
        after = self._qint("after", 30)
        if stale and elapsed >= after:
            elapsed = after  # playlist frozen at the moment it went stale
        # Additive, not max(): the sequence must visibly advance every
        # segment-duration from the first request, or a freeze inside the
        # first window is indistinguishable from a fresh playlist.
        return HLS_WINDOW + int(elapsed / HLS_SEGMENT_SECONDS)

    def _serve_hls_playlist(self, stale: bool):
        seq = self._hls_sequence(stale)
        first = seq - HLS_WINDOW + 1
        lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            f"#EXT-X-TARGETDURATION:{HLS_SEGMENT_SECONDS}",
            f"#EXT-X-MEDIA-SEQUENCE:{first}",
        ]
        for n in range(first, seq + 1):
            lines.append(f"#EXTINF:{HLS_SEGMENT_SECONDS:.1f},")
            lines.append(f"/hls/seg-{n}.ts")
        body = ("\n".join(lines) + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/vnd.apple.mpegurl")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _serve_hls_segment(self, path: str):
        try:
            n = int(path[len("/hls/seg-") : -len(".ts")])
        except ValueError:
            self.send_error(404)
            return
        seg_bytes = aligned(int(KBPS * 1000 / 8 * HLS_SEGMENT_SECONDS))
        chunk = fill_source(n * seg_bytes, seg_bytes)
        self.send_response(200)
        self.send_header("Content-Type", "video/mp2t")
        self.send_header("Content-Length", str(len(chunk)))
        self.end_headers()
        self.wfile.write(chunk)


def main():
    global SOURCE, KBPS
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--source", required=True, help="raw MPEG-TS file to loop")
    ap.add_argument("--port", type=int, default=8899)
    ap.add_argument("--kbps", type=int, default=4000, help="paced stream bitrate")
    args = ap.parse_args()

    with open(args.source, "rb") as f:
        SOURCE = f.read()
    if len(SOURCE) < TS_PACKET * 100:
        sys.exit("source too small to loop meaningfully")
    if SOURCE[0] != 0x47:
        sys.exit("source is not MPEG-TS (first byte != 0x47 sync)")
    SOURCE = SOURCE[: aligned(len(SOURCE))]
    KBPS = args.kbps

    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print(f"IPTV fault lab up. Add this as an M3U source in Debrify:")
    print(f"  http://{lan_ip()}:{args.port}/playlist.m3u")
    print(f"Source: {args.source} ({len(SOURCE)//1024} KiB looped @ {KBPS} kbps)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

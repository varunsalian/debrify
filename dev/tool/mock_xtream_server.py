#!/usr/bin/env python3
"""
Mock Xtream Codes server for testing Debrify's IPTV Series support without a
real subscription. Serves your own local video files as an Xtream "series"
panel: speaks the player_api.php protocol the app calls, and streams the files
back over the /series/{user}/{pass}/{id}.{ext} URLs it builds.

Usage:
    python3 tool/mock_xtream_server.py /path/to/your/media [port]

Media folder layout — each subfolder is a series; season/episode is parsed from
the filename (SxxExx anywhere in the name or path). Nested "Season N" folders
are fine too:

    media/
      Breaking Bad/
        S01E01 - Pilot.mkv
        S01E02.mkv
        S02E01.mp4
      The Office/
        Season 1/
          S01E01 Pilot.mkv

Then in Debrify: IPTV settings -> Xtream Codes -> add a playlist with
    Server URL: http://<this-machine-ip>:<port>
    Username:   test   (anything)
    Password:   test   (anything)
select it, switch the content type to "Series", and browse.

Stdlib only — no pip installs. Ctrl-C to stop.

Notes / things it deliberately exercises in the app:
  * lowercase `releasedate` at episode level (the real-panel spelling)
  * a `duration:"HH:MM:SS"` string with `duration_secs:"0"` on odd episodes,
    to check the app's HH:MM:SS runtime fallback
  * two files that parse to the SAME SxxExx (e.g. an SD + a 4K copy) show up as
    two tiles with different URLs — tapping either must play that exact file
    (the "playbackUrl-first" fix). Drop a duplicate in to try it.

Live TV + EPG (all synthetic, no media needed): every video file in the media
root doubles as a "live channel" looping stream, with a generated schedule.
Endpoints: get_live_categories / get_live_streams / get_short_epg /
get_simple_data_table, plus the whole-account xmltv.php guide and a
get.php?type=m3u_plus playlist export (to exercise the M3U-from-Xtream path).

Real-panel quirk flags (each mimics a documented panel misbehavior):
  --epg-map          get_short_epg answers `epg_listings` as a JSON *object*
                     keyed by index (PHP assoc-array quirk) instead of a list
  --epg-shift N      shift epoch timestamps by N hours (panels with broken TZ
                     math — the guide looks empty because nothing "airs now")
  --epg-plain        titles/descriptions NOT base64-encoded
  --no-short-epg     get_short_epg/get_simple_data_table answer [] (panels
                     with the per-stream EPG endpoints broken/disabled — the
                     app should fall back to xmltv.php)
  --typo-data-table  get_simple_data_table answers [] and only the legacy
                     typo action get_simple_date_table has data (old panels
                     — exercises the app's typo fallback)
  --no-hls           /live/... .m3u8 URLs 404 (TS-only panel)
  --no-ts            /live/... .ts URLs 404 (HLS-only panel)
"""

import base64
import gzip
import html
import http.server
import json
import mimetypes
import os
import re
import socket
import socketserver
import sys
import time
import urllib.parse
import urllib.request

VIDEO_EXTS = {".mkv", ".mp4", ".avi", ".mov", ".m4v", ".webm", ".ts", ".flv", ".wmv", ".mpg", ".mpeg"}

# Season/episode from a name, tried in order:
#   1) SxxEyy  (S01E01, s1e1, S01.E01, S01 E01)
#   2) NxNN    (1x01, 01x01)
_SXXEXX = re.compile(r"[Ss](\d{1,3})[ ._x-]*[Ee](\d{1,4})")
_NXNN = re.compile(r"(?<![\dx])(\d{1,3})x(\d{1,4})(?!\d)", re.IGNORECASE)
# Season from a folder name: "Season 1", "Season 01", "S1", "Series 1", "Specials".
_SEASON_DIR = re.compile(r"^(?:season|series|s)[ ._-]*(\d{1,3})$", re.IGNORECASE)
_SPECIALS_DIR = re.compile(r"^specials?$", re.IGNORECASE)
# Episode number inside a name once the season is known from the folder:
# "E01"/"Ep 1"/"Episode 1", else a leading "01 - Title".
_EP_IN_NAME = re.compile(r"[Ee]p?(?:isode)?[ ._-]*(\d{1,4})")
_LEADING_NUM = re.compile(r"^\s*(\d{1,4})\b")


def _season_from_dirs(rel_path):
    """Read a season number from any parent folder of the episode file."""
    for part in os.path.dirname(rel_path).split(os.sep):
        if _SPECIALS_DIR.match(part.strip()):
            return 0
        m = _SEASON_DIR.match(part.strip())
        if m:
            return int(m.group(1))
    return None


def _clean_title(raw, number):
    """Tidy the episode title: dots/underscores → spaces, cut everything from
    the first release-junk token (MULTi/1080p/WEB/…), collapse separators.
    Falls back to 'Episode N' when nothing usable remains."""
    t = re.sub(r"[._]+", " ", raw)
    j = _NAME_JUNK.search(t)
    if j:
        t = t[: j.start()]
    t = re.sub(r"\s*-\s*-\s*", " - ", t)  # "A -  - B" -> "A - B"
    t = re.sub(r"\s+", " ", t).strip(" -_.")
    return t or f"Episode {number}"


def _parse_se(rel_path, seq_counter):
    """Return (season, number, title). seq_counter[0] is a running fallback
    episode index for files no pattern matches. The title is taken from the
    text AFTER the season/episode token (that's where the episode name sits in
    'Show.S01E01.Episode.Name.junk' releases)."""
    base = os.path.splitext(os.path.basename(rel_path))[0]

    m = _SXXEXX.search(base)
    if m:
        num = int(m.group(2))
        return int(m.group(1)), num, _clean_title(base[m.end():], num)

    # SxxEyy only in a parent folder (rare) — season/number from there, title
    # from the whole filename.
    mp = _SXXEXX.search(rel_path)
    if mp:
        num = int(mp.group(2))
        return int(mp.group(1)), num, _clean_title(base, num)

    m = _NXNN.search(base)
    if m:
        num = int(m.group(2))
        return int(m.group(1)), num, _clean_title(base[m.end():], num)

    # Season from the folder, episode number from the filename.
    season = _season_from_dirs(rel_path)
    if season is not None:
        em = _EP_IN_NAME.search(base) or _LEADING_NUM.search(base)
        if em:
            number = int(em.group(1))
            return season, number, _clean_title(base[em.end():], number)

    # Nothing matched — sequential within season 1 (keeps the file usable).
    seq_counter[0] += 1
    return 1, seq_counter[0], _clean_title(base, seq_counter[0])

mimetypes.add_type("video/x-matroska", ".mkv")
mimetypes.add_type("video/mp4", ".m4v")
mimetypes.add_type("video/mp2t", ".ts")


class Episode:
    def __init__(self, ep_id, season, number, title, path):
        self.id = ep_id
        self.season = season
        self.number = number
        self.title = title
        self.path = path
        self.ext = os.path.splitext(path)[1].lstrip(".").lower() or "mp4"
        # Enriched from TVMaze (see enrich()); None until then.
        self.plot = None
        self.still = None      # per-episode thumbnail URL
        self.airdate = None
        self.runtime_secs = None


class Series:
    def __init__(self, series_id, name, folder):
        self.id = series_id
        self.name = name
        self.folder = folder
        self.episodes = []  # list[Episode]
        # Enriched from TVMaze (see enrich()); None/[] until then.
        self.poster = None
        self.backdrop = None
        self.plot = None
        self.genres = []
        self.rating = None     # 0-10 string
        self.year = None       # "2013"
        self.cast = None


class LiveChannel:
    """A synthetic live channel backed by a looping local file."""

    def __init__(self, ch_id, name, path, category_id, epg_channel_id):
        self.id = ch_id
        self.name = name
        self.path = path
        self.category_id = category_id
        self.epg_channel_id = epg_channel_id


_EPG_SHOWS = [
    ("Morning Briefing", "The day's headlines and what they mean."),
    ("Cooking with Fire", "Three chefs, one pantry, no rules."),
    ("Grand Prix Recap", "Every overtake from the weekend, analysed."),
    ("Nature's Giants", "Filmed over two years across four continents."),
    ("The Quiz Hour", "Contestants battle through five rounds of trivia."),
    ("Night Owls", "Late-night conversation with tomorrow's guests."),
    ("Classic Cinema", "A restored favourite from the golden age."),
    ("Tech Today", "Hands-on with the week's new gadgets."),
]


def build_live_channels(episodes_by_id):
    """One live channel per distinct media file (capped), plus a channel with
    NO epg_channel_id (guide must simply not show for it, nothing breaks)."""
    channels = []
    ch_id = 1001
    for ep in list(episodes_by_id.values())[:12]:
        base = os.path.splitext(os.path.basename(ep.path))[0]
        channels.append(
            LiveChannel(
                ch_id,
                f"Mock {base[:24]}",
                ep.path,
                category_id="10" if ch_id % 2 else "11",
                epg_channel_id=f"mock{ch_id}.test",
            )
        )
        ch_id += 1
    if channels:
        # A channel the guide doesn't cover — epg_channel_id empty.
        no_epg = channels[0]
        channels.append(
            LiveChannel(ch_id, "Mock NoGuide Channel", no_epg.path, "10", "")
        )
    return channels


def epg_schedule(channel, hours_back=6, hours_fwd=24, shift_hours=0):
    """Deterministic 30-minute programme blocks around 'now' for a channel.
    Returns a list of (start_epoch, stop_epoch, title, desc) tuples."""
    now = int(time.time())
    slot = 1800
    start = (now // slot) * slot - hours_back * 3600
    end = now + hours_fwd * 3600
    out = []
    i = 0
    t = start
    while t < end:
        show, desc = _EPG_SHOWS[(channel.id + i) % len(_EPG_SHOWS)]
        out.append(
            (t + shift_hours * 3600, t + slot + shift_hours * 3600, show, desc)
        )
        t += slot
        i += 1
    return out


# Release-name junk: the series title is everything before the first of these.
_NAME_JUNK = re.compile(
    r"\b(?:COMPLETE|MULTi|DUAL|\d{3,4}p|19\d{2}|20\d{2}|S\d{1,2}|"
    r"WEB[- ]?(?:DL|Rip)?|BluRay|BRRip|HDRip|DVDRip|x264|x265|HEVC|AVC|AV1|"
    r"AAC|DDP?\d?|DD\+?|DTS|HDR|NF|AMZN|DSNP|HMAX|ATVP|iNTERNAL|REPACK|PROPER)\b",
    re.IGNORECASE,
)


def _clean_series_name(raw):
    """'Orange.Is.the.New.Black.COMPLETE.MULTi.1080p...' -> 'Orange Is the
    New Black'. Falls back to the dotted-to-spaced whole name if the cut
    would leave nothing."""
    spaced = re.sub(r"[._]+", " ", raw)
    m = _NAME_JUNK.search(spaced)
    cut = spaced[: m.start()] if m else spaced
    cut = cut.strip(" -_.")
    return cut or spaced.strip(" -_.") or raw


def _strip_html(s):
    if not s:
        return None
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    return re.sub(r"\s+", " ", s).strip() or None


def _tvmaze_get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "debrify-mock/1.0"})
    with urllib.request.urlopen(req, timeout=12) as r:
        return json.load(r)


def enrich(series_list, log=print):
    """Fill in real metadata from TVMaze (keyless, no API key). Best-effort per
    show — a lookup failure leaves that show on its filename-derived
    placeholders, so the server still works fully offline."""
    for s in series_list:
        try:
            q = urllib.parse.quote(s.name)
            show = _tvmaze_get(
                f"https://api.tvmaze.com/singlesearch/shows?q={q}&embed=episodes"
            )
        except Exception as e:
            log(f"  ! TVMaze lookup failed for {s.name!r}: {e}")
            continue
        if not isinstance(show, dict):
            continue

        img = show.get("image") or {}
        s.poster = img.get("original") or img.get("medium")
        s.backdrop = s.poster  # TVMaze has no wide art; the poster fills the hero
        s.plot = _strip_html(show.get("summary"))
        s.genres = show.get("genres") or []
        rating = (show.get("rating") or {}).get("average")
        s.rating = str(rating) if rating else None
        premiered = show.get("premiered") or ""
        s.year = premiered[:4] if len(premiered) >= 4 else None

        # Match TVMaze episodes to our files by (season, number).
        embedded = ((show.get("_embedded") or {}).get("episodes")) or []
        by_se = {}
        for te in embedded:
            se, nu = te.get("season"), te.get("number")
            if se is not None and nu is not None:
                by_se[(int(se), int(nu))] = te

        matched = 0
        for ep in s.episodes:
            te = by_se.get((ep.season, ep.number))
            if not te:
                continue
            matched += 1
            if te.get("name"):
                ep.title = te["name"]  # canonical episode title
            ep.plot = _strip_html(te.get("summary"))
            ei = te.get("image") or {}
            ep.still = ei.get("original") or ei.get("medium")
            ep.airdate = te.get("airdate") or None
            rt = te.get("runtime")
            if isinstance(rt, int) and rt > 0:
                ep.runtime_secs = rt * 60

        log(f"  ✓ {s.name}: poster={'yes' if s.poster else 'no'}, "
            f"{matched}/{len(s.episodes)} episodes enriched")
        time.sleep(0.25)  # respect TVMaze's 20 req / 10s limit


def _video_files(folder):
    files = []
    for dirpath, _dirs, filenames in os.walk(folder):
        for fn in filenames:
            if os.path.splitext(fn)[1].lower() in VIDEO_EXTS:
                files.append(os.path.join(dirpath, fn))
    files.sort(key=lambda p: p.lower())
    return files


def _is_series_dir(folder):
    """True when a folder is itself one series: it has Season/Specials
    subfolders, or video files sitting directly inside it."""
    try:
        entries = list(os.scandir(folder))
    except OSError:
        return False
    for e in entries:
        if e.is_dir() and (
            _SEASON_DIR.match(e.name.strip()) or _SPECIALS_DIR.match(e.name.strip())
        ):
            return True
    for e in entries:
        if e.is_file() and os.path.splitext(e.name)[1].lower() in VIDEO_EXTS:
            return True
    return False


def scan(root):
    """Build the series/episode model. `root` may be a single show folder
    (Season subfolders / videos directly inside) or a folder of many shows."""
    # Decide whether root is one series or a library of series.
    if _is_series_dir(root):
        series_dirs = [root]
    else:
        series_dirs = [
            e.path for e in sorted(os.scandir(root), key=lambda e: e.name.lower())
            if e.is_dir()
        ]

    series_list = []
    episodes_by_id = {}
    next_series_id = 1
    next_ep_id = 1

    for folder in series_dirs:
        series = Series(
            next_series_id, _clean_series_name(os.path.basename(folder)), folder
        )
        next_series_id += 1

        seq = [0]  # boxed so _parse_se can bump the fallback counter
        for path in _video_files(folder):
            rel = os.path.relpath(path, folder)
            season, number, title = _parse_se(rel, seq)
            ep = Episode(next_ep_id, season, number, title, path)
            episodes_by_id[next_ep_id] = ep
            next_ep_id += 1
            series.episodes.append(ep)

        if series.episodes:
            series.episodes.sort(key=lambda e: (e.season, e.number))
            series_list.append(series)

    return series_list, episodes_by_id


class Handler(http.server.BaseHTTPRequestHandler):
    # Injected by main().
    series_list = []
    episodes_by_id = {}
    live_channels = []          # list[LiveChannel]
    live_by_id = {}             # id -> LiveChannel
    # Quirk flags (see module docstring).
    epg_map = False
    epg_shift = 0
    epg_plain = False
    no_short_epg = False
    typo_data_table = False
    no_hls = False
    no_ts = False

    def log_message(self, fmt, *args):
        sys.stderr.write("  %s\n" % (fmt % args))

    # ---- player_api.php ----------------------------------------------------

    def _json(self, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _auth_payload(self):
        return {
            "user_info": {
                "username": "test",
                "password": "test",
                "status": "Active",
                "exp_date": "4102444800",  # year 2100
                "is_trial": "0",
                "active_cons": "0",
                "max_connections": "1",
            },
            "server_info": {
                "url": self.headers.get("Host", "").split(":")[0],
                "port": str(self.server.server_address[1]),
                "https_port": "",
                "server_protocol": "http",
            },
        }

    def _series_list_payload(self):
        out = []
        for s in self.series_list:
            try:
                r5 = round(float(s.rating) / 2, 1) if s.rating else 0
            except ValueError:
                r5 = 0
            out.append({
                "num": s.id,
                "name": s.name,
                "series_id": s.id,
                "cover": s.poster or "",
                "plot": s.plot or f"{s.name} — {len(s.episodes)} episode(s).",
                "cast": s.cast or "",
                "director": "",
                "genre": ", ".join(s.genres) if s.genres else "",
                "releaseDate": f"{s.year}-01-01" if s.year else "",
                "last_modified": "0",
                "rating": s.rating or "",
                "rating_5based": r5,
                "backdrop_path": [s.backdrop] if s.backdrop else [],
                "youtube_trailer": "",
                "episode_run_time": "",
                "category_id": "1",
            })
        return out

    def _series_info_payload(self, series_id):
        series = next((s for s in self.series_list if s.id == series_id), None)
        if series is None:
            return {"info": {}, "episodes": {}, "seasons": []}

        episodes = {}
        seasons_seen = {}
        for ep in series.episodes:
            skey = str(ep.season)
            if ep.runtime_secs:
                dur_secs, dur_str = str(ep.runtime_secs), ""
            else:
                # No real runtime — send it as an HH:MM:SS string with
                # duration_secs "0" (exercises the app's fallback parse).
                dur_secs, dur_str = "0", "00:42:00"
            episodes.setdefault(skey, []).append({
                "id": str(ep.id),
                "episode_num": ep.number,
                "title": ep.title,
                "container_extension": ep.ext,
                "season": ep.season,
                "info": {
                    "plot": ep.plot or
                    f"{series.name} — S{ep.season:02d}E{ep.number:02d}.",
                    # lowercase key on purpose (the real-panel spelling)
                    "releasedate": ep.airdate or "",
                    "duration_secs": dur_secs,
                    "duration": dur_str,
                    "movie_image": ep.still or "",
                    "rating": series.rating or "",
                },
            })
            seasons_seen[ep.season] = seasons_seen.get(ep.season, 0) + 1

        seasons = [
            {
                "season_number": num,
                "name": "Specials" if num == 0 else f"Season {num}",
                "episode_count": str(cnt),
                "overview": "",
                "cover": series.poster or "",
                "cover_big": series.backdrop or series.poster or "",
            }
            for num, cnt in sorted(seasons_seen.items())
        ]

        return {
            "info": {
                "name": series.name,
                "plot": series.plot or series.name,
                "cast": series.cast or "",
                "genre": ", ".join(series.genres) if series.genres else "",
                "releaseDate": f"{series.year}-01-01" if series.year else "",
                "rating": series.rating or "",
                "cover": series.poster or "",
                "backdrop_path": [series.backdrop] if series.backdrop else [],
            },
            "episodes": episodes,
            "seasons": seasons,
        }

    # ---- live TV + EPG ------------------------------------------------------

    def _live_streams_payload(self):
        out = []
        for i, ch in enumerate(self.live_channels):
            out.append({
                "num": i + 1,
                "name": ch.name,
                "stream_type": "live",
                "stream_id": ch.id,
                "stream_icon": "",
                "epg_channel_id": ch.epg_channel_id,
                "added": "0",
                "category_id": ch.category_id,
                "custom_sid": "",
                "tv_archive": 1 if ch.id % 3 == 0 else 0,
                "direct_source": "",
                "tv_archive_duration": 3 if ch.id % 3 == 0 else 0,
            })
        return out

    def _epg_text(self, s):
        if self.epg_plain:
            return s
        return base64.b64encode(s.encode("utf-8")).decode("ascii")

    def _epg_listings(self, ch, limit=None, full=False):
        now = int(time.time())
        rows = epg_schedule(
            ch,
            hours_back=24 if full else 2,
            hours_fwd=48 if full else 6,
            shift_hours=self.epg_shift,
        )
        if limit is not None:
            # short_epg: from the currently-airing row onward (panel behavior)
            rows = [r for r in rows if r[1] > now - self.epg_shift * 3600 or full]
            rows = rows[:limit]
        listings = []
        for idx, (start, stop, title, desc) in enumerate(rows):
            listings.append({
                "id": str(ch.id * 100000 + idx),
                "epg_id": "7",
                "title": self._epg_text(title),
                "lang": "",
                # Panel-local time strings (we pretend panel TZ == UTC here).
                "start": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(start)),
                "end": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(stop)),
                "description": self._epg_text(desc),
                "channel_id": ch.epg_channel_id,
                "start_timestamp": str(start),
                "stop_timestamp": str(stop),
                **({"has_archive": 1} if full and stop < now else {}),
                **({"now_playing": 1} if start <= now < stop else {}),
            })
        if self.epg_map:
            # PHP assoc-array quirk: an OBJECT keyed by stringified index.
            return {str(i): row for i, row in enumerate(listings)}
        return listings

    def _handle_epg_action(self, qs, action):
        if self.no_short_epg:
            return self._json({"epg_listings": []})
        # Old-panel typo mode: only the misspelled action has data.
        if self.typo_data_table and action == "get_simple_data_table":
            return self._json({"epg_listings": []})
        sid = (qs.get("stream_id") or ["0"])[0]
        try:
            ch = self.live_by_id.get(int(sid))
        except ValueError:
            ch = None
        if ch is None or not ch.epg_channel_id:
            return self._json({"epg_listings": []})
        if action == "get_short_epg":
            limit = 4
            try:
                limit = int((qs.get("limit") or ["4"])[0])
            except ValueError:
                pass
            return self._json(
                {"epg_listings": self._epg_listings(ch, limit=limit)}
            )
        return self._json({"epg_listings": self._epg_listings(ch, full=True)})

    def _serve_xmltv(self):
        """Whole-account XMLTV guide (xmltv.php), gzip-encoded like real
        panels serve it."""
        parts = ['<?xml version="1.0" encoding="UTF-8"?>\n<tv>']
        for ch in self.live_channels:
            if not ch.epg_channel_id:
                continue
            parts.append(
                f'<channel id="{html.escape(ch.epg_channel_id)}">'
                f"<display-name>{html.escape(ch.name)}</display-name>"
                f"</channel>"
            )
        for ch in self.live_channels:
            if not ch.epg_channel_id:
                continue
            for start, stop, title, desc in epg_schedule(
                ch, hours_back=24, hours_fwd=48, shift_hours=self.epg_shift
            ):
                st = time.strftime("%Y%m%d%H%M%S", time.gmtime(start))
                en = time.strftime("%Y%m%d%H%M%S", time.gmtime(stop))
                parts.append(
                    f'<programme start="{st} +0000" stop="{en} +0000" '
                    f'channel="{html.escape(ch.epg_channel_id)}">'
                    f"<title>{html.escape(title)}</title>"
                    f"<desc>{html.escape(desc)}</desc></programme>"
                )
        parts.append("</tv>")
        body = gzip.compress("".join(parts).encode("utf-8"))
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        # Real panels serve the gzip FILE (magic bytes), not Content-Encoding.
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _serve_m3u(self, host):
        """get.php M3U export of the live channels, tvg-ids included —
        exercises the app's M3U-from-Xtream path."""
        lines = ['#EXTM3U']
        for ch in self.live_channels:
            lines.append(
                f'#EXTINF:-1 tvg-id="{ch.epg_channel_id}" tvg-name="{ch.name}" '
                f'group-title="Mock Live",{ch.name}'
            )
            lines.append(f"http://{host}/live/test/test/{ch.id}.ts")
        body = "\n".join(lines).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "audio/x-mpegurl")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _handle_api(self, qs):
        action = (qs.get("action") or [""])[0]
        if not action:
            return self._json(self._auth_payload())
        if action == "get_series_categories":
            return self._json([{"category_id": "1", "category_name": "Local Series"}])
        if action == "get_series":
            return self._json(self._series_list_payload())
        if action == "get_series_info":
            sid = (qs.get("series_id") or ["0"])[0]
            try:
                sid = int(sid)
            except ValueError:
                sid = 0
            return self._json(self._series_info_payload(sid))
        if action == "get_live_categories":
            return self._json([
                {"category_id": "10", "category_name": "Mock News"},
                {"category_id": "11", "category_name": "Mock Sports"},
            ])
        if action == "get_live_streams":
            return self._json(self._live_streams_payload())
        if action in (
            "get_short_epg",
            "get_simple_data_table",
            "get_simple_date_table",  # the real-world legacy typo alias
        ):
            return self._handle_epg_action(qs, action)
        if action == "get_vod_categories":
            return self._json([])
        if action == "get_vod_streams":
            return self._json([])
        return self._json([])

    # ---- /series/{user}/{pass}/{id}.{ext} stream ---------------------------

    def _serve_stream(self, path):
        # /series/<user>/<pass>/<id>.<ext>
        parts = path.strip("/").split("/")
        if len(parts) != 4:
            self.send_error(404)
            return
        filepart = parts[3]
        id_str = os.path.splitext(filepart)[0]
        try:
            ep_id = int(id_str)
        except ValueError:
            self.send_error(404)
            return
        ep = self.episodes_by_id.get(ep_id)
        if ep is None or not os.path.isfile(ep.path):
            self.send_error(404)
            return
        self._serve_file_with_range(ep.path)

    def _serve_file_with_range(self, filepath):
        size = os.path.getsize(filepath)
        ctype = mimetypes.guess_type(filepath)[0] or "application/octet-stream"
        rng = self.headers.get("Range")
        start, end = 0, size - 1
        status = 200
        if rng:
            m = re.match(r"bytes=(\d*)-(\d*)", rng)
            if m:
                if m.group(1):
                    start = int(m.group(1))
                if m.group(2):
                    end = int(m.group(2))
                start = max(0, start)
                end = min(end, size - 1)
                status = 206
        length = end - start + 1

        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if self.command == "HEAD":
            return
        with open(filepath, "rb") as f:
            f.seek(start)
            remaining = length
            chunk = 64 * 1024
            try:
                while remaining > 0:
                    data = f.read(min(chunk, remaining))
                    if not data:
                        break
                    self.wfile.write(data)
                    remaining -= len(data)
            except (BrokenPipeError, ConnectionResetError):
                pass  # player seeked / closed — normal

    # ---- /live/{user}/{pass}/{id}.{ts|m3u8} stream -------------------------

    def _serve_live(self, path):
        parts = path.strip("/").split("/")
        if len(parts) != 4:
            self.send_error(404)
            return
        stem, ext = os.path.splitext(parts[3])
        ext = ext.lstrip(".").lower()
        if ext == "m3u8" and self.no_hls:
            self.send_error(404)
            return
        if ext == "ts" and self.no_ts:
            self.send_error(404)
            return
        if ext not in ("ts", "m3u8"):
            self.send_error(404)
            return
        try:
            ch = self.live_by_id.get(int(stem))
        except ValueError:
            ch = None
        if ch is None or not os.path.isfile(ch.path):
            self.send_error(404)
            return
        # Both extensions just serve the backing file — enough for probes and
        # for the preview/player to actually show frames.
        self._serve_file_with_range(ch.path)

    # ---- routing -----------------------------------------------------------

    def _route(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path.endswith("player_api.php"):
            return self._handle_api(urllib.parse.parse_qs(parsed.query))
        if parsed.path.endswith("xmltv.php"):
            return self._serve_xmltv()
        if parsed.path.endswith("get.php"):
            return self._serve_m3u(self.headers.get("Host", "localhost"))
        if parsed.path.startswith("/live/"):
            return self._serve_live(parsed.path)
        if parsed.path.startswith("/series/"):
            return self._serve_stream(parsed.path)
        if parsed.path in ("/", ""):
            body = b"Mock Xtream server running. Point Debrify at this host."
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)
            return
        self.send_error(404)

    def do_GET(self):
        self._route()

    def do_HEAD(self):
        self._route()


class ThreadingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


_FLAGS = {
    "--no-enrich", "--epg-map", "--epg-plain", "--no-short-epg",
    "--typo-data-table", "--no-hls", "--no-ts",
}


def main():
    argv = sys.argv[1:]
    args = []
    epg_shift = 0
    skip_next = False
    for i, a in enumerate(argv):
        if skip_next:
            skip_next = False
            continue
        if a == "--epg-shift" or a.startswith("--epg-shift="):
            value = a.split("=", 1)[1] if "=" in a else (
                argv[i + 1] if i + 1 < len(argv) else None
            )
            skip_next = "=" not in a
            try:
                epg_shift = int(value)
            except (TypeError, ValueError):
                print(f"--epg-shift needs an integer hour count, got: {value!r}")
                sys.exit(2)
        elif a not in _FLAGS:
            args.append(a)
    do_enrich = "--no-enrich" not in argv
    if not args:
        print(__doc__)
        sys.exit(1)
    root = os.path.abspath(os.path.expanduser(args[0]))
    port = int(args[1]) if len(args) > 1 else 8888
    if not os.path.isdir(root):
        print(f"Media folder not found: {root}")
        sys.exit(1)

    series_list, episodes_by_id = scan(root)

    if do_enrich and series_list:
        print("Enriching from TVMaze (real posters/plots/stills)… "
              "use --no-enrich to skip")
        enrich(series_list)

    live_channels = build_live_channels(episodes_by_id)

    Handler.series_list = series_list
    Handler.episodes_by_id = episodes_by_id
    Handler.live_channels = live_channels
    Handler.live_by_id = {c.id: c for c in live_channels}
    Handler.epg_map = "--epg-map" in argv
    Handler.epg_shift = epg_shift
    Handler.epg_plain = "--epg-plain" in argv
    Handler.no_short_epg = "--no-short-epg" in argv
    Handler.typo_data_table = "--typo-data-table" in argv
    Handler.no_hls = "--no-hls" in argv
    Handler.no_ts = "--no-ts" in argv

    ip = lan_ip()
    print("=" * 64)
    print("Mock Xtream server")
    print(f"  Media root : {root}")
    print(f"  Series     : {len(series_list)}")
    for s in series_list:
        seasons = sorted({e.season for e in s.episodes})
        art = "art✓" if s.poster else "art✗"
        print(f"    - {s.name}: {len(s.episodes)} ep, seasons {seasons} [{art}]")
    if not series_list:
        print("    (none found — check the folder layout in this script's header)")
    print(f"  Live       : {len(live_channels)} synthetic channels "
          f"(EPG: short_epg={'off' if Handler.no_short_epg else 'on'}, "
          f"shift={epg_shift}h, map={Handler.epg_map}, plain={Handler.epg_plain})")
    print("-" * 64)
    print("In Debrify -> IPTV settings -> Xtream Codes, add:")
    print(f"  Server URL : http://{ip}:{port}")
    print("  Username   : test")
    print("  Password   : test")
    print("M3U-from-Xtream path: add a URL playlist pointing at")
    print(f"  http://{ip}:{port}/get.php?username=test&password=test&type=m3u_plus")
    print("=" * 64)

    ThreadingServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()

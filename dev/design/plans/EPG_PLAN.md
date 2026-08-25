# IPTV EPG — Now/Next + Per-Channel Schedule

Per-channel EPG via Xtream's per-stream endpoints (`get_short_epg` /
`get_simple_data_table`) — no database, no XMLTV download, no grid. Credentials
are recovered from each channel's own stream URL, so guide data works with zero
playlist plumbing in every surface, including the native player over the
bridge. Channels without guide data render exactly as before.

**Status: BUILT (uncommitted) — all three steps: Xtream (1), players (2),
and XMLTV for plain M3U playlists (3).**

## What was built

### Core
- `lib/services/iptv_epg_service.dart` — `IptvEpgService`: parses
  `server/live/user/pass/id.m3u8|.ts` (and the legacy un-prefixed form) back
  into Xtream credentials; `nowNext(url)` + `schedule(url)`; base64-decodes
  titles/descriptions; prefers epoch timestamps over local-time strings;
  LRU caches (now/next valid until the airing programme ends, empty answers
  held 5 min; schedules 30 min), in-flight coalescing. Failures → empty, never
  errors.

### IPTV page (TV two-pane)
- Rail: `IptvRailEpgCard` under the channel identity — NOW tag + time range,
  title, progress bar, "Xm left", description, NEXT line. Fetch on focus
  (250 ms debounce, cache-first), 30 s ticker advances the bar and rolls over
  programme boundaries. Static skeleton, no shimmer.
- RIGHT on a channel row → `IptvSchedulePane` swaps the right pane in place
  (preview keeps playing). Day-grouped, NOW highlighted + autofocused,
  BACK/LEFT/escape closes and refocuses the originating row.
- Rail hints line gains "▶ Guide" when the focused channel is EPG-capable.

### Phone
- Calendar icon on rows (touch always, desktop on hover) →
  `showIptvScheduleSheet` bottom sheet, same day-grouped list, auto-scrolled
  to now.

### In-app player (Dart)
- `iptv_channel_sheet.dart` tiles: sub-line shows "Now: <title>" (falls back
  to group). Per-tile lazy fetch = naturally viewport-scoped; handles element
  recycling.

### Native TV player (Kotlin)
- Bridge: new `requestIptvEpg` case in `android_tv_player_bridge.dart`
  (native sends channelUrl, Dart answers now/next/schedule maps — stateless,
  mirrors `requestIptvStreamUrls`).
- Guide overlay rows: accent "Now: <title>" line, fetched lazily on bind with
  partial-bind payload (`PAYLOAD_EPG`); stale entries (programme ended)
  re-fetch on next bind.
- Now-playing header: "Now: X › Next: Y" line.
- RIGHT on a guide row → schedule dialog (day headers, airing row highlighted
  + scrolled to, BACK dismisses back to the guide).

### XMLTV (plain M3U playlists) — step 3
- `lib/services/xmltv_epg_source.dart` — streams the (often gzipped, up to
  300 MB) guide to a temp file; parses in `Isolate.run` with `xml_events`
  streaming (never `XmlDocument.parse`); keeps only playlist tvg-ids within
  −6 h..+48 h, ≤80 rows/channel, 120k rows total, descriptions truncated;
  snapshots the filtered index to `epg_cache/` (12 h TTL, stale-snapshot
  fallback when a refresh fails). Unit tests in
  `test/xmltv_epg_source_test.dart` (offsets, CDATA, gzip, filtering).
- Guide URL: user-entered per playlist (`IptvPlaylist.epgUrl`, new optional
  field in the settings URL tab) wins over the playlist's own
  `#EXTM3U url-tvg=`/`x-tvg-url=` header (now parsed by `m3u_parser.dart`).
- `IptvEpgService` gained an XMLTV context (one active playlist at a time,
  set from `_loadPlaylist`): channel-URL → tvg-id map + in-memory programme
  index. now/next is computed live from the index on every ask, so
  programmes roll with zero refetching. `contextVersion` notifier repaints
  the rail and re-arms row affordances when a slow first download lands.
- Every existing surface (rail, schedule pane, phone sheet, both players via
  the same service/bridge) works unchanged on XMLTV channels. Favorites view
  loses M3U EPG (rebuilt channels carry no tvg-id) — known, acceptable.
- Note: the default iptv-org playlist declares no url-tvg and iptv-org no
  longer hosts prebuilt guides — users must supply a guide URL for it.

## Testing checklist (TV unless noted)
1. Xtream playlist → focus a live channel → rail shows now/next within ~1s;
   progress bar sane; arrowing quickly doesn't spam (debounce).
2. RIGHT on a row → schedule pane; preview keeps playing; UP/DOWN walks rows;
   BACK returns focus to the same row. LEFT also closes (sidebar still opens
   via LEFT from the normal list).
3. M3U playlist / Stremio channels / VOD view → no EPG UI anywhere, nothing
   broken.
4. Favorites view with starred Xtream channels → EPG works there too (URL
   carries the creds).
5. Native player → Guide: rows fill in "Now:" lines as they scroll into view;
   header shows now/next for the playing channel; RIGHT on a row → schedule
   dialog; BACK once = dialog, twice = guide.
6. Phone: calendar icon on Xtream rows → bottom sheet schedule; in-player
   channel sheet shows "Now:" lines.
7. XMLTV: add an M3U playlist with an EPG URL (or one whose header declares
   url-tvg) → after the first download (can take a minute for big guides),
   rows gain the guide affordance, rail shows now/next, schedules open;
   restart the app → guide is instant (disk snapshot, no re-download);
   playlist without EPG URL → nothing changes anywhere.

## Deferred / next steps
- Page rows intentionally have NO now-line (Xtream's per-channel endpoint
  would need viewport-batched fetching; rail covers the focused channel).
  For XMLTV playlists the data is local, so row now-lines would be free —
  possible later polish.
- Name-based fuzzy matching for playlists whose channels lack tvg-ids
  (deliberately skipped — tvg-id only).
- Day picker in schedules (currently shows whatever horizon the source
  serves, capped at +48 h for XMLTV).
- Favorites view: M3U channels lose EPG there (no tvg-id on rebuilt
  channels); could persist tvg-id into the favorites store later.

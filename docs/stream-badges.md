# Stream badges

Settings › **Play Loader** › **Stream badges**. Import a Nuvio-style
`badges.json` and every source row — the detail screen's Sources list,
keyword search results, the in-player source picker — gains small chips for
whatever its rules match: provider, release format, resolution, HDR flavour,
audio codec and channels, language flags.

Rulesets come from a link (refreshable later), a file, or pasted text.
Several can be active at once and apply in list order; each can be disabled
or deleted, and the page has an on/off switch for the whole feature.
While enabled presets contain active valid rules, imported badges replace
Debrify's built-in format/quality tags, including for sources with no match.
Disabling the feature or all active rules restores the built-in tags. Cache
status, size, seeders, coverage, and playing indicators remain visible.
Rulesets are stored per profile and are included in Backup & Restore and in
Remote's Send Setup and Transfer Everything (the `streamBadges` payload in
both).

## File format

The Nuvio Badge Studio format, unchanged:

```json
{
  "groups": [
    { "id": "gq", "name": "Quality", "color": "#FF27C04F", "isExpanded": true }
  ],
  "filters": [
    {
      "id": "q-r", "groupId": "gq", "name": "Remux", "type": "filter",
      "pattern": "(?i)\\bremux\\b", "isEnabled": true,
      "imageURL": "https://…/remux.png",
      "tagColor": "#E600E932", "tagStyle": "filled",
      "textColor": "#27C04F", "borderColor": "#FF00FF37"
    }
  ]
}
```

- `pattern`: a regular expression. A leading `(?i)` makes it
  case-insensitive (Dart's engine has no inline flags, so the prefix is
  translated). Lookahead, lookbehind and Unicode ranges work. A pattern the
  engine rejects is reported at import and never matches; it does not break
  the rest of the file.
- A rule matches when its pattern hits the source's **name** or its
  **description** — the Badge Studio's semantics. For an addon stream the
  name is `behaviorHints.filename` when the addon supplies one, otherwise the
  stream title; the description is the addon's short label
  ("Torrentio 4K RD+") followed by its description block.
- `imageURL`: shown instead of text when present (the name is shown if the
  image fails to load). Otherwise the chip is `name` in small bold capitals.
- `tagStyle`: `filled` paints `tagColor`; `outlined` draws `borderColor`
  (`tagColor` when unset); `filled and bordered` does both. `textColor`
  colours the label. Colours are `#RRGGBB` or Android-style `#AARRGGBB`;
  fully transparent values count as absent.
- `isEnabled: false` rules are kept but inactive.

## SVG artwork

`imageURL` supports ordinary bitmap images and static SVG badges in both
Flutter source lists and Android TV's native source picker. SVG links can
include query parameters; extensionless artwork links also try SVG decoding
if bitmap decoding fails. Existing PNG and other bitmap rendering is unchanged.

SVGs are decoded off the UI thread and rasterized to small, aspect-ratio-preserving
bitmaps, shared through the platform's image cache. Moving focus does not parse
the artwork again. Flutter also caches up to 64 downloaded SVG files; native TV
caches the rendered bitmaps on disk.

This supports simple self-contained vector artwork, including paths, gradients,
and clipping, rather than every browser SVG feature. Files must be UTF-8 and
at most 128 KiB. Scripts, animation, document entities, external resources,
embedded images, `use`, patterns, markers, and filters are not supported. SVGs
containing `<style>` stylesheets are rejected on both platforms: the Flutter
renderer ignores those rules, which would silently change the artwork's colours.
Presentation attributes and inline `style` colours/local references are supported;
inline declarations are converted to presentation attributes before validation
and rendering. Comments never reach a renderer's CSS parser, inline colours win
over presentation attributes regardless of XML order, and `!important` precedence
is preserved. CSS cannot supply structural SVG attributes such as `id` or `href`.
CSS escapes are rejected. Markers are excluded because their per-vertex and
inherited rendering work is not covered by the reference budget.
Dash patterns are also rejected in attributes and inline styles, including on
ancestors: a tiny SVG can expand into an arbitrarily large vector path before
bitmap sizing. The explicit solid-stroke setting `stroke-dasharray="none"`
remains supported.
Both paths preflight XML depth before building a tree, normalize namespaces and
local references, and reject duplicate IDs. Editor annotations cannot accidentally
become rendering attributes. Structure and reference-expansion limits include
geometry size, repeated uses, and the native renderer's two passes per mask,
rejecting expensive mask chains. Only the resulting normalized XML is rendered.
Unsupported,
oversized, or unavailable artwork shows the rule's text label, keeping the badge
and navigation usable.

The shared `test/fixtures/stream_badge_svg_contract.json` corpus is exercised by
both the Flutter compiler/pixel tests and Android's real SVG decoder. These cover
comment/namespace bypasses, reference cycles, colour precedence, quoted references,
and ordinary artwork. Separate tests retain network limits, fallback, warm-cache,
and D-pad focus coverage. Native tests also select Android's DOM implementation
explicitly for the deep-XML regression; the desktop JDK parser behaves differently.

## Why `Torrent` carries the addon's label and description

`Torrent.name` on its own is not enough to match against. It holds the
filename (or the stream title), while community rulesets identify providers
and languages from the text the addon itself writes: the short stream label
("Torrentio 4K RD+") and the description block (seeders, size, language
flags). So `Torrent` keeps `streamLabel` and `streamDescription` alongside
`name`, and `Torrent.badgeDescription` joins them into the matcher's
description input. Non-addon sources leave both null and match on `name`
alone.

## Code

| Piece | Where |
|---|---|
| Ruleset model, parser, colour and pattern helpers | `lib/models/stream_badge_rules.dart` |
| Matcher (name-or-description, memoised) | `lib/services/stream_badge_matcher.dart` |
| Store, import (link/file/paste), refresh, backup, live matcher | `lib/services/stream_badges_service.dart` |
| Chip widgets (`StreamBadgeStrip`, `StreamBadgeStripFor`, `StreamBadgeChip`) | `lib/widgets/stream_badge_strip.dart` |
| SVG validation and cached bitmap decoding | `lib/utils/stream_badge_svg.dart`, `lib/services/stream_badge_svg_image.dart`, `android/app/src/main/kotlin/com/debrify/app/tv/StreamBadgeSvg.kt` |
| Settings page | `lib/screens/settings/stream_badges_settings_page.dart` |
| Row model (`streamLabel`, `streamDescription`, `badgeDescription`) | `lib/models/torrent.dart`, `lib/services/stremio_service.dart` |
| Rendering sites (`badgeName`/`badgeDescription` on `SourceRow`) | `lib/widgets/source_row.dart`, `lib/screens/video_player/widgets/source_sheet.dart` |
| Tests | `test/stream_badges_test.dart` |

## Storage and transfer reliability

The combined encoded preset inventory is limited to **128 KiB per profile**.
Imports that exceed this limit, or the device's remaining preference-storage
budget, fail without reporting a successful save. Downloads stop at 4 MiB;
this is an input safety limit, not a promise that a 4 MiB preset can be stored.

Imports remain bound to their initiating profile. Concurrent edits are
serialized, and a refresh cannot resurrect a preset deleted while downloading.
WebDAV changes refresh the active matcher without restarting the profile.
Selective remote transfers include the master switch when the authenticated
receiver advertises protocol v7 or newer. Older receivers receive the legacy
source array, which leaves their master switch unchanged. New receivers accept
both formats; pairing and the minimum version for other transfers are unchanged. Whole-profile backups retain both keys.
Corrupt optional badge data does not prevent startup; the settings page offers
retry and an explicit reset.

## Matching and player rendering

Rule execution runs in a dedicated worker isolate, shared by Flutter source
rows and Android TV's native source browser. The first source match has a
two-second cold-execution deadline; subsequent matches have 500 ms. An overrun
or worker failure terminates that matcher and completes pending requests without blocking navigation. The settings page
reports the stopped matcher. Changing the presets creates a fresh matcher.
Worker startup is bounded to three seconds and preparation has a separate
five-second deadline. Both paths share the same pattern compiler. Inventories
allow up to 512 active, valid rules across enabled presets; existing oversized inventories show a settings warning
and can be reduced or disabled without truncating saved data. Source name and
description inputs over 8192 characters are skipped
rather than truncated into misleading matches. The cache holds 400 results and
the request queue holds at most 64 pending entries. Saturated queues defer
new requests without evicting admitted work. Mounted Flutter rows retry deferred
admission; disposed rows stop retrying. Native pickers cache only resolved
outcomes, including confirmed empty matches. Unresolved native requests retry
with backoff up to ten seconds while visible. Hiding or destroying the picker
cancels pending requests, retry timers and scroll animations. Unchanged badge
configuration retains its matcher across preference refreshes.

Text and image chips have bounded widths and wrap below source titles. Both
honor the preset's filled/outlined/bordered style. Image pixels retain their
original colours: black artwork can use the preset's yellow or white fill.
Missing fills use a dark backing; translucent fills are composited on that
backing so row focus cannot change their contrast. Text and image loading/error
labels retain the requested text colour when readable, otherwise use black or
white for contrast. Flutter and native TV share these resolved display colours.
Artwork uses compact aspect-ratio widths instead of equal-width native slots.
Source-list tiles are 24 pixels high (26 on Flutter TV), with six-pixel gaps,
consistent rounded corners, and a subtle outline unless the preset supplies one.
Image loading/error labels keep the chip height stable. Flutter badges expose
their full names to screen readers and pointer tooltips; truncated text uses an
ellipsis. Every match remains visible through wrapping, without extra TV focus
stops or disclosure controls.
Android TV requests matches only for visible rows, checks the playback session,
and ignores results from a closed browser generation. Artwork falls back to its
label if loading fails. Badge updates do not invoke source selection or move
focus. Row growth preserves the selected source position; active keyboard
scroll animations are retargeted to the new layout. Flutter touch/wheel
scrolling remains under user control. Native pending-request timers are canceled when the picker
closes.

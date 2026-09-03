# Stream badges

Settings › **Play Loader** › **Stream badges**. Import a Nuvio-style
`badges.json` and every source row — the detail screen's Sources list,
keyword search results, the in-player source picker — gains small chips for
whatever its rules match: provider, release format, resolution, HDR flavour,
audio codec and channels, language flags.

Rulesets come from a link (refreshable later), a file, or pasted text.
Several can be active at once and apply in list order; each can be disabled
or deleted, and the page has an on/off switch for the whole feature.
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
| Settings page | `lib/screens/settings/stream_badges_settings_page.dart` |
| Row model (`streamLabel`, `streamDescription`, `badgeDescription`) | `lib/models/torrent.dart`, `lib/services/stremio_service.dart` |
| Rendering sites (`badgeName`/`badgeDescription` on `SourceRow`) | `lib/widgets/source_row.dart`, `lib/screens/video_player/widgets/source_sheet.dart` |
| Tests | `test/stream_badges_test.dart` |

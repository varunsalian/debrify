# Quick Play Filter Ladder — Plan

Make the Home/Search **Play** button honor the user's default filters
(quality / rip source / audio language) as a **tiered preference**: try a full
match first, relax one dimension at a time, and finally accept anything
playable — with the Pipeline loading overlay narrating each step
("Matching your filters… → No English match, relaxing language… → …").

Stremio TV is explicitly **out of scope** — it has its own preferred-quality
system and stays untouched.

---

## 1. Current state (research findings)

### The filters
- Model: `lib/models/torrent_filter_state.dart` — three independent sets:
  `Set<QualityTier> qualities` (ultraHd/fullHd/hd/sd),
  `Set<RipSourceCategory> ripSources` (web/bluRay/hdrip/dvdrip/cam/other),
  `Set<AudioLanguage> languages` (12 languages + multiAudio).
  `isEmpty` == no filtering.
- Classifiers (all parse the torrent **name**):
  - `Torrent.qualityTier` extension — `torrent_result_row.dart:523`. Pixel
    tokens win (2160p/1080p/720p/480p), keyword fallbacks (4k/uhd/fullhd/hd),
    **defaults to `sd` when nothing matches** (never null).
  - `TorrentFilterMatcher.detectRipSource` — `torrent_filter_matcher.dart:36`.
    Defaults to `RipSourceCategory.other` (never null).
  - `TorrentFilterMatcher.detectAudioLanguage` — `torrent_filter_matcher.dart:64`.
    **Returns null when no token found** — and most release names carry no
    language token (English releases rarely tag "ENG"). `_matches` rejects
    null when a language filter is active. This is the single biggest
    correctness trap (see §3.3).
- Persistence: `StorageService.getDefaultFilterQualities/RipSources/Languages`
  (`storage_service.dart:4069+`), edited in
  `settings/filter_settings_page.dart`, loaded by the Search tab into its
  toolbar state.
- Applied today ONLY in two visible lists: keyword results
  (`search_screen.dart:2751`) and the Sources browse toolbar
  (`search_screen.dart:8580` `_applyToolbar`). **Never on any play path.**

### The quick-play pipeline (`lib/services/torrent_playback_service.dart`)
`playFromSelection` (line 523):
1. non-`tt` id → `_playAddonStream` (line 844) → Stremio-inclusive search →
   `playBest`.
2. bound source → `_playViaBound` (explicit user pin — plays as-is).
3. provider pick → Pipeline overlay up.
4. series pack-first path (line 607) → `searchByImdbWithStremio` →
   `_curatePackCandidates` (coverage/seeders sort) → `_cacheFirst` → probe.
5. episode/movie search → `searchByImdb` (engines) → `_curateCandidates`
   (title match → episode relevance → RD-blocked) → **[new since last
   commit]** empty ⇒ `searchStremioAddonsOnly` fallback → `playBest`.

`playBest` (line 311):
- plays the **first** `directUrl` stream immediately (no validation, no
  ordering) — line 335;
- else filters to acquirable non-external candidates, `_cacheFirst` for
  TorBox/Premiumize, then `_probeCandidates` (line 454) walks the list in
  order, capped at 1 attempt (or Quick-Play "try multiple" max, PikPak
  always 1).

**Ordering is everything**: the probe cap means whatever sorts first gets the
(often only) attempt. So the ladder is implemented as *ordering + selection*,
not as re-searching.

### The loading overlay (`lib/widgets/pipeline_loading_overlay.dart`)
Handle-based; `setStage(stage, {sourceCount, cachedCount})` drives a
checklist. **No free-text capability today** — needs a small `setNote()`
API for the narration the user asked for. Rebuild scope is already
ValueNotifier-based, so a note rides the same notifier cheaply.

---

## 2. UX contract (what the user asked for)

1. Quick Play honors the saved default filters **strictly first**.
2. If no source satisfies all of them, relax **one dimension at a time** and
   retry (no re-search — same result set, looser match).
3. If nothing matches any tier, play **anything playable** (today's behavior).
4. Every step is **visible in the loading screen**: what we're looking for,
   what we relaxed, what we ended up using. No silent downgrades.

---

## 3. Design

### 3.1 `FilterLadder` (new, `lib/utils/filter_ladder.dart`)
Pure, unit-testable. Built once per play from the saved defaults:

```dart
class FilterLadder {
  final TorrentFilterState filters;      // saved defaults
  final List<TorrentFilterState> tiers;  // strict → loose, last == empty
  // tierOf(t): index of the FIRST tier t satisfies (0 = full match).
  // order(list): stable sort by tierOf, preserving in-tier order.
  // describeTier(i): human copy for the overlay ("without language match").
  // counts(list): per-tier counts for the overlay note.
}
```

**Relaxation order** (drop the least-reliable signal first, keep the most
user-visible longest):

| Tier | Constraint set |
|---|---|
| 0 | quality + ripSource + language (all active dimensions) |
| 1 | drop **language** (name-based detection is unreliable) |
| 2 | drop **ripSource** |
| 3 | drop **quality** ⇒ unrestricted (always present, = "anything playable") |

Tiers are generated **only for active dimensions** — a user with only a
quality filter gets a 2-tier ladder (quality → any); empty filters give a
1-tier ladder and the whole feature becomes a no-op (zero overhead, zero
notes — critical so users without filters see no change at all).

### 3.2 Matching rules
Reuse the existing classifiers verbatim (`qualityTier`, `detectRipSource`,
`detectAudioLanguage`) so quick-play can never disagree with the badges and
the Sources-list filter. One deliberate divergence:

### 3.2b Real-world corpus findings (689 live names, 10 titles, apibay)
Validated 2026-07-15 against real release names (torrents-csv was down; The
Pirate Bay API used instead — mainstream US film/series, Bollywood, anime).
Faithful Python ports of the three classifiers, full numbers in §5.0. Four
consequences are folded into the design below:

1. **89% of names carry NO language token** (611/689). With naive null=reject,
   a "1080p + WEB/BluRay + English" preset matches **1 of 689** names at
   tier 0; with the §3.3 rule it matches 240. The rule is load-bearing.
2. **Bare `.WEB.` names classify as `other`** — 17/689 modern releases like
   `The.Penguin.S01E01.2160p.WEB.H265` miss every token in
   `detectRipSource` ('web ' has a trailing space; dotted names never match).
   Fix in the shared classifier (§3.2c).
3. **Dual-audio tag lists defeat first-match-wins language detection**:
   `…ENG.LATINO.HINDI…` returns `hindi` (list order), so an English filter
   wrongly demotes a release that HAS English audio. Ladder-side fix (§3.3b).
4. **1080p CAMs would outrank proper releases**: with "1080p + WEB" filters,
   `Oppenheimer 1080p TELESYNC` lands tier 2 (quality matches, rip relaxed)
   ABOVE a 2160p BluRay remux at tier 3 (quality mismatch). 34/689 corpus
   names are cam/telesync, most tagged 1080p. Cam demotion rule (§3.3c).

### 3.2c Shared classifier fix: bare WEB token
Add a word-boundary fallback to `detectRipSource`'s web family:
`RegExp(r'\bweb\b')` — checked AFTER the existing substring tokens and after
the bluray family (so `…WEB…BluRay…` stays bluray, order already guarantees
it). Accepted false positive: a title containing the word "Web"
(e.g. *Charlotte's Web*) with no other rip token classifies as web instead of
other — harmless, and earlier families still win when present. This changes
the browse-list badge and Sources filter too (desirable — same 17/689 names
are currently unfilterable there); keep in sync with `FormatTagDetector` per
the existing comment in `qualityTier`.

### 3.3 Unknown language ≠ wrong language
`detectAudioLanguage == null` means "the name doesn't say", not "not
English". The browse list rejecting null is defensible (user is looking at a
list); auto-play rejecting null would exclude *most English releases* when an
English filter is set, and **every** addon direct link (their names are
quality labels). Rule for the ladder:

- **null language counts as a match when `AudioLanguage.english` is among the
  selected languages** (English is the unmarked default of release naming);
- if the user selected only non-English languages, null is NOT a match
  (someone filtering for Hindi audio doesn't want unmarked releases) — those
  land in tier 1.

This is the one semantic judgment call in the plan; it's isolated in a single
`_langMatches()` helper with a comment, easy to flip. **Corpus-confirmed
mandatory**: without it, tier 0 for an English preset is 1/689 (§3.2b.1).

### 3.3b Ladder language matching scans ALL tokens (not first-match-wins)
`detectAudioLanguage` returns the FIRST language in its fixed list — fine for
a single badge, wrong for matching: `Dune…ENG.LATINO.HINDI…` detects `hindi`
and would fail an English filter despite carrying English audio (§3.2b.3;
these multi-audio releases are common in the corpus). The ladder's
`_langMatches` therefore does its own scan: a name matches when **any
selected language's token pattern** appears (reusing the same per-language
regexes), when it carries a multi-audio tag (`multiAudio` satisfies ANY
selection), or via the §3.3 null-English rule. The shared
`detectAudioLanguage` stays untouched — badges and the browse filter keep
their current behavior.

### 3.3c Cam demotion (absolute floor)
Unless the user explicitly selected `cam` in their rip-source filter,
cam-classified candidates (`detectRipSource == cam` — corpus shows the
detector is accurate: all 34 hits were genuine CAM/HDCAM/TELESYNC/TS) sort
**below every tier**, as a floor bucket after tier N. Rationale from data:
quality tags on cams are common ("1080p TELESYNC"), so without this a cam
outranks any proper release whose quality mismatches the filter — nobody
setting "1080p + WEB" wants a telecine picked over a 2160p remux. They remain
playable (floor, not excluded), narrated as "playing best available".

### 3.4 Where the ladder plugs in (all inside `torrent_playback_service.dart`)

| Site | Change |
|---|---|
| `playFromSelection` episode/movie list (after `_curateCandidates`, incl. the addon fallback) | `ladder.order(torrents)` before `playBest`; report tier counts to overlay. |
| `playBest` direct-URL pick (line 335) | Instead of "first direct wins": compute the best occupied tier across ALL candidates; pick a direct stream **only from that tier** (first one in it). Direct still beats torrents *within the same tier*, but a full-match torrent now beats a tier-3 direct link. |
| `playBest` probe list | `_cacheFirst` becomes **per-tier**: partition by tier, cache-sort within each, concatenate. Filter preference dominates cachedness; instant-play still wins inside a tier. |
| `_probeCandidates` | Accept an optional `onCandidate(Torrent t)` callback so the flow can update the overlay note when probing crosses a tier boundary ("Exact match wasn't playable — trying without language…"). |
| Series pack path `_curatePackCandidates` (line 779) | Add tier as the PRIMARY sort key, before coverage/seeders. Rationale: the winning pack gets **pinned** by auto-bind — a wrong-quality pack would lock every future episode to it. Strictness matters most here. |
| `_playAddonStream` (non-`tt` ids) | Gets the ladder for free via `playBest`; also pass tier counts to its overlay. |
| `_playViaBound` | **Skipped on purpose** — a pinned source is an explicit user choice that outranks defaults. |
| Next-episode advance | Re-enters `playFromSelection` → inherited. |

Filters load once per play via the three `StorageService.getDefaultFilter*`
reads (same parsing as `filter_settings_page.dart:77`), behind a small
`TorrentFilterState loadDefaults()` helper so all sites share it.

### 3.4b Series specifics (episode plays and packs)
Scope note — "probing" exists at three layers and the ladder only touches
two: **search-side season probing** (`DynamicEngine._probeSeasons` parallel
per-season queries, Stremio smart-fallback pack tiers, `availableSeasons`
seeding) is candidate *generation* and stays byte-identical — the ladder
orders its output and deliberately never re-probes with quality-flavored
queries (if the probed pool has no tier-0 item, we relax and narrate; we
don't spend more network). **Resolve-side probing** (`_probeCandidates`) and
**pack coverage classification** integrate as described below/§3.4. The
`_recentlyNoPack` negative cache is upstream of the ladder and unchanged.

The episode path layers three mechanisms; the ladder slots between them:

1. **Title curation runs first** (`_curateCandidates` step 1) — drops
   other-show noise ("The Bad Guys: Breaking In" in a Breaking Bad search)
   before the ladder ever sees it. Ladder never reorders junk to the top
   that curation would have dropped.
2. **Episode-relevance survives inside tiers**: `curateEpisodeCandidates`
   FILTERS to exact-episode singles + packs covering the season, sorted
   exact-episode → seasonPack → multiSeason → complete. `ladder.order` is a
   stable sort, so that relevance order is preserved *within* each tier.
   Across tiers, a tier-0 pack CAN outrank a tier-2 exact-episode single —
   that's the feature (the pack carries the wanted quality), and the
   existing `_resolvedHasEpisode` guard + pack cleanup already handle packs
   that lie.
3. **Probe-cap safety**: with "try multiple torrents" OFF (default, 1
   probe), a tier-promoted pack that fails to resolve would dead-end where
   today's order might have played an exact-episode single. Corpus check
   (§5.0b) shows episode searches are dominated by exact-episode singles —
   the window is rare — but guard it anyway: **when the ladder is active
   and the top candidate is a pack, grant one extra probe reserved for the
   best exact-episode single.** Cheap, and removes the only regression path.
4. **Binge consistency**: once the pack-first path pins a pack, every later
   episode plays via the bound path (no ladder) — consistent quality across
   the season. Without a pin, each episode re-runs the ladder independently,
   so quality can vary episode-to-episode as availability varies; the
   overlay note makes each choice visible. Accepted.

### 3.5 Overlay narration (`pipeline_loading_overlay.dart`)
Add to the handle:

```dart
void setNote(String? note);   // rides the existing ValueNotifier
```

Rendered as one quiet line under the steps list (portrait + landscape + TV,
scaled like the step labels; `maxLines: 2`, ellipsis). Copy spec:

| Moment | Note |
|---|---|
| Search done, tier 0 non-empty | `Matching your filters · 12 of 40 sources` |
| Tier 0 empty, tier 1 has hits | `No full filter match — relaxed audio language · 5 sources` |
| Only tier 3 (unrestricted) has hits | `Nothing matches your filters — playing best available` |
| Probe advances past a tier (try-multiple on) | `Filtered match wasn't playable — trying next tier` |
| Filters empty | *(no note at all)* |

Filter description strings come from `FilterLadder.describeTier` +
a compact filter summary ("1080p · WEB · English") built from the enums'
display names already used by the filters sheet (`torrent_filters_sheet.dart`
label helpers — extract to the ladder file or reuse).

The note is **not** monotonic (unlike `setStage`) — it reflects the latest
truth and may change several times.

### 3.6 Setting (kill switch)
New toggle in Filter Settings: **"Apply filters to Quick Play"**
(`StorageService.get/setQuickPlayHonorsFilters`, default **ON**). Subtitle:
"Play prefers sources matching these filters, relaxing them only when
nothing matches." Off ⇒ ladder is skipped entirely (single-tier). Default ON
is the point of the feature, and the tier-3 floor guarantees it can never
make a previously-playable title unplayable — the worst case is identical to
today plus a note.

---

## 4. Behavior guarantees (review checklist)

- **Never fewer plays**: tier 3 == the unfiltered list, so anything playable
  today stays playable. The ladder only reorders.
- **Empty filters ⇒ byte-identical behavior** (single tier, stable order, no
  notes).
- **Torrents-vs-direct preference preserved**: the addon fallback still runs
  only when engines return nothing; within a mixed list, tier outranks
  stream type, direct beats torrent within a tier.
- **Curation untouched**: title-match / episode-relevance / RD-blocked run
  first; the ladder sorts what survives. (Curation's "never empty the list"
  invariant composes cleanly — the ladder doesn't drop, only orders.)
- **Cache-first demoted to within-tier**: deliberate trade — an uncached
  tier-0 candidate is probed before a cached tier-2. With "try multiple
  torrents" off (default 1 attempt) a dead top candidate still dead-ends,
  exactly as it does today for any uncached top pick.
- **PikPak**: single probe as today — it simply probes the best-tier
  candidate now.
- **Pack pinning**: tier-first pack ordering means auto-bind pins a pack the
  user's filters approve of, or (if none) the same pack it would pin today.

---

## 5. Validation

### 5.0 Real-world corpus results (done, 2026-07-15)
689 names from apibay across: Dune Part Two, Oppenheimer, Interstellar,
John Wick 4, Godzilla Minus One, Breaking Bad S01E01, The Penguin S01E01,
One Piece, Jawan, Kalki 2898 AD. Corpus + analysis script in the session
scratchpad (`corpus.json`); re-runnable via the §5.2 probe.

- Language tokens: **89% null** overall (95–99% on mainstream US titles;
  Jawan 53% — Bollywood names do tag Hindi). Detected languages on English
  titles are almost all genuine foreign/dual-audio releases (Ita/Fre/Latino
  dubs) — the detector's precision is good; its recall on English is ~0.
- Preset "1080p + WEB/BluRay + English" tier histogram (with §3.3 rule):
  **tier0 240 / tier1 19 / tier2 105 / tier3 325**; every title has tier-0
  candidates. Without the rule: tier0 = 1. (§3.3 confirmed mandatory.)
- Preset "4K only": tier0 present for 9/10 titles (1–18 each); Kalki has
  none ⇒ exercises the relax narration.
- Preset "Hindi only": Jawan/Kalki tier0-rich; US titles fall to tier 1 as
  expected — the few US tier-0 hits are dual-audio HDCAMs (⇒ §3.3c matters
  here too).
- Classifier gaps found: bare `.WEB.` → other (17/689, fixed by §3.2c);
  dual-audio ENG.LATINO.HINDI → hindi (§3.3b); cam detector fully accurate
  (34/34 genuine).

### 5.0b Series corpus results (done, 2026-07-15)
Episode searches (Breaking Bad S01E01, The Penguin S01E01, GoT S02E05,
Severance S02E01 — 160 names) and pack searches (BB complete / BB season 1 /
The Office complete / The Penguin season 1 — 269 pack-like names):

- **Every episode search had exact-episode singles at tier 0** under the
  "1080p + WEB/BluRay + EN" preset (Penguin 22, Severance 3, GoT 3, BB 3).
  The tier-first top pick was an exact-episode single in all four cases —
  the pack-over-single inversion (§3.4b.3) never occurred in real data.
  Older/airing-era shows skew HDTV (tier 2) exactly as expected; the ladder
  narrates the relax instead of silently playing it.
- **Tier-0 packs exist for pinning**: BB 18–22/100, Penguin 3/4. The Office
  (pre-HD era) is the relax case: 4/65 tier-0, mostly SD/DVD packs at
  tier 3 — auto-pin still works, note explains the downgrade.
- Confirms §3.4b's design: relevance-in-tier + tier-across + the one extra
  pack-top probe covers everything observed.

### 5.1 Unit tests (`test/filter_ladder_test.dart`)
Pure-Dart tests over `FilterLadder` with a curated fixture of ~60 real-world
release names covering: pixel vs keyword quality tokens ("UHD BluRay 1080p"
must be fullHd), all rip-source families, language-tagged names (Hindi/VF/
Latino/multi-audio), **untagged English releases** (the §3.3 rule), addon
direct-link style names ("Torrentio 4k | RD+"), junk (CAM, 480p). Assert:
tier assignment, ordering stability, empty-filter no-op, non-English-only
language sets rejecting null.

### 5.2 Real-data probe (`tool/filter_ladder_probe.dart`)
Dev-only script (not shipped): given titles, pull names from the torrents-csv
API (`https://torrents-csv.com/service/search?q=…` — returned 502 at plan
time; fall back to the downloadable SQLite dump or the bundled fixture when
unreachable), run the classifiers, and print a tier histogram per title for a
few filter presets (1080p+WEB+EN, 4K-only, Hindi-only). Purpose: eyeball
hit-rates so we catch a classifier gap (e.g. a language filter starving
tier 0) BEFORE shipping, not from user reports.

### 5.3 Manual matrix
| Scenario | Expected |
|---|---|
| Filters off | No note, behavior unchanged |
| 1080p+WEB+EN, popular movie | Tier-0 note, plays a 1080p WEB rip |
| Hindi-only, western title | Relax note → best-available note |
| 4K-only, title with no 4K | "relaxed…" note, plays 1080p |
| Addon-only title (engines dry) + quality filter | Fallback + ladder note, direct link plays |
| Series with auto-pin | Pinned pack respects quality filter |
| Bound source pinned | Plays pin, no ladder note |
| TV (DPAD) | Note legible at 10ft, Cancel still focusable |

---

## 6. Implementation order (each step testable alone)

0. Shared classifier fix: bare `\bweb\b` in `detectRipSource` (+ badge/filter
   parity check, FormatTagDetector sync) with fixture tests from the corpus.
1. `FilterLadder` + `loadDefaults()` + unit tests + probe script. *(pure, no UI)*
   Includes §3.3 null-English rule, §3.3b all-token language matching, and
   §3.3c cam floor.
2. `PipelineLoadingOverlay.setNote` + rendering in all three layouts.
3. Wire ladder into `playFromSelection` main list + `playBest`
   (direct-pick-by-tier, per-tier cache-first, probe note callback).
4. Pack path tier-first ordering.
5. Filter Settings toggle (+ storage key, default ON).
6. Full review pass + on-device test (phone + TV).

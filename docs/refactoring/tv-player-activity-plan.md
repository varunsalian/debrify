# Android TV player activity refactor — plan

Written 2026-10-07 on `refactor/codebase` at `39c630303`. Follow
[AGENTS.md](../../AGENTS.md). This is the first **player** refactor and the
first **Kotlin** refactor in the series. The Dart-side technique (verbatim
moves, characterization of the original with mutation proofs, independent
review, merged-tree gates) carries over; the tooling does not, so this plan
defines the Kotlin equivalents.

Inputs: a six-part read-only responsibility map of the file (clusters, owned
fields, cross-cluster state, external effects, teardown order, reflective test
access, source-text anchors). It is copied into
`docs/refactoring/tv-player-activity-deps.md` at step 0 and is the inventory
every phase is checked against.

## Goal and scope

`android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt`
is **22,221 lines**: imports 1–133, one class `AndroidTvTorrentPlayerActivity :
AppCompatActivity()` at 136–20177 (≈724 properties, ≈545 functions, 11 nested
types, a companion at 20129–20176), then 25 top-level declarations at
20178–22221 (models, the playlist / movie / IPTV channel / EPG / Stremio TV
guide adapters, two `internal` merge functions).

It is the native Android TV player for torrent/debrid/Stremio/IPTV/PikPak
playback: Media3 ExoPlayer setup, the IPTV live pipeline (twin trial,
strict-TS, live recovery, recording, guide, zap, EPG, Start Over), the
Stremio TV guide, source switching and startup failover, subtitles and
auto-sync, controls/seekbar/dock skins, the playlist, Up Next, skip segments,
sleep timer, progress reporting and lifecycle teardown.

The end state splits it into cohesive, explicitly-dependent collaborators in
`com.debrify.app.tv` (same package — the existing house pattern:
`SubtitlePanelController`, `UnifiedMenuController`, `TvSourceBrowserController`
… a class with a narrow `Callbacks`/host interface the activity implements).
The activity remains the Android entry point, the owner of lifecycle order and
of the shared player instance, and the composition root that wires
collaborators.

**This is too large for one batch.** It runs as **ordered phases**, each a
reviewable batch on its own branch (`refactor/tvplayer-pN`), merged into
`refactor/codebase` and pushed to `private` before the next phase starts.
Phases are sequential (every phase edits the same file; parallel branches
would conflict constantly). Each later phase gets its own detailed section in
this plan, written and Codex design-reviewed before that phase executes,
using the then-current line numbers.

Unchanged by every phase (the contract): the activity FQN and manifest entry;
intent extras (`playbackSessionId`, `payloadPath` read-then-delete, legacy
`payload`, `NativePlayerPreferences.EXTRA`); the received broadcast
`com.debrify.app.tv.UPDATE_EPISODE_METADATA` and its extras; all 32
activity→Flutter `MethodChannel` method names, argument maps and their call
order; Media3 configuration (buffer presets, load-error policies, data-source
headers, track-selector parameters); every Handler/coroutine delay; token and
generation guards; focus order and key routing; view ids/layouts; lifecycle
and teardown order (`onStop` 12 steps, `onDestroy` 43 steps as mapped);
threading (`@Volatile` fields read on loader threads stay volatile and are
read through the same field). No bug fixes ride along — bugs found during the
work (e.g. the un-cancelled 45 s EPG watchdog, dead `showSeekbar` path,
unreachable menu "sources" section) are recorded in **Follow-ups**, not fixed.

## Shared rules for every phase

1. **Move, don't rewrite.** Moved declarations keep their bodies, comments and
   order token-for-token. Allowed edits are only those listed per move in the
   manifest: visibility (`private` → `internal` for file-private top-level
   declarations that now cross files; a moved member becomes `internal` only
   when the activity still calls it), receiver qualification for state that
   stays in the activity (`foo` → `host.foo`), `this@AndroidTvTorrentPlayerActivity`
   → the injected activity reference, and `inner` removal for a nested class
   proven not to use outer members. Each allowed edit is declared, not
   inferred.
2. **Kotlin move checker** (`dev/tool/check_kotlin_moves.py`, built in phase 1
   step T). Manifest-driven like `check_verbatim_moves.py`, and **exhaustive
   over the original file**, not only over moved code:
   - **Ownership.** Every declaration of the original file at the recorded
     base SHA (top-level, class members incl. property initializers and
     `init` blocks, nested types, companion members) is assigned exactly one
     fate in the manifest: `retained` (stays in the original file),
     `moved` (destination file + declared substitutions) or `rewritten`
     (only with a reason and a named test). Unassigned, doubly assigned,
     surviving-after-move (original and destination both present) and
     unexpected new declarations in the original file or any destination are
     errors.
   - **Retained code is compared too.** Every retained declaration must be
     token-identical to the original (only declared substitutions — e.g. a
     call that now targets a collaborator), and retained members keep their
     relative order, so property-initializer and `init` order cannot change
     silently. File-level items are validated: `package`, file annotations
     (`@file:`), the class-level `@OptIn`, and the import list (only removals
     of imports proven unused, and additions in destinations).
   - **Lexing.** A real Kotlin lexer for Kotlin 2.2.20 syntax: nested block
     comments, KDoc, string templates `$x`/`${…}` with nesting, raw strings,
     char literals, backtick identifiers, annotations with use-site targets,
     numeric literals with `_`/suffixes, labels (`return@x`, `this@X`).
     Comments are tokens. **Newlines are significant** (Kotlin's grammar
     treats `NL` as a statement separator): the comparison keeps one `NL`
     token per line break between tokens and only normalises indentation and
     trailing spaces. Same-tokens/different-newline layouts are a failure.
   - **Substitutions** are declared per declaration with the exact original
     token sequence, its replacement and an expected occurrence count; any
     other difference fails.
   - **Self-tests**: positive real-config fixtures, and negatives that must
     each fail for the stated reason — changed literal, dropped/edited
     comment, reordered statement, newline-only change, undeclared receiver
     change, undeclared visibility change, missing declaration, duplicate
     move, original+destination both present, unexpected new declaration,
     retained-body edit, property-initializer reorder, template-content
     change, import change in the original that is not an unused-import
     removal.
3. **Characterize the original first (step 0).** Before any move in a phase,
   add Robolectric/JVM tests that pin the phase's observable behaviour on the
   **original** code, prove each with an assertion-failing mutation of the
   original (in a detached worktree under the evidence dir), and record the
   mutation table. Claude independently samples further mutations; gaps found
   are closed in step 0b. Tests target behaviour (bound view text/visibility,
   click/focus callbacks, key routing results, Handler-scheduled effects with
   `ShadowLooper`, `MethodChannel` invocations through a test seam, Media3
   parameter values), not source text.
4. **Tests that reach private names.** Reflection tests
   (`StremioTvStartupWatchdogTest`, `ShufflePlaybackFlowTest`,
   `SubtitleSyncDismissTest`, `NativePlayerSettingsConsumptionTest`,
   `NativePlayerRejectedLaunchTest`) and Dart source-text tests
   (`test/android_tv_auto_advance_resume_test.dart`,
   `test/manual_source_validation_contract_test.dart`,
   `test/android_tv_mdblist_progress_source_test.dart`,
   `test/profiles/profile_source_guard_test.dart` directory scans,
   `NativeAudioRoutingTest` source read) must keep their **purpose**. When a
   reflected member or anchored range moves, the test is retargeted to the new
   owner/path in the same commit with an equal-or-stronger assertion; the
   phase's dependency report lists each retarget (old anchor → new anchor) and
   the reviewer checks it. Never delete an assertion to make a move pass.
5. **R8 parity.** `proguard-rules.pro:52` already has
   `-keep class com.debrify.app.** { *; }`, which covers every class in the
   app package — the activity, its nested types, top-level classes and JVM
   file facades (`…Kt`) alike — in addition to the activity-specific rules
   at 157/166. Extracted classes stay in `com.debrify.app.tv`, so their
   shrink/obfuscation treatment is unchanged and **no rules are added**. The
   broad rule must be preserved (a phase that would need to change any
   proguard rule stops and asks). The phase-gate release build's
   `mapping.txt` is checked for the complete moved set: every moved class,
   its nested holders and new file facades (e.g. `TvPlaybackItemKt`) appear
   with identity mappings for the class and all moved members.
6. **Gates per phase** (local; CI does not run Android JVM tests).
   Evidence paths resolve through `git rev-parse --path-format=absolute
   --git-common-dir` (worktrees have a `.git` file) under
   `refactor-evidence/tvplayer/`.
   - JVM baseline: a clean `:app:cleanTestDebugUnitTest :app:testDebugUnitTest`
     run (Android Studio JBR, JDK 21) at the phase base, archived with every
     test identity and status, the tested revision, dirty-file count, Gradle
     exit code and JDK version (`junit/<label>/identities.json` + raw XML).
     A **new complete baseline is recorded after step 0** adds
     characterization tests; later runs are compared against it. A
     comparison fails on: any new failure/error, any missing identity, any new
     skip, a run with no/partial XML (identity count lower than the baseline
     or Gradle aborting before tests), or a tree that changed during the run.
     Known pre-existing failure:
     `TvSourceBrowserFocusTest.dpadAndRailFocusKeepRowsAndImportedArtworkAttached`.
   - `./gradlew :app:compileDebugKotlin` with no new Kotlin warnings
     (compiler warning set compared by message identity, line shifts
     tolerated).
   - Kotlin move checker + its self-tests; `check_file_sizes.py` (the
     activity's baseline entry is lowered with `--update`; every new file
     ≤ 800 lines unless a documented exception); format/analyze of any Dart
     touched; the Dart source-text tests above.
   - At the phase gate: a **release build** (`flutter build apk --release`,
     no install) succeeds, `dev/scripts/verify_android_subtitle_decoders.sh`
     passes on it, and the R8 mapping check of rule 5 passes; plus the full
     Flutter suite via `suite_evidence.py` on the merged tree (gate commits
     contain `gate`).
   - Never `flutter run`/install anything on a device; no emulators.
7. **Device checks** are not gates. Each phase lists what a human should check
   on a real Android TV at the end of the whole series; Claude aggregates them
   into the end-of-series checklist.
8. **Codex** (gpt-6.1-sol, xhigh, via `~/bin/codex-run`) reviews each phase
   design until "No P1s", executes, and does an independent post-review;
   Claude reviews every phase range too.

## Phase map (risk-ordered)

Line numbers are at `39c630303`; each phase section re-measures.

| Phase | Content | ≈ lines out | Risk |
|---|---|---|---|
| 1 | Top-level models + adapters; self-contained nested types; Kotlin move checker | 2,250 | low |
| 2 | Pure helpers and stateless policies (IPTV error classification, recording URL rules, payload parsing helpers, playlist next/prev targeting, formatting); Flutter bridge seam (`TvPlayerFlutterBridge` wrapping the 32 method calls, same names/args/order) | 2,000 | low–med |
| 3 | Self-owned features with timers: sleep timer, skip segments, Up Next card, status pill, PikPak cold-storage retry, recording actions, auto-sync ring/pill | 2,500 | med |
| 4 | Tracks / subtitles / display / speed / night mode; progress reporter | 2,500 | med |
| 5 | IPTV live: guide, browse, zap paging, channel switch + startup-channel memory, EPG, Start Over, zap banner, Stremio candidate ladder (one unit: shared token protocol) | 4,000 | high |
| 6 | Stremio TV guide; source switcher + startup/manual-switch gate (one unit) | 2,500 | high |
| 7 | Playback start + shuffle + resolve (`playItem`/`resolveAndPlay`/`startPlayback`), metadata receiver, controls / seekbar / cinema scrub / dock skins, key dispatcher, `playbackListener`, media pipeline factory | 4,000 | highest |

After phase 7 the activity holds lifecycle methods (teardown order intact),
field wiring of collaborators, `Callbacks` implementations and the shared
player. Its expected size is reassessed then; anything above 800 lines gets a
documented exception with remaining responsibilities and an exit milestone.

## Phase 1 — models, adapters, self-contained nested types

Branch `refactor/tvplayer-p1`, worktree `../debrify-wt/tvplayer`. Evidence
under `<git-common-dir>/refactor-evidence/tvplayer/p1/`.

### Moves

All destinations are in `android/app/src/main/kotlin/com/debrify/app/tv/`,
package `com.debrify.app.tv`. Declarations keep their source order inside each
destination. Top-level `private` → `internal` (required: Kotlin `private`
top-level is file-private). Nested `private` types that become top-level →
`internal`.

| Destination | Declarations (original lines) |
|---|---|
| `TvPlaybackItem.kt` | `PlaybackItem` 20409–20516 (already internal), `mergeLateMetadataResumePosition` 20365–20377, `mergeLateMetadataDuration` 20380–20391 (with their KDoc), `GuideEpisode` 20394–20407, `SeasonEpisode` 20537–20540 |
| `TvPlaybackPayload.kt` | `PlaylistMode` 20178, `ManualSourceSwitchSnapshot` 20180–20190, `CollectionGroup` 20192–20195, `MovieGroups` 20197–20212, `PlaybackPayload` 20336–20358, `SubtitleCatalogResult` 20518–20535 |
| `TvStremioSource.kt` | `StremioSource` 20230–20334 (with companion) |
| `TvPlaylistAdapter.kt` | `PlaylistOverlayAdapter` 20220–20224, `PlaylistListItem` 20543–20549, `PlaylistAdapter` 20551–21099 (≈550) |
| `TvMoviePlaylistAdapter.kt` | `MovieTab` 20214–20218, `MoviePlaylistAdapter` 21101–21408 |
| `IptvChannelAdapter.kt` | banner comment 21409–21412, `IptvChannelEntry` 21413–21469, `IptvChannelAdapter` 21471–21788, `IptvSourceEntry` 21790–21802, `IptvListEntry` 21805–21809 |
| `IptvEpgAdapter.kt` | `IptvEpgProgram` 21811–21817, `IptvEpgAdapter` 21819–21920 |
| `StremioTvGuideAdapter.kt` | `StremioTvGuideChannel` 21926–21946, `StremioTvGuideAdapter` 21948–22221 |
| `IptvPickerAdapters.kt` | nested `IptvCategoryAdapter` 10602–10672, `IptvListPickerAdapter` 10837–10909 (static nested, no outer capture) |
| `AutoSyncRingView.kt` | nested `AutoSyncColors` 16200–16204, `AutoSyncRingView` 16207–16258 (`inner` removed — proven to use no outer member; the checker's declared substitution) |

Exact line ranges, including leading comments/annotations
(`@androidx.annotation.OptIn` at 21471/21948), are re-measured at step 0 and
recorded in the manifest; a banner/KDoc travels with the declaration it
precedes.

**Stays in the activity in phase 1** (with reasons): `IptvLiveLoadErrorPolicy`
(inner, captures `iptvChannels`/`currentIptvIndex` — phase 2 with a supplier);
`ShufflePlaybackAttempt` (reflected by `ShufflePlaybackFlowTest` via simple
name + constructor order — moves with shuffle in phase 7);
`SkipSegmentRequest`/`SleepTimerMode` (phase 3, with their features);
`DockSkinSpec` (phase 7, with dock skins); `IptvStremioCandidate` (phase 5);
`TvSourceAddon` (public nested; binary name — phase 6 decides); the companion.

### Constraints specific to phase 1

- Destination files import exactly what they need (`com.debrify.app.R`,
  Glide, Media3 `UnstableApi`, views); imports are not part of the token
  comparison but unused imports must not be added. The activity's import list
  only loses imports that become unused (checked by compile warnings diff).
- R8: covered by the existing broad `-keep class com.debrify.app.** { *; }`
  (rule 5); no rule changes. The gate's mapping check covers all ten
  destination files' classes, nested holders (`ViewHolder`s, companions,
  `PlaylistListItem` subclasses) and the new `TvPlaybackItemKt` facade.
- `mergeLateMetadata*` move from the `AndroidTvTorrentPlayerActivityKt` JVM
  facade to `TvPlaybackItemKt`; nothing references the facade by name
  (verified at step 0 by grep over Kotlin, Java, proguard rules and tests).
- The Dart source-text test anchoring inside `PlaylistAdapter` (≈20671–20691)
  and the `PlaybackItem.displayProgressPercent` `if (watched) return 100`
  pin are retargeted to the new files with equal assertions.
- Size: every destination ≤ 800 lines (largest expected: `TvPlaylistAdapter.kt`
  ≈ 560). Activity shrinks by ≈ 2,250 to ≈ 19,970 (before import cleanup);
  baseline lowered to the measured count.

### Step 0 — characterization of the original

Robolectric tests under `android/app/src/test/kotlin/com/debrify/app/tv/`
exercising the moved declarations through their public surface, run against
the original file and then unchanged after the moves:

- `PlaybackItem` / `StremioSource` / `PlaybackPayload`-related parsing:
  `fromJson`/`fromMap` field mapping incl. optional/absent keys, header maps,
  quality parsing, `startupFailureKey` derivation, `seasonEpisodeLabel`,
  `displayProgressPercent` edge cases (extend existing
  `PlaybackItemHeadersTest`/`PlaybackProgressPolicyTest` rather than
  duplicating).
- Each adapter (`PlaylistAdapter`, `MoviePlaylistAdapter`,
  `IptvChannelAdapter`, `IptvEpgAdapter`, `StremioTvGuideAdapter`,
  `IptvCategoryAdapter`, `IptvListPickerAdapter`): `itemCount`, view types,
  bound text/visibility/selected state for representative rows (now playing,
  watched, progress, missing episode, season header, favourite, EPG now/next,
  Glide-free fallbacks), click, long-click (incl. whether it is consumed) and
  focus-change lambdas invoked with the right arguments, and any DPAD key
  handling the adapter installs. In addition, explicitly:
  - season/group ordering and filtering, and a recycled holder going from a
    missing-episode row to an actual row (and back) leaves no stale state;
  - payload (partial) binds: the progress payload path and active-position
    notifications of `PlaylistAdapter` (≈20698), Stremio TV guide partial
    binds (≈21982);
  - IPTV channel identity-based notifications, DiffUtil updates, list
    readiness / mutable membership and stale-EPG request eligibility
    (≈21637, ≈21722);
  - posted callbacks (e.g. the Stremio guide progress-width post ≈22156) with
    their recycled-holder / `NO_POSITION` guards — exercised through an
    **attached, measured RecyclerView** (directly invoking
    `onBindViewHolder` leaves `bindingAdapterPosition == NO_POSITION` and
    would make the guard trivially exit);
  - classic vs styled binding where an adapter has both (guide styles).
- `AutoSyncRingView`, under a PAUSED looper with bounded advances: the pulse
  animator's 1,800 ms duration, its infinite-repeat request (assert the
  requested repeat count via `ShadowValueAnimator.getActualRepeatCount()` —
  Robolectric 4.15.1 runs `INFINITE` as one repeat, which is not production
  behaviour and must not be asserted as such), the repeated-start guard,
  stop/reset, cancellation on detach, `arcColor` changes, and non-pixel draw
  assertions (circle/arc calls and paint colour/stroke/alpha) via legacy
  canvas recording.
- Mutation proofs on the original for every test; Claude samples ≥ 10 more.

**Access to private originals.** Every phase-1 target is file-private or a
private nested type today (`StremioSource`, `PlaybackPayload`, all five
top-level adapters and their entry/model classes, the two nested picker
adapters, `AutoSyncColors`, the `inner` `AutoSyncRingView`, whose
constructor takes the outer activity instance). Step 0 adds one test helper
(`TvPlayerOriginalAccess.kt`) with reflection-based locators/constructors
for each (by JVM binary name, e.g. `com.debrify.app.tv.PlaylistAdapter`,
`com.debrify.app.tv.AndroidTvTorrentPlayerActivity$IptvCategoryAdapter`,
the ring's `(outer, Context)` constructor). Production visibility is not
widened to establish the baseline. In the move commit only that helper is
retargeted to direct references (or to the new binary names); the
behavioural assertions in the tests do not change, which the reviewer
verifies with a diff limited to the helper.

### Phase 1 steps

- **T** — `check_kotlin_moves.py` + self-tests (fixtures under
  `dev/tool/fixtures/kotlin_moves/`), and the phase-1 manifest
  `dev/tool/kotlin_moves/tvplayer_p1.json` naming base SHA `39c630303`.
- **0 / 0b** — dependency report copy, characterization + mutation tables.
- **1** — the moves (one commit per destination group is fine), keep rules,
  retargeted source-text tests, baseline update.
- **gate** — compile, JVM tests vs baseline, checker, size, Dart
  source-text tests, release build + decoder verification + mapping check,
  full Flutter suite (`suite_evidence.py`), commit message contains `gate`.
- **Review** — Claude's own review + independent Codex review of the range.

### Phase 1 device checklist (end of series)

Android TV, release build: open a series → playlist overlay (season tabs,
now-playing, watched/progress, missing episodes); a movie collection playlist;
IPTV guide (channel list, categories picker, list picker, EPG pane); Stremio TV
guide; auto-sync ring animates during subtitle auto-sync.

## Follow-ups (found while mapping; not fixed here)

- `requestIptvEpg`'s private 45 s watchdog Handler is never cancelled in
  `onDestroy`; it can deliver `null` into `ensureIptvChannelEpg` (no
  `isDestroyed` guard). `iptvStremioToken` is not bumped in `onDestroy`.
- `showSeekbar`/`stopSeekbarProgressUpdates` have no callers; the dispatcher's
  seekbar branch is unreachable.
- `showSubtitleTrackDialog`, `hideSubtitleSettingsPanel` have no callers; the
  unified menu's "sources" section is unreachable.
- `waitForPikPakMetadata` polls on an un-cancelled local Handler;
  `setupPlaylistNavigation` adds a focus listener per rebuild.
- `IptvLiveLoadErrorPolicy` reads non-volatile `iptvChannels` on loader threads.
- Pre-existing JVM failure `TvSourceBrowserFocusTest.dpadAndRailFocusKeepRowsAndImportedArtworkAttached`.
- Revisit the per-class R8 keep rules after the series.

## Progress

(appended per step)
- 2026-10-07 — design round 1 (Codex): 2 P1 (checker must be exhaustive incl.
  retained code; baseline archive incomplete), 5 P2, 1 P3 — all folded into
  rules 2, 5, 6 and phase-1 step 0. Clean JVM baseline recorded:
  `junit/baseline-39c630303/identities.json` at `8bb284e3c` (docs-only over
  `39c630303`): 259 identities, 258 pass, 1 known failure.

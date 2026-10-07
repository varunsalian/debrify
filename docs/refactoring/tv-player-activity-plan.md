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
     `moved` (destination file + declared substitutions) or `patched`.
     **`patched` is forbidden in phase 1.** In later phases it is allowed
     only for wiring edits and is expressed as exact before→after token
     patches with occurrence counts; the checker applies the patches to the
     original declaration and compares the **entire** resulting declaration
     token-for-token (a reason and a named test supplement, never replace,
     that comparison). Unassigned, doubly assigned,
     surviving-after-move (original and destination both present) and
     unexpected new declarations in the original file or any destination are
     errors.
   - **Retained code is compared too.** Every retained declaration must be
     token-identical to the original (only declared substitutions — e.g. a
     call that now targets a collaborator), and retained members keep their
     relative order, so property-initializer and `init` order cannot change
     silently. File-level items are validated: `package`, file annotations
     (`@file:`), the class-level `@OptIn`, and the import lists: **the
     activity's imports are frozen in phase 1** (any leftover unused import
     is harmless and is cleaned up later as its own reviewed step with an
     explicit removal list in the manifest); every destination's import list
     must equal an exact reviewed list in the manifest. (Kotlin 2.2.20 emits
     no unused-import diagnostic, so compiler warnings cannot prove an import
     unused.)
   - **Partitioning.** A split container (the activity class, whose nested
     types leave) is not compared whole. The checked spans are disjoint and
     together cover the whole original file: whole moved subtrees; for each
     split container its header, its opening/closing braces and its ordered
     list of children; every intervening comment/blank-line/token run between
     children (attached to the following child, or to the container's
     closing brace). Declarations are identified by overload-safe selectors
     (kind + name + parameter type list as written + container path, e.g.
     `fun parseIptvChannels(JSONArray)` vs `fun parseIptvChannels(List<*>)`;
     `init#n` for the n-th `init` block; property by name; companion and
     anonymous objects by container path). Expression bodies, delegated
     properties, constructor properties, anonymous objects and nested `init`
     blocks are handled; anything the parser cannot classify is an error, never
     silently skipped.
   - **Parser.** Declaration structure comes from the real Kotlin PSI pinned to
     the project's Kotlin **2.2.20** (`kotlin-compiler-embeddable:2.2.20`,
     already resolvable from the Gradle cache used by the app build), via a
     small JVM adapter under `dev/tool/kotlin_psi/` that dumps the declaration
     tree (kinds, selectors, exact offsets) and the token stream as JSON;
     Python orchestrates the manifest logic. If the adapter cannot be built
     offline, stop and report rather than fall back to a hand-written parser.
     Before any production move the checker must (a) self-compare the
     original file at the base SHA with an all-`retained` manifest (zero
     diffs, every declaration classified) and (b) pass a complete phase-1
     extraction fixture.
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
     change, any import change in the original, a destination import list
     differing from the manifest, an overloaded-function mix-up, and a
     `patched` declaration with one extra edit beyond its declared patches.
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
  comparison; each destination's import list is pinned exactly in the
  manifest. The activity's import list is frozen in phase 1 (rule 2).
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
  - all four payload (partial) bind overloads — `PlaylistAdapter` (≈20698),
    `MoviePlaylistAdapter` (≈21151, progress payload accepted anywhere in the
    list), `IptvChannelAdapter` (≈21573, EPG payload recognised only as the
    first payload, focus/scale preserved) and `StremioTvGuideAdapter`
    (≈21982) — each with empty, unknown and mixed payload lists, asserting
    partial-versus-full bind effects; plus the active-position and progress
    notifications of both playlist adapters, including hidden items and an
    unchanged active position;
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
  assertions through a test-only recording `Canvas` subclass that **copies
  the `Paint` inside each `drawCircle` call** (Robolectric's legacy
  recording stores the live `Paint`, which the ring mutates after the halo
  — alpha reset, style → `FILL` — so post-hoc inspection is wrong). Assert
  the halo and dot snapshots (radius, colour, style, stroke width, alpha);
  mutations prove the halo alpha/stroke assertions. (The view draws circles
  only — no arcs.)
- Mutation proofs on the original for every test; Claude samples ≥ 10 more.

**Access to private originals.** `PlaybackItem` and both
`mergeLateMetadata*` functions are already `internal` and keep their existing
direct test access. Every other phase-1 target is file-private or a
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

- **T** — `dev/tool/android_junit_evidence.py` (`run <label>` = the clean
  run + identity archive of rule 6; `compare <label> --against <label>` =
  the rule-6 failure conditions), `check_kotlin_moves.py` + self-tests (fixtures under
  `dev/tool/fixtures/kotlin_moves/`), and the phase-1 manifest
  `dev/tool/kotlin_moves/tvplayer_p1.json` naming base SHA `39c630303`.
- **0 / 0b** — dependency report copy, characterization + mutation tables.
- **1** — the moves (one commit per destination group is fine), the
  reflection helper retargeted, retargeted source-text tests, size-baseline
  update; verify (do not edit) existing R8 coverage.
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
- Independent post-review P3 coverage follow-up before phase 3: characterize
  ring repaint requests after color changes, animator updates and stop/reset,
  with original-code assertion-killed `invalidate()` removal mutations. Current
  calls are preserved by the exact checker; no production bug was found.
- Phase-1 local decoder gate: the unchanged upstream fallback MediaKit jars
  omit `pgssub`, `xsub`, `ccaption`, `jacosub`, `microdvd`, `mpl2`, `pjs`,
  `realtext`, `sami` and the `astats`/`aspectralstats`/`ametadata` filters.
  Complete verification needs the existing pinned CI patched native bundle;
  its build recipe requires Linux. No libraries/recipes were changed here.
- Observed full Flutter baseline has 41 failing/error identities and 20 skips
  (`p1/flutter-gate-known-failures.json`); all statuses are unchanged at the
  phase-1 gate. Follow up separately; no obsolete allowlist was used.

## Progress

(appended per step)
- 2026-10-07 — design round 1 (Codex): 2 P1 (checker must be exhaustive incl.
  retained code; baseline archive incomplete), 5 P2, 1 P3 — all folded into
  rules 2, 5, 6 and phase-1 step 0. Clean JVM baseline recorded:
  `junit/baseline-39c630303/identities.json` at `8bb284e3c` (docs-only over
  `39c630303`): 259 identities, 258 pass, 1 known failure.
- 2026-10-07 — design round 2 (Codex): baseline P1 resolved; new P1
  (`rewritten` fate bypassed exact comparison → `patched` forbidden in
  phase 1, exact token patches + whole-declaration compare later); P2s
  folded: PSI-backed partitioning with overload-safe selectors and
  original self-comparison, frozen activity imports + exact destination
  import lists, Paint-copying recording canvas, all four payload-bind
  overloads.
- 2026-10-07 — design round 3 (Codex): **No P1s**; two P3 wording fixes
  applied. Design approved for phase 1 execution.
- 2026-10-07 — **Phase 1 step T complete**, commit `05dd8a9e9` on
  `refactor/tvplayer-p1`. Added `android_junit_evidence.py` run/compare with
  reference-compatible archives and 3 passing self-tests (including the
  rule-6 rejection cases). Kotlin 2.2.20 PSI adapter builds offline from the
  Gradle cache; no fallback parser or application dependency changes.
  Original `39c630303` all-retained self-comparison: **3,477 declarations
  classified, zero differences**. Phase-1 manifest pins 29 moved subtrees
  across 10 destinations and retained ownership/imports. **24 checker
  self-tests pass**, including a complete extraction of the original into
  the planned destinations and every required negative with its expected
  rejection reason. Evidence: `p1/original-all-retained.json`,
  `p1/original-self-comparison.log`, `p1/checker-self-tests.log`,
  `p1/junit-helper-self-tests.log`, `p1/complete-extraction-fixture/`.
- 2026-10-07 — **Phase 1 step 0 complete**, commit `04540666d`.
  Added **38 characterization tests** and the private-original reflection
  helper; reused 8 header/progress/metadata-merge tests. All seven adapters,
  all four payload overloads, ordering/filtering/recycling, notifications,
  IPTV identity/DiffUtil/EPG eligibility, picker readiness/membership,
  attached measured guide posts, guide styles, and ring timing/draw/lifetime
  contracts are covered. **49 isolated original-code mutations** across
  **46 named tests** each compiled and failed on the named assertion.
  Full table and evidence references are appended to the dependency report's
  “Phase 1 step 0” section. The detached mutation worktree at `39c630303`
  was removed after the proofs; raw patches/logs/XML remain in `p1/mutations/`.
  Clean original run `junit/p1-step0-original-verified` and post-step-0
  baseline **`junit/p1-step0`** each have **297 identities: 296 pass, the
  same known focus failure, no skips**. Compared with
  `baseline-39c630303`: **38 passing additions only**, all 259 original
  identities/statuses preserved. Original/current comparisons also match;
  run fingerprints are stable. Baseline tested revision `05dd8a9e9` with
  12 dirty files (the committed tests/report); JBR 21.0.10. File-size and
  diff checks pass; facade-name search found no explicit consumers.
- 2026-10-07 — **Stopped after step 0 as requested, before step 1**.
  Production source, `pubspec.lock`, and ProGuard rules are unchanged; no
  device interaction, branch switch, or push. Claude's independent ≥10
  additional mutation samples and any step 0b work remain for the reviewer.
  Moves, anchor/helper retargets, release/R8 and full Flutter phase gates
  remain at their planned milestones. Later JVM runs compare against
  **`p1-step0`**, not the pre-characterization baseline.

- 2026-10-07 — **Phase 1 step 0b complete**. Added 26 characterization tests
  and strengthened the existing ring pulse test. All seven exact Claude
  survivors are assertion-killed against all 72 relevant original-code tests.
  The gap sweep archives 278 runs: 262 assertion kills, 14 equivalent variants
  explained in the dependency report, and two early survivors closed by final
  assertions. Every one of the 27 new/strengthened named tests has a mutation
  proof. Exact visibility, absent defaults, focus axes/durations/elevations,
  progress thresholds, alpha and ring/pulse boundaries are covered. Evidence:
  `p1/step0b/`; original clean run 72/72. Detached original worktree removed.
  Clean JVM baseline **`p1-step0b`**: 323 identities, 322 pass, unchanged known
  focus failure, no skips; **26 passing additions only** versus `p1-step0`,
  stable fingerprints, JBR 21.0.10. Production source, lockfile and ProGuard
  remain unchanged. Later phase-1 JVM gates compare against `p1-step0b`.

- 2026-10-07 — **Phase 1 step 1 moves complete**. Extracted the exact 29
  manifest subtrees into all ten planned files and wired the existing callers
  through unchanged package references. Only the reflection helper and two
  Dart source anchors were retargeted; behavior assertions are unchanged.
  Rule-2 checker: 3,477 declarations, zero differences. Debug Kotlin compile
  succeeds. Activity: **19,961 lines** (was 22,221); largest
  destination **572 lines**. Size baseline
  lowered with `--update` and scoped to this activity. ProGuard and lockfile
  unchanged. Retarget inventory and legacy native localization prerequisite
  recorded in the dependency report. Remaining activity duties exit in phases
  2–7; no new size exception. Phase gate follows on this tree.

- 2026-10-07 — **Phase 1 gate checks run on `b783e5b02`; release decoder
  gate remains FAILED/pending**. JVM `p1-gate` matches `p1-step0b` exactly:
  323 identities, 322 pass, unchanged known focus failure, zero additions,
  removals or skips, clean/stable input fingerprints. Debug Kotlin compile
  succeeds with the same five warning messages. Move checker: 3,477
  declarations, zero differences; all 24 self-tests pass. File-size check
  passes; Dart formatting changes zero lines. Analyzer comparison adds zero
  diagnostic identities (1,852 before, 1,767 after; duplicate/build-output
  diagnostics removed). Four focused Dart source-test files: 45 identities,
  44 pass and the unchanged profile-source guard failure. First concurrent
  focused run was rejected for a generated Kotlin session path; verified
  rerun after release build has a stable fingerprint.
  Release APK build succeeds. Rule-5 complete check passes: all ten source
  files, 53 emitted classes and 1,080 fields/methods, including nested holders,
  companions, anonymous classes and `TvPlaybackItemKt`. R8 represents 519
  member mappings explicitly and omits 561 unchanged identities; every one
  of the latter is independently verified by name and mapped descriptor in
  the actual APK DEX definitions. Inline-frame groups are distinguished from
  residual-member mappings. Three negative controls reject renamed class,
  renamed member and missing DEX member. This representation refinement
  strengthens verification without adding/removing ProGuard rules.
  Decoder verification fails: each of the three APK ABIs lacks nine required
  decoders and three auto-sync filters. Packaged binaries exactly match the
  vendored Gradle recipe's pinned upstream v1.1.5 fallback (hashes archived),
  with no `.debrify-subtitle-build` marker; the CI patched bundle recipe
  requires Linux. No dependency, binary, build-setting or bug fix was made.
  The phase gate is not declared passed; patched-library verification remains
  pending in a suitable environment.
  Full Flutter suite on the clean moved tree matches the observed original
  baseline exactly: **12,855 identities**, **12,794 pass**, **13 failures**,
  **28 errors**, **20 skips**; no additions, missing identities, status changes
  or newly skipped tests. Flutter 3.44.8 / Dart 3.12.2, stable before/after
  tested-tree fingerprints; comparison PASS. Raw reporter emits one repeated
  success event; identity-based totals are used, as required by the plan.
  Evidence: `p1/gate-checker*`, `compile-after-moves.log`,
  `kotlin-warnings-comparison.json`, `analyze-comparison.log`,
  `flutter-source-anchors-verified*`, `release-build.log`,
  `mapping-result.json`, `moved-bytecode-inventory.json`, `check_mapping.py`,
  `release-provenance.json`, `release-{mapping,configuration,seeds,usage}.txt`,
  `decoder-verification.log`, `decoder-provenance.json`,
  `decoder-missing-all-abis.json`, `flutter-gate*`, `junit/p1-gate/`.

- 2026-10-07 — **Independent phase-1 post-review complete** using
  `~/bin/codex-run`, gpt-6.1-sol / xhigh, session
  `01a1166b-1dce-7c23-a4e0-1f4684ac7888`. **No P1s; no production-source
  regression found**. Independently verified zero-diff PSI comparison, all
  24 self-tests, all 278 patches/XML archives, all 27 named proofs, the seven
  exact survivors, helper/anchor retargets, sizes, protected inputs, complete
  mapping/DEX coverage and exact JVM/Flutter comparisons. R8 representation
  refinement is accepted as preserving rule 5 without weakening it. Review
  flags P2: required patched-library decoder gate remains unmet (existing
  local environment limitation), and P3: explicit ring repaint-request tests
  before phase 3. Both are recorded in Follow-ups; no source edits requested
  for this move batch. Evidence: `p1/post-review/review.md` and independent
  audit JSON/logs. Launcher was resumed once after its background process
  ended before a report; the completed review used the same verified model
  and read-only session. **Stopped after phase-1 moves and gate checks;
  decoder gate pending. No phase 2, push, device or emulator work.**
- 2026-10-07 — post-implementation reviews of `f4e83b026..f63d9f297`.
  Claude: five scratch tampers (retained-code delay, moved literal,
  newline-only, retained declaration order, invalid literal) all fail the
  checker; size baseline differs only in the activity count
  (22,221 → 19,961); `AutoSyncRingView(this)` construction unchanged; new
  declarations are `internal` in `com.debrify.app.tv` and compile without
  clashes. Independent Codex review (fresh session): **No P1s**; visibility
  audit over 92 package files, retargets, 327 mutation patches and gate
  evidence re-verified. **P2 (pending, environmental):** the decoder
  verification script fails on all ABIs because local release builds package
  the pinned fallback media_kit jars (the patched PGS-capable bundle is built
  only on Linux CI by `dev/scripts/build_android_media_kit_libraries.sh`);
  native/library/build inputs are unchanged by this phase and the packaged
  binaries are byte-identical to the fallback jars. Not claimed as passed:
  the CI release build's decoder verification is on the end-of-series
  checklist. **P3 → phase 3:** add invalidation (repaint-request) assertions
  with mutation proofs for `AutoSyncRingView` colour changes, animator
  updates and stop/reset.
- Phase 1 complete; merged into `refactor/codebase`.

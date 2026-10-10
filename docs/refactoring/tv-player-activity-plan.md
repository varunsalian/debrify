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
| 2 | Activity-pure helpers (46 names), Flutter request functions, `IptvLiveLoadErrorPolicy` (see phase 2) | 900 | low |
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

## Phase 2 — activity-pure helpers, Flutter request functions, IPTV load-error policy

Branch `refactor/tvplayer-p2` off `dcbd9aafe` (phase 1 merged). Evidence
under `refactor-evidence/tvplayer/p2/`. Line numbers below are at
`dcbd9aafe` (activity 19,961 lines). The full verified inventory (purity
proof per identifier, callers, collisions, reflection/anchor checks, the
88 "almost-pure" exclusions) is the "Phase 2 inventory" section of the deps
report.

**Why this phase is smaller than the phase map estimated.** A complete
fixpoint scan of all 487 member functions found only 46 names (47
declarations, 784 lines with KDoc) whose bodies touch no activity member.
Phase 2 moves exactly those (plus one policy class); everything else needs a
signature change and belongs to a later, feature-owned phase. Expected
removal ≈ 900 lines.

### Moves (verbatim, top-level `internal fun` in package `com.debrify.app.tv`)

Call sites do not change: a top-level function of the same name resolves
identically once the member is gone, and the inventory proves no same-name
member/overload remains in the class, no star/same-name import or
extension exists in the package, and the only same-name member elsewhere
(`SubtitleLinePickerController.formatTime`) is a class member that keeps
winning inside its own class.

| Destination | Contents (inventory group) |
|---|---|
| `IptvLoadErrorPolicy.kt` | A: `classifyIptvError`; plus `IptvLiveLoadErrorPolicy` (below) |
| `IptvPayloadParsing.kt` | B: `parseIptvSources`, `parseIptvLists`, `parseStringList`, both `parseIptvChannels` overloads (must move together), `iptvChannelEntry` |
| `IptvRecordingUrlRules.kt` | C: `isSegmentedStreamUrl`, `xtreamTsTwin`, `sanitizeRecordingName`, `recordingTimestamp` |
| `IptvEntryRules.kt` | D |
| `StremioTvGuideData.kt` | E |
| `TvTrackLabels.kt` | F |
| `SubtitleSearchQuery.kt` | G |
| `TvPlayerFormatting.kt` | H |
| `UnifiedMenuRows.kt` | I (`mrow`) |
| `TvStartupDiagnostics.kt` | J |
| `PlaylistNavigationMaps.kt` | K (`rebuildNavigationMaps`) |
| `TvPlayerFlutterRequests.kt` | L: `requestStreamFromFlutter`, `requestMovieMetadataFromFlutter`, `requestIptvEpg`, `reportIptvStreamResult`, `requestQuickPlayNextEpisode`, plus `requestIptvStreamUrls` with its nested `IptvStremioCandidate` (becomes top-level `internal`) |

These request functions only use `MainActivity.getAndroidTvPlayerChannel()`
and their parameters; method names, argument maps, callbacks, the
`requestIptvEpg` private 45 s watchdog Handler and threading stay
byte-identical (verbatim move). The bridge *seam* (an injectable interface)
is not introduced here; it arrives with the first phase that needs to fake
these calls for a stateful collaborator.

**Companion constants.** `SEARCH_SUBTITLE_LABEL` and
`STARTUP_FAILOVER_LOG_TAG` (single users that move) become `private const
val` in their destination file; `EXTERNAL_SUBTITLE_PREFIX` and
`PROVIDER_PIKPAK` (also used by retained code) become top-level `internal
const val` in the destination and leave the companion. Retained unqualified
references resolve to the top-level constant; `const` inlining is unchanged.
Step 0 greps that nothing references them qualified
(`AndroidTvTorrentPlayerActivity.X` / `Companion.X`) in Kotlin, Java, Dart
or tests (none at planning time).

**Opt-in annotations.** Moved code using Media3 `@UnstableApi` APIs loses the
activity's class-level `@OptIn(UnstableApi::class)`; each such moved
declaration gains exactly `@OptIn(UnstableApi::class)` using
`androidx.annotation.OptIn` (declared substitution, listed per declaration in
the manifest). The required set is fixed now, not lint-driven:
`languageOfOverride`, `buildAudioTrackLabel` (`Format.bitrate` is
`@UnstableApi` in Media3 1.8.0) and `IptvLiveLoadErrorPolicy`
(`DefaultLoadErrorHandlingPolicy`). `classifyIptvError` uses only stable
Media3 APIs and gets **no** annotation (corrected at step 0 from the
Media3 1.8.0 bytecode, confirmed with `javap`; see Progress); step 0 re-derives the set from the Media3 1.8.0
class annotations and stops if it differs. No file-level opt-in.
Android lint's `UnsafeOptInUsageError` result for the module must be
unchanged (run `./gradlew :app:lintDebug` at base and gate and compare the
issue set).

**`IptvLiveLoadErrorPolicy`** (`private inner class`, 700–749) becomes
`internal class IptvLiveLoadErrorPolicy(private val liveNow: () -> Boolean)
: DefaultLoadErrorHandlingPolicy()` in `IptvLoadErrorPolicy.kt`; the 2-line
`liveNow()` member is deleted and its expression moves verbatim into the
single call site (≈2960):
`IptvLiveLoadErrorPolicy { iptvChannels.getOrNull(currentIptvIndex)?.isLive == true }`.
The body (713–748) is verbatim: `liveNow()` invokes the function-typed
property with the same syntax. **Checker encoding** (matches the
implemented semantics: `patched` rows stay in the original file, `moved`
rows carry substitutions): the policy class is a `moved` row whose declared
substitutions are exact token sequences with occurrence counts for (1) the
annotation/header (`private inner class IptvLiveLoadErrorPolicy :` →
`@OptIn(UnstableApi::class)` + `internal class IptvLiveLoadErrorPolicy(
private val liveNow: () -> Boolean,) :`) and (2) deletion of the 2-line
`liveNow()` member; `setupPlayer` is a `patched` row (retained in the
activity) with the single call-site patch. The checker compares the entire
resulting declarations. Step T of phase 2 extends
`dev/tool/test_kotlin_moves.py`'s fixture materializer to apply `patched`
rows and moved-row substitutions, and adds a **complete phase-2 extraction
fixture** (all moves, the companion-constant relocation, the policy's
substitutions and the caller patch) that must pass, plus negatives: an
extra edit inside the policy beyond its substitutions, and an extra edit in
`setupPlayer` beyond its patch. Both must pass/fail before any production
move. Threading, evaluation time (each `getRetryDelayMsFor` /
`getMinimumLoadableRetryCount` call reads the fields on the loader thread
exactly as before), instance count (one per factory build) and captured
lifetime (the lambda captures the activity as the inner class did) are
unchanged. The non-volatile read stays a recorded follow-up.

**Not in phase 2** (move with their features): `TvSourceAddon` (phase 6),
`SkipSegmentRequest`/`SleepTimerMode` (phase 3), `DockSkinSpec` (phase 7),
`ShufflePlaybackAttempt` (reflected by name — phase 7), the 88 almost-pure
functions.

### Step 0 — characterization of the original

- Each moved pure helper is exercised directly through
  `TvPlayerOriginalAccess` (reflection on an un-created
  `Robolectric.buildActivity(...).get()` instance for private members;
  binary names for nested types), covering every branch the body has
  (inputs → outputs, including null/empty/malformed JSON, overload
  dispatch between the two `parseIptvChannels`, regex edge cases in
  `xtreamTsTwin`/`isSegmentedStreamUrl`, formatting boundaries, label rules,
  diagnostics strings, navigation-map construction).
- Flutter request functions: a test installs
  `MainActivity.setAndroidTvPlayerChannel(MethodChannel(recordingMessenger,
  "com.debrify.app/android_tv_player"))` (saving and restoring the previous
  static channel in `@After`). The fake `BinaryMessenger` flips each
  outgoing request buffer and decodes it with
  `StandardMethodCodec.decodeMethodCall` to assert method names and exact
  argument maps; replies are built with `encodeSuccessEnvelope` /
  `encodeErrorEnvelope` (buffers flipped before the channel decodes them), and **posts replies through a main-looper
  Handler** (production `MethodChannel` invokes results on the replying
  thread; a synchronous fake would misrepresent timing). It distinguishes a
  raw-`null` reply (`notImplemented`) from an encoded-null success envelope,
  and supports error envelopes and a `send` that throws. Pinned per function:
  success/error/notImplemented mapping; the null-channel path (stream-URL
  request fails synchronously; torrent-stream and movie-metadata requests
  invoke no callback; EPG failure posts asynchronously); send exceptions
  (stream-result reporting swallows, quick-play next-episode propagates);
  the `requestIptvEpg` 45 s watchdog under a PAUSED looper (fires
  `callback(null)` once at 45 s; a reply before it wins; a reply after the
  timeout does not call back twice); and **real default-argument dispatch**
  of `requestIptvEpg` with `includeCatchupMetadata` omitted, for
  `entry.isCurrent` true and false.
- Reflection access selects members by **parameter types**, not by name and
  arity (`TvPlayerOriginalAccess` gains typed selectors), so the two
  one-argument `parseIptvChannels` overloads (`JSONArray`, `List<*>`) are
  each exercised directly.
- `IptvLiveLoadErrorPolicy`: one policy instance per test; the activity's
  `iptvChannels`/`currentIptvIndex` are changed **between calls** (live →
  non-live → invalid index) and both `getRetryDelayMsFor` and
  `getMinimumLoadableRetryCount` are exercised each time, proving the state
  is read per invocation, not snapshotted. Boundaries: retry-count 4/5 and
  15/16, Retry-After fallback and clamps, per HTTP status/exception class,
  and non-live delegation to the superclass. After the move the helper
  retargets to the constructor supplier and additionally asserts the
  supplier is not evaluated at construction and runs on the invoking
  thread.
- Mutation proofs on the original for every test; Claude samples further
  mutations; 0b closes survivors. New JVM baseline `p2-step0`.

### Gate, review, device checks

As rule 6 (JVM identities vs `p2-step0`, checker incl. the moved policy
with its substitutions and the patched `setupPlayer`, lint opt-in comparison, size baseline, release build + mapping
check, decoder check recorded as pending-environment if the patched bundle
is unavailable, full Flutter suite). Reviews as rule 8. Also carried from
phase 1 → phase 3: `AutoSyncRingView` repaint-request coverage.

Device checklist (end of series): IPTV live channel with a flaky source
(retries/live-edge behaviour), IPTV start-up from a payload with sources,
lists and categories, a recording start (file name), subtitle search
(query/identity row), track menus (labels), Stremio TV guide data,
quick-play next episode, EPG load on a slow provider (45 s timeout path).

## Phase 3 — first stateful collaborators: sleep timer, skip segments, Up Next card, IPTV recording actions

Branch `refactor/tvplayer-p3` off the phase-2 merge `ec365eb80` (activity 19,017 lines). Evidence under
`refactor-evidence/tvplayer/p3/`. The feasibility inventory (owned state,
every inbound reference, outbound host needs, timers and teardown position,
`this`-ambiguity and `::x.isInitialized` hazards, per-feature substitution
and patch counts) is the "Phase 3 inventory" section of the deps report;
line numbers there are at `dcbd9aafe` and are re-measured on the phase-2
merge before the manifest is written.

**Re-estimate (honest scope).** The phase map's sizes were optimistic: most
of the activity is stateful and cross-coupled. Phase 3 moves ≈ 810 lines
(≈ 580 if skip segments are deferred) for ≈ 54 declared activity edits. The remaining phases are re-planned after
phase 3 with the same per-feature feasibility method; expect more, smaller
phases than the original seven.

**Selected features** (ranked by patch count and risk in the inventory):
sleep timer (≈ 68 lines, 13 call-site patches), skip segments (≈ 230, 8),
Up Next card (≈ 118, 12), IPTV recording actions (≈ 395, 21). **Status pill
deferred** (design round 1): keeping its 40 call sites verbatim needs
delegators, i.e. one original declaration with two verified outputs, which
the checker does not model; it moves later together with its callers. **Deferred, with reasons:** PikPak
retry (shares `pikPakRetryId` with the startup gate → phase 6), auto-sync
pill (belongs with the auto-sync engine → phase 4), "Next" overlay (one
patch per line; reflected by a test → phase 6/7).

### Collaborator pattern (applies from phase 3 on)

- Each feature becomes `internal class Tv<Feature>Controller(...)` (house
  pattern) in its own file. Its owned fields and functions move **verbatim**
  into the class body, in original order, with only declared substitutions:
  `this` (when it means the activity/Context) → `activity`; inherited
  Activity members (`isFinishing`, `isDestroyed`, `runOnUiThread`,
  `findViewById`, `getSharedPreferences`, `resources`, `window`,
  `currentFocus`, `startService`) → `activity.` qualified; inherited
  *static* members (`MODE_PRIVATE`) → `Context.MODE_PRIVATE`; host
  state and calls → `host.x`. A `this` that refers to an anonymous
  `Runnable`/`object` (inventory lists them, e.g. the Up Next ticker) is
  never substituted; the checker gets each substitution with an exact token
  context and occurrence count, so a wrong `this` cannot be rewritten
  silently.
- **Injected activity type.** Each controller receives the activity as
  `activity: AppCompatActivity` (the activity's direct superclass), never
  `Activity`/`Context`, so every `this` → `activity` substitution keeps the
  original static type's overload resolution (e.g. Glide 4.16.0
  `with(FragmentActivity)` → activity-lifecycle request manager, whereas
  `with(Activity)` → application context). Step T lists every substituted
  `this` site whose callee is overloaded on Context/Activity/
  FragmentActivity/LifecycleOwner and records the resolved overload before
  and after (from the compiled bytecode) — any difference fails.
- **Cross-feature state** has one owner: when a moved feature reads another
  moved feature's state (Skip reads Up Next visibility to suppress credits
  skipping and focus offers), its Host getter reads the **owning
  controller** through the activity (`this@AndroidTvTorrentPlayerActivity.
  upNextController.x`), never a mirrored copy.
- **Host interfaces** are narrow (only the members the moved bodies use) and
  are implemented by an `object : Tv<Feature>Controller.Host { … }` inside the
  controller's property initializer in the activity. Host members are
  one-line forwarders to existing activity members (no logic), and their
  binding is fixed: properties are **computed** (`override val player get()
  = this@AndroidTvTorrentPlayerActivity.player`, `override var x get() = … set(v)
  { this@AndroidTvTorrentPlayerActivity.x = v }`), never initialized `val`s
  (no snapshot, no premature `lateinit` read); every forwarder targets
  `this@AndroidTvTorrentPlayerActivity` explicitly (a same-name unqualified
  reference inside the object would recurse); no Host member is read during
  construction. The activity's class header does not change.
- **Construction order.** The controller property is declared exactly where
  the feature's field block was, so property-initializer order and creation
  time of Handlers/scopes are unchanged (Handlers and the skip coroutine
  scope are created in the controller's own initializers, in the same
  relative order).
- **`::x.isInitialized`** cannot be qualified across objects. Each such check
  becomes an **activity-owned** private getter with the identical expression
  (`private val skipSegmentButtonReady: Boolean get() =
  ::skipSegmentButton.isInitialized`, an `added` declaration), which the Host
  forwards explicitly; it is evaluated at the same moment as before; the
  moved-code use is a declared substitution.
- **String templates.** A host-qualified name inside a template must use the
  braced form: `$skipSegmentProviderId` → `${host.skipSegmentProviderId}` (a
  bare `$host.x` would interpolate the Host object). Declared per occurrence;
  a checker negative proves the unbraced form fails.
- **State not cleanly ownable stays** in the activity behind the host (e.g.
  `sleepStopLatched`, written in 5 places, read on 7 playback paths).
- **Teardown order is unchanged**: `onDestroy`/`onStop`/`onPause` keep their
  statement order; a moved cancel call becomes `controller.cancelX()` in the
  same position (a declared call-site patch). Borrowed handlers (e.g.
  `externalSubtitleHandler` for the status pill) stay owned and cleared by
  the activity; the controller never clears a borrowed handler.
- **Companion constants** used by one feature only move with it as
  file-private constants (Up Next ×3, skip ×2 incl. `IMDB_ID_REGEX`).
- **Reflection.** Kotlin mangles JVM names of `internal` members; tests that
  reflect moved members target `private` members or public members of the
  `internal` class, never an `internal fun`. Dart source-text anchors on
  `triggerUpNext`/`dismissUpNext` are retargeted to the new file with equal
  assertions.
- **Checker extensions (step T).** Destinations are partitioned
  exhaustively like the original: every span of every destination file is
  owned — moved members (selector = class + order, compared to the original
  plus substitutions) or **pinned structural spans** (class header,
  constructor and its defaults, `Host` interface, any other new declaration,
  file-level items), each compared to exact token text in the manifest; any
  unowned destination declaration fails. In the activity, `added` declarations
  (controller properties incl. their Host object, readiness getters) are
  pinned by exact text **and anchored to an original slot** (the position of
  the feature's first removed field), so a controller property cannot move
  among the initializers. Phase-3 fixtures are wired into
  `test_kotlin_moves.py`'s dispatcher; a complete phase-3 positive extraction
  fixture must pass before production moves. New negatives: an extra `this`→`activity`
  rewrite at an undeclared position, a host forwarder containing logic
  beyond its pinned text, a moved field reordered inside the controller, an
  `added` declaration differing from its pinned text, teardown statement
  reordering in `onDestroy`, an added constructor side effect, an unexpected
  `init` block in a controller, a changed Host declaration, a relocated
  controller property, an unbraced host template. Also: manifests are phase-scoped (each
  describes the activity at its own phase's completion), so the checker
  gains `--at <sha>` to verify a historical manifest against its phase's
  merge commit (phase 1 at `dcbd9aafe`, phase 2 at `ec365eb80`), and the
  integration checks run every manifest that way. In addition, every earlier
  phase's destination file is compared in the current tree against its
  approved revision (`ec365eb80`), with an explicit, reviewed whitelist for
  any later change (none expected in phase 3).

### Step 0 — characterization of the original

Behaviour through the activity's existing surface on the original
(Robolectric, PAUSED looper, reflection via `TvPlayerOriginalAccess`, fake
Flutter channel where needed), mutation-proved:

- **Sleep timer:** countdown arm/re-arm/cancel, minutes-left/value labels,
  end-of-item arming, fire order (cancel → latch → `sendProgress(completed =
  false)` → pause → release screen → toast), playbackListener interactions
  (end-of-item consumes and cancels), `onDestroy` cancellation, unified-menu
  rows wiring.
- **Skip segments** (prerequisite: a deterministic network fixture — a
  test-only Robolectric shadow of the private `SkipSegmentHttpClient` with
  latch-controlled responses, keeping the production coroutine body and
  IO/Main dispatch — demonstrated on the original first; if it cannot be made
  reliable, skip segments are **deferred** out of phase 3): the complete
  request key incl. provider id and stream duration (provider changes,
  different durations; mutation-prove the unbraced-template mistake),
  request construction (IMDb extraction, season/episode),
  cache bound (`MAX_SKIP_SEGMENT_CACHE_ENTRIES`), stale-result rejection
  (request identity), button visibility vs `hasEverBeenReady`, skip action
  seek target, reset on `playItem` (order: `hasEverBeenReady` reset → Up
  Next hide → skip reset), scope cancellation in `onDestroy`.
- **Up Next card:** the poster request's Glide lifecycle ownership (request
  manager bound to the activity's lifecycle; cleared on destroy) —
  mutation-proved by changing the original to
  `Glide.with(this.applicationContext)`; threshold/min-duration/tick constants, show/dismiss/
  trigger, ticker start/stop, interaction with `isCleanPlaybackState`, key
  handling while visible, `onDestroy` cleanup.
- **Skip ↔ Up Next wiring** through the production activity: showing Up
  Next suppresses credits skipping on the next skip-state update, dismissing
  it reveals skipping again, and focus offering keeps its original conditions
  (also exercised in the skip-deferred variant).
- (Status pill characterization moves with the feature to a later phase.)
- **IPTV recording actions:** gating (engine on, recordable URL, permissions
  path incl. SDK 28/29/33 branches), start/stop toggles for tee and engine
  recording (service-intent payloads), file naming (phase-2 helpers),
  `RecordingRegistry` listener add/remove order and a queued notification
  followed by listener removal before the looper drains (membership is
  evaluated when the posted notification runs), finalize/publication in
  `onStop`/`onDestroy` through a fake MediaStore provider, first-access timing
  of the lazy `recordingEngineEnabled` (preference changed before vs after
  first access) and the retained lazy tee, and profile/resource authorization
  evaluated **when the confirmation is clicked** (change while the dialog is
  open) followed by the persisted schedule payload.
- **Host liveness:** player replacement and view binding after controller
  construction are observed by the controllers (forwarding is live).
- **Carried from phase 1:** `AutoSyncRingView` repaint requests
  (invalidate on colour change, animator update, stop/reset).
- Claude's independent mutation sample; 0b closes survivors.

### Gate, review, device checks

As rule 6, plus: the teardown-order assertion of the checker; JVM
characterization re-run after moves unchanged except the access helper;
lint issue-set comparison. Device checklist (end of series): sleep timer
countdown + end-of-episode, intro/credits skip button and skip, Up Next card
near the end of an episode (auto-advance and dismiss), status pill messages
during source switching and subtitle loads, IPTV recording start/stop (tee
and engine), scheduled recording confirmation.

## Phase 4 — subtitle rendering/selection and the auto-sync engine

Branch `refactor/tvplayer-p4` off the phase-3 merge `eee52b084` (activity 18,265 lines). The phase-3 initializer-timing rule applies (moved initializers running earlier must be listed and proven inert, else slots preserved). Evidence under
`refactor-evidence/tvplayer/p4/`. The feasibility inventory (ranked
candidates, every inbound reference, ownership choices, hazards) is the
"Phase 4 inventory" section of the deps report; its line numbers are at
`ec365eb80` and are re-measured on the phase-3 merge before the manifest is
written.

**Selected:** two controllers following the phase-3 collaborator pattern
(all its rules apply unchanged: `AppCompatActivity` injection with the
overload audit, computed explicitly-qualified Host forwarders, slot-anchored
controller properties, activity-owned readiness getters, braced host
templates, cross-feature reads via the owning controller, no delegators,
teardown order unchanged):

- `TvAutoSyncController` — the auto-sync engine (manual run, ladder, verify
  pass, cue cache, audio-tap use) and its pill/ring UI wiring (≈ 516 lines).
- `TvSubtitleController` — external (Stremio) subtitle loading/rendering,
  subtitle track selection, the subtitle settings panel wiring and the five
  subtitle unified-menu row builders (≈ 571 lines).

≈ 1,087 moved lines for ≈ 28 activity call-site patches in 14 declarations;
no existing-test retargets expected. Lifecycle edits are in-place token
patches in `onStart`/`onStop`/`onDestroy`; statement order unchanged.

**Ownership.** `externalSubtitleHandler`, `subtitleScope`, the two sync
overlays (`syncOverlay`, `linePickerOverlay`) and `speechTap` stay in the
activity and are **borrowed** by the controllers through the Host (the
activity remains their owner and keeps clearing/cancelling them exactly
where it does today; `SubtitleSyncDismissTest` reflects the overlays on the
activity and stays unchanged). The controllers never clear a borrowed
handler or cancel a borrowed scope.

**Behaviour to preserve exactly** (from the inventory/survey): manual
auto-sync catches `Throwable` (the MiBox OOM fix) while the periodic verify
pass catches only `Exception`; ladder/verify timings; the pill's
heartbeat/announce/result UI and colours (there is **no** countdown);
subtitle offset and selection semantics; external subtitle ticker cadence on
the shared handler; `SubtitleCueCache` semantics as they are (an unbounded
map — no bound exists to preserve).

**Step T additions (overload audit).** The phase-3 bytecode auditor is
extended before any move: (a) resolution of **every constructor
invocation** whose arguments include the substituted receiver
(`AutoSyncRingView`, `TextView`, `LinearLayout`, both overlay controllers,
`Intent`, dialog builders, …), (b) **context aliases** (`val ctx = this`
and any later use of the alias), collected by the PSI adapter even when not
under a call expression, (c) an explicit, reviewed list of `this`
occurrences that are anonymous `Runnable`/object receivers (≈ activity lines
13607, 13628, 14384 at `eee52b084`) excluded from activity substitution, with
any unlisted `Runnable`-typed `this` failing. A complete phase-4 audit
fixture with negatives (wrong receiver classification, constructor resolved
to a different overload, unlisted alias) must pass first. `test_kotlin_moves.py`
dispatches a complete phase-4 production-config extraction fixture plus the
inventory's negatives (multi-block, cross-controller, default-argument,
shadowed-local), keeps all historical suites, and earlier destinations
(including the four phase-3 controllers) are frozen against `eee52b084`.

**Deferred with reasons:** progress reporter (needs 6 test retargets and an
edit to the phase-3 sleep `sendProgress` forwarder → its own phase);
display/audio/speed/night mode (20 patches inside `playbackListener`/
`setupPlayer`/analytics listener, native audio-effect lifetime → with the
playback core); unified-menu model (Host would need 61 members → split into
owning controllers as they move); status pill (34 of 40 callers move in
phase 6 → with them).

### Step 0 — characterization of the original

Prerequisites, **per feature**, each demonstrated on the original first and
keeping the production coroutine/handler dispatch:
- auto-sync: a deterministic seam for the subtitle aligner (alignment can be
  **blocked** by a latch to test subtitle replacement and destruction while a
  result is pending) and the audio tap;
- subtitles: a latch-controlled **uncached** cue fetch (test-only shadow or
  MockWebServer, as phase 3's skip HTTP shadow) proving IO execution, Main
  publication, failure fallback, superseded loads (stale token) and destroy
  during fetch — seeding the cache is not sufficient (hits return
  synchronously and skip the guarded path).
Fixtures release and settle their workers during cleanup. **A feature whose
own prerequisite fails is deferred**; only features whose prerequisites
pass are moved, and a reduced set (e.g. subtitles only, or subtitles +
progress reporter) gets revised inbound patches, characterization and a
design re-review before execution.

- Auto-sync: manual run success/failure/OOM (`Throwable`) paths, ladder
  steps and timings, verify pass (`Exception` only), restore/decline result
  states, pill transitions (heartbeat/announce/result, busy/ok/fail colours,
  label, ring pulsing on/off), auto-sync work **continuing across `onStop`**
  (pinned as-is; a recorded follow-up), and destroy-only subtitle-scope
  cancellation plus shared-handler clearing.
- Subtitles: external subtitle load/render ticker cadence, stale-load
  rejection, selection (embedded vs external, off), offset changes, settings
  panel callbacks, the five menu rows' labels and actions, `onStart`/`onStop`
  resume/suspend behaviour.
- Mutation proofs on the original; Claude's independent sample; 0b.

### Gate, review, device checks

As rule 6 plus every phase-3 gate addition. Device checklist (end of
series): external subtitles (load, timing, offset), subtitle track switching
incl. off, subtitle settings panel, auto-sync manual run + automatic verify
(incl. a long file on a low-RAM box), the auto-sync pill states.

## Phase 5 — progress reporter, IPTV channel start + Stremio candidate ladder, Start Over

Branch `refactor/tvplayer-p5` off the phase-4 merge `1a33c42cb` (activity 17,205 lines). Evidence under
`refactor-evidence/tvplayer/p5/`. The feasibility inventory (incl. the
complete writer/reader table of the IPTV shared token fields, Appendix 2) is
the "Phase 5 inventory" section of the deps report; lines are at
`eee52b084` and are re-measured on the phase-4 merge. All phase-3/4
collaborator rules apply unchanged (incl. the extended bytecode overload
audit and the initializer-timing rule).

**Selected (≈ 792 moved lines, ≈ 36 activity edits in 19 declarations):**

- `TvProgressReporter` — `sendProgress`, the final-progress snapshot and
  recovery staging/ack handling (≈ 266 lines, 12 edits in 8 declarations +
  1 edit to the phase-3 sleep controller's Host `sendProgress` forwarder. That
  forwarder lives in the **activity's** `sleepTimerController` property, so
  it is a phase-5 `patched` row on that whole activity property (the single
  forwarder replacement, a reason, the named sleep characterization test and
  an extra-edit negative); the phase-3 manifest and controller file stay
  unchanged and no earlier-destination exception is used). `sendFinished` stays
  in the activity (a whole-file Dart test pins its payload). The two edits
  inside `recordPlaybackLifecycle`'s string template use braced host
  references. Retargets: 5 reflective calls in
  `StremioTvStartupWatchdogTest` and 1 Dart anchor
  (`manual_source_validation_contract_test.dart`), each with equal assertions.
- `TvIptvChannelStartController` — watch registration + startup-channel
  memory and the Stremio candidate ladder together with
  `beginIptvPlayback` (14 of the ladder's 23 inbound references are there).
- `TvIptvStartOverController` — owns `iptvCatchupToken` and the catch-up
  request flow; the three Start Over status flags stay in the activity
  (written by live recovery, the player error path and channel switch).

**IPTV split rule (from the inventory).** Only guide + browse + zap paging +
channel switch (+ `initIptvMode`) must move as one unit, because six shared
token/context fields (`iptvUiContextToken`, `iptvBrowseToken`,
`iptvZapRequestToken`, `iptvZapOwnsUiContext`, `iptvZapRequestInFlight`,
`iptvZapPendingInputs`) are written by both guide and zap code. Phase 5 moves
none of that core and none of those fields; each phase-5 async guard is owned
by exactly one controller. Planned order afterwards: zap banner (split
classic/styled to stay ≤ 800 lines per file), then core + EPG + VOD as one
multi-file unit; live dock styling with the controls phase; tune pipeline,
twin trial and live recovery with the playback core.

**Hazards for step T** (all must be fixtures/negatives): shadowed locals
`window` and `currentIndex` (no host substitution), the `this.index`
receiver that must not be rewritten, default arguments that read activity
state (evaluated at call time — must stay so), and controllers constructed
before the `iptvBrowseHandler`/`progressHandler` they borrow (Host getters
are computed, never read at construction; the 16 earlier-running moved
initializers are listed and proven constant/empty-allocation).

**Step T (checker).** The initializer classifier gains narrowly constrained
support for the forms phase 5 needs — typed empty collection factories
(`mutableSetOf<String>()` and siblings with explicit type arguments and no
arguments) and numeric literals with underscores/suffixes (`1_000L`) —
preserving the original expressions; negatives reject state-reading or
effectful initializers. A complete phase-5 production extraction fixture
exercises all 16 proofs. `test_kotlin_moves.py` dispatches per manifest
phase: the historical phase-4 suite runs with its own manifest, a new
phase-5 extraction/negative suite runs with the phase-5 manifest, and all 28
earlier destination files are frozen against `1a33c42cb`.

### Step 0 — characterization of the original

- Progress: every `sendProgress` path (periodic, completed, paused, sleep,
  final snapshot in `finish`/`onStop`/`onDestroy` incl. the non-try/finally
  `onStop` difference — exercised by injecting a player-read failure
  **outside** the delivery catch, since messenger send failures are caught),
  argument maps sent to Flutter, ack handling (delayed and out-of-order ACKs,
  ACK after destroy) and recovery staging (`TvPlaybackRecoveryStore`) through
  a test-only reflected **executor barrier** on the store's separate writer
  executor (bounded latch waits, cleanup), proving ordinary ticks queue their
  writes while final/completed/local-completion checkpoints persist before
  delivery or teardown; and the reflective contracts the watchdog test uses.
- Channel start: watch registration payload, startup-channel memory
  read/write, `beginIptvPlayback` ordering, Stremio candidate ladder
  (candidate order, failure advance, winner reporting, token supersession,
  `isFinishing` guard) with the recording fake channel.
- Start Over: catch-up request/token supersession, timeline/flag effects as
  observed through the retained flags, cancellation on stop/destroy.
- Mutation proofs on the original; Claude's independent sample; 0b.

### Gate, review, device checks

As rule 6 plus every phase-3/4 gate addition. Device checklist (end of
series): resume position saved on exit/stop/sleep and restored next launch;
Trakt/Simkl progress after watching; IPTV channel start incl. a Stremio
IPTV channel with failing first candidates; startup channel remembered;
Start Over / catch-up on an archive-enabled channel.

## Phase 6 — IPTV zap banner (classic controller + styled renderer)

Branch `refactor/tvplayer-p6` off the phase-5 merge `e71ddac3a` (activity 16,487 lines). Evidence under
`refactor-evidence/tvplayer/p6/`. The feasibility inventory is the "Phase 6
inventory" section of the deps report (measured at `1a33c42cb`; re-measure
on the phase-5 merge — both phase 5 and the banner patch
`switchToIptvChannel`). All collaborator rules from phases 3–5 apply.

**Re-planned remainder (honest scope).** The phase-6 inventory measured the
rest of the activity: ≈ 12 more phases after this one (order: 7 Stremio TV
guide "lite"; 8 startup/manual gate + source switcher + badge; 9 fetch-more
+ episode fetch + PikPak + status pill; 10–11 IPTV core + EPG + VOD; 12
IPTV tune pipeline + live recovery; then controls I/II (Next overlay in II),
playlist overlay + guide skin, shuffle + subtitle fetch, playback start +
media pipeline + metadata receiver, unified menu split by owner; the two
routers — `playbackListener` and `dispatchKeyEvent` — last, possibly never).
**Expected end state:** the activity cannot reach 800 lines under these
rules — Host wiring alone is ≈ 800 lines and grows as code leaves. Realistic
final size ≈ 2,800–3,600 lines (≈ 2,100–2,700 if the routers move), holding
lifecycle/teardown order, the composition root and Host objects, shared
single-owner state, `bindViews`/`parsePayload`. That will be recorded as a
documented end exception with responsibilities and an exit path when the
series reaches it.

**Selected:** the zap banner (≈ 1,304 lines, 47 members): 16 activity patches
in 9 declarations; no test or Dart retargets; no lifecycle edits; no
coupling with phase-5 controllers. Structure (inventory's recommendation):
`TvIptvZapBannerController` (classic, ≈ 660 lines) constructs
`TvIptvZapBannerStyledRenderer` (≈ 700 lines) and passes itself; the styled
code's 38 references to 19 classic members become explicit `classic.x`
substitutions and the classic code's 4 dispatch calls become `styled.x`, so
any missed qualification fails to compile. The activity provides a single
19-member Host. Extension functions are rejected (size-rule evasion).
**Initializer timing:** the renderer is constructed inside the classic
controller, so *all eight* renderer fields run at the classic controller's
construction slot, and every classic field after its first does too —
**28 inert proofs** in total under the existing all-later-fields rule (no
contiguous-block exemption). ≈ 281
declared substitutions incl. 122 `dp` calls and 42 overload-audit sites
(4 `Glide.with`).

**Step T.** Checker support for a destination class that constructs a second
destination class (both pinned structurally; the renderer's constructor
argument and its initializer position inside the classic controller pinned;
**effective construction-slot mapping** so the renderer's fields are proved
against the classic controller's slot), the initializer classifier extended
narrowly for `Any()` and `Color.parseColor("<string literal>")` (literal
argument only), a complete production extraction fixture with all 28 proofs,
negatives for a missing renderer-first-field proof and for reading
`classic`/Host during construction, the `classic.`/`styled.` cross-qualification substitutions
with occurrence counts, and negatives (missed qualification compiled against
a same-name Host member, renderer constructed lazily vs eagerly, swapped
dispatch target). Per-phase dispatcher; earlier destinations frozen at the
phase-5 merge.

### Step 0 — characterization of the original

The banner style and guide tokens are cached lazies, and the builder returns
the existing tree before checking tokens, so style is fixed per activity
session: characterize **four separate activity instances**, one per style,
and prove that a preference change mid-session keeps the existing session's
style and tree. Assert directly: view hierarchy, drawable properties,
typography, progress, floating vs docked transitions, show/hide timing,
now/next/EPG text, channel number/name/logo (Glide request lifecycle
owner), the **LIVE/REC** badges, and favourites-gated jump-hint visibility.
The two styled `paint…` functions mutate views (they do not draw through
Canvas) — assert their view effects; a recording canvas is used only where a
drawable's own drawing is shown to be observable. Pin as-is: an explicit hide
cancels the tick token but leaves the pending hide callback posted; layout
listeners are never removed (recorded follow-up). Mutation proofs on the
original; Claude's independent sample; 0b.

### Gate, review, device checks

As rule 6 plus phase 3–5 gate additions. Device checklist (end of series):
zap banner in classic and each styled guide style while zapping channels
(up/down, number entry), logos, EPG now/next, LIVE/REC badges, the
favourites-gated jump hint, floating vs docked banner.

## Phase 7 — Stremio TV guide ("lite")

Branch `refactor/tvplayer-p7` off the phase-6 merge `a4ed4f368` (activity 15,167 lines). Evidence under
`refactor-evidence/tvplayer/p7/`. Source: section B of the "Phase 6
inventory" (measured at `1a33c42cb`; re-measure on the phase-6 merge). All
collaborator rules from phases 3–6 apply.

**Selected:** `TvStremioTvGuideController` — 30 members, ≈ 529 lines: the
guide-ready wait (`hideGuideWhenReady`, `cancelGuideWait`, listener +
timeout fields), guide init/setup/show/hide/toggle/filter/header,
focus-in-list check, lazy guide-data requests, `requestStremioTvNext` and
`switchToStremioTvChannel`, plus the contiguous owned state block
(`stremioTvChannels`, 9 view refs, adapter, visibility/in-progress flags,
`stremioTvSwitchToken`). `isStremioTvMode` stays in the activity (Host
`var` forwarder). The media-start trio (`updateStremioSourcesFromPlaybackMap`,
`replacePayloadWithStremioTvItem`, `playStremioTvPlaybackMap`) stays for the
playback-start phase; the controller reaches `playStremioTvPlaybackMap`
through a Host forwarder (re-pointed when the trio moves).

16 activity patches in 6 declarations; 12-member Host; ≈ 68 declared
substitutions (21 host, 36 Android incl. `runOnUiThread` ×12 and
`finish()` ×6 — which must stay `activity.finish()` so the activity's
`finish` override still runs — `findViewById` ×9, `currentFocus`, 8 `this`
sites; 11 visibility changes). Overload audit: `LinearLayoutManager(this)`,
`Glide.with(this)`, 2 `Toast` + 4 `this@…` Toasts inside
`MethodChannel.Result`. `playerView.findViewById` stays host-qualified (not
the inherited `findViewById`). Default argument `finishOnFailure = false`
stays evaluated at call time. **Initializer timing:** 17 owned properties
(15 in the contiguous block, plus the guide-wait listener/runnable) move into
the controller, constructed at the first property's slot, so **16**
initializers run earlier and each gets an exact inert proof (no
contiguous-block exemption). The Host forwarder to the retained trio is the
real five-argument `playStremioTvPlaybackMap(channel, map, url, title,
hideGuideOnReady)` (Next passes `false`, switching passes `true`).

**Step T.** Per-phase dispatcher: the phase-6 suite keeps running with the
historical phase-6 manifest; a complete phase-7 extraction fixture and
negatives (incl. omitting a contiguous-field proof, a forwarder dropping or
hard-coding `hideGuideOnReady`) run separately; compiled audit of all eight
receiver sites; the 33 earlier destination files are frozen against
`a4ed4f368`. One reflective retarget:
`StremioTvStartupWatchdogTest` calls `initStremioTvGuide` by name — it
becomes a **public** member of the internal controller and the test's local
`call` helper routes it to the controller (assertions byte-identical).

**Follow-ups pinned as-is (not fixed):** `stremioTvSwitchToken` is not bumped
in `onDestroy`; the guide-ready listener and 10 s wait are not cancelled
there.

### Step 0 — characterization of the original

Guide init from JSON (channel parsing, current flag, inline now/next,
`isStremioTvMode` set, playlist button repurposed only for
`PlaylistMode.NONE`); show/hide/toggle with focus and scroll-to-current
(`post` + 150 ms); search filter; header binding (poster vs letter, Glide
lifecycle owner); lazy guide-data for the visible range and row merge;
`requestStremioTvNext` (no current channel → toast and optional finish, null
bridge, success → trio with no guide wait, empty URL, error, notImplemented,
stale token, 1.5 s overlay hide); `switchToStremioTvChannel` (flags, stale
token, rollback of `isCurrent`/`isSwitchingChannel` marks on failure, and a
**successful switch through the real retained trio** with a recording player:
media-start order, channel/adapter updates, guide-wait registration and
READY-triggered hiding — contrasted with Next's no-wait path); guide-data
replies, which do **not** check the switch token (only Next/switch callbacks
do): a reply after token advancement, partial replies (only valid returned
entries clear loading; omitted ones stay loading), malformed replies, a null
bridge (guide-data loading stays set; a switch stays in progress with its new
current/switching marks), error/notImplemented/send-exception cleanup — all
pinned as-is; guide-ready
wait (`READY` hides, `IDLE` clears switching marks, 10 s fallback,
`cancelGuideWait` removes the listener from the current player). Fake
Flutter channel with async main-looper replies (phase-2 messenger).
Mutation proofs on the original; Claude's independent sample; 0b.

### Gate, review, device checks

As rule 6 plus phase 3–6 additions. Device checklist (end of series):
Stremio TV mode — open/close the guide, search, switch channels (incl. a
failing channel), next-item auto-advance, guide closes once playback is
ready, back-key behaviour inside the guide list and search box.

## Phase 8 — Stremio source switcher (selection + badge + apply)

Branch `refactor/tvplayer-p8` off the phase-7 merge `53906805d` (activity 14,637 lines). Evidence under
`refactor-evidence/tvplayer/p8/`. The inventory is the "Phase 8 inventory"
section of the deps report (measured at `a4ed4f368`; re-measure on the
phase-7 merge — phase 7's guide-wait members sat between switcher members).
All collaborator rules from phases 3–7 apply.

**Scope decision (switcher first, gate next).** The full gate + switcher +
badge unit is ≈ 1,398 lines with 109 patches, 31 initializer proofs, 15
`onDestroy` patches and 45 reflective watchdog-test sites. Phase 8 moves only
the switcher (≈ 768 lines; 23 patches in 19 declarations + 4 Host forwarder
re-points + 1 visibility patch; 1 initializer proof; ≈ 207 substitutions;
3 Dart anchor edits) and leaves every risky gate element — watchdog protocol,
the `onDestroy` block, listener/`resolveAndPlay` patches, the 45 reflective
sites, `finish()`, 29 of the 31 proofs — for phase 9 (gate, possibly paired
with PikPak to settle `pikPakRetryId`, measured then). Cost: ≈ 20 % more total
churn (11 Host forwarders into the gate, re-pointed when the gate moves).

**Structure** (phase-6 shape, no new checker feature):
`TvSourceSwitchController.kt` (selection + badge, ≈ 435 lines) eagerly
constructs `TvSourceSwitchApplier.kt` (switch apply, ≈ 450 lines) and passes
itself; one 51-member Host; activity property at the switcher's first owned
slot (≈ 12920 at `a4ed4f368`).

**Ownership / hazards.**
- `stremioResolutionToken` stays activity-owned (Host `var`; bumped by episode
  fetch, gate and switcher).
- `pikPakRetryId` stays activity-owned and is read **live** at fire time
  inside the reprepare Runnable (never snapshotted).
- `ShufflePlaybackAttempt` (private nested) becomes `internal` so the applier
  and the Host's `playItem` can name it; its JVM binary name is unchanged, so
  both reflective tests stay valid.
- `playItem` has two call shapes; the per-controller Host exposes exactly the
  shapes used (no interface defaults).
- `activeVodHeaders` is `@Volatile`; the applier writes it through a Host
  setter that writes the same field.
- Unbraced templates in moved code are braced per occurrence.
- The 4 Host forwarder re-points all belong to the `iptvChannelStartController`
  activity property: one whole-property `patched` row with exactly four
  substitutions. `progressReporter` references retained gate state and stays
  unchanged until the gate phase.
- 3 Dart anchors are retargeted (`automaticRecovery`, the
  `onStremioSourceSelected` start marker, `requireExactStartupEpisode`) with
  equal-or-stronger assertions.

### Step T

Phase-8 extraction fixture + negatives (missed `applier.`/`controller.`
qualification, snapshot of `pikPakRetryId`, dropped `playItem` shape,
non-volatile write path); per-phase dispatcher keeping all historical
suites; compiled overload audit; earlier destinations frozen at the phase-7
merge.

### Step 0 — characterization of the original

Source selection flows (manual pick, automatic recovery pick, same-source
reselect, episode-exact requirement), badge text/visibility, apply path
(media item rebuild, headers incl. the volatile `activeVodHeaders`, seek
restore, resolver token checks — both moved resolvers check the switch token
**only before** `runOnUiThread` dispatch (error/notImplemented likewise):
characterized by delivering a captured reply on a bounded worker thread,
superseding the token before draining the paused main looper, and verifying
the accepted UI action still runs; the playlist resolver's live cursor read
inside the UI block is preserved and no second guard is introduced; PikPak reprepare runnable reading the live retry id, shuffle
attempt interplay, `stremioResolutionToken` supersession), the sources panel
render/selection highlight, `cancelSourceSwitchWait` in `onDestroy`.
Mutation proofs on the original; Claude's independent sample; 0b.

### Gate, review, device checks

As rule 6 plus phases 3–7 additions. Device checklist (end of series):
switching sources from the Sources panel during movie and series playback
(resume position kept), automatic recovery to the next source after a dead
link, badge text, PikPak cold-storage source switch, switching during shuffle.

## Phase 9 — startup / manual source-switch gate

Branch `refactor/tvplayer-p9` off the phase-8 merge `c4906cd2f` (activity 13,937 lines). Evidence under
`refactor-evidence/tvplayer/p9/`. Inventory: "Phase 9 inventory" in the deps
report (measured at `53906805d`; lines after the switcher shift ≈ −700 once
phase 8 merges — re-measure on the phase-8 merge). All collaborator rules
from phases 3–8 apply. This is the highest-risk unit so far.

**Selected (option A — gate alone):** `TvStartupGateController.kt`
(≈ 700 lines; 46 members + 5 companion constants), 32-member Host, activity
property at the gate's first owned slot. 93 activity patches in 15
declarations (incl. 4 braced-template patches in `resolveAndPlay` and
`parsePayload`), 15 Host re-points as 2 `patched` activity-property rows
(`progressReporter` ×4, the phase-8 switcher Host ×11 — phase-8 destination
files stay byte-identical), 29 inert initializer proofs (all supported forms;
the second field block now runs before `recoveryStartedAtMs` and
`progressReporter`), ≈ 191 substitutions. PikPak retry is **not** paired:
pairing would not settle `pikPakRetryId` (its writers stay split), and adds
≈ 20 % more edits and new hazard classes; it moves next with fetch-more,
episode fetch and the status pill.

**Lifecycle.** The 15 gate statements in `onDestroy` stay **in place** as
single-reference patches (not folded into a controller call), after the final
progress snapshot and before `sendFinished`, in the same order.

**Hazards.** `finish()` becomes `activity.finish()` compiled as
`invokevirtual` so the activity's override still runs (its progress reads hit
the same gate fields); 2 `Runnable` self-references stay unsubstituted;
`pikPakRetryId` and `player` are read live at fire time inside the reprepare
Runnable; 3 `findViewById` + 1 Toast overload sites; the gate's 7
`sourceSwitchController.` references become `host.sourceSwitchController.`.

**Retargets.** Reflection: 45 watchdog sites, 7 progress-test sets, 18 gate
sites in phase-8 tests (incl. `TvSourceSwitchBoundaryCharacterizationTest`
setting `startupTryNextOnFailure`) — routed by **14** owner-map entries in
`TvPlayerOriginalAccess` plus one `when` branch in the watchdog test's local
`call` helper; 5 reflected functions become public members of the internal
controller; assertions byte-identical. Dart: 5 anchor edits in
`manual_source_validation_contract_test.dart` (incl. the host-qualified
`playItem(currentIndex, suppressTrakt = true)` text) plus one added assertion
so the gate's `sourcePersistenceSessionId` payload site stays pinned.

### Step T

Phase-9 extraction fixture + negatives (static/super `finish` dispatch, a
snapshotting forwarder for `pikPakRetryId`/`player`, a folded `onDestroy`
block, a missed `host.sourceSwitchController.` qualification), per-phase
dispatcher keeping all historical suites, compiled audit incl. the
`invokevirtual` `finish` descriptor, earlier destinations frozen at the
phase-8 merge. **Auditor extension:** the PSI collector also records reviewed
**implicit inherited-receiver** call sites (`finish()`, the 3
`findViewById`), the bytecode parser retains invocation opcodes, and each site
pins its expected before/after owner + descriptor + opcode (`finish` must be
`invokevirtual` on the activity so the override runs); compiled positives and
negatives prove virtual override dispatch and inherited-method resolution;
existing argument-based audits are unchanged. Owner-map routes are rescanned
after step 0 adds accesses.

### Step 0 — characterization of the original

Commit grace, startup candidate arm/commit/fail, manual begin/commit/fail
and restore, gate UI (status/indicator views), recovery "fetch more" handoff,
exhaustion through `finish()` characterized **separately for ordinary VOD
and Stremio TV**: the progress reporter suppresses exhausted playback only in
Stremio TV mode, so ordinary VOD can still report from the `finish` override
after the gate clears its cursor — both current behaviours (reporting,
checkpoint, handoff, one-shot finish flag, `sendFinished` payload) are pinned
as-is, no suppression added,
watchdog caps and timings, the 30 s recovery fallback and `missing-source`
post (cancelled only by the full `progressHandler` clear — pinned as-is),
`onDestroy` ordering of the 15 statements. Mutation proofs on the original;
Claude's independent sample; 0b.

### Gate, review, device checks

As rule 6 plus phases 3–8 additions. Device checklist (end of series):
Stremio movie/series startup with dead first sources (automatic failover,
commit after first frame), manual source pick before and after first frame
(incl. a failing pick and restore), exhaustion of all sources (activity
finishes and reports), Stremio TV channel startup.

## Phase 10 — status pill, PikPak cold-storage retry, source fetch (fetch-more + episode fetch)

Branch `refactor/tvplayer-p10` off the phase-9 merge `8a4d40d1c` (activity 13,320 lines). Evidence under
`refactor-evidence/tvplayer/p10/`. Inventory: "Phase 10 inventory" in the deps
report (measured at `c4906cd2f` with phase 9 taken from its committed
manifest; re-measure on the phase-9 merge). All collaborator rules from
phases 3–9 apply.

**Selected (≈ 640 lines, three sibling controllers):**
- `TvStatusPillController` (≈ 75 lines) at the `statusPill` slot; keeps
  borrowing `externalSubtitleHandler` (never clears it).
- `TvPikPakRetryController` (≈ 240) at the `isPikPakRetrying` slot; owns its
  retry `Handler` and `pikPakRetryId` (read live everywhere, incl. the gate's
  fire-time reads through its Host); 4 PikPak companion constants move with it.
- `TvSourceFetchController` (≈ 425) at the `episodeFetchInFlight` slot,
  holding fetch-more and episode fetch together (fetch-more owns no field of
  its own; merging keeps both `adoptSourceList` calls internal).
  `stremioResolutionToken` stays activity-owned; episode fetch bumps it via a
  Host `var` (`++host.stremioResolutionToken`).

27 activity patches in 13 declarations (incl. one-token in-place lifecycle
patches in `onPause` and `onDestroy` ×2); 17 Host forwarder re-points (20
token edits) as `patched` activity-property rows in the subtitle Host (3),
switcher Host (9) and phase-9 gate Host (5); 4 inert initializer proofs (pill
`Runnable`, PikPak `0`s and `Handler`); 2 new activity-owned readiness getters
(`startupGateStatusReady`, `pikPakReactivationIndicatorReady`); ≈ 176
substitutions (incl. 18 `host.startupGateController.`, 4
`host.sourceSwitchController.`, one already-braced template). Status-pill
direct callers left in the activity afterwards: 2 (`playbackListener`,
`playShowShuffle`). `playPikPakVideoWithRetry` stays (media start → playback
start phase).

**Hazards.** 4 `Runnable` self-references in `waitForPikPakMetadata`,
`TextView(this)` constructor, `findViewById`, 2 Toasts, 18 `runOnUiThread`,
named argument `allowResolverFallback`, the Host `var` increment. Follow-up
pinned as-is: the PikPak metadata `checkHandler` is never cleared; the PikPak
exhaustion branch checks `isFinishing` but not `isDestroyed`.

**Retargets.** Reflection: 28 direct sites on main + those added by phase 9 —
7 new owner-map entries, one more `when` branch in the watchdog `call` helper,
a one-line `ShufflePlaybackFlowTest` field-helper change; `waitForPikPakMetadata`,
`cancelPikPakRetry`, `showStatusPill` become public members. Dart: the
`map["recoveryCandidateCount"]` check reads the new `TvSourceFetchController.kt`
(literal unchanged).

### Step T

Phase-10 extraction fixture + negatives (three sibling controllers at their
slots, readiness getters, Host `var` increment, missed
`host.startupGateController.` qualification, snapshotting `pikPakRetryId`);
per-phase dispatcher keeping all historical suites; compiled audit (incl.
`TextView(this)` constructor and inherited `findViewById`); earlier
destinations frozen at the phase-9 merge. **Auditor extension:** the PSI
collector also records the 18 `runOnUiThread` calls and the 10
`isFinishing`/`isDestroyed` property reads (mapped to their JVM getters);
all 32 inventoried inherited-receiver sites carry before/after
owner–descriptor–opcode pins, with omission and wrong-dispatch negatives;
historical suites retained.

### Step 0 — characterization of the original

Heavy (episode fetch and fetch-more have no characterization today):
episode fetch (request, adjacent fetch, token supersession, in-flight guard,
pill messages, payload merge) and fetch-more with **paired inline and queued
reply cases** (the phase-8 bounded `workerReply` seam): token, continuation or
payload are changed before the main queue drains, pinning deferred lock
clearing, stale rejection inside the UI block, the live payload/index reads of
the adjacent fallback, the unguarded `notImplemented`, and fetch-more's
deferred finishing guard — with assertion-failing timing mutations; fetch-more (request, result adoption, empty /
error / notImplemented, recovery handoff to the gate, candidate counts),
PikPak retry under a **virtual clock**: `waitForPikPakMetadata` uses
`System.currentTimeMillis()`, which PAUSED looper mode does not redirect, so
the clock instrumentation covers both the original activity and the future
controller (incl. its nested `Runnable`); pinned boundaries: cumulative
monitoring timeouts at 10/22/36/54/80/108 s and auto-advance at 109.5 s
(backoff schedule, metadata wait polling, exhaustion routing,
`onPause` cancel, retry id supersession, reactivation indicator), status
pill (lazy creation, show/transient/hide timing on the borrowed handler).
Mutation proofs on the original; Claude's independent sample; 0b.

### Gate, review, device checks

As rule 6 plus phases 3–9 additions. Device checklist (end of series):
PikPak cold-storage source (retry backoff, reactivation indicator,
exhaustion), "fetch more sources" after all initial sources fail, next/previous
episode fetch from the player, status pill messages.

## Phase 11 — IPTV core (guide + browse + zap paging + channel switch + VOD navigation)

Branch `refactor/tvplayer-p11` off the phase-10 merge `00c60870e` (activity 12,717 lines). Evidence under
`refactor-evidence/tvplayer/p11/`. Inventory: "Phase 11 inventory" in the
deps report (measured at `8a4d40d1c`; field slots 838–1067 stay, functions
after ≈ 6449 shift — re-measure on the phase-10 merge). All collaborator rules
from phases 3–10 apply. **Highest-risk phase**: the async token protocol, and
browse/zap/switch have no characterization today.

**IPTV split (unchanged rule):** the six shared token/context fields
(`iptvUiContextToken`, `iptvBrowseToken`, `iptvZapRequestToken`,
`iptvZapOwnsUiContext`, `iptvZapRequestInFlight`, `iptvZapPendingInputs`)
are written by guide and zap code, so ownership is not split: one owner holds
every core field.

**Selected (≈ 1,250 lines):**
- `TvIptvGuideController` (≈ 430 lines) owns **all 48 core fields** (incl. the
  six shared fields) plus 14 guide/browse/search functions; activity property
  at the `iptvSeriesAudioKey` slot; one 23-member Host.
- It eagerly constructs two **fieldless** collaborators that reach shared
  state only through the owner: `TvIptvZapPager` (13 members, ≈ 525) and
  `TvIptvChannelNavigator` (zap keys, adjacent category, channel switch, VOD
  navigation; 17 members, ≈ 420). Every cross-file qualification (≈ 228) is
  compile-checked (a miss does not compile).
- 47 inert initializer proofs; the classifier gains two narrow forms: string
  literals and `java.util.ArrayDeque<Int>()` (typed, no arguments).
- 134 activity patches in 24 declarations, of which 67 (12 declarations) are
  temporary prefixes inside overlay/picker/EPG code that phase 12 moves; 5
  in-place `onDestroy` patches; Host re-points: Start Over controller (7
  forwarders, 8 token edits) and zap-banner controller (4).
- `initIptvMode` **stays** in the activity as patched bootstrap code (moving
  it needs 7 lifecycle-setup forwarders and writes across four owners); its
  116 lines join the documented end-state exception.
- Timers: only the borrowed `iptvBrowseHandler` (guide-hide trim post, 60 s
  EPG archive retry); no `progressHandler`; teardown order unchanged.

**Hazards.** Shadowed locals (`window`, `currentIndex`, `title`), `this.index`
×2 (receiver lambdas, not substituted), the activity `this` passed to
`EditText(this)` (substituted, constructor-audited), the
`requestIptvBrowse` default argument reading state (call-time evaluation),
labels `return@requestIptvZapPage` ×7, 6 inherited-receiver audit sites.

**Retargets.** 31 reflective sites via 7 owner-map entries;
`installIptvZapWindow` becomes a public member. No Dart anchors.

**Phase 12 (next):** `TvIptvGuideChromeController` (EPG pane + now/next
header, 21 fields) with fieldless overlay-builder and picker collaborators,
≈ 1,154 lines, medium risk (53 inherited-receiver sites, 2 `Glide.with`).

### Step T

Classifier extension (string literal, typed empty `ArrayDeque`) with
negatives (non-literal string, non-empty constructor); phase-11 extraction
fixture (owner + two fieldless collaborators, owner-only shared state,
cross-qualification) + negatives (a collaborator field, a collaborator
reading Host directly for shared state, missed qualification, label
rewrite); **receiver-lambda exclusions:** the PSI collector exhaustively
inventories reviewed `this` expressions that bind to a receiver lambda
(exactly the two entry-owned `this.index` sites; the `this` in
`EditText(this)` is the **activity** passed to the constructor outside the
lambda — it is substituted to `activity` and covered by the compiled
constructor-overload audit), pins each
with its source context, and rejects an omitted or misclassified exclusion or
any substitution of those expressions; the 7 Toast and 6 inherited-call audit
sites are retained; per-phase dispatcher keeping all historical suites; compiled audit;
earlier destinations frozen at the phase-10 merge.

### Step 0 — characterization of the original

From zero, **through the real IPTV bootstrap and its installed callbacks**
(not only reflection), so the phase-11 re-points inside retained
`setupIptvOverlay` are verified: series/episode/live row selection,
scroll-prefetch guards, submit-only search, numeric-dialog submission. Guide
open/close, browse requests and token supersession (UI context token, browse
token), search, zap paging (window install/merge, paging totals, pending
inputs, in-flight guard, page requests) with the **asymmetric stale-reply
contract** for all three reply kinds (success/error/notImplemented), each
varied independently by request token, UI token and ownership: an old
request preserves a newer in-flight flag; a matching request with stale
context or lost ownership **clears** the in-flight flag first and then
suppresses callbacks, queue clearing and Toasts; channel-jump replies check
only the request token (pinned separately); inline and queued main-looper
replies; assertion-failing mutations of cleanup ordering and each guard.
Channel switch (startup-channel memory interplay via the phase-5 controller,
Start Over interplay), adjacent category, the real key matrix (CHANNEL_UP/
CHANNEL_DOWN and DPAD left/right zap; UP short press opens the guide, long
press the jump dialog; repeat/action handling; controls-visible/focus and
live/VOD gates), number entry, VOD/episode navigation, borrowed `iptvBrowseHandler` posts
(trim, 60 s archive retry), `onDestroy` statements. Fake Flutter channel with
paired inline/queued replies. Mutation proofs on the original; Claude's
independent sample; 0b.

### Gate, review, device checks

As rule 6 plus phases 3–10 additions. Device checklist (end of series): IPTV
guide (open/close, browse categories, search), zapping up/down and by number
across category pages, channel switch while the guide is open/closed, VOD
episode next/previous, startup channel restore, Start Over after a switch.

## Phase 12 — IPTV guide chrome (EPG pane + now/next header, overlay builder, pickers)

Branch `refactor/tvplayer-p12` off the phase-11 merge `b870a16b1` (activity 11,458 lines). Evidence under
`refactor-evidence/tvplayer/p12/`. Inventory: section 3 of the "Phase 11
inventory" in the deps report (measured at `8a4d40d1c`; re-measure on the
phase-11 merge). All collaborator rules from phases 3–11 apply, and the
phase-11 lesson: a first independent mutation sample below ~75 % kills
triggers a systematic statement-level sweep and a second sample before moves.

**Selected (≈ 1,154 lines, 39 members):**
- `TvIptvGuideChromeController.kt` (owner, ≈ 400 lines): 21 fields (6
  now/next header views; EPG pane views, adapter, programmes, day offset,
  `iptvEpgToken`, visibility, entry) + 10 functions (`ensureIptvChannelEpg`,
  `updateIptvGuideEpgHeader`, `focusedIptvGuideEntry`, `formatEpgTime`,
  `showIptvSchedulePane`, `paintIptvEpgLogo`, `selectIptvEpgDay`,
  `hideIptvEpgPane`, `isFocusInIptvEpgPanel`, `updateIptvGuideCurrentName`);
  activity property at the `iptvGuideCurrentName` slot; one 13-member Host
  (incl. a `host.iptvGuideController` cross-feature getter).
- It eagerly constructs fieldless `TvIptvGuideOverlayBuilder.kt` (≈ 475:
  `setupIptvOverlay`, `applyGuideStyle`, `showIptvSourcePicker`,
  `showIptvChannelJumpDialog`) and fieldless `TvIptvGuidePickers.kt` (≈ 415:
  category/list pickers, `removeIptvGuideRow`, `toggleIptvFavorite`).
  Cross-file references: overlay → owner as `chrome.x` (14 refs incl. one
  **write** of `iptvEpgAdapter`), overlay → pickers as `chrome.pickers.x`.
- 26 activity patches in 4 declarations (`setupControls`, `dispatchKeyEvent`,
  `initIptvMode` view binds + `setupIptvOverlay` call, in-place `onDestroy`
  `iptvEpgToken++`); 5 Host re-points (Start Over `iptvEpgToken`; zap banner
  `ensureIptvChannelEpg`/`formatEpgTime`; the phase-11 `iptvGuideController`
  property's added Host span → a phase-12 `patched` row, phase-11 files stay
  byte-identical); the 67 temporary `iptvGuideController.` prefixes from
  phase 11 become `host.iptvGuideController.` substitutions.
- 20 inert initializer proofs (supported forms). ≈ 330 substitutions.

**Audit.** 24 `this` → `activity` sites (incl. **2 `Glide.with(this)`** that
must keep the `FragmentActivity` overload, `AlertDialog.Builder(ctx, theme)`,
`EditText`/`TextView`/`LinearLayout`/`RecyclerView` constructors,
`LinearLayoutManager`, Toasts, `ContextCompat.getColorStateList`,
`DateFormat.getTimeFormat`); 53 implicit inherited sites (`findViewById` ×46,
`resources` ×2, `isFinishing`/`isDestroyed` ×2 each, `currentFocus`); one
**excluded receiver**: `TextViewCompat.setCompoundDrawableTintList(this, …)`
inside `EditText(this).apply {}` — that `this` is the EditText; shadowed
`title` (lambda parameter, local).

**Timers/teardown.** 60 s archive retry on the borrowed `iptvBrowseHandler`
(cleared wholesale in `onDestroy`), `iptvEpgToken` guard bumped in place in
`onDestroy`, uncancelled view posts pinned as-is, `requestIptvEpg` 45 s
watchdog unchanged (follow-up).

**Retargets.** 20 reflective accesses across 5 names (`iptvEpgToken` ×4,
`iptvGuideCurrentName` ×7, `iptvEpgPanel` ×4, `iptvEpgVisible` ×4,
`showIptvChannelJumpDialog` ×1, incl. phase-11 sweep tests): four field
routes to the chrome owner and the dialog route to `.overlay` (dialog method
public in the internal class, unmangled); assertions preserved; rescanned
after step 0. No Dart anchors.

### Step T

Phase-12 extraction fixture (owner + two fieldless collaborators, the
`iptvEpgAdapter` cross-file write) + negatives; receiver handling for
`EditText(this).apply { … this … }`: the checker permits exactly the reviewed
constructor-receiver transformation (`EditText(this)` → `EditText(activity)`)
while preserving the inner `this` binding (positive fixture with both
expressions; negatives for rewriting the inner `this`, changing its receiver,
or omitting the constructor audit); the PSI collector also records
`resources` and `currentFocus` property reads, resolved to `getResources()` /
`getCurrentFocus()` with before/after owner–descriptor–opcode pins and
omission/wrong-receiver negatives; compiled audit of 24 + 53 sites; per-phase dispatcher
keeping all historical suites; earlier destinations frozen at the phase-11
merge.

### Step 0 — characterization of the original

Through the real IPTV bootstrap: overlay construction for each of the 4 guide
styles (separate activity instances — the style is cached per session);
adapter callbacks (select, long-press series sentinel, favourite, list,
replay, record); search field focus/IME/Back; source/category/list pickers
incl. membership load-before-toggle and favourites; channel-jump dialog
gating (favourites/list source toast); EPG pane show/hide, day buttons, stale
token, null reply, destroy; now/next header (Glide lifecycle owner, letter
fallback); the 60 s archive retry; **now/next fetching and enrichment**:
the captured `requestedCatchupMetadata` vs live `entry.isCurrent`
distinction (paired main-looper replies where current-channel identity
changes during a cheap request), silent-request/watchdog delivery after
destruction (enrichment replies are unguarded after destroy and can post
another borrowed-handler retry — pinned as-is), enrichment bookkeeping,
follow-up request arguments, metadata clearing before the retry's lifecycle
guard, and freshness boundaries under clock instrumentation covering both the
original activity and the future chrome owner — mutation-proved. Mutation proofs on the original; Claude's
independent sample (≥ 75 % kill rate required, else sweep + second sample);
0b.

### Gate, review, device checks

As rule 6 plus phases 3–11 additions. Device checklist (end of series): IPTV
guide in each guide style (overlay layout, fonts, tokens), category/list
pickers, favourites toggle, row removal from a custom list, channel-number
jump dialog, EPG schedule pane (day navigation, replay/record actions),
now/next header with logo and letter fallback.

## Phase 13 — playlist overlay, focus navigation and guide skin

Branch `refactor/tvplayer-p13` off the phase-12 merge `315448a3c` (activity 10,297 lines). **First item of step T:** split the 813-line `TvPlayerOriginalAccess.kt` test helper (exit milestone from phase 12) into cohesive helpers (e.g. owner-route map vs reflection primitives), each ≤ 800 lines, assertions untouched, and drop its size-baseline exception before any new route is added. Evidence under
`refactor-evidence/tvplayer/p13/`. Inventory: "Phase 13 inventory" in the deps
report (measured at `b870a16b1`; phase 12 has no references either way —
re-measure on the phase-12 merge). All collaborator rules from phases 3–12
apply, incl. the phase-11 sampling lesson; the systematic statement-level
coverage sweep is part of step 0 from the start (101 `if`, 16 `when`, 70
`return` sites).

**Remaining plan (re-measured):** 13 playlist overlay + guide skin (1,199);
14 subtitle fetch + subtitle menu rows (1,113; 45 reflective sites); 15
controls I + display/speed/night mode (≈ 1,075); 16 controls II + title
identity + Next overlay (1,116); 17 IPTV tune pipeline + twin trial + live
recovery (732; no existing tests); 18 playback start + shuffle (912); 19
media pipeline + metadata receiver (697); 20 the routers decision
(`playbackListener` ≈ 71 and `dispatchKeyEvent` ≈ 47 activity-member
dependencies at `b870a16b1`, ≈ 110 combined; later extractions shrink both —
the phase-20 exception decision is based on the interfaces remaining after
phase 19). **Revised end state:** ≈ 3,450–3,750 lines
if the routers stay (≈ 2,850–3,150 if they move): lifecycle, ≈ 26 controller
Hosts (~30 lines each), `bindViews`, `parsePayload`, `initIptvMode`, menu
composition and shared single-owner state — recorded as the documented
end-state exception when the series completes.

**Selected (≈ 1,199 lines, 60 members):** `TvPlaylistOverlayController`
(≈ 580) eagerly constructs `TvPlaylistFocusNavigator` (≈ 325; owns the 4
focus fields, avoiding template-bracing edits) and `TvPlaylistGuideSkin`
(≈ 395); 49 compile-checked cross-references; the three playlist views stay
in the activity behind computed Host getters; one 11-member Host. 31 activity
patches in 15 declarations; 7 forwarder re-points in 6 controller Hosts
(`patched` activity-property rows); the 7 `onDestroy` statements patched in
place, in order. 28 initializer proofs; the classifier gains three narrow
forms: the negative literal `-1`, an enum entry (`PlaylistMode.NONE`), and
getter-only properties (no backing initializer). ≈ 220 substitutions.

**Audit.** 8 `this` → `activity` sites (2 `Glide.with` must keep the
`FragmentActivity` overload), 15 implicit inherited calls, 1 excluded
listener `this`, 2 `::guideSkinBind` function references (resolve to the same
member after the move).

**Retargets.** 10 reflective sites via 4 owner-map routes; no Dart anchors.

### Step T

Phase-13 extraction fixture (owner + navigator with fields + skin; computed
view getters) + negatives; auditor extensions: PSI getter collection for
`layoutInflater` → `getLayoutInflater()` and a narrowly typed
`ViewTreeObserver.OnGlobalLayoutListener` `this` exclusion pinned to
declaration/context/binding (omission, wrong-dispatch and
listener-substitution negatives; other unreviewed object receivers still
rejected); classifier forms + negatives (non-literal negative
expression, enum entry with arguments, getter with side effects); compiled
audit (8 + 15 sites, listener exclusion, function references); per-phase
dispatcher keeping all historical suites; earlier destinations frozen at the
phase-12 merge.

### Step 0 — characterization of the original

From zero: 7 separate activity instances (one per controls skin); playlist
show/hide (animation, focus restore), season tabs and group filtering,
movie-collection tabs, focus engine (DPAD up/down/left/right across tabs and
rows, edge behaviour, recovery posts and their cancellation) incl. explicit
paused-looper cases for recovery replacement/cancellation, an older reset
callback overlapping newer navigation (it clears the current navigation state
unconditionally — pinned as-is), pending View work across hide/rebuild/
destroy, and global focus-listener accumulation across rebuilds (pinned
as-is), guide skin
binding per skin (`::guideSkinBind`), current-item highlight and scroll,
adapter rebuild paths, `onDestroy` statements; plus the systematic
statement-level coverage sweep with a coverage matrix. Mutation proofs on the
original; Claude's independent sample (≥ 75 % kills, else sweep + second
sample); 0b.

### Gate, review, device checks

As rule 6 plus phases 3–12 additions. Device checklist (end of series):
playlist overlay for a series (season tabs, episode rows, current episode
highlighted) and a movie collection, DPAD navigation incl. edges and long
lists, the playlist in each controls skin, opening/closing during playback.

## Phase 14 — subtitle sources (addon fetch, auto-select, manual identity, search dialogs, subtitle menu rows)

Branch `refactor/tvplayer-p14` off the phase-13 merge `82b16832c` (activity 9,079 lines). Evidence under
`refactor-evidence/tvplayer/p14/`. Inventory: "Phase 14 inventory" in the deps
report (measured at `315448a3c`; phases 13 and 14 patch the same five
declarations at different statements — re-measure on the phase-13 merge).
All collaborator rules from phases 3–13 apply; the statement-level coverage
sweep runs from the start (67 `if`, 48 `return` sites).

**Not merged into `TvSubtitleController`:** it is already 776 lines (merging
would give ≈ 1,870), it is a frozen earlier destination, and its 9 Host
forwarders into this unit would become self-references.

**Selected (≈ 1,094 lines, 43 members):** `TvSubtitleSourcesController`
(≈ 712: all 21 fields + addon fetch, auto-select, manual identity, identity
label, the 4 subtitle menu rows) eagerly constructs fieldless
`TvSubtitleSearchDialogs` (≈ 487: both dialogs, catalog search, result
adapter, current-search-item lookup); one shared 15-member Host; property at
the `stremioSubtitles` slot. `subtitleScope`, `stremioSubtitleService` and
`subtitleTrackReadiness` stay activity-owned and are borrowed through the
Host. 24 activity patches in 9 declarations (2 braced templates; 1 in-place
`onDestroy` statement between `subtitleScope.cancel()` and
`stremioSubtitleService = null`); 12 Host re-points (14 token edits) in 4
properties (`subtitleController` ×9, `iptvStartOverController`,
`iptvGuideController`, `pikPakRetryController`); 20 inert initializer proofs
(new narrow form: `emptyList()`; reuses phase 13's `-1`); ≈ 134 substitutions
(77 host, 10 cross-file reads, 22 `this` → `activity` incl. an `ArrayAdapter`
super-constructor argument, 3 `runOnUiThread`, 22 visibility). Not
substituted: the receiver `this.adapter`, `context` ×4, `getItem`, and the
named argument `resources =`.

**Retargets.** 34 reflective sites over 7 field names in 5 files via 7
owner-map routes (`subtitleScope` sites stay; the 2 `resetSubtitleState`
sites target `TorboxTvPlayerActivity` and are unaffected). No Dart retargets
(one patch inside the `handleMetadataUpdate` anchored range; asserted text
unchanged).

**Pinned as-is (follow-ups, not fixed):** a late metadata reply after destroy
still runs the fetch path (content token never bumped in `onDestroy`) — but
because destruction already nulled `stremioSubtitleService`, it obtains zero
addons, clears slots, sets discovery ready and loading **false**, launches
nothing, while the captured metadata cache still receives the reply (pinned
exactly; separate from the already-running-fetch cancellation case); a
fetch cancelled by the activity's `subtitleScope.cancel()` is caught by
`catch (e: Exception)`, marks the addon FAILED, retries auto-select and can
toast after destroy; catalog search has no request counter, so an older
reply can overwrite newer results.

### Step T

`emptyList()` is already accepted (phase-4 proofs); step T only tightens its
validation (declared type / stdlib binding checks, historical proofs stay
compatible); `ListView(this)` constructor-receiver transformation (Context
constructor pinned, inner `this.adapter` receiver preserved, omission and
substitution negatives), mirroring the phase-12 `EditText` mechanism; the
PSI collector also records `KtSuperTypeCallEntry` call metadata so the
`ArrayAdapter` super-constructor argument is audited; phase-14 extraction fixture (owner
+ fieldless dialogs, borrowed scope/service/readiness) + negatives (receiver
exclusions above, the named `resources =` argument, the `ArrayAdapter`
super-constructor site); compiled audit; per-phase dispatcher keeping all
historical suites; earlier destinations frozen at the phase-13 merge.

### Step 0 — characterization of the original

Three harnesses first, demonstrated on the original: a latch on
`StremioSubtitleService.attemptFetch`, a fake Flutter channel with
**endpoint-specific contracts** — `searchSubtitleCatalogs` (success/error;
`runOnUiThread` runs inline on the activity thread; inline, queued-main and a
worker-thread reply proving main-thread dispatch) and `requestMovieMetadata`
(no `onError`: a null channel produces no callback, a send failure invokes
`callback(null)` synchronously), each asserting the resulting controller
loading state — and a dialog harness. Then: addon slot fetch/retry/failure, flat
list rebuild, auto-select rules and `failedSubtitleUrls`, injected subtitle
seeding, IMDb lookup path, manual identity apply, identity label, search
dialogs (query, results, season/episode prompt), the 4 menu rows, the
pinned-as-is quirks above, `onDestroy` order; systematic coverage sweep with
a coverage matrix. Mutation proofs on the original; Claude's independent
sample (≥ 75 % kills, else sweep + second sample); 0b.

### Gate, review, device checks

As rule 6 plus phases 3–13 additions. Device checklist (end of series):
addon subtitles for a movie and an episode (auto-select, retry of a failed
addon), subtitle search dialog with season/episode prompt, manual identity
correction, subtitle menu rows.

## Phase 15 — controls dock builder + live dock styler, playback display/audio settings

Branch `refactor/tvplayer-p15` off the phase-14 merge `ce3ddfb06` (activity 7,982 lines). Evidence under
`refactor-evidence/tvplayer/p15/`. Inventory: "Phase 15 inventory" in the deps
report (measured at `82b16832c`; phases 14 and 15 patch five of the same
declarations incl. `unifiedMenuCallbacks` and two of the same Host properties
— re-measure on the phase-14 merge). All collaborator rules from phases 3–14
apply; statement-level coverage sweep from the start.

**Split with phase 16.** Phase 15 = dock *builder* side + display/audio (66
members, ≈ 1,071 lines); phase 16 = dock *runtime* (show/hide/auto-hide
timers, play/pause, seekbar and cinema scrub, title/OTT identity, Next overlay,
clean-state; ≈ 1,110). This direction leaves 3 temporary patches (the reverse
would need ≈ 44).

**Selected:**
- `TvControlsDockController` (≈ 560): OTT skin install, caption,
  `setupControls`, the 17 dock-only views; eagerly constructs
  `TvLiveDockStyler` (≈ 290, IPTV live dock styling; 48 compile-checked
  styler→dock qualifications through an injected reference named
  **`controlsDock`** — not `dock`, which would collide with the existing
  `dock` locals/parameter in `arrangeLiveIptvControlDock`,
  `restoreOriginalControlDockOrder` and `replaceControlDockOrder` (14 of the
  48 sites); the original locals are preserved). 24 shared views stay in the activity behind
  Host `var`s (ownership decided in phase 16); `controlsSkin`, `dockSkinSpec`,
  `nativeAudioRouting`, `trackSelector` and `player` stay; only the
  `DockSkinSpec` type moves (top-level `internal`).
- `TvPlaybackDisplayController` (≈ 420, sibling): aspect, speed, night mode,
  audio effects, display-match, `loadPlayerDefaults`, the decoder analytics
  listener, the unified-menu display/audio rows.
- Hosts: dock/styler 58 members (24 view/state forwarders), display 11;
  ≈ 338 substitutions. 41 activity patches in 13 declarations (12 in
  `playbackListener`, 9 in `setupPlayer`); 12 Host re-points in 5 properties
  (Start Over, guide, progress reporter, recording, source switch); 3
  in-place `onDestroy` statements (display-mode clear/null,
  `releaseLoudnessEnhancer`); nothing in `onStop`/`onPause`/`finish`. No
  owned Handler/token/coroutine.
- 31 initializer proofs from two slots; three new narrow classifier forms: an
  empty typed `HashMap<…>()`, `arrayOf` with literal elements (incl.
  `AspectRatioFrameLayout.RESIZE_MODE_*` constants, with bytecode proof they
  are inlined), and the reviewed anonymous `object : AnalyticsListener`.
- Audit: 14 receiver/constructor sites, 3 inherited getters, and all 23
  `findViewById` assignment sites inventoried with **cast presence/absence
  and target type pinned** (re-measured bytecode: 12 sites cast; 8 `View`
  targets and 3 typed-array stores have no cast), comparing the original field descriptors against the new
  Host setter or array-getter descriptors; exact source types and
  nullability preserved; widening and omitted-site negatives.
- Reflection: 41 sites across 10 names via 9 owner-map routes plus the
  `NativePlayerSettingsConsumptionTest` `nightModeIndex` helper change
  (assertions unchanged); `getControlsSkin`/`trackSelector` stay. No Dart
  anchors.
- `LoudnessEnhancer` lifetime unchanged (created at READY, on session change,
  track init, night-mode change; released on transitions, route changes and
  `onDestroy`, **not** in `onStop` — recorded follow-up, not fixed).

### Step T

Classifier forms + negatives; extraction fixture (two sibling owners, nested
styler via `controlsDock`, Host-typed `findViewById`) + negatives (incl. a
shadowing negative where a `dock`-named reference would be captured by a
local); compiled audit incl. the
`findViewById` compiled-type check; per-phase dispatcher keeping all
historical suites; earlier destinations frozen at the phase-14 merge.

### Step 0 — characterization of the original

Prerequisite: a deterministic way to observe `LoudnessEnhancer` creation,
gain and release (shadow or seam) **and to inject failures** (constructor,
enable/gain incl. failure on the second gain call, release), demonstrated on
the original, pinning as-is: an enable/gain failure during initialization
clears the reference without releasing the newly allocated effect; a release
failure still clears it; enable/gain calls in `applyNightMode` sit outside
that catch and propagate — if it
cannot be made reliable, night mode + the effect session leave phase 15 and
the design is re-reviewed. Then from zero: 7 controls skins × 4 guide styles
(separate activity instances) for dock construction and OTT install; focus
and click routing installed by `setupControls`; live dock styling; aspect
(incl. 4:3 scale), speed (NativeAudioRouting interplay), night mode, audio
effects, display-match, `loadPlayerDefaults`, decoder analytics listener
callbacks, unified-menu display/audio rows, `onDestroy` statements; coverage
sweep + matrix. Mutation proofs on the original; Claude's independent sample
(≥ 75 %, else sweep + second sample); 0b.

### Gate, review, device checks

As rule 6 plus phases 3–14 additions. Device checklist (end of series):
controls dock in each of the 7 skins (buttons, captions, focus order), IPTV
live dock styling, aspect cycling incl. 4:3, playback speed with audio
pitch, night mode (loudness) on/off and across track/route changes, system
audio effects toggle, display-mode matching (refresh rate) on a supported TV.

## Phase 16 — controls dock runtime (overlay show/hide, dock identity, seekbar + cinema scrub)

Branch `refactor/tvplayer-p16` off the phase-15 merge `df439aed1` (activity 6,986 lines). Evidence under
`refactor-evidence/tvplayer/p16/`. Inventory: "Phase 16 inventory" in the deps
report (measured at `ce3ddfb06` with phase 15 read from its branch;
re-measure on the phase-15 merge). All collaborator rules from phases 3–15
apply; statement-level coverage sweep from the start (104 `if`, 47 `return`).

**Selected (80 members, ≈ 1,161 lines, one activity property
`controlsOverlayController` at the phase's first owned slot, one shared
Host):**
- `TvControlsOverlayController` (owner, ≈ 430): show/hide/auto-hide (owns
  `controlsHandler`, 4 s auto-hide only while playing), play/pause, Next
  overlay, clean-state.
- eagerly constructs `TvDockIdentityPresenter` (≈ 330: title/OTT identity
  incl. `@Volatile ottShowName`, annotation kept) and `TvSeekScrubController`
  (≈ 540: legacy seekbar + cinema scrub; owns `seekbarHandler` 100 ms ticker,
  never stopped, and the 80 ms scrub animator).
- The owner is referenced as **`controls`** (not `overlay` — three owner
  functions have `val overlay` locals); `seek`/`identity` verified
  collision-free; 10 compile-checked cross-references.
- **View ownership decision:** 23 of the 24 shared views from phase 15 move
  (owner 2, identity 8, seek 13); `ottSkinInstalled` stays (readers span
  several owners); the 18 lateinit title/Next-overlay/seekbar views stay in
  the activity (avoids 18 `bindViews` patches, 39 reflective retargets and an
  un-checkable `::seekbarOverlay.isInitialized` in `onDestroy`).
- 48 activity patches in 11 declarations (27 in `dispatchKeyEvent`; 10 later
  consumed by phases 18–19); 46 Host re-points (68 token edits) in 10
  properties (31 in phase 15's `controlsDockController` Host incl. 22 get/set
  pairs); 2 in-place `onDestroy` patches; 2 activity-owned readiness getters
  (`startupGateViewReady`, `nextBackdropReady`).
- 38 initializer proofs; new narrow classifier forms: scalar float literals,
  `arrayOfNulls<TextView>(3)`, a reviewed `object : Runnable`.
- ≈ 228 substitutions (155 host, 3 `this` → `activity` incl. 2 `Glide.with`
  and a Toast, 1 excluded Runnable `this`, 4 inherited calls, 53
  visibility). `updateSeekbarProgress` shadows `player` with a local (not
  substituted). `progressHandler` and the zap-banner tokens are untouched.
- Retargets: all **34 moved names** accessed reflectively by existing tests
  (151 quoted accesses incl. phase-15 suites, e.g. `hideControlsRunnable`,
  `pauseButton`, `seekbarProgressRunnable`) are routed to their new owners
  before step T, then extended for step-0 additions; assertions preserved;
  no Dart retargets (two anchored ranges get patches; asserted text
  unchanged).

**Pinned as-is:** `showSeekbar` has no caller (the legacy seekbar path is
dead; step 0 reaches it by reflection); the seekbar ticker writes
progress-reporter guards every tick; the 100 ms ticker is never stopped.

### Step T

Classifier forms + negatives; extraction fixture (owner + two collaborators
via `controls`/`seek`/`identity`, `@Volatile` preserved) + negatives (a
`overlay`-named reference captured by a local, the shadowed `player` local);
compiled audit (incl. retaining all 23 phase-15 view-binding pins — 12
casts, 11 without, incl. three array stores — with their target
descriptors); per-phase dispatcher keeping all historical suites; earlier
destinations frozen at the phase-15 merge.

### Step 0 — characterization of the original

Prerequisite: deterministic animator stepping under the paused looper and a
recording player probe, demonstrated on the original. Then: 7 per-skin
activity instances; show/hide/auto-hide timing (playing vs paused), the full
key matrix that drives the dock, play/pause, Next overlay fade timings and
clean-state — **each of its twelve blockers independently** (that blocker set,
all others clear) plus the all-clear case, each mutation-proved, title/OTT identity per skin, cinema scrub (start, step, commit,
cancel, animator), the legacy seekbar path via reflection, ticker effects on
progress-reporter guards, `onDestroy` statements; coverage sweep + matrix.
Mutation proofs on the original; Claude's independent sample (≥ 75 %, else
sweep + second sample); 0b.

### Gate, review, device checks

As rule 6 plus phases 3–15 additions. Device checklist (end of series):
controls dock show/hide/auto-hide while playing and paused in each skin,
play/pause from the dock and remote, cinema scrub seeking (hold/release,
cancel), title/OTT identity text, the Next overlay during auto-advance.

## Phase 17 — IPTV tune pipeline, HLS→TS twin trial, strict-TS, live recovery wiring

Branch `refactor/tvplayer-p17` off the phase-16 merge. Evidence under
`refactor-evidence/tvplayer/p17/`. Inventory: "Phase 17 inventory" in the deps
report (measured at `ce3ddfb06`; re-measure on the phase-16 merge). All
collaborator rules from phases 3–16 apply; statement-level coverage sweep
from the start; the ≥ 75 % first-sample rule applies. **High risk:** the twin trial, recovery wiring
and strict-TS have no tests yet; phase-16 tests already cover parked
restoration and lazy recovery timing and are reused in step 0.

**Selected (whole unit; splitting would cost ≈ 30 throwaway edits and a second
step 0 because owner and twin reference each other 28 times):**
`TvIptvTuneController` (≈ 400: tune pipeline `setIptvMediaItem`, strict-TS
sets, recovery wiring, reconnect pill) eagerly constructs field-bearing
`TvIptvTwinTrial` (≈ 285; owns `iptvTwinTrialHandler`); property
`iptvTuneController` at the unit's first owned slot; 41 members / ≈ 614 lines.
Qualifiers **`tune.`/`trial.`** (`twin` collides with 8 local bindings and 1 parameter binding — 25
code-token occurrences in moved code).

**Deliberately left in the activity:** the two `@Volatile` loader-thread fields
(`currentIptvHttpHeaders`, `iptvStrictTsActive`) — activity-owned with Host
setters, as `activeVodHeaders` in phase 8, so the loader-thread code in
`setupPlayer` is not edited at all (the decision moves to phase 19);
`iptvTuneDiagnostics`, the diagnostic analytics listener (mostly VOD
startup-gate commits), the codec selector and `iptvDecoderMode`,
`reportDecoderFailure`, the network callback and the rejoin bookkeeping.

- 28 activity patches in 6 declarations: `playbackListener` 14 (error-branch
  order pinned), `progressRunnable` 3, `setupPlayer` 3 (`setOffline` calls
  only), `onStart` 2, `onStop` 4, `onDestroy` 2 — all in place, order
  unchanged.
- 8 Host re-points (9 edits) in 4 properties: Start Over 1, channel start 3
  (incl. the `currentIptvStreamUrl` get/set), recording actions 2, phase-16
  controls overlay 2 (`iptvLiveRecovery`, `restoreParkedIptvTwinIfNeeded`).
- 20-member Host (computed, explicitly qualified); ten names deliberately
  not Host members so a missed `tune.`/`trial.` qualification fails to compile.
- 21 initializer proofs; new narrow classifier forms: typed no-argument
  `HashSet`/`HashMap`, and a `by lazy { … }` delegate (lazy first-access
  timing preserved, incl. the VOD case where `onStop`/`onDestroy` builds the
  recovery machine only to cancel it — pinned as-is).
- ≈ 120 substitutions, no templates needing braces. Audit: 2 receiver sites
  (`TextView(this)`, Toast) and 6 inherited pins incl. a **new kind**:
  `addContentView` called implicitly inside `TextView.apply` must keep
  dispatching to `AppCompatActivity`'s override while the inner `this` stays
  the TextView. The owner needs `@OptIn(UnstableApi::class)` (Media3 javap
  verified); the twin does not.
- Retargets: 31 reflective sites over 7 routing keys (`currentIptvStreamUrl`
  ×22, `iptvHlsForcedUrls` ×2, `iptvTwinPreferredUrls` ×1, both parked-restore
  fields ×2 each, `iptvLiveRecovery$delegate` ×1 and the generated getter
  `getIptvLiveRecovery` ×1 — `memberOwner` strips `$delegate` but does not
  normalize getter names, so the getter is routed explicitly); no Dart anchors.

### Step T

Classifier forms + negatives; extraction fixture (owner + field-bearing twin,
`tune.`/`trial.`) + negatives (missed qualification, snapshot of a volatile
field, eager evaluation of the lazy recovery machine); compiled audit incl.
the implicit `addContentView` inherited-dispatch pin; per-phase dispatcher
keeping all historical suites; earlier destinations frozen at the phase-16
merge.

### Step 0 — characterization of the original

Prerequisites demonstrated on the original (the phase stops if the
loader-thread fixture cannot be made reliable): a PAUSED-looper clock fixture
where `elapsedRealtime` advances with the looper; an extended player proxy
(decoder counters, `playerError`); a real-pipeline loader-thread fixture
reaching the Media3 1.8.0 factories by reflection with MockWebServer; a fake
`ConnectivityManager` callback; error-chain fixtures; device-quirk instances.
Then: tune pipeline (HLS/TS selection, headers, strict-TS), twin trial
(arm/timeout/park/restore), recovery ladder (retune/backoff, error
classification, reconnect pill), `onStart`/`onStop`/`onDestroy` parking and
cancellation order; coverage sweep + matrix. Mutation proofs on the
original; Claude's independent sample; 0b.

### Gate, review, device checks

As rule 6 plus phases 3–16 additions. Device checklist (end of series): IPTV
live channels on HLS and TS, an Xtream HLS channel that needs the `.ts`
twin, strict-TS providers, network drop and recovery (Wi-Fi off/on),
backgrounding (Home) and resuming live TV, a stalling channel's reconnect
pill.

## Phase 18 — playback start, resolve, Stremio TV media start, navigation and shuffle

Branch `refactor/tvplayer-p18` off the phase-17 merge. Evidence under
`refactor-evidence/tvplayer/p18/`. Inventory: "Phase 18 inventory" in the deps
report (measured at `df439aed1`, phase-16 design read from its branch;
re-measure on the phase-17 merge). All collaborator rules from phases 3–17
apply; statement-level coverage sweep from the start (84 `if`, 56 `return`).
**High risk:** the playback-start path and shuffle protocol.

**Selected (whole unit — splitting start and shuffle costs ≈ 23 temporary
edits because they reference each other 9 and 18 times):**
- `TvPlaybackStartController.kt` (≈ 650; reference name **`playbackStart`**):
  `playItem` → `resolveAndPlay` → `startPlayback` → `buildMergedSource`,
  `discoverProtectedMime`, `playPikPakVideoWithRetry`, the Stremio TV
  media-start trio; owns `mediaPreparationScope`, `mediaPreparationGeneration`,
  `pendingShufflePlayback`; class-level Media3 `@OptIn`.
- eagerly constructs `TvPlaybackNavigator.kt` (≈ 385; reference name
  **`navigator`** — `navigation`/`generation` collide with locals and
  `ShufflePlaybackAttempt` properties): `playNext`/`playPrevious`,
  `updateCatalogEpisodeControls`, random, the shuffle protocol and its 6
  shuffle-only fields (`showShuffleGeneration`, `queued*`,
  `shuffleWatchGeneration`).
- Activity property `playbackStartController` at the unit's first owned slot;
  one shared 43-member computed Host (12 var, 27 val, 4 fun); the
  `protectedStreamClient` getter keeps running on the IO thread exactly as
  the original field read did.
- **Stay in the activity:** `ShufflePlaybackAttempt` (nested; three frozen
  earlier files import `AndroidTvTorrentPlayerActivity.ShufflePlaybackAttempt`
  and four test sites look it up by binary name — no binary-name retargets),
  `stremioResolutionToken`, `sleepStopLatched`, `@Volatile activeVodHeaders`,
  `continuousShuffleEnabled`; startup/manual tokens stay with the gate
  controller, the PikPak retry id with the PikPak controller.
- 17 activity patches in 5 declarations (`playbackListener` 8, `onCreate` 2,
  `handleMetadataUpdate` 1 — consumed by phase 19, `umPlaybackModel` 4,
  in-place `onDestroy` 2: scope cancel then generation bump); 21 Host
  re-points (22 token edits) in 8 properties (Up Next, playlist, dock, gate,
  Stremio TV guide, PikPak, fetch, switcher), built on the phase-16 versions;
  phase 16's 6 patches inside this unit become
  `host.controlsOverlayController[.identity].…`.
- 8 inert initializer proofs (new narrow form: `ShowShuffle()`, or keep
  `showShuffle` in the activity); ≈ 265 substitutions; one braced template
  (`${host.stremioResolutionToken}`); the three `player?.apply {}` receiver
  blocks pinned; local functions inside `playShowShuffle` handled by the
  checker (step-T fixture).
- Audit: 11 receiver/constructor sites, 9 inherited sites; `finish()`
  compiled `invokevirtual`.
- Async: three shuffle posts on the borrowed `progressHandler` and the MIME
  coroutine; no owned Handler/`Runnable`/Glide/`findViewById`/`runOnUiThread`;
  teardown order unchanged.

**Retargets.** 61 reflective sites over 20 names in 13 files: 14 owner-map
routes plus one `when` branch in `ShufflePlaybackFlowTest`'s local `call`
helper; 9 functions become public members (split the owner-map file before
it passes 800 lines). Dart: `test/android_tv_auto_advance_resume_test.dart`
reads the new controller file and its start marker becomes `'fun playItem('`
(public for reflection) with an added uniqueness assertion;
`test/manual_source_validation_contract_test.dart` only changes the file
(both markers stay `private`); every asserted string and the `playItem` →
`resolveAndPlay` → `startPlayback` order are preserved.

### Step T

Classifier form + negatives; extraction fixture (owner + navigator via
`playbackStart`/`navigator`, local functions in `playShowShuffle`,
`player?.apply {}` receivers) + negatives; compiled audit incl.
`invokevirtual finish`; per-phase dispatcher keeping all historical suites;
owner-map file split if needed; earlier destinations frozen at the phase-17
merge.

### Step 0 — characterization of the original

The `playNext` ladder, `playPrevious`, the catalog-controls matrix, shuffle
bag and eligibility (assert bag invariants after seeding `shuffleBag` —
`Random.Default` is not seeded), every `playShowShuffle` branch, each resolve
and MIME guard and generation/token supersession, merged-source fallback,
PikPak start, the Stremio TV trio, `onDestroy` statements; coverage sweep +
matrix. Mutation proofs on the original; Claude's independent sample (≥ 75 %,
else sweep + second sample); 0b.

### Gate, review, device checks

As rule 6 plus phases 3–17 additions. Device checklist (end of series):
start a movie and a series episode from each source type (debrid, torrent,
direct, PikPak, protected stream needing MIME discovery), resume position,
next/previous episode, auto-advance at end, catalog episode controls, show
shuffle (start, continue, exhaustion), Stremio TV channel next item.

## Follow-ups (found while mapping; not fixed here)

- Phase 16 original runtime observations, preserved by Step 0: hidden dock
  scheduling leaves a pre-existing callback and deadline intact; queued focus
  offers survive hide and can re-arm auto-hide; the 100 ms seekbar ticker is
  retained through pause/stop and only removed by teardown; onDestroy does
  not cancel a running scrub animator. The reflection-only legacy seekbar
  hide resumes playback even when it was paused before entry. Any change to
  these timing/lifetime behaviors belongs to a separate behavior change.
  CLASSIC focus remaining on PlayerView is a Robolectric fixture observation,
  not a claimed device finding; device checks stay at the planned milestone.

- Phase 13 focus behavior, preserved by Step 0: older reset callbacks clear
  newer navigation state unconditionally; rebuilding accumulates global focus
  listeners; already queued View focus work survives hide/rebuild/destroy.
  Characterization and original mutation proofs pin these behaviors. Any
  cancellation or listener-lifetime correction belongs to a separate behavior
  change after this structural series.

- Phase 12 scoped test-helper size exception (**resolved in Phase 13 Step T**):
  `android/app/src/test/kotlin/com/debrify/app/tv/TvPlayerOriginalAccess.kt`
  grows 774 → 813 physical lines solely from the 39 required owner routes.
  Retain its existing reflection/adapter fixture behavior and byte-identical
  assertions in this move; the 813-line ratchet is explicit in the size baseline.
  Exit milestone: before the next phase adds any owner route, extract the
  immutable controller-owner lookup into a dedicated test fixture, preserving
  all names/values and keeping the access helper below 800. No production
  size exception or numeric-check exemption is added.


- Phase-9 full Robolectric suite exceeds the default 512 MiB test-worker heap.
  Three attempts were rejected; matched original/extracted 1024 MiB runs pass
  identity comparison via an evidence-only init script. A durable test-harness
  memory setting remains a separate infrastructure follow-up; repository build
  settings stay unchanged in this structural phase.

- Phase-5 original player-read failure occurs outside `deliverProgress`'s
  catch: `onStop` leaves `finalProgressSnapshot` true, while `finish` and
  `onDestroy` clear it in `finally`. Characterization pins the difference;
  any exception-handling change belongs in a separate behavior fix.
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
- Phase-12 evidence found a timing-sensitive original Phase-1 guide test:
  `TvGuideVisibilityCharacterizationTest.epgAiringReplayFutureAndExpiredRowsPinVisibilityAlphaAndProgressScale`
  allows only 30 ms of real-clock binding drift. One concurrent full run
  produced progress 32 outside 1..31; the unchanged isolated and quiet full
  runs pass. Investigate clock control separately; no test window or
  production change is included here.
- Revisit the per-class R8 keep rules after the series.
- `keyword_cache_screen_test.dart` uses a 150ms real async startup wait; one full run under concurrent gate workload missed it, while the isolated file and complete quiet retry passed unchanged. Investigate timing reliability separately; no test delay/allowlist or application fix here.
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

- Phase-2 characterization preserves query-only subtitle suffix filtering:
  `.ttml`/`.dfxp` URLs with a fragment can pass `isSideRenderableSubtitle`.
  Review separately; no filter change is made here.
- Phase-2 characterization preserves case-sensitive `mypikpak.com` URL
  matching (provider matching is case-insensitive) and prefix-only catalog
  IMDB validation (a bare `tt` is accepted). Any normalization/validation
  change needs its own behavior change and tests.

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
- 2026-10-07 — phase 2 design round 1 (Codex): P1 (policy `patched`
  encoding didn't match the checker → policy `moved` with substitutions,
  `setupPlayer` `patched`, fixture materializer + full phase-2 extraction
  fixture first); P2s folded (per-invocation policy reads, async fake
  messenger + per-function null-channel/exception/default-argument cases,
  typed reflection selectors); P3s: fixed opt-in set, inventory scope notes.
- 2026-10-07 — phase 2 design round 2 (Codex): **No P1s**; two P3 wording
  fixes applied. Phase 2 design approved for execution.

- 2026-10-07 — **Phase 2 step T complete**, based on `dcbd9aafe` at
  starting branch revision `2df3c1a9f`. The checker accepts the selected
  manifest for normal checks and self-tests; phase fixture evidence uses the
  selected phase, while the offline Kotlin 2.2.20 PSI build cache remains
  shared. The fixture materializer applies moved-row substitutions and
  retained `patched` rows. Added `tvplayer_p2.json`: 54 moved subtrees,
  12 destinations, one `setupPlayer` patch, with companion-constant
  relocation and exact policy substitutions. Complete phase-2 extraction
  passes; all **32 checker self-tests** pass (the unchanged 24 phase-1
  checks plus eight phase-2 checks, including both required extra-edit
  negatives). Original all-retained self-comparison: **2,839 declarations,
  zero differences**. Unchanged phase-1 manifest on this tree: **3,477
  declarations, zero differences**. Evidence: `p2/checker-self-tests.log`,
  `p2/original-self-comparison.log`, `p2/phase1-regression.log`,
  `p2/fixtures/`. No production moves.

- 2026-10-07 — **Phase 2 step 0 stopped at the required Media3 opt-in
  preflight**, before characterization or production moves. Actual cached
  Media3 1.8.0 class annotations require the policy, `languageOfOverride`
  and `buildAudioTrackLabel`; **`classifyIptvError` uses stable symbols and
  drops out of the derived set**. Independent `javap` confirms the
  exception type and `responseCode` field are stable. The plan expressly
  says to stop if the set differs, so the manifest retains the approved
  design pending resolution. Details are in the dependency report's
  "Phase 2 step 0 preflight" section and `p2/media3-opt-in-audit*`.
  Clean original JVM baseline **`baseline-dcbd9aafe`** recorded: **323
  identities, 322 pass, one existing focus failure, no skips**, zero dirty
  files, stable fingerprints, JBR 21.0.10. Original lint archive: **253
  errors, 1,100 warnings, 175 UnsafeOptInUsageError issues**, complete
  issue set and reports in `p2/lint-baseline-dcbd9aafe/`. No `p2-step0`
  baseline, mutation table or additions-only comparison is claimed.
  Characterization and its proofs remain pending. Detached original
  worktree removed; no production source, lockfile, ProGuard or phase-1
  manifest changes, branch switch, push or device interaction.
- 2026-10-07 — step-0 opt-in preflight stopped as designed: Media3 1.8.0
  bytecode shows `classifyIptvError` uses only stable APIs; the required
  opt-in set is the three declarations above (Claude approved the
  correction). Step 0 resumes.

- 2026-10-07 — **Phase 2 opt-in manifest correction complete** after the
  approved plan update `861aa13ed`. `classifyIptvError` now has only the
  private-to-internal visibility substitution. The complete extraction
  fixture explicitly pins the three annotations and absence of one on the
  classifier; all 32 checker self-tests pass. Re-derived Media3 1.8.0 set
  matches the corrected design. Evidence: `p2/step0/media3-opt-in-audit.json`
  and `p2/step0/checker-self-tests.log`. Step 0 continues on the original
  production base `dcbd9aafe`; no production moves.

- 2026-10-07 — **Phase 2 step 0 complete** on original production
  `dcbd9aafe`, following the approved three-declaration opt-in correction
  (`5bb66a997`). Added **55 named tests in ten classes**, covering all
  **48 moved function declarations**, the nested candidate and policy, and
  the four consumed constants. Exact typed reflection selects both channel
  overloads; real Kotlin default dispatch is exercised for EPG current
  true/false and menu rows. Fake messenger request/reply buffers and main
  Handler timing, per-function result/failure/null-channel contracts,
  reporting swallow/quick-play propagation, exactly-once 45 s EPG delivery,
  policy per-invocation reads in both methods and retry/header boundaries
  are pinned. Original focused run: **55/55 pass**.
  **65 distinct isolated original-code mutations are assertion-killed**,
  covering every named test, with zero survivors or compile/crash proofs.
  Four final assertion/isolation proofs were repeated (69 proof runs total).
  The complete test → mutation → failing assertion table is appended to
  the dependency report; raw patches/logs/XML and exact mutation strings
  are in `p2/step0/`. Both policy methods independently reject stale state;
  EPG before/after-deadline delivery and send-exception contracts have extra
  controls. All four qualified-constant reference searches return no matches.
  Re-derived Media3 1.8.0 annotation set matches the approved three; all
  **32 checker self-tests** pass, including the complete updated fixture.
  Original lint evidence from the preflight remains valid and archived for
  the later gate comparison (253 errors, 1,100 warnings, 175 opt-in issues).
  New full JVM baseline **`p2-step0`** and original-plus-tests verification
  each have **378 identities: 377 pass, the unchanged known focus failure,
  no skips**. Versus clean `baseline-dcbd9aafe`: **55 passing additions
  only**, zero missing identities or changed original statuses; original
  and current maps match exactly. Stable fingerprints, JBR 21.0.10; current
  baseline tested `5bb66a997` with the 14 final test files awaiting this
  commit, whose hashes are archived. File-size and diff checks pass.
  Detached original worktree removed. **Stopped before production moves**
  as requested; no source, lockfile or ProGuard changes, push, branch switch,
  device or emulator interaction. Later phase-2 JVM gates use `p2-step0`.

- 2026-10-07 — **Phase 2 step 0b complete** on original production
  `dcbd9aafe`. Added four URL-guard tests: 59/59 phase-2 tests pass on the
  original. Six named assertion-failing proof runs cover five distinct
  mutations; exact Claude d01 also fails both new twin assertions in the
  full 120-identity characterization run. No compile/crash proofs. First
  delimiter and query/fragment guard order, ampersands and encoded delimiters
  are pinned; the equivalent segmented-strip order is documented. Mutation
  table appended to the dependency report; evidence `p2/step0b/`.
  JVM baseline **`p2-step0b`: 382 identities, 381 pass, the unchanged focus
  failure, no skips**. All 378 prior statuses match `p2-step0`; four passing
  additions only, stable input fingerprint/JBR 21.0.10. Mutation worktree
  removed; no production, lockfile or ProGuard edits. Later phase-2 JVM
  gates compare against `p2-step0b`.

- 2026-10-07 — **Phase 2 step 1 moves complete**, following step 0b
  `6a441d0f4`. Moved exactly 54 subtrees to the 12 manifest destinations;
  policy supplier/setupPlayer patch, constants and three opt-ins are the
  only declared semantic-token edits. PSI checker: all 2,839 declarations
  classified, zero differences; 32 self-tests pass (phase-1 fixture retained).
  Test-helper-only retargets preserve typed/default dispatch and candidate
  class assertions; the policy helper additionally verifies construction
  laziness and both callbacks on their invoking thread. Dependency report
  records every retarget; Dart/native source anchors remain valid unchanged.
  Activity 19,961 → 19,017 lines, new files 7–233; size ratchet updated
  with `--update`, preserving unrelated entries. Compile/tests, size and
  diff checks pass with no new Kotlin warnings. Clean **`p2-gate` matches
  all 382 `p2-step0b` identity/status pairs exactly**; 381 pass, unchanged
  focus failure, no skips. Four Dart guard suites: 44 pass/one existing
  failure, all 45 statuses match phase-1 gate. Evidence `p2/step1/`,
  `junit/p2-gate/`. Release/R8, lint, decoder and full Flutter gates follow.
  The activity retains phase 3–7 responsibilities under its existing
  temporary exception; no new oversized component or localization text.

- 2026-10-07 — **Phase 2 gate checks complete on `0607b0b60`; decoder
  verification pending-environment.** All 382 JVM identity/status pairs
  exactly match `p2-step0b` (381 pass, unchanged focus failure, no skips).
  Checker classifies all 2,839 declarations with zero differences; all
  32 self-tests pass, including the unchanged phase-1 fixture. Kotlin
  compilation has no new warnings; size ratchet and source guards pass
  (the latter retain their one observed historical failure). Android lint
  issue identities/multiplicities exactly match original `dcbd9aafe`: 1,353
  issues (253 errors, 1,100 warnings), including all 175 opt-in issues.
  Both lint runs exit 1 for existing issues; no new lint regression.
  Release APK builds successfully. R8 verifies all 12 destinations, 18
  classes (12 new `…Kt` facades plus policy/candidate/request-result
  classes) and 102 members: 87 explicit identity mappings, 15 implicit
  identities checked in DEX; three negative controls pass. Decoder script
  fails identically to phase 1: all three ABI `libmpv` hashes match the
  unchanged fallback, with the same nine missing subtitle decoders and
  three filters. Patched-bundle verification remains **pending-environment**;
  no dependency or ProGuard workaround, and no complete decoder-gate claim.
  Full Flutter suite via `suite_evidence.py` on the clean Step 1 tree:
  **all 12,855 identity/status pairs exactly match phase 1** — 12,794
  successes, 13 existing failures, 28 existing errors, 20 skips; no additions,
  removals, changed statuses or SDK/tree drift. Extra analyzer comparison
  has no added diagnostics after exact generated debug/release-copy
  relocation (1,758 vs 1,767, removed output/duplicate entries); all Dart
  sources unchanged. Raw evidence under `p2/gate/`, JVM under
  `junit/p2-gate/`; the dependency report records commands/results and the
  generated-path comparison details. Lockfile, ProGuard and phase-1
  manifest protected hashes unchanged. No independent review performed:
  Claude runs the separate session. **Stopped after phase 2** with no push,
  branch switch, device/emulator interaction or bug fix.
- 2026-10-07 — phase 2 post-implementation reviews of `2df3c1a9f..dec50b884`.
  Claude: activity diff is removals plus the single patched call site;
  footprint limited to tv/ Kotlin, tests, dev/tool and docs; size baseline
  only 19,961 → 19,017; Claude's 16-mutation sample 15/16 killed, survivor
  d01 closed in 0b. Independent Codex review (fresh session): **No P1s, no
  findings**. Decoder verification remains pending-environment (CI release
  build, end-of-series checklist). Phase 2 complete; merged.
- 2026-10-07 — phase 3 design round 1 (Codex): P1s folded (status pill
  deferred — no two-output delegator in the checker; exhaustive destination
  partitioning with pinned structural spans and slot-anchored `added`
  controller properties, phase-3 fixtures first); P2s folded (computed,
  explicitly-qualified Host forwarders; braced host templates; skip network
  fixture prerequisite or deferral; recording evaluation-time cases;
  current-tree check of earlier destinations); P3 `Context.MODE_PRIVATE`.
- 2026-10-07 — phase 3 design round 2 (Codex): P1 (Up Next `Glide.with`
  overload would change with an `Activity`-typed injection) → controllers
  take `AppCompatActivity`, overload-resolution audit of every substituted
  `this`, Glide lifecycle test; P2 cross-feature reads go through the owning
  controller + Skip↔Up Next characterization; P3 scope/title/estimate.
- 2026-10-07 — phase 3 design round 3 (Codex): **No P1s** (all 58 activity `this` uses audited for overload resolution); P3 sketch types fixed. Phase 3 design approved.

- 2026-10-08 — phase 3 step T complete on `refactor/tvplayer-p3` (base
  `ec365eb80`), with production code untouched. Re-measured 62 moved subtrees,
  22 patched declarations / 52 context occurrences, six original-slot additions.
  Exhaustive pinned destination partitions, computed Host scaffolding, slot/order
  checks, historical `--at` checks and unchanged earlier destinations are covered
  by 53 passing dispatcher self-tests. Complete extraction fixture compiles;
  all 58 activity-this sites retain their compiled overload descriptors. A
  compiled Activity-injection negative is rejected for the Glide overload
  change. Raw evidence is under `p3/`; the dependency report records the
  re-measured inventory and commands/results. No production moves performed.

- 2026-10-08 — phase 3 step 0 complete on original `ec365eb80`, with 44
  new passing characterization identities and 44/44 assertion-based mutation
  proofs (one named proof for every addition). Deterministic skip HTTP shadow
  prerequisite passed 20 consecutive latch-controlled IO/Main fetches; skip
  remains in scope. Timer/menu/end behavior, Glide activity lifecycle,
  Up Next ticking/keys/teardown, Skip↔Up Next and playItem order, recording
  engine/tee/permissions/lazy reads, registry delivery-time membership,
  click-time profile/resource authority and persisted schedules, host liveness,
  and ring repaint paths are covered. Clean JVM baseline `baseline-ec365eb80`
  (382/381 pass) → `p3-step0` (426/425 pass): all prior statuses identical,
  44 passing additions only; the same existing focus failure remains.
  Original lint issue set archived (1,353 issues; 253 errors/1,100 warnings;
  175 UnsafeOptInUsageError). Deps report contains the complete mutation table
  and baseline provenance. Lockfile, ProGuard, activity and earlier destinations
  unchanged. Temporary original worktree removed after evidence archival.
  **Stopped after step T/0; no production moves, push or device interaction.**

- 2026-10-08 — **Phase 3 step 0b complete before moves.** Added 30 original-surface characterization tests; all 70 sweep mutations fail named assertions on ec365eb80. All nine skip focus exclusions, key/post conditions, animation durations/targets/deadband, reachable recording Toast occurrences, dialog text and sleep/skip/Up Next strings are pinned. Claude exact e12–e15 rerun against 194 phase-2/3 tests: all killed, clean control passes. Clean `p3-step0b` has 456 identities (455 pass, unchanged source-browser focus failure), retaining all 426 p3-step0 statuses with 30 passing additions. Rejected fixture-leak attempt is archived; accepted combined run passes after cleanup. Three unreachable original recording-message guards are preserved and documented, no bug fix. Evidence `p3/step0b/` and `junit/p3-step0b/`; original detached tree removed. Production, lockfile, ProGuard and earlier manifests unchanged. Step 1 and gates follow.

- 2026-10-08 — **Phase 3 step 1 moves complete.** Manifest-materialized four controllers (92/282/155/436 lines), 62 subtrees, 22 exact patched activity declarations, six slot-anchored additions; activity 19,017 → 18,265, size baseline updated without unrelated changes. Typed shared reflection helper and Dart Up Next anchor retargeted; all other characterization bytes/assertions unchanged. All 194 characterizations pass. Checker zero differences across 2,671 declarations; 53 self-tests, both historical manifests and current 22 earlier destinations pass. Forced Kotlin recompile matches all five original warnings. Compiled overload audit passes all 58 sites, Glide remains FragmentActivity; complete onStop/onDestroy order assertion passes. No snapshot Host state, initializer relocation, teardown reorder, status-pill move, bug fix, dependency or ProGuard edit. Full gate follows.

- 2026-10-08 — **Phase 3 final step-0b message boundary supplement.** Gate verification corrected the earlier stable-dependency reachability assumption. Three extra cases pass on original ec365eb80 and three named assertion mutations kill engine/schedule permission revocation messages and a forced-HLS change between eligibility reads. All recording Toast branches/texts are now covered; step-0b totals 33 new tests and 73/73 sweep proofs. Original proofs precede bringing these cases into the moved tree. Sequencing deviation: these test-only additions finish during the gate after Step 1; production is unchanged. Original canonical p3-step0b is extended, preserving earlier 456-identity archives with before-boundary labels. The quiet full Flutter rerun already exactly matches all 12,855 phase-2 identity/status pairs; these later changes affect only Android JVM tests/docs, with no Dart or production input changes.

- 2026-10-08 — **Phase 3 gate complete; decoder pending-environment.** Final original p3-step0b and clean moved p3-gate exactly match **459 JVM statuses** (458 pass, unchanged focus failure); 33 passing additions vs p3-step0. **73/73 sweep proofs**, final Claude e12–e15 rerun against 197 characterizations all killed. Checker zero differences for 2,671 declarations, 53 self-tests, both historical manifests, all 22 earlier destinations, 58 bytecode overload sites and full teardown order pass. Forced compile preserves five warnings; size passes at activity 18,265/controllers 92–436. Final lint no additions: 1,352 issues, same 253 errors/175 opt-ins, only fixture-referenced splash_logo unused warning removed. Release APK succeeds; R8/DEX verifies 21 classes/276 members including all Host/anonymous objects and both Kt facades (159 explicit + 117 DEX identities, three negatives). Decoder output and three libmpv hashes unchanged from earlier phases: pending-environment, no workaround. Full quiet Flutter run exactly matches **all 12,855 phase-2 statuses**; initial one keyword-cache startup timing miss rejected, focused and complete quiet retry pass unchanged. Analyzer exactly matches all 1,758 phase-2 diagnostics. Extra three original-proved message cases finished during gate, baseline/Native JVM/lint extended; complete Flutter/release evidence remains valid for test-only/docs additions. Protected inputs unchanged, original detached tree removed. Evidence p3/gate/, p3/step0b-boundary/, junit/p3-step0b/ and junit/p3-gate/. No self independent review, push, branch switch, device interaction or bug fix. **STOPPED after phase 3**; Claude's separate review follows.
- 2026-10-08 — phase 3 post-implementation reviews of `399e115a2..2b0a38442`.
  Claude: every added activity line read — controllers in their original
  field slots, computed explicitly-qualified Host forwarders, activity-owned
  readiness getters, Skip→Up Next read via `upNextController`, call-site
  patches only, `onDestroy` cleanup order unchanged; Claude's 18-mutation
  sample 14/18, survivors e12–e15 closed in 0b. Independent Codex review
  (fresh session): **No P1s**; 58 overload descriptors, Host/ownership/
  Runnable `this`/teardown verified; 117 mutation patches re-verified.
  **P3 accepted as a documented exception:** a few moved field initializers
  now run when the controller is constructed (activity line ≈162) instead of
  at their original slot — the Up Next ticker `Runnable` allocation and the
  notification request-code constant; both are allocation/constant-only
  (no reads, no side effects), so no observable change. **Rule tightened for
  phase 4+:** a moved field whose initializer would run earlier than its
  original slot must be listed in the manifest and proven inert
  (constant / allocation-only, no reads of other state, no side effects);
  otherwise the controller property is split or the slot preserved.
  Decoder verification remains pending-environment. Phase 3 complete; merged.
- 2026-10-08 — phase 4 design round 1 (Codex): P1s folded (overload auditor
  extended for constructors, context aliases and reviewed Runnable
  receivers, with a phase-4 audit fixture; per-feature prerequisite →
  deferral rule); P2s folded (phase-4 fixture dispatch + earlier destinations
  frozen at `eee52b084`; uncached latch-controlled cue fetch and blockable
  alignment; expectations corrected — no countdown, work continues across
  `onStop`, destroy-only cancellation, unbounded cue cache).
- 2026-10-08 — phase 4 design round 2 (Codex): **No P1s**, no further findings. Phase 4 design approved.

- 2026-10-08 — phase 4 step T: re-measured `eee52b084` (2,629 PSI
  declarations); manifest owns 66 moved subtrees / 1,131 partition lines,
  31 references patched in 14 retained declarations, four added declarations
  and 28 exact initializer-timing proofs. Earlier destinations (26 files,
  including all four phase-3 controllers) frozen at `eee52b084`; no whitelist.
  Original all-retained comparison and complete production-config extraction
  fixture: zero differences. Fixture compiles; all 23 direct/alias/constructor
  invocation descriptors unchanged; four reviewed Runnable self receivers.
  Phase-4 constructor/alias/receiver audit fixture and move-checker negatives
  added; all historical phase suites/checks retained. Evidence: `p4/`;
  production unchanged. Checker self-tests: 73/73 pass (historical suites
  included; each negative fails for its stated reason). Explicit controller property types resolve the Host
  cycle without construction-time reads.

- 2026-10-08 — phase 4 tooling follow-up: the inherited phase-3 positive
  fixture writer still hard-coded `p3/fixtures/phase3` when dispatched by
  phase 4. It now uses the active evidence phase, like the phase-1/2 writers.
  The focused historical positive check passes and archives under `p4/`;
  its bytes equal the existing historical fixture. Earlier step-T runs had
  regenerated those same historical fixture bytes in `p3/`; this evidence
  path deviation is recorded here. Production and manifests unchanged.

- 2026-10-08 — phase 4 step 0: both per-feature prerequisites passed on
  `eee52b084` first (seven tests, 20 blocked alignments and 20 uncached loads;
  Main publication, stale work, failure fallback and destroy covered).
  No feature deferred. Added 61 original characterizations for auto-sync
  outcomes/OOM, ladder/verify boundaries and timings, pill UI/animations,
  continued work across onStop, destroy cancellation/shared-handler cleanup,
  renderer/ticker/offset/selection, panel callbacks, all five menu builders,
  external/embedded overlay routing and the legacy track dialog. Every new
  test has an original-code assertion mutation proof: 61/61 killed, no
  compile failures or incidental crashes accepted. Table appended to deps;
  exact mutations, logs/XML/assertions and final test sources under `p4/`.
  Clean `baseline-eee52b084`: 459 (458 pass, existing focus failure 1).
  `p4-step0`: 520 (519 pass, same failure); identity comparison passes,
  additions only (61), all prior statuses identical. Original lint archived:
  1,352 issues (253 Error / 1,099 Warning), unchanged baseline issue set for
  the later gate. Production/protected inputs unchanged; temporary original
  worktree removed. STOP before production moves; Claude's independent
  mutation sample/review and any 0b follow later.

- 2026-10-08 — **Phase 4 step 0b complete before moves.** Nineteen new original-surface cases close Claude f01/f07/f13/f14/f15 and sweep moved strings/auto-hide deadlines, negative/zero offset guards and visible-only failure refresh. All 47 original sweep proofs fail named assertions; Claude exact five rerun against all 80 phase-4 characterizations are killed, control 80/80. Clean `p4-step0b`: 539 identities (538 pass, same focus failure), all 520 p4-step0 statuses identical with 19 passing additions. Evidence `p4/step0b/`, `junit/p4-step0b/`; original detached tree removed. Production/protected inputs and manifest unchanged; Step 1 and gates follow.

- 2026-10-08 — **Phase 4 step 1 moves complete.** Manifest-materialized 66 subtrees into auto-sync/subtitle controllers (684/776 lines), 31 inbound references in 14 declarations, four slot-anchored additions; activity 18,265 → 17,205 and its size baseline lowered with `--update`. Only the shared reflection helper is retargeted (94 name/getter entries); all other test bytes/assertions unchanged, no Dart retarget necessary. All 80 phase-4 characterizations pass, affected Dart source tests match all 45 prior statuses, forced Kotlin compile preserves five warnings. Checker zero differences over 2,629 declarations; historical manifests and 26 earlier destinations unchanged. Extended compiled overload audit 23/23 identical, four Runnable self sites, full lifecycle order and 28 initializer-timing proofs pass. No status-pill move, borrowed-resource cleanup, dependency/ProGuard edit or bug fix. Full gate follows.

- 2026-10-08 — **Phase 4 gate checks complete on `22990ad8a`; decoder pending-environment.** Clean JVM p4-gate exactly matches all 539 p4-step0b statuses (538 pass, same focus failure); all 80 phase-4 characterizations pass. Checker zero differences over 2,629 declarations, 73 self-tests, all three historical manifests and 26 frozen earlier destinations pass. Extended bytecode overload audit 23/23, four Runnable self sites, 28 initializer proofs and full lifecycle teardown/order pass; compile preserves five warnings. Size passes at activity 17,205/controllers 684/776. Lint exactly matches original 1,352 issues (253 errors, 175 opt-in errors), analyzer all 1,758 prior diagnostics. Release APK succeeds; R8/DEX verifies every new class/Host/anonymous object/facade (18 classes/323 members, three negative controls). Decoder script failure/output and all three native hashes unchanged: pending-environment, no workaround. Full quiet Flutter suite exactly matches all 12,855 phase-3 identity/status pairs on the same SDK and stable tree. Step 0b: 19 passing additions, all 47 sweep proofs and Claude's exact five survivors killed on original eee52b084. Evidence p4/step0b/, p4/step1/, p4/gate/, junit/p4-step0b/ and junit/p4-gate/. Protected inputs/manifest/earlier destinations unchanged; detached original removed. No self independent review, push, branch switch, device/emulator or bug fix. **STOPPED after phase 4**; Claude reviews separately.
- 2026-10-08 — phase 4 post-implementation reviews of `a665502e8..bee1f5ea2`.
  Claude: all non-forwarder activity additions read (controllers in slots,
  subtitle→auto-sync reads via `autoSyncController`, borrowed overlays stay
  activity-owned, two readiness getters, call-site patches in place incl.
  `onStop`/`onDestroy`); Claude's 16-mutation sample 11/16, survivors
  f01/f07/f13/f14/f15 closed in 0b (one earlier invalid 0-test attempt
  discarded). Independent Codex review (fresh session): **No P1s, no
  P2/P3**; 81 compiled overload sites across phases 3–4 match; 28 earlier-
  running initializers covered by inert proofs. Decoder verification remains
  pending-environment. Phase 4 complete; merged.
- 2026-10-08 — phase 5 design round 1 (Codex): P1s folded (sleep forwarder
  as a phase-5 `patched` activity-property row; initializer classifier
  support for typed empty collections/underscored literals with negatives;
  per-phase fixture dispatch + earlier destinations frozen at `1a33c42cb`);
  P2 recovery-writer executor barrier and ACK/exception cases.
- 2026-10-08 — phase 5 design round 2 (Codex): **No P1s**; P2 inventory wording superseded by the plan (note at the inventory head). Phase 5 design approved.

- 2026-10-08 — **Phase 5 step T complete.** Re-measured `1a33c42cb`: 2,548
  declarations, 42 moved subtrees / 820 partition lines, 20 patched retained
  declarations, three slot-anchored controller properties and 16 exact inert
  initializer proofs. Narrow classifier support for typed empty factories and
  underscored/suffixed literals; state/effectful negatives reject matching
  forged proofs. Phase-scoped dispatcher preserves the phase-4 manifest/suite;
  all **97/97** historical and phase-5 checker tests pass. Original all-retained
  self-comparison and complete production-config extraction fixture: zero
  differences. Fixture compiles; all seven activity receiver invocation
  descriptors unchanged; no context aliases/Runnable self sites. All 28
  earlier destinations frozen at `1a33c42cb`, no whitelist. Sleep wiring is
  one patched activity-property row with named existing characterization and
  extra-edit negative. Evidence: `p5/`; production unchanged.

- 2026-10-08 — phase 5 step-T routing follow-up: direct invocation of
  `test_kotlin_moves.py --manifest …` now selects the active evidence phase,
  matching the checker wrapper. All historical fixture output stays under
  `p5/`; the direct dispatcher also passes **97/97** tests. Evidence:
  `p5/direct-dispatch-self-tests.log`. No production changes.

- 2026-10-08 — **Phase 5 step 0 complete.** Added 44 original-surface
  characterizations (18 progress, 13 channel-start/ladder, 12 Start Over,
  one recording handoff) using typed selectors, binary messenger replies,
  an entered/bounded separate recovery-writer executor barrier, real
  stop/destroy and tee publication. Queued ordinary versus synchronous
  final/completed/local-completion recovery, exact progress maps, delayed
  out-of-order/after-destroy ACKs, the non-finally onStop player-read failure,
  playlist refresh order, channel/ladder deadlines and token supersession,
  call-time Start Over defaults and lifecycle/player-error cancellation
  are pinned. All 44 new tests pass on `1a33c42cb`; **44/44** original-code
  mutations fail named assertions. Two invalid harness attempts are
  archived separately and excluded; repaired positives/proofs pass.
  Clean `baseline-1a33c42cb`: 539 identities (538 pass, existing focus
  failure 1). Final `p5-step0`: 583 (582 pass, same failure), all 539 prior
  statuses identical and 44 passing additions; identity comparison passes.
  Original lint archived: 1,352 issues (253 Error / 1,099 Warning), existing
  errors retained for later issue-set comparison. Mutation table appended
  to deps; raw logs/XML, exact patches and final test hashes under `p5/` and
  `junit/`. All production/protected inputs and 28 earlier destinations
  unchanged; detached original removed. Step T commits `ae3e8e64f` and
  `e1859e450` retain 97/97 checker tests, zero-diff original comparison and
  seven identical compiled overload descriptors. **STOP before production
  moves**; Claude's separate sample/review and any Step 0b follow later.

- 2026-10-08 — **Phase 5 step 0b complete before moves.** Six controlled-clock
  cases pin both programme start/stop comparisons at equality and ±1 ms, including
  request-time airing captured across a delayed reply. All six original-code
  mutations fail named assertions; Claude exact g14 rerun against all 50 phase-5
  tests is killed (control 50/50). The moved 60-second elapsed logging comparison
  retains step-0 coverage/proof; no other moved time comparison exists. Clean
  p5-step0b: 589 identities (588 pass, same focus failure), all 583 p5-step0
  statuses identical with six passing additions. Table/raw XML/logs/clock source
  and original bytecode under p5/step0b/ and junit/p5-step0b/. Production, manifest
  and protected inputs unchanged; detached original removed before Step 1.

- 2026-10-08 — **Phase 5 step 1 moves complete.** Manifest-materialized 42
  members into progress/channel-start/Start Over controllers (445/497/375 lines),
  20 patched activity declarations including the sleep forwarder, three original-slot
  controller properties and 16 inert initializer proofs. Activity 17,205 → 16,487;
  size --update scoped to its ratchet. Shared reflection helper gains 42 owner routes;
  the five watchdog accesses and one Dart progress anchor retarget with equal assertions.
  Focused JVM 64/64 (all 50 phase-5 cases), all 45 affected Dart statuses unchanged.
  Checker zero differences across 2,548 declarations; seven compiled overload sites,
  full lifecycle token/order and five original warning identities pass. All 28 earlier
  destinations, manifest/protected inputs unchanged. Evidence p5/step1/. Full gate follows.

- 2026-10-08 — **Phase 5 gate complete on 5d3d9a067; decoder pending-environment.**
  Clean JVM p5-gate matches all 589 p5-step0b statuses (588 pass, same focus failure);
  all 50 phase-5 cases pass. Checker zero differences over 2,548 declarations, all
  97 self-tests and four historical manifests pass; 28 earlier destinations frozen.
  Seven actual bytecode overload descriptors, 16 initializer proofs, full lifecycle
  order and five original warning identities pass. Size passes at activity 16,487,
  controllers 445/497/375. Lint exactly retains 1,352 issues (253 errors, 175 opt-ins);
  analyzer all 1,758 prior identities. Release APK succeeds; R8/DEX preserves all
  14 new classes/273 members and three negative controls. Decoder failure/output and
  all three native hashes unchanged: pending-environment. Full quiet Flutter suite
  exactly matches all 12,855 phase-4 identity/status pairs on the same SDK/flags
  and stable clean tree. Step 0b: six passing additions, six original assertion proofs,
  Claude exact g14 killed (control 50/50). Manifest/protected inputs/earlier files
  unchanged; detached original removed. Evidence p5/step0b/, p5/step1/, p5/gate/
  and junit/. No self independent review, push, branch switch, device/emulator or
  bug fix. **STOPPED after phase 5**; Claude reviews separately.
- 2026-10-08 — phase 5 post-implementation reviews of `4dd0d97e0..ecc5a3f9d`.
  Claude: activity-side changes and both retargets read (Dart anchor now in
  `TvProgressReporter.kt`, asserted manual-switch guards still inside
  `sendProgress`); Claude's 18-mutation sample 17/18, survivor g14 (exact-now
  programme boundary) closed in 0b. Independent Codex review (fresh
  session): **No P1s, no P2/P3**; 4 historical `--at` checks, 28 frozen
  destinations, progress/recovery/ACK/teardown ordering, `onStop`
  non-finally vs `finish`/`onDestroy` finally all preserved. Activity
  17,205 → 16,487. Decoder verification remains pending-environment.
  Phase 5 complete; merged.
- 2026-10-08 — phase 6 design round 1 (Codex): P1 folded (renderer fields run
  at the classic controller's slot → effective slot mapping, 28 inert
  proofs, classifier support for `Any()`/`Color.parseColor(literal)`, new
  negatives); P2 step 0 corrected to the real implementation (per-style
  activity instances, cached style, view-mutating painters, LIVE/REC badges,
  favourites hint gating, hide leaves the pending callback).
- 2026-10-08 — phase 6 design round 2 (Codex): **No P1s**; P2 inventory superseded-note and P3 checklist fixed. Phase 6 design approved.

- 2026-10-08 — **Phase 6 step T complete (production untouched).** Re-measured
  `e71ddac3a`: 16,487 activity lines / 2,567 PSI declarations; 47 moved
  members / 1,344 partition lines (including attached trivia), 16 activity
  occurrences patched in nine declarations, one slot-anchored controller
  property. Nested eager renderer construction/argument/position is pinned;
  effective slots require all **28** exact inert proofs, including the
  renderer's first field. Classifier allows only zero-argument `Any()` and
  valid literal-only `Color.parseColor`, rejecting state/effectful reads.
  Complete production fixture compiles; checker original self-comparison
  and extraction have zero differences. **118/118** dispatcher tests pass
  (all historical suites retained); the compilable same-name Host capture
  negative fails the exact moved-body comparison. All 38 `classic.` / four
  `styled.` cross references are counted. Compiled overload audit **42/42**
  retains descriptors, including four Glide FragmentActivity calls. Five
  historical `--at` checks and 31 earlier destinations frozen at
  `e71ddac3a` pass, without whitelist. Evidence: `p6/`; Step 0 follows.

- 2026-10-08 — phase 6 Step-T size follow-up: the initial fixture copied
  the activity's full imports (801/846 lines). Exact reviewed destination
  subsets now produce **689/729-line** files; activity imports remain frozen.
  Final phase-6 suite **21/21** passes; historical suites unchanged. Fixture
  recompiles; original bytecode was rebuilt from restored `e71ddac3a` before
  the repeated **42/42** overload audit. The transient prefix/newline failure
  was rejected, not accepted as parity. Evidence `p6/finalize-imports.log`,
  `reviewed-destination-imports.json`, `phase6-final-self-tests.log`.

- 2026-10-08 — **Phase 6 step 0 complete; STOP before production moves.**
  Original `e71ddac3a` passes all **43** new characterizations, spanning
  four independent style instances, cached style/tree, hierarchy/drawables/
  typography, dock geometry and layout callbacks, entrance/hide/tick
  timings, now/next/progress, LIVE/REC/favourites, same-channel repaint,
  window install/merge, default arguments and both Glide lifecycle paths.
  **45/45** original mutations fail named assertions (every new test plus
  two explicit layout-callback proofs); no compile/crash/zero-test proof.
  Final `p6-step0` has **632 identities / 631 pass / the existing focus
  failure**: all 589 clean `baseline-e71ddac3a` statuses identical, 43
  passing additions only, complete XML and stable fingerprints. Original
  lint archived: 1,352 issues, 253 errors/1,099 warnings (175 opt-in errors);
  no fix. Mutation table in deps; raw evidence `p6/` and `junit/`.
  Provisional baseline retained separately after strengthening two layout
  cases; final baseline rerun and compared, no regressions accepted.
  Manifest named-test metadata matches recorded cases; move/patch/proof
  configuration unchanged. Production, previous manifests/destinations,
  lockfile and ProGuard unchanged. Temporary original worktree removed.
  No production moves, push, branch switch, device interaction or self
  independent review. Claude's independent sample/review and any 0b follow.

- 2026-10-08 — **Phase 6 step 0b complete.** Closed Claude h11 and swept both
  paging gates across four styles: stale totals with paging inactive, paged
  positive/nonpositive totals, empty/single/multiple windows and favourite
  hint gating. Original control 47/47; eight named assertion mutation proofs
  pass; exact h11 rerun kills all four new cases. `p6-step0b`: 636 identities
  (635 pass, existing focus failure); all 632 step-0 statuses unchanged, four
  passing additions only. Evidence `p6/step0b/`, table in deps; production
  unchanged and original worktree removed. Step 1 follows.

- 2026-10-08 — **Phase 6 step 1 complete (`c21519da7`).** Exact manifest
  extraction: classic controller 689 lines, eager nested styled renderer 729;
  activity 16,487 → 15,167. All 47 characterizations pass unchanged; only the
  shared reflection helper retargets 47 names (14 via nested `styled`).
  No Dart retargets. Scoped size baseline updated with `--update`.
  Computed 19-member Host, eager renderer first field and all 28 inert
  proofs preserved; no lifecycle edits. Evidence `p6/step1/`.
- 2026-10-08 — **Phase 6 gate complete; STOP for Claude’s review.** Tested
  clean committed `c21519da7` tree. Checker: all 2,567 declarations, zero
  differences; 118/118 self-tests; five historical `--at` checks (p5 at
  e71ddac3a); 31 frozen earlier destinations, no whitelist. Compiled audit
  42/42, all four Glide FragmentActivity calls; 28 initializer proofs and
  identical teardown/lifecycle tokens. JVM exactly preserves all 636
  p6-step0b identities (635 pass, existing focus failure). Five production
  compiler warnings unchanged; lint exactly retains all 1,352 e71ddac3a
  issues (253 errors, 175 opt-ins); analyzer all 1,758 prior identities.
  Focused source tests exactly retain 44 passes/one existing failure.
  Release APK succeeds; R8/DEX all seven new classes/152 members and three
  negative controls pass. Decoder pending-environment: valid APK check,
  failure output and all three native hashes identical to Phase 5; rejected
  missing-argument invocation recorded separately. Full quiet Flutter suite
  exactly matches all 12855 Phase-5 identity/status pairs
  (12794 success/13 failure/28
  error/20 skipped), same SDK/flags and stable clean tree.
  Step 0b: four passing additions, eight original assertion proofs, exact
  Claude h11 killed in all four styles (47/47 control). Evidence p6/step0b/,
  p6/step1/, p6/gate/ and junit/; table/retargets in deps. Manifest/protected
  inputs/earlier files unchanged; original worktree removed. No production
  deviation, bug fix, push, branch switch, device/emulator or self independent
  review. **STOPPED after phase 6**; Claude reviews separately.
- 2026-10-08 — phase 6 post-implementation reviews of `239460785..a72dfb14f`.
  Claude's 20-mutation sample 19/20 (first-occurrence variant for strings
  duplicated between classic/styled); survivor h11 (paging-gated category
  total) closed in 0b. Independent Codex review (fresh session): **No P1s,
  no P2/P3**; 38 `classic.`/4 `styled.` qualifications correct, 28 inert
  initializer proofs, 42 compiled overload descriptors (4 Glide
  `FragmentActivity`) + historical 37 Toast sites reproduce. Activity
  16,487 → 15,167. Decoder verification remains pending-environment.
  Phase 6 complete; merged.
- 2026-10-08 — phase 7 design round 1 (Codex): P1 folded (16 inert
  initializer proofs, not 2); P2s folded (phase-7 fixture dispatch + earlier
  destinations frozen at `a4ed4f368` + 8-site audit; five-argument trio
  forwarder with `hideGuideOnReady` and a successful-switch characterization;
  guide-data callback contract corrected and characterized as-is).
- 2026-10-08 — phase 7 design round 2 (Codex): **No P1s**, no new findings. Phase 7 design approved.

- 2026-10-08 — **Phase 7 step T complete; production untouched.** Re-measured
  a4ed4f368: 15,167 lines / 2,417 declarations, 30 selected members, 16
  occurrences in six activity patches, 17 properties / 16 exact inert
  proofs, first-field slot 1,192. Complete extraction fixture compiles
  (586-line controller), zero checker differences; 8/8 compiled receiver
  descriptors including Glide FragmentActivity. All 134 dispatcher tests
  pass (16 new Phase-7 cases; historical Phase 6 uses its own manifest);
  33 earlier destinations frozen at a4ed4f368, no whitelist. The measured
  Host has 11 members; finish is the separate activity dependency, all six
  calls use activity.finish(). Five-argument trio forwarder pinned with
  drop/hard-code negatives; omitted contiguous initializer proof rejects.
  Clean original baseline (636/635 pass) and lint (1,352 issues) archived
  before fixture mutation; full provenance/evidence p7/ and junit/.
  No production moves or lockfile/ProGuard edits. Step 0 follows.

- 2026-10-08 — **Phase 7 step 0 complete; STOP before production moves.**
  Original a4ed4f368 passes **37/37** new cases: attached guide UI/focus/search,
  Glide ownership, visible-range lazy loading, async/partial/malformed/null
  bridge contracts, Next/switch success through the real playback trio,
  production Next/ENDED/key/clean-state callers, stale replies/rollback,
  READY/IDLE/10 s waits and unchanged destroy semantics. **52/52** mutations
  fail named assertions on the original, every new test covered; final
  fixture hashes recorded. Final `p7-step0`: **673 identities / 672 pass /
  the existing focus failure**; all 636 clean `baseline-a4ed4f368` statuses
  identical, 37 passing additions only, complete XML/stable fingerprints.
  Original lint archived (1,352 issues, 253 errors/1,099 warnings, 175 opt-ins).
  Checker repeated **134/134**, 2,417 original declarations/zero differences;
  16 inert proofs, eight compiled receiver descriptors, 33 frozen earlier
  files retained. Six manifest rows now name their fixture/behavior tests;
  move/patch/proof configuration unchanged. Two provisional full runs rejected
  for attached-view Robolectric synchronization interference; explicit
  activity/controller instrumentation and saved/restored frame settings
  resolve it. Original control/all proofs rerun with final fixture. Table,
  follow-ups and rejected-attempt details in deps; raw p7/ and junit/.
  Production, existing assertions, lockfile and ProGuard untouched; original
  worktree removed. No production moves, retargets, push, branch switch,
  device/emulator interaction or self independent review. **STOP**; Claude
  runs the independent sample/review and any 0b follows separately.

- 2026-10-08 — **Phase 7 step 0b complete before moves.** Fourteen original
  cases close i03/i08 and sweep every guide-wait cleanup call, both overlay
  cancellations, uppercase header/row fallbacks, type/rating/number/year/Next
  formatting and recycled-row Glide clearing. Original control 51/51;
  17/17 named assertion proofs with final fixture hashes, exact Claude i03/i08
  killed against all 51 cases. Clean-run `p7-step0b`: 687 identities, 686 pass,
  unchanged focus failure; all 673 p7-step0 statuses identical, 14 passing
  additions only, complete XML/stable fingerprints. Provisional fixture and
  mutation attempts rejected/archived; no behavior allowance changed.
  Table/evidence in deps and p7/step0b/, junit/p7-step0b/; detached original
  removed. Production, manifests, protected inputs and previous assertions
  unchanged. Step 1 and gate follow; no self independent review.

- 2026-10-08 — **Phase 7 step 1 moves complete.** Exact manifest extraction:
  30 members, controller 586 lines, activity 15,167 → 14,637; slot-anchored
  construction, all 16 inert proofs and the live explicitly qualified Host
  preserved. Real five-argument forwarder retains hideGuideOnReady; all six
  finish calls use the activity override. Only shared reflection routing
  (30 names) and the watchdog's local init helper change; all assertions and
  Dart tests unchanged. Focused 65/65 pass (51 Phase 7 + 14 watchdog), fresh
  debug compile retains five warning identities. Checker zero differences
  across 2,417 declarations; compiled receiver audit 8/8, Glide remains
  FragmentActivity. All 33 earlier files and five lifecycle bodies/order
  byte-identical; scoped size baseline lowered with --update. No status-pill
  move, production deviation, bug fix or self independent review. Full gate
  follows; evidence p7/step1/ and p7/gate/.

- 2026-10-08 — **Phase 7 gate complete; STOP for Claude's review.** Clean
  committed `6133bb444` tree: all 687 JVM identity/status pairs exactly match
  p7-step0b (686 pass, unchanged focus failure), complete XML/stable inputs;
  51 Phase-7 + 14 watchdog focused cases pass. Checker all 2,417 declarations,
  zero differences; 134/134 self-tests; all six historical --at checks
  (p6@a4ed4f368), 33 frozen earlier destinations/no whitelist. Compiled
  audit 8/8, Glide FragmentActivity; 16 exact inert proofs and all five full
  lifecycle/teardown bodies retained. Five compiler warnings unchanged;
  lint exactly retains all 1,352 a4ed4f368 issues (253 errors/175 opt-ins),
  analyzer all 1,758 prior diagnostics. Affected source tests exactly retain
  44 passes/one existing failure. Release APK succeeds; R8/DEX all 10 new
  classes/136 members and three mapping negatives pass. Decoder remains
  pending-environment: valid APK failure output, all three native hashes
  and missing sets match Phase 6; prior-log filename comparator mistake
  rejected/corrected, no native/script workaround. Full quiet Flutter suite
  exactly matches all 12855 Phase-6 statuses (12794
  success/13 failure/28 error/20
  skipped), same SDK/flags, complete/stable clean tree. Step 0b adds 14
  passing cases, 17 original assertion proofs, exact i03/i08 killed in all
  51-case runs. Evidence/table/retargets recorded in deps, p7/ and junit/;
  manifests/protected inputs/earlier files unchanged, original trees removed.
  No production deviation, bug fix, push, branch switch, device/emulator
  interaction or self independent review. **STOPPED after phase 7**.
- 2026-10-08 — phase 7 post-implementation reviews of `43a39dea9..cfd2a3f17`.
  Claude's 18-mutation sample 16/18; survivors i03 (hide cancels the guide
  wait) and i08 (uppercase header letter) closed in 0b. Independent Codex
  review (fresh session): **No P1s, no P2/P3**; 16 inert proofs, 8 compiled
  receiver descriptors, `finish()` virtual dispatch, true/false
  `hideGuideOnReady`, unguarded guide-data replies, watchdog assertions
  byte-identical. Activity 15,167 → 14,637. Decoder verification remains
  pending-environment. Phase 7 complete; merged.
- 2026-10-08 — phase 8 design round 1 (Codex): **No P1s**; P2s folded
  (resolver token checks only before dispatch, with a worker-thread
  characterization; all four re-points are one `iptvChannelStartController`
  patched row; `progressReporter` unchanged). Phase 8 design approved.
- 2026-10-08 — phase 8 Step T: re-measured on `53906805d` (activity
  14,637 lines). Manifest classifies all 2,335 declarations: 15 moved
  subtrees, 20 whole-declaration patched rows (23 caller substitutions in
  18 declarations, the four IPTV Host re-points in one property, and the
  retained ShufflePlaybackAttempt visibility patch). One exact inert
  initializer proof, eager fieldless applier construction, 51 computed Host
  forwarders, all 34 earlier destinations frozen. Complete production-config
  fixture compiles (controller 447/applier 450 lines); same-name Host capture
  negative also compiles and is rejected for its changed cross call and Host
  span. Original self-comparison: zero differences. Dispatcher keeps every
  historical manifest/suite; 152 tests pass including 18 phase-8 cases, all
  required negatives, and the historical phase-7 check at its merge. One
  compiled Toast receiver descriptor matches exactly. Evidence `p8/`;
  production unchanged. Public reflected members in internal controllers
  follow the phase-3 unmangled-name rule. Step 0 next; no production moves.
- 2026-10-08 — phase 8 Step 0: 45 original characterization tests pass;
  49/49 scoped original mutations fail their named assertions, all on the
  final fixture signature. Worker replies pin token acceptance before UI
  dispatch and live cursor evaluation; real apply path pins headers, resume,
  targets, metadata, shuffle and PikPak interplay. Bounded loopback MIME probe
  verifies headers, recursive apply and supersession. Badge/end-action and
  after-release cancellation are pinned. Clean baseline-53906805d has 687
  identities (686 pass/one existing focus failure); p8-step0 has 732 (731
  pass/same failure), all original statuses identical plus 45 new passes.
  Original lint archived: 1,352 issues (253 errors/1,099 warnings, 175 opt-ins).
  Mutation table and re-measured inventory appended to deps; raw evidence in
  p8/ and junit/. Detached original removed. All production/protected inputs
  unchanged; no production moves, bug fixes, push, device interaction or
  self independent review. **STOPPED after phase 8 Step T/0**.
- 2026-10-08 — phase 8 Step 0b: all four Claude survivors killed on original
  `53906805d`, with all 72 phase-8 tests per exact mutation. Added 27 tests
  and one stronger discovered-MIME assertion; 30/30 named assertion proofs
  cover every new/strengthened test. Sweep pins routes, all manual/startup
  resolver and apply reason strings, whole payload fields and both badge
  refresh sites. p8-step0b has 759 identities (758 pass/same focus failure),
  every p8-step0 status unchanged plus 27 passing additions. Raw evidence
  p8/step0b/ and junit/p8-step0b/; mutation table appended to deps. Original
  pack parser ignores MIME metadata: preserved and recorded as a follow-up.
  Detached original removed after proofs. Production moves are next.
- 2026-10-08 — phase 8 Step 1: materialized the approved manifest exactly.
  Activity 14,637 → 13,937 lines; source switch controller 447/applier 450.
  Applier is eager/fieldless; controller sits at its original first owned slot.
  All 51 Host forwarders computed and explicitly qualified, retained volatile
  headers and live retry-id read preserved. Whole IPTV property receives only
  the four pinned re-points; nested ShufflePlaybackAttempt changes visibility
  only. Shared reflection helper retargets 15 members, no assertions changed;
  three Dart anchors retargeted with the same assertions (19 tests pass).
  Source-switch, IPTV-start and watchdog JVM tests pass. Checker zero differences
  over 2,335 declarations, all seven historical manifests and 34 frozen earlier
  files pass; compiled overload 1/1, initializer proof and teardown order pass.
  Size baseline updated with --update (also ratchets existing upstream shrinkage).
  Protected inputs/manifests unchanged. Full gate next on the clean move commit.
- 2026-10-08 — **phase 8 gate complete on `dfa683648`; decoder
  pending-environment.** Step 0b `6d8c94c98` adds 27 passes, strengthens one
  MIME assertion, kills 30/30 named original mutations and Claude's exact
  j05/j08/j11/j12 against all 72 characterizations. Extraction `dfa683648`
  preserves scope and manifest exactly. Checker zero differences over 2,335
  declarations; 152 self-tests, seven historical manifests, 34 frozen earlier
  files, compiled receiver 1/1, initializer proof and teardown order all pass.
  Clean JVM gate exactly matches all 759 p8-step0b statuses (758 pass/same
  focus failure). Lint exact original 1,352 issues (253 errors/175 opt-ins);
  five compiler warnings and all 1,758 analyzer diagnostics unchanged.
  Size passes at activity 13,937/controller 447/applier 450. Release succeeds,
  R8/DEX verifies 7 classes/189 members including Host/anonymous objects.
  Decoder output, missing sets and three native hashes exactly match phase 7:
  pending-environment. Full quiet Flutter suite exactly matches all
  12855 phase-7 identities/statuses on the same SDK, stable clean tree;
  affected source suite also exactly matches 45 identities. All assertions
  retained at retargeted helper/three Dart anchors. Evidence p8/step0b/,
  p8/step1/, p8/gate/, junit/p8-step0b/ and junit/p8-gate/. Protected inputs
  and earlier destinations unchanged, original worktree removed. No self
  independent review, push, branch switch, device/emulator or bug fix.
  **STOPPED after phase 8**; Claude reviews separately.
- 2026-10-08 — phase 8 post-implementation reviews of `6fdfaf8c6..17a25ec67`.
  Claude's 15-mutation sample 11/15; survivors j05/j08/j11/j12 (route
  predicate, reason strings, payload mimeType, badge refresh) closed in 0b.
  Independent Codex review (fresh session): **No P1s, no P2/P3**; gate state
  untouched, live `pikPakRetryId` reads, volatile setter target, 43 compiled
  Toast descriptors, watchdog file byte-identical. Activity 14,637 → 13,937.
  Decoder verification remains pending-environment. Phase 8 complete; merged.
- 2026-10-08 — phase 9 design round 1 (Codex): **No P1s**; P2s folded
  (VOD vs Stremio TV exhaustion characterized separately; 14th owner-map
  route for the phase-8 boundary tests + rescan; auditor extension for
  implicit inherited receivers with opcode pinning). Phase 9 design approved.

- 2026-10-08 — phase 9 Step T complete against `c4906cd2f`. Re-measured
  manifest: 51 moved subtrees (30 fields, 16 functions, 5 constants),
  29 initializer proofs, 32 computed Host members, 93 activity-reference
  edits plus 18 token edits in the two whole-property rows (15 Host re-points).
  All 182 checker/auditor self-tests pass: 152 historical plus 22 extraction
  and 8 compiled inherited-receiver tests. Original self-comparison classifies
  all 2359 declarations with zero differences; all 36 earlier destinations
  remain frozen. Full production-config extraction fixture compiles (718-line
  controller) and its five receiver sites pass the bytecode audit, including
  explicit owner/descriptor/`invokevirtual` pins for three `findViewById`
  calls and `finish`; both Runnable self receivers are preserved. Static,
  super and widened-receiver compiled negatives fail for their stated reason.
  Evidence: p9/checker-self-tests-final.log, original-self-comparison.log,
  earlier-destinations.log, fixture-compile.log, overload-audit.json and
  fixtures/phase9-overloads/. Production unchanged; Step 0 follows.

- 2026-10-08 — phase 9 Step 0 complete on original `c4906cd2f`: 40 new
  characterization cases, 53/53 named assertion mutation kills (no compile
  errors/crashes accepted), with definitions, patches, raw Gradle/XML and
  dependency hashes under p9/mutations/ (a final terminal blank-line trim
  leaves all executable instructions/fields/descriptors identical; only debug
  line ranges differ, archived under p9/final-formatting/). Covers commit grace, manual
  rollback/supersession, UI/focus/animation/copy, failure predicates, recovery
  handoff/fallback, VOD versus Stremio TV exhaustion through the actual finish
  override, live watchdog/reprepare guards, diagnostics, parsing, stale resolve
  callbacks and the compiled fifteen-statement teardown order plus real queue
  retirement. Original controls pass (40 final new tests; earlier 142 affected
  tests). Clean baseline-c4906cd2f 759 = 758 pass + the existing focus failure;
  p9-step0 799 = 798 pass + that same failure. Identity comparison passes with
  40 additions only; the observed intermediate 797 statuses also remain
  unchanged. An initial Robolectric heap-error run with no complete XML was
  discarded; final fixtures reuse the phase-8 sandbox and both controls/proofs
  were repeated without changing heap/dependencies/runner configuration.
  Original lint archived: 1352 issues (253 errors, 1099 warnings, 175 unsafe
  opt-ins) for the later gate. Post-test owner-map rescan requires 30 entries
  (16 additions to the reviewed 14), retains the five public functions, and
  records the compiled-order helper retarget. Manifest supplements name actual
  tests. All 36 earlier destinations and protected inputs remain unchanged;
  original detached worktree removed. **STOPPED before production moves**;
  Claude's independent sample/review and Step 0b/Step 1/gate remain next.

- 2026-10-08 — phase 9 Step 0b: 11 new boundary cases; 28/28 named
  assertion mutation kills on original `c4906cd2f`, including all four exact
  Claude survivors k04/k09/k10/k12. Additional sweep covers every moved
  focus/controls gate, both real progress restart calls, every owned callback
  removal on commit/failure/rearm, switcher wait removal, failure stop and
  token/generation changes, and retained PikPak cancellation. The failed-row
  late resolver reply is ignored while recovery keeps the host alive. The
  four exact survivors also fail against all 65 phase-9/watchdog tests.
  `p9-step0b` 810 = 809 pass + the existing focus failure; all 799 `p9-step0`
  identities/statuses retained with 11 passing additions only. Owner rescan
  remains 30. Raw proofs/control/XML and comparisons: p9/step0b/. Production
  unchanged; approved Step 1 moves and the gate follow.

- 2026-10-08 — phase 9 Step 1 moves complete: manifest materialized with
  slot-anchored 718-line gate controller / 13,320-line activity, 32 computed
  Host members, 29 inert initializer proofs, 93 activity edits and the two
  whole-property rows' 15 re-points (18 token edits). The fifteen teardown
  statements remain in place; all 36 earlier destinations are byte-identical.
  Checker: 2359 declarations, zero differences; five compiled receiver sites
  retain descriptor/opcode pins, including virtual finish. All 155 focused
  JVM cases pass; 45 Dart source-test statuses exactly match phase 8. Thirty
  owner routes, watchdog public-call routing and the compiled-order helper
  are retargeted; one stack-frame fixture hook additionally follows the
  internal JVM suffix through a helper, with assertions unchanged. Five
  Dart anchor changes and an added session-payload assertion are formatted;
  size baseline lowered. Evidence: p9/step1/ and p9/gate/. Full gate follows.

- 2026-10-08 — phase 9 gate complete on `4b3ca5d87`: checker 2359
  declarations / zero differences; all 182 self-tests and historical p1–p8
  manifests pass; 36 frozen earlier destinations, 29 initializer proofs,
  five compiled receiver sites (virtual finish / inherited findViewById),
  two Runnable receivers and fifteen in-place teardown statements verified.
  JVM 810 = 809 pass + the same original focus failure, exact p9-step0b
  comparison. Three 512 MiB full-run heap failures were discarded; both
  original + pre-move tests and extracted trees complete with the same
  evidence-only 1024 MiB test heap and retain all 810 statuses. No repository
  build configuration or assertions changed; heap diagnostics, matched
  baseline/flags and raw failed runs are archived. Lint exactly retains 1352
  issues (253 errors / 1099 warnings; 175 unsafe opt-ins), Kotlin five warnings
  and Flutter analyze 1758 diagnostics. Release APK builds; six classes and
  197 members retain R8/DEX identities. Decoder pending-environment, directly
  verified unchanged from phase 1 (all three library hashes and nine missing
  decoders / three filters). Full Flutter suite: 12,855 identities, exact
  phase-8 status comparison (12,794 success / 13 failures / 28 errors /
  20 skipped); clean tested tree. Protected inputs / manifests unchanged, original worktree
  removed; no device interaction, install or push. Evidence: p9/gate/ and
  junit/p9-gate/. **STOPPED after phase 9**; no next-phase work or independent
  self-review performed.
- 2026-10-08 — phase 9 post-implementation reviews of `fbc53a10d..4226d658b`.
  Claude's 18-mutation sample 14/18; survivors k04/k09/k10/k12 (focus guard,
  controls-gated badge, progress restart on commit, resolution-token bump on
  failure) closed in 0b. Independent Codex review (fresh session): **No P1s,
  no P2/P3**; `finish()` compiled `invokevirtual`, 15 teardown statements in
  order between the final snapshot and `sendFinished`, VOD/TV exhaustion as
  characterized, live retry/player reads; the 1 GB heap override was
  evidence-only (committed build config unchanged). Activity 13,937 → 13320.
  Decoder verification remains pending-environment. Phase 9 complete; merged.
- 2026-10-08 — phase 10 design round 1 (Codex): **No P1s**; P2s folded
  (auditor extension for 18 `runOnUiThread` + 10 lifecycle getters; PikPak
  virtual-clock instrumentation with 10/22/36/54/80/108 s + 109.5 s pins;
  paired inline/queued reply timing cases). Phase 10 design approved.

- 2026-10-08 — **Phase 10 step T complete** on original `8a4d40d1c`:
  re-measured 29 subtrees, 176 moved substitutions, 27 caller edits in 13
  declarations and 17 computed Host re-points (20 edits) in three whole-property
  patched rows. Complete three-sibling extraction fixture passes and compiles;
  32 original/fixture bytecode receiver pins pass (TextView constructor, two
  Toasts, findViewById, eighteen runOnUiThread calls, ten lifecycle getters).
  Four initializer proofs, four Runnable self receivers, five slot-anchored
  additions including activity-owned readiness getters; all 37 earlier files
  frozen at the merge with an empty whitelist. Original self-comparison: 2,309
  declarations, zero differences. All 219 checker/auditor self-tests pass,
  including historical phase 1–9 suites and phase-10 negatives. Evidence p10/;
  no production move, branch change, protected-input change or device action.

- 2026-10-08 — **Phase 10 step T constructor controls strengthened.**
  The compiled phase-10 audit fixture now selects a TextView constructor,
  rejects a changed constructor overload, and rejects missing/wrong constructor
  opcode pins. All fourteen current phase-10 audit cases pass. Together with
  the unchanged 208 historical/extraction cases from the complete run, all
  222 unique checker/auditor cases are validated; logs and identity union in
  p10/checker-self-test-summary.json. Production manifest and its 32 compiled
  receiver sites are unchanged. No production moves.

- 2026-10-08 — **Phase 10 step 0 complete before production moves.**
  Seventy-nine original-code cases (pill 7, PikPak 25, episode fetch 27,
  fetch-more/addon 20), each with a named assertion-killed mutation on
  `8a4d40d1c`. PikPak virtual clock pins 10/22/36/54/80/108 s and 109.5 s;
  paired inline/worker replies pin UI-time locks, stale/continuation checks,
  live adjacent payload/index reads, unguarded notImplemented and deferred
  fetch-more finishing checks. Three isolated fixture strengthenings remove
  teardown/unchecked-access noise and isolate the default argument; only
  accepted assertion proofs count. Mutation table appended to deps; raw logs,
  XML, definitions, fixture versions and owner rescan under p10/.
  Clean `baseline-8a4d40d1c`: 810 = 809 pass + known focus failure, clean tree.
  Final `p10-step0`: 889 = 888 pass + same failure; additions-only comparison,
  79 passing additions and no missing/new failing/skipped identity. Matching
  evidence-only 1024 MiB workers, JBR 21.0.10; repository build settings unchanged.
  Original lint: 1,352 issues (253 errors, 1,099 warnings, 175 unsafe opt-ins),
  archived for the later gate. Fifteen reflected names / 77 literal sites
  rescanned; future internal fetch/default helpers will route through typed
  Kotlin calls, with equal assertions and no visibility expansion.
  Protected inputs and production bytes unchanged; original worktree removed.
  **STOPPED before phase-10 production moves.**

- 2026-10-08 — **Phase 10 step 0b complete on original `8a4d40d1c`.**
  Fifteen real-renderer/overlay cases close the loading refresh gap and sweep
  every moved fetch UI refresh; all twenty targeted original mutations fail
  on named assertions. Exact Claude l13 rerun is killed against all 94 phase-10
  cases; original control passes all 94. Invalid l10 remains excluded.
  `p10-step0b`: 904 = 903 pass + unchanged known focus failure; comparison
  against `p10-step0` permits exactly 15 passing additions. Matching 1024 MiB
  worker, unchanged production/protected inputs. Evidence `p10/step0b/`;
  mutation table appended to deps. No production move or device action.

- 2026-10-08 — **Phase 10 step 1 production moves complete.**
  Three sibling controllers at original slots: status pill 81 lines, retry 249,
  source fetch 431; Activity 13,320 → 12,717, size ratchet lowered. Four inert
  proofs and activity-owned readiness getters retained; three whole-property
  patches apply 17 Host re-points, callers and lifecycle statements stay in
  place. Twenty reflected owner routes plus typed internal/default dispatch,
  watchdog/shuffle helper retargets and the equal Dart candidate-count anchor;
  every Kotlin assertion unchanged. Checker classifies all 2,309 declarations
  with zero differences; all 115 focused JVM cases pass. Gate follows.

- 2026-10-08 — **Phase 10 gate complete; STOPPED.**
  Tested clean move `de9fadaca`: 2,309 declarations/zero diffs, all 222
  checker/auditor self-tests, historical phases 1–9 and 37 frozen earlier
  files pass. All 32 compiled receiver pins, four initializer proofs, four
  Runnable selves and teardown order preserved. JVM `p10-gate` vs
  `p10-step0b`: exact 904 statuses (903 pass + known focus failure), matched
  1024 MiB worker. Five production warnings unchanged; lint exact 1,352
  issues after refreshing only the stale derived Maven index from a clean
  original rerun (initial rejected reports retained, no normalization or
  build configuration changes). Release APK succeeds; R8/DEX 16 classes,
  223 members and all three Hosts preserve identity. Decoder remains
  pending-environment with phase-1/9 identical libraries and gaps.
  Full Flutter vs phase-9 gate: exact 12,855 statuses (12,794 success,
  13 failure, 28 error, 20 skipped); 45 affected source tests and 1,758
  analyzer diagnostics unchanged. Sizes 81/249/431, Activity 12,717.
  Retarget assertions preserved, protected inputs unchanged, detached
  evidence worktree removed. Evidence `p10/gate/`; no push, device,
  emulator, bug fix or self independent review. Stopped for Claude review.
- 2026-10-08 — phase 10 post-implementation reviews of `91882d41b..009808f5d`.
  Claude's 18-mutation sample: 16 killed, l10 invalid (compile error),
  survivor l13 (unified-menu re-render on fetch-more start) closed in 0b.
  Independent Codex review (fresh session): **No P1s, no P2/P3**; single
  retry-ID owner with live gate/switcher reads, borrowed pill handler,
  callback timing and lifecycle order preserved; Maven index refresh touched
  derived metadata only. Activity 13,320 → 12,717. Decoder verification
  remains pending-environment. Phase 10 complete; merged.
- 2026-10-08 — phase 11 design round 1 (Codex): **No P1s**; P2s folded
  (receiver-lambda exclusion audit; production bootstrap/callback-routed
  step 0 and the corrected key matrix; asymmetric stale-reply cleanup
  contract with independently varied guards). Phase 11 design approved.

- 2026-10-08 — phase 11 step T tooling prepared on `refactor/tvplayer-p11`.
  Re-measured clean original `00c60870e`: Activity 12,717 lines, 2,295 PSI
  declarations; all-retained self-comparison zero differences. Draft manifest:
  92 moved members, one 48-field owner, eager fieldless pager/navigator,
  47 initializer proofs, 224 cross-file references (four further name hits
  are unchanged return labels), 132 Host substitutions, 134 Activity token
  re-points plus the two eight/four Host-property patches. Extraction fixture
  compiles (425/524/431 lines); all 13 receiver sites retain pinned JVM
  dispatch. Historical 222 checker cases pass; final phase-11 38 cases pass,
  including every omitted initializer proof and receiver misclassification
  negatives. Initial four draft fixture-harness failures were corrected and
  rerun; raw logs retained. All 40 earlier destination files remain frozen.
  **Pending design clarification:** the plan names an `EditText.apply`
  receiver-lambda `this`, but original line 10001 passes Activity `this` to
  the constructor outside the lambda. Only the two entry-owned `this.index`
  expressions are receiver-lambda exclusions. Source/bytecode evidence and
  the proposed correct distinction are in the deps report and
  `p11/receiver-design-finding.json`; clarification requested before declaring
  step T complete and continuing the ordered characterization step.
  Clean original JVM baseline `baseline-00c60870e`: 904 identities, 903 pass,
  unchanged source-browser focus failure. Original lint archive: 1,352 issues
  (253 errors, 1,099 warnings, 175 unsafe opt-ins). No new JVM tests, mutations
  or `p11-step0` run yet. No production edits, lockfile or ProGuard changes;
  no push or device interaction. Evidence under `p11/` and `junit/`.
- 2026-10-08 — step T stopped on a design mismatch (correctly): only two
  receiver-lambda `this` exclusions exist; `EditText(this)` passes the activity
  (source + bytecode evidence in the deps report). Plan corrected (Claude
  approved): two exclusions; the `EditText(this)` site is substituted and
  constructor-audited. Step 0 resumes.

- 2026-10-08 — phase 11 step T completed after Claude approved the receiver
  finding (`6deb8cf7e`). Manifest retains exactly two entry-owned `this.index`
  exclusions. A linked compiled constructor fixture substitutes Activity
  `this` with injected `activity`, preserving `EditText(Context)` and
  `invokespecial`; omitted/misclassified exclusions, omitted constructor audit
  and changed constructor are rejected. It supplements the 13 production
  receiver pins without moving the retained numeric dialog. Historical 222
  cases and the prior 38 extraction cases remain passing; six new constructor
  provenance/audit cases pass (266 unique checker cases). The 47 initializer
  proofs and 40 frozen destinations are unchanged. No production moves.

- 2026-10-08 — **Phase 11 Step 0 complete** on original `00c60870e`: 134 new
  characterization tests pass through real live/VOD bootstrap and installed
  callbacks. Every new test has an original named assertion proof; all 162
  mutations are killed, including retained caller wiring and asymmetric
  success/error/notImplemented stale-reply cleanup for inline/queued timing.
  Real remote-key matrix, paging boundaries, number entry, outgoing checkpoint,
  startup memory, Start Over, borrowed-handler trim/archive retry and teardown
  are pinned. Mutation table appended to the deps report; raw evidence `p11/`.
  Clean `baseline-00c60870e` has 904 identities (903 pass, unchanged focus
  failure); `p11-step0` has 1,038 (1,037 pass, same failure), no skips:
  134 passing additions only, stable run fingerprint, matched 1 GiB/JBR 21.0.10.
  Original lint remains archived: 1,352 issues (253 errors/1,099 warnings,
  175 unsafe opt-ins). Reflection rescan finds 67 routes (37 fields/30 funcs);
  29 additional reflected functions need public unmangled members at Step 1.
  Step T commit `d83360125`: exactly two receiver-lambda exclusions, Context
  constructor audit and negatives; 266 unique checker cases, original 2,295
  declarations classified with zero differences, 47 initializer proofs and
  40 frozen earlier destinations. Detached original removed. Production,
  lockfile and ProGuard unchanged; no push, branch switch or device/emulator.
  **STOPPED before production moves**, awaiting Claude's separate sample/review.

- 2026-10-09 — **Phase 11 Step 0b complete; STOPPED before moves.**
  Claude's exact ten survivors (m02/m04/m05/m06/m08/m09/m11/m13/m14/m16)
  are assertion-killed on original `00c60870e`, each against all 230 phase-11
  cases; no compile/crash proofs. The original final cohort passes 230/230.
  Added 96 tests, each with an isolated named mutation proof; 541 distinct
  systematic original mutants are assertion-killed (542 accepted runs) across
  all 44 moved functions. Five
  named proofs repeated after final refinements; rejected discovery attempts
  retained separately. PSI-based per-function matrix inventories all 800 sites
  (199 writes/416 calls/105 ifs/77 returns/two whens/one loop), distinguishing
  direct proofs from nested value/guard groups. Mutation tables and the complete
  matrix are appended to the deps report; raw evidence `p11/step0b/`.
  JVM `p11-step0b`: 1,134 identities (1,133 pass, same known focus failure,
  no skips), all 1,038 `p11-step0` statuses retained, 96 passing additions only;
  complete stable run, matched 1 GiB/JBR 21.0.10. Original lint archive reused.
  Final reflection rescan: 89 routes, 45 fields/all 44 functions, 908 literal
  sites/779 direct selectors; 43 further functions require public unmangled
  members plus matching manifest/fixture pins when Step 1 is authorized.
  Detached original removed; production, lockfile and ProGuard unchanged.
  No production moves, gate, push, branch switch, device/emulator, bug fix or
  self independent review. Claude's second independent sample is next.

- 2026-10-09 — **Phase 11 Step 0c complete before moves.** Claude exact n01
  is assertion-killed on original `00c60870e` against all 233 phase-11 cases;
  unchanged-original control passes 233/233. Three added tests sweep all three
  nullable server-message Toasts, including null/default, empty text and paired
  inline/queued delivery. All nine named original mutation proofs pass. n13/n16
  are recorded as equivalent because the page-request entry point supplies the
  same offset clamp and in-flight guard. Stable matched-heap JVM `p11-step0c`:
  1,137 identities (1,136 pass, same known focus failure); all 1,134 prior
  statuses retained, three passing additions only. Mutation table and sweep are
  appended to the deps report; raw evidence `p11/step0c/`,
  `junit/p11-step0c/`. Final rescan: 89 routes, 45 fields/44 functions,
  913 quoted sites/784 direct selectors. Production/protected inputs unchanged;
  detached original removed after proofs. Approved Step 1 moves and gate follow.

- 2026-10-09 — **Phase 11 Step 1 production moves complete.** Materialized
  all 92 manifest rows into the guide owner (48 core fields), fieldless pager
  and fieldless navigator (425/524/431 lines); activity 12,717 → 11,458,
  size baseline lowered with `--update`. One slot-anchored eager controller,
  computed qualified Host forwarders, whole-property Start Over/banner patches,
  retained patched `initIptvMode`, and in-place teardown patches match the
  manifest. Rescan supplies 89 reflection owner routes; 43 additional public
  function visibility pins join the originally public install function, without
  changing any characterization assertion. No watchdog or Dart moved-member
  selectors need a further retarget. All 233 phase-11 characterizations pass.
  Checker: 2,295 declarations classified, zero differences; p1–p10 historical
  checks and 40 frozen earlier files pass. Compiled audit pins all 13 production
  receivers, two receiver-lambda exclusions remain; five original Kotlin warnings,
  47 initializer proofs and full lifecycle order are unchanged. Historical and
  current checker self-tests and the full clean-tree gate follow. Evidence
  `p11/step1/`, `p11/gate/`. No bug fix, dependency or ProGuard change.

- 2026-10-09 — **Phase 11 gate complete on `74c99a786`; STOPPED.**
  Checker: 2,295 original declarations classified, zero differences; all 266
  self-tests (including complete phase-11 extraction and negatives), p1–p10
  historical merge checks and 40 frozen earlier destination files pass. All 13
  production receiver pins, exactly two entry-lambda exclusions, the retained
  EditText(Context) site and its compiled substituted constructor fixture pass.
  All 47 initializer proofs, eager fieldless construction, protected inputs,
  unchanged assertion bytes and full lifecycle teardown order are verified.
  Clean matched-heap JVM `p11-gate` exactly matches `p11-step0c`: 1,137
  identities (1,136 pass, same known source-browser focus failure), no skips;
  all 233 phase-11 characterizations pass. All five Kotlin warning identities
  remain. Lint exactly matches archived original `00c60870e`: 1,352 issues,
  253 errors/1,099 warnings, 175 opt-in errors. Analyzer matches all 1,758
  phase-10 diagnostics. Release APK succeeds without installation; R8/DEX
  preserves every new controller/Host/anonymous class and member (8 classes,
  303 members, three negative controls). Decoder check remains
  **pending-environment**: output, missing decoder/filter manifests and all three
  native hashes are identical to phase 10 and phase 1, without a workaround.
  Full clean-tree Flutter suite via `suite_evidence.py` exactly matches all
  12,855 phase-10 identity/status pairs (12,794 success, 13 failure, 28 error,
  20 skipped; 1,232 suites); affected Dart checks match all 45 prior outcomes.
  Step 0c adds three passing JVM cases, nine named original proofs and the exact
  all-233 n01 kill; n13/n16 are documented equivalent. Evidence `p11/step0c/`,
  `p11/step1/`, `p11/gate/`, `junit/p11-step0c/`, `junit/p11-gate/`.
  Public reflection pins were updated from the Step-0b rescan; only the shared
  helper routes changed, and no Dart/watchdog selector retarget was necessary.
  Matched 1 GiB test workers remain an evidence-only pre-existing harness
  exception. Detached original removed; lockfile and ProGuard unchanged.
  No bug fix, push, branch switch, device/emulator, or self independent review.
  **STOPPED after phase 11**; Claude reviews separately.
- 2026-10-09 — phase 11 post-implementation reviews of `4c31e5e1c..90ede8bc7`.
  Claude's first independent sample was weak for step 0 (8/18 killed); a
  thorough 0b followed (96 tests, 541 systematic mutations, per-function
  coverage matrix over 44 functions / 800 sites); Claude's **second**
  independent sample then 13/16 (2 equivalent: n13/n16; n01 closed in 0c).
  Independent Codex review (fresh session): **No P1s, no P2/P3**; one owner
  for all 48 core fields, fieldless collaborators, stale-reply asymmetry,
  paging/wrapping, switch side effects, key routing and teardown preserved.
  Activity 12,717 → 11458. Decoder verification remains pending-environment.
  Phase 11 complete; merged. **Lesson:** a first-sample kill rate below ~75 %
  triggers a systematic statement-level sweep and a second independent sample
  before moves.
- 2026-10-09 — phase 12 design round 1 (Codex): **No P1s**; P2s folded
  (constructor-receiver transformation with inner-`this` preservation;
  `resources`/`currentFocus` getter audit; 20 reflective accesses / 5 names;
  now/next fetch + enrichment characterization incl. after-destroy behaviour).
  Phase 12 design approved.

- 2026-10-09 — **Phase 12 Step T complete; no production moves.** Re-measured
  `b870a16b1`: 39 selected members, 294 exact substitutions, 20 initializer
  proofs, 13-member computed Host, eager fieldless overlay/pickers and all
  seven whole-declaration patches (26 activity + five Host re-points). Original
  self-comparison classifies all 2,139 declarations with zero differences; all
  43 earlier destinations are frozen. The full production-config extraction
  fixture compiles and passes all 77 before/after receiver pins (24 context /
  constructor + 53 inherited), including both FragmentActivity Glide overloads.
  The constructor-receiver rule permits exactly the reviewed EditText Activity
  argument while preserving the single inner tint receiver; resources/currentFocus
  getters have owner–descriptor–opcode pins and compiled negatives. All **298**
  dispatcher self-tests pass (266 historical + 32 phase-12), including complete
  extraction, all 20 missing-proof negatives and phase-11 at its merge. Evidence
  `p12/`, including compiled original/extraction archives and raw self-test logs.
  Production, lockfile and ProGuard remain unchanged. Step 0 follows.

- 2026-10-09 — **Phase 12 Step 0 complete; stopped before production moves.**
  Added **153** original characterization tests in 18 behavior classes plus
  the bootstrap fixture: four separately cached guide styles, real adapter
  and key/IME callbacks, pickers, jump dialog, EPG pane/header, Glide lifecycle
  and request/model/listener/scaling, paired replies, exact freshness, the
  45 s watchdog and 60 s retry including the existing after-destroy behavior.
  Every new test has an original named assertion mutation proof. The systematic
  sweep covers all 18 moved functions and **793** PSI sites; **540 accepted
  assertion-killed proof records** across the final archives, three equivalent
  removals explained, compile/crash-only variants excluded. The per-function
  matrix and 153-row mutation table are in the dependency report; raw patches,
  logs, XML and immutable fixture versions are in `p12/step0/`. Detached
  original `b870a16b1` worktree removed after restoring and archiving.
  Clean JVM `baseline-b870a16b1`: **1,137** identities, 1,136 passes and the
  existing focus failure. Final quiet `p12-step0`: **1,290** identities,
  1,289 passes and the same failure, **153 passing additions only**, no
  removals/status changes/skips, stable fingerprint. A concurrent run's
  unchanged live-clock guide failure was rejected and retained; isolated and
  quiet full verification pass without test/allowlist edits. Original lint:
  **1,352** identities (253 errors, 1,099 warnings), archived for the gate.
  Rescan: **250** quoted references across **39** routes (21 fields, 18
  functions); all moved functions have public unmangled members in the
  internal destination classes. Five additional visibility substitutions
  raise the manifest total from 294 to **299**; the regenerated future fixture
  compiles and preserves all **77** receiver pins, **20** initializer proofs
  and **43** earlier files. All **298** checker self-tests pass; original
  self-comparison classifies **2,139** declarations with zero differences.
  Production, prior tests/helpers, lockfile and ProGuard are unchanged; no
  push, branch switch or device interaction. Claude's independent sample,
  moves, helper retargets and production gates remain for their next steps.


- 2026-10-09 — **Phase 12 Step 0b complete before moves.** Ten additional
  original-surface tests close URL-prefix, deferred-current and numeric-input
  boundary gaps. All ten named original mutation proofs fail assertions; exact
  Claude o03/o06/o12 reruns against all **163** phase-12 tests are assertion-killed,
  with a passing 163-test control and matched 1 GiB heap. Related guard sweep
  and mutation rows appended to the dependency report. Preliminary nullable
  test-error crashes are rejected, archived and replaced by null-safe assertions.
  Quiet `p12-step0b`: **1,300** identities, 1,299 passes and the unchanged focus
  failure; every prior 1,290 status is retained with **ten passing additions
  only**, no missing/skipped/changed identities and a stable tree fingerprint.
  Evidence `p12/step0b/`, `junit/p12-step0b/`. Detached original removed;
  production, manifest, old tests/helpers, lockfile and ProGuard unchanged.
  Approved Step 1 and gate follow.


- 2026-10-09 — **Phase 12 Step 1 moves complete.** Materialized the approved
  manifest exactly into the chrome owner and eager fieldless overlay/pickers
  (**394/469/416** lines), with the owner at the first removed field slot.
  Activity **11,458 → 10,297**; size baseline lowered with `--update`.
  Seven whole-declaration patches include the phase-11 Host span and in-place
  teardown. Shared test-helper owner map gains all **39** rescanned routes;
  all prior/new test assertions and Dart files remain byte-identical. The
  helper's 813-line scoped exception and pre-next-route split milestone are
  recorded explicitly; no production exception. All **163** phase-12
  characterizations pass. Current checker: **2,139** original declarations
  classified, zero differences; all **77** compiled receiver pins, **20**
  initializer proofs, lifecycle order, **43** earlier destination bytes and
  protected inputs pass. Forced compile preserves all five warning identities.
  Evidence `p12/step1/`, `p12/gate/`. Full integration gate follows on the
  committed tree; no self independent review, bug fix or device interaction.


- 2026-10-09 — **Phase 12 gate complete on `3d389848f`; decoder
  pending-environment. STOPPED after Phase 12.** Step 0b `94f018032` adds ten
  passing tests, ten named original assertion proofs and kills exact Claude
  o03/o06/o12 against all 163 phase-12 cases; o08 remains invalid/excluded.
  Clean `p12-gate` exactly matches all **1,300** Step-0b identities/statuses
  (1,299 passes, unchanged focus failure), matched 1 GiB heap, no missing or
  new skips and a stable clean tree. Checker classifies **2,139** originals
  with zero differences; **298** self-tests and p1–p11 historical merge checks
  pass. All **43** prior destinations remain byte-identical to `b870a16b1`.
  Compiled audit **77/77** (24 constructor/context + 53 inherited, incl.
  resources/currentFocus getters and EditText inner-this preservation), **20**
  initializer proofs, full lifecycle/teardown order and exact test-retarget
  reversal pass; five compiler warning identities unchanged. Size gate passes
  at activity **10,297**, production **394/469/416**, with only the explicit
  **813**-line test-helper exception and pre-next-route split milestone.
  Lint exactly matches all **1,352** original identities (253 errors,
  1,099 warnings; 175 existing opt-in errors); analyzer **1,758** unchanged.
  Release APK succeeds; R8/DEX verifies **12 classes / 204 members**, including
  all new controllers/collaborators/Host/anonymous objects and the activity
  Host implementation, plus three mapping negative controls. Decoder failure
  output, all three native library hashes and missing decoder/filter manifest
  exactly match phase 1: pending-environment, no workaround. Affected Dart
  source tests match all **45** prior statuses; full Flutter suite via
  `suite_evidence.py` exactly matches all **12,855** phase-11 identities/statuses
  (12,794 success, 13 failure, 28 error, 20 skipped), same SDK/flags and stable
  clean committed tree. No Dart anchors changed. Evidence `p12/step0b/`,
  `p12/step1/`, `p12/gate/`, `junit/p12-step0b/`, `junit/p12-gate/`. Detached
  original removed; lockfile, ProGuard and earlier manifests unchanged.
  No push, branch switch, self independent review, device/emulator or bug fix.
- 2026-10-09 — phase 12 post-implementation reviews of `114731e76..25c66936c`.
  Claude's independent sample 12/15 valid kills (80 %; o08 pattern absent;
  two earlier invalid attempts caused by a test-list word-splitting bug in
  Claude's shell, discarded); survivors o03/o06/o12 closed in 0b.
  Independent Codex review (fresh session): **No P1s, no P2/P3**; the
  813-line `TvPlayerOriginalAccess.kt` helper exception accepted (39 routing
  rows, ratcheted, split before the next route is added — first item of
  phase 13). Activity 11,458 → 10,297. Decoder verification remains
  pending-environment. Phase 12 complete; merged.
- 2026-10-09 — phase 13 design round 1 (Codex): **No P1s**; P2s folded
  (getter + typed listener-exclusion auditor extensions; explicit async focus
  quirk cases); P3s: inventory totals corrected to 29 properties / 31
  functions / 3 view getters, router estimates per router (≈ 71 / ≈ 47).
  Phase 13 design approved.


- 2026-10-09 — **Phase 13 Step T complete; production unchanged.** First split
  the 813-line original-access test helper into the 325-line access fixture
  and 494-line immutable owner table; all 487 route entries and all other
  access code are byte-preserved, and the size exception is removed. Helper
  JVM verification retains all 1,300 phase-12 identities/statuses (1,299 pass,
  unchanged focus failure). Re-measured manifest at `315448a3c`: 60 members
  (29 properties / 31 functions), 31 activity patches in 15 declarations,
  seven Host re-points in six whole-property rows, 49 cross-qualifications,
  28 initializer proofs and 46 frozen earlier destinations. Original
  self-comparison classifies all 2,013 declarations with zero differences.
  Complete extraction fixture passes and compiles only in the detached
  original/evidence tree (586/327/398 lines). Audit pins all 23 receivers
  (eight constructor/context plus 15 inherited, incl. layoutInflater), the
  typed listener self binding and both bound guide-skin function references.
  Narrow negative-integer, reviewed enum and getter-only classifier forms
  reject their stated negatives. All 298 historical and 39 final phase-13
  self-tests pass; historical suites retain their own manifests. Evidence
  `p13/helper-split.json`, `p13/checker-self-tests.log`,
  `p13/phase13-final-self-tests.log`, `p13/overload-audit.json`.
  Step 0 follows on the original; no production move or owner-route addition.

- 2026-10-09 — **Phase 13 Step 0 complete; production unchanged.** Added 120
  characterization identities from real activity bootstrap, with seven separate
  controls-skin variants and installed adapter/key/focus/click callbacks. Pins
  layout/bindings, every tab style and visible string, guide artwork lifecycle,
  season/group filtering and refresh, default dispatch, focus boundaries,
  off-screen scroll requests, 50/100 ms ordering, recovery replacement/cancellation
  and delivery-time reads, the three original asynchronous quirks above, and
  seven compiled teardown statements plus live cleanup before the finished reply.
  The deterministic paused-looper fixture uses ViewRoot's own traversal entry
  point; rejected frame/setup experiments remain separate from accepted evidence.
  All 120 new tests have named assertion-failing mutation proofs on `315448a3c`.
  The systematic matrix covers all 31 moved functions and 723 PSI nodes
  (135 writes, 100 if, 14 when, 70 returns, five loops and 399 calls). All
  state/branch/effect obligations have a direct assertion proof or an explained
  equivalent deletion; nested reads link to their observed outputs. Additional
  sweep batches contain 462 runs / 412 assertion kills, with six explained
  equivalent deletions; compiler errors/crashes are never kills. All 25 final
  full-set reruns kill the earlier real survivors. Clean final controls pass
  131 selected tests; the 14 filtered clean-control cohorts pass as well.
  Matched 1 GiB JVM evidence: clean `baseline-315448a3c` has 1,300 identities
  (1,299 pass, unchanged SourceBrowser focus failure); `p13-step0` has 1,420
  (1,419 pass, same failure). Comparison proves 120 passing additions, zero
  missing identities and zero existing status changes, with stable fingerprints.
  Original lint archived: 1,352 issues (253 errors / 1,099 warnings, 175
  UnsafeOptInUsage); exit 1 is pre-existing, not a lint pass. Owner rescan finds
  59 reflected moved names, including dynamic bindings and both getter aliases;
  guideGridSpan is unreferenced. Public reflected functions/getters are already
  pinned in the manifest; no owner route is added before extraction. The
  teardown bytecode helper's receiver interpretation must retarget in Step 1
  while keeping its seven-event assertion unchanged.
  Evidence: `p13/step0/`, `p13/lint-original/`,
  `junit/baseline-315448a3c/`, `junit/p13-step0/`; mutation table and per-function
  matrix appended to the deps report. Original detached worktree removed.
  Helper-size exception remains resolved; lockfile, ProGuard and all production
  sources unchanged. No push, branch switch, device/emulator or bug fix.
  **Stopped before production moves; Claude's independent sample follows.**


- 2026-10-09 — **Phase 13 Step 1 moves complete.** Claude's sample kills all
  12 non-equivalent mutations against 120 phase-13 tests; q06 is equivalent
  because index 0 falls back to the same 0, recorded in the deps report and
  p13/claude-mutations/classification.json. No Step 0b required. Materialized
  the approved overlay owner, focus navigator and guide skin (586/327/398
  lines); activity 10,297 → 9,079, size baseline lowered with --update.
  Three playlist views stay behind computed Host getters; eager child
  construction, the original slot and seven in-place teardown statements
  are preserved. Owner map adds 59 name routes plus two getter aliases;
  bytecode-access helper recognizes the new setters/getters, keeping all
  test assertions byte-identical. All 120 characterizations pass with matched
  1 GiB workers. Checker classifies 2,013 originals with zero differences;
  historical p1–p12 checks, 46 frozen earlier destinations, 28 initializer
  proofs, full lifecycle order, 23 compiled receiver pins, the typed listener
  exclusion and both bound references pass. Five Kotlin warning identities
  unchanged. No Dart anchors needed; split helpers remain 325/555 lines.
  Evidence p13/step1/, p13/gate/. Full integration gate follows on the
  committed tree; no self independent review, bug fix or device interaction.


- 2026-10-09 — **Phase 13 native gate recorded on 031e3b83e; Flutter gate
  pending.** Clean p13-gate exactly matches all 1,420 p13-step0 identities
  (1,419 pass, the same pre-existing SourceBrowser focus failure), matched
  1 GiB heap, stable clean tree. Analyzer matches all 1,758 prior diagnostics.
  Release APK succeeds; R8/DEX verifies all 12 generated moved-slice classes
  and 177 members, including Host/anonymous classes and the activity Host
  implementation, with three mapping negative controls. Decoder output,
  three library hashes and missing-feature manifest match phase 1 exactly:
  pending-environment. Lint retains 1,352 issues (253 errors / 1,099 warnings,
  175 opt-in errors): 1,350 exact identities, plus two existing Overdraw
  warnings whose inferred-theme message changes from AppCompat to Holo for
  marquee/pulse. Cached lint 31.11.1 detector bytecode proves its Activity-only
  layout association and Holo fallback; unchanged manifest/layout hashes and
  the compiled inflater audit prove runtime ownership/theme are unchanged.
  Raw strict comparison remains archived as different; the exact two-pair
  correspondence check rejects message/location/additional-issue changes.
  No suppressions, checker relaxation or production fixes. Historical p1–p12
  checks pass; full historical checker self-tests are still running. Full
  Flutter comparison follows on a clean commit containing gate. Evidence
  p13/gate/ and junit/p13-gate/.


- 2026-10-09 — **Phase 13 gate complete on 83a1a41dd; decoder
  pending-environment. STOPPED after Phase 13.** Step 1 031e3b83e extracts
  the playlist owner / focus navigator / guide skin (586/327/398 lines);
  activity 10,297 → 9,079. All 120 characterizations pass with assertions
  unchanged. Claude's sample kills all 12 non-equivalent mutations; q06 is
  equivalent (index 0 returns the same fallback 0), recorded without Step 0b.
  Current checker classifies 2,013 originals with zero differences; all 337
  checker/auditor self-tests and p1–p12 historical merge checks pass. All 46
  earlier destination files are byte-identical to 315448a3c. Compiled audit
  preserves 23 receiver pins (8 context/constructors incl. two Glide
  FragmentActivity calls, 15 inherited incl. getLayoutInflater), the typed
  OnGlobalLayoutListener exclusion and both guideSkinBind references.
  All 28 initializer proofs, eager nested construction, original property
  slot, full lifecycle order and the seven-event runtime/bytecode teardown
  assertion pass. Shared owner-map retargets and bytecode-access changes are
  exact; every assertion and all Dart files remain unchanged. Size gate
  passes with no new exception; split helpers remain 325/555 lines. Five
  Kotlin warning identities and 1,758 analyzer diagnostics are unchanged.
  Clean p13-gate exactly matches all 1,420 p13-step0 identities/statuses:
  1,419 passes, the same pre-existing SourceBrowser focus failure, matched
  1 GiB heap, no missing/new skips and a stable clean tree. Lint retains
  1,352 issues (253 errors / 1,099 warnings; 175 opt-in errors): 1,350 exact
  identities and two documented Overdraw inferred-theme correspondences.
  Raw message differences remain archived; detector bytecode, unchanged
  manifest/layout hashes, audited inflater ownership and three correspondence
  negative controls explain the delta without suppressions or fixes.
  Release APK succeeds; R8/DEX verifies 12 classes / 177 members, including
  all new owners/Host/anonymous classes and the activity Host implementation,
  with three mapping negative controls. Decoder failure output, all three
  library hashes and missing-feature manifest exactly match phase 1:
  pending-environment. Affected Dart source tests match all 45 prior statuses;
  full quiet Flutter suite via suite_evidence.py on clean gate commit
  83a1a41dd exactly matches all 12,855 phase-12 identities/statuses (12,794
  success, 13 failure, 28 error, 20 skipped), same SDK/flags and stable tree.
  Evidence p13/step1/, p13/gate/, junit/p13-gate/. Lockfile, ProGuard,
  earlier manifests and destinations unchanged. No push, branch switch,
  self independent review, device/emulator or bug fix. Phase 14 not started.
- 2026-10-09 — phase 13 post-implementation reviews of `f7d1541bf..2f3a82759`.
  Claude's independent sample 12/13 killed; q06 equivalent (index 0 falls back
  to the same 0) — no 0b needed. Independent Codex review (fresh session):
  **No P1s, no P2/P3**; the two lint "inferred theme" message changes are
  static-analysis only (lint's Overdraw detector associates layouts with
  Activity subclasses; moved inflation lost that association → Holo
  fallback), while runtime inflation uses the same injected activity and the
  unchanged AppCompat manifest theme. Test helper split (325/494), its size
  exception removed. Activity 10,297 → 9,079. Decoder verification remains
  pending-environment. Phase 13 complete; merged.
- 2026-10-09 — phase 14 design round 1 (Codex): **No P1s**; P2s folded
  (correct post-destroy late-metadata outcome; endpoint-specific fake-channel
  contracts incl. worker-thread catalog reply; ListView constructor-receiver
  transformation + KtSuperTypeCallEntry audit); P3 `emptyList()` wording.
  Phase 14 design approved.

- 2026-10-09 — phase 14 Step T complete: re-measured `82b16832c`; 43-member
  production-config fixture, 134 substitutions, 20 initializer proofs and 49
  frozen earlier destinations. Corrected Host counts to 13 tokens / 11
  forwarders in four whole-property patched rows (deps Step T explains).
  Original self-comparison: 1,850 declarations, zero differences. All 378
  checker self-tests pass, including every historical suite; compiled complete
  fixture passes 25 receiver calls plus six preserved bindings. Typed stdlib
  emptyList validation, ListView inner receiver and ArrayAdapter super-call
  metadata/pins are covered by positives and stated-reason negatives. Evidence
  `p14/`; production unchanged. Step 0 next; no production moves.

- 2026-10-09 — **Phase 14 Step 0 complete; STOPPED before production moves.**
  All three prerequisite harnesses pass on original 82b16832c, including the
  real IO/retry/Main ladder, endpoint-specific inline/queued/worker replies
  and shown/measured dialog callbacks. All 172 new tests pass. Systematic
  PSI sweep covers 724 nodes in every one of the 22 moved functions
  (106 writes, 66 if, five when, 48 returns, six loops, 493 calls). Every
  required state/branch/loop/direct-call node is resolved: 364 assertion
  proofs and three documented Android setter equivalents. Raw sweep has
  465 runs, 396 assertion kills; compile-invalid/crash-only/draft variants
  receive no kill credit. Every new named test has an assertion witness.
  Matrix and test→mutation→assertion table are appended to the deps report;
  exact patches, immutable fixtures, logs/XML and equivalence bytecode are
  archived under p14/step0/. Corrected late-metadata outcome is pinned:
  cache write, zero addons, discovery true/loading false/no jobs after destroy.
  Running-fetch cancellation publication and older catalog overwrite remain
  unchanged. Clean baseline-82b16832c has 1,420 identities; p14-step0 has
  1,592 (1,591 pass, same known SourceBrowser focus failure, no skips):
  172 passing additions only, stable fingerprints, matched 1 GiB heap/JBR.
  Original lint archives 1,352 issues (253 errors/1,099 warnings; 175 opt-in)
  for the later comparison. Reflection rescan identifies 41 future routes;
  borrowed scope/service/readiness stay Activity-owned. Step T is 1ce352474:
  378 self-tests, zero original differences, 20 initializer proofs and
  25 receiver pins plus six preserved bindings. Detached original removed;
  file-size/diff checks pass. Production, old assertions, lockfile and
  ProGuard unchanged; no moves, gate, push, branch switch, device or bug fix.
  Claude's independent sample and Step 1 remain for the next checkpoint.

- 2026-10-09 — **Phase 14 Step 0b complete.** Claude r03/r16 are now
  assertion-killed on original 82b16832c against all 186 characterizations;
  r17 is equivalent (en/eng share canonical English matching), proved by
  original bytecode execution over 13,417 tags and the full r17 rerun.
  Fourteen new boundary tests each have named assertion witnesses; the
  type/null/empty/language sweep kills 15 of 16 variants, with only r17
  equivalent. The recording suspend-call seam preserves real IO/retries/Main.
  p14-step0b has 1,606 identities (1,605 pass, same known focus failure):
  fourteen passing additions only vs p14-step0, stable matched 1 GiB inputs.
  Matrix/table and raw evidence under p14/step0b/. No production or protected
  input changes. Step 1 follows under the approved manifest.

- 2026-10-09 — **Phase 14 Step 1 moves complete.** The approved 43-member
  extraction produces the 710-line subtitle-source owner and eager fieldless
  495-line dialogs collaborator; activity 9,079 → 7,982, size ratchet lowered.
  Borrowed scope/service/readiness remain activity-owned. All 134 substitutions,
  four Host-property rows (11 forwarders / 13 tokens) and in-place destruction
  patch match the manifest. Forty-one reflection routes are added only in the
  shared helper; all existing assertions and Dart anchors remain unchanged.
  Focused characterizations 186/186 pass. Checker: 1,850 declarations, zero
  differences; historical p1–p13, 49 frozen destinations, 20 initializer
  proofs, teardown order, 25 compiled receiver sites plus six preserved
  bindings and all five Kotlin warning identities pass. Full checker suites
  and clean JVM/lint/release/Flutter gates follow on this gate commit.


- 2026-10-09 — **Phase 14 gate complete on a85ae8f28; decoder
  pending-environment. STOPPED after Phase 14.** Step 0b f576c6f68 adds
  fourteen original-surface tests, every one assertion-proved; sweep 15/16
  killed, r17 equivalent. Claude r03/r16 fail assertions on original 82b16832c;
  r17 passes all 186 and original LanguageMapper bytecode produces identical
  en/eng outcomes over 13,417 tags. Step 1 a85ae8f28 extracts the 710-line
  subtitle-source owner and eager, fieldless 495-line dialogs collaborator;
  activity 9,079 → 7,982. Scope/service/readiness stay activity-owned and
  borrowed. Forty-one owner-map routes are the only test retarget; assertions
  and Dart files remain byte-identical. Current checker classifies 1,850
  original declarations with zero differences. All 378 checker/auditor
  self-tests and historical p1–p13 merge checks pass. Forty-nine earlier
  destinations are byte-identical to 82b16832c; twenty initializer proofs,
  eager construction, slot anchoring, full lifecycle/teardown order and the
  runtime cancellation → flat-list clear → service-null assertion pass.
  Compiled audit pins 25 receiver calls and six preserved bindings, including
  ListView Context construction with inner this.adapter preserved and the
  ArrayAdapter super-constructor. Five Kotlin warnings and 1,758 analyzer
  diagnostics are unchanged. Clean p14-gate exactly matches all 1,606
  p14-step0b identities/statuses: 1,605 pass, same known SourceBrowser focus
  failure, no missing/new skips, stable input, matched evidence-only 1 GiB heap.
  Lint exactly retains all 1,352 issue identities (253 errors/1,099 warnings;
  175 opt-in errors), with moved locations mapped back to original symbols;
  no additions/removals/suppressions. Release APK succeeds. R8/DEX checks all
  eight generated classes and 162 members, including Host, activity Host
  implementation and anonymous/coroutine classes, with three negative
  controls. Decoder failure output/native hashes/missing-feature manifest
  remain identical to phase 1: pending-environment. Affected Dart source
  tests match all 45 prior statuses. Full quiet Flutter suite via
  suite_evidence.py on clean gate commit a85ae8f28 exactly matches all 12,855
  phase-13 identities/statuses (12,794 success, 13 failure, 28 error, 20
  skipped), same SDK/flags and stable tree. Size baseline updated; no new
  exception. Evidence p14/step0b/, p14/step1/, p14/gate/ and junit/p14-gate/.
  Lockfile, ProGuard and earlier manifests/destinations remain unchanged.
  No push, branch switch, self independent review, device/emulator or bug fix.
  Phase 15 not started.
- 2026-10-09 — phase 14 post-implementation reviews of `66ddf4d27..3c09a7a38`.
  Claude's independent sample 14/17 (82 %); r03/r16 closed in 0b; r17
  ("en" vs "eng" default) equivalent — both canonicalize to English
  (13,417 language-tag checks, independently re-run by the reviewer).
  Independent Codex review (fresh session): **No P1s, no P2/P3**; single
  ownership of 21 fields, borrowed scope/service/readiness untouched,
  teardown cancellation → flat-list clear → service null order unchanged,
  `this.adapter` binding preserved. Activity 9,079 → 7,982. Decoder
  verification remains pending-environment. Phase 14 complete; merged.
- 2026-10-09 — phase 15 design round 1 (Codex): P1 folded (styler's injected
  owner named `controlsDock` to avoid the `dock` local/parameter collision at
  14 of 48 sites; shadowing negative); P2s folded (per-site cast
  presence/absence pins for the 23 findViewById sites; LoudnessEnhancer
  failure injection pinned as-is); P3 patch count 41.
- 2026-10-09 — phase 15 design round 2 (Codex): **No P1s**, no further collisions or findings. Phase 15 design approved.
- 2026-10-09 — phase 15 Step T complete. Manifest re-measured at ce3ddfb06:
  1,730 original declarations classified, 68 moved subtrees, zero original
  self-comparison differences; two slots and 31 initializer proofs. Complete
  production-config fixture passes and compiles (dock 554, styler 294,
  display 438 lines). Audit passes 17 receiver/getter pins, 23 shared-view
  binds and resize-array constant inlining. Measured cast correction:
  12 CHECKCAST / 11 no-cast, including three typed TextView[] stores.
  All 419 checker cases verified through the full run and 42 corrected
  rechecks; historical phase-6 exception behavior restored and retained.
  Phase-14 historical comparison and all 51 frozen destinations pass.
  Evidence p15/; 68 protected paths byte-identical to the merge. No
  production moves, lockfile/ProGuard edits, new size exception or bug fix.
  Step 0 is next; LoudnessEnhancer prerequisite must run first.

- 2026-10-09 — phase 15 Step 0 complete. Loudness prerequisite 7/7 on
  ce3ddfb06, including constructor/enable/gain/second-gain/release failure
  semantics; no feature deferred. Added 335 named characterization cases,
  with separate activities for all 7 skins × 4 guide styles, real installed
  click/focus/Media3 callbacks, IPTV watch ACK routing, diagnostic-writer
  barriers and exact live/VOD repaint, style and lifecycle behavior.
  Statement sweep: 668 nodes across all 35 functions/callbacks, all 214
  direct calls attempted; 386 required assertion proofs plus 20 reviewed
  equivalents resolve all 406 required obligations. 493 archived original
  attempts, 406 assertion kills; invalid/crash attempts get no credit.
  All 335 named cases have original mutation witnesses. Full table/matrix,
  fixture hashes, patches/logs/XML and owner rescan are in deps/p15/step0.
  Clean baseline-ce3ddfb06 has 1,606 identities (1,605 pass, known focus
  failure); p15-step0 has 1,941 (1,940 pass, same failure): exactly 335
  passing additions, strict old-status equality and stable fingerprints,
  matched evidence-only 1 GiB heap/JBR. Original lint archived: 1,352 issues
  (253 errors/1,099 warnings, 175 opt-in errors), exit 1 unchanged baseline.
  Final clean checker suite passes 419/419; earlier destinations and all
  protected paths unchanged. Original detached worktree removed. No new
  size exception, old-test assertion edit, production move, bug fix,
  lockfile/ProGuard change, device interaction, branch switch or push.
  Stopped before Step 1 for Claude’s independent sample; move/release/R8/
  Flutter phase gates remain at their planned milestone.


- 2026-10-09 — **Phase 15 Step 0b complete.** Independent s01 is observable:
  the extra label/caption publication precedes resize application. Two new
  original-surface TextWatcher tests pin evaluation-time resize state and one
  repaint per action; exact s01 and a duplicate-after-resize variant each fail
  both named assertions. All 337 phase-15 controls pass on original ce3ddfb06.
  s02 is equivalent: all four production writers preserve resizeModeIndex
  0..3; == 3 and >= 3 coincide, and its full 337-case mutant run passes.
  Classification, invariant, immutable fixtures, logs/XML and mutation rows
  are in p15/step0b/ and the deps report. p15-step0b has 1,943 identities:
  1,942 pass, same known focus failure; exactly two passing additions versus
  p15-step0, every prior status equal, stable tree, matched 1 GiB/JBR.
  Original detached worktree removed; all 68 protected paths unchanged.
  No old assertion edit, production bug fix, lockfile/ProGuard edit or device
  interaction. Step 1 and the integration gate follow as authorized.


- 2026-10-09 — **Phase 15 Step 1 moves complete.** Extracted the approved
  dock owner (554 lines), eagerly constructed live styler (294, reference
  controlsDock) and sibling playback-display owner (438); DockSkinSpec is
  top-level. Activity 7,982 → 6,986, size baseline lowered with --update.
  Shared views, skin lazies and borrowed routing/player/preferences/selector
  remain activity-owned; dock runtime stays for phase 16. Computed Hosts,
  both original slots, five Host-property re-points and three in-place
  onDestroy patches preserve initializer and lifecycle order.
  Checker: 1,730 original declarations, zero differences; 51 earlier files
  frozen at ce3ddfb06, 31 initializer proofs. Compiled production audit:
  17 receiver/getter pins, 23 findViewById assignments (12 cast/11 no-cast),
  resize constants inlined. All five Kotlin warning identities unchanged.
  Owner map routes 54 moved names; NativePlayerSettings helper retargets
  Android TV nightModeIndex only. All assertions and Dart files unchanged,
  helpers 325/650 lines. Focused JVM run passes 341/341 (337 phase-15 plus
  four native settings cases). Evidence p15/step1/ and p15/gate/.
  No production bug fix, new size exception, lockfile/ProGuard edit, push,
  branch switch or device interaction. Integration gate follows on this
  committed tree; no self independent review.


- 2026-10-09 — **Phase 15 gate complete on 699668ae8; decoder
  pending-environment. STOPPED after Phase 15.** Step 0b f3aea36e0 pins
  observable s01 with two original-surface tests and two assertion-killed
  variants; s02 is equivalent under the proven 0..3 production invariant
  and passes all 337 mutant cases. Step 1 699668ae8 extracts the 554-line
  dock owner, eager 294-line live styler via controlsDock and sibling
  438-line playback-display owner; DockSkinSpec is top-level. Activity
  7,982 → 6,986. Dock runtime and borrowed infrastructure stay; size
  baseline lowered without a new exception. Current checker: all 1,730
  original declarations classified, zero differences. All 419 self-tests
  and historical p1–p14 merge checks pass. Fifty-one earlier destinations
  remain byte-identical to ce3ddfb06; 31 initializer proofs, slot/eager
  construction and full lifecycle/teardown order pass. Production compiled
  audit pins 17 receiver/getter sites, 23 view bindings (12 cast/11 no-cast)
  and resize constant inlining. Fifty-four owner routes and the Android TV
  nightModeIndex helper retarget retain every assertion; Dart unchanged.
  Clean p15-gate exactly matches all 1,943 p15-step0b identities/statuses
  (1,942 pass, same known focus failure), stable clean tree, complete XML,
  matched evidence-only 1 GiB workers/JBR. Five Kotlin warnings and 1,758
  analyzer diagnostics are unchanged. Lint exactly retains all 1,352 issue
  identities (253 errors/1,099 warnings, 175 opt-in errors), after normalizing
  one absolute wrapper path from the original archive to the same checkout-
  relative location; raw initial comparison and identical wrapper bytes are
  archived, with no suppressions or diagnostic changes. Release APK builds.
  R8/DEX checks all 13 generated classes and 389 members, including both
  Hosts/activity implementations, DockSkinSpec, anonymous classes and new
  file facades; three mapping negative controls pass. Decoder failure
  output, all three native hashes and missing-feature manifest match prior
  phases/phase 1: pending-environment. Affected Dart source tests match all
  45 prior statuses. Full Flutter suite via suite_evidence.py on clean gate
  commit 699668ae8 exactly matches all 12,855 phase-14 identities/statuses
  (12,794 success, 13 failure, 28 error, 20 skipped), same SDK/flags, stable
  tree. Evidence p15/step0b/, step1/, gate/ and junit/p15-step0b/, p15-gate/.
  Lockfile, ProGuard and earlier manifests/destinations unchanged. No push,
  branch switch, self independent review, device/emulator or bug fix.
  Phase 16 not started.
- 2026-10-09 — phase 15 post-implementation reviews of `1e184b9b1..e92fe6fb7`.
  Claude's independent sample 13/15 (87 %); s01 (extra aspect-label update
  before apply) proved observable and pinned; s02 (`== 3` → `>= 3`)
  equivalent under the verified 0–3 index invariant. Independent Codex review
  (fresh session): **No P1s, no P2/P3**; 7 × 4 skin/style matrix, loudness
  failure paths, aspect publication order, 12/11 cast pins all preserved;
  lint path normalization changes only the wrapper path. Activity
  7,982 → 6,986. Decoder verification remains pending-environment. Phase 15
  complete; merged.
- 2026-10-09 — phase 16 design round 1 (Codex): **No P1s**; P2s folded (route
  all 34 reflectively accessed moved names; twelve independent clean-state
  blockers); P3 retain all 23 view-binding pins. Phase 16 design approved.

- 2026-10-10 — **Phase 16 step T complete** on `refactor/tvplayer-p16`. First routed all 34 existing reflective names (151 quoted accesses); assertions unchanged, original-owner compatibility retained until extraction. Re-measured at `df439aed1`: 1,727 declarations, 80 Activity members plus the companion constant, 48 in-place edits and 46 Host forwarders/68 token re-points. All-retained original self-comparison has zero differences; phase-15 historical check at the merge passes; all 54 earlier destinations are frozen. The complete extraction fixture (416/329/542 lines) compiles offline and passes the source partition, 38 initializer proofs, seven receiver pins, all 23 retained phase-15 view bindings (12 casts/11 absent, three array stores), and volatile identity field/writer/reader checks. Narrow float/null-array/Runnable classifier forms and negatives, readiness reads, nested slots, `controls`/local `overlay` and local `player` exclusions, computed forwarders, opt-in presence/absence and teardown/named-argument negatives are covered. **419 historical + 44 phase-16 checker/auditor self-tests pass**, including the separate phase-15 merge-history test; the router fixture context was corrected and all phase-16 cases rerun. Clean original JVM `baseline-df439aed1`: 1,943 identities (1,942 pass, unchanged source-browser focus failure); stable `p16-tools-recheck` preserves every identity/status. Original lint archived: 1,352 issues, 175 opt-in errors. Evidence: `p16/tools-result.json`, `overload-audit.json`, self-test logs, `remeasured-inventory.json`, `lint-original/`, and `junit/`. Production source, lockfile, ProGuard and all earlier manifests/destinations remain unchanged. Step 0 follows; no production moves.

- 2026-10-10 — **Phase 16 Step 0 complete; stopped before production moves.**
  Animator/recording-player prerequisites demonstrated first on df439aed1,
  repeated and assertion-mutation-proved; no feature deferred. Added 287
  named cases in 13 behavior suites plus prerequisite suite, 18 cohesive
  files, separate real activities for seven skins. Pins full key routing,
  twelve independent blockers/all-clear, dock/Next/auto-hide timing,
  per-skin identity, live retry ordering, scrub/legacy seek and ticker,
  metadata worker timing, Host/caller wiring, pause/stop and onDestroy.
  Real framework callback stepping resolves paused-looper native vsync;
  cancellation observations settle bootstrap and moved animations stay real.
  Statement matrix: 668 nodes in 43 functions/callbacks; all 439 required
  obligations (160 direct calls, eight Elvis guards included) have named
  assertion proofs, no equivalents/unresolved nodes. 537 original attempts,
  484 assertion kills; invalid/crash/cancelled attempts get no credit;
  every one of 287 named cases has a witness. Deps table/matrix and raw
  fixture hashes/patches/logs/XML in p16/step0. Final clean p16-step0:
  2,230 identities (2,229 pass, same known source-browser focus failure),
  versus baseline-df439aed1 1,943 (1,942 pass): exactly 287 passing additions,
  strict old-status equality, stable fingerprints, matched evidence-only
  1 GiB/JBR. Original lint archived: 1,352 issues (253 errors/1,099 warnings,
  175 opt-in errors), exit 1. Final combined checker/auditor suite 463/463;
  72 protected hashes unchanged. Reflection rescan: 78 names/699 sites;
  Step-1 route additions remain. Original worktree removed; lockfile,
  ProGuard, production and size baseline unchanged. No bug fix, push or
  device interaction. STOP before Step 1 for Claude’s independent sample.

- 2026-10-10 — **Phase 16 Step 0b complete; STOP before production moves.**
  First independent sample killed 11/16 (69%); all five survivors
  t07/t12/t14/t15/t16 are now assertion-killed on df439aed1, including a
  final rerun against all 379 Phase-16 cases. Added 92 named cases in five
  cohesive suites plus a 27-line actual-framework end-action observation
  helper (six files, at most 79 lines each); all 287 old cases and their
  18 fixture/test files are byte-for-byte unchanged. Seven-skin hide/reveal
  and scrub cases pin pre-cleanup alpha/translation/scale, exact durations
  and easing, title reset, floating-banner lifetime, missing metadata and
  deliberately late delivery of real production callbacks. Re-sweep:
  96 PSI nodes / 67 required direct obligations across showControlsMenu,
  hideControlsMenu and hideTitleImmediately freshly assertion-proved;
  57 parameter variants (12 duration sites, five curves), seven end-action
  installations/bodies (24 mutations), eight additional predicate variants.
  166 original mutation attempts, all named assertion kills; every one of
  92 additions has a witness, no missing matrix entry or equivalent claim.
  Final original control: 379/379. Stable matched-1-GiB/JBR p16-step0b:
  2,322 identities (2,321 pass, same known source-browser focus failure),
  vs p16-step0 2,230: exactly 92 passing additions, all old statuses equal;
  helper and strict comparisons pass. Coverage matrix, mutation table,
  source patches, fixture snapshots, full logs/XML and comparisons archived
  in p16/step0b and junit/p16-step0b. Reflection rescan: 78 names/756 sites.
  All 72 protected hashes and the size baseline retained; size/diff checks
  pass. Earlier unchanged checker/auditor and original lint evidence reused.
  Detached original removed. No production move, bug fix, push or device
  interaction. Claude runs the required second independent sample next.

- 2026-10-10 — **Phase 16 Step 0c complete.** Claude's second sample's u06
  and u12 are assertion-killed against all 399 Phase-16 cases. CLASSIC has a
  null dock spec, but u12 changes the real styled-selected/uninstalled
  live-IPTV gate; all seven legacy icon pairs are now pinned. u14 is
  **equivalent**: the unchanged `formatTime` already maps every nonpositive
  input to `00:00`; exact mutation runs all 399 cases successfully. Preserve
  the original padded remaining string `-00:00`. Twenty added cases each
  have a named assertion proof, including zero/past-duration boundaries.
  `p16-step0c` archives 2,342 identities (2,341 pass, the unchanged focus
  failure), additions-only versus `p16-step0b`, matched 1 GiB/JBR, stable
  tree and complete XML. Rescan 78 referenced names/766 sites; all 80 moved
  Activity members will be routed. Mutation table/matrix extension appended
  to deps; evidence `p16/step0c/` and `junit/p16-step0c/`. No production
  changes; Step 1 is now authorized by the second independent sample.

- 2026-10-10 — **Phase 16 Step 1 complete.** Manifest-exact controls owner
  plus eager identity/seek collaborators; 1,727 declarations, zero source
  differences. View decision preserved (23 nullable views move;
  `ottSkinInstalled` and 18 lateinit views retained), 46 Host re-points/68
  edits, two readiness getters and two in-place teardown patches. Files
  416/329/542 lines, Activity 6,986 → 5,891; size ratchet updated. All 80
  Activity member routes (46 added) with unchanged assertion/Dart bytes.
  All 399 Phase-16 cases pass, compiled audit of seven receiver sites and
  all 23 phase-15 binding pins passes, volatile field/writers/reader verified.
  Thirty-eight initializer proofs, teardown order and 54 frozen destinations
  pass. Evidence `p16/step1/`, `p16/gate/`; full gate follows.

- 2026-10-10 — **Phase 16 gate native checkpoint** at `8f3c3d35f`. Clean JVM
  exactly matches all 2,342 `p16-step0c` identities/statuses (same one focus
  failure); five Kotlin warnings unchanged. Current/historical p1..p15
  checkers, original self-comparison, 54 frozen destinations, 38 initializer
  proofs, compiled receiver/binding audit and teardown pass. Lint has no
  additions and retains all 175 opt-in findings; one Activity-only
  `GestureBackNavigation` finding disappears after its unchanged handler
  moves to the seek controller, confirmed by the installed detector's
  bytecode. All other 1,351 identities remain. Release APK succeeds; all
  eight generated classes/289 members retain R8/DEX identities (three
  negative controls). Decoder remains pending-environment with exact
  phase-15 output and phase-1 library/gap hashes. Stable analyzer rerun
  exactly matches 1,758 diagnostics; retained initial overlapping-build
  attempt duplicated existing diagnostics, with no source changes. Full
  checker fixtures continue; affected/full Flutter comparison follows on
  this clean `gate` checkpoint. Evidence `p16/gate/`, `junit/p16-gate/`.

- 2026-10-10 — **Phase 16 final gate complete; STOP after Phase 16.**
  All 463 checker/auditor self-tests and historical p1..p15 merge checks pass,
  1,727 declarations/zero differences, 54 frozen destinations, 38 initializer
  proofs, seven compiled receiver sites plus all 23 phase-15 binding pins,
  volatile identity writer/reader and teardown order verified. All 399
  Phase-16 cases pass; clean `p16-gate` exactly preserves 2,342 `p16-step0c`
  statuses (same one JVM failure). On clean gate commit 3ab9553da,
  affected Dart tests preserve all 45 statuses and full Flutter preserves
  all 12,855 phase-15 identities/statuses (12,794 success, 13 failure,
  28 error, 20 skipped), stable tree/same SDK. Release + R8/DEX 8 classes/
  289 members pass; five Kotlin warnings and 1,758 analyzer diagnostics
  unchanged. Lint has no additions / 175 opt-in findings unchanged; the
  single Activity-only back-navigation diagnostic removal is explained by
  the installed detector's subclass predicate, with unchanged key behavior.
  Decoder remains pending-environment with exact phase-15 failure and all
  phase-1 binary/gap hashes. No new behavior regression observed. All 80
  routes use unchanged assertions; Dart, lockfile, ProGuard, earlier files
  and manifests unchanged. Evidence `p16/gate/summary.json` and raw
  archives, `p16/step0c/`, `p16/step1/`, `junit/p16-step0c/`, `junit/p16-gate/`.
  No push, device or emulator interaction; no independent self-review.
  Phase 17 not started.
- 2026-10-10 — phase 16 post-implementation reviews of `df439aed1..55f8b4135`.
  Claude's independent samples 11/16 then 14/17 after the 0b sweep; 0c
  closed u06/u12 by assertion, u14 (`coerceAtLeast(0)`) equivalent because
  `formatTime` already maps nonpositive values to `"00:00"`. Independent
  Codex review (fresh session): **No P1s, no P2**; one P3 (deps wording
  "nullable views" → "shared dock fields") fixed. Verified 27 dispatcher
  patches keep order and every `super` fallthrough, the cinema key listener
  is byte-identical after reversals, and the back-navigation lint removal is
  detector scope only. Activity 6,986 → 5,891. Decoder verification remains
  pending-environment. Phase 16 complete; merged.
- 2026-10-10 — phase 17 design review (Codex, `tvp-design`): **No P1s**.
  P2 folded: reflective retargets are 31 sites over 7 routing keys incl.
  the generated getter `getIptvLiveRecovery`; phase-16 tests already cover
  parked restoration and lazy recovery timing. P3 folded: `twin` collision
  count (8 local + 1 parameter bindings, 25 occurrences). Other counts
  re-verified on `be5635fae`: 41 members / 614 lines, 28 activity patches,
  8 Host re-points / 9 edits, 20 Host members, 21 initializer proofs.

- 2026-10-10 — **Phase 17 Step T complete** on `refactor/tvplayer-p17`. Routed all 31 original reflective sites/seven keys first, including raw `getIptvLiveRecovery`; assertions unchanged. Re-measured at `be5635fae`: 1,676 declarations/zero self-comparison differences, 41 members/614 span lines, 28 in-place patches, eight Host re-points/nine edits, 120 substitutions. Complete production extraction fixture compiles offline (396/289 lines), all 21 initializer proofs and eight compiled receiver pins pass, including implicit AppCompat `addContentView` in TextView.apply with inner receivers preserved. Two Activity-owned volatile fields/Host accessors, deferred synchronized recovery/device lazies, all 23 phase-15 binding pins and volatile identity writers/reader verified. Fifty-seven earlier destinations and all sixteen earlier manifests frozen. Checker/auditor: 463 historical + 54 final Phase-17 cases pass (507-case dispatcher plus final 54-case focused run). Clean original baseline 2,342 identities/2,340 pass; helper-only run preserves every status, including the focus NPE and EPG progress timing assertion observed in this baseline. Lint archive 1,351 issues/175 opt-in errors. All 76 protected hashes unchanged. Evidence `p17/tools-result.json`, fixture/compiler/auditor/self-test logs, `lint-original/`, `junit/baseline-be5635fae`, `junit/p17-tools`. No production move, lockfile/ProGuard change, bug fix, push or device interaction. Step 0 prerequisites follow.

- 2026-10-10 — **Phase 17 Step 0 complete; STOP before production moves.** Mandatory real-pipeline loader prerequisite passes on original `be5635fae`: installed Media3 1.8.0 resolver/extractor factories, two bounded worker/MockWebServer invocations, live header re-read, both aggressive/strict extractor overloads and Activity volatility. PAUSED clock, extended opt-in player proxy, fake network callbacks, error chains and device instances pass; no feature deferred. Added **183 original characterization identities in 16 cohesive classes**, plus eight reused controls/live cases; final control 191/191. **339 accepted mutations fail named assertions; every new identity has a witness.** Systematic matrix accounts for all 282 collected nodes across 21 moved/lazy units and five nested callbacks, including all state writes, guards, posts, calls and returns. Pure constructor/value aliases are explicit; one return-removal is equivalent (zero elapsed since the just-stored sample, pure comparison below 15000 ms), verified against all 191 cases. Type-invalid, ineffective, crash-only and interrupted attempts are archived/excluded and corrected alternatives credited. Real callers, repeated UI refresh counts, forced-HLS/device diagnostics, VOD subtitle-readiness before resumed dispatch, strict/twin boundaries, tee publication, ticker wiring, and stop/start/destroy/network ordering are pinned. Clean `baseline-be5635fae` 2342 (2340 pass/two observed failures) → `p17-step0` 2525 (2524 pass/one failure): 183 passing additions, no removals/new failures/skips; every old pass remains passing. Existing source-browser focus NPE remains; the previously observed EPG real-clock timing failure passes now, explicitly recorded as status variation rather than strict equality or a fix. Original lint remains archived: 1351 identities/175 opt-in errors. Ten patched manifest rows now name actual tests; structural patches unchanged. All 41 moved names + raw getter routed, both volatile fields Activity-owned; original self-comparison 1676/zero and 57 frozen earlier destinations pass. Step-T 463 historical cases retained; final 54-case Phase-17 checker/auditor recheck passes (517 distinct cases), with 21 initializer/eight receiver/23 binding pins retained. All 76 protected hashes and lockfile/ProGuard unchanged; size check without update, helper ≤800. Evidence `p17/step0/`, `lint-original/`, `junit/baseline-be5635fae`, `junit/p17-step0`. Detached original removed after archival. No bug fix, production move, push, branch switch, device/emulator interaction or self independent review. Claude's separate sample/review is next.

- 2026-10-10 — **Phase 17 Step 0b complete.** Claude's independent sample 19/21; exact c08/c15 re-runs now fail named assertions. Added two original tests: real record-button TextWatcher callbacks before an injected prepare failure, and AUTH preference revocation through a later channel start plus loss of preferred-map strict demux. Both killed, neither equivalent. Updated corresponding witnesses in the 282-node matrix; original control 10/10. Clean matched-heap `p17-step0b` 2527/2526 pass/one existing focus NPE exactly preserves all `p17-step0` statuses with two passing additions. EPG passes at both steps; clean-base failure remains documented original timing flakiness. Evidence `p17/step0b/`, `junit/p17-step0b/`; no production, lockfile or ProGuard edit. Approved Step 1 and gates follow.

- 2026-10-10 — **Phase 17 Step 1 complete; integration gate follows.** Extracted the 396-line tune owner and eagerly constructed 289-line field-bearing trial from the exact manifest; Activity 5891 → 5312, size ratchet updated. All 28 in-place patches and eight/nine Host re-point edits preserve order, 20 computed Host members/ten deliberate absences, 21 initializer proofs, lazy first-access timing, two Activity-owned volatile loader fields and the three-only `setupPlayer` patches verified. Zero checker differences across 1676 declarations; p1–p16 historical checks, 57 frozen destinations, teardown tokens, compiled eight receiver/23 earlier binding pins and volatile/identity storage audits pass. All five production Kotlin warnings unchanged. Focused 193/193 pass with all assertions/test files byte-identical; 42 preinstalled owner routes include raw getter, no Dart edits. Evidence `p17/step1/`, `p17/gate/`; full clean-tree integration gate next. No bug fix, dependency/ProGuard edit, push, device interaction or self independent review.

- 2026-10-10 — **Phase 17 gate complete; STOP after Phase 17.** Clean `gate` checkpoint `9772e09e5`: 517 checker/auditor self-tests, 1676 declarations/zero differences, all p1–p16 historical `--at` checks, 57 frozen destinations, 21 initializer proofs, eight compiled receiver/23 retained view pins, volatile/lazy/identity and teardown-order checks pass. Owner/trial 396/289 lines, Activity 5891 → 5312, size ratchet lowered; 28 in-place patches, eight/nine Host re-point edits, 20 computed Host members/ten deliberate absences and 42 routes preserve scope. All 193 focused cases pass unchanged. Clean matched-heap JVM `p17-gate` exactly preserves all 2527 Step-0b statuses: 2526 pass, one known focus NPE. EPG fails only at the clean original baseline and passes at Step 0, Step 0b and gate; explicitly original real-clock flakiness, no hidden status change or test-window fix. Original lint exact: 1351 issues/175 opt-in errors; all five Kotlin warnings unchanged. Release build succeeds, R8/DEX five new/generated classes/132 members pass; decoder remains pending-environment with phase-16/1 identical failure/gaps/library hashes. Full Flutter suite exactly matches all 12855 phase-16 statuses (12794 success/13 failure/28 error/20 skipped), 45 source-text statuses and 1758 analyzer diagnostics unchanged. Evidence `p17/step0b/`, `step1/`, `gate/`, `junit/p17-step0b/`, `p17-gate/`; original detached worktree removed, protected files and all test inputs unchanged. Heavy processes niced; no bug fix, push, branch switch, device/emulator interaction or self independent review. Phase 18 not started.
- 2026-10-10 — phase 17 post-implementation reviews of `be5635fae..710d3de9f`.
  Claude's independent sample 19/21 (90 %); c08 (dropped record-button
  refresh after finalize) and c15 (AUTH revoke keeps the original→twin
  preference) closed in 0b by mutation-proved tests. Independent Codex review
  (fresh session): **No P1s, no P2/P3**; volatile storage, lazy recovery
  timing, implicit `addContentView` dispatch, error-branch priority and
  teardown order preserved; EPG timing flakiness classification supported.
  Activity 5,891 → 5,312. Decoder verification remains pending-environment.
  Phase 17 complete; merged.

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

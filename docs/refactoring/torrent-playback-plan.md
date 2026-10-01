# Torrent playback service refactor — plan

Written 2026-10-01 on `refactor/search-screen` at `1d6fa710`. Follow
[AGENTS.md](../../AGENTS.md). This page plus AGENTS.md is everything the
executing agent needs; the search-screen plans are history and need not be
read.

Work on the existing `refactor/codebase` branch; don't create a new
one. Commit after every step (more often is fine). Never
push to `origin`; push to `private` only if the goal you were given says so.

## Goal

`lib/services/torrent_playback_service.dart` is 7,103 lines: one static class
`TorrentPlaybackService` (~110 static methods) plus `_Resolved` and
`_PlaybackCancelToken`. It picks, searches, ranks, acquires, binds and launches
sources for every play button in the app. Split it into
`lib/features/sources/` by responsibility, **moving code verbatim**, and leave
a small facade.

## What it contains (line numbers at `1d6fa710`)

| Lines | Area | Key symbols | Context/UI? | Destination under `lib/features/sources/` |
| --- | --- | --- | --- | --- |
| 106–494 | Shared state and the manual entry point | `_cancelled`, `_noPackUntil`, `_recentlyNoPack`, `_markNoPack`, `activateTorrent` (320 lines) | `activateTorrent` yes | `_cancelled` → step 1; no-pack memory with `playFromSelection`; `activateTorrent` → `presentation/legacy_playback/manual_source_activation.dart` |
| 495–1178 | Automatic "play best" | `playBest` (680 lines; `playDirect` and `playFirstAliveDirect` are closures inside it), `_isDirectCandidate` | yes | `presentation/legacy_playback/automatic_play_best.dart` |
| 1179–1432 | Probing and pack safety | `selectDirect`, `probeAttemptCount`, `packTopSafety`, `_packCoverageTypes`, `_probeCandidates`, `cleanupFailedAutomaticAcquisition` | **no** | `application/source_probing.dart` |
| 1433–2150 | Quick play from a selection | `playFromSelection`, `tryPackRoute`, ladder fallbacks; `loadLadder`, `ladderNote`, `_applyLadderNote` | yes, except the ladder helpers | `presentation/legacy_playback/automatic_play_selection.dart`; `loadLadder`/`ladderNote` → `application/` |
| 2151–2555 | Ranking and search plans | `orderCandidatesForRules`, `_qualityScore`, `prefersTorrentCandidates`, `mergePreparedTorrentOrder`, alias warm-up/cache, `orderCacheCheckedCandidatesForRules`, `directValidationBudgetForRules`, `shouldPreflightDirectStream`, `shouldTryDirectBeforeTorrent`, `isAutoPlayableCandidate`, `confirmDeferredIptvAvailability`, `shouldSearchAddonsBeforeProvider`, `allowsAddonSearch`, `addonStreamSearchPlan`, `packSearchReportedErrors` | no | `application/source_candidate_ranking.dart`, `application/source_search_plans.dart` |
| 2556–3174 | Source searches | `searchSeriesPackSources`, `seriesPackSearchPlan`, `iptvQuickPlaySearchTimeout`, `searchIptvForQuickPlay`, `_originEpisodeVideoId`, `searchCuratedSources`, `prepareRecoverySources`, `resolveRecoverySource` | no | `data/series_pack_search.dart`, `data/iptv_quick_play_search.dart`, `data/curated_source_search.dart`, `data/recovery_source_resolution.dart` |
| 3175–3953 | Fetchers and curation | `seriesFetcherFor`, `movieFetcherFor`, `_fetchOneEngine`, `_fetchMediaServerSources`, `_mediaServerSourceRefs`, `_sourceEngineListing`, `_effectiveFetchProvider`, `_curateCandidates`, `_curatePackCandidates`, `earlyDirectCandidate`, `earlyDirectRecovery`, `leadingDirectAddonKey`, `directSearchErrors` | no | `data/source_fetchers.dart`, `application/source_curation.dart` |
| 3954–4373 | Addon-stream playback | `_playAddonStream` | yes | `presentation/legacy_playback/addon_stream_playback.dart` |
| 4374–5267 | Bound-source playback | `_bindingMatchesMeta`, `_providerFromStored`, `storedProviderKey`, `_boundProviderSupported`, `_resolveLocalBound`, `_resolveProviderNativeBound`, `_seLabel`, `_resolvedHasEpisode`, `_torrentFromSource`, `_playViaBound` | yes, except the step 1 helpers under "Dependency order" | `presentation/legacy_playback/bound_source_playback.dart`, `presentation/legacy_playback/bound_source_resolution.dart` |
| 5268–5470 | Binding | `_recoverAfterBoundStartupFailure`, `bindSource`, `bindDirectSource`, `bindIptvSource`, `bindLocalSource` | yes | `presentation/legacy_playback/source_binding_actions.dart` |
| 5471–6031 | Acquire and launch | `_add`, `_play`, `_advanceToNextEpisode`, `_playerArgs`, `playerArgsForTesting`, `_configuredProviders`, `_defaultConfiguredProvider`, `_lazyProviderResolver`, `_launch` | `_add` and the provider helpers **no**; the rest yes | `_add` → `application/source_probing.dart`; provider helpers → `application/source_provider_config.dart`; the rest → `presentation/legacy_playback/source_player_launch.dart` |
| 6032–7075 | Provider action menu | `_launchWithDeoVR`, `_directValidationKey`, `supportsDirectStreamDownload`, `downloadDirectStream` (calls the existing `downloadSource`), `_acceptedProviderAction`, `_download`, `_addToPlaylist`, `_showChooser`, TorBox/Premiumize ZIP and transfer, `_handleNotCached`, `_pickProvider`, `_isConfigured`, `_cacheFirst`, `_hasAcquisition`, `_label`, `_showPipeline`, `showResolvingOverlay`, `_showLoading`, `_snack` (the class's single `_snack`), `_resolverFor`, `_validatedLaunchCommitter`, `_lazySourceCommitter`, `_postAction` | yes, except the step 1 helpers under "Dependency order" | `presentation/legacy_playback/provider_action_menu.dart`, `presentation/legacy_playback/provider_zip_actions.dart`, `presentation/legacy_playback/source_loading_overlays.dart`, `presentation/legacy_playback/deovr_launch.dart`, `data/deovr_json_upload.dart` (see Technique) |
| 7076–7103 | Private types | `_Resolved`, `_PlaybackCancelToken` | no | `models/resolved_source.dart`, `models/playback_cancel_token.dart` |

The file names are suggestions. Keep each new file under 500 lines (prefer
300) with one responsibility, and split further where needed.

**Where presentation code goes, and why.** Moving verbatim means the moved
pipelines, menu, launch and binding still call legacy services directly
(`StorageService`, `DebridService`, `IptvSourceSearch`, `VideoPlayerLauncher`,
and so on). The guard rejects `lib/services/` imports from `presentation/`,
except in the named bridge folder `presentation/legacy_playback/`
(`LEGACY_PLAYBACK_BRIDGE` in `dev/tool/check_search_architecture.py`):
- Every context-taking moved file goes there, and only those.
- It may import `lib/services/`, including the facade for `TEMP(tps)` calls.
- `http`, `shared_preferences` and `sqflite` stay forbidden there.
- `application/`, `data/` and `models/` keep the strict rules.
- This is a temporary structural exception. Its exit milestone: those service
  calls move behind Sources data contracts and the folder is dissolved, after
  this plan. Record it in Progress. Before moving
anything into `application/`, `data/` or `models/`, confirm it uses no
`BuildContext`, widget or dialog. If it does, it belongs in `presentation/legacy_playback/`.

**Production callers today:** 7 files (Home catalog play bridge and play
action, the two Sources bridges, the search screen composition,
`video_player_launcher.dart`, `series_source_fetcher.dart`), plus 26 test
files.

## Dependency order (checked at `1d6fa710`)

The areas are not independent. These context-free helpers live in later,
UI-heavy areas but are called by earlier, no-UI areas, so **they move in step
1**:
- **probing and acquisition:** `_add`, `_probeCandidates`, `selectDirect`,
  `probeAttemptCount`, `packTopSafety`, `cleanupFailedAutomaticAcquisition`
- **candidate tests:** `_isDirectCandidate`, `_hasAcquisition`,
  `_resolvedHasEpisode`, `_bindingMatchesMeta`, `_directValidationKey`,
  `_cacheFirst`
- **config and ladder:** `_cancelled`, `iptvQuickPlaySearchTimeout`,
  `_defaultConfiguredProvider`, `loadLadder`, `ladderNote`

The presentation areas call each other in a cycle, so step 3 moves menu,
launch and binding together:
- the menu calls `_play`;
- launch calls the menu's `_launchWithDeoVR`, `_pickProvider`, `_label` and
  `_snack`, and calls `playFromSelection`;
- binding calls `playFromSelection` and `_playViaBound`.

Import cycles between presentation files in the same feature are fine in Dart
and allowed by the guard.

**Temporary cross-calls.** Code that has moved but still calls an unmoved
member goes through `TorrentPlaybackService.<name>`, with the leading `_`
dropped and the comment `// TEMP(tps): moves in step N` on the member.
- Only `legacy_playback/` files may make such calls.
- `application/` and `data/` code must never need one. If it does, move the
  callee earlier instead.
- Step 5 removes every one: `grep -rn "TEMP(tps)" lib` must be empty when
  you finish.

Re-run this check before each step rather than trusting the table. For each
moved member, grep the area being moved for names defined elsewhere in the
service.

## Invariants (every step)

1. Play buttons, Quick Play, source tabs, bound sources and recovery choose the
   same sources in the same order with the same filter-ladder notes, timeouts,
   probe counts and fallbacks.
2. Profile ownership is unchanged:
   - captured owners and `canContinue`/`isCurrent` guards;
   - retirement cleanup: fresh Real-Debrid torrent removal, PikPak and
     rejected-source cleanup;
   - an accepted provider action (`_acceptedProviderAction`) finishes after
     the screen closes.
3. Loading dialogs, pipeline overlays, snackbars, chooser sheets, route pops
   and player launch keep their order, text and dismissal. No player-engine or
   native-bridge payload change (headers, subtitle/audio settings, DeoVR).
4. Static state keeps its lifetime. `_noPackUntil` (no-pack memory) and the
   source alias cache/warm-up are process-wide statics. Move each with its
   single owner, keep it static, don't make it profile-scoped here, and
   record that classification in Progress.
5. No Riverpod, providers or new DI. This is service and bridge code with no
   new consumer: use plain functions and small classes.

## Technique: move-only

- Move bodies **verbatim** into top-level functions, or into small `final`
  classes with static members.
- **Allowed edits:**
  - drop the leading `_` when another file now uses the symbol
    (`_Resolved` → `ResolvedSource`, `_PlaybackCancelToken` →
    `PlaybackCancelToken`);
  - change call sites, qualifiers and imports;
  - add `TEMP(tps)` cross-calls as above.
- **Imports:** take `PlaylistEntry` from `lib/models/playlist_entry.dart`.
  `lib/screens/video_player/models/playlist_entry.dart` only re-exports it,
  and the guard rejects `lib/screens/` imports from `application/`, `data/`
  and `models/`. The same layers may import Flutter only through
  `package:flutter/foundation.dart` (`debugPrint`, `@visibleForTesting`).
- **One extraction is required, not just allowed.** `_launchWithDeoVR` posts
  the DeoVR JSON with `http.post` (service line 6188), and the bridge folder
  may not import `http`. Move exactly that block into
  `data/deovr_json_upload.dart` as
  `Future<String> uploadDeoVrJson(Map<String, dynamic> json)`. The block
  posts to `https://jsonblob.com/api/jsonBlob`, throws unless the status is
  201, throws if there is no `location` header, and returns
  `'https://jsonblob.com$location'`. Keep the same request, the same exception
  messages, the same order (it still throws before the loading dialog is
  popped) and the same single `await`. `deovr_launch.dart` then calls it in
  place of the inline block. No other `http` use exists in the service.
- **Not allowed:**
  - reordering awaits or guards;
  - merging look-alike helpers into one;
  - splitting `playBest`, `playFromSelection`, `_playViaBound` or
    `_playAddonStream` (400–680 lines each). Each moves whole into its own
    file; splitting them changes control flow and is a later change.
- `@visibleForTesting` members move with their code. Repoint their tests by
  import and qualifier only. Don't keep facade forwarders just for tests.
- Dependencies run `presentation → application/data → models`.

## Steps

| # | Move | Notes |
| --- | --- | --- |
| 0 | Baseline | See below. |
| 1 | `models/`: the two private types. `application/`: ranking and search plans (2151–2555), probing (1179–1432), the pure curation helpers from 3739–3953, and every helper in the step 1 list under "Dependency order". | No UI. Heaviest test repointing (`orderCandidatesForRules` and friends). |
| 2 | `data/`: searches and fetchers (2556–3740). | `series_source_fetcher.dart` and `video_player_launcher.dart` call into this area. Keep those calls working through the facade, or repoint them. |
| 3 | `presentation/legacy_playback/`: menu, overlays, DeoVR, launch and binding (5268–7075, minus anything moved in step 1). Several commits are fine. | Keep every `context.mounted`/`isCurrent` gate and `_acceptedProviderAction` exactly as they are. **Full-suite gate 1** after this step. |
| 4 | `presentation/legacy_playback/`: the pipelines. `playBest`, `playFromSelection`, `_playAddonStream`, `_playViaBound` with its helpers, `activateTorrent`, and the no-pack memory. | One pipeline per commit. |
| 5 | Facade, guards, CI, then **full-suite gate 2**. | See "Definition of done". |

### Step 0 — baseline

Evidence lives in `<git common dir>/refactor-evidence/`, so every worktree of
this clone shares it. It is never committed. `dev/tool/suite_evidence.py`
records and compares runs; `<E>` below is
`$(git rev-parse --git-common-dir)/refactor-evidence`.

**Baseline:** `<E>/finish/bugfixes.jsonl` at `1d6fa710`, with 10,289 pass /
22 fail / 29 err / 20 skip.
- Environment: Flutter 3.44.8, framework `058e0af2c2`, Dart 3.12.2, in
  `<E>/finish/bugfixes.env.json`.
- `compare` refuses runs whose recorded SDK differs. Run `flutter --version`
  first; if it isn't 3.44.8 at that revision, stop and ask. Don't upgrade.
- Later commits touch no app Dart, so reuse this baseline rather than
  rerunning it.

**If the baseline file is missing** (fresh clone, or another machine), record
one at the base revision before moving anything:
`git worktree add ../tps-base 1d6fa710`, then in that worktree
`python3 dev/tool/suite_evidence.py run tps/base`, using
`<E>/tps/base.jsonl` as the baseline. The tool must be copied in or
cherry-picked first, because it postdates `1d6fa710`. `run` records its
checkout root in `base.env.json`, so identities recorded in that worktree
compare cleanly with runs from this one.

Then record the whole-repo analyzer:
`flutter analyze > <E>/tps/analyze-gate0.txt`. That is all of step 0.

### Per step

1. Move the code and fix call sites until `flutter analyze` on the touched
   files reports nothing new. A shifted line number is not a new diagnostic;
   compare rule, symbol and message.
2. Run `dart format` on **new** files only. Don't run it on
   `torrent_playback_service.dart` before step 5: it has pre-existing
   unformatted regions, and reformatting them would bury the moves. By step 5
   those regions have moved into formatted files, and the facade is formatted
   whole.
3. Run `python3 dev/tool/check_search_architecture.py` and
   `python3 dev/tool/check_file_sizes.py`. After the service shrinks, run
   `check_file_sizes.py --update` and commit the lowered baseline.
4. Run the affected tests: `test/features/sources`, plus every test file that
   imports `torrent_playback_service.dart` or a file you created (`grep -rl`).
   Compare failures with the baseline by test name.
5. Self-check that the move is verbatim:
   `git diff --color-moved=dimmed-zebra --color-moved-ws=allow-indentation-change HEAD`.
   Every moved line should show as moved; only the edits allowed above should
   show as changed.
6. Commit: `refactor: move <area> out of TorrentPlaybackService`.

**Full-suite gates.** Run `python3 dev/tool/suite_evidence.py run tps/gate1`
(later `tps/gate2`), then
`python3 dev/tool/suite_evidence.py compare --against <E>/finish/bugfixes.jsonl <E>/tps/gate1.jsonl`.
`compare` decides (`PASS`/`FAIL`): no new failures, no missing tests, no new
skips, same SDK. Show that each renamed or repointed test identity is present
with the same outcome. For a focused per-step comparison, `run NAME PATHS...`
records a scoped run, and `compare` then checks only the suites it ran.

**CI behaviour tests.** The `sources-behavior` job in `checks.yml` runs
`suite_evidence.py check dev/tool/ci_behavior_known_failures.txt @dev/tool/ci_behavior_tests.txt`.
It fails on any failure not listed by exact identity, and on a listed
identity that passes or no longer exists. Keep both files current:
- A test you create or move into a new file is added to
  `ci_behavior_tests.txt`.
- A known failure whose guard you port is removed from
  `ci_behavior_known_failures.txt`.
- Never add an entry to the known-failures list to get a pass.

### Source-text tests

`test/manual_source_validation_contract_test.dart`,
`test/media_server_service_test.dart` and `test/filter_ladder_test.dart` read
this file's source text.
- Point each guard at the file its code moved to, keeping its purpose, or
  replace it with an executable test.
- Never delete an assertion to make a move pass.
- Four contract tests already fail at baseline: "recovery uses automatic
  probes…", "every saved-source launch…", "bound startup recovery…" and
  "delayed startup recovery…". Leave them failing unless a guard is genuinely
  ported; they must not start passing because something was deleted.

## Definition of done

1. `torrent_playback_service.dart` is a facade of **at most 400 lines**. It
   holds only members with a production caller, each forwarding to its new
   owner. At `1d6fa710` there are 14:
   - `activateTorrent`, `playFromSelection`, `showResolvingOverlay`
   - `bindSource`, `bindDirectSource`, `bindIptvSource`
   - `downloadDirectStream`, `supportsDirectStreamDownload`
   - `seriesFetcherFor`, `prepareRecoverySources`, `resolveRecoverySource`
   - `loadLadder`, `directValidationBudgetForRules`,
     `shouldPreflightDirectStream`

   List them with
   `grep -rhoE "TorrentPlaybackService\.[a-zA-Z]+" lib | sort -u`.
   Repointing a caller and dropping its forwarder is also fine.
2. The guard measures the facade.
   - Register it in `dev/tool/check_search_architecture.py` with a 400-line
     cap and no import check, like `COMPOSITION_ROOTS`: it forwards into
     `presentation/legacy_playback/`.
   - Record it in Progress as a temporary exception. AGENTS.md wants
     context-taking playback entry points behind named presentation bridges,
     not in `lib/services`. Exit milestone: repoint the 7 callers to the
     Sources bridges and delete the facade.
3. New files are at most 500 lines. The exception is the four pipeline files,
   which may reach 800 while their method moves whole. Record them in
   Progress with "split the method" as the exit milestone.
4. No new analyzer diagnostics (whole repo, against `analyze-gate0.txt`).
   - Gate 2 is clean against `bugfixes.jsonl` and `tps/gate1.jsonl`.
   - Both guard scripts pass.
   - The service is gone from `file_size_baseline.txt`: `--update` drops
     files at or under 800 lines. The guard's 400-line facade cap is what
     enforces its size.
   - `grep -rn "TEMP(tps)" lib` is empty.
5. CI passes on the branch (`checks.yml` runs on `refactor/**`):
   - file sizes, the architecture guard, and the `sources-behavior` tests;
   - `torrent_playback_service.dart`, formatted in step 5, added to the
     scoped `dart format` and `flutter analyze` steps.
6. Stop after gate 2 and report. The user has Claude review
   `<step 0 commit>..HEAD` before anything is merged.

## Explicitly not in scope

- Splitting the four pipeline methods.
- Making the no-pack memory or the alias cache profile-scoped.
- Any behaviour change, bug fix or provider change. Record a bug you find
  under "Found, not fixed", with file, symbol and a one-line repro.
- Other large files (`storage_service.dart`, the player screens).

## Progress

| Step | Commit | Service lines | Result |
| --- | --- | --- | --- |
| 0 | `e0d3e932` | 7,103 | Reused `finish/bugfixes.jsonl` at `1d6fa710`; SDK matches. Whole-repo `flutter analyze`: 836 existing diagnostics in `<E>/tps/analyze-gate0.txt`. |
| 1 | `1e47f83a` | 5,893 | Moved no-UI dependencies and models. Focused suite: 1,101 pass / 4 observed baseline failures; comparison PASS. Size/import guards pass. |
| 2 | `014502cf` | 4,749 | Search/fetcher owners wired; focused suite 1,101 pass / same 4 failures; comparison PASS. Analyzer and size/import guards unchanged/pass. |
| 3 | `396c93c0` | 3,148 | Menu/launch/binding owners wired; 1,106 focused pass / 2 historical failures. No new analyzer diagnostics. Full-suite gate 1 comparison PASS: 10,294 pass / 20 fail / 29 err / 20 skip; same baseline identities and skips, 3 new passing tests. |

## Found, not fixed

- `test/profiles/profiles_hub_test.dart`, `settle` / disable-profile test: under full-suite load the disabled badge can miss the six 50 ms real-I/O windows. Gate-1 first attempt failed this unchanged test; isolated run passed all 5 and the same-SDK/configuration full rerun passed the baseline comparison. No allowlist or application change. Evidence: `<E>/tps/gate1-first.jsonl`, `gate1-profile-check.jsonl`, `gate1.jsonl`.

### Retained oversized service and structural exceptions

- `lib/services/torrent_playback_service.dart` remains oversized during steps
  1–4 to preserve usable checkpoints. Remaining responsibilities follow the
  inventory above; step 5 reduces it to a forwarding facade at most 400 lines.
- `presentation/legacy_playback/` retains existing service orchestration and
  unchanged legacy user-facing text. After this plan, move service calls behind
  Sources data contracts, dissolve the bridge folder, and migrate the retained
  text through the app localization infrastructure.
- The final service facade is temporary: repoint its production callers to the
  Sources bridges and delete it in the subsequent playback migration.

### Step 1 evidence and ownership

- New owners: `application/source_candidate_ranking.dart`,
  `source_search_plans.dart`, `source_iptv_availability.dart`,
  `source_filter_ladder.dart`, `source_probing.dart`,
  `source_candidate_checks.dart`, `source_provider_config.dart`,
  `source_curation.dart`, `source_cache_ordering.dart`;
  `models/resolved_source.dart` and `models/playback_cancel_token.dart`.
- The provider configuration dependency closure (`_configuredProviders`,
  `_isConfigured`, `_effectiveFetchProvider`) moved in step 1 with the default
  provider selector, avoiding application-to-presentation/facade calls.
- Alias cache and single-flight warm-up remain process-wide statics owned by
  `SourceCandidateRanking`; the no-pack memory stays with the retained
  selection pipeline until step 4. Captured profile owners and guards remain
  unchanged. The cancellation flag remains action-owned.
- Original `@visibleForTesting` annotations move intact. Existing production
  calls that crossed a library boundary receive a call-site-only
  `invalid_use_of_visible_for_testing_member` ignore; this preserves the
  annotation without adding warnings for previously internal calls.
- Evidence: `<E>/tps/step1.jsonl`, `analyze-step1.txt`, `mapping.json`, and
  syntax-token comparison against the untouched `original.dart`. Test names
  remain unchanged. No runtime behavior changes or new dependency versions.

### Step 2 evidence

- Search owners: `data/series_pack_search.dart`, `iptv_quick_play_search.dart`,
  `curated_source_search.dart`, `recovery_source_resolution.dart`. Fetcher
  owners: `source_series_fetcher.dart`, `source_movie_fetcher.dart`,
  `source_engine_fetchers.dart`. Each is under 500 lines after formatting.
- Production fetch/recovery callers retain forwarding APIs. Repointed tests
  keep their original identities; the recovery source guard now reads its
  actual data owner and checks the same one-attempt probe contract.
- Evidence: `<E>/tps/step2.jsonl`, `analyze-step2.txt`, and verbatim syntax-token
  comparison for all 119 original static members. No new diagnostics or test
  failures; the four historical source-contract failures remain.

- Formatting longer qualified calls exposes six new curly-brace lint reports
  on unchanged single-statement guards in the recovery and fetcher owners.
  Line-specific ignores preserve their original tokens. Review and add braces
  in the subsequent control-flow refactor; the existing baseline curly-brace
  diagnostics remain measured.

### Step 3 evidence

- Menu, ZIP/provider actions, provider choice, loading overlays, binding,
  player arguments, launch, next-episode handoff, and DeoVR moved together
  into 11 cohesive legacy presentation bridges, all under 500 lines.
- Required DeoVR extraction: `data/deovr_json_upload.dart`. Three new tests
  under `test/features/sources/data/` verify the unchanged request, location
  URL, and original status/header errors using a scoped HTTP fake. The existing
  CI directory entry includes these tests.
- The two saved-source guards are ported to their actual new owners and
  explicitly cover all four existing routes (including media servers). Their
  stale three-route assumption is corrected; every per-route assertion remains.
  Both now pass and are removed from the CI historical-failure list.
- Evidence: `<E>/tps/step3-final.jsonl` (comparison PASS), `analyze-step3.txt`
  (836 diagnostics, none added), verbatim comparison for all 119 members.
  Temporary facade cross-calls are presentation-only and retire in step 4.

- Gate 1 local CI commands: formatting 988 files unchanged; scoped analyzer passed with 5 baseline infos. Gate run revision `396c93c0`; private CI verification follows the evidence commit.

### Step 4 pipeline checkpoints

- `playBest` → `presentation/legacy_playback/automatic_play_best.dart`
  (739 lines including imports/comments). Whole method retained. Temporary
  size exception: split the method in the next playback control-flow refactor.
  Focused suite 1,106 pass / same 2 baseline failures; no new diagnostics;
  verbatim comparison and size/import guards pass. Evidence:
  `<E>/tps/step4-best.jsonl`, `analyze-step4-best.txt`.

- `playFromSelection` and its no-pack memory →
  `presentation/legacy_playback/automatic_play_selection.dart` (788 lines).
  `_noPackUntil` remains process-wide static state with the original key and
  TTL. Whole method retained; split the method in the subsequent playback
  refactor. Two formatting-exposed single-statement guards receive the same
  line-specific curly-brace exception as step 2. Focused suite 1,106 pass /
  same 2 failures, no new diagnostics, verbatim and guard checks pass.
  Evidence: `<E>/tps/step4-selection.jsonl`, `analyze-step4-selection.txt`.

- `_playAddonStream` → `presentation/legacy_playback/addon_stream_playback.dart`
  (482 lines). Whole method retained; split in the subsequent playback refactor.
  One additional formatting-exposed guard gets a line-specific curly-brace
  exception. Focused suite 1,106 pass / same 2 failures, no new diagnostics,
  verbatim and guard checks pass. Evidence: `<E>/tps/step4-addon.jsonl`,
  `analyze-step4-addon.txt`. Gate 1 private CI run `36840285688` passed all
  three jobs at `4c9aa004` (confirmed through GitHub).

- `_playViaBound` and its resolution helpers →
  `presentation/legacy_playback/bound_source_playback.dart` (665 lines) and
  `bound_source_resolution.dart` (233 lines). Whole pipeline retained; split
  the method in the subsequent playback refactor. One formatting-exposed
  guard receives the scoped curly-brace exception. Source-text guards read
  this owner and tolerate formatted argument whitespace while retaining
  preferred-provider checks. Focused suite 1,106 pass / same 2 failures,
  no new diagnostics; verbatim and guards pass. Evidence:
  `<E>/tps/step4-bound-final.jsonl`, `analyze-step4-bound.txt`.
- Accidental player-screen lint/import cleanup and its three-line size ratchet
  were restored to the original; that screen has no final diff. Cleanup is
  restricted to the migrated source set and affected tests. All original
  analyzer diagnostics are again measured (836, none added).

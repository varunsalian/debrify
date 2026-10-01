# Torrent playback service refactor — plan

Written 2026-10-01 on `refactor/search-screen` at `1d6fa710`. Follow
[AGENTS.md](../../AGENTS.md). This page plus AGENTS.md is everything the
executing agent needs; the search-screen plans are history and need not be
read.

Work on a new branch `refactor/torrent-playback` created from
`refactor/search-screen`. Commit after every step (more often is fine). Never
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
| 106–494 | Shared state and the manual entry point | `_cancelled`, `_noPackUntil`, `_recentlyNoPack`, `_markNoPack`, `activateTorrent` (320 lines) | `activateTorrent` yes | `_cancelled` → step 1; no-pack memory with `playFromSelection`; `activateTorrent` → `presentation/manual_source_activation.dart` |
| 495–1178 | Automatic "play best" | `playBest` (680 lines; `playDirect` and `playFirstAliveDirect` are closures inside it), `_isDirectCandidate` | yes | `presentation/automatic_play_best.dart` |
| 1179–1432 | Probing and pack safety | `selectDirect`, `probeAttemptCount`, `packTopSafety`, `_packCoverageTypes`, `_probeCandidates`, `cleanupFailedAutomaticAcquisition` | **no** | `application/source_probing.dart` |
| 1433–2150 | Quick play from a selection | `playFromSelection`, `tryPackRoute`, ladder fallbacks; `loadLadder`, `ladderNote`, `_applyLadderNote` | yes, except the ladder helpers | `presentation/automatic_play_selection.dart`; `loadLadder`/`ladderNote` → `application/` |
| 2151–2555 | Ranking and search plans | `orderCandidatesForRules`, `_qualityScore`, `prefersTorrentCandidates`, `mergePreparedTorrentOrder`, alias warm-up/cache, `orderCacheCheckedCandidatesForRules`, `directValidationBudgetForRules`, `shouldPreflightDirectStream`, `shouldTryDirectBeforeTorrent`, `isAutoPlayableCandidate`, `confirmDeferredIptvAvailability`, `shouldSearchAddonsBeforeProvider`, `allowsAddonSearch`, `addonStreamSearchPlan`, `packSearchReportedErrors` | no | `application/source_candidate_ranking.dart`, `application/source_search_plans.dart` |
| 2556–3174 | Source searches | `searchSeriesPackSources`, `seriesPackSearchPlan`, `iptvQuickPlaySearchTimeout`, `searchIptvForQuickPlay`, `_originEpisodeVideoId`, `searchCuratedSources`, `prepareRecoverySources`, `resolveRecoverySource` | no | `data/series_pack_search.dart`, `data/iptv_quick_play_search.dart`, `data/curated_source_search.dart`, `data/recovery_source_resolution.dart` |
| 3175–3953 | Fetchers and curation | `seriesFetcherFor`, `movieFetcherFor`, `_fetchOneEngine`, `_fetchMediaServerSources`, `_mediaServerSourceRefs`, `_sourceEngineListing`, `_effectiveFetchProvider`, `_curateCandidates`, `_curatePackCandidates`, `earlyDirectCandidate`, `earlyDirectRecovery`, `leadingDirectAddonKey`, `directSearchErrors` | no | `data/source_fetchers.dart`, `application/source_curation.dart` |
| 3954–4373 | Addon-stream playback | `_playAddonStream` | yes | `presentation/addon_stream_playback.dart` |
| 4374–5267 | Bound-source playback | `_bindingMatchesMeta`, `_providerFromStored`, `storedProviderKey`, `_boundProviderSupported`, `_resolveLocalBound`, `_resolveProviderNativeBound`, `_seLabel`, `_resolvedHasEpisode`, `_torrentFromSource`, `_playViaBound` | yes, except the step 1 helpers under "Dependency order" | `presentation/bound_source_playback.dart`, `presentation/bound_source_resolution.dart` |
| 5268–5470 | Binding | `_recoverAfterBoundStartupFailure`, `bindSource`, `bindDirectSource`, `bindIptvSource`, `bindLocalSource` | yes | `presentation/source_binding_actions.dart` |
| 5471–6031 | Acquire and launch | `_add`, `_play`, `_advanceToNextEpisode`, `_playerArgs`, `playerArgsForTesting`, `_configuredProviders`, `_defaultConfiguredProvider`, `_lazyProviderResolver`, `_launch` | `_add` and the provider helpers **no**; the rest yes | `_add` → `application/source_probing.dart`; provider helpers → `application/source_provider_config.dart`; the rest → `presentation/source_player_launch.dart` |
| 6032–7075 | Provider action menu | `_launchWithDeoVR`, `_directValidationKey`, `supportsDirectStreamDownload`, `downloadDirectStream` (calls the existing `downloadSource`), `_acceptedProviderAction`, `_download`, `_addToPlaylist`, `_showChooser`, TorBox/Premiumize ZIP and transfer, `_handleNotCached`, `_pickProvider`, `_isConfigured`, `_cacheFirst`, `_hasAcquisition`, `_label`, `_showPipeline`, `showResolvingOverlay`, `_showLoading`, `_snack` (the class's single `_snack`), `_resolverFor`, `_validatedLaunchCommitter`, `_lazySourceCommitter`, `_postAction` | yes, except the step 1 helpers under "Dependency order" | `presentation/provider_action_menu.dart`, `presentation/provider_zip_actions.dart`, `presentation/source_loading_overlays.dart`, `presentation/deovr_launch.dart` |
| 7076–7103 | Private types | `_Resolved`, `_PlaybackCancelToken` | no | `models/resolved_source.dart`, `models/playback_cancel_token.dart` |

The file names are suggestions. Keep each new file under 500 lines (prefer
300) with one responsibility, and split further where needed. Before moving
anything into `application/`, `data/` or `models/`, confirm it uses no
`BuildContext`, widget or dialog. If it does, it belongs in `presentation/`.

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
dropped and the comment `// TEMP(tps): moves in step N` on the member. Step 5
removes every one: `grep -rn "TEMP(tps)" lib` must be empty when you finish.

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
| 3 | `presentation/`: menu, overlays, DeoVR, launch and binding (5268–7075, minus anything moved in step 1). Several commits are fine. | Keep every `context.mounted`/`isCurrent` gate and `_acceptedProviderAction` exactly as they are. **Full-suite gate 1** after this step. |
| 4 | `presentation/`: the pipelines. `playBest`, `playFromSelection`, `_playAddonStream`, `_playViaBound` with its helpers, `activateTorrent`, and the no-pack memory. | One pipeline per commit. |
| 5 | Facade, guards, CI, then **full-suite gate 2**. | See "Definition of done". |

### Step 0 — baseline

The accepted full-suite baseline is `.git/refactor-evidence/finish/bugfixes.jsonl`:
10,289 pass / 22 fail / 29 err / 20 skip at `1d6fa710`. Later commits touch no
Dart, so don't rerun it. Record the whole-repo analyzer:
`flutter analyze > .git/refactor-evidence/tps/analyze-gate0.txt` (create the
folder). That is all of step 0.

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

**Full-suite gates.** Run `python3 .git/refactor-evidence/run_full.py tps/gate1`
(later `tps/gate2`), then
`python3 .git/refactor-evidence/compare.py --against .git/refactor-evidence/finish/bugfixes.jsonl <run>.jsonl`.
`compare.py` decides: no new failures, no missing tests, no new skips. Show
that each renamed or repointed test identity is present with the same
outcome.

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
     `presentation/`.
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
   - `file_size_baseline.txt` holds the service's lowered count.
   - `grep -rn "TEMP(tps)" lib` is empty.
5. CI runs on the branch: `checks.yml` already covers `refactor/**` and
   `lib/features`.
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
| 0 | | 7,103 | |

## Found, not fixed

(none yet)

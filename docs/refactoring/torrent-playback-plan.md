# Torrent playback service refactor — plan

Written 2026-10-01 on `refactor/search-screen` at `1d6fa710`. Follow
[AGENTS.md](../../AGENTS.md). This page plus AGENTS.md is everything the
executing agent needs; the search-screen plans are history and need not be
read.

Work on a new branch `refactor/torrent-playback` created from
`refactor/search-screen`. Commit after every step. Never push to `origin`;
push to `private` only if the goal you were given says so.

## Goal

`lib/services/torrent_playback_service.dart` is 7,103 lines: one static class
`TorrentPlaybackService` (~110 static methods) plus `_Resolved` and
`_PlaybackCancelToken`. It picks, searches, ranks, acquires, binds and launches
sources for every play button in the app. Split it into the Sources feature by
responsibility, **moving code verbatim**, and leave a small facade.

## What it contains (line numbers at `1d6fa710`)

| Lines | Area | Key symbols | UI? | Destination under `lib/features/sources/` |
| --- | --- | --- | --- | --- |
| 106–495 | Shared state and small helpers | `_cancelled`, `_noPackUntil`, `_markNoPack`, `_recentlyNoPack`, `logSourceSelection`, `_lazyProviderResolver`, `_defaultConfiguredProvider`, `_snack` | some | Split by owner, below; see step 1 |
| 495–1432 | Automatic "play best" | `playBest`, `playDirect`, `playFirstAliveDirect`, `_pickProvider`, `probeAttemptCount`, `cleanupFailedAutomaticAcquisition`, pack-coverage helpers | yes | `presentation/automatic_play_best.dart` |
| 1433–2150 | Quick play from a selection | `playFromSelection`, `tryPackRoute`, ladder fallbacks, `loadLadder`, `ladderNote`, `_applyLadderNote` | yes | `presentation/automatic_play_selection.dart`; `ladderNote` is pure → `application/` |
| 2151–2555 | Candidate ranking and search plans (pure) | `orderCandidatesForRules`, `_qualityScore`, `prefersTorrentCandidates`, `mergePreparedTorrentOrder`, source alias warm-up/cache, `orderCacheCheckedCandidatesForRules`, `directValidationBudgetForRules`, `shouldPreflightDirectStream`, `shouldTryDirectBeforeTorrent`, `isAutoPlayableCandidate`, `confirmDeferredIptvAvailability`, `shouldSearchAddonsBeforeProvider`, `allowsAddonSearch`, `addonStreamSearchPlan`, `packSearchReportedErrors` | no | `application/source_candidate_ranking.dart`, `application/source_search_plans.dart` |
| 2556–3175 | Source searches | `searchSeriesPackSources`, `seriesPackSearchPlan`, `searchIptvForQuickPlay`, `searchCuratedSources`, `prepareRecoverySources`, `resolveRecoverySource` | no | `data/series_pack_search.dart`, `data/iptv_quick_play_search.dart`, `data/curated_source_search.dart`, `data/recovery_source_resolution.dart` |
| 3175–3953 | Episode/movie fetchers and curation | `seriesFetcherFor`, `movieFetcherFor`, `_fetchOneEngine`, `_fetchMediaServerSources`, `_mediaServerSourceRefs`, `_sourceEngineListing`, `_curateCandidates`, `_curatePackCandidates`, `earlyDirectCandidate`, `leadingDirectAddonKey`, `directSearchErrors` | no | `data/source_fetchers.dart`, `application/source_curation.dart` |
| 3954–4669 | Addon-stream playback | `_playAddonStream` and its helpers | yes | `presentation/addon_stream_playback.dart` |
| 4670–5267 | Bound-source playback | `_playViaBound`, `_torrentFromSource` | yes | `presentation/bound_source_playback.dart` |
| 5268–5470 | Binding | `_recoverAfterBoundStartupFailure`, `bindSource`, `bindDirectSource`, `bindIptvSource`, `bindLocalSource` | context | `presentation/source_binding_actions.dart` |
| 5471–6031 | Acquire and launch | `_add`, `_play`, `_advanceToNextEpisode`, `_playerArgs`, `playerArgsForTesting`, `_launch` | yes | `presentation/source_player_launch.dart` |
| 6032–7075 | Provider action menu | `_launchWithDeoVR`, `_showChooser`, `_download`, `downloadSource`, `supportsDirectStreamDownload`, `downloadDirectStream`, `showResolvingOverlay`, `_addToPlaylist`, `_acceptedProviderAction`, TorBox/Premiumize ZIP and transfer, `_handleNotCached`, `_cacheFirst`, `_isConfigured`, `_label`, `_showPipeline`, `_showLoading` | yes | `presentation/provider_action_menu.dart`, `presentation/provider_zip_actions.dart`, `presentation/source_loading_overlays.dart`, `presentation/deovr_launch.dart` |
| 7076–7103 | Private types | `_Resolved`, `_PlaybackCancelToken` | no | `models/resolved_source.dart`, `models/playback_cancel_token.dart` |

Lines 2151–3953 never touch a `BuildContext` or UI. The names in the table
are suggestions: keep each new file under 500 lines (prefer 300) and one
responsibility; split further where a file would pass that. If a "no UI"
function turns out to need a `BuildContext`, it belongs in `presentation/`.

**Callers today:** 8 production files (Home catalog play, Sources bridges,
the search screen composition, `video_player_launcher.dart`,
`series_source_fetcher.dart`, `storage_service.dart`) and 26 test files.

## Invariants (every step)

1. Play buttons, Quick Play, source tabs, bound sources and recovery choose the
   same sources in the same order with the same filter-ladder notes, timeouts,
   probe counts and fallbacks.
2. Profile ownership is unchanged: captured owners, `canContinue`/`isCurrent`
   guards, retirement cleanup (fresh Real-Debrid torrent removal, PikPak and
   rejected-source cleanup) and the provider-action rule that an accepted
   action finishes after the screen closes.
3. Loading dialogs, pipeline overlays, snackbars, chooser sheets, route pops and
   player launch keep their order, text and dismissal. No player-engine or
   native-bridge payload change (headers, subtitle/audio settings, DeoVR).
4. Static state keeps its lifetime. `_noPackUntil` (no-pack memory) and the
   source alias cache/warm-up are process-wide statics today; move each with
   its single owner, keep it static, and do not make it profile-scoped in this
   refactor. Record that classification in Progress.
5. No Riverpod, providers or new DI here: this is service and bridge code with
   no new consumer. Plain functions and small classes only.

## Technique: move-only

- Move method bodies **verbatim** into top-level functions or small `final`
  classes with static members in the new file.
- **Allowed edits:**
  - drop the leading `_` when a symbol is now used from another file
    (`_Resolved` → `ResolvedSource`, `_PlaybackCancelToken` →
    `PlaybackCancelToken`, `_snack` → a shared helper);
  - change call sites to the new owner;
  - change imports;
  - add a `// Moved from TorrentPlaybackService.<name>.` doc line where it
    helps.
- **Not allowed:**
  - reordering awaits or guards;
  - merging duplicate helpers that differ in any detail;
  - splitting the 400–680-line methods (`playBest`, `playFromSelection`,
    `_playViaBound`, `_playAddonStream`). They move whole, one per file.
    Splitting them changes control flow and is a separate later change.
- `@visibleForTesting` members move with their code. Repoint their tests
  (import and qualifier only). Do not keep forwarding members on the facade
  just for tests.
- Dependencies between new files go `presentation → application/data →
  models`. `data/` and `application/` must not import Flutter widgets or
  take a `BuildContext`.

## Steps (least coupled first)

| # | Move | Notes |
| --- | --- | --- |
| 0 | Baseline | See below. |
| 1 | Private types → `models/`; pure ranking, search plans, ladder note, curation helpers → `application/` (2151–2555, the pure parts of 3739–3953, `ladderNote`) | No UI. Heaviest test repointing (`orderCandidatesForRules` and friends). |
| 2 | Source searches and fetchers → `data/` (2556–3740) | `seriesFetcherFor` is used by `series_source_fetcher.dart`; keep it reachable through the facade or repoint that caller. |
| 3 | Provider action menu, loading overlays, DeoVR → `presentation/` (6032–7075) | Keep `_acceptedProviderAction` semantics and every `context.mounted`/`isCurrent` gate exactly. **Full-suite gate 1** after this step. |
| 4 | Acquire/launch and binding → `presentation/` (5268–6031) | `_play`, `_launch`, `_playerArgs` are shared by every pipeline; move them before step 5. |
| 5 | Pipelines → `presentation/`: `playBest`, `playFromSelection`, `_playAddonStream`, `_playViaBound`, each in its own file, plus `activateTorrent` and no-pack memory | Largest moves; do one pipeline per commit. |
| 6 | Facade, guards, CI | See "Definition of done". **Full-suite gate 2.** |

### Step 0 — baseline

The accepted full-suite baseline is `.git/refactor-evidence/finish/bugfixes.jsonl`:
10,289 pass / 22 fail / 29 err / 20 skip at `1d6fa710`. Commits since then
touch no Dart, so do not rerun it. Record the whole-repo analyzer:
`flutter analyze > .git/refactor-evidence/tps/analyze-gate0.txt` (create the
folder). That is the only step 0 work.

### Per step

1. Move the code and fix call sites until `flutter analyze` on the touched
   files reports nothing new. A shifted line number is not a new diagnostic;
   compare rule, symbol and message.
2. Run `dart format` on the changed files only. Do not reformat untouched
   regions of `torrent_playback_service.dart`: it has pre-existing unformatted
   code. Format only the hunks you changed.
3. Run `python3 dev/tool/check_search_architecture.py` and
   `python3 dev/tool/check_file_sizes.py`. When the service shrinks, run
   `check_file_sizes.py --update` and commit the lowered baseline.
4. Run the affected tests: `test/features/sources` plus every test file that
   imports `torrent_playback_service.dart` or a file you created
   (`grep -rl`). Compare failures with the baseline by test name.
5. Commit: `refactor: move <area> out of TorrentPlaybackService`.

Full-suite gates: `python3 .git/refactor-evidence/run_full.py tps/gate1` (and
`tps/gate2`), then
`python3 .git/refactor-evidence/compare.py --against .git/refactor-evidence/finish/bugfixes.jsonl <run>.jsonl`.
The verdict is `compare.py`: no new failures, no missing tests, no new skips.
Renamed or repointed test identities must each be shown present with the same
outcome.

### Source-text tests

`test/manual_source_validation_contract_test.dart`,
`test/media_server_service_test.dart` and `test/filter_ladder_test.dart` read
this file's source text.
- Point each guard at the file its code moved to, keeping its purpose; or
  replace it with an executable test.
- Never delete an assertion to make a move pass.
- Four contract tests already fail at baseline: "recovery uses automatic
  probes…", "every saved-source launch…", "bound startup recovery…" and
  "delayed startup recovery…". They must not newly pass by deletion. Leave
  them failing unless the guard is genuinely ported.

## Definition of done

1. `torrent_playback_service.dart` is a facade of **at most 400 lines**. It
   holds only members with a production caller, each forwarding to its new
   owner. At `1d6fa710` those are 14:
   - `activateTorrent`, `playFromSelection`, `showResolvingOverlay`
   - `bindSource`, `bindDirectSource`, `bindIptvSource`
   - `downloadDirectStream`, `supportsDirectStreamDownload`
   - `seriesFetcherFor`, `prepareRecoverySources`, `resolveRecoverySource`
   - `loadLadder`, `directValidationBudgetForRules`,
     `shouldPreflightDirectStream`

   Find them with
   `grep -rhoE "TorrentPlaybackService\.[a-zA-Z]+" lib | sort -u`. Repointing a
   caller and removing its facade entry is also fine.
2. Every new file is at most 500 lines, except the four pipeline files, which
   may reach 800 while their method moves whole. Record those four as
   temporary exceptions in Progress, with "split the method" as their exit
   milestone.
3. No new analyzer diagnostics (whole repo, compared with `analyze-gate0.txt`).
   Gate 2 is clean against `bugfixes.jsonl` and `tps/gate1.jsonl`. Both
   guard scripts pass. `file_size_baseline.txt` has the service's lowered
   count.
4. CI (`.github/workflows/checks.yml`) runs on `refactor/**` pushes. Add the
   new Sources files to its scoped `dart format`/`flutter analyze` step only if
   they are not already covered (`lib/features` is).
5. Stop after gate 2 and report. The user has Claude review
   `<step 0 commit>..HEAD` before anything is merged.

## Explicitly not in scope

- Splitting `playBest`, `playFromSelection`, `_playViaBound` and
  `_playAddonStream` into smaller methods.
- Making the no-pack memory or the alias cache profile-scoped.
- Any behaviour change, bug fix or provider change. If you find a bug, add it
  to "Found, not fixed" with file, symbol and a one-line repro.
- Other large files (`storage_service.dart`, the player screens).

## Progress

| Step | Commit | Service lines | Result |
| --- | --- | --- | --- |
| 0 | | 7,103 | |

## Found, not fixed

(none yet)

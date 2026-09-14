# Metadata integration audit — 2026-09-08

Six requested review/fix passes completed against the current worktree. All
changes remain uncommitted. No AGENTS.md was found in the repository.

## Confirmed issues fixed

1. **Continue Watching artwork provenance.** Classic/stage cards used an episode
   label as evidence of an episode still and skipped selected backdrop metadata.
   Caller tracing showed these paths currently pass show/derived artwork through
   `_stageCardArt` and `_titleArtUrl`, never an episode still. Removed that label
   exception and centralized their primary/error artwork policy. Collection
   covers retain their independent user-artwork behaviour.
2. **Image-error fallback.** Classic/stage title cards could restore a poster
   after an explicitly selected backdrop failed. Their error path now respects
   fallback-off. Spotlight's actual episode-still error path also respects an
   explicit episode-artwork selection; changing backdrop providers alone does
   not alter the independent episode-artwork behaviour.
3. **Spotlight navigation baseline.** Keyboard, compact tap/button and wide tap
   now open the original catalog item, while the hero still renders presentation
   metadata. This prevents a subsequent detail reset from retaining old overlays.
4. **Recommendation navigation baseline.** Both detail hosts rendered overlaid
   recommendation batches and passed those overlays into new detail pages. They
   now retain identity-keyed original references for opening. Each batch entry
   maps to its source entry, preserving duplicate IDs from different sources.
5. **Open settings after sync.** Metadata settings did not observe external
   metadata revisions and could overwrite synced choices on the next edit. It
   now reloads on revisions and guards edits while the loaded revision is stale.
6. **Remaining background error boundaries.** Hero trailer and detail trailer
   startup perform additional asynchronous work after loading metadata settings.
   Full background attempts now contain failures and clear loading state only
   for their current request. Hero enrichment checks relevance before starting
   delayed work and passes it through to provider requests.

## Six review passes

- [x] **1 — Provider policy and presentation.** Inspected the provider model and
  overlays, catalog tiles, classic/stage/Spotlight cards and heroes, both detail
  hosts, shared detail layouts, episode overlays, and Discover publication.
  Checked current defaults, independent categories, missing fields, image errors,
  required title fallback and IMDb rating provenance. Fixed issues 1–2.
- [x] **2 — Navigation and identity.** Traced all Spotlight open gestures, both
  recommendation hosts, ordinary catalog callbacks, franchise/Explore navigation
  and deferred native-ID resolution. Fixed issues 3–4. Caller widget tests verify
  original object identity, not only equal IDs or displayed text.
- [x] **3 — Async lifecycle.** Inspected presentation generations, item/profile/
  revision invalidation, hero debounce/trailer timers, detail trailer setup,
  Explore and franchise loads, episode-generation guards, and ambient probes.
  Fixed issue 6. Existing native-route and stale-result guards remain intact.
- [x] **4 — Persistence and settings.** Inspected profile facade reads/writes,
  preferences normalization, canonical sanitized export validation, settings
  dialog/save sequencing and sync authorization/revision notifications. Fixed
  issue 5. External-change-then-edit test verifies unrelated synced fields survive.
- [x] **5 — Providers and networking.** Inspected exact ID resolution, addon
  configuration identity, language/cache keys, response/queue/cache limits,
  client ownership and bounded retries, DNS/TLS cancellation, malformed payload
  handling, episode-coordinate preservation and Discover pagination/filtering.
  Relevant repository, TLS, profile, episode and cache tests passed. No additional
  confirmed provider/network regression was found in this pass.
- [x] **6 — Final integration.** Ran the combined 56-file regression selection,
  analyzed all 64 changed/new Dart files, built macOS release, inspected the final
  diff, and scanned task sources for credential patterns and exposed env files.

## Verification evidence

- Final combined run: **1,639 passed; one pre-existing test failure**.
  `/tmp/debrify-audit-final-tests.log`;
  exact file selection: `/tmp/debrify-audit-test-files.txt`.
- The failure is `detail_theme_test.dart`'s colour-literal guard against white
  ink in `_DetailHoldHintPill`, an intentionally dark floating hint. Both the
  test file and `detail_episode_cells.dart` are byte-for-byte identical to HEAD.
  The guard was not weakened and the unrelated widget was not changed.
- Targeted navigation/stage run: 48 passed. Recommendation baseline caller
  widgets: 2 passed. Settings/portability/sync run: 32 passed. Repository,
  transport, lifecycle and settings run: 35 passed. These overlap with the
  final suite and must not be added to its count.
- Final analysis: no errors, no diagnostics on newly changed source lines.
  The unused `_plateFill` warning and informational diagnostics predate this
  work (flagged source lines checked against HEAD).
  `/tmp/debrify-audit-final-analysis.log`.
- macOS release build succeeded: `debrify.app`, 153.7 MB.
  `/tmp/debrify-audit-final-build.log`.
- `git diff --check` passed. No JWT/GitHub-token pattern matches in task Dart
  files; no exposed untracked environment files. Nothing staged or committed.

## Verification limits

This audit includes automated touch/remote, layout, provider, lifecycle and
profile tests plus a macOS release build. It does not claim fresh physical-device
verification on every platform or live YouTube/provider-account testing. The
inherited colour-guard failure remains visible above. These results support the
specific reviewed paths and fixes, not a claim that no future issue is possible.


## Follow-up fixes — additional reviewer findings

The earlier passes missed the following integration cases; this follow-up does
not claim exhaustive coverage or physical-device verification.

- Removed the generic Home-settings listener from metadata presentation. Local
  addon/provider changes now emit the specific metadata revision; external sync
  and profile changes retain their existing invalidation. A mounted consumer
  test verifies that unrelated Home notifications do not reset presentation.
- Episode text/artwork changes, including policy reset, retain view generation.
  A mounted panel using actual addon metadata and layout-owned focus nodes
  preserves focus on episode 8 and a 600-pixel scroll position through repeated
  provider changes while its displayed thumbnail updates.
- Missing primary artwork now resolves to permitted fallback before rendering,
  in both search cards and Spotlight. Fallback-off remains authoritative.
- Sparse hero details merge over the catalog baseline before presentation.
  The search hero similarly includes host-enriched artwork, plot and runtime
  in its stable baseline; host-field changes invalidate that baseline.
- Preference decoding is memoized by the exact raw JSON and profile scope.
  Reads still consult the current profile facade, so external writes and
  malformed replacements cannot leave a stale parsed selection.
- IMDb enrichment and TMDB credits load concurrently, then apply the existing
  field/fallback policy. A delayed-IMDb test verifies early TMDB dispatch and
  preservation of the eventual IMDb rating.
- No-art ambient clearing is intentional when fallback is disabled. Exact
  duplicate ambient notifications are suppressed, while image publication
  remains immediate and a later usable tint can still update the shell.

Verification: the 58-file combined regression run passed 1,650 tests with the
same inherited color-guard failure documented above. Both files involved in
that failure remain byte-for-byte identical to HEAD. The final additional
hero/focus/ambient checks are recorded in `/tmp/debrify-metadata-last-tests.log`.
Targeted analysis reported no errors or warnings (20 existing informational
diagnostics). `git diff --check` passed. No commit, push, install or fresh native
release build was performed for this follow-up.

Logs: `/tmp/debrify-metadata-fix-full-tests.log`,
`/tmp/debrify-metadata-fix-analysis.log`;
file selection: `/tmp/debrify-metadata-fix-test-files.txt`.


## Final source-action and listener follow-up

Source-management callbacks and bound-source counts now use the original catalog
item in both classic and alternate detail layouts. Presentation metadata remains
for rendering. Two mounted detail tests cover the classic binding action and
both alternate-layout source actions; related navigation checks passed.

Removed EpisodesPanel's remaining generic Home-settings listener. The mounted
focus regression also verifies that unrelated Home changes retain the exact
presented episode list, focus, and scroll position. Metadata revision and profile
scope remain the episode-policy invalidation signals.

The reported enrichment-loss concern was not supported by caller tracing:
ratings and TVMaze backfills receive the same original season objects stored in
the baseline map, so their mutable fields are retained when policy allows them.

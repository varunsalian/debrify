# Debrify engineering practices

These rules describe the destination for new code and incremental refactoring of
project-owned Dart, native code, tests, and build configuration. Follow the user's
task and scope; these rules do not authorize unrelated rewrites or migrations.

The first migration is tracked in the [search-screen finish plan](docs/refactoring/search-screen-finish-plan.md),
which supersedes the original [search-screen plan](docs/refactoring/search-screen-plan.md).
Keep durable rules here and migration progress, evidence, and temporary exceptions
in the relevant plan. When sharing external URLs, show the complete URL.

## Refactoring approach

- Refactor one cohesive workflow/responsibility per reviewable batch, starting
  with low-risk work. Move related methods, state, and callers together; do not
  require a separate extraction, provider, commit, or review for every helper.
  Avoid redesigning unrelated subsystems together. Keep the app usable at batch
  checkpoints and stop dependent work on unexplained regressions.
- Preserve observable behavior: layouts, navigation, focus, ordering, timing,
  settings, profile ownership, provider behavior, and playback contracts.
  Separate intentional behavior changes and bug fixes from structural moves.
- Establish relevant baseline behavior before extraction. Reuse existing tests;
  add coverage for meaningful gaps at the boundary being changed.
- Extract, wire the actual production caller, verify, then remove the replaced
  implementation. Avoid long-lived duplicate implementations or unused scaffolds.
- Preserve working compatibility code until its purpose is understood. Document
  the condition it handles and how that behavior is verified.
- A new folder, smaller file, or renamed class is not sufficient progress: the
  extracted component must have a clear responsibility and explicit dependencies.
- Define each migration's completed source set and measurable acceptance criteria.
  Track every original responsibility to its replacement or evidenced removal.
  Moving code outside a feature folder does not remove it from the migration's
  size/boundary checks. Temporary structural exceptions must have an exit milestone
  and cannot silently become the completed architecture.

## Architecture and feature ownership

- Widgets own rendering, layout, animation, focus, and interaction dispatch.
  Application controllers own presentation state and action orchestration.
  Repositories/services own data access and business operations. New or migrated
  widgets must not directly query databases, make HTTP requests, write preferences,
  or invoke native services.
- Dependencies flow from presentation to application logic to data/platform
  contracts. Application and data code must not import screens, use `BuildContext`,
  show dialogs, or navigate. Riverpod notifiers may own application state;
  repositories, services, and business policies remain independent of UI and Riverpod.
- Organize migrated code under `lib/features/<feature>/`, using `presentation/`,
  `application/`, `data/`, and `models/` only when each is needed. Mirror those
  paths under `test/`. Use descriptive `lower_snake_case` filenames.
- Existing `screens/`, `services/`, `models/`, and `widgets/` may coexist during
  migration. Do not reorganize unrelated code to satisfy a directory convention.
- Share components only when there is demonstrated reuse. Keep shared design
  components in `lib/ui/core/` and genuinely shared infrastructure in `lib/core/`
  as needed. Do not build a catch-all utility or application-service directory.
- Shared infrastructure must not import feature implementations or UI. Access
  another feature through a small public contract, wired at the composition
  boundary; avoid circular dependencies and imports of private implementations.
- Composition/provider factories may import concrete data adapters to wire them;
  controllers depend on their narrow contracts. Keep those factories identifiable
  and small. A legacy playback entry point requiring `BuildContext` belongs behind
  a named presentation bridge, not a data adapter that secretly performs UI work.
  New persistence and business decisions must remain outside that bridge.
- Use Riverpod (`flutter_riverpod`) as the standard DI and application-state
  library for new/migrated features. Keep provider declarations with their feature
  and establish `ProviderScope` at app composition when introducing the first
  consumer. Avoid one giant registration file or a global mutable `ProviderContainer`.
  Declare providers statically, not inside widget builds or controller instances.
  Keep the app scope above the Navigator used by its consuming routes/dialogs.
- Use Riverpod `Provider` for dependencies, `NotifierProvider` for synchronous
  state/actions, and `AsyncNotifierProvider` when asynchronous state warrants it.
  Use `FutureProvider`/`StreamProvider` for suitable read-only data. Views consume
  state through `Consumer`/`ConsumerWidget` and narrow subscriptions as appropriate.
- Application notifiers and provider factories may use `Ref` to resolve declared
  dependencies. Pass ordinary constructor arguments into repositories, services,
  and policies; do not pass them `Ref`, containers, or `BuildContext`. Existing
  global services may sit behind injected adapters while callers migrate.
- Declare app, profile/session, and screen lifetimes explicitly. Use stable typed
  family keys containing profile/session and view/query identity where relevant;
  keys need stable equality. A nested scope or automatic disposal alone does not
  establish profile isolation. Invalidate outgoing work and retained private state
  during the existing profile handoff; do not leak snapshots across tab variants.
  Independent route instances must not share mutable workflow state merely because
  they show the same title/query; read-only cached data may still be shared safely.
- Choose automatic disposal and retention deliberately. Use `ref.onDispose` for
  owned cleanup/cancellation; borrowed services keep their original owner. Do not
  mutate other providers during disposal. Keep ordered asynchronous player teardown
  in its lifecycle coordinator; provider disposal does not await that protocol.
- Start writes, downloads, and playback from explicit actions, not provider
  initialization/recomputation. Dispatch navigation/dialog effects once per accepted
  action; a rebuild, re-listen, or invalidation must not replay the side effect.
  Keep this as ordinary action handling rather than introducing a generic event bus.
- Preserve initialization timing, refresh rules, retries, and route/tab behavior.
  When using Riverpod 3, disable its automatic retries for migrated operations
  initially so existing services remain the retry owner; verify out-of-view listener
  pausing and retained state. Do not let framework defaults silently change behavior.
- Keep one source of truth for each state and make its lifetime explicit. Derive
  filtered lists and display values where practical. Avoid copying the same state
  into a screen, controller, and native player with competing owners.
- Keep models strongly typed and immutable at component boundaries. Confine raw
  JSON and `dynamic` to validated integration boundaries. Do not change persisted
  formats merely to introduce a new Dart model.
- When reusing mutable legacy models, publish immutable snapshots or deliberate
  revision-bearing state at the boundary. Verify an in-place legacy update still
  notifies consumers; do not mutate an object already published as Riverpod state.
- Keep local widget state local and pure policies as simple functions. Preserve
  existing notifier-based services behind narrow adapters where useful; do not
  create competing state owners. New feature state uses Riverpod. Introduce
  interfaces for real boundaries, not an interface and use case for every method.
- Start with manually declared Riverpod providers. Code generation is optional
  and needs a demonstrated benefit; do not add a generator pipeline by default.
  Add a compatible stable dependency with the first production integration and
  commit the resolved lockfile without unrelated upgrades. Do not use the existing
  `provider` package for new feature DI or add another DI system, router, or storage
  framework as part of this decision.

## File and class size

Count physical lines after normal formatting, including imports, comments, and
blank lines, for handwritten application code in Dart and native languages.

| Lines | Policy |
| --- | --- |
| Up to 300 | Preferred; shorter cohesive files are welcome. |
| 301–500 | Acceptable with one clear responsibility. |
| 501–800 | Review responsibilities and extract independent components where useful. |
| Over 800 | Split before completing new/extracted code, or document a concrete exception. |

- Review class size and dependencies as well as file size. Do not replace a giant
  screen with a giant controller, expose its entire state to children, or split it
  into tightly coupled fragments. Do not use `part` files, mixins, compressed
  formatting, or deleted comments to evade the limits.
- Existing oversized files may shrink across multiple changes. Before editing
  one during a planned refactor, record its path, reason for temporary retention,
  remaining responsibilities, and extraction milestone in the plan. Do not require
  an unrelated whole-file rewrite for a small fix; record the exception and scope.
- New/extracted code follows the thresholds immediately unless specifically
  documented otherwise. Reassess exceptions when extending the affected component;
  exceptions are not permission for unlimited growth.
- Generated code, third-party vendor sources, localization resources, documentation,
  and fixtures are exempt from numeric limits. Organize test code by behavior and
  scenario; it still needs clear responsibilities. Extracted original application
  code is not vendor code and does not gain an automatic exemption.

## Profiles, asynchronous work, and resources

- Classify state, persistent data, settings, caches, and operations as device-wide,
  profile-owned, or explicitly shared. Pass profile context into owned operations;
  include profile/source identity in relevant queries and cache keys.
- Capture originating profile/session and request identity before asynchronous
  work. Reject stale results after query changes, profile switches, cancellation,
  or disposal. `mounted` alone does not establish that a result is still current.
- A profile-keyed Riverpod state does not make a legacy storage call profile-safe.
  Preserve existing captured-scope/write guards through adapters and verify actual
  writes, not just visible results, during profile switching. Reject stale actions
  before invoking an API that would resolve the newly active profile implicitly.
- For Riverpod actions, `ref.mounted` alone is insufficient too: two actions can
  race within one live notifier. Preserve request generations or cancellation and
  test that an old action cannot publish state or clear a newer action's loading flag.
- Delayed saves must target their originating profile and must not recreate data
  for deleted profiles. Enforce access rules in operation/data boundaries too.
- Treat profile switching as an ordered handoff: settle or cancel outgoing work,
  handle playback/progress, release owned state, then expose incoming state.
- Keep deletion cleanup idempotent and restart-safe across databases, files, and
  secure storage; preserve shared resources and persist pending cleanup work.
- Give each asynchronous operation an owner. Await ordering-sensitive work;
  explicitly handle errors from intentionally unawaited work. Preserve diagnostic
  context for recovery and expose useful failure states instead of swallowing errors.
- Give retries one owner, bounded attempts, eligibility rules, backoff, and
  cancellation. Prevent competing recovery loops and retrying rejected credentials.
- Define construction and disposal ownership for every player, controller, timer,
  subscription, focus node, and native resource. Cover completion, failure,
  cancellation, route changes, and profile changes. Do not change lifecycle ordering
  incidentally while extracting code.

## UI, localization, and platform behavior

- Keep `build()` free of side effects and long-lived resource creation. Use small
  reusable widgets, suitable `const` constructors, existing design tokens, and
  subscriptions that rebuild only the affected UI.
- Choose layouts from available logical space. Treat TV experience, input support,
  and platform capabilities separately. Share state/actions across layout variants;
  preserve selection, scroll, focus, and playback when resizing or switching layouts.
- Every TV action must work with directional keys, Select, and Back. Preserve
  remote repeat/hold behavior and restore meaningful focus after dialogs, playback,
  result updates, and pagination. Essential actions cannot depend only on hover/touch.
- Support accessibility semantics, text scaling, longer translations, and RTL.
  Localize new app-owned user-facing text, including native controls and errors.
  If an area lacks localization infrastructure, record that scoped prerequisite;
  do not invent a second translation system inside a refactor. Unchanged extracted
  text may retain a documented legacy exception pending a localization migration.
- Keep UI, audio, and subtitle languages independent; preserve locale fallbacks,
  localized formatting, and explicit time-zone handling. Do not translate provider
  metadata unless the provider supplies a localized version.
- Preserve all existing Debrify targets, including Android/Android TV, iOS, tvOS,
  and supported desktops. Put platform differences behind adapters/capabilities.
  Do not scatter new OS checks throughout migrated presentation code.

## Data, performance, and playback

- Put persistence behind repositories. Keep structured datasets in appropriate
  databases, secrets in secure storage, and large files in filesystem storage.
  Preserve existing preferences and schemas during extraction; storage migration
  requires its own compatibility plan and tests.
- Keep migrations explicit and non-destructive. For SQLite work, enable and verify
  foreign keys on each physical connection outside transactions; check referential
  integrity after migrations and test reopen/cascade/restrict behavior.
- Paginate large datasets, use lazy widgets, and bound memory/disk caches. Decode
  artwork near display size and avoid broad rebuilds or repeated network work.
  Process large inputs incrementally; expensive CPU work needs a worker isolate,
  not merely an `async` function.
- Measure performance on representative devices in profile/release mode before
  claiming an improvement. Preserve request counts, pagination behavior, and cache
  lifetime unless an intentional optimization is independently verified.
- Keep logs useful and redact credentials, tokens, authorization headers, and
  secrets embedded in URLs. Do not log private search/profile data unnecessarily.
- Keep engine-specific playback behavior behind typed boundaries. Preserve native
  bridge payloads, headers, subtitle/audio settings, fallback policies, session
  identity, progress handling, and teardown ordering during app refactors.
- Retain package versions, patches, binary/build provenance, and licenses.
  Separate extraction from engine/dependency upgrades; do not bulk-format vendors.

## Verification and completion

- Before a batch, establish relevant test and analyzer evidence. Reuse a recorded
  baseline when its revision, affected code/dependencies, SDK, and configuration
  still apply; rerun only missing or invalidated coverage. Do not rerun the same
  baseline for each mechanical move within a batch. Compare diagnostic identities
  and test names, not only counts. The checked-in failure list is historical
  evidence, not proof of current failures.
  Treat shifted line numbers from extraction separately from new diagnostics;
  use the rule, affected symbol, and message to establish correspondence.
  A test passing in the observed baseline must stay passing even if it appears in
  an older known-failure list. Compare against the observed run as well as the helper;
  an obsolete allowlist entry must not conceal a reintroduced failure.
- Test observable behavior at meaningful boundaries using fakes when useful.
  Prioritize filtering, ordering, stale results, pagination, profile isolation,
  focus, persistence, playback handoff, and disposal. Add reproducible bug coverage;
  avoid tests that merely mirror implementation or check trivial boilerplate.
- Test Riverpod state with isolated test containers and dependency overrides;
  widget tests use `ProviderScope` overrides. Dispose containers/subscriptions and
  verify cancellation, profile changes, retention, and cleanup where affected.
  Tests of pure services/policies should not need Riverpod setup.
- Source-text tests are not a substitute for behavior tests. When code moves,
  preserve each guard's purpose at its new location or replace it with equivalent
  executable coverage; do not delete assertions just to make the move pass.
- Format changed project-owned Dart code, run `flutter analyze`, and run affected
  tests at each completed batch. Run fast focused checks during implementation
  when useful. Broaden testing at integration milestones and run native/build/device
  checks when the changed boundary requires them. Reuse the same SDK/configuration
  for before/after comparisons; keep SDK upgrades separate and commit the lockfile.
- Run the full suite at planned cross-feature integration gates and completion,
  or earlier when a shared dependency change or unexplained failure warrants it.
  A mechanical helper move alone does not require another full-suite run. Add
  tests for uncovered contracts and meaningful risks, not boilerplate or every
  moved method. Review each batch once; repeat only the parts affected by fixes.
- Keep progress evidence concise: batch outcome, revision, check commands/results,
  material risks, and remaining deliverables. Reuse evidence and fixtures rather
  than duplicating logs or rebuilding old/new harnesses for covered behavior.
- The full-suite comparison helper is `python3 dev/tool/test_baseline.py`. Never
  use `--record` to accept new regressions. Investigate failures and distinguish
  pre-existing issues, environment limitations, and changes introduced by the work.
- For a migrated slice to be complete, production callers must use it, obsolete
  code must be removed, affected behavior must pass its checks, and new exceptions
  must be documented. Report unavailable checks as pending; do not claim parity.
- Introduce proportionate CI checks for formatting, analysis, behavior tests,
  import boundaries, and file-size rules with documented exclusions. Do not weaken
  checks or meaningful tests to obtain a pass.
- At the first migrated feature, add simple size/import checks scoped to migrated
  code and keep them updated as it grows. Run them at workflow/batch checkpoints and require them in CI
  before declaring the migration complete. Use existing tooling or a small script;
  dependency ownership and behavior still require review, not a bespoke framework.
- Documentation-only changes need link, accuracy, consistency, and diff checks;
  application builds/tests are unnecessary unless execution is affected.
- Report what changed, checks actually performed, remaining failures, and material
  limitations. Preserve unrelated user work and keep diffs reviewable.

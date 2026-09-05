# Settings circle join: runtime handoff findings

The device's exact exception was not captured. The field evidence is that a
force-quit/relaunch, with a fresh scope capture, fully healed the phone. The
same-ID handoff's missing runtime publication and the corrected ordering support
that observation; they do not establish the precise exception or predicate that
failed on the device. `ProfileAuthorizationContext.validate` rejecting a changed
profile authorization revision remains one plausible source of the resource
authorization rejection, not a confirmed device trace.

## Code and git evidence

- `restoreDeviceGraph` allocates a fresh local profile ID for every imported
  profile (`profile_restore_coordinator.dart:143`). A restored Admin and an
  imported Admin can have the same display name without sharing local identity.
  Publication activates staging rows; it does not replace the currently active
  profile's ID or generation.
- At HEAD before this fix, the same-ID branch of `switchTo` skipped both
  `commitActivation` and `ProfileRuntime.publish`. It reused the old scope while
  draining and warming participants. That branch already exists in `87f7644b`.
- `git diff 87f7644b HEAD -- lib/services/profiles/profile_authorization.dart
  lib/services/profiles/profile_runtime.dart
  lib/services/profiles/profile_restore_coordinator.dart` is empty.
- `1f1431fd` added the durable completeOnboarding intent. `313eb414` added
  afterAuthorityCommitted, including an early call on the same-ID branch.
  `142c1619` moved the ordinary switch's committed marker into the registry's
  post-transaction callback. Runtime publication remained after the awaited
  commitActivation call, and therefore after its recovery checkpoint.
- `ProfileAuthorizationContext.validate` checks maintenance, lock state,
  profile ID/session epoch, enabled state, and authorization revision. It does
  not compare device activation_revision or visible_data_generation.
- The explicit generation rejection is
  `storage_service.dart:2269`: isInitialSetupComplete throws when the registry's
  visible generation differs from the captured scope. Its sole caller,
  AppInitializer, already catches the failure and has mounted guards.
- `_pendingCredentialTypes` already returns an empty set after scope replacement.
  The vulnerable Settings aggregation allowed a single failed provider read to
  reject the page's load; the working-tree hardening isolates these failures.

## Implemented changes

- Same-ID handoffs with hooks, onboarding intent, or a stale generation now use
  the full activation path. Only an unchanged, hook-free selection remains a
  no-op. Candidate generation is reread after the drained precommit hook.
- Runtime publication and the new epoch occur synchronously in
  commitActivation's post-transaction callback, before recovery checkpointing.
- Active single-profile generation restore publishes at the same durable edge
  through publishDataGeneration's new callback. Post-commit errors roll forward.
  Device graph import still stages new identities; its handoff publishes them.
- Resumed adoption onto an already authoritative target retains post-handoff
  error classification, including failures during drain.
- Settings keeps per-read fallbacks, short Attention status and per-item captions,
  tolerant IPTV summary failure handling, and loading completion. Tests now
  expect the current presentation and include a live same-ID epoch remount.
- Ordinary Stremio addon display reads return an empty, uncached unavailable
  result on resource-authorization rejection or a retired scope. Management and
  remote-transfer reads still propagate errors. No authorization predicate or
  execution barrier was weakened.

No engine merge, scheduler, wire, authority hash-pin, secret-storage, sanitized
parse, or scoped-discard logic changed. No git commit was made.

## Regression coverage and validation limits

Tests cover same-ID stale-generation handoff; runtime publication before the
checkpoint; fresh capture/validate succeeding and retired context rejection;
same-ID onboarding durability; resumed handoff error classification; active
restore publication before checkpoint; Settings failure isolation and a live
same-ID epoch remount; and restored-backup/circle-adoption collection readback,
including a retired Stremio display read that must not poison the fresh cache.
The existing collection-remapping and Admin-selection tests were retained.

The stale-generation test explicitly demonstrates that onboarding rejects a
stale generation while a newly captured authorization context can still validate
before handoff. Its fresh epoch/generation assertions and the live Settings
remount assertion do not hold on the old same-ID shortcut. This is a code-level
regression predicate; no red/green execution is claimed.

Validation attempted in this sandbox:

- `flutter analyze` over all ten touched Dart files: launcher could not write its
  telemetry session outside the workspace. Direct invocation of the installed
  Dart analysis server provides analysis without that launcher write. Final
  result: zero errors/warnings; four existing Settings BuildContext lint infos.
- Targeted Flutter tests attempted before and after changes: no tests could
  start because binding the test runner's localhost socket is denied.
- Full-suite attempt: blocked by the same socket denial. Its test-file loading
  failures are infrastructure failures, not the stated 13-test baseline. The
  baseline count and executed red/green proof remain unverified.
- Logs: `/tmp/join-analysis-results.log`, `/tmp/join-analyze.log`,
  `/tmp/join-target-before.log`, `/tmp/join-target-after.log`,
  `/tmp/join-full-suite.log`.

## Fix-round actor audit (T1)

The production path carries explicit managing authority; `runForAdminSession`
is not an implicit substitute for the registry's actor arguments:

- Settings `SyncAndMigratePage._configureSync` checks `requireAdmin`
  (`lib/screens/settings/sync_and_migrate_page.dart`). The connect controller's
  `connect` uses `runForAdminSession` around root configuration
  (`webdav_sync_connect_controller.dart:178`).
- `ProfileWebDavSyncSetupAuthorization._runForAdminSession` captures a
  `ProfileAsyncAuthorization` for `backupRestore`, validates Admin role plus
  `manageProfiles` and `backupRestore`, and gives setup a revalidation barrier
  (`webdav_sync_setup_authorization.dart:54`). That scope ends before `_activate`;
  it is not carried as a stale captured scope into the imported profile.
- Activation independently calls
  `WebDavSyncRuntime._connectExistingRoot` (`webdav_sync_runtime.dart:800`),
  which captures `_captureManagingAdmin()` at line 809 and passes that context
  and the recapture callback to `WebDavSyncExistingRootConnector.connect`.
  `_captureManagingAdmin` at line 1468 validates the active context, Admin role,
  and both management features.
- The connector puts this context in `WebDavSyncAdoptionRequest.authorization`
  (`webdav_sync_existing_root_connector.dart:103`). Adoption forwards it through
  `restoreGraph` (`webdav_sync_adoption.dart:191`) to
  `ProfileRestoreCoordinator.restoreDeviceGraph`, which revalidates the Admin
  (`profile_restore_coordinator.dart:82`). Each staged `createProfile` supplies
  `actingProfileId`, `actingAuthorizationRevision`, and `actingSessionEpoch`
  from that context (lines 194–196). `_assertManagingActor` remains intact.
- The drained handoff runs via `webdav_sync_adoption.dart:507` and
  `DefaultWebDavSyncAdoptionOperations.handoff`. `commitActivation` changes the
  activation journal/device authority and, when requested, setup completion in
  the same transaction. It does not create profiles or call
  `_assertManagingActor`; ordinary member profile selection also uses this
  activation API. No new managing-actor argument is missing from that path.
  Post-handoff pruning and quarantine explicitly recapture and validate the
  newly active Admin before their registry mutations
  (`webdav_sync_adoption_operations.dart:216–245,274`).

The failing fixture created its member after `commitBootstrap` without the
required actor arguments. It now captures the active Admin and supplies all
three arguments before creating the member. No authorization predicate changed.

## Fix-round regressions (T2, R1–R4)

- Per-read failures retain their item labels immediately, even while other
  summaries are pending. An unexpected whole-load error has a separate boolean
  and never inserts a generic “Settings” item. The banner is short and bounded;
  cards show “Attention” with a retry/sign-in caption and constrain status width.
- Each read has a five-second deadline using the same item fallback mechanism.
  The widget cases include an IPTV future that never completes, assert the
  skeleton disappears, and inspect IPTV's status and caption. Legacy and
  committed fixtures both allow platform work to finish while pumping frames.
  The member fixture revokes the automatically seeded IPTV use grant, ensuring
  it produces a real authorization denial rather than a descriptor type error.
- Abort/checkpoint failures cannot skip participant rollback. Same-ID and
  different-ID tests fail the precommit hook and abort checkpoint, include a
  failing rollback, verify reverse order for every participant, and require the
  identical initiating exception with unchanged authority.
- Management calls the strict executable addon loader, including its hydration
  reread. Display remains fail-soft and uncached. A borrowed-resource regression
  rotates actual resource authority during decryption: management throws from
  revalidation, repeated display reads return empty, and a later stable read
  returns the addon without cache invalidation.
- Both Home IPTV series/watchlist actions catch authorization rejection around
  strict playlist reads and show a retry/sign-in Snackbar. Service authorization
  and execution filtering remain strict. These private UI callbacks were reviewed
  statically; no new Home interaction test was executed.

Fix-round validation: `flutter analyze` was attempted but its subprocess cannot
write the telemetry session outside the workspace. Direct analysis-server
execution completed for all 14 touched Dart files: zero errors/warnings, 21
existing lint infos in Settings/Home. Formatting and `git diff --check` pass.
Targeted tests were attempted for Settings, lifecycle, Stremio isolation, restore,
and adoption operations; the runner cannot bind its localhost socket in this
sandbox. Neither the four original new tests nor these added regressions have an
executed pass result here. The supplied 13-failure full-suite baseline is not
reverified. Logs: `/tmp/join-fix-analysis-results.log`,
`/tmp/join-fix-analyze.log`, `/tmp/join-fix-targeted.log`. No commit was made.

## Orchestrator corrections after executing the suite (2026-09-05)

The implementer's sandbox could not run widget tests, so the following were
found and corrected by actually running them:

- The `Flexible(maxLines: 1, ellipsis)` wrap around `info.status` in
  `settings_widgets.dart` shifted the status label a few pixels on every card
  and broke the pinned TV golden `goldens/settings_spotlight_tv.png` (0.85%
  diff). It was also aimed at the wrong element: the original 27px overflow
  came from the long attention caption sitting inside a card row, and that
  caption was independently moved into its own full-width, wrapping banner
  (`ValueKey('settings-summary-attention')`). The wrap is reverted; the
  golden is unchanged; the per-item failure captions are short
  (`Unavailable; retry or sign in` / `Unable to load; open the item to retry`).
- `test/settings_summary_reads_test.dart` asserted on a `ConnectionsSummary`
  widget. `_buildLayout` constructs one and hands it to `_SettingsLayout`, but
  the rendered layout builds `ConnectionCard`s directly from the same
  `ConnectionInfo` data and never places that widget, so the finder could not
  match (offstage included). The assertions now read the Torbox / IPTV /
  Real-Debrid `ConnectionCard.info` that is actually in the tree — same
  properties, real widgets. This is pre-existing layout structure, not a
  behaviour change.
- Verified by execution: all six settings-summary tests pass (including the
  never-completing read and the live same-ID join remount); the adoption
  handoff Admin-actor test passes; the TV Spotlight golden passes.

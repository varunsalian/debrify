# Android IPTV background ownership integration contract

Status: design only; WorkManager is not registered. Native execution must remain
disabled until the scheduler and ingestion drain contracts below are implemented
and verified together. This document is the handoff for the scheduler and
ingestion owners; it does not claim their agreement.

## Ownership

Use one native coordinator, serialized on the Android main thread, with states
`idle`, `foreground`, `background(token)`, and `draining(token)`.

- Foreground ownership begins **before engine construction**, including the
  default FlutterActivity engine path. Count engine identities, not activities
  or resumed windows. An engine in a stopped activity still owns its storage.
- Background admission succeeds only with no foreground engines, no foreground
  startup reservation, and no other worker. Each admission receives a unique
  token. Stale callbacks cannot release a newer owner's lease.
- A foreground launch reserves priority and requests background cancellation.
  It must wait asynchronously in a native launch gate before creating or
  attaching a Flutter engine. Do not wait synchronously in onCreate and do not
  defer calling super.onCreate until an asynchronous callback. Preserve launch
  intents, saved state, configuration changes, and privacy flags through the
  gate. Cover launcher, deep-link, notification and internal MainActivity paths.
- Release background ownership only after acknowledged drain, database close,
  and background engine destruction. Worker cancellation and timeout request
  drain; neither releases ownership directly.
- Foreground destruction also needs proof that its child database workers have
  exited before admitting background work. Without a foreground drain hook,
  conservatively disallow background admission for the rest of that process
  after any foreground engine has existed. Background work can still run in a
  later cold process. An activity-destroyed callback alone is insufficient.
- If a drain fails or its deadline expires, fail closed: retain ownership and
  do not start another engine. This protects data but cannot meet bounded launch
  latency. Shipping requires either bounded cancellation in ingestion or an
  isolated background process with a cross-process file lease held until that
  process has actually died. A process-local flag cannot support that alternative.

## Headless initialization

Add a production background initializer inside ProfileBootstrap and an
existing-only registry open path; do not use debugInstallRegistry or ordinary
initialize(). Under the exclusive lease:

1. Open the existing registry without create, migration, recovery, repair,
   cleanup, native projection publication, or active-profile changes. Reject an
   unsupported schema, missing committed authority, pending activation/restore/
   migration, reset/cleanup work, or persisted database-adoption barrier.
2. Initialize the existing Android vault without creating a key. Defer to normal
   startup if a vault migration audit or recovery is required.
3. Select only the persisted active profile for the initial implementation;
   do not iterate or activate other profiles. Require an enabled, fully set up,
   active profile, a valid visible generation, IPTV permission, and live source
   grants. Treat this as background job authority, not a fabricated UI unlock.
   Revalidate profile/resource revisions before fetching credentials and commit.
4. Install an isolate-local runtime scope and registry for scheduler getters,
   without invoking foreground lifecycle participants or starting UI services.
5. On completion close only handles opened by this engine. Do not repair or
   delete a catalog if opening it fails in background mode.

The dedicated entrypoint must be imported into the application's compiled Dart
library graph (the scheduler owner can import/export the helper without changing
main.dart), and marked @pragma('vm:entry-point'). Native code selects its explicit
package library URI. Verify this in an Android release/AOT build.

## Required scheduler and ingestion agreement

Proposed scheduler contract: `pauseAndDrain()` atomically rejects new refreshes,
cancels pending timers/queued work, requests cancellation of active work, then
waits for **all** network requests, parse/ingest isolates, native database calls,
and cleanup to finish. Calling it before refresh starts must prevent that run.
It must be idempotent and safe concurrently with refreshDue(). Do not call start()
in the headless engine: run refreshDue() once.

The ingestion owner must confirm or implement:

- Cancellation propagated to downloads and between bounded ingest chunks.
- No detached database work survives the refresh Future or drain acknowledgement.
- Every started child isolate is joined; a timeout wrapper is not a join.
- Interrupted ingestion leaves the published generation valid and restartable.
- Background database open fails without deleting database/WAL/SHM files.
- No shared handle is closed by another engine or a stale completion callback.

Existing evidence: IptvCatalogDb.runExclusive uses a Dart static Future queue;
ingest allocates a generation outside its transaction and relies on that queue.
M3U and Xtream ingestion run in compute isolates. Therefore a native admission
check without the release/drain guarantees above is not enough.

## WorkManager wiring once prerequisites pass

Enqueue unique periodic work with KEEP, a six-hour interval and connected-network
constraint. Treat six hours as an approximate wake-up opportunity; refreshDue()
decides which catalogs are due. Use a CoroutineWorker and an execution deadline
below WorkManager's ten-minute limit, reserving time for acknowledged drain.
Perform Flutter engine construction, channel handling and destruction on the
main thread. Register only required headless plugins and the device-vault channel.
Use token-tagged ready/run/cancel/drained messages. Cancellation cleanup must run
even when the CoroutineWorker coroutine has already been cancelled.

## Required acceptance checks

- Race worker admission against foreground engine creation in both orders.
- Open app during download, parse, ingest chunk, commit and database close.
- Stop work before entrypoint readiness and during every execution phase.
- Deliver late acknowledgements from a previous token and recreate activities.
- Inject failed drain: no lease release or foreground engine admission.
- Test pending profile activation, restore, adoption, reset and vault recovery;
  verify background execution performs no recovery writes.
- Test disabled profiles, revoked resources, missing generations and PIN profiles
  without unlocking or publishing foreground privacy state.
- Kill/restart during ingest; verify the published generation and retry behavior.
- Confirm release/AOT entrypoint reachability and actual headless plugin support.

References:

- https://developer.android.com/reference/androidx/work/WorkManager
- https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work
- https://api.flutter.dev/javadoc/io/flutter/embedding/engine/FlutterEngine.html
- https://api.flutter.dev/javadoc/io/flutter/embedding/engine/dart/DartExecutor.DartEntrypoint.html

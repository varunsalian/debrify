# Android startup database fix — isolated worktree

Worktree: `/private/tmp/debrify-webdav-startup-fix`
Branch: `webdav-sync`, base `93b92cafcf3b8e71d7333fa28ae84848ab7e4226`.
Changes are uncommitted. The original worktree also checks out this branch;
committing here would move its branch reference too. No commit, push, APK
installation, data reset, or edits to the original worktree were performed.

## Findings and changes

The September 6 21:18 launch logged 14 sqflite lock-wait warnings and never
completed Home loading before exit. Private diagnostics showed a responsive
Dart heartbeat, no held preference/adoption barrier, and engine recreation
inside the same Android process. The logs did not identify the SQL lock owner.

Native JVM tests reproduce two concrete upstream sqflite_android 2.4.1 defects:
engine detach retains an unfinished SQLite transaction, and separate engines
share a native database handle. These are consistent with the observed failure,
but do not establish the exact transaction responsible for the phone incident.

A vendored Android plugin patch gives each engine its own native handles and
worker pool. Detach rejects further calls and closes owned connections on their
workers, rolling back unfinished transactions before worker shutdown. Pending
opens/closes are accounted for, cursors and abandoned SQL queues are released,
and cleanup does not close another engine's database. The Dart API and database
schemas are unchanged. See `packages/sqflite_android_patched/PATCHES.md`.

Home's initial board load now has a 25-second overall deadline. Timeout retires
the load generation, stops stale pagination, releases the loading state, and
shows a retry button when there are no previous rows. Background refresh retains
existing rows. Late completion cannot replace a newer board load. Timeout alone
does not close or roll back a live database transaction.

## Validation

- 18 native JVM tests passed, including 10 new lifecycle tests. Cases cover
  unfinished transactions/queued reads, committed-data preservation, separate
  engines, pending opens, multiple handles, failed opens, detached-call rejection,
  and 12 successive engine recreations.
- 132 Flutter tests passed across Home deadlines/catalog refresh, registry,
  profile database isolation, adoption gate, WebDAV scheduler, device job
  ownership, and live profile switching.
- `:app:compileDebugKotlin` passed, including Flutter debug compilation and the
  patched plugin integration.
- Targeted Flutter analysis found no errors or warnings; 17 informational
  notices remain in unchanged SearchScreen code (primarily deprecations).
- `git diff --check` passed.

Logs: `/tmp/debrify-startup-android-check.log`,
`/tmp/debrify-flutter-regressions.log`, `/tmp/debrify-startup-sync-check.log`,
`/tmp/debrify-startup-analysis.log`.

The live-profile-switch tests print font-download diagnostics but pass. The
original intermittent incident has not been reproduced end to end on the phone;
validation was automated locally, without requiring user reproduction steps.

## Review corrections

The dispatcher now runs a workerless delete outside the admission lock, removing
its reverse lock order against database-open/close workers. A deterministic test
holds the open/close lock and verifies that a waiting delete leaves the admission
lock available. An additional test starts the replacement engine while the old
worker is paused with an exclusive transaction and teardown is still pending;
reopen and subsequent reads complete after the old worker is released.

Refresh timeout restores the previous catalog references, addon lookup, and last
committed pagination cursor. The cursor used to reserve an in-flight request is
not treated as completed work. Superseded pagination cannot reset a newer load's
busy state. Existing rows remain scrollable and a snackbar provides Retry. The
new timeout regression checks that remaining rows stay accessible and a late
refresh cannot overwrite the restored paging position.

The second review correction replaces refresh-start snapshots with one immutable
committed-board snapshot (catalog references, paging cursor, addon lookup). It is
published only after a full load or page is accepted. Overlapping refreshes all
recover that committed state, never another refresh's tentative references. The
additional regression covers two overlapping refreshes, both timeouts, and late
completion of both responses; the original remaining rows and sources survive.

## Integration with current webdav-sync

Pulled origin/webdav-sync with --ff-only; already current at 82edcd2a. The shared branch had advanced while this worktree retained the 93b92caf index. Backed up the startup patch and untracked files under /tmp/debrify-startup-before-pull*, refreshed this checkout, and reapplied the patch. Resolved the one search_screen.dart conflict by wrapping the latest Home pipeline, retaining collections reads, claimed-catalog filtering, and pinned collection ordering. No commit created.

Validation: 78 Home/deadline/collections tests passed. Targeted analysis reports no errors or warnings, with 17 existing informational diagnostics outside the changed code. Native patch unchanged.

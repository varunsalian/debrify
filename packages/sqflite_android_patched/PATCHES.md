# Debrify Android database lifecycle patch

Based on sqflite_android 2.4.1, retaining its upstream license and public Dart API.
Only SqflitePlugin.java and Database.java change at runtime.

Each Flutter engine now owns its native database maps and worker pool. A second
engine cannot recover a first engine's connection or pending transaction queue.
Hot restart within the same engine retains the upstream recovery behavior.

On engine detach, the plugin rejects new calls and queues connection closure on
each database's owning worker, bypassing the abandoned transaction queue. Cleanup explicitly rolls back unfinished work on the owning worker before
closing its SQLite connection and quitting the worker;
committed data is retained. Other engines' handles and native recording/download
services are not closed. A separate ownership set includes pending opens and
closes, so shutdown cannot strand an in-flight open or quit before all handles
close. Retained cursors and queued operations are released with the connection.
Worker-count changes with live connections are rejected instead of discarding
pending work.

The Android build uses Debrify's existing API 24 minimum. Robolectric 4.15.1 is
used only for JVM tests. EngineLifecycleTest covers separate live engines,
abandoned transactions and queued reads, committed-data preservation, another
engine continuing work, detach during a queued open, closing multiple handles,
and repeated engine recreation. The unpatched implementation fails the handle
ownership and abandoned-transaction cases.

This repairs a reproducible lifecycle defect consistent with the September 6
startup logs. It does not prove the exact transaction responsible for that phone
incident: those logs did not record the database/transaction owner.

Review follow-up: workerless deletion executes outside the admission lock to
preserve lock ordering. Tests cover a waiting delete, immediate replacement-engine
open while old transaction cleanup is pending, and continued committed reads.

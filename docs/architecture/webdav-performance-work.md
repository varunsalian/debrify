# WebDAV performance and memory work

Requested outcome: fast WebDAV backup/restore and initial sync on low-end TVs,
with bounded memory, no automatic pre-join safety backup, four review/fix rounds,
and all changes left uncommitted. WebDAV formats have not shipped; no legacy
WebDAV wire compatibility is required.

## Implementation requirements

1. Remove automatic sync safety-backup packaging and its cleanup dependencies.
   Preserve staged restore, validated handoff, and interruption recovery journals.
2. Use file-backed snapshots and bounded authenticated binary I/O for WebDAV
   manual archives and sync bootstrap. Page large metadata/collections. Avoid
   whole-file/base64/JSON buffers, including worker-isolate copies.
3. Share immutable bootstrap objects across devices. Join from an existing
   snapshot without re-exporting and re-uploading it; establish an imported
   baseline and merge concurrent changes.
4. Omit only rebuildable catalog/EPG caches; preserve durable user data. Hash
   transfers in flight, avoid duplicate parsing/decryption, and reuse derived
   root keys within the authenticated connection lifetime.
5. Bound buffers, decompression, queued work, and concurrency. One large-data
   worker initially; allow bounded independent small metadata operations.
6. Resume completed immutable-object transfers; retry only missing work. Bound
   database transactions, commit manifests after their dependencies, and clean
   temporary storage.
7. Record stage durations, transfer bytes, process memory and temporary storage;
   exercise large libraries, slow connections, corruption and process interruption.
   Validate in release mode on the weakest available target TV.

## Implemented behavior

- First join no longer creates, decrypts, or retains an automatic safety backup.
  Manual-backup guidance, staged restore, authorization, adoption journals,
  rollback before handoff, and deferred predecessor cleanup remain.
- WebDAV manual backups and bootstrap use the local file-backed ZIP snapshot
  pipeline, wrapped in `DBRFENC2` authenticated binary encryption. New WebDAV
  filenames end in `.debrify.enc`. Normal local exports remain archive version
  1; WebDAV exports use version 2 with separately paged preference metadata.
- Database files and imported playlist attachments travel as archive entries,
  without base64 database envelopes. Preference JSON is emitted in 128 KiB
  pages and restored one profile at a time. Attachments load one resource at
  a time; large sealed secrets stay in private scratch until publication.
- Streaming gzip level 1 reduces SQLite/JSON redundancy. Sampling skips the
  compression pass for incompressible inputs. Authenticated encryption uses
  256 KiB segments, the AES-GCM-HKDF streaming construction specified by Tink,
  independent per-file salts, ordered segment nonces, and an authenticated
  final-segment bit. Compression flags and context are authenticated too.
- Bootstrap descriptors reference shared immutable `objects/<sha256>.enc`
  files outside device directories. A joining device republishes the small
  descriptor, preserving the original archive's identity maps. It does not
  export or upload another bootstrap. The imported baseline lets newer peer
  records win the first merge while later local edits keep fresh timestamps.
- Completed adoption retries authenticate root, manifests, and the descriptor
  without downloading, decrypting, or extracting the archive again. Normal
  first adoption still verifies the complete archive before changing data.
- Content-addressed downloads resume with HTTP Range and verify the full
  SHA-256, including the retained prefix. A server returning 200 restarts the
  download. Completed shared uploads are reused after verified read-back;
  a matching strong ETag can reuse the verification receipt. Lost PUT responses
  are reconciled through read-back before publication.
- SHA-256 is calculated during transfers. Root derivation is cached only for
  an exact authenticated marker/passphrase pair, with invalidation on runtime
  teardown and memory pressure. Existing transport-client reuse is retained.
- Large file crypto, background KDF, section codecs, and collection merge
  workers share a serial permit. Small manifest reads allow concurrency 3;
  large peer-section reads run sequentially. Collection shard target size starts
  at 512 KiB and increases when necessary to fit the shared manifest budget,
  while preserving the 32 MiB section bound. Decoded-cache accounting allows for object expansion; separate
  decoded budgets are 4 MiB ordinary / 8 MiB collections, plus at most 8 MiB
  encrypted bytes. Cache diagnostics include both kinds of storage.
- Retry-cache pruning spans circles, retaining at most two inactive large
  files and 512 MiB of inactive data, expiring after seven days. The current
  transfer is exempt. Startup awaits abandoned restore-scratch cleanup before
  first-sync work can begin. Plaintext files are released as stages complete.
- Backup/snapshot diagnostics record stage duration, bytes, and process peak
  RSS without paths or credentials. The standalone release benchmark also
  samples working-directory storage every 100 ms.

## Four review and fix rounds

### Round 1 — format, authentication, and restored data

Inspected archive references, schema negotiation, file ownership, and restore
publication. Fixed the bootstrap schema ratchet to recognize version 2 while
still rejecting future schemas. Updated production-path test fixtures to use
real file-backed archives. Fixed publication of spooled resource secrets so
both the registry column and chunk rows receive the actual sealed payload.

Validation includes an independently generated Python AEAD fixture, segment
boundary cases, wrong key/context, reordered/truncated/corrupt ciphertext,
database/cache preservation, Unicode preference pages, corrupted-page rollback,
and exact restoration of a large playlist. The focused archive/coordinator/
graph-tier/discovery checkpoint passed 72 tests. Earlier broad checkpoints and
all affected paths were included again in round 4.

### Round 2 — allocations, throughput, and temporary storage

Inspected whole-buffer reads, canonical JSON hashing, metadata and attachment
lifetimes, compression expansion, worker overlap, and cache accounting. Added
streamed canonical hashing, paged preferences, lazy attachments, disk-backed
sealed secrets, and shared worker serialization. Limited gzip decoder input
to 4 KiB to bound each expansion chunk. Removed the collection cache that held
large source objects and parts together.

Review caught a regression where rejecting large decoded cache entries caused
repeat downloads. Added the bounded encrypted-byte cache and included it in
cache metrics. The engine/archive regression checkpoint passed 116 tests.
Fresh-process release measurements at 64 and 512 MiB verified hashes and
showed near-flat file-pipeline RSS; results are recorded below.

### Round 3 — interruptions, retries, and publication order

Inspected adoption journals, manifest ordering, shared-object reuse, failed
read-back, cancellation, and scratch cleanup. Added descriptor-only discovery
after completed adoption, final-completion cancellation checks, cross-circle
scratch cleanup, and startup cleanup ordering. Fixed cancellation during
retained-prefix hashing to release the HTTP response before its body loop starts.

The connector/discovery/engine/archive/streaming checkpoint passed 160 tests.
Four dedicated snapshot tests passed for a lost PUT response, failed read-back
followed by upload reuse, corrupt read-back rejection, and abandoned scratch in
another circle. Protocol coverage includes Range 206, fallback 200, invalid
ranges, corrupt prefixes, interrupted responses, deadlines, and cancellation.
Existing adoption tests cover interruption recovery and blocked publication.

### Round 4 — final regression and requirement audit

Final broad command:

```sh
flutter test test/services/webdav_sync test/profiles \
  test/services/webdav_protocol_client_test.dart \
  test/services/streaming_encrypted_file_test.dart \
  test/services/canonical_json_test.dart \
  test/profile_backup_migrate_source_guard_test.dart test/webdav_picker_test.dart
```

Result: **1,343 passed, four pre-existing failures**. All four were reproduced
in a clean detached worktree at `c1f8240e` (18 passed, the same four failed):

- Two `edit_profile_screen_test.dart` expectations for “Member” and
  “Choose image or GIF” no longer match the existing UI.
- The source-guard SharedPreferences allowlist omits the existing
  `webdav_sync_save_feedback.dart` adapter.
- The native-diagnostic reset source guard searches for an outdated substring.

Static analysis of the other 52 changed Dart files reported no issues.
`main.dart` has ten informational findings; all ten also occur on clean HEAD,
with only line offsets changed. Final focused checks after the encrypted-size
bound/diagnostics adjustment passed 65 tests; analysis of those files passed.
Formatting and `git diff --check` were checked. Nothing was committed.

## Follow-up review fixes — 2026-09-09

An independent review found two gaps in the earlier coverage. Both were
confirmed in the production code and corrected without committing:

- The 512 KiB collection target could exceed the 512-section manifest limit.
  Seed preparation and the engine now plan one budget across profiles, reserve
  room for non-collection sections (including library/TV-library sections), and
  account for retained references. The target grows only when needed, up to the
  existing section size bound. Existing partitions can be repacked when other
  references consume their space. Unchanged inventories reuse published counts
  when they still fit, and hot digests are calculated once per publication pass.
- Shared-object transport had omitted the expected digest and cancellation
  callback when calling the protocol client. Both are now forwarded. Regression
  tests invoke the actual adapter and verify Range after an interruption,
  retained-prefix integrity, and cancellation during the response body.

All four manifest publication paths now apply the reader's structural validation
before upload. Oversized seed section sets fail before section uploads. Capacity
or invalid-reference errors preserve the working remote manifest.

Regression coverage includes the reported 513 collections at roughly 382 KiB
each, shared budgets across profiles, unchanged-inventory repartitioning,
capacity exhaustion, initializer/publisher/engine failures before manifest
replacement, and the production shared-object adapter. The broader sync,
protocol, and archive run passed **682 tests**. The subsequent focused run passed
**159 tests**, and static analysis of the affected files reported no issues.

## Release benchmark

```sh
dart compile exe tool/benchmark_webdav_streaming.dart -o /tmp/webdav-bench
/tmp/webdav-bench 64 compressible
/tmp/webdav-bench 64 compressible legacy
/tmp/webdav-bench 512 compressible
/tmp/webdav-bench 64 random
```

The benchmark writes a deterministic binary file, then encrypts, decrypts,
and verifies its hash. “Compressible” is approximately 88% zero bytes; the
legacy case reproduces database base64 inside a compressed JSON envelope.
Each case runs in a fresh AOT process. Root/password KDF time, real database
snapshot creation, Flutter rendering, and network time are excluded. These
are file-pipeline measurements, not end-to-end backup/first-sync timings.

Results from the final isolated host run (milliseconds and decimal MB):

| Input / pipeline | Samples | Encrypt | Decrypt | Transfer MB | Peak RSS MB | Sampled working storage MB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 64 MiB / previous JSON shape | 3 | 1,191 | 668 | 11.60 | 591.86 | 145.82 |
| 64 MiB / binary stream | 3 | 579 | 850 | 8.77 | 63.34 | 150.90 |
| 512 MiB / binary stream | 1 | 4,617 | 6,742 | 70.17 | 68.29 | 1,209.95 |

Three-sample values are medians of each metric. At 64 MiB, the combined median
stage times decrease about 23%, transfer bytes about 24%, and peak RSS about
89%. Encryption improves substantially; decryption by itself is slower in this
case. Avoiding the safety-backup round trip and bootstrap re-export adds savings
outside this benchmark. No claim is made that every stage or server is faster.

The storage sampler includes the generated source, encrypted file, restored
file, and any observed gzip intermediates. It is sampled, not an exact disk
high-water mark. The binary route trades temporary disk for bounded transfer
buffers. An earlier incompressible 64 MiB run verified its output at 61.98 MB
peak RSS, with 67.113 MB transferred (essentially only encryption overhead).

Raw final samples are in `webdav-performance-benchmarks.jsonl`; the executable
source is `tool/benchmark_webdav_streaming.dart`. All seven final cases verified
their output hashes. Measurements used Dart 3.12.2 AOT on an Apple M5 Max running
macOS 26.4, without other test/analyzer jobs running during the final sequence.

## Remaining limits and device validation

The large-file transport no longer scales memory with archive size. This is
not a hard ceiling for the entire app: existing preference storage and resource
encryption still materialize one profile/record, and recurring sync's baseline
models can materialize large collections. Metadata paging avoids the extra
whole-archive JSON envelope; it does not replace SharedPreferences or the
resource-secret storage API. Decoded-cache sizes are conservative accounting
estimates, not a measurement of every VM allocation.

A single collection can exceed the 512 KiB shard target (the existing 32 MiB
individual-section limit remains). Existing larger state/document limits remain
as format bounds, not promises that maximum-sized inputs fit every TV.

Generic WebDAV PUT does not provide portable partial-upload resume. An
unfinished manual PUT must restart; completed immutable sync uploads and
interrupted content-addressed downloads can be reused. Shared remote archives
are not garbage-collected yet. Local retry data is cleaned on the next snapshot
operation; an interrupted active file may temporarily exceed the inactive-cache
budget. Active staging needs enough disk for input, intermediate compression,
and output; disk use is deliberately traded for lower memory use.

## Device access

At the initial inspection, `adb devices -l` reported no connected devices. The
target TV model and access have been requested. Host benchmarks do not establish
the final TV memory ceiling or device performance. The final check also found
no connected device. Before shipping, run a release build on the weakest target
TV with representative maximum libraries, a slow WebDAV server, cancellation,
and force-stop/restart during download, staging, handoff, and manifest publication.
Capture stage logs, Android PSS/RSS, and free staging space while confirming that
normal UI navigation stays responsive.

## Hard memory stress tests (September 9, 2026)

Added `tool/webdav_memory_stress/` to run unchanged production Dart components
in Linux AOT containers with a hard cgroup v2 limit, swap disabled and one CPU
quota. The local Docker engine runs ARM64 Linux in Colima. The SDK is pinned to
Dart 3.12.2 and all 19 resolved dependencies match the app's lockfile. The runner
checks Docker settings and the actual cgroup files, and requires a deliberately
oversized allocation control to be killed by Linux. Inputs and image identity
are fingerprinted in the JSONL report.

The archive scenarios create a ZIP, encrypt, upload to a disk-backed loopback
HTTP server, download, decrypt and extract. They verify ciphertext hashes, ZIP
CRC, restored length and restored SHA-256. The server shares the client's RAM
budget. Additional scenarios cover incompressible data, very large compression
expansion, five round trips in one process, interrupted GET with actual Range
resume, cancellation during download/encryption, and corrupted ciphertext with
partial-output cleanup. The collection scenarios exercise the global planner
and worker section preparation using distinct allocations for every large
record, and verify both manifest capacity and record preservation.

Run instructions and the exact matrix are in
[`tool/webdav_memory_stress/README.md`](../../tool/webdav_memory_stress/README.md).
The original report is [`webdav-memory-stress-results.jsonl`](webdav-memory-stress-results.jsonl).
These are opt-in stress tests; ordinary Flutter tests do not need Docker.

The initial run verified all 12 cases' limits. Nine operations passed, two were
OOM-killed, and the oversized control was killed as required. The runner exited
1. **Correction:** the collection OOM happened in the test's JSON comparison
after production section preparation completed. The old report's `lastStage`
field named the last completed stage and was misinterpreted as the active stage.
The follow-up below corrects the harness and resolves the password failure.

| Operation | RAM cap | Outcome | Peak process RSS |
| --- | --- | --- | --- |
| 512 MiB sync-key archive | 128 MiB | Passed | 50.67 MiB |
| 1 GiB sync-key archive | 128 MiB | Passed | 48.44 MiB |
| 128 MiB incompressible archive | 128 MiB | Passed | 50.02 MiB |
| 512 MiB all-zero archive | 128 MiB | Passed | 54.91 MiB |
| 128 MiB password-protected archive | 128 MiB | OOM during decryption | At least 109.63 MiB |
| Same password-protected archive | 256 MiB | Passed | 135.12 MiB |
| Five 64 MiB round trips in one process | 128 MiB | Passed | 51.92 MiB |
| Resume, cancellation and corruption recovery | 128 MiB | Passed | 64.34 MiB |
| 64 separate 382 KiB collection titles | 128 MiB | Passed | 43.84 MiB |
| 513 separate 382 KiB collection titles | 256 MiB | OOM in test verification after preparation | At least 222.59 MiB |
| Same 513-collection inventory | 512 MiB | Passed | 261.21 MiB |

The 513-collection input contains about 191 MiB of distinct text. A passing
streamed archive does not establish a memory bound for the password and
in-memory inventory paths. These are whole-pipeline observations; the failing
stage alone does not isolate the root cause of retained allocations.

The full runner fails on a failed operation, including collection probes by
default. Its explicit exploratory option can permit a probe OOM while still
recording the operation as `oom`. It never reports a killed operation as a
successful backup or sync. Cgroup peak includes reclaimable file cache;
process RSS is reported separately, and pre-kill RSS is only a lower bound.

These results concern file transport/crypto/ZIP and collection preparation.
They do not cover Flutter UI, Android native/plugin memory, SQLite export or
import, preferences parsing, profile adoption or Android lifecycle recovery.
They provide repeatable checks, not proof that the complete app cannot crash on
a low-end TV.

### Follow-up: managed password derivation and corrected collection assertion

The password file codec used `Argon2id`, whose Dart implementation starts a
nested isolate and allocates its working buffer through native malloc. The
file operation already runs in a heavy worker. Setting `DartArgon2id`'s
`maxIsolates` to zero keeps its working buffer in managed typed data in that
worker, so Dart's garbage collector accounts for it. The same change applies
to sync root key derivation. This preserves Argon2id's 19456 KiB, two iterations,
one lane and 32-byte key defaults; serialized KDF parameters and encryption
formats are unchanged. Logout now explicitly requests background root opening,
matching the other production callers.

A new sync stress case creates a root marker, clears the root cache, unlocks it
with the production defaults, and uses that key for the archive round trip. It
initially reproduced an OOM under 128 MiB after the upload completed. With the
managed KDF it completed under the same cap. Additional cases cover a 512 MiB
password archive and five password round trips without restarting the process.

Collection verification now uses `DeepCollectionEquality` on the complete
returned records, avoiding two large JSON strings per comparison. It has its
own `collection-verify` stage; reports distinguish `activeStageAtExit` from
`lastCompletedStage`. The 513-collection case completed under 256 MiB with this
assertion correction and no production collection change. Its initial failure
does not establish a collection-preparation bug. The model still holds about
191 MiB of text, so this does not establish a small memory bound for arbitrary
inventories or the full app.

The follow-up results are recorded separately in
[`webdav-memory-stress-fixed-results.jsonl`](webdav-memory-stress-fixed-results.jsonl),
preserving the initial measurements. A new interoperability test decrypts a
password file using the library's default Argon2id implementation, independently
of the production worker configuration. Existing root golden-vector,
wrong-password, corruption, cancellation and sync lifecycle tests cover the
unchanged cryptographic and functional behavior.

Final validation: **15/15 stress expectations met** (14 operations passed plus
the required OOM control), all limits verified, runner exit 0. The 661-test
WebDAV sync, streaming crypto and local archive regression suite passed. Static
analysis of the five changed Dart files reported no issues. Source/harness
fingerprints in the final report match the tested files.

| Follow-up operation | RAM cap | Outcome | Peak process RSS |
| --- | --- | --- | --- |
| 128 MiB password archive | 128 MiB | Passed | 50.71 MiB |
| 128 MiB password archive | 256 MiB | Passed | 50.98 MiB |
| 512 MiB password archive | 128 MiB | Passed | 60.59 MiB |
| Five 64 MiB password round trips | 128 MiB | Passed | 55.07 MiB |
| Fresh sync root unlock and 128 MiB archive | 128 MiB | Passed | 40.53 MiB |
| 1 GiB sync-key archive | 128 MiB | Passed | 49.96 MiB |
| 513 separate 382 KiB collection titles | 256 MiB | Passed with corrected verification | 222.79 MiB |

The 256 MiB password comparison is a drop from 135.12 MiB to 50.98 MiB peak RSS
on the same workload and cap. These component results remain distinct from
full-app Android/TV validation.

### Build provenance review and pre-push validation

The stress runner now fingerprints its copied build context and stores the
fingerprints in the image. New builds use Docker's per-build image ID file;
reuse resolves the tag once. Every case runs the verified immutable image ID,
checks the actual container image, and reports the copied source fingerprints.
Workspace edits or concurrent builds cannot relabel the tested source. Five
Python regression tests cover these races and stale-image rejection. Real Docker
checks passed for both build and reuse, including the required OOM control,
failure recovery and a collection operation.

The final broad Flutter check passed **1,358 tests**, with only the same four
baseline failures listed above. Analysis of all 57 changed Dart files found
only the ten existing informational findings in `main.dart`; formatting passed
for all 57 files, and `git diff --check` passed. All production source hashes
still match the successful 15-case memory stress report.

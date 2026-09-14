# WebDAV tests with a hard memory limit

Run from the repository root with Python 3 and a running local Docker engine:

```sh
python3 tool/webdav_memory_stress/run.py --report /tmp/webdav-memory-results.jsonl
```

The [original September 9 report](../../docs/architecture/webdav-memory-stress-results.jsonl)
recorded a real password-path OOM and a collection-test OOM. Inspection of its
events showed that collection preparation had already ended: the test's JSON
equality assertion exhausted the remaining memory. Its old `lastStage` field
incorrectly suggested the last completed production stage was still active.
The assertion now compares the object graph directly, and reports separate
active/completed stages. Production collection preparation needed no change.

The [updated report](../../docs/architecture/webdav-memory-stress-fixed-results.jsonl)
uses managed Argon2id working memory inside the existing heavy worker for both
manual passwords and sync root keys. The algorithm, memory/time/lane parameters,
key size and archive format are unchanged. New cases cover a larger password
archive, repeated password operations and a fresh sync root unlock.
All **15 cases met their expectations**: 14 operations completed and the control
was OOM-killed as required. The runner exited 0, with every RAM/swap limit
verified. The 128 MiB password archive peaked at 50.71 MiB under a 128 MiB cap;
the 512 MiB password archive at 60.59 MiB; fresh sync unlock plus transfer at
40.53 MiB. The 513-collection case peaked at 222.79 MiB under a 256 MiB cap.

The report path must be new. To rerun selected cases after building:

```sh
python3 tool/webdav_memory_stress/run.py --skip-build \
  --case limit-control --case faults-64 \
  --report /tmp/webdav-memory-recovery.jsonl
```

The runner fingerprints the copied build context and stores those fingerprints
in the resulting image. It refuses to test an image whose copied inputs differ
from the workspace at validation, including with `--skip-build`. Images from
older versions of the runner need rebuilding once to add this provenance.
New builds select their image using Docker's per-build ID file; `--skip-build`
resolves the reusable image tag once. Every case then uses that immutable image
ID and verifies the container's actual image. Concurrent rebuilds cannot switch
the code under test. Reports retain the image's source fingerprints even if the
workspace is edited after validation.

The runner's race regression tests need only Python, without Docker:

```sh
python3 -m unittest discover -s tool/webdav_memory_stress -p 'test_*.py' -v
```

The Linux Dart SDK image and pub dependencies are pinned; the dependency versions
match the app's lockfile when this harness was added. Update them together when
the app upgrades. The build context contains only the listed production Dart
files, the worker and dependency manifests. It does not use a Flutter SDK or
modify the app's package configuration.

Each case runs in a fresh Linux AOT process inside its own container, with one
CPU quota and a hard RAM limit. `--memory-swap` equals `--memory`, which
[disables container swap](https://docs.docker.com/engine/containers/resource_constraints/).
The worker also reads `memory.max` and `memory.swap.max`, and the runner verifies
these against Docker's configuration. A cgroup v2 Docker engine is required.
The control deliberately allocates and touches more memory than allowed; the
runner requires Docker to report `OOMKilled=true`. A Dart exception alone does
not count as proof of an enforced limit.

Runtime networking is disabled except for loopback. A streamed HTTP server
stores the uploaded object on disk and serves it back through the actual
`WebDavProtocolClient`. The server shares the client's RAM budget. The budget
includes the Dart process, worker isolates, server, and charged kernel/file
cache memory. Compilation happens before the limited container starts.

| Case | Data | RAM limit | Required outcome |
| --- | --- | --- | --- |
| `limit-control` | Touch and retain 384 MiB | 128 MiB | Kernel OOM kill |
| `archive-512` | 512 MiB, partly compressible | 128 MiB | Exact round trip |
| `archive-1024` | 1 GiB, partly compressible | 128 MiB | Exact round trip |
| `incompressible-128` | 128 MiB deterministic pseudorandom bytes | 128 MiB | Exact round trip |
| `high-expansion-512` | 512 MiB zeros | 128 MiB | Exact round trip |
| `password-128` | 128 MiB with production password KDF | 128 MiB | Exact round trip |
| `password-128-at-256` | Same password-protected archive | 256 MiB | Exact round trip |
| `password-512` | 512 MiB with production password KDF | 128 MiB | Exact round trip |
| `password-repeat-64` | Five password-protected 64 MiB round trips | 128 MiB | All five pass |
| `sync-unlock-128` | Create root, clear key cache, unlock, then 128 MiB archive | 128 MiB | Exact round trip |
| `repeat-64` | Five 64 MiB round trips in one process | 128 MiB | All five pass |
| `faults-64` | 64 MiB, interrupted transfer/cancellation/corruption | 128 MiB | Correct recovery and cleanup |
| `collections-64-at-128` | 64 distinct 382 KiB collection titles | 128 MiB | Boundary probe |
| `collections-513-at-256` | 513 distinct 382 KiB collection titles | 256 MiB | Boundary probe |
| `collections-513-at-512` | Same collection inventory | 512 MiB | Boundary probe |

Archive cases call production ZIP writing, encryption, upload, download,
decryption and extraction. They verify uploaded/downloaded ciphertext SHA-256,
ZIP CRC, restored byte count and restored SHA-256. The highly compressible case
exercises decompression expansion. Password mode uses the production KDF
settings. The sync-unlock case creates and opens a real root marker with default
KDF settings, clears the cache before opening, and uses the returned key for the
archive. It covers crypto/transfer rather than the full profile adoption flow.
Repetition catches growth large enough to exhaust the fixed budget; it is not a
proof that there are no slow leaks.

The recovery case drops an HTTP connection after 1 MiB, requires a retained
prefix, and verifies both the retry's Range offset and reduced response size.
It also cancels during a response body and encryption, then corrupts ciphertext
and requires failed outputs to be removed. This tests protocol behavior; the
Flutter production adapter's forwarding is covered by its existing unit tests.

The collection cases call the production global shard planner and background
section preparation, check the 512-section budget, and compare every returned
record using a deep comparison without full JSON string copies. Every title is
a separate string allocation: shared padding would understate live inventory
memory. These are deliberately adversarial payloads,
not a claim that a typical collection has a 382 KiB title. They expose the cost
of keeping a large structured inventory in memory even when archive I/O streams.

The JSONL report records the copied source and build-input hashes, image identity,
architecture, limits, process RSS, cgroup peak/events, stage timings and Docker
OOM status. Every case also records and verifies its actual container image ID.
For a killed process, logged peak RSS is only a lower bound because the process
cannot emit a final measurement. Cgroup peak includes reclaimable file cache;
it is not the Dart heap size. Probe outcomes are reported as `pass` or `oom`;
an OOM probe is a discovered limitation, not a successful sync. The runner exits
nonzero for any failed operation, an unexpected error/timeout, or unverified
limits. `--allow-probe-oom` explicitly permits exploratory collection OOMs
without failing the run; they still appear as `oom`, never `pass`, in the report.

Containers and their temporary archives are removed after each case. The local
SDK/test images remain reusable. Allow several GiB of free Docker disk space
for the largest archive's source, ZIP, encrypted/uploaded/downloaded files and
restored output. Use `--timeout` to adjust the default 900 seconds per case on
slower hosts.

These tests establish behavior for the exercised production components under
real Linux memory limits. They do **not** run the Flutter renderer, Android
plugins, SQLite export/import, profile registry adoption, preferences parsing,
video playback or Android's app lifecycle/low-memory killer. A 128 MiB container
budget is not equivalent to a TV with 128 MiB physical RAM. Test the full release
app on the target TV before claiming that backup or first sync cannot crash.

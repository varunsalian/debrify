# Mac streaming backup feasibility results

Date: 2026-09-05. Platform: macOS 26.4, arm64.
Status: Standalone archive feasibility validated; application integration pending.

## Method

Built `../prototypes/backup_archive_probe.dart` as a native Dart executable using
the repository package configuration (`archive` 4.0.7). Each benchmark phase
ran in a fresh process, with roughly 13 MiB starting RSS. Reported peak memory
is `ProcessInfo.maxRss`, not Dart heap alone. SQLite fixture creation/integrity
checks run through the system sqlite3 CLI; their child-process RSS is not
included in the Dart peak. Full Flutter app baseline memory is not included.

Synthetic SQLite files contain random 4 KiB saved-hash payloads, a favorite
record, and `user_version=7`. Synthetic M3U files contain repeated channel lines
and nonfunctional example.invalid URLs. No real profiles, credentials, network,
or sync data were read or modified. Fixtures are not actual app database schemas.

Test phases: write archive from file streams; stream-copy to a second local
file and compare source/destination SHA-256; extract file streams; compare each
extracted file with its original SHA-256 and size; check SQLite integrity,
schema version, and favorite record. The largest case was also restored directly
from the saved copy after updating the probe to prefer that path.

These are individual warm/local-filesystem runs, not statistically sampled
benchmarks or power-loss durability tests. They establish feasibility and expose
large allocation differences; timings are not predictions for TV storage.

## Results: stored ZIP entries, no encryption or compression

| Input case | Actual DB + M3U size | Archive write | Peak write RSS | Extract + hashes + SQLite checks | Peak restore RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Small | 13.3 MiB | 0.049 s | 40.6 MiB | 0.087 s | 29.6 MiB |
| Medium | 123.5 MiB | 0.392 s | 44.9 MiB | 0.682 s | 47.1 MiB |
| Large | 613.7 MiB | 1.979 s | 44.9 MiB | 3.308 s | 47.0 MiB |

The large case contains a 590,000,128-byte SQLite file and a 53,495,700-byte M3U.
Archive sizes were 13,918,120; 129,546,858; and 643,496,366 bytes respectively.
Archive write timings exclude initial fixture generation and original hash
calculation. They also exclude app metadata export and snapshot creation.

Stream-copy plus read-back hashing took 0.138 / 1.286 / 6.411 seconds for the
small / medium / large cases; peak RSS was 18.4 / 20.8 / 23.7 MiB. This includes
hashing both files and demonstrates the cost of verification separately from
archive creation. It does not exercise Android's native destination bridge.

Stored-entry write/restore peaks remain approximately flat between 124 MiB and
614 MiB inputs. This supports the proposed file-backed approach for large
databases, rather than claiming a universal fixed memory ceiling.

## Comparison on the same medium input

| Path | Time | Peak RSS | Output size |
| --- | ---: | ---: | ---: |
| Stored ZIP write | 0.392 s | 44.9 MiB | 129,546,858 bytes |
| Level-1 compressed ZIP write | 1.779 s | 405.1 MiB | 106,353,977 bytes |
| Compressed ZIP extraction and validation | 1.013 s | 167.5 MiB | — |
| Whole-file base64 + JSON write | 1.007 s | 799.6 MiB | 172,728,463 bytes |

The JSON comparison deliberately reproduces only whole-file reads, base64,
JSON, and final byte copying. It is NOT the real beta backup implementation or
an end-to-end comparison: it excludes encryption, section hashing, package
checks, SQLite snapshotting, and UI work. Its purpose is allocation comparison.
Random database payloads limit compression; real library compression ratios
and timings can differ.

## Library findings that change the implementation choice

- `archive` 4.0.7 `ZipEncoder.add` compresses an entry into an
  `OutputMemoryStream` before writing it. File input alone does not make the
  compressed writer memory-bounded.
- Its IO zlib decoder uses `ChunkedConversionSink.withCallback`, collecting
  decompressed output until close. The measured compressed restore has a
  substantially higher peak too.
- Stored entries explicitly marked `CompressionType.none` use file streams
  without those whole-entry compression buffers. Merely selecting a low
  compression level is not sufficient.
- `ZipDecoder.decodeStream` has its CRC verification block commented out.
  Do not rely on `verify: true` for integrity. The probe uses independent
  streamed SHA-256 checks against known fixture hashes.

Recommendation: use stored ZIP entries for the first local format. Defer
compression unless a separately validated bounded-memory codec is supplied.
Do not patch the shared archive dependency as part of this isolated work.

## Failure checks

- Deterministically flip one byte in a stored entry: rejected by SHA-256 check.
- Truncate the archive to half its original size: rejected by entry-count check.
- All successful runs preserve file hashes, SQLite integrity, schema version,
  and the synthetic favorite record.

The probe is not a hardened production reader: it trusts a small external
fixture manifest and only accepts its three known entries. It does not prove
malicious ZIP handling, bounded central-directory parsing, decompression-bomb
protection, rollback, or application-level restore authorization.

## What remains before shipping

- Actual app export/restore integration, per-resource allocation limits, and
  selective durable-IPTV snapshot correctness/performance.
- Existing single/all-profile transaction, generation, ID-remapping, migration,
  and cache-refresh behavior using real application schemas.
- Full-app memory/UI responsiveness and old encrypted backup compatibility.
- Low-disk, permission, cancellation and interruption tests in the real save
  flow; production manifest validation and archive limits.
- Android file-save bridge and platform interchange verification. Mac evidence
  is sufficient to proceed with implementation; unavailable physical TV tests
  remain explicitly pending rather than blocking local development.

No backup/restore app code or sync code was changed by this validation.

## Reproduction and retained artifacts

Compile from the repository root:

```sh
dart compile exe --packages=.dart_tool/package_config.json dev/design/prototypes/backup_archive_probe.dart -o /private/tmp/debrify-backup-probe.P7GKvI/probe
```

Use a fresh fixture directory, then invoke the executable with:

```text
fixture <directory> 100
pack <directory> store
copy <directory> store
restore <directory> store
pack <directory> deflate
restore <directory> deflate
json-baseline <directory>
corrupt <directory> store
truncated <directory> store
```

The fixture parameter is approximate random payload MiB; SQLite overhead and
M3U content increase actual size. Tested parameters: 10, 100, 500.
Synthetic files and executable remain under
`/private/tmp/debrify-backup-probe.P7GKvI` for inspection. They are disposable
and are not user backups. The OS may eventually purge this temporary directory.

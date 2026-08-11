## 0.0.3

* **Fix:** `getApplicationSupportDirectory()` no longer returns a path that
  does not exist. The tvOS sandbox refuses to create
  `Library/Application Support`, and that failure was swallowed (`try?`), so
  callers received a path and only discovered the problem at their first write.
  It now returns `null`, which `path_provider` surfaces as
  `MissingPlatformDirectoryException` at the call site.
* **Docs:** corrected the claim that tvOS has "a normal app sandbox" where the
  standard lookups work unchanged. Verified on a physical Apple TV 4K
  (tvOS 26.5): only `Library/Caches` and `tmp` are writable — writes to
  `Documents` are denied, and `Library/Application Support` cannot be created.
  The tvOS simulator permits all of these, which is why this went unnoticed.
* `getApplicationDocumentsDirectory()` now logs a one-time warning on tvOS.
  The path is still returned — Documents exists and reads work — but writes to
  it fail on a physical Apple TV, and silently handing back a path for the most
  common `path_provider` call made that failure hard to trace.
* **Behaviour change:** apps calling `getApplicationSupportDirectory()` on tvOS
  now get an exception instead of an unusable path. Switch to
  `getApplicationCacheDirectory()`, and note that tvOS storage is purgeable by
  platform contract — durable data belongs on a server or in iCloud key-value
  storage.

## 0.0.2

* Add Swift Package Manager support: ships a `tvos/Package.swift` so the
  package can be consumed via SwiftPM (the Flutter 3.44 default) alongside the
  existing CocoaPods podspec. No API or behaviour change.

## 0.0.1

Initial release — **hand-written, maintained** tvOS implementation of
`path_provider` for
[flutter-tvos](https://github.com/fluttertv/flutter-tvos). Upstream
`path_provider_foundation` is a `dart:ffi` / native-assets plugin that
the tvOS toolchain cannot build, so this package is not generated
output — it is a thin native (`NSSearchPath…` / `NSTemporaryDirectory`)
implementation answering the same method-channel contract.

* **Supported:** `getTemporaryDirectory()`,
  `getApplicationDocumentsDirectory()`,
  `getApplicationSupportDirectory()` (auto-created),
  `getApplicationCacheDirectory()` (auto-created),
  `getLibraryDirectory()`.
* **Not supported on tvOS:** `getDownloadsDirectory()` returns `null`
  (no user Downloads dir in the tvOS sandbox);
  `getExternalStoragePath*` / `getExternalCachePaths` throw
  `UnsupportedError` (Android-only, same as iOS).

Verified end-to-end on a physical Apple TV via `video_player_tvos`
(14/14 integration tests). See `README.md` and `PORTING_REPORT.md`
for detail.

# path_provider_tvos

tvOS implementation of [`path_provider`](https://pub.dev/packages/path_provider)
for [flutter-tvos](https://github.com/fluttertv/flutter-tvos).

> **Hand-written, maintained** tvOS implementation. The upstream
> `path_provider_foundation` is a dart:ffi/native-assets plugin that the
> tvOS toolchain cannot build, so this is not generated output.
> **Verified:** exercised on a physical Apple TV via
> `video_player_tvos` (14/14).

## Usage

```yaml
dependencies:
  path_provider: ^2.x
  path_provider_tvos: ^0.0.3
```

## ⚠️ tvOS is not iOS: only two directories are writable

The tvOS sandbox is far more restrictive than the iOS one. Measured on a
physical Apple TV 4K (tvOS 26.5) by writing a file into each directory:

| directory | on a real Apple TV |
|---|---|
| `tmp` | ✅ writable |
| `Library/Caches` | ✅ writable |
| `Documents` | ❌ exists, but **writes are denied** |
| `Library/Application Support` | ❌ **does not exist and cannot be created** |

**The tvOS simulator permits all of these writes**, so code that works in the
simulator can still fail on real hardware. Test storage on a device.

tvOS provides **no persistent local storage** by platform contract: even
`Library/Caches` is purgeable by the OS at any time. Data that must survive
belongs on a server or in iCloud key-value storage.

## tvOS support

### ✅ Supported and writable
- `getTemporaryDirectory()` — `NSTemporaryDirectory()`
- `getApplicationCacheDirectory()` — `Library/Caches/` (auto-created)

### ⚠️ Returned, but not writable
- `getApplicationDocumentsDirectory()` — app `Documents/`. Returned for parity
  with iOS and fine to read from, but writes fail on a real Apple TV. **Use
  `getApplicationCacheDirectory()` instead.** Calling it logs a one-time
  warning so a later write failure is traceable to the sandbox.
- `getLibraryDirectory()` — app `Library/`. The container itself; write to
  `Library/Caches` beneath it.

### ❌ Not supported on tvOS
- `getApplicationSupportDirectory()` → throws `MissingPlatformDirectoryException`.
  The tvOS sandbox refuses to create `Library/Application Support`, so this
  fails at the call rather than handing back an unusable path.
- `getDownloadsDirectory()` → returns `null` (no user Downloads dir).
- `getExternalStorage*` → `UnsupportedError` (Android-only, same as iOS).

See `PORTING_REPORT.md` for detail.

## Dependency management

Supports both **Swift Package Manager** and **CocoaPods** from a single
source tree. `flutter-tvos` wires the right one automatically: apps on
Flutter 3.44+ link it via SwiftPM (this package ships a `tvos/Package.swift`),
while CocoaPods-based projects keep using the podspec. No manual setup needed.

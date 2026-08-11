// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Maintained tvOS implementation of `path_provider`.
//
// The tvOS sandbox is NOT the iOS sandbox. Measured on a physical Apple TV 4K
// (tvOS 26.5) by writing a file into each directory:
//
//   tmp                          writable
//   Library/Caches               writable
//   Documents                    exists, but writes are DENIED (errno 1)
//   Library/Application Support  does not exist and CANNOT be created (errno 1)
//
// Only Caches and tmp are usable for writing. tvOS provides no persistent
// local storage by platform contract — data that must survive belongs on a
// server or in iCloud key-value storage, and even Caches is purgeable at any
// time. The tvOS *simulator* permits all of these writes, so this difference
// appears only on real hardware.
//
// Documents is still returned: it is a real directory and reads work. Callers
// simply must not write there. Application Support returns nil instead of a
// path that neither exists nor can be created — path_provider turns nil into
// MissingPlatformDirectoryException at the call site, which is far easier to
// diagnose than an errno at the caller's first write.
//
// There is no user-facing Downloads directory on tvOS, so that request returns
// nil (matching iOS/path_provider, where downloads is macOS-only).

import Flutter
import Foundation

public class PathProviderPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "plugins.flutter.io/path_provider",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PathProviderPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getTemporaryDirectory":
      result(NSTemporaryDirectory())
    case "getApplicationDocumentsDirectory":
      // Returned for parity with iOS, but NOT writable on tvOS — see above.
      // Warn once so the write that fails later is traceable to the sandbox
      // rather than to an errno that names nothing.
      _ = PathProviderPlugin.warnDocumentsNotWritable
      result(directory(.documentDirectory))
    case "getApplicationSupportDirectory":
      // PATCHED (Debrify): upstream returns nil here, because Application
      // Support cannot be created in the tvOS sandbox. nil becomes a
      // MissingPlatformDirectoryException in Dart, which is honest but breaks
      // every DEPENDENCY that asks for this path and has no tvOS branch to
      // fall back to — flutter_cache_manager (so no image ever caches, i.e. no
      // artwork anywhere), google_fonts (so text falls back), and
      // background_downloader. Those are not call sites we can route around.
      //
      // Hand back a namespaced subdirectory of Caches instead. It is writable,
      // and on tvOS it is the only thing that is. The cost is that the system
      // may purge it under storage pressure — correct for caches and fonts,
      // and no worse than the alternative, since tvOS offers no persistent
      // local storage at all. Anything that must survive belongs on a server.
      result(ensuredSubdirectory(of: .cachesDirectory, named: "ApplicationSupport"))
    case "getApplicationCacheDirectory":
      result(ensuredDirectory(.cachesDirectory))
    case "getLibraryDirectory":
      result(directory(.libraryDirectory))
    case "getDownloadsDirectory":
      // No user Downloads directory in the tvOS sandbox.
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Emitted the first time Documents is requested. `static let` is lazily
  /// initialised exactly once per process, so this is a thread-safe one-shot.
  /// Documents is still returned — it exists, reads work, and some apps ship
  /// pre-populated data there — but writes to it fail on a real Apple TV, and
  /// silently returning a path for the most common path_provider call is what
  /// makes that failure hard to place.
  private static let warnDocumentsNotWritable: Void = {
    NSLog(
      "[path_provider_tvos] getApplicationDocumentsDirectory(): on a physical "
        + "Apple TV, Documents is readable but NOT writable. Use "
        + "getApplicationCacheDirectory() for files your app writes. "
        + "(The tvOS simulator permits the write, so this only fails on device.)")
  }()

  private func directory(_ type: FileManager.SearchPathDirectory) -> String? {
    return NSSearchPathForDirectoriesInDomains(type, .userDomainMask, true)
      .first
  }

  /// Application Support / Caches are not guaranteed to exist on first launch,
  /// so create them when missing (mirroring path_provider_foundation on
  /// iOS/macOS). On tvOS the creation genuinely fails for Application Support,
  /// so the error is surfaced rather than swallowed: `try?` here would return a
  /// path that does not exist, and the caller would only find out at its first
  /// write, with an errno that names nothing useful.
  /// A created-on-demand subdirectory of a search-path directory. Used to give
  /// Application Support a real, writable home under Caches — see the patch
  /// note at the call site.
  private func ensuredSubdirectory(
    of type: FileManager.SearchPathDirectory,
    named name: String
  ) -> String? {
    guard let base = ensuredDirectory(type) else { return nil }
    let path = (base as NSString).appendingPathComponent(name)
    if !FileManager.default.fileExists(atPath: path) {
      do {
        try FileManager.default.createDirectory(
          atPath: path, withIntermediateDirectories: true, attributes: nil)
      } catch {
        NSLog(
          "[path_provider_tvos] cannot create \(path): "
            + "\(error.localizedDescription)")
        return nil
      }
    }
    return path
  }

  private func ensuredDirectory(
    _ type: FileManager.SearchPathDirectory
  ) -> String? {
    guard let path = directory(type) else { return nil }
    if !FileManager.default.fileExists(atPath: path) {
      do {
        try FileManager.default.createDirectory(
          atPath: path, withIntermediateDirectories: true, attributes: nil)
      } catch {
        NSLog(
          "[path_provider_tvos] cannot create \(path): "
            + "\(error.localizedDescription). The tvOS sandbox only permits "
            + "writes to Library/Caches and tmp.")
        return nil
      }
    }
    return path
  }
}

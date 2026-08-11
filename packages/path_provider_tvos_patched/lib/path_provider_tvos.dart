// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Maintained tvOS implementation of `path_provider`.
//
// The platform-interface method-channel contract
// (`plugins.flutter.io/path_provider`) is reused verbatim — the native
// `PathProviderPlugin` answers the same method names the iOS/macOS
// implementation does, so the Dart side is a thin federated forwarder.

import 'package:flutter/services.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// tvOS implementation of `path_provider`.
///
/// `base` is required because `PathProviderPlatform` is a `base class`.
base class PathProviderTvos extends PathProviderPlatform {
  static const MethodChannel _channel =
      MethodChannel('plugins.flutter.io/path_provider');

  /// Registers this class as the tvOS `path_provider` implementation.
  static void registerWith() {
    PathProviderPlatform.instance = PathProviderTvos();
  }

  @override
  Future<String?> getTemporaryPath() =>
      _channel.invokeMethod<String>('getTemporaryDirectory');

  @override
  Future<String?> getApplicationSupportPath() =>
      _channel.invokeMethod<String>('getApplicationSupportDirectory');

  @override
  Future<String?> getLibraryPath() =>
      _channel.invokeMethod<String>('getLibraryDirectory');

  @override
  Future<String?> getApplicationDocumentsPath() =>
      _channel.invokeMethod<String>('getApplicationDocumentsDirectory');

  @override
  Future<String?> getApplicationCachePath() =>
      _channel.invokeMethod<String>('getApplicationCacheDirectory');

  @override
  Future<String?> getDownloadsPath() async => null; // None on tvOS.

  // Android-only APIs: keep behaviour identical to the iOS/macOS
  // implementation (unsupported off Android).
  @override
  Future<String?> getExternalStoragePath() => throw UnsupportedError(
      'getExternalStoragePath is not supported on tvOS');

  @override
  Future<List<String>?> getExternalCachePaths() => throw UnsupportedError(
      'getExternalCachePaths is not supported on tvOS');

  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) =>
      throw UnsupportedError(
          'getExternalStoragePaths is not supported on tvOS');
}

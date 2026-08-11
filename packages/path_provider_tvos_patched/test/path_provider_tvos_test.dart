// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show Directory;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_tvos/path_provider_tvos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> log;

  /// Answers the native side with [responses], recording every method name.
  /// A missing key answers null, which is what the tvOS plugin returns for a
  /// directory the sandbox will not give us.
  void mockNative(Map<String, String?> responses) {
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      log.add(call.method);
      return responses[call.method];
    });
  }

  setUp(() {
    log = <String>[];
    PathProviderTvos.registerWith();
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('registerWith installs itself as the platform implementation', () {
    expect(PathProviderPlatform.instance, isA<PathProviderTvos>());
  });

  group('method-channel contract', () {
    test('each getter invokes the matching native method', () async {
      mockNative(<String, String?>{
        'getTemporaryDirectory': '/tmp',
        'getApplicationSupportDirectory': '/support',
        'getLibraryDirectory': '/library',
        'getApplicationDocumentsDirectory': '/documents',
        'getApplicationCacheDirectory': '/caches',
      });
      final tvos = PathProviderTvos();

      expect(await tvos.getTemporaryPath(), '/tmp');
      expect(await tvos.getApplicationSupportPath(), '/support');
      expect(await tvos.getLibraryPath(), '/library');
      expect(await tvos.getApplicationDocumentsPath(), '/documents');
      expect(await tvos.getApplicationCachePath(), '/caches');

      expect(log, <String>[
        'getTemporaryDirectory',
        'getApplicationSupportDirectory',
        'getLibraryDirectory',
        'getApplicationDocumentsDirectory',
        'getApplicationCacheDirectory',
      ]);
    });

    test('downloads resolves to null without touching the channel', () async {
      mockNative(<String, String?>{});
      expect(await PathProviderTvos().getDownloadsPath(), isNull);
      expect(log, isEmpty);
    });

    test('Android-only APIs throw UnsupportedError', () async {
      final tvos = PathProviderTvos();
      expect(tvos.getExternalStoragePath, throwsUnsupportedError);
      expect(tvos.getExternalCachePaths, throwsUnsupportedError);
      expect(tvos.getExternalStoragePaths, throwsUnsupportedError);
    });
  });

  group('directories the tvOS sandbox refuses', () {
    // The native side returns nil for Application Support because tvOS will not
    // let us create it (measured on a physical Apple TV). Returning a path that
    // does not exist is what this replaced: the caller used to find out only at
    // its first write, as an errno naming nothing.
    test('a null Application Support surfaces as an exception, not a path',
        () async {
      mockNative(<String, String?>{'getApplicationSupportDirectory': null});

      expect(await PathProviderTvos().getApplicationSupportPath(), isNull);
      await expectLater(
        getApplicationSupportDirectory(),
        throwsA(isA<MissingPlatformDirectoryException>()),
      );
    });

    test('Documents is still returned — it exists and reads work', () async {
      mockNative(<String, String?>{
        'getApplicationDocumentsDirectory': '/documents',
      });

      // Deliberately NOT null: nil'ing this would break iOS parity and any app
      // reading pre-populated data. Writes fail on device; the plugin logs a
      // one-time warning and the README says so.
      expect(await getApplicationDocumentsDirectory(),
          isA<Directory>().having((Directory d) => d.path, 'path', '/documents'));
    });
  });
}

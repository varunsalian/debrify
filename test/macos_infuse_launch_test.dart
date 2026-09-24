import 'dart:io';

import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  const videoUrl =
      'https://example.com/Arcane%20S02E02.mkv?token=a%2Bb&name=日本語+#part';
  final calls = <MethodCall>[];
  var opened = true;
  var throws = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfilePreferenceBudget.debugReset();
    calls.clear();
    opened = true;
    throws = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (throws) {
            throw PlatformException(code: 'launch_failed', message: videoUrl);
          }
          return opened;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    ProfilePreferenceBudget.debugReset();
    ProfileRuntime.debugReset();
  });

  void expectInfuseHandoff() {
    expect(calls, hasLength(1));
    expect(calls.single.method, 'launch');
    final arguments = calls.single.arguments as Map;
    final uri = Uri.parse(arguments['url'] as String);
    expect(uri.scheme, 'infuse');
    expect(uri.host, 'x-callback-url');
    expect(uri.path, '/play');
    expect(uri.queryParameters, {'url': videoUrl});
    expect(arguments['useSafariVC'], isFalse);
    expect(arguments['useWebView'], isFalse);
  }

  group('macOS Infuse', () {
    test('hands the complete encoded URL to Infuse', () async {
      final result = await ExternalPlayerService.launchWithPlayer(
        videoUrl,
        ExternalPlayer.infuse,
      );
      expect(result.success, isTrue);
      expect(result.usedPlayer, ExternalPlayer.infuse);
      expectInfuseHandoff();
    });

    test(
      'preferred Infuse uses the scheme without an app-directory check',
      () async {
        await StorageService.setPreferredExternalPlayer('infuse');
        final result = await ExternalPlayerService.launchWithPreferredPlayer(
          videoUrl,
        );
        expect(result.success, isTrue);
        expect(result.usedPlayer, ExternalPlayer.infuse);
        expectInfuseHandoff();
      },
    );

    for (final throwOnLaunch in [false, true]) {
      test(
        'launch ${throwOnLaunch ? 'exception' : 'rejection'} reports failure without browser fallback',
        () async {
          opened = false;
          throws = throwOnLaunch;
          await StorageService.setPreferredExternalPlayer('infuse');
          final result = await ExternalPlayerService.launchWithPreferredPlayer(
            videoUrl,
          );
          expect(result.success, isFalse);
          expect(result.usedPlayer, isNull);
          expect(result.errorMessage, contains('Could not open Infuse'));
          expect(result.errorMessage, isNot(contains(videoUrl)));
          expectInfuseHandoff();
        },
      );
    }
  }, skip: !Platform.isMacOS);
}

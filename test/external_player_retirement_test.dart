import 'dart:async';

import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('debrify/tvurl');
  const url = 'https://example.test/video.mp4';
  final calls = <String>[];
  late Completer<bool> canOpen;
  late Completer<bool> opened;
  var active = true;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    PlatformUtil.debugSetTvOS(true);
    active = true;
    calls.clear();
    canOpen = Completer<bool>();
    opened = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'canOpen' ? canOpen.future : opened.future;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    PlatformUtil.debugSetTvOS(null);
    ProfileRuntime.debugReset();
  });

  test('retired preferred launch performs no platform discovery', () async {
    active = false;
    final result = await ExternalPlayerService.launchWithPreferredIOSPlayer(
      url,
      canContinue: () => active,
    );
    expect(result.success, isFalse);
    expect(calls, isEmpty);
  });

  test('retirement during scheme discovery prevents dispatch', () async {
    final launch = ExternalPlayerService.launchWithIOSPlayer(
      url,
      iOSExternalPlayer.infuse,
      canContinue: () => active,
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['canOpen']);
    active = false;
    canOpen.complete(true);
    expect((await launch).success, isFalse);
    expect(calls, ['canOpen']);
  });

  test(
    'accepted dispatch remains successful when its response arrives late',
    () async {
      final launch = ExternalPlayerService.launchWithIOSPlayer(
        url,
        iOSExternalPlayer.infuse,
        canContinue: () => active,
      );
      canOpen.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['canOpen', 'open']);
      active = false;
      opened.complete(true);
      expect((await launch).success, isTrue);
      expect(calls, ['canOpen', 'open']);
    },
  );

  test('unguarded callers keep discovery and launch behavior', () async {
    final launch = ExternalPlayerService.launchWithIOSPlayer(
      url,
      iOSExternalPlayer.infuse,
    );
    canOpen.complete(true);
    opened.complete(true);
    expect((await launch).success, isTrue);
    expect(calls, ['canOpen', 'open']);
  });
}

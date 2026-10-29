import 'dart:async';
import 'dart:io';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/fake_player.dart';

void main() {
  const enabled = bool.fromEnvironment('DEBRIFY_VP_TEST_HOOKS');

  tearDown(() {
    if (enabled) VpS2Hooks.install(null);
  });

  test('S2 native defaults are unchanged without an installed override', () {
    expect(VpS2Hooks.isIOS, Platform.isIOS);
    expect(VpS2Hooks.isAndroid, Platform.isAndroid);
    expect(VpS2Hooks.isAndroidRendererValidation, Platform.isAndroid);
  });

  test('S2f renderer validation is independent of the Android override', () {
    if (!enabled) return;
    final calls = <String>[];
    VpS2Hooks.install(
      VpS2Hooks(
        android: () {
          calls.add('android');
          return true;
        },
      ),
    );
    expect(VpS2Hooks.isAndroidRendererValidation, Platform.isAndroid);
    expect(calls, isEmpty);
    expect(VpS2Hooks.isAndroid, isTrue);
    expect(calls, ['android']);
    calls.clear();
    var validation = true;
    VpS2Hooks.install(
      VpS2Hooks(
        androidRendererValidation: () {
          calls.add('validation');
          return validation;
        },
      ),
    );
    expect(VpS2Hooks.isAndroid, Platform.isAndroid);
    expect(calls, isEmpty);
    expect(VpS2Hooks.isAndroidRendererValidation, isTrue);
    validation = false;
    expect(VpS2Hooks.isAndroidRendererValidation, isFalse);
    expect(calls, ['validation', 'validation']);
  });

  test('S2 installation requires the explicit test-only compile-time flag', () {
    if (enabled) {
      expect(() => VpS2Hooks.install(null), returnsNormally);
    } else {
      expect(() => VpS2Hooks.install(null), throwsStateError);
    }
  });

  test('S2 live overrides evaluate once and partial hooks keep defaults', () {
    if (!enabled) return;
    var ios = false;
    var android = true;
    final calls = <String>[];
    VpS2Hooks.install(
      VpS2Hooks(
        ios: () {
          calls.add('ios');
          return ios;
        },
        android: () {
          calls.add('android');
          return android;
        },
      ),
    );
    expect(VpS2Hooks.isIOS, isFalse);
    expect(VpS2Hooks.isAndroid, isTrue);
    expect(calls, ['ios', 'android']);
    ios = true;
    android = false;
    calls.clear();
    expect(VpS2Hooks.isIOS, isTrue);
    expect(VpS2Hooks.isAndroid, isFalse);
    expect(calls, ['ios', 'android']);
    VpS2Hooks.install(VpS2Hooks(ios: () => false));
    expect(VpS2Hooks.isIOS, isFalse);
    expect(VpS2Hooks.isAndroid, Platform.isAndroid);
  });

  test(
    'fake handles distinguish instances and permit held old delivery',
    () async {
      final first = FakePlayer(const mk.PlayerConfiguration());
      final replacement = FakePlayer(const mk.PlayerConfiguration());
      final held = Completer<void>();
      first.delays['handle'] = held;
      var delivered = false;
      final oldHandle = first.handle.then((value) {
        delivered = true;
        return value;
      });
      final replacementHandle = await replacement.handle;
      expect(delivered, isFalse);
      expect(replacementHandle, isNot(first.handleValue));
      held.complete();
      expect(await oldHandle, first.handleValue);
      expect(first.calls.single.$1, 'handle');
      final controlled = FakePlayer(
        const mk.PlayerConfiguration(),
        handle: 901,
      );
      expect(await controlled.handle, 901);
      controlled.failures['handle'] = StateError('held native handle failure');
      await expectLater(controlled.handle, throwsStateError);
      await first.closeStreams();
      await replacement.closeStreams();
      await controlled.closeStreams();
    },
  );
}

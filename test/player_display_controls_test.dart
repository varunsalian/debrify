import 'package:debrify/services/player_display_controls.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'foreground wake owners cannot release playback or each other',
    () async {
      final calls = <bool>[];
      final controls = PlayerDisplayControls(
        toggleWakelock: (value) async {
          calls.add(value);
        },
      );
      final first = Object();
      final second = Object();
      await controls.setWakelock(true);
      await controls.setWakelockOwner(first, true);
      await controls.setWakelockOwner(second, true);
      await controls.setWakelock(false);
      expect(calls.last, isTrue);
      await controls.setWakelockOwner(first, false);
      expect(calls.last, isTrue);
      await controls.setWakelock(true);
      await controls.setWakelockOwner(second, false);
      expect(calls.last, isTrue);
      await controls.setWakelock(false);
      expect(calls.last, isFalse);
    },
  );

  tearDown(() => debugDefaultTargetPlatformOverride = null);
  for (final platform in [TargetPlatform.linux, TargetPlatform.fuchsia]) {
    test('$platform skips unsupported brightness calls', () async {
      debugDefaultTargetPlatformOverride = platform;
      var calls = 0;
      final controls = PlayerDisplayControls(
        readBrightness: () async {
          calls++;
          return 0.8;
        },
        writeBrightness: (_) async {
          calls++;
        },
        resetBrightness: () async {
          calls++;
        },
      );
      expect(await controls.brightness(), 0.5);
      await controls.setBrightness(0.7);
      await controls.resetBrightness();
      expect(calls, 0);
    });
  }
  test(
    'native asynchronous failures do not escape display operations',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      Future<T> fail<T>() async {
        await Future<void>.delayed(Duration.zero);
        throw MissingPluginException('unavailable');
      }

      final controls = PlayerDisplayControls(
        readBrightness: fail<double>,
        writeBrightness: (_) => fail<void>(),
        resetBrightness: fail<void>,
        toggleWakelock: (_) => fail<void>(),
      );
      expect(await controls.brightness(), 0.5);
      await controls.setBrightness(0.7);
      await controls.resetBrightness();
      await controls.setWakelock(true);
      await controls.setWakelock(false);
    },
  );
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  ]) {
    test('$platform preserves supported controls', () async {
      debugDefaultTargetPlatformOverride = platform;
      final calls = <Object>[];
      final controls = PlayerDisplayControls(
        readBrightness: () async => 0.8,
        writeBrightness: (value) async {
          calls.add(value);
        },
        resetBrightness: () async {
          calls.add('reset');
        },
        toggleWakelock: (value) async {
          calls.add(value);
        },
      );
      expect(await controls.brightness(), 0.8);
      await controls.setBrightness(0.2);
      await controls.resetBrightness();
      await controls.setWakelock(true);
      await controls.setWakelock(false);
      expect(calls, [0.2, 'reset', true, false]);
    });
  }
}

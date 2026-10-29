// Swipe-to-seek can be turned off, and pans that start in the system
// back-gesture zones (24 px at either side edge) never seek or change volume.
import 'package:debrify/features/video_player/data/player_gesture_settings.dart';
import 'package:debrify/screens/video_player/models/hud_state.dart';
import 'package:debrify/screens/video_player/widgets/seek_hud.dart';
import 'package:debrify/screens/video_player/widgets/vertical_hud.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/p21_controls_driver.dart';
import 'support/trakt_transport.dart';

const _at = Duration(seconds: 300);

Future<P21Driver> _mount(WidgetTester t, {bool swipeSeek = true}) async {
  final d = P21Driver(t);
  await d.initialize();
  await PlayerGestureSettings.setSwipeSeek(swipeSeek);
  await d.mount(screen: P21Driver.screen());
  await d.wait(4000);
  await d.at(_at);
  return d;
}

SeekHudState? _seekHud(WidgetTester t) {
  final hud = find.byType(SeekHud);
  return hud.evaluate().isEmpty ? null : t.widget<SeekHud>(hud).hud;
}

VerticalHudState? _verticalHud(WidgetTester t) {
  final hud = find.byType(VerticalHud);
  return hud.evaluate().isEmpty ? null : t.widget<VerticalHud>(hud).hud;
}

Future<void> _start(P21Driver d, Offset at) async {
  d.observe(() => d.gestures.onPanStart!(DragStartDetails(localPosition: at)));
  await d.wait(0);
  await d.wait(0);
}

void _update(P21Driver d, Offset at) => d.observe(
  () => d.gestures.onPanUpdate!(
    DragUpdateDetails(globalPosition: at, localPosition: at),
  ),
);

Future<void> _end(P21Driver d) async {
  d.observe(() => d.gestures.onPanEnd!(DragEndDetails()));
  await d.wait(0);
}

void main() {
  p21Timeouts();
  TraktTestTransport.install();
  setUp(() => PlayerGestureSettings.swipeSeekCached = true);

  test('swipe seek is on by default and the choice is stored', () async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    addTearDown(ProfileRuntime.debugReset);
    expect(await PlayerGestureSettings.load(), isTrue);
    await PlayerGestureSettings.setSwipeSeek(false);
    expect(PlayerGestureSettings.swipeSeekCached, isFalse);
    final prefs = await ProfilePreferences.instance();
    expect(prefs.getBool(PlayerGestureSettings.swipeSeekKey), isFalse);
    PlayerGestureSettings.swipeSeekCached = true;
    expect(await PlayerGestureSettings.load(), isFalse);
    expect(PlayerGestureSettings.swipeSeekCached, isFalse);
  });

  testWidgets('with swipe seek off a horizontal pan does nothing', (t) async {
    final d = await _mount(t, swipeSeek: false);
    try {
      await _start(d, const Offset(640, 400));
      _update(d, const Offset(700, 405));
      _update(d, const Offset(768, 410));
      await d.wait(0);
      expect(_seekHud(t), isNull);
      expect(_verticalHud(t), isNull);
      await _end(d);
      expect(d.seeks, isEmpty);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  testWidgets('with swipe seek off a vertical pan still changes volume', (
    t,
  ) async {
    final d = await _mount(t, swipeSeek: false);
    try {
      await _start(d, const Offset(900, 400));
      _update(d, const Offset(900, 450));
      await d.wait(0);
      expect(_verticalHud(t)?.kind, VerticalKind.volume);
      await _end(d);
      expect(d.seeks, isEmpty);
    } finally {
      await d.close();
    }
  });

  testWidgets('a pan from either side edge never seeks or changes volume', (
    t,
  ) async {
    final d = await _mount(t);
    try {
      for (final x in [10.0, 23.0, 1257.0, 1270.0]) {
        await _start(d, Offset(x, 400));
        _update(d, Offset(x + 80, 400));
        _update(d, Offset(x + 80, 470));
        await d.wait(0);
        expect(_seekHud(t), isNull, reason: 'x=$x');
        expect(_verticalHud(t), isNull, reason: 'x=$x');
        await _end(d);
        await d.wait(300);
      }
      expect(d.seeks, isEmpty);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  testWidgets('a pan just inside the guard seeks as before', (t) async {
    final d = await _mount(t);
    try {
      await _start(d, const Offset(24, 400));
      _update(d, const Offset(152, 400));
      await d.wait(0);
      expect(_seekHud(t)?.target, const Duration(seconds: 312));
      await _end(d);
      expect(d.seeks, [const Duration(seconds: 312)]);
    } finally {
      await d.close();
    }
  });
}

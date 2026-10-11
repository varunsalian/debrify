import 'dart:async';

import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing resolved interface; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'player_actions.dart';
import 'video_player_environment.dart';

Future<PlayerMenuPanel> sleepMenu(
  WidgetTester tester,
  VideoPlayerEnvironment fixture,
) async {
  if (find.byType(TvControls).evaluate().isNotEmpty) {
    tester.widget<TvControls>(find.byType(TvControls)).onSleepTimer();
  } else {
    playerControls(tester).onSleepTimer();
  }
  await fixture.advance(tester);
  await fixture.advance(tester, const Duration(milliseconds: 400));
  expect(find.byType(PlayerMenuPanel), findsOneWidget);
  final panel = tester.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
  expect(panel.initialSection, PlayerMenuSection.sleep);
  return panel;
}

Future<void> pickSleep(
  WidgetTester tester,
  VideoPlayerEnvironment fixture,
  SleepTimerSelection selection,
) async {
  final menu = await sleepMenu(tester, fixture);
  expect(() => menu.onSleepSelected(selection), returnsNormally);
  await fixture.advance(tester);
}

/// Snackbars queue in the original. Observe the requested toast as it enters
/// the screen, rather than skipping over it with one large elapsed-time jump.
Future<void> waitSleepToast(
  WidgetTester tester,
  VideoPlayerEnvironment fixture,
  String message,
) async {
  for (var i = 0; i < 600 && find.text(message).evaluate().isEmpty; i++) {
    await fixture.advance(tester, const Duration(milliseconds: 20));
  }
  expect(find.text(message), findsOneWidget);
}

/// Intercepts the existing preference transport. It can suspend a real resume
/// write, without exposing the State or replacing _saveResume.
class SleepResumeWrites extends InMemorySharedPreferencesStore {
  SleepResumeWrites(super.values) : super.withData();
  final writes = <(String, Object)>[];
  final resumed = <String>[];
  Completer<void>? barrier;
  bool entered = false;
  bool Function(String key)? block;

  static Future<SleepResumeWrites> install() async {
    final store = SleepResumeWrites(
      await SharedPreferencesStorePlatform.instance.getAll(),
    );
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    return store;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes.add((key, value));
    if (barrier != null &&
        (block?.call(key) ?? key.endsWith('playback_state_v1'))) {
      entered = true;
      await barrier!.future;
    }
    final result = await super.setValue(type, key, value);
    resumed.add(key);
    return result;
  }

  void release() {
    if (barrier?.isCompleted == false) barrier!.complete();
    barrier = null;
  }
}

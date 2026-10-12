import 'dart:async';

import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/widgets/aspect_ratio_video.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_appearance_storage.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'player_actions.dart';
import 'video_player_environment.dart';

VideoPlayerScreen displayScreen({
  bool hideBackButton = false,
  bool hideOptions = false,
  List<PlaylistEntry>? playlist,
}) => VideoPlayerScreen(
  videoUrl: playlist?.first.url ?? 'https://player.test/display.mp4',
  title: playlist?.first.title ?? 'Display fixture',
  hideBackButton: hideBackButton,
  hideOptions: hideOptions,
  playlist: playlist,
);

GestureDetector displayGesture(WidgetTester t) => t.widget<GestureDetector>(
  find.byWidgetPredicate(
    (w) => w is GestureDetector && w.onLongPressStart != null,
  ),
);

double speedHudOpacity(WidgetTester t) => t
    .widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.text('2× Speed'),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

class DisplayModeDriver {
  DisplayModeDriver(this.t, this.f);
  final WidgetTester t;
  final VideoPlayerEnvironment f;
  Future<void> rebuild(VideoPlayerScreen screen) async {
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: f.navigator,
        theme: ThemeData.dark(),
        home: screen,
      ),
    );
    await f.advance(t);
  }

  List<double> get rates => f.player.calls
      .where((c) => c.$1 == 'rate')
      .map((c) => c.$2 as double)
      .toList();

  Future<void> defaults({int aspect = 0, String dock = 'classic'}) async {
    await t.runAsync(() async {
      await PlayerSettingsStorage.setPlayerDefaultAspectIndex(aspect);
      await PlayerAppearanceStorage.setPlayerDockStyle(dock);
    });
  }

  Future<PlayerMenuPanel> menu(PlayerMenuSection section) async {
    if (find.byType(TvControls).evaluate().isNotEmpty) {
      final controls = t.widget<TvControls>(find.byType(TvControls));
      (section == PlayerMenuSection.speed
              ? controls.onSpeed
              : controls.onAspect)
          .call();
    } else {
      final controls = playerControls(t);
      (section == PlayerMenuSection.speed
              ? controls.onSpeed
              : controls.onAspect)
          .call();
    }
    await f.advance(t);
    await f.advance(t, const Duration(milliseconds: 350));
    expect(find.byType(PlayerMenuPanel), findsOneWidget);
    final panel = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
    expect(panel.initialSection, section);
    return panel;
  }

  Future<void> closeMenu() async {
    t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel)).onClose();
    await f.advance(t, const Duration(milliseconds: 350));
    expect(find.byType(PlayerMenuPanel), findsNothing);
  }

  Future<void> speed(double value) async {
    final panel = await menu(PlayerMenuSection.speed);
    panel.onSpeedSelected(value);
    await f.advance(t);
    expect(
      find.byType(TvControls).evaluate().isNotEmpty
          ? t.widget<TvControls>(find.byType(TvControls)).speed
          : playerControls(t).speed,
      value,
    );
    await closeMenu();
  }

  Future<void> aspect(AspectMode value) async {
    final panel = await menu(PlayerMenuSection.aspect);
    panel.onAspectSelected(value);
    await f.advance(t);
    expect(
      find.byType(TvControls).evaluate().isNotEmpty
          ? t.widget<TvControls>(find.byType(TvControls)).aspectMode
          : playerControls(t).aspectMode,
      value,
    );
    await closeMenu();
  }

  Future<void> startHold([Offset at = const Offset(640, 400)]) async {
    displayGesture(t).onLongPressStart!(
      LongPressStartDetails(localPosition: at, globalPosition: at),
    );
    await f.advance(t);
  }

  Future<void> endHold() async {
    displayGesture(t).onLongPressEnd!(const LongPressEndDetails());
    await f.advance(t);
  }

  void expectAspect(AspectMode mode, BoxFit fit, double? ratio) {
    expect(playerControls(t).aspectMode, mode);
    expect(t.widget<mkv.Video>(find.byType(mkv.Video)).fit, fit);
    if (ratio == null) {
      expect(find.byType(AspectRatioVideo), findsNothing);
    } else {
      expect(find.byType(AspectRatioVideo), findsOneWidget);
      final wrapper = t.widget<AspectRatioVideo>(find.byType(AspectRatioVideo));
      expect(wrapper.customAspectRatio, ratio);
      expect(wrapper.currentFit, fit);
      expect(
        t
            .widget<AspectRatio>(
              find
                  .descendant(
                    of: find.byType(AspectRatioVideo),
                    matching: find.byType(AspectRatio),
                  )
                  .first,
            )
            .aspectRatio,
        ratio,
      );
    }
  }

  Future<Map<String, dynamic>> record({
    String title = 'Display fixture',
    double? speed,
    String? aspect,
  }) async {
    Map<String, dynamic>? value;
    for (var i = 0; i < 40; i++) {
      value = await t.runAsync<Map<String, dynamic>?>(
        () => VideoProgressStorage.getVideoPlaybackState(videoTitle: title),
      );
      if (value != null &&
          (speed == null || value['speed'] == speed) &&
          (aspect == null || value['aspect'] == aspect)) {
        break;
      }
      await f.advance(t);
    }
    expect(value, isNotNull);
    return value!;
  }
}

/// Records the existing platform transport and timers created by the actual
/// public Controls callback, including its continuations after await.
class DisplayOrientationDriver {
  DisplayOrientationDriver(this.f) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          f.channels.add(('flutter/platform', call));
          calls.add(call);
          if (hold && call.method == 'SystemChrome.setPreferredOrientations') {
            final reply = Completer<Object?>();
            pending.add(reply);
            return reply.future;
          }
          return null;
        });
  }
  final VideoPlayerEnvironment f;
  final calls = <MethodCall>[];
  final pending = <Completer<Object?>>[];
  final timers = <(Duration, Timer)>[];
  bool hold = false;
  List<Object?> get orientations => calls
      .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
      .map((c) => c.arguments)
      .toList();
  List<Timer> get hideTimers => timers
      .where((entry) => entry.$1 == const Duration(seconds: 3))
      .map((entry) => entry.$2)
      .toList();

  Future<void> toggle(Controls controls) => Zone.current
      .fork(
        specification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createTimer(zone, duration, callback);
            timers.add((duration, timer));
            return timer;
          },
        ),
      )
      .run(() => Function.apply(controls.onRotate, const []) as Future<void>);

  void releaseAll() {
    for (final reply in pending) {
      if (!reply.isCompleted) reply.complete();
    }
  }
}

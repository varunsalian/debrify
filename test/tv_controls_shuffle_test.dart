import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    VoidCallback? onRandom,
    bool live = false,
    bool hideOptions = false,
    bool transitioning = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(960, 540));
    final scope = FocusScopeNode();
    final play = FocusNode();
    final progress = FocusNode();
    final clock = ValueNotifier(const PlaybackUiClockValue.zero());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      scope.dispose();
      play.dispose();
      progress.dispose();
      clock.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvControls(
            title: 'Episode',
            subtitle: null,
            clock: clock,
            isPlaying: true,
            isLive: live,
            isTransitioning: transitioning,
            scopeNode: scope,
            playPauseFocusNode: play,
            progressFocusNode: progress,
            progressFocusable: false,
            onPlayPause: () {},
            onShowTracks: () {},
            onSpeed: () {},
            onAspect: () {},
            onSleepTimer: () {},
            onNext: () {},
            onPrevious: () {},
            onShowPlaylist: () {},
            onShowSources: () {},
            onRandom: onRandom,
            hideOptions: hideOptions,
            speed: 1,
            aspectMode: AspectMode.contain,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('remote traversal reaches Shuffle and Enter activates it', (
    tester,
  ) async {
    var calls = 0;
    await mount(tester, onRandom: () => calls++);
    final icon = find.byIcon(Icons.shuffle_rounded);
    expect(icon, findsOneWidget);
    var reached = false;
    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      if (Focus.of(tester.element(icon)).hasPrimaryFocus) {
        reached = true;
        break;
      }
    }
    expect(reached, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported sessions omit Shuffle', (tester) async {
    await mount(tester);
    expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
  });

  testWidgets('live playback omits Shuffle', (tester) async {
    await mount(tester, live: true, onRandom: () {});
    expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
  });

  testWidgets('hidden options omit Shuffle', (tester) async {
    await mount(tester, hideOptions: true, onRandom: () {});
    expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
  });

  testWidgets('Shuffle cannot activate during a transition', (tester) async {
    var calls = 0;
    await mount(tester, transitioning: true, onRandom: () => calls++);
    await tester.tap(find.byIcon(Icons.shuffle_rounded));
    expect(calls, 0);
    expect(
      Focus.of(
        tester.element(find.byIcon(Icons.shuffle_rounded)),
      ).canRequestFocus,
      isFalse,
    );
  });
}

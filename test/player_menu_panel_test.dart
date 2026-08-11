import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host({
    PlayerMenuSection initial = PlayerMenuSection.subtitles,
    bool hasPlaylist = false,
    bool showSpeed = true,
    bool allowEndOfItem = true,
    double speed = 1.0,
    ValueChanged<double>? onSpeed,
    ValueChanged<SleepTimerSelection>? onSleep,
    VoidCallback? onClose,
    GlobalKey<PlayerMenuPanelState>? key,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PlayerMenuPanel(
          key: key,
          initialSection: initial,
          onClose: onClose ?? () {},
          audioTracks: const [
            PlayerMenuTrackOption('1', 'English 5.1'),
            PlayerMenuTrackOption('2', 'Français'),
          ],
          selectedAudioId: '1',
          onAudioSelected: (_, __) async {},
          embeddedSubtitles: const [PlayerMenuTrackOption('3', 'English')],
          selectedSubtitleId: 'no',
          onSubtitlesOff: (_) async {},
          onEmbeddedSubtitleSelected: (_, __) async {},
          onAddonSubtitleSelected: (_, __) async => true,
          showSpeed: showSpeed,
          speed: speed,
          onSpeedSelected: onSpeed ?? (_) {},
          aspectMode: AspectMode.contain,
          onAspectSelected: (_) {},
          sleepMode: SleepTimerMode.off,
          allowEndOfItem: allowEndOfItem,
          onSleepSelected: onSleep ?? (_) {},
          hasPlaylist: hasPlaylist,
          continuousShuffle: false,
          onShuffleOnce: () {},
          onShuffleContinuousToggle: () {},
        ),
      ),
    );
  }

  testWidgets('rail shows sections, hiding shuffle without a playlist',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Subtitles'), findsOneWidget);
    expect(find.text('Subtitle style'), findsOneWidget);
    expect(find.text('Sleep timer'), findsOneWidget);
    expect(find.text('Shuffle'), findsNothing);

    await tester.pumpWidget(host(hasPlaylist: true));
    await tester.pumpAndSettle();
    expect(find.text('Shuffle'), findsOneWidget);
  });

  testWidgets('speed section hides for live and OK picks a speed',
      (tester) async {
    final picked = <double>[];
    await tester.pumpWidget(
      host(
        initial: PlayerMenuSection.speed,
        onSpeed: picked.add,
      ),
    );
    await tester.pumpAndSettle();

    // RIGHT enters the value pane on the first row (0.5×), DOWN to 0.75×,
    // OK selects it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, [0.75]);

    // Live: no Speed section at all.
    await tester.pumpWidget(host(showSpeed: false));
    await tester.pumpAndSettle();
    expect(find.text('Speed'), findsNothing);
  });

  testWidgets('BACK walks pane -> rail -> close, and host back mirrors it',
      (tester) async {
    var closed = false;
    final key = GlobalKey<PlayerMenuPanelState>();
    await tester.pumpWidget(
      host(
        initial: PlayerMenuSection.sleep,
        onClose: () => closed = true,
        key: key,
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    // In the pane: the host-back contract reports a pane change, not a close.
    expect(key.currentState!.handleHostBack(), isTrue);
    await tester.pumpAndSettle();
    // At the rail: host back says "close me".
    expect(key.currentState!.handleHostBack(), isFalse);

    // Key-driven BACK from the rail closes via onClose.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('sleep pane hides End of episode for live content',
      (tester) async {
    await tester.pumpWidget(
      host(initial: PlayerMenuSection.sleep, allowEndOfItem: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('End of episode'), findsNothing);
    expect(find.text('45 minutes'), findsOneWidget);

    final picked = <SleepTimerSelection>[];
    await tester.pumpWidget(
      host(initial: PlayerMenuSection.sleep, onSleep: picked.add),
    );
    await tester.pumpAndSettle();
    expect(find.text('End of episode'), findsOneWidget);

    // Tap a preset directly (touch path).
    await tester.tap(find.text('30 minutes'));
    await tester.pumpAndSettle();
    expect(picked.single.mode, SleepTimerMode.countdown);
    expect(picked.single.minutes, 30);
  });

  testWidgets('subtitles pane lists Off + embedded and marks the selection',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.text('Off'), findsWidgets);
    expect(find.text('EMBEDDED'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}

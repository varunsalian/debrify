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

  testWidgets('subtitles pane roundtrip keeps rail DPAD alive', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlayerMenuPanel(
          initialSection: PlayerMenuSection.subtitles,
          onClose: () {},
          audioTracks: const [PlayerMenuTrackOption('1', 'English 5.1')],
          selectedAudioId: '1',
          onAudioSelected: (_, __) async {},
          embeddedSubtitles: const [PlayerMenuTrackOption('3', 'English')],
          selectedSubtitleId: 'no',
          onSubtitlesOff: (_) async {},
          onEmbeddedSubtitleSelected: (_, __) async {},
          onAddonSubtitleSelected: (_, __) async => true,
          speed: 1.0,
          onSpeedSelected: (_) {},
          aspectMode: AspectMode.contain,
          onAspectSelected: (_) {},
          sleepMode: SleepTimerMode.off,
          onSleepSelected: (_) {},
          onShuffleOnce: () {},
          onShuffleContinuousToggle: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // RIGHT into the pane, LEFT back to the rail, then DOWN twice.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    // Rail should now be on "Subtitle style": entering it shows its header.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('SUBTITLE STYLE'), findsOneWidget,
        reason: 'DOWN after a pane roundtrip must move the rail');
  });
}

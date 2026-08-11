import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('publishes the latest position at no more than four hertz', (
    tester,
  ) async {
    final clock = PlaybackUiClockController();
    clock.beginMedia();
    var notifications = 0;
    clock.addListener(() => notifications++);

    clock.updatePosition(const Duration(seconds: 1));
    clock.updatePosition(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 249));
    expect(notifications, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(notifications, 1);
    expect(clock.value.position, const Duration(seconds: 2));

    for (var i = 3; i <= 12; i++) {
      clock.updatePosition(Duration(seconds: i));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(notifications, 1);

    await tester.pump(const Duration(milliseconds: 50));
    expect(notifications, 2);
    expect(clock.value.position, const Duration(seconds: 12));

    clock.dispose();
  });

  testWidgets('hidden controls retain raw time without notifying the UI', (
    tester,
  ) async {
    final clock = PlaybackUiClockController();
    clock.beginMedia();
    clock.setVisible(false);
    var notifications = 0;
    clock.addListener(() => notifications++);

    for (var i = 1; i <= 20; i++) {
      clock.updatePosition(Duration(seconds: i));
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(notifications, 0);
    expect(clock.rawPosition, const Duration(seconds: 20));
    expect(clock.value.position, Duration.zero);

    clock.setVisible(true);
    expect(notifications, 1);
    expect(clock.value.position, const Duration(seconds: 20));

    clock.dispose();
  });

  testWidgets('a stale media generation cannot overwrite the new clock', (
    tester,
  ) async {
    final clock = PlaybackUiClockController();
    final oldGeneration = clock.beginMedia();
    final currentGeneration = clock.beginMedia();
    var notifications = 0;
    clock.addListener(() => notifications++);

    clock.updatePosition(
      const Duration(minutes: 42),
      generation: oldGeneration,
      immediate: true,
    );
    expect(notifications, 0);
    expect(clock.value.position, Duration.zero);

    clock.updatePosition(
      const Duration(seconds: 7),
      generation: currentGeneration,
      immediate: true,
    );
    expect(notifications, 1);
    expect(clock.value.position, const Duration(seconds: 7));

    clock.dispose();
  });

  testWidgets('clock updates rebuild only the listening leaf', (tester) async {
    final clock = PlaybackUiClockController();
    clock.beginMedia();
    var rootBuilds = 0;
    var leafBuilds = 0;

    await tester.pumpWidget(
      _ClockHarness(
        clock: clock,
        onRootBuild: () => rootBuilds++,
        onLeafBuild: () => leafBuilds++,
      ),
    );
    expect(rootBuilds, 1);
    expect(leafBuilds, 1);

    clock.updatePosition(const Duration(seconds: 5), immediate: true);
    await tester.pump();

    expect(rootBuilds, 1);
    expect(leafBuilds, 2);
    expect(find.text('5'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    clock.dispose();
  });
}

class _ClockHarness extends StatelessWidget {
  const _ClockHarness({
    required this.clock,
    required this.onRootBuild,
    required this.onLeafBuild,
  });

  final PlaybackUiClockController clock;
  final VoidCallback onRootBuild;
  final VoidCallback onLeafBuild;

  @override
  Widget build(BuildContext context) {
    onRootBuild();
    return MaterialApp(
      home: ValueListenableBuilder<PlaybackUiClockValue>(
        valueListenable: clock,
        builder: (context, value, _) {
          onLeafBuild();
          return Text('${value.position.inSeconds}');
        },
      ),
    );
  }
}

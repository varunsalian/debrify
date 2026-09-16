import 'package:debrify/widgets/random_playback_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    required ValueChanged<RandomPlaybackMode?> onResult,
    Size size = const Size(1280, 720),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => onResult(
                await showRandomPlaybackDialog(
                  context,
                  title: 'Better Call Saul — a long series title that can wrap',
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('initial focus and Enter choose random once', (tester) async {
    RandomPlaybackMode? result;
    await open(tester, onResult: (value) => result = value);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result, RandomPlaybackMode.once);
    expect(find.byType(RandomPlaybackDialog), findsNothing);
  });

  for (final key in [LogicalKeyboardKey.select, LogicalKeyboardKey.enter]) {
    testWidgets('D-pad down and $key choose continuous shuffle', (
      tester,
    ) async {
      RandomPlaybackMode? result;
      await open(tester, onResult: (value) => result = value);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(result, RandomPlaybackMode.continuous);
    });
  }

  testWidgets('D-pad up returns to random once', (tester) async {
    RandomPlaybackMode? result;
    await open(tester, onResult: (value) => result = value);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(result, RandomPlaybackMode.once);
  });

  testWidgets('Back dismisses without launching', (tester) async {
    var completed = false;
    RandomPlaybackMode? result;
    await open(
      tester,
      onResult: (value) {
        completed = true;
        result = value;
      },
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
  });

  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(768, 1024),
    const Size(960, 540),
    const Size(1920, 1080),
  ]) {
    testWidgets('touch layout and selection at $size with large text', (
      tester,
    ) async {
      RandomPlaybackMode? result;
      await open(
        tester,
        size: size,
        textScale: 1.5,
        onResult: (value) => result = value,
      );
      expect(tester.takeException(), isNull);
      final choice = find.widgetWithText(OutlinedButton, 'Continuous shuffle');
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(result, RandomPlaybackMode.continuous);
      expect(tester.takeException(), isNull);
    });
  }
}

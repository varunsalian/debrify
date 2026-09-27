import 'package:debrify/features/home/presentation/home_unavailable_origin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class DialogHarness {
  bool current = true;
  bool removable = true;
  final visible = ValueNotifier(true);
  Future<bool>? result;
  late BuildContext origin;

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, shown, _) => shown
                ? Builder(
                    builder: (context) {
                      origin = context;
                      return TextButton(
                        onPressed: () {
                          result = confirmHomeUnavailableOriginRemoval(
                            context: context,
                            title: 'Missing series',
                            canRemove: () => removable,
                            isCurrent: () => current,
                          );
                        },
                        child: const Text('Open'),
                      );
                    },
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    addTearDown(visible.dispose);
  }

  Future<void> open(WidgetTester tester) async {
    await mount(tester);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}

const removeText = 'Remove from Continue Watching';

void main() {
  testWidgets('eligible title preserves copy and explicit removal choice', (
    tester,
  ) async {
    final h = DialogHarness();
    await h.open(tester);
    expect(find.text('Missing series'), findsOneWidget);
    expect(
      find.text(
        'The addon configuration for this series is unavailable. Your local history is still saved.',
      ),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    await tester.tap(find.text(removeText));
    await tester.pumpAndSettle();
    expect(await h.result, isTrue);
  });

  testWidgets('non-history item offers only Close', (tester) async {
    final h = DialogHarness()..removable = false;
    await h.open(tester);
    expect(find.text(removeText), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(await h.result, isFalse);
  });

  testWidgets('membership is read when the dialog builds', (tester) async {
    final h = DialogHarness()..removable = false;
    await h.mount(tester);
    await tester.tap(find.text('Open'));
    h.removable = true;
    await tester.pumpAndSettle();
    expect(find.text(removeText), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(await h.result, isFalse);
  });

  for (final dismiss in ['close', 'back', 'barrier']) {
    testWidgets('$dismiss never confirms deletion', (tester) async {
      final h = DialogHarness();
      await h.open(tester);
      if (dismiss == 'close') {
        await tester.tap(find.text('Close'));
      } else if (dismiss == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(const Offset(2, 2));
      }
      await tester.pumpAndSettle();
      expect(await h.result, isFalse);
    });
  }

  testWidgets('retired profile cannot open a confirmation', (tester) async {
    final h = DialogHarness()..current = false;
    await h.open(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(await h.result, isFalse);
  });

  testWidgets('profile retirement while open rejects an old Remove result', (
    tester,
  ) async {
    final h = DialogHarness();
    await h.open(tester);
    h.current = false;
    await tester.tap(find.text(removeText));
    await tester.pumpAndSettle();
    expect(await h.result, isFalse);
  });

  testWidgets(
    'originating view disposal rejects a dialog still on the navigator',
    (tester) async {
      final h = DialogHarness();
      await h.open(tester);
      h.visible.value = false;
      await tester.pumpAndSettle();
      expect(h.origin.mounted, isFalse);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(removeText));
      await tester.pumpAndSettle();
      expect(await h.result, isFalse);
      expect(
        await confirmHomeUnavailableOriginRemoval(
          context: h.origin,
          title: 'Retired',
          canRemove: () => throw StateError('must not build'),
          isCurrent: () => true,
        ),
        isFalse,
      );
    },
  );

  testWidgets('directional focus and Enter confirm the removal button', (
    tester,
  ) async {
    final h = DialogHarness();
    await h.open(tester);
    // Modal traversal starts at Close, then Right reaches Remove.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(await h.result, isTrue);
  });
}

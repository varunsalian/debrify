import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/widgets/tv_text_field.dart';

/// Reported on Discord: on a TV with an air mouse, clicking a letter on the
/// Debrify keyboard closed the keyboard instead of typing it. Android treats a
/// mouse press outside a text field as a reason to unfocus it, and the
/// keyboard lives in an overlay outside the field.
void main() {
  const fieldKey = GlobalObjectKey<TvTextFieldState>('field');

  Future<TextEditingController> openKeyboard(WidgetTester tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: TvTextField(
              key: fieldKey,
              controller: controller,
              forceTvKeyboard: true,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(fieldKey.currentState!.debugHasKeyboardOverlay, isTrue);
    return controller;
  }

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('a ${kind.name} click on a key types it and keeps the '
        'keyboard open', (tester) async {
      final controller = await openKeyboard(tester);

      await tester.tap(find.text('q'), kind: kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text('w'), kind: kind);
      await tester.pumpAndSettle();

      expect(controller.text, 'qw');
      expect(fieldKey.currentState!.debugHasKeyboardOverlay, isTrue);
    });
  }

  testWidgets('a mouse click away from the keyboard still closes it', (
    tester,
  ) async {
    await openKeyboard(tester);
    await tester.tapAt(const Offset(5, 300), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(fieldKey.currentState!.debugHasKeyboardOverlay, isFalse);
  });
}

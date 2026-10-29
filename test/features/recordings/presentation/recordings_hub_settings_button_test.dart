import 'package:debrify/features/recordings/presentation/recordings_hub_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bar({VoidCallback? onSettings}) => MaterialApp(
  home: Scaffold(
    body: RecordingsHubHubBar(
      onBack: () {},
      onSchedule: () {},
      onSettings: onSettings,
    ),
  ),
);

void main() {
  testWidgets('settings button is hidden without a route', (t) async {
    await t.pumpWidget(_bar());
    expect(find.byTooltip('Recording location & timing'), findsNothing);
  });

  testWidgets('settings button opens the route by tap and by Select', (
    t,
  ) async {
    var opened = 0;
    await t.pumpWidget(_bar(onSettings: () => opened++));
    final button = find.byTooltip('Recording location & timing');
    expect(button, findsOneWidget);

    await t.tap(button);
    await t.pump();
    expect(opened, 1);

    // D-pad: focus the button, then Select.
    Focus.of(t.element(find.byIcon(Icons.tune_rounded))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    await t.pump();
    expect(opened, 2);
  });
}

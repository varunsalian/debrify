import 'dart:ui' show PointerDeviceKind;

import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/ui/core/see_all_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final compact in [false, true]) {
    testWidgets('See All compact=$compact dispatches exactly one tap', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SeeAllLink(compact: compact, onTap: () => taps++),
            ),
          ),
        ),
      );
      final label = find.text(compact ? 'All' : 'See All');
      expect(label, findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await tester.tap(label);
      await tester.pump();
      expect(taps, 1);
    });
  }

  testWidgets('mouse hover brightens then restores the existing theme color', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SeeAllLink(onTap: () => taps++)),
        ),
      ),
    );
    final label = find.text('See All');
    final theme = AppThemeScope.of(tester.element(label));
    Color? color() => tester.widget<Text>(label).style?.color;
    expect(color(), theme.fade(theme.core.tx, 0.5));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(label));
    await tester.pump();
    expect(color(), theme.core.tx);
    expect(taps, 0);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(color(), theme.fade(theme.core.tx, 0.5));
    await mouse.removePointer();
  });
}

import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:debrify/widgets/stream_badge_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final theme in ['legacy', 'spotlight', 'spotlight-rich']) {
    testWidgets('badge state survives focus transitions on $theme Android TV', (
      tester,
    ) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
      final row = FocusNode();
      final outside = FocusNode();
      addTearDown(row.dispose);
      addTearDown(outside.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AppThemeScope(
            theme: AppThemes.byId(
              theme == 'spotlight-rich' ? 'spotlight' : theme,
            ),
            child: Scaffold(
              body: Column(
                children: [
                  Focus(focusNode: outside, child: const SizedBox(height: 20)),
                  _scope(
                    enabled: theme == 'spotlight-rich',
                    child: SourceRow(
                      title: 'Movie',
                      subtitle: '',
                      badgeName: 'Movie',
                      focusNode: row,
                      onTap: () {},
                      isTelevision: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      outside.requestFocus();
      await tester.pumpAndSettle();
      final resting = tester.element(find.byType(StreamBadgeStripFor));
      row.requestFocus();
      await tester.pumpAndSettle();
      final focused = tester.element(find.byType(StreamBadgeStripFor));
      outside.requestFocus();
      await tester.pumpAndSettle();
      final unfocused = tester.element(find.byType(StreamBadgeStripFor));
      final remounts =
          (identical(resting, focused) ? 0 : 1) +
          (identical(focused, unfocused) ? 0 : 1);
      expect(remounts, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final key in [
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
  ]) {
    testWidgets('held ${key.keyLabel} uses source navigation', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      var ups = 0;
      var downs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SourceRow(
              title: 'Source',
              subtitle: '',
              focusNode: node,
              onTap: () {},
              isTelevision: true,
              onNavigateUp: () => ups++,
              onNavigateDown: () => downs++,
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(key);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyRepeatEvent(key);
        await tester.pump();
      }
      await tester.sendKeyUpEvent(key);
      expect(ups, key == LogicalKeyboardKey.arrowUp ? 4 : 0);
      expect(downs, key == LogicalKeyboardKey.arrowDown ? 4 : 0);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

Widget _scope({required bool enabled, required Widget child}) =>
    enabled ? ParallaxRichScope(child: child) : child;

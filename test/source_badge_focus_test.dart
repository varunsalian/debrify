import 'package:debrify/models/stream_badge_rules.dart';
import 'package:debrify/services/stream_badge_matcher.dart';
import 'package:debrify/services/stream_badges_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:debrify/widgets/stream_badge_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final rules = <StreamBadgeRule>[
    for (final label in [
      '4K',
      'REMUX',
      'DOLBY VISION',
      'HDR10+',
      'TRUEHD',
      'ATMOS',
      'DTS-HD MA',
      'HEVC',
      '7.1',
      'ENGLISH',
    ])
      StreamBadgeRule(
        id: label,
        groupId: 'test',
        name: label,
        pattern: 'Movie',
      ),
  ];

  Future<StreamBadgeMatcher> warm(WidgetTester tester) async {
    final svc = StreamBadgesService.instance;
    svc.resetProfileScope();
    addTearDown(svc.resetProfileScope);
    final matcher = StreamBadgeMatcher([
      StreamBadgeRuleset(groups: const [], rules: rules),
    ]);
    svc.matcher.value = matcher;
    await tester.runAsync(() => matcher.matchesFor(name: 'Movie'));
    return matcher;
  }

  for (final width in [
    480.0,
    560.0,
    640.0,
    720.0,
    800.0,
    960.0,
    1120.0,
    1280.0,
  ]) {
    testWidgets('warm TV badges keep geometry and widgets on focus at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await warm(tester);
      final row = FocusNode();
      final sibling = FocusNode();
      addTearDown(row.dispose);
      addTearDown(sibling.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AppThemeScope(
            theme: AppThemes.legacy,
            child: Scaffold(
              body: Column(
                children: [
                  Focus(focusNode: sibling, child: const SizedBox(height: 10)),
                  SourceRow(
                    title: 'Source',
                    subtitle: 'metadata',
                    badgeName: 'Movie',
                    focusNode: row,
                    onTap: () {},
                    isTelevision: true,
                    showPlayPill: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // No second pump: cached matching must participate in the first layout.
      expect(find.byType(StreamBadgeChip), findsNWidgets(rules.length));
      sibling.requestFocus();
      await tester.pumpAndSettle();
      final geometry = tester.getSize(find.byType(SourceRow));
      final strip = tester.widget(find.byType(StreamBadgeStrip));
      for (var i = 0; i < 4; i++) {
        row.requestFocus();
        await tester.pumpAndSettle();
        expect(find.text('Play').hitTestable(), findsOneWidget);
        expect(tester.getSize(find.byType(SourceRow)), geometry);
        expect(
          identical(tester.widget(find.byType(StreamBadgeStrip)), strip),
          true,
        );
        sibling.requestFocus();
        await tester.pumpAndSettle();
        expect(find.text('Play').hitTestable(), findsNothing);
        expect(tester.getSize(find.byType(SourceRow)), geometry);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'shared badge strip retains artwork subtree on parent rebuild and remounts warm',
    (tester) async {
      await warm(tester);
      Widget build({double height = 24, String name = 'Movie'}) => MaterialApp(
        home: StreamBadgeStripFor(name: name, height: height),
      );
      await tester.pumpWidget(build());
      final strip = tester.widget<StreamBadgeStrip>(
        find.byType(StreamBadgeStrip),
      );
      await tester.pumpWidget(build());
      expect(
        identical(tester.widget(find.byType(StreamBadgeStrip)), strip),
        true,
      );
      await tester.pumpWidget(build(height: 26));
      expect(
        tester.widget<StreamBadgeStrip>(find.byType(StreamBadgeStrip)).height,
        26,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(build());
      expect(find.byType(StreamBadgeChip), findsNWidgets(rules.length));
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'synchronous matches are scoped, bounded, and unavailable after disposal',
    () async {
      final matcher = StreamBadgeMatcher([
        StreamBadgeRuleset(groups: const [], rules: rules),
      ]);
      addTearDown(matcher.dispose);
      expect(matcher.cachedMatchesFor(name: 'Movie'), isNull);
      final matched = await matcher.matchesFor(name: 'Movie');
      expect(identical(matcher.cachedMatchesFor(name: 'Movie'), matched), true);
      expect(
        matcher.cachedMatchesFor(name: 'Movie', description: 'other'),
        isNull,
      );
      await matcher.matchesFor(name: 'No match');
      expect(matcher.cachedMatchesFor(name: 'No match'), isEmpty);
      for (var i = 0; i < 401; i++) {
        await matcher.matchesFor(name: 'Movie $i');
      }
      expect(matcher.cachedMatchesFor(name: 'Movie'), isNull);
      matcher.dispose();
      expect(matcher.cachedMatchesFor(name: 'Movie 400'), isNull);
    },
  );
}

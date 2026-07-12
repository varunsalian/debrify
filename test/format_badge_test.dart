import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/utils/format_tag_detector.dart';
import 'package:debrify/widgets/format_badge.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );

  group('FormatBadge', () {
    testWidgets('renders every tag without throwing', (tester) async {
      for (final tag in FormatTag.values) {
        await pump(tester, FormatBadge(tag));
        expect(tester.takeException(), isNull, reason: 'threw for $tag');
      }
    });

    testWidgets('shows expected label text for key marks', (tester) async {
      await pump(tester, FormatBadge(FormatTag.uhd4k));
      expect(find.text('4K'), findsOneWidget);

      await pump(tester, FormatBadge(FormatTag.imax));
      expect(find.text('IMAX'), findsOneWidget);

      await pump(tester, FormatBadge(FormatTag.hevc));
      expect(find.text('HEVC'), findsOneWidget);

      await pump(tester, FormatBadge(FormatTag.dtsHdMa));
      expect(find.text('DTS-HD MA'), findsOneWidget);
    });

    testWidgets('every tag renders exactly one uniform chip (one Text)', (tester) async {
      for (final tag in FormatTag.values) {
        await pump(tester, FormatBadge(tag));
        expect(find.byType(Text), findsOneWidget, reason: 'ragged multi-text for $tag');
      }
    });

    testWidgets('scale multiplies rendered font size', (tester) async {
      await pump(tester, FormatBadge(FormatTag.imax));
      final base = tester.widget<Text>(find.text('IMAX')).style!.fontSize!;
      await pump(tester, FormatBadge(FormatTag.imax, scale: 2.0));
      final scaled = tester.widget<Text>(find.text('IMAX')).style!.fontSize!;
      expect(scaled, base * 2.0);
    });
  });

  group('FormatBadgeRow', () {
    testWidgets('empty tags render nothing visible', (tester) async {
      await pump(tester, const FormatBadgeRow([]));
      expect(find.byType(FormatBadge), findsNothing);
    });

    testWidgets('renders one FormatBadge per tag', (tester) async {
      final tags = FormatTagDetector.detect('Film.2160p.REMUX.HDR.IMAX.HEVC');
      await pump(tester, FormatBadgeRow(tags));
      expect(find.byType(FormatBadge), findsNWidgets(tags.length));
      expect(tags.length, greaterThan(2));
    });
  });
}

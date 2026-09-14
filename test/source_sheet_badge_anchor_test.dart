import 'dart:async';
import 'dart:convert';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/stream_badge_rules.dart';
import 'package:debrify/services/stream_badge_matcher.dart';
import 'package:debrify/services/stream_badges_service.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class Controlled extends StreamBadgeMatcher {
  Controlled() : super(const []);
  final pending = <String, Completer<List<StreamBadgeRule>>>{};
  @override
  Future<StreamBadgeMatchResult> matchResultFor({
    required String name,
    String? description,
  }) => (pending[name] ??= Completer<List<StreamBadgeRule>>()).future.then(
    (badges) => StreamBadgeMatchResult(StreamBadgeMatchStatus.resolved, badges),
  );
}

void main() {
  for (final mode in [
    'initial',
    'navigate',
    'navigate-overlap',
    'manual-scroll',
  ]) {
    testWidgets('delayed badges respect viewport ownership: $mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final svc = StreamBadgesService.instance;
      svc.resetProfileScope();
      addTearDown(svc.resetProfileScope);
      final m = Controlled();
      svc.matcher.value = m;
      final sources = [
        for (var i = 0; i < 20; i++)
          Torrent(
            rowid: i,
            infohash: '$i',
            name: 'Movie $i',
            sizeBytes: 0,
            createdUnix: 0,
            seeders: 0,
            leechers: 0,
            completed: 0,
            scrapedDate: 0,
            source: 'stremio:test',
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: SourceSheet(
            sources: sources,
            currentSourceIndex: 5,
            resolveSource: (_) async => 'https://example.test',
            onSourceSelected: (_, __) {},
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (mode.startsWith('navigate')) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        if (mode == 'navigate-overlap') {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
        } else {
          await tester.pumpAndSettle();
        }
      }
      final label = mode.startsWith('navigate') ? 'Movie 6' : 'Movie 5';
      if (mode == 'manual-scroll') {
        await tester.drag(find.byType(ListView).last, const Offset(0, -160));
        await tester.pumpAndSettle();
      }
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position;
      final beforeOffset = position.pixels;
      final before = tester.getRect(find.text(label));
      expect(before.top, greaterThan(0));
      expect(before.bottom, lessThan(800));
      final rules = StreamBadgeRuleset.parse(
        jsonEncode({
          'filters': [
            for (var i = 0; i < 15; i++)
              {'name': 'Long badge $i', 'pattern': 'Movie'},
          ],
        }),
      ).rules;
      for (final job in m.pending.values.toList()) {
        job.complete(rules);
      }
      await tester.pumpAndSettle();
      if (mode == 'manual-scroll') {
        expect(position.pixels, closeTo(beforeOffset, 1));
        return;
      }
      final after = find.text(label).evaluate().isEmpty
          ? null
          : tester.getRect(find.text(label));
      expect(after, isNotNull);
      expect(after!.bottom, lessThan(800));
      expect(after.top, greaterThan(0));
      if (mode == 'navigate-overlap') {
        final row = tester.renderObject(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(KeyedSubtree),
              )
              .first,
        );
        final viewport = RenderAbstractViewport.of(row);
        final desired = viewport
            .getOffsetToReveal(row, 0.45)
            .offset
            .clamp(position.minScrollExtent, position.maxScrollExtent);
        expect(position.pixels, closeTo(desired, 1));
      } else {
        expect(after.top, closeTo(before.top, 1));
      }
    });
  }
}

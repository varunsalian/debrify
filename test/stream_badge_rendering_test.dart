import 'dart:async';
import 'dart:convert';
import 'package:debrify/services/stream_badge_matcher.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/stream_badge_rules.dart';
import 'package:debrify/services/stream_badges_service.dart';
import 'package:debrify/widgets/stream_badge_strip.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('image badge slots remain stable and reveal together', (
    tester,
  ) async {
    final rules = StreamBadgeRuleset.parse(
      jsonEncode({
        'filters': [
          {
            'name': 'Short',
            'pattern': 'x',
            'imageUrl': 'https://example.test/one.png',
          },
          {
            'name': 'A longer badge',
            'pattern': 'x',
            'imageUrl': 'https://example.test/two.png',
          },
        ],
      }),
    ).rules;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StreamBadgeStrip(badges: rules, height: 24),
          ),
        ),
      ),
    );
    final chips = tester
        .widgetList<StreamBadgeChip>(find.byType(StreamBadgeChip))
        .toList();
    expect(chips.first.onImageReady, isNotNull);
    final before = tester.getSize(find.byType(StreamBadgeStrip));
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    chips.first.onImageReady!();
    await tester.pump();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    chips.last.onImageReady!();
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );
    expect(tester.getSize(find.byType(StreamBadgeStrip)), before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'slow badge artwork reveals bounded fallback slots after timeout',
    (tester) async {
      final rules = StreamBadgeRuleset.parse(
        jsonEncode({
          'filters': [
            {
              'name': 'Slow artwork',
              'pattern': 'x',
              'imageUrl': 'https://example.test/slow.png',
            },
          ],
        }),
      ).rules;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: StreamBadgeStrip(badges: rules, height: 24),
            ),
          ),
        ),
      );
      final before = tester.getSize(find.byType(StreamBadgeStrip));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
      expect(tester.getSize(find.byType(StreamBadgeStrip)), before);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final disposeBeforeRetry in [false, true]) {
    testWidgets(
      'deferred matching retries only while mounted: $disposeBeforeRetry',
      (tester) async {
        final svc = StreamBadgesService.instance;
        svc.resetProfileScope();
        addTearDown(svc.resetProfileScope);
        final matcher = _DeferredMatcher();
        svc.matcher.value = matcher;
        await tester.pumpWidget(
          const MaterialApp(home: StreamBadgeStripFor(name: 'x')),
        );
        await tester.pump();
        expect(matcher.calls, 1);
        expect(find.byType(StreamBadgeChip), findsNothing);
        if (disposeBeforeRetry) await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        expect(matcher.calls, disposeBeforeRetry ? 1 : 2);
        expect(
          find.byType(StreamBadgeChip),
          disposeBeforeRetry ? findsNothing : findsOneWidget,
        );
      },
    );
  }
  testWidgets('short text chips share a row and long labels stay bounded', (
    tester,
  ) async {
    final rules = StreamBadgeRuleset.parse(
      jsonEncode({
        'filters': [
          for (final label in ['4K', 'HDR', 'Long ' * 100])
            {'name': label, 'pattern': 'x'},
        ],
      }),
    ).rules;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: StreamBadgeStrip(badges: rules, height: 20),
            ),
          ),
        ),
      ),
    );
    final chips = find.byType(StreamBadgeChip);
    expect(tester.getSize(chips.at(0)).width, lessThan(100));
    expect(
      tester.getTopLeft(chips.at(0)).dy,
      tester.getTopLeft(chips.at(1)).dy,
    );
    expect(tester.getSize(chips.at(2)).width, lessThanOrEqualTo(200));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'late matches cannot restore badges from a previous source or matcher',
    (tester) async {
      final svc = StreamBadgesService.instance;
      svc.resetProfileScope();
      addTearDown(svc.resetProfileScope);
      final controlled = _ControlledMatcher();
      svc.matcher.value = controlled;
      final rule = StreamBadgeRuleset.parse(
        jsonEncode({
          'filters': [
            {'name': 'OLD', 'pattern': 'old'},
          ],
        }),
      ).rules;
      Widget source(String name) =>
          MaterialApp(home: StreamBadgeStripFor(name: name));
      await tester.pumpWidget(source('old'));
      await tester.pumpWidget(source('new'));
      controlled.requests['old']!.complete(rule);
      await tester.pump();
      expect(find.byType(StreamBadgeChip), findsNothing);
      svc.matcher.value = StreamBadgeMatcher.empty;
      await tester.pump();
      controlled.requests['new']!.complete(rule);
      await tester.pump();
      expect(find.byType(StreamBadgeChip), findsNothing);
      expect(tester.takeException(), isNull);
      controlled.dispose();
    },
  );
  for (final width in [400.0, 1000.0, 1920.0]) {
    testWidgets('player badges fit and remain legible at width $width', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final svc = StreamBadgesService.instance;
      svc.resetProfileScope();
      addTearDown(svc.resetProfileScope);
      await svc.importJson(
        jsonEncode({
          'filters': [
            for (final label in [
              'Torrentio',
              'Real-Debrid',
              '4K UHD',
              'BluRay REMUX',
              'Dolby Vision',
              'HDR10+',
              'TrueHD Atmos',
              '7.1 Surround',
              'English',
            ])
              {'name': label, 'pattern': 'Movie'},
          ],
        }),
        name: 'Preset',
      );
      // Warm the actual worker outside the widget test's fake clock.
      await tester.runAsync(() => svc.matcher.value.matchesFor(name: 'Movie'));
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: SourceSheet(
            sources: [
              Torrent(
                rowid: 0,
                infohash: 'a' * 40,
                name: 'Movie',
                sizeBytes: 0,
                createdUnix: 0,
                seeders: 0,
                leechers: 0,
                completed: 0,
                scrapedDate: 0,
                source: 'stremio:test',
              ),
            ],
            currentSourceIndex: 0,
            resolveSource: (_) async => 'https://example.invalid/video',
            onSourceSelected: (_, __) {},
            onClose: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(StreamBadgeChip), findsNWidgets(9));
      final chip = find.byType(StreamBadgeChip).first;
      final decorated = tester.widget<Container>(
        find.descendant(of: chip, matching: find.byType(Container)).first,
      );
      expect(
        (decorated.decoration as BoxDecoration).color,
        StreamBadgeChip.imageBacking,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _ControlledMatcher extends StreamBadgeMatcher {
  _ControlledMatcher() : super(const []);
  final requests = <String, Completer<List<StreamBadgeRule>>>{};
  @override
  Future<StreamBadgeMatchResult> matchResultFor({
    required String name,
    String? description,
  }) => (requests[name] ??= Completer<List<StreamBadgeRule>>()).future.then(
    (badges) => StreamBadgeMatchResult(StreamBadgeMatchStatus.resolved, badges),
  );
}

class _DeferredMatcher extends StreamBadgeMatcher {
  _DeferredMatcher() : super(const []);
  int calls = 0;
  @override
  Future<StreamBadgeMatchResult> matchResultFor({
    required String name,
    String? description,
  }) async {
    if (++calls == 1) {
      return const StreamBadgeMatchResult(StreamBadgeMatchStatus.deferred);
    }
    return StreamBadgeMatchResult(
      StreamBadgeMatchStatus.resolved,
      StreamBadgeRuleset.parse(
        '{"filters":[{"name":"Match","pattern":"x"}]}',
      ).rules,
    );
  }
}

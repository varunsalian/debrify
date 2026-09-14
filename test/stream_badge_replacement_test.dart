import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/services/stream_badges_service.dart';
import 'package:debrify/utils/format_tag_detector.dart';
import 'package:debrify/widgets/format_badge.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:debrify/widgets/stream_badge_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('badge hover labels preserve source taps and long presses', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final service = StreamBadgesService.instance;
    service.resetProfileScope();
    addTearDown(service.resetProfileScope);
    await service.importJson(
      '{"filters":[{"name":"Badge label","pattern":"Movie"}]}',
      name: 'Test',
    );
    await tester.runAsync(
      () => service.matcher.value.matchesFor(name: 'Movie'),
    );
    final node = FocusNode();
    addTearDown(node.dispose);
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SourceRow(
            title: 'Movie',
            subtitle: '',
            badgeName: 'Movie',
            focusNode: node,
            onTap: () => taps++,
            onLongPress: () => holds++,
          ),
        ),
      ),
    );
    await tester.pump();
    final badge = find.byType(StreamBadgeChip);
    expect(badge, findsOneWidget);
    await tester.longPress(badge);
    await tester.pump();
    expect(holds, 1);
    expect(taps, 0);
    expect(find.text('Badge label'), findsNothing);
    await tester.tap(badge);
    expect(taps, 1);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(badge));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Badge label'), findsOneWidget);
    expect(holds, 1);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  for (final layout in ['format', 'compact', 'player']) {
    for (final matches in [true, false]) {
      testWidgets(
        '$layout replaces built-in tags by configuration, match=$matches',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final service = StreamBadgesService.instance;
          service.resetProfileScope();
          addTearDown(service.resetProfileScope);
          const title = 'Movie.2160p.WEB-DL';
          final imported = await service.importJson(
            jsonEncode({
              'filters': [
                {
                  'name': 'CUSTOM',
                  'pattern': matches ? 'Movie' : 'DoesNotMatch',
                },
              ],
            }),
            name: 'Test',
          );
          await tester.runAsync(
            () => service.matcher.value.matchesFor(name: title),
          );
          final node = FocusNode();
          addTearDown(node.dispose);
          var taps = 0;
          final widget = layout == 'player'
              ? SourceSheet(
                  sources: [
                    Torrent(
                      rowid: 0,
                      infohash: 'a' * 40,
                      name: title,
                      sizeBytes: 2 * 1024 * 1024 * 1024,
                      createdUnix: 0,
                      seeders: 42,
                      leechers: 0,
                      completed: 0,
                      scrapedDate: 0,
                      source: 'stremio:test',
                    ),
                  ],
                  currentSourceIndex: 0,
                  resolveSource: (_) async => 'https://example.invalid/video',
                  onSourceSelected: (_, __) => taps++,
                  onClose: () {},
                )
              : Scaffold(
                  body: SourceRow(
                    title: title,
                    subtitle: '2 GB · 42 seeders',
                    focusNode: node,
                    onTap: () => taps++,
                    formatTags: layout == 'format'
                        ? FormatTagDetector.detect(title)
                        : const [],
                    qualityTag: '4K',
                    cacheLabel: 'TB',
                    coverageBadge: 'Season Pack',
                    badgeName: title,
                  ),
                );
          await tester.pumpWidget(MaterialApp(home: widget));
          await tester.pump();
          void expectBuiltIn(bool visible) {
            if (layout == 'format') {
              expect(
                find.byType(FormatBadge),
                visible ? findsWidgets : findsNothing,
              );
            } else {
              expect(find.text('4K'), visible ? findsOneWidget : findsNothing);
            }
          }

          expectBuiltIn(false);
          expect(
            find.byType(StreamBadgeChip),
            matches ? findsOneWidget : findsNothing,
          );
          if (layout == 'player') {
            expect(find.text('42 seeders'), findsOneWidget);
            expect(find.text('▮▮▮'), findsOneWidget);
            expect(
              tester.widget<Text>(find.text('▮▮▮')).semanticsLabel,
              'Playing',
            );
          } else {
            expect(find.text('TB'), findsOneWidget);
            expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
            expect(find.text('Season Pack'), findsOneWidget);
          }
          expect(taps, 0);
          await service.setEnabled(false);
          await tester.pump();
          expectBuiltIn(true);
          await service.setEnabled(true);
          await tester.pump();
          expectBuiltIn(false);
          await service.setSourceEnabled(imported.source.id, false);
          await tester.pump();
          expectBuiltIn(true);
          await service.setSourceEnabled(imported.source.id, true);
          await tester.pump();
          expectBuiltIn(false);
          await service.remove(imported.source.id);
          await tester.pump();
          expectBuiltIn(true);
          expect(taps, 0);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}

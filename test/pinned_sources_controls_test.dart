import 'dart:async';
import 'package:debrify/widgets/clear_pinned_sources_button.dart';
import 'package:debrify/widgets/detail/showcase_parts.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'one summary card shows all pins and D-pad reaches every action',
    (tester) async {
      final nodes = List.generate(3, (_) => FocusNode());
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
      });
      var opened = 0;
      var browsed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShowcaseSources(
              sources: List.generate(
                4,
                (i) => SeriesSource(
                  torrentHash: '$i',
                  torrentName: 'Source $i',
                  debridService: 'realdebrid',
                  debridTorrentId: '$i',
                  boundAt: 1,
                ),
              ),
              nodes: nodes,
              onOpen: () => opened++,
              onBrowseAll: () => browsed++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pinned sources (4)'), findsOneWidget);
      expect(find.text('Source 0'), findsNothing);
      nodes.first.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(opened, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(nodes[1].hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(opened, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(nodes[2].hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(browsed, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Clear all is reached by D-pad and Select runs once while busy', (
    tester,
  ) async {
    var clears = 0;
    final gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  autofocus: true,
                  onPressed: () {},
                  child: const Text('Add source'),
                ),
                ClearPinnedSourcesButton(
                  onClear: () async {
                    clears++;
                    await gate.future;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(clears, 1);
    expect(find.text('Clearing…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(clears, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Clear all'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

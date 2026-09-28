import 'package:debrify/features/home/presentation/home_tonight_focus.dart';
import 'package:debrify/features/home/presentation/home_stage_rows.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'queue identity survives inserts and detached rows fall back without losing zone',
    (tester) async {
      final nodes = List.generate(3, (_) => FocusNode());
      final item = StremioMeta(id: 'title', type: 'series', name: 'Title');
      HomeTonightQueueEntry entry(String id, FocusNode node) =>
          HomeTonightQueueEntry(
            rail: HomeRail(
              cw: HomeContinuationRow(
                rowId: id,
                title: id,
                tag: null,
                kind: HomeContinuationKind.local,
                items: [item],
                nodes: [node],
                progressOf: (_) => .5,
                episodeOf: (_) => 'S1 E2',
                remainingMinutesOf: (_) => 10,
                episodeArtworkOf: (_) => null,
                onOpen: (_) {},
                onQuickPlay: (_) {},
                onRemove: (_) async {},
              ),
            ),
            col: 0,
          );
      final a = entry('a', nodes[0]);
      final b = entry('b', nodes[1]);
      final c = entry('c', nodes[2]);
      final focus = HomeTonightFocus(
        railKeyOf: (rail) => rail.cw!.rowId,
        nearestNode: (nodes, column) =>
            nodes[column].context?.mounted == true ? nodes[column] : null,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              for (final node in [nodes[0], nodes[2]])
                Focus(focusNode: node, child: const SizedBox()),
            ],
          ),
        ),
      );
      focus.selectQueue(b, 1, item);
      expect(focus.resolveIndex([c, a, b]), 2);
      expect(focus.card.value!.holdAction, 'Options');
      expect(focus.card.value!.progress, .5);
      expect(focus.focusQueue([c, a, b]), isTrue);
      await tester.pump();
      expect(nodes[2].hasFocus, isTrue);
      expect(focus.resolveIndex([c, a, b]), 0);
      expect(focus.focusRail(null), isFalse);
      expect(focus.isQueue, isTrue);
      expect(focus.focusRail(nodes[0]), isTrue);
      await tester.pump();
      expect(nodes[0].hasFocus, isTrue);
      expect(focus.isQueue, isFalse);
      expect(focus.focusQueue([]), isFalse);
      expect(focus.isQueue, isFalse);
      focus.selectRail(const HomeRail(sectionIndex: 0), item);
      expect(focus.card.value!.holdAction, isNull);
      focus.resetPosition();
      expect(focus.isQueue, isTrue);
      expect(focus.resolveIndex([a, b]), 0);
      // Position reset intentionally leaves the caption's notification ordering
      // with the route; disposal owns the signal but never the borrowed nodes.
      expect(focus.card.value, isNotNull);
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      focus.dispose();
      expect(focus.focusQueue([a]), isFalse);
      expect(() => focus.selectQueue(a, 0, item), returnsNormally);
      for (final node in nodes) {
        node.dispose();
      }
    },
  );
}

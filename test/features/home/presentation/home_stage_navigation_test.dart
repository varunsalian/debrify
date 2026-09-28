import 'package:debrify/features/home/presentation/home_stage_navigation.dart';
import 'package:debrify/features/home/presentation/home_stage_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'rail switches preserve continuation priority and deferred paging order',
    () {
      const rails = [HomeRail(sectionIndex: 0), HomeRail(sectionIndex: 1)];
      final navigation = HomeStageNavigation(
        keyOf: (rail) => '${rail.sectionIndex}',
        nodesFor: (_) => [],
        itemsFor: (_) => [],
      );
      final events = <String>[];
      var pending = false;
      var advance = true;
      var continuation = false;
      void move(int delta, {List<HomeRail> rows = rails}) {
        events.clear();
        navigation.switchRail(
          rails: rows,
          delta: delta,
          rowsPending: () => pending,
          canAdvance: () => advance,
          focusContinuation: () {
            events.add('continuation');
            return continuation;
          },
          deferAdvance: (key) => events.add('defer:$key'),
          loadMore: () => events.add('load'),
          activate: (key) {
            navigation.activeKey = key;
            events.add('activate:$key');
          },
          scheduleFocus: () => events.add('focus:${navigation.activeKey}'),
        );
      }

      navigation.columns['0'] = 7;
      move(1);
      expect(events, ['activate:1', 'focus:1']);
      expect(navigation.columns, {'0': 7});
      move(1);
      expect(events, ['continuation', 'defer:1', 'load']);
      continuation = true;
      move(1);
      expect(events, ['continuation']);
      pending = true;
      move(1);
      expect(events, ['defer:1', 'load']);
      advance = false;
      move(1);
      expect(events, ['continuation']);
      pending = false;
      continuation = false;
      move(1);
      expect(events, ['continuation', 'continuation']);
      move(-1);
      expect(events, ['activate:0', 'focus:0']);
      expect(navigation.columns['0'], 7);
      move(-1);
      expect(events, isEmpty);
      move(0);
      expect(events, isEmpty);
      move(1, rows: []);
      expect(events, isEmpty);
    },
  );

  testWidgets(
    'rail identity and mounted-column restoration survive insertions and short Atrium',
    (tester) async {
      final nodes = List.generate(5, (_) => FocusNode());
      const a = HomeRail(sectionIndex: 0);
      const b = HomeRail(sectionIndex: 1);
      const c = HomeRail(sectionIndex: 2);
      final navigation = HomeStageNavigation(
        keyOf: (rail) => '${rail.sectionIndex}',
        nodesFor: (rail) => switch (rail.sectionIndex) {
          0 => nodes.sublist(0, 3),
          1 => [nodes[3]],
          _ => [nodes[4]],
        },
        itemsFor: (_) => [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              for (final node in [nodes[0], nodes[2], nodes[4]])
                Focus(focusNode: node, child: const SizedBox()),
            ],
          ),
        ),
      );
      expect(navigation.resolveView([a, b])!.rail, same(a));
      navigation.columns['0'] = 1;
      expect(navigation.railTarget([a, b]), same(nodes[0])); // Lower tie wins.
      expect(navigation.resolveIndex([c, a, b]), 1);
      navigation.columns['0'] = 2;
      expect(
        navigation.railTarget([c, a, b], focusedAtriumKey: '1'),
        same(nodes[2]),
      );
      // An out-of-window marker never overrides the active rail.
      expect(
        navigation.railTarget([a, b, c], focusedAtriumKey: '2'),
        same(nodes[2]),
      );
      expect(navigation.resolveView([c, b])!.rail, same(c));
      expect(navigation.activeKey, '2');
      expect(navigation.resolveView([]), isNull);
      expect(navigation.activeKey, '2');
      expect(navigation.railTarget([]), isNull);

      final scheduled = <FocusNode? Function()>[];
      void seed() => navigation.seedFocus(
        schedule: scheduled.add,
        resolveTarget: () => nodes[0],
      );
      seed();
      seed();
      expect(scheduled.length, 1);
      nodes[4].requestFocus();
      await tester.pump();
      expect(scheduled.single(), isNull); // No stealing an established focus.
      navigation.resetSeed();
      seed();
      expect(scheduled.length, 2);
      await tester.pumpWidget(const SizedBox());
      for (final node in nodes) {
        node.dispose();
      }
    },
  );
}

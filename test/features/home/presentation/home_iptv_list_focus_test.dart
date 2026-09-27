import 'package:debrify/features/home/models/home_iptv_list.dart';
import 'package:debrify/features/home/presentation/home_iptv_list_focus.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HomeIptvList row(String id, int count, {String? title}) => HomeIptvList(
  listId: id,
  title: title ?? id,
  channels: List.generate(count, (i) => IptvChannel(name: '$i', url: '$id:$i')),
);

void main() {
  testWidgets(
    'reorder/rename retain focused nodes; shrinking/removing disposes only retired nodes',
    (tester) async {
      final focus = HomeIptvListFocus();
      var rows = [row('a', 2), row('b', 1)];
      focus.reconcile(rows);
      final a = focus.nodesFor('a');
      final a0 = a.first;
      final a1 = a.last;
      final b0 = focus.nodesFor('b').single;
      expect(a.clear, throwsUnsupportedError);
      Future<void> render() => tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              for (final r in rows)
                for (final node in focus.nodesFor(r.listId))
                  Focus(
                    key: ObjectKey(node),
                    focusNode: node,
                    child: Text(node.debugLabel!),
                  ),
            ],
          ),
        ),
      );
      await render();
      a0.requestFocus();
      await tester.pump();
      expect(a0.hasFocus, isTrue);
      rows = [row('b', 2), row('a', 1, title: 'Renamed')];
      focus.reconcile(rows);
      await render();
      expect(focus.nodesFor('a').single, same(a0));
      expect(a, hasLength(1));
      expect(a0.hasFocus, isTrue);
      expect(focus.nodesFor('b').first, same(b0));
      expect(focus.nodesFor('b').last.debugLabel, 'search_iptvlist_b_1');
      expect(() => a1.addListener(() {}), throwsFlutterError);
      final borrowedB = focus.nodesFor('b');
      rows = [row('a', 1)];
      focus.reconcile(rows);
      await render();
      expect(borrowedB, isEmpty);
      expect(() => b0.addListener(() {}), throwsFlutterError);
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      expect(a, isEmpty);
      expect(() => a0.addListener(() {}), throwsFlutterError);
      expect(tester.takeException(), isNull);
    },
  );
}

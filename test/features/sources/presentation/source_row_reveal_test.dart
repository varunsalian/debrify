import 'package:debrify/features/sources/presentation/source_row_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cancellation after the frame prevents stale node access', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final events = <String>[];
    var retired = false;
    final work = revealSourceRow(
      index: 0,
      controller: controller,
      readNodes: () => throw StateError('stale node access'),
      canContinue: () => !retired,
      cancellationReason: () => retired ? 'new_search' : null,
      onRowMounted: (_) => fail('stale focus'),
      focusRequested: () => true,
      onEvent: (event, fields) => events.add('$event:${fields['reason']}'),
    );
    retired = true;
    await tester.pump();
    await work;
    expect(events, ['reveal_skipped:new_search']);
  });

  for (final index in [19, 0]) {
    testWidgets(
      'walks lazy viewport to row $index without replacing its focus node',
      (tester) async {
        final nodes = List.generate(30, (_) => FocusNode());
        final controller = ScrollController(
          initialScrollOffset: index == 0 ? 1200 : 0,
        );
        addTearDown(() {
          controller.dispose();
          for (final node in nodes) {
            node.dispose();
          }
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 200,
                child: ListView.builder(
                  controller: controller,
                  scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                  itemCount: nodes.length,
                  itemExtent: 60,
                  itemBuilder: (_, i) => Focus(
                    focusNode: nodes[i],
                    child: SizedBox(height: 60, child: Text('Row $i')),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(nodes[index].context, isNull);
        final events = <String>[];
        FocusNode? mountedNode;
        Object? requestedFocus;
        var complete = false;
        final work = revealSourceRow(
          index: index,
          controller: controller,
          readNodes: () => nodes,
          canContinue: () => true,
          cancellationReason: () => null,
          onRowMounted: (node) {
            mountedNode = node;
            node.requestFocus();
          },
          focusRequested: () => true,
          onEvent: (event, fields) {
            events.add(event);
            requestedFocus = fields['focus_requested'];
          },
        ).then((_) => complete = true);
        for (var frame = 0; frame < 30 && !complete; frame++) {
          await tester.pump();
        }
        expect(complete, isTrue);
        await work;
        await tester.pump();
        expect(events, ['reveal_complete']);
        expect(mountedNode, same(nodes[index]));
        expect(requestedFocus, isTrue);
        expect(nodes[index].hasFocus, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'unattached scroll controller ends reveal without requesting focus',
    (tester) async {
      final node = FocusNode();
      final controller = ScrollController();
      addTearDown(node.dispose);
      addTearDown(controller.dispose);
      String? reason;
      final work = revealSourceRow(
        index: 0,
        controller: controller,
        readNodes: () => [node],
        canContinue: () => true,
        cancellationReason: () => null,
        onRowMounted: (_) => fail('unmounted row'),
        focusRequested: () => false,
        onEvent: (_, fields) => reason = fields['reason'] as String?,
      );
      await tester.pump();
      await work;
      expect(reason, 'scroll_not_attached');
      expect(node.hasFocus, isFalse);
    },
  );
}

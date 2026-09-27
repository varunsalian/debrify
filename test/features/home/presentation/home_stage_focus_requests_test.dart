import 'package:debrify/features/home/presentation/home_stage_focus_requests.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('target resolves after the frame using its latest value', (
    tester,
  ) async {
    final h = _FocusHost();
    addTearDown(h.dispose);
    await h.mount(tester);
    var target = h.nodes[1];
    var resolved = 0;
    h.requests.schedule(() {
      resolved++;
      return target;
    });
    expect(resolved, 0);
    expect(h.nodes[0].hasFocus, isTrue);
    target = h.nodes[2];
    await _frame(tester);
    expect(resolved, 1);
    expect(h.nodes[2].hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a changed layout rejects the old target and accepts a new request',
    (tester) async {
      final h = _FocusHost();
      addTearDown(h.dispose);
      await h.mount(tester);
      var resolved = 0;
      h.requests.schedule(() {
        resolved++;
        return h.nodes[1];
      });
      h.style = 'mosaic';
      await _frame(tester);
      expect(resolved, 0);
      expect(h.nodes[0].hasFocus, isTrue);
      h.requests.schedule(() {
        resolved++;
        return h.nodes[2];
      });
      await _frame(tester);
      expect(resolved, 1);
      expect(h.nodes[2].hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reseed or returning to the same layout cannot revive an invalidated request',
    (tester) async {
      final h = _FocusHost();
      addTearDown(h.dispose);
      await h.mount(tester);
      var resolved = 0;
      h.requests.schedule(() {
        resolved++;
        return h.nodes[1];
      });
      h.style = 'tonight';
      h.requests.invalidate();
      h.style = 'canvas';
      await _frame(tester);
      expect(resolved, 0);
      expect(h.nodes[0].hasFocus, isTrue);
      h.requests.schedule(() {
        resolved++;
        return h.nodes[2];
      });
      h.requests.invalidate();
      await _frame(tester);
      expect(resolved, 0);
      h.requests.schedule(() {
        resolved++;
        return h.nodes[2];
      });
      await _frame(tester);
      expect(resolved, 1);
      expect(h.nodes[2].hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('retired view is rejected before style or target access', (
    tester,
  ) async {
    final h = _FocusHost();
    addTearDown(h.dispose);
    await h.mount(tester);
    h.requests.schedule(() => throw StateError('Retired target accessed'));
    final reads = h.styleReads;
    h.mounted = false;
    await tester.pumpWidget(const SizedBox());
    expect(h.styleReads, reads);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'null targets leave focus alone and valid requests keep their frame order',
    (tester) async {
      final h = _FocusHost();
      addTearDown(h.dispose);
      await h.mount(tester);
      h.requests.schedule(() => null);
      await _frame(tester);
      expect(h.nodes[0].hasFocus, isTrue);
      final order = <int>[];
      h.requests.schedule(() {
        order.add(1);
        return h.nodes[1];
      });
      h.requests.schedule(() {
        order.add(2);
        return h.nodes[2];
      });
      await _frame(tester);
      expect(order, [1, 2]);
      expect(h.nodes[2].hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('one view invalidation cannot retire another owner', (
    tester,
  ) async {
    final h = _FocusHost();
    addTearDown(h.dispose);
    await h.mount(tester);
    final other = HomeStageFocusRequests(
      isMounted: () => h.mounted,
      readStyle: () => h.style,
    );
    h.requests.schedule(() => throw StateError('Old target accessed'));
    other.schedule(() => h.nodes[2]);
    h.requests.invalidate();
    await _frame(tester);
    expect(h.nodes[2].hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _FocusHost {
  final nodes = List.generate(3, (_) => FocusNode());
  bool mounted = true;
  String style = 'canvas';
  int styleReads = 0;
  late final requests = HomeStageFocusRequests(
    isMounted: () => mounted,
    readStyle: () {
      if (!mounted) throw StateError('Retired style accessed');
      styleReads++;
      return style;
    },
  );

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            for (var i = 0; i < nodes.length; i++)
              Focus(focusNode: nodes[i], child: Text('Target $i')),
          ],
        ),
      ),
    );
    nodes[0].requestFocus();
    await _frame(tester);
  }

  void dispose() {
    for (final node in nodes) {
      node.dispose();
    }
  }
}

// addPostFrameCallback does not schedule a frame. Production callers rebuild
// the board; this host must explicitly provide that frame too.
Future<void> _frame(WidgetTester tester) async {
  tester.binding.scheduleFrame();
  await tester.pump();
}

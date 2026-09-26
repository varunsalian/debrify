import 'package:debrify/features/sources/presentation/source_row_focus_nodes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RowsHost extends StatefulWidget {
  const RowsHost({super.key, required this.owner});
  final SourceRowFocusNodes owner;
  @override
  State<RowsHost> createState() => RowsHostState();
}

class RowsHostState extends State<RowsHost> {
  final toolbar = FocusNode(debugLabel: 'toolbar');
  @override
  void initState() {
    super.initState();
    widget.owner.resize(4);
  }

  void resize(int count) => setState(() => widget.owner.resize(count));
  void replace(int count) => setState(() => widget.owner.replaceAll(count));
  void reset() => setState(widget.owner.resetForSearch);

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Focus(focusNode: toolbar, child: const Text('Toolbar')),
      for (var i = 0; i < widget.owner.nodes.length; i++)
        Focus(
          key: ValueKey(i),
          focusNode: widget.owner.nodes[i],
          child: Text('Row $i'),
        ),
    ],
  );

  @override
  void dispose() {
    toolbar.dispose();
    widget.owner.dispose();
    super.dispose();
  }
}

void expectAlive(FocusNode node) {
  void listener() {}
  node.addListener(listener);
  node.removeListener(listener);
}

void expectDisposed(FocusNode node) {
  expect(() => node.addListener(() {}), throwsFlutterError);
}

void main() {
  late SourceRowFocusNodes owner;
  late GlobalKey<RowsHostState> host;

  Future<void> pumpHost(WidgetTester tester) async {
    owner = SourceRowFocusNodes();
    host = GlobalKey<RowsHostState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RowsHost(key: host, owner: owner),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'growing retains node identity and does not steal toolbar focus',
    (tester) async {
      await pumpHost(tester);
      final live = owner.nodes;
      final original = List<FocusNode>.of(live);
      host.currentState!.toolbar.requestFocus();
      await tester.pump();
      host.currentState!.resize(6);
      await tester.pump();
      expect(identical(owner.nodes, live), isTrue);
      expect(live.take(4), original);
      expect(live.map((node) => node.debugLabel), [
        'src_0',
        'src_1',
        'src_2',
        'src_3',
        'src_4',
        'src_5',
      ]);
      expect(() => live.clear(), throwsUnsupportedError);
      expect(host.currentState!.toolbar.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      for (final node in original) {
        expectDisposed(node);
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final count in [3, 1, 0]) {
    testWidgets(
      'shrinking focused rows to $count retires nodes after rebuild',
      (tester) async {
        await pumpHost(tester);
        final original = List<FocusNode>.of(owner.nodes);
        original.last.requestFocus();
        await tester.pump();
        expect(original.last.hasFocus, isTrue);
        host.currentState!.resize(count);
        for (final node in original) {
          expectAlive(node);
        }
        await tester.pump();
        await tester.pump();
        expect(owner.nodes, original.take(count).toList());
        for (final node in original.skip(count)) {
          expectDisposed(node);
        }
        if (count > 0) expect(owner.nodes.last.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'toolbar replacement retires reused row nodes without moving focus',
    (tester) async {
      await pumpHost(tester);
      final original = List<FocusNode>.of(owner.nodes);
      host.currentState!.toolbar.requestFocus();
      await tester.pump();
      host.currentState!.replace(2);
      expect(owner.nodes, hasLength(2));
      expect(original.contains(owner.nodes.first), isFalse);
      for (final node in original) {
        expectAlive(node);
      }
      await tester.pump();
      for (final node in original) {
        expectDisposed(node);
      }
      expect(host.currentState!.toolbar.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'new search immediately retires old nodes and starts fresh labels',
    (tester) async {
      await pumpHost(tester);
      final original = List<FocusNode>.of(owner.nodes);
      host.currentState!.reset();
      expect(owner.nodes, isEmpty);
      for (final node in original) {
        expectDisposed(node);
      }
      await tester.pump();
      host.currentState!.resize(1);
      await tester.pump();
      expect(owner.nodes.single.debugLabel, 'src_0');
      expect(original.contains(owner.nodes.single), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('view disposal also lets pending retired nodes finish cleanup', (
    tester,
  ) async {
    await pumpHost(tester);
    final retired = List<FocusNode>.of(owner.nodes);
    host.currentState!.replace(2);
    final current = List<FocusNode>.of(owner.nodes);
    await tester.pumpWidget(const SizedBox());
    for (final node in [...retired, ...current]) {
      expectDisposed(node);
    }
    owner.resize(4);
    owner.replaceAll(3);
    owner.resetForSearch();
    owner.dispose();
    expect(owner.nodes, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

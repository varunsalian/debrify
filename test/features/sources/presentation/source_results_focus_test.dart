import 'package:debrify/features/sources/presentation/source_results_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FocusFixture {
  final rows = List.generate(3, (_) => FocusNode());
  final filter = FocusNode();
  final pill = FocusNode();
  final rail = FocusNode();
  final scroll = ScrollController();
  final events = <String>[];
  bool mounted = true;
  bool frozen = false;
  bool pending = false;
  bool selectedVisible = false;
  bool recoverEmpty = false;
  bool empty = false;
  bool television = true;
  int token = 0;
  late final SourceResultsFocus focus = SourceResultsFocus(
    controller: scroll,
    readNodes: () {
      if (!mounted) throw StateError('Retired node access');
      return empty ? [] : rows;
    },
    filterFocus: filter,
    pillFocus: pill,
    isMounted: () => mounted,
    searchToken: () => token,
    isFrozen: () => frozen,
    hasPendingResults: () => pending,
    hasSelectedVisible: () => selectedVisible,
    hasRailFocus: () => rail.hasFocus,
    canRecoverEmpty: () => recoverEmpty,
    isTelevision: () => television,
    freeze: () {
      frozen = true;
      focus.cancelReveal();
    },
    onEvent: (event, fields) => events.add('$event:${fields['reason']}'),
  );

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final node in [...rows, filter, pill, rail])
                Focus(focusNode: node, child: const Text('Target')),
            ],
          ),
        ),
      ),
    );
    addTearDown(() async {
      mounted = false;
      await tester.pumpWidget(const SizedBox());
      for (final node in [...rows, filter, pill, rail]) {
        node.dispose();
      }
      scroll.dispose();
    });
  }
}

void main() {
  for (final mode in [
    (redesign: false, television: true),
    (redesign: true, television: false),
    (redesign: true, television: true),
  ]) {
    testWidgets('row navigation preserves first-row behavior for $mode', (
      tester,
    ) async {
      final fixture = FocusFixture()..television = mode.television;
      await fixture.mount(tester);
      fixture.rows[1].requestFocus();
      await tester.pump();
      fixture.focus.rowUp(1, redesign: mode.redesign);
      expect(fixture.frozen, isTrue);
      await tester.pump();
      expect(fixture.rows.first.hasFocus, isTrue);
      fixture.focus.rowUp(0, redesign: mode.redesign);
      await tester.pump();
      expect(fixture.filter.hasFocus, mode.redesign && mode.television);
      expect(fixture.rows.first.hasFocus, !(mode.redesign && mode.television));
      fixture.focus.rowDown(0);
      await tester.pump();
      expect(fixture.rows[1].hasFocus, isTrue);
      fixture.focus.rowDown(1);
      await tester.pump();
      fixture.focus.rowDown(2);
      await tester.pump();
      expect(fixture.rows.last.hasFocus, isTrue);
    });
  }

  testWidgets(
    'pending results take precedence and navigation reads live state',
    (tester) async {
      final fixture = FocusFixture();
      await fixture.mount(tester);
      fixture.rows.first.requestFocus();
      await tester.pump();
      fixture.pending = true;
      fixture.focus.rowUp(0, redesign: false);
      await tester.pump();
      expect(fixture.pill.hasFocus, isTrue);
      expect(fixture.focus.pillUp(), isTrue);
      await tester.pump();
      expect(fixture.filter.hasFocus, isTrue);
      fixture.focus.filterDown();
      await tester.pump();
      expect(fixture.pill.hasFocus, isTrue);
      fixture.focus.pillDown();
      await tester.pump();
      expect(fixture.rows.first.hasFocus, isTrue);
      fixture.pending = false;
      fixture.filter.requestFocus();
      await tester.pump();
      fixture.focus.filterDown();
      await tester.pump();
      expect(fixture.rows.first.hasFocus, isTrue);
      fixture.empty = true;
      fixture.filter.requestFocus();
      await tester.pump();
      fixture.focus.filterDown();
      await tester.pump();
      expect(fixture.filter.hasFocus, isTrue);
    },
  );

  testWidgets('reveal reads TV mode when the row mounts', (tester) async {
    final fixture = FocusFixture();
    await fixture.mount(tester);
    final work = fixture.focus.reveal(2);
    fixture.television = false;
    tester.binding.scheduleFrame();
    await tester.pump();
    await work;
    expect(fixture.events.last, 'reveal_complete:null');
    expect(fixture.rows[2].hasFocus, isFalse);
  });

  for (final reason in [
    'unmounted',
    'new_search',
    'newer_result_batch',
    'user_interaction',
  ]) {
    testWidgets('reveal cancels after its frame for $reason', (tester) async {
      final fixture = FocusFixture();
      await fixture.mount(tester);
      final work = fixture.focus.reveal(2);
      switch (reason) {
        case 'unmounted':
          fixture.mounted = false;
        case 'new_search':
          fixture.token++;
        case 'newer_result_batch':
          fixture.focus.cancelReveal();
        case 'user_interaction':
          fixture.frozen = true;
      }
      tester.binding.scheduleFrame();
      await tester.pump();
      await work;
      expect(fixture.events, ['reveal_start:null', 'reveal_skipped:$reason']);
      expect(fixture.rows.any((node) => node.hasFocus), isFalse);
    });
  }

  for (final target in ['filter', 'pill', 'rail']) {
    testWidgets('reveal respects $target focus acquired during its frame', (
      tester,
    ) async {
      final fixture = FocusFixture();
      await fixture.mount(tester);
      final work = fixture.focus.reveal(2);
      final node = switch (target) {
        'filter' => fixture.filter,
        'pill' => fixture.pill,
        _ => fixture.rail,
      };
      node.requestFocus();
      tester.binding.scheduleFrame();
      await tester.pump();
      await work;
      expect(node.hasFocus, isTrue);
      expect(fixture.events.last, startsWith('reveal_skipped:'));
      expect(fixture.rows[2].hasFocus, isFalse);
    });
  }

  testWidgets('preserving rail focus reveals and remembers the selected row', (
    tester,
  ) async {
    final fixture = FocusFixture();
    await fixture.mount(tester);
    fixture.rail.requestFocus();
    tester.binding.scheduleFrame();
    await tester.pump();
    fixture.frozen = true;
    final work = fixture.focus.reveal(2, preserveFocus: true);
    tester.binding.scheduleFrame();
    await tester.pump();
    await work;
    expect(fixture.rail.hasFocus, isTrue);
    expect(fixture.events.last, 'reveal_complete:null');
    fixture.focus.focusRememberedRow();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(fixture.rows[2].hasFocus, isTrue);
    expect(fixture.focus.rememberFocusedRow(), isTrue);
    fixture.focus.resetRememberedRow();
    fixture.focus.focusRememberedRow();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(fixture.rows.first.hasFocus, isTrue);
  });

  testWidgets('streaming anchor checks live selection and user focus', (
    tester,
  ) async {
    final fixture = FocusFixture();
    await fixture.mount(tester);
    fixture.focus.anchorStreamingAfterFrame();
    fixture.selectedVisible = true;
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(fixture.rows.first.hasFocus, isFalse);
    fixture.selectedVisible = false;
    fixture.focus.anchorStreamingAfterFrame();
    fixture.rail.requestFocus();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(fixture.rail.hasFocus, isTrue);
    fixture.focus.restoreAfterFrame(1);
    fixture.mounted = false;
    fixture.focus.anchorCompletionAfterFrame();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(fixture.rail.hasFocus, isTrue);
  });

  testWidgets(
    'empty completion recovers filter only when recovery is available',
    (tester) async {
      final fixture = FocusFixture();
      await fixture.mount(tester);
      fixture.empty = true;
      fixture.focus.anchorCompletionAfterFrame();
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(fixture.filter.hasFocus, isFalse);
      fixture.focus.anchorCompletionAfterFrame();
      fixture.recoverEmpty = true;
      tester.binding.scheduleFrame();
      await tester.pump();
      tester.binding.scheduleFrame();
      await tester.pump();
      expect(fixture.filter.hasFocus, isTrue);
    },
  );
}

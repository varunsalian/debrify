import 'package:debrify/features/search/presentation/keyword_focus_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shrinking focused rows and tabs reanchors before deferred cleanup',
    (tester) async {
      final focus = KeywordFocusController(
        focusSearch: () {},
        focusSidebar: () {},
        focusAboveToolbar: () {},
        hasAccessibleArrivals: () => false,
      );
      focus.syncRows(3);
      focus.syncTabs(2);
      Future<void> mount() => tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              for (final node in [...focus.rows, ...focus.tabs])
                Focus(
                  key: ValueKey(node),
                  focusNode: node,
                  child: Text(node.debugLabel!),
                ),
            ],
          ),
        ),
      );
      await mount();
      final removedRow = focus.rows.last;
      removedRow.requestFocus();
      await tester.pump();
      focus.syncRows(2);
      await mount();
      expect(focus.rows.last.hasFocus, isTrue);
      expect(() => removedRow.addListener(() {}), throwsFlutterError);
      final removedTab = focus.tabs.last;
      removedTab.requestFocus();
      await tester.pump();
      focus.syncTabs(1);
      await mount();
      expect(focus.tabs.last.hasFocus, isTrue);
      expect(() => removedTab.addListener(() {}), throwsFlutterError);
      // A queued reveal must be harmless after its owning view retires.
      focus.focusTab(1);
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      focus.dispose();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'toolbar and tab navigation preserve boundaries and empty arrivals',
    (tester) async {
      final calls = <String>[];
      var pending = true;
      final focus = KeywordFocusController(
        focusSearch: () => calls.add('search'),
        focusSidebar: () => calls.add('sidebar'),
        focusAboveToolbar: () => calls.add('above'),
        hasAccessibleArrivals: () => pending,
      );
      focus.syncTabs(1);
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              for (final node in [
                ...focus.toolbar,
                ...focus.tabs,
                focus.arrivals,
              ])
                Focus(focusNode: node, child: Text(node.debugLabel!)),
            ],
          ),
        ),
      );
      KeyDownEvent key(LogicalKeyboardKey key) => KeyDownEvent(
        logicalKey: key,
        physicalKey: PhysicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );
      void activate() => calls.add('activate');
      focus.handleTabKey(0, 2, activate, key(LogicalKeyboardKey.arrowLeft));
      focus.handleTabKey(0, 2, activate, key(LogicalKeyboardKey.arrowUp));
      focus.handleTabKey(0, 2, activate, key(LogicalKeyboardKey.enter));
      focus.handleToolbarKey(0, 3, activate, key(LogicalKeyboardKey.arrowUp));
      expect(calls, ['sidebar', 'search', 'activate', 'above']);
      focus.toolbar.first.requestFocus();
      await tester.pump();
      focus.handleToolbarKey(0, 3, activate, key(LogicalKeyboardKey.arrowDown));
      await tester.pump();
      expect(focus.arrivals.hasFocus, isTrue);
      pending = false;
      focus.toolbar.first.requestFocus();
      await tester.pump();
      focus.handleToolbarKey(0, 3, activate, key(LogicalKeyboardKey.arrowDown));
      await tester.pump();
      expect(focus.toolbar.first.hasFocus, isTrue);
      focus.handleToolbarKey(
        0,
        3,
        activate,
        key(LogicalKeyboardKey.arrowRight),
      );
      await tester.pump();
      expect(focus.toolbar[1].hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      expect(
        focus.handleTabKey(0, 2, activate, key(LogicalKeyboardKey.enter)),
        KeyEventResult.ignored,
      );
      expect(calls.where((c) => c == 'activate'), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}

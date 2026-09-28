import 'package:debrify/features/search/models/search_mode.dart';
import 'package:debrify/features/search/presentation/search_focus_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'entry follows visible results and keeps loading TV Home in place',
    (tester) async {
      final focus = SearchFocusController(onSourcesVisibilityChanged: () {});
      final result = FocusNode();
      final discovery = FocusNode();
      final sidebar = FocusNode();
      final nodes = [
        focus.field,
        focus.catalog,
        focus.keyword,
        focus.lists,
        focus.dropdown,
        result,
        discovery,
        sidebar,
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              for (final node in nodes)
                Focus(focusNode: node, child: const SizedBox()),
            ],
          ),
        ),
      );
      var boardReads = 0;
      var shelfEntries = 0;
      void enter({
        SearchMode mode = SearchMode.catalog,
        bool search = true,
        bool discover = false,
        bool tv = true,
        bool loading = false,
        FocusNode? target,
        bool shelf = false,
      }) {
        focus.focusContent(
          discoverMode: discover,
          searchMode: search,
          isTelevision: tv,
          mode: mode,
          discoverSource: discovery,
          keywordToolbar: target,
          listsResult: target,
          catalogResult: target,
          focusCatalogShelf: shelf
              ? () {
                  shelfEntries++;
                }
              : null,
          topBoardNode: () {
            boardReads++;
            return target;
          },
          loading: loading,
          focusSidebar: sidebar.requestFocus,
        );
      }

      for (final mode in SearchMode.values) {
        enter(mode: mode);
        await tester.pump();
        expect(focus.field.hasFocus, isTrue);
        enter(mode: mode, target: result);
        await tester.pump();
        expect(result.hasFocus, isTrue);
      }
      enter(target: result, shelf: true);
      expect(shelfEntries, 1);
      enter(shelf: true);
      await tester.pump();
      expect(shelfEntries, 1);
      expect(focus.field.hasFocus, isTrue);
      enter(discover: true, mode: SearchMode.keyword, target: result);
      await tester.pump();
      expect(discovery.hasFocus, isTrue);
      expect(boardReads, 0);
      enter(search: false, loading: true);
      await tester.pump();
      expect(discovery.hasFocus, isTrue);
      enter(search: false);
      await tester.pump();
      expect(sidebar.hasFocus, isTrue);
      enter(search: false, tv: false);
      await tester.pump();
      expect(focus.field.hasFocus, isTrue);
      enter(search: false, target: result);
      await tester.pump();
      expect(result.hasFocus, isTrue);
      focus.focusMode(SearchMode.lists, compact: false);
      await tester.pump();
      expect(focus.lists.hasFocus, isTrue);
      focus.focusMode(SearchMode.keyword, compact: true);
      await tester.pump();
      expect(focus.dropdown.hasFocus, isTrue);
      final text = TextEditingController(text: 'query');
      focus.focusFieldAtEnd(text);
      await tester.pump();
      expect(text.selection.baseOffset, 5);
      expect(focus.field.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      text.dispose();
      focus.dispose();
      result.dispose();
      discovery.dispose();
      sidebar.dispose();
    },
  );

  testWidgets(
    'Sources survives blur for taps, refocus cancels hide, disposal cancels timer',
    (tester) async {
      var changes = 0;
      final focus = SearchFocusController(
        onSourcesVisibilityChanged: () {
          changes++;
        },
      );
      final other = FocusNode();
      focus.field.addListener(focus.onFieldFocusForSources);
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              Focus(focusNode: focus.field, child: const SizedBox()),
              Focus(focusNode: other, child: const SizedBox()),
            ],
          ),
        ),
      );
      focus.field.requestFocus();
      await tester.pump();
      expect(focus.sourcesVisible, isTrue);
      other.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 249));
      expect(focus.sourcesVisible, isTrue);
      focus.field.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(focus.sourcesVisible, isTrue);
      expect(changes, 1);
      other.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(focus.sourcesVisible, isFalse);
      focus.field.requestFocus();
      await tester.pump();
      other.requestFocus();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      focus.dispose();
      other.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(changes, 3);
      expect(tester.takeException(), isNull);
    },
  );

  test('compact selector preserves TV and touch thresholds', () {
    for (final tv in [true, false]) {
      final threshold = tv ? 900.0 : 342.0;
      expect(
        SearchFocusController.useCompactModeMenu(
          listsEnabled: true,
          isTelevision: tv,
          width: threshold - 1,
        ),
        isTrue,
      );
      expect(
        SearchFocusController.useCompactModeMenu(
          listsEnabled: true,
          isTelevision: tv,
          width: threshold,
        ),
        isFalse,
      );
      expect(
        SearchFocusController.useCompactModeMenu(
          listsEnabled: false,
          isTelevision: tv,
          width: 100,
        ),
        isFalse,
      );
    }
  });
}

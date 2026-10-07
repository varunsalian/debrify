import 'dart:async';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/premiumize_files_fixture.dart';

void main() {
  testWidgets(
    'root preserves server order on initial load and parent reentry',
    (t) => premiumizeCase(t, (f) async {
      f.rows = [
        premiumizeFile('z9', name: '10. Ten.mkv'),
        premiumizeFile('a2', name: 'Season 10', folder: true),
        premiumizeFile('m5', name: '2. Two.mkv'),
        premiumizeFile('n6', name: 'Season 2', folder: true),
      ];
      await f.mount(t);
      expect(f.ids, [
        'z9',
        'a2',
        'm5',
        'n6',
      ], reason: 'root listing keeps server order rather than Sort order');
      f.member('navigateIntoFolder')(f.items[1]);
      await f.until(t, () => f.member('isLoading') == false);
      f.member('setViewMode')(f.member('sortedMode'));
      f.member('navigateUp')();
      await f.until(t, () => f.member('isLoading') == false);
      expect(f.ids, [
        'z9',
        'a2',
        'm5',
        'n6',
      ], reason: 'reentering root restores server order');
      expect(f.member('getCurrentViewMode')(), f.member('rawMode'));
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/list', {'id': 'a2'}),
        f.getRequest('folder/list'),
      ]);
    }),
  );
  testWidgets(
    'deep linked folder hides dropdown until navigation stack has a parent',
    (t) => premiumizeCase(t, (f) async {
      f.pages['z9'] = [premiumizeFile('child', folder: true)];
      await f.mount(t, initialId: 'z9', initialName: 'Deep folder');
      expect(f.member('isAtRoot'), isFalse);
      expect(f.member('navigationStack'), isEmpty);
      expect(
        find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        findsNothing,
        reason: 'deep link with empty stack has no view mode dropdown',
      );
      await t.tap(find.text('Folder child'));
      await f.until(t, () => f.member('isLoading') == false);
      expect(
        find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        findsOneWidget,
        reason: 'navigated folder with a parent exposes the dropdown',
      );
      f.member('navigateUp')();
      await f.until(t, () => f.member('isLoading') == false);
      expect(f.member('navigationStack'), isEmpty);
      expect(
        find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        findsNothing,
      );
      expect(f.log, [
        f.getRequest('folder/list', {'id': 'z9'}),
        f.getRequest('folder/list', {'id': 'child'}),
        f.getRequest('folder/list', {'id': 'z9'}),
      ]);
    }),
  );
  testWidgets(
    'navigate up focuses first parent row after held listing completes',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      f.member('navigateIntoFolder')(f.items.first);
      await f.until(t, () => f.member('isLoading') == false);
      await t.pump();
      expect((f.member('firstItemFocusNode') as FocusNode).hasFocus, isTrue);
      final search = f.member('searchButtonFocusNode') as FocusNode;
      search.requestFocus();
      await t.pump();
      expect(search.hasFocus, isTrue);
      final parent = Completer<http.Response>();
      f.held['folder/list|'] = parent;
      f.member('navigateUp')();
      await f.until(t, () => f.requests.length == 3);
      expect(f.ids, isEmpty);
      expect(f.member('isLoading'), isTrue);
      parent.complete(f.json(f.page(f.rows)));
      await f.until(t, () => f.member('isLoading') == false);
      await t.pump();
      await t.pump();
      expect(
        (f.member('firstItemFocusNode') as FocusNode).hasFocus,
        isTrue,
        reason: 'parent listing completion reclaims first row focus',
      );
      expect(search.hasFocus, isFalse);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/list', {'id': 'z9'}),
        f.getRequest('folder/list'),
      ]);
    }),
  );
  testWidgets(
    'TV focus waits through empty loading then chooses completed empty fallback',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      final listing = Completer<http.Response>();
      f.held['folder/list|z9'] = listing;
      f.member('navigateIntoFolder')(f.items.first);
      await f.until(t, () => f.requests.length == 2);
      final search = f.member('searchButtonFocusNode') as FocusNode;
      search.requestFocus();
      await t.pump();
      expect(f.ids, isEmpty);
      expect(f.member('isLoading'), isTrue);
      expect(MainPageBridge.requestTvContentFocus(), isTrue);
      await t.pump();
      await t.pump();
      expect(
        (f.member('addLinkButtonFocusNode') as FocusNode).hasFocus,
        isFalse,
        reason: 'held empty loading must not focus Add Link',
      );
      expect(search.hasFocus, isTrue);
      expect(f.member('shouldFocusOnLoad'), isTrue);
      listing.complete(f.json(f.page([])));
      await f.until(t, () => f.member('isLoading') == false);
      await t.pump();
      await t.pump();
      expect(
        (f.member('addLinkButtonFocusNode') as FocusNode).hasFocus,
        isTrue,
        reason: 'completed empty folder focuses Add Link',
      );
      expect(find.text('Folder is Empty'), findsOneWidget);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/list', {'id': 'z9'}),
      ]);
    }),
  );
  testWidgets(
    'selection during held empty navigation offers Select All with zero items',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      final listing = Completer<http.Response>();
      f.held['folder/list|z9'] = listing;
      f.member('navigateIntoFolder')(f.items.first);
      await f.until(t, () => f.requests.length == 2);
      expect(f.ids, isEmpty);
      expect(f.member('isLoading'), isTrue);
      await t.tap(find.byTooltip('Select items'));
      await t.pump();
      expect(f.member('isSelectionMode'), isTrue);
      expect(f.member('selectedIds'), isEmpty);
      expect(find.text('0 selected'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Select All'),
        findsOneWidget,
        reason: 'zero items must not be treated as all selected',
      );
      expect(find.text('Deselect All'), findsNothing);
      final delete = t.widget<FilledButton>(
        find.ancestor(
          of: find.text('Delete'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(delete.onPressed, isNull);
      listing.complete(f.json(f.page([])));
      await f.until(t, () => f.member('isLoading') == false);
      expect(find.text('Select All'), findsOneWidget);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/list', {'id': 'z9'}),
      ]);
    }),
  );
}

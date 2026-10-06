import 'dart:async';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:debrify/widgets/cloud/cloud_file_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/premiumize_files_fixture.dart';

Future<void> search(WidgetTester t, PremiumizeFixture f, String query) async {
  if (f.member('isSearchActive') == false) {
    await t.tap(find.byTooltip('Search files'));
    await t.pump();
  }
  await t.enterText(find.byType(TextField), query);
  await t.pump();
}

void main() {
  testWidgets(
    'root debounce fires at exactly 350ms and replaces unsettled query',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      await search(t, f, 'Alpha');
      expect(f.member('isSearching'), isTrue);
      await t.pump(const Duration(milliseconds: 349));
      expect(f.log, [
        f.getRequest('folder/list'),
      ], reason: 'no root request at 349ms');
      await t.pump(const Duration(milliseconds: 1));
      expect(f.requests.length, 2, reason: 'one root request at 350ms');
      await f.until(t, () => f.member('isSearching') == false);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/search', {'q': 'Alpha'}),
      ], reason: 'one root request at 350ms');
      await search(t, f, 'Beta');
      await t.pump(const Duration(milliseconds: 200));
      await search(t, f, 'Gamma');
      await t.pump(const Duration(milliseconds: 150));
      expect(f.requests.length, 2);
      await t.pump(const Duration(milliseconds: 200));
      await f.until(t, () => f.requests.length == 3);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/search', {'q': 'Alpha'}),
        f.getRequest('folder/search', {'q': 'Gamma'}),
      ]);
    }),
  );
  testWidgets(
    'toggle search clears selection focuses field and cancels timer',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      f.member('toggleSelectionMode')();
      f.member('toggleSelection')('a2');
      await t.pump();
      await search(t, f, 'Alpha');
      await t.pump();
      expect(f.member('isSelectionMode'), isFalse);
      expect(f.member('selectedIds'), isEmpty);
      expect((f.member('searchFocusNode') as FocusNode).hasFocus, isTrue);
      await t.tap(find.byTooltip('Close search'));
      await t.pump(const Duration(milliseconds: 350));
      expect(f.member('isSearchActive'), isFalse);
      expect(f.member('isSearching'), isFalse);
      expect(f.resultIds, isEmpty);
      expect((f.member('searchController') as TextEditingController).text, '');
      expect(f.log, [f.getRequest('folder/list')]);
    }),
  );
  testWidgets(
    'typing empty cancels debounce resets flag and results',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      await search(t, f, 'Alpha');
      await search(t, f, '');
      await t.pump(const Duration(milliseconds: 350));
      expect(f.member('isSearching'), isFalse);
      expect(f.resultIds, isEmpty);
      expect(f.log, [f.getRequest('folder/list')]);
    }),
  );
  for (final keyboard in [false, true]) {
    testWidgets(
      'clear button preserves pending timer and flag keyboard=$keyboard',
      (t) => premiumizeCase(t, (f) async {
        await f.mount(t);
        await search(t, f, 'Alpha');
        if (keyboard) {
          (f.member('searchClearFocusNode') as FocusNode).requestFocus();
          await t.pump();
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await t.tap(find.byIcon(Icons.clear));
        }
        await t.pump();
        expect(
          (f.member('searchController') as TextEditingController).text,
          '',
        );
        expect(f.resultIds, isEmpty);
        expect(
          f.member('isSearching'),
          isTrue,
          reason: 'clear button retains in-flight flag',
        );
        await t.pump(const Duration(milliseconds: 349));
        expect(f.requests.length, 1);
        await t.pump(const Duration(milliseconds: 1));
        await f.until(t, () => f.requests.length == 2);
        expect(f.log, [
          f.getRequest('folder/list'),
          f.getRequest('folder/search', {'q': 'Alpha'}),
        ]);
        expect(f.member('isSearching'), isTrue);
        expect((f.member('searchFocusNode') as FocusNode).hasFocus, isTrue);
      }),
    );
  }
  testWidgets(
    'folder navigation leaves root debounce armed',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      await search(t, f, 'Alpha');
      f.member('navigateIntoFolder')(premiumizeItem('z9', folder: true));
      await f.until(t, () => f.member('isLoading') == false);
      expect(f.member('isSearchActive'), isFalse);
      await t.pump(const Duration(milliseconds: 350));
      await f.until(t, () => f.requests.length == 3);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/list', {'id': 'z9'}),
        f.getRequest('folder/search', {'q': 'Alpha'}),
      ]);
    }),
  );
  testWidgets(
    'folder filter is synchronous files only case insensitive',
    (t) => premiumizeCase(t, (f) async {
      f.pages['z9'] = [
        premiumizeFile('folder', name: 'Alpha folder', folder: true),
        premiumizeFile('a2', name: 'Alpha.mkv'),
        premiumizeFile('m5', name: 'Beta.mkv'),
      ];
      await f.mount(t);
      f.member('navigateIntoFolder')(premiumizeItem('z9', folder: true));
      await f.until(t, () => f.member('isLoading') == false);
      await search(t, f, ' ALPHA ');
      expect(f.resultIds, ['a2']);
      expect(f.member('isSearching'), isFalse);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/list', {'id': 'z9'}),
      ]);
      await search(t, f, '');
      expect(f.resultIds, isEmpty);
    }),
  );
  testWidgets(
    'stale success drops result after field changes',
    (t) => premiumizeCase(t, (f) async {
      final a = Completer<http.Response>();
      f.held['folder/search|A'] = a;
      await f.mount(t);
      await search(t, f, 'A');
      await t.pump(const Duration(milliseconds: 350));
      await f.until(t, () => f.requests.length == 2);
      await search(t, f, 'B');
      a.complete(f.json(f.page([premiumizeFile('old')])));
      await t.pump();
      await t.pump();
      expect(f.resultIds, isEmpty);
      expect(f.member('isSearching'), isTrue);
      await t.pump(const Duration(milliseconds: 350));
      await f.until(t, () => f.member('isSearching') == false);
      expect(f.resultIds, ['hit']);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/search', {'q': 'A'}),
        f.getRequest('folder/search', {'q': 'B'}),
      ]);
    }),
  );
  testWidgets(
    'stale failure clears newer loading flag and shows error',
    (t) => premiumizeCase(t, (f) async {
      final a = Completer<http.Response>(), b = Completer<http.Response>();
      f.held['folder/search|A'] = a;
      f.held['folder/search|B'] = b;
      await f.mount(t);
      await search(t, f, 'A');
      await t.pump(const Duration(milliseconds: 350));
      await f.until(t, () => f.requests.length == 2);
      await search(t, f, 'B');
      await t.pump(const Duration(milliseconds: 350));
      await f.until(t, () => f.requests.length == 3);
      expect(f.member('isSearching'), isTrue);
      a.complete(f.json({'status': 'error'}, 500));
      await f.until(t, () => f.member('isSearching') == false);
      expect(find.textContaining('Search failed:'), findsOneWidget);
      expect(f.resultIds, isEmpty);
      b.complete(f.json(f.page([premiumizeFile('new')])));
      await f.until(t, () => f.resultIds.isNotEmpty);
      expect(f.resultIds, ['new']);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/search', {'q': 'A'}),
        f.getRequest('folder/search', {'q': 'B'}),
      ]);
    }),
  );
  testWidgets(
    'A B A accepts first A response by field text',
    (t) => premiumizeCase(t, (f) async {
      final a = Completer<http.Response>();
      f.held['folder/search|A'] = a;
      await f.mount(t);
      await search(t, f, 'A');
      await t.pump(const Duration(milliseconds: 350));
      await f.until(t, () => f.requests.length == 2);
      await search(t, f, 'B');
      await search(t, f, 'A');
      a.complete(f.json(f.page([premiumizeFile('first-A')])));
      await f.until(t, () => f.resultIds.isNotEmpty);
      expect(f.resultIds, ['first-A']);
      expect(f.member('isSearching'), isFalse);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/search', {'q': 'A'}),
      ]);
      await t.tap(find.byTooltip('Close search'));
      await t.pump();
    }),
  );
  testWidgets(
    'search arrows and clear left restore expected focus',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      await search(t, f, 'Alpha');
      final field = t.widget<TvTextField>(find.byType(TvTextField));
      field.onUpArrow!();
      await t.pump();
      expect((f.member('searchButtonFocusNode') as FocusNode).hasFocus, isTrue);
      field.onRightArrow!();
      await t.pump();
      expect((f.member('searchClearFocusNode') as FocusNode).hasFocus, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      expect((f.member('searchFocusNode') as FocusNode).hasFocus, isTrue);
      await t.pump(const Duration(milliseconds: 350));
      await f.until(t, () => f.member('isSearching') == false);
      expect(f.resultIds, ['hit']);
      (f.member('searchFocusNode') as FocusNode).requestFocus();
      await t.pump();
      field.onDownArrow!();
      await t.pump();
      final row = t.widget<CloudFileRow>(
        find.widgetWithText(CloudFileRow, 'Video hit.mkv'),
      );
      expect(row.focusNode, isNull);
      expect(
        (f.member('searchFocusNode') as FocusNode).hasFocus,
        isTrue,
        reason: 'original single-result ArrowDown remains in the search field',
      );
      await t.tap(find.byTooltip('Close search'));
      await t.pump();
    }),
  );
}

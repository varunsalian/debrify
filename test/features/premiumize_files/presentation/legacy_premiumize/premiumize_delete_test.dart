import 'dart:async';
import 'package:debrify/models/premiumize_transfer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/premiumize_files_fixture.dart';

void main() {
  for (final folder in [false, true]) {
    for (final confirm in [false, true]) {
      testWidgets(
        'single delete dialog lexical pop folder=$folder confirm=$confirm',
        (t) => premiumizeCase(t, (f) async {
          await f.mount(t, useNested: true);
          await f.transitions(t);
          f.member('toggleSelectionMode')();
          f.member('toggleSelection')('m5');
          final item = f.items.firstWhere(
            (i) => i.id == (folder ? 'z9' : 'a2'),
          );
          var beforeRequest = false;
          f.onRequest = (r) async {
            if (r.method == 'POST') {
              beforeRequest = f.member('isSelectionMode') == true;
            }
          };
          f.member('showDeleteDialog')(item);
          await f.transitions(t);
          final cancel = t.widget<TextButton>(
            find.widgetWithText(TextButton, 'Cancel'),
          );
          expect(cancel.autofocus, isTrue);
          final del = t.widget<TextButton>(
            find.widgetWithText(TextButton, 'Delete'),
          );
          expect(del.style!.foregroundColor!.resolve({}), Colors.red);
          await t.tap(
            find.widgetWithText(TextButton, confirm ? 'Delete' : 'Cancel'),
          );
          await f.transitions(t);
          if (confirm) {
            await f.until(t, () => f.member('isSelectionMode') == false);
          }
          expect(
            f.nestedObserver.popped,
            isEmpty,
            reason: 'delete pops dialog lexical root navigator',
          );
          expect(f.observer.popped.whereType<PopupRoute>().length, 1);
          expect(f.log, [
            f.getRequest('folder/list'),
            if (confirm)
              f.postRequest(folder ? 'folder/delete' : 'item/delete', {
                'apikey': 'fixture-key',
                'id': item.id,
              }),
          ]);
          expect(
            f.ids,
            confirm
                ? (folder ? ['a2', 'm5'] : ['z9', 'm5'])
                : ['z9', 'a2', 'm5'],
          );
          if (confirm) {
            expect(beforeRequest, isTrue);
            expect(f.member('selectedIds'), isEmpty);
            expect(find.text('Deleting 1 item...'), findsOneWidget);
          }
        }),
      );
    }
  }
  for (final confirm in [false, true]) {
    testWidgets(
      'selected snapshot ordered sequential deletes confirm=$confirm',
      (t) => premiumizeCase(t, (f) async {
        await f.mount(t);
        f.member('toggleSelectionMode')();
        f.member('toggleSelection')('m5');
        f.member('toggleSelection')('z9');
        f.member('toggleSelection')('a2');
        final h = Completer<http.Response>();
        f.held['folder/delete|z9'] = h;
        final action = f.member('handleDeleteSelected')() as Future<void>;
        await f.transitions(t);
        // Change the live collection during confirmation: the accepted snapshot remains.
        f.items.removeWhere((i) => i.id == 'a2');
        await t.tap(
          find.widgetWithText(TextButton, confirm ? 'Delete' : 'Cancel'),
        );
        await t.pump();
        if (confirm) {
          await f.until(t, () => f.requests.length == 2);
          expect(f.log, [
            f.getRequest('folder/list'),
            f.postRequest('folder/delete', {
              'apikey': 'fixture-key',
              'id': 'z9',
            }),
          ], reason: 'second delete waits for first response');
          h.complete(f.json({'status': 'success'}));
          await action;
        } else {
          await action;
          h.complete(f.json({'status': 'success'}));
        }
        await f.transitions(t);
        expect(f.log, [
          f.getRequest('folder/list'),
          if (confirm) ...[
            f.postRequest('folder/delete', {
              'apikey': 'fixture-key',
              'id': 'z9',
            }),
            f.postRequest('item/delete', {'apikey': 'fixture-key', 'id': 'a2'}),
            f.postRequest('item/delete', {'apikey': 'fixture-key', 'id': 'm5'}),
          ],
        ], reason: 'snapshot uses original item order');
        expect(f.ids, confirm ? isEmpty : ['z9', 'm5']);
        expect(f.member('isSelectionMode'), !confirm);
      }),
    );
  }
  testWidgets(
    'partial delete retains failure removes search result and clears selection',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      f.failures.add('item/delete|m5');
      f.searches['Video'] = [premiumizeFile('a2'), premiumizeFile('m5')];
      await t.tap(find.byTooltip('Search files'));
      await t.pump();
      await t.enterText(find.byType(TextField), 'Video');
      await t.pump(const Duration(milliseconds: 350));
      await f.until(t, () => f.member('isSearching') == false);
      expect(f.resultIds, [
        'a2',
        'm5',
      ], reason: 'matching search completes before deletion');
      f.member('toggleSelectionMode')();
      f.member('toggleSelectAll')();
      await f.member('executeDelete')(List.of(f.items));
      await t.pump();
      expect(f.ids, ['m5']);
      expect(f.resultIds, ['m5']);
      expect(f.member('selectedIds'), isEmpty);
      expect(f.member('isSelectionMode'), isFalse);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/search', {'q': 'Video'}),
        f.postRequest('folder/delete', {'apikey': 'fixture-key', 'id': 'z9'}),
        f.postRequest('item/delete', {'apikey': 'fixture-key', 'id': 'a2'}),
        f.postRequest('item/delete', {'apikey': 'fixture-key', 'id': 'm5'}),
      ]);
      await f.waitForText(t, 'Deleted 2, 1 failed');
    }),
  );
  for (final outcome in ['cancel', 'success', 'failure']) {
    testWidgets(
      'transfer delete confirm and failure $outcome',
      (t) => premiumizeCase(t, (f) async {
        await f.mount(t);
        f.member('switchView')(f.member('transfersView'));
        await f.until(t, () => f.member('isLoadingTransfers') == false);
        final identity = f.member('transfers');
        if (outcome == 'failure') f.failures.add('transfer/delete|t9');
        final action =
            f.member('deleteTransfer')(
                  (identity as List<PremiumizeTransfer>).first,
                )
                as Future<void>;
        await f.transitions(t);
        await t.tap(find.text(outcome == 'cancel' ? 'Cancel' : 'Delete'));
        await action;
        await f.transitions(t);
        expect(identical(f.member('transfers'), identity), isTrue);
        expect(
          (f.member('transfers') as List<PremiumizeTransfer>).map((r) => r.id),
          outcome == 'success' ? ['t2', 't5'] : ['t9', 't2', 't5'],
        );
        expect(f.log, [
          f.getRequest('folder/list'),
          f.getRequest('transfer/list'),
          if (outcome != 'cancel')
            f.postRequest('transfer/delete', {
              'apikey': 'fixture-key',
              'id': 't9',
            }),
        ]);
        if (outcome != 'cancel') {
          expect(
            find.textContaining(
              outcome == 'success'
                  ? 'Transfer removed'
                  : 'Failed to remove transfer:',
            ),
            findsOneWidget,
          );
        }
      }),
    );
  }
  testWidgets(
    'clear finished posts before awaited transfer reload',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      await t.tap(find.text('Transfers'));
      await f.until(t, () => f.member('isLoadingTransfers') == false);
      f.transfers = f.transfers.skip(1).toList();
      await t.tap(find.text('Clear finished'));
      await f.until(
        t,
        () => f.requests.length == 4 && f.member('isLoadingTransfers') == false,
      );
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('transfer/list'),
        f.postRequest('transfer/clearfinished', {'apikey': 'fixture-key'}),
        f.getRequest('transfer/list'),
      ]);
      expect(find.text('Cleared finished transfers'), findsOneWidget);
      expect(find.text('Clear finished'), findsNothing);
    }),
  );
}

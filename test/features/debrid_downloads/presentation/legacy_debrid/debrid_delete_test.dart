import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/debrid_downloads_fixture.dart';

void main() {
  for (final ddl in [false, true]) {
    for (final confirm in [false, true]) {
      testWidgets(
        'single DELETE ddl=$ddl confirm=$confirm',
        (t) => debridCase(t, (f) async {
          await f.mount(t);
          if (ddl) await f.ddl(t);
          final id = ddl ? 'w8' : 'z9';
          final action =
              f.member(ddl ? 'handleDeleteDownload' : 'handleDeleteTorrent')(
                    ddl ? f.download(id) : f.torrent(id),
                  )
                  as Future<void>;
          await t.pumpAndSettle();
          expect(f.deletes, isEmpty);
          await t.tap(
            find.widgetWithText(TextButton, confirm ? 'Delete' : 'Cancel'),
          );
          await t.pumpAndSettle();
          await action;
          expect(f.deletes.length, confirm ? 1 : 0);
          if (confirm) {
            expect(
              f.deletes.single.url.path,
              '/rest/1.0/${ddl ? 'downloads' : 'torrents'}/delete/$id',
            );
            expect(f.deletes.single.body, '');
          }
          expect(
            (f.member(ddl ? 'downloads' : 'torrents') as List).map(
              (dynamic r) => r.id,
            ),
            confirm
                ? (ddl ? ['b3', 'n6'] : ['a2', 'm5'])
                : (ddl ? ['w8', 'b3', 'n6'] : ['z9', 'a2', 'm5']),
          );
          expect(find.byType(AlertDialog), findsNothing);
        }),
      );
    }
    for (final scenario in ['success', 'partial', 'cancel', 'decline']) {
      testWidgets(
        'selected DELETE ddl=$ddl $scenario insertion order exact waits and state',
        (t) => debridCase(t, (f) async {
          await f.mount(t);
          if (ddl) await f.ddl(t);
          final ids = ddl ? ['n6', 'w8', 'b3'] : ['m5', 'z9', 'a2'];
          final active = ddl ? 'selectedDownloadIds' : 'selectedTorrentIds';
          final inactive = ddl ? 'selectedTorrentIds' : 'selectedDownloadIds';
          f.member('toggleSelectionMode')();
          (f.member(active) as Set<String>).addAll(ids);
          (f.member(inactive) as Set<String>).add('other');
          f.failDelete = scenario == 'partial' ? ids[1] : null;
          if (scenario == 'cancel') {
            f.holdDelete = true;
            f.pending = Completer<http.Response>();
          }
          var done = false;
          final action = f.member('handleDeleteSelected')() as Future<void>;
          action.then((_) => done = true);
          await t.pumpAndSettle();
          expect(
            find.text('Delete 3 ${ddl ? 'downloads' : 'torrents'}'),
            findsOneWidget,
          );
          expect(f.deletes, isEmpty);
          await t.tap(
            find.widgetWithText(
              TextButton,
              scenario == 'decline' ? 'Cancel' : 'Delete',
            ),
          );
          await t.pump();
          await t.pump();
          if (scenario == 'decline') {
            await action;
            expect(f.deletes, isEmpty);
            expect(f.member('isSelectionMode'), isTrue);
            expect((f.member(active) as Set).toList(), ids);
            return;
          }
          await f.until(t, () => f.deleteCount == 1);
          if (scenario == 'cancel') {
            await t.pumpAndSettle();
            await t.tap(find.widgetWithText(TextButton, 'Cancel'));
            await t.pumpAndSettle();
            expect(done, isFalse);
            f.pending!.complete(http.Response('', 204));
            await t.pump();
            await t.pump();
            await f.until(t, () => done);
            expect(
              done,
              isTrue,
              reason: 'Post-request cancellation bypasses the 150 ms wait',
            );
          } else {
            for (var count = 1; count <= 3; count++) {
              await t.pump(const Duration(milliseconds: 149));
              expect(f.deleteCount, count);
              expect(done, isFalse);
              await t.pump(const Duration(milliseconds: 1));
              if (count < 3) {
                await f.until(t, () => f.deleteCount == count + 1);
              } else {
                await f.until(t, () => done);
              }
            }
          }
          await action;
          await t.pumpAndSettle();
          expect(
            f.deletes.map((r) => r.url.path.split('/').last),
            scenario == 'cancel' ? [ids.first] : ids,
          );
          expect(f.deletes.every((r) => r.body.isEmpty), isTrue);
          expect(
            (f.member(ddl ? 'downloads' : 'torrents') as List).map(
              (dynamic r) => r.id,
            ),
            scenario == 'success'
                ? []
                : scenario == 'partial'
                ? [ids[1]]
                : ddl
                ? ['w8', 'b3']
                : ['z9', 'a2'],
          );
          expect(
            (f.member(active) as Set).toList(),
            scenario == 'cancel' ? ids.skip(1).toList() : [],
          );
          expect(
            (f.member(inactive) as Set).toList(),
            scenario == 'cancel' ? ['other'] : [],
          );
          expect(f.member('isSelectionMode'), scenario == 'cancel');
          if (scenario == 'partial') {
            expect(find.text('Deleted 2. 1 failed to delete.'), findsOneWidget);
          }
          if (scenario == 'cancel') {
            expect(find.textContaining('deleted successfully'), findsNothing);
          }
          expect(find.byType(AlertDialog), findsNothing);
        }),
      );
    }
    for (final scenario in [
      'success',
      'partial',
      'cancel',
      'fetch-cancel',
      'decline',
      'paged-cancel',
    ]) {
      testWidgets(
        'delete ALL ddl=$ddl $scenario real confirmation unfiltered refresh and success-only waits',
        (t) => debridCase(t, (f) async {
          await f.mount(t);
          if (ddl) await f.ddl(t);
          final ids = ddl ? ['n6', 'w8', 'b3'] : ['m5', 'z9', 'a2'];
          final originalRows = ddl ? f.downloads : f.torrents;
          originalRows.sort(
            (a, b) => ids.indexOf(a['id']).compareTo(ids.indexOf(b['id'])),
          );
          if (!ddl) {
            originalRows[1]['status'] = 'waiting_files_selection';
          }
          f.member('toggleSelectionMode')();
          (f.member('selectedTorrentIds') as Set).add('kept-t');
          (f.member('selectedDownloadIds') as Set).add('kept-d');
          f.failDelete = scenario == 'partial' ? ids[1] : null;
          if (['cancel', 'paged-cancel'].contains(scenario)) {
            f.holdDelete = true;
            f.pending = Completer<http.Response>();
          }
          if (scenario == 'fetch-cancel') {
            f.holdAll = true;
            f.pending = Completer<http.Response>();
          }
          if (scenario == 'paged-cancel') {
            final pages = <int, List<Map<String, dynamic>>>{
              1: [
                ...originalRows,
                for (var i = 0; i < 997; i++)
                  ddl ? debridDownload('extra-$i') : debridTorrent('extra-$i'),
              ],
              2: [ddl ? debridDownload('tail') : debridTorrent('tail')],
            };
            if (ddl) {
              f.allDownloadPages = pages;
            } else {
              f.allTorrentPages = pages;
            }
          }
          final before = f.requests.length;
          var done = false;
          final action =
              f.member(
                    ddl
                        ? 'handleDeleteAllDownloads'
                        : 'handleDeleteAllTorrents',
                  )()
                  as Future<void>;
          action.then((_) => done = true);
          await t.pumpAndSettle();
          expect(f.requests.length, before);
          await t.tap(
            find.widgetWithText(
              TextButton,
              scenario == 'decline' ? 'Cancel' : 'Delete All',
            ),
          );
          await t.pump();
          await t.pump();
          if (scenario == 'decline') {
            await action;
            expect(f.requests.length, before);
            return;
          }
          await f.until(
            t,
            () => f.requests
                .skip(before)
                .any((r) => r.url.queryParameters['limit'] == '1000'),
          );
          if (scenario == 'fetch-cancel') {
            await t.pump(const Duration(milliseconds: 200));
            await t.tap(find.widgetWithText(TextButton, 'Cancel'));
            await t.pumpAndSettle();
            expect(done, isFalse);
            f.pending!.complete(http.Response(jsonEncode(originalRows), 200));
            await f.until(t, () => done);
            expect(f.deletes, isEmpty);
          } else {
            await f.until(t, () => f.deleteCount == 1);
            if (['cancel', 'paged-cancel'].contains(scenario)) {
              await t.pumpAndSettle();
              await t.tap(find.widgetWithText(TextButton, 'Cancel'));
              await t.pumpAndSettle();
              expect(done, isFalse);
              f.pending!.complete(http.Response('', 204));
              await t.pump();
              await t.pump();
              await t.pump(const Duration(milliseconds: 149));
              expect(done, isFalse);
              expect(f.deleteCount, 1);
              await t.pump(const Duration(milliseconds: 1));
              await f.until(t, () => done);
            } else {
              await t.pump(const Duration(milliseconds: 149));
              expect(f.deleteCount, 1);
              await t.pump(const Duration(milliseconds: 1));
              await f.until(
                t,
                () => f.deleteCount == (scenario == 'partial' ? 3 : 2),
              );
              if (scenario == 'partial') {
                expect(
                  f.deleteCount,
                  3,
                  reason: 'No wait after failed second request',
                );
              } else {
                await t.pump(const Duration(milliseconds: 149));
                expect(f.deleteCount, 2);
                await t.pump(const Duration(milliseconds: 1));
                await f.until(t, () => f.deleteCount == 3);
              }
              await t.pump(const Duration(milliseconds: 149));
              expect(done, isFalse);
              await t.pump(const Duration(milliseconds: 1));
              await f.until(t, () => done);
            }
            expect(
              f.deletes.map((r) => r.url.path.split('/').last),
              ['cancel', 'paged-cancel'].contains(scenario) ? [ids.first] : ids,
            );
          }
          await action;
          await t.pumpAndSettle();
          final gets = f.requests
              .skip(before)
              .where((r) => r.method == 'GET')
              .toList();
          expect(
            gets.map((r) => r.url.queryParameters['limit']),
            scenario == 'paged-cancel'
                ? ['1000', '1000', '50']
                : ['1000', '50'],
          );
          expect(
            gets.map((r) => r.url.queryParameters['page']),
            scenario == 'paged-cancel' ? ['1', '2', '1'] : ['1', '1'],
          );
          expect(
            gets.every((r) => !r.url.queryParameters.containsKey('filter')),
            isTrue,
          );
          expect((f.member('selectedTorrentIds') as Set).toList(), ['kept-t']);
          expect((f.member('selectedDownloadIds') as Set).toList(), ['kept-d']);
          expect(f.member('isSelectionMode'), isTrue);
          if (scenario == 'partial') {
            expect(
              find.text(
                'Deleted 2 ${ddl ? 'downloads' : 'torrents'}. 1 failed to delete.',
              ),
              findsOneWidget,
            );
          }
          if (scenario == 'success') {
            expect((f.member(ddl ? 'downloads' : 'torrents') as List), isEmpty);
          }
          if (['cancel', 'paged-cancel', 'fetch-cancel'].contains(scenario)) {
            expect(find.textContaining('deleted successfully'), findsNothing);
          }
        }),
      );
    }
  }
}

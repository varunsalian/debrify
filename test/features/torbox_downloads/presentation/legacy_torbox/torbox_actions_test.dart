import 'dart:async';
import 'dart:convert';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/torbox_downloads_fixture.dart';

void main() {
  for (final web in [false, true]) {
    for (final confirm in [false, true]) {
      testWidgets(
        'single delete web=$web confirm=$confirm exact POST',
        (t) => torboxCase(t, (f) async {
          await f.mount(t);
          final future = web
              ? f.member('confirmDeleteWebDownload')(f.download(11))
              : f.member('confirmDeleteTorrent')(f.torrent(1));
          await t.pumpAndSettle();
          await t.tap(
            find.widgetWithText(
              confirm ? FilledButton : TextButton,
              confirm ? 'Delete' : 'Cancel',
            ),
          );
          await t.pumpAndSettle();
          await future;
          final posts = f.requests.where((r) => r.method == 'POST').toList();
          expect(posts.length, confirm ? 1 : 0);
          if (confirm) {
            expect(
              posts.single.url.path,
              web
                  ? '/v1/api/webdl/controlwebdownload'
                  : '/v1/api/torrents/controltorrent',
            );
            expect(
              jsonDecode(posts.single.body),
              web
                  ? {'webdl_id': 11, 'operation': 'delete'}
                  : {'torrent_id': '1', 'all': false, 'operation': 'delete'},
            );
          }
          expect(find.byType(AlertDialog), findsNothing);
        }),
      );
    }
    for (final scenario in ['success', 'partial', 'cancel', 'decline']) {
      testWidgets(
        'bulk delete web=$web $scenario preserves insertion order selection and dialog',
        (t) => torboxCase(t, (f) async {
          await f.mount(t);
          if (web) await t.tap(find.text('Web Downloads'));
          await t.pumpAndSettle();
          final ids = web ? [13, 11, 12] : [3, 1, 2];
          f.member('toggleSelectionMode')();
          (f.member(web ? 'selectedWebDownloadIds' : 'selectedTorrentIds')
                  as Set<int>)
              .addAll(ids);
          f.failDelete = scenario == 'partial' ? ids[1] : null;
          if (scenario == 'cancel') {
            f.holdDelete = true;
            f.pending = Completer<http.Response>();
          }
          var done = false;
          final future = f.member('handleDeleteSelected')() as Future<void>;
          future.then((_) => done = true);
          await t.pumpAndSettle();
          final label = web ? 'web downloads' : 'torrents';
          expect(find.text('Delete 3 $label'), findsOneWidget);
          expect(
            find.text(
              'Are you sure you want to delete 3 selected $label? This action cannot be undone.',
            ),
            findsOneWidget,
          );
          expect(f.deleteCount, 0);
          await t.tap(
            find.widgetWithText(
              TextButton,
              scenario == 'decline' ? 'Cancel' : 'Delete',
            ),
          );
          // Pump no elapsed time: preserve the first inter-request deadline.
          await t.pump();
          await t.pump();
          if (scenario == 'decline') {
            await future;
            await t.pumpAndSettle();
            expect(f.deleteCount, 0);
            expect(f.member('isSelectionMode'), isTrue);
            expect(
              (f.member(web ? 'selectedWebDownloadIds' : 'selectedTorrentIds')
                      as Set<int>)
                  .toList(),
              ids,
            );
            expect(find.byType(AlertDialog), findsNothing);
            return;
          }
          await f.until(t, () => f.deleteCount == 1);
          if (scenario != 'cancel') {
            await t.pump(const Duration(milliseconds: 149));
            expect(f.deleteCount, 1, reason: 'No second request before 150 ms');
            await t.pump(const Duration(milliseconds: 1));
            await f.until(t, () => f.deleteCount == 2);
            expect(f.deleteCount, 2, reason: 'Next request starts at 150 ms');
          }
          if (scenario == 'cancel') {
            await t.pumpAndSettle();
            expect(f.deleteCount, 1);
            await t.tap(find.widgetWithText(TextButton, 'Cancel'));
            await t.pumpAndSettle();
            expect(
              done,
              isFalse,
              reason: 'Cancellation lets the in-flight POST finish',
            );
            f.pending!.complete(http.Response('{"success":true}', 200));
          }
          for (var i = 0; i < 40 && !done; i++) {
            await t.pump(const Duration(milliseconds: 200));
          }
          expect(
            done,
            isTrue,
            reason: 'Bulk loop completes after its ordered 150 ms waits',
          );
          await future;
          await t.pumpAndSettle();
          final posts = f.requests.where((r) => r.method == 'POST').toList();
          final processed = posts.map((r) {
            final p = jsonDecode(r.body);
            return int.parse('${p[web ? 'webdl_id' : 'torrent_id']}');
          }).toList();
          expect(processed, scenario == 'cancel' ? [ids.first] : ids);
          final rows = (f.member(web ? 'webDownloads' : 'torrents') as List)
              .map((e) => e.id)
              .toList();
          expect(
            rows,
            scenario == 'success'
                  ? []
                  : scenario == 'partial'
                  ? [ids[1]]
                  : ids.skip(1).toList()
              ..sort(),
          );
          final selected =
              f.member(web ? 'selectedWebDownloadIds' : 'selectedTorrentIds')
                  as Set<int>;
          expect(
            selected.toList(),
            scenario == 'cancel' ? ids.skip(1).toList() : [],
          );
          expect(f.member('isSelectionMode'), scenario == 'cancel');
          expect(find.byType(AlertDialog), findsNothing);
        }),
      );
    }
  }
  for (final confirm in [false, true]) {
    testWidgets(
      'delete all confirm=$confirm exact all POST',
      (t) => torboxCase(t, (f) async {
        await f.mount(t);
        final future = f.member('confirmDeleteAll')();
        await t.pumpAndSettle();
        await t.tap(
          find.widgetWithText(
            confirm ? FilledButton : TextButton,
            confirm ? 'Delete All' : 'Cancel',
          ),
        );
        await t.pumpAndSettle();
        await future;
        final posts = f.requests.where((r) => r.method == 'POST').toList();
        expect(posts.length, confirm ? 1 : 0);
        if (confirm) {
          expect(jsonDecode(posts.single.body), {
            'operation': 'delete',
            'all': true,
          });
        }
      }),
    );
  }
  for (final web in [false, true]) {
    for (final scenario in ['success', 'failure', 'cancel']) {
      testWidgets(
        'create web=$web $scenario request and refresh',
        (t) => torboxCase(t, (f) async {
          await f.mount(t);
          f.failCreate = scenario == 'failure';
          final before = f.requests.length;
          final future = f.member(
            web ? 'showAddWebDownloadDialog' : 'showAddMagnetDialog',
          )();
          await t.pumpAndSettle();
          if (!web) {
            await f.until(
              t,
              () => find.text('Add Magnet Link').evaluate().isNotEmpty,
            );
            await t.pumpAndSettle();
          }
          if (scenario == 'cancel') {
            await t.tap(find.widgetWithText(TextButton, 'Cancel'));
          } else {
            if (web) {
              (f.member('webLinkController') as TextEditingController).text =
                  'https://example.test/archive';
              (f.member('webNameController') as TextEditingController).text =
                  'Fixture name';
              (f.member('webPasswordController') as TextEditingController)
                      .text =
                  'fixture password';
            } else {
              (f.member('magnetController') as TextEditingController).text =
                  'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567';
            }
            await t.pump();
            await t.tap(find.widgetWithText(FilledButton, 'Add'));
          }
          await t.pumpAndSettle();
          await future;
          final added = f.requests.skip(before).toList();
          final posts = added.where((r) => r.method == 'POST').toList();
          expect(posts.length, scenario == 'cancel' ? 0 : 1);
          if (posts.isNotEmpty) {
            expect(
              posts.single.url.path,
              web
                  ? '/v1/api/webdl/createwebdownload'
                  : '/v1/api/torrents/createtorrent',
            );
            final body = posts.single.body;
            if (web) {
              expect(body, contains('https://example.test/archive'));
              expect(body, contains('Fixture name'));
              expect(body, contains('fixture password'));
            } else {
              expect(body, contains('magnet:?xt=urn:btih:'));
              for (final entry in {
                'seed': '1',
                'allow_zip': 'true',
                'add_only_if_cached': 'true',
              }.entries) {
                expect(
                  body,
                  contains('name="${entry.key}"\r\n\r\n${entry.value}\r\n'),
                );
              }
            }
          }
          final refresh = added.where((r) => r.method == 'GET').toList();
          expect(refresh.length, scenario == 'success' ? 1 : 0);
          if (refresh.isNotEmpty) {
            expect(
              refresh.single.url.path,
              web ? '/v1/api/webdl/mylist' : '/v1/api/torrents/mylist',
            );
          }
          expect(find.byType(AlertDialog), findsNothing);
        }),
      );
    }
  }
  for (final web in [false, true]) {
    for (final count in [1, 3]) {
      testWidgets(
        'playlist persistence web=$web files=$count kind and ordered IDs',
        (t) => torboxCase(t, (f) async {
          await f.mount(t);
          await t.runAsync(() async {
            if (web) {
              await f.member('handleAddWebDownloadToPlaylist')(
                f.download(
                  42,
                  files: count,
                  fileIds: count == 1 ? [3] : [3, 1, 2],
                ),
              );
            } else {
              await f.member('handleAddToPlaylist')(
                f.torrent(
                  42,
                  files: count,
                  fileIds: count == 1 ? [3] : [3, 1, 2],
                ),
              );
            }
          });
          final items = await t.runAsync(PlaylistStorage.getPlaylistItemsRaw);
          expect(items!.length, 1);
          final item = items.single;
          expect(item['provider'], web ? 'torbox_webdl' : 'torbox');
          expect(item['kind'], count == 1 ? 'single' : 'collection');
          expect(item[web ? 'torboxWebDownloadId' : 'torboxTorrentId'], 42);
          expect(
            item[count == 1 ? 'torboxFileId' : 'torboxFileIds'],
            count == 1 ? 3 : [3, 1, 2],
          );
          expect(item[web ? 'webdl_hash' : 'torrent_hash'], 'hash-42');
        }),
      );
    }
  }
  testWidgets(
    'magnet created from Web Downloads refreshes web list',
    (t) => torboxCase(t, (f) async {
      await f.mount(t);
      await t.tap(find.text('Web Downloads'));
      await t.pumpAndSettle();
      final before = f.requests.length;
      final future = f.member('showAddMagnetDialog')();
      await f.until(
        t,
        () => find.text('Add Magnet Link').evaluate().isNotEmpty,
      );
      await t.pumpAndSettle();
      (f.member('magnetController') as TextEditingController).text =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567';
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Add'));
      await t.pumpAndSettle();
      await future;
      final added = f.requests.skip(before).toList();
      expect(
        added.where((r) => r.method == 'POST').single.url.path,
        '/v1/api/torrents/createtorrent',
      );
      expect(
        added.where((r) => r.method == 'GET').single.url.path,
        '/v1/api/webdl/mylist',
      );
    }),
  );
}

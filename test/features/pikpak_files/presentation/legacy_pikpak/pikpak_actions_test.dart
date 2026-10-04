import 'dart:async';
import 'dart:convert';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/pikpak_files_fixture.dart';

void main() {
  for (final restricted in [false, true]) {
    for (final failure in [false, true]) {
      testWidgets(
        'add link real dialog exact parent body refresh restricted=$restricted failure=$failure',
        (t) => pikpakCase(
          t,
          (f) async {
            f.failPost = failure;
            await f.mount(
              t,
              initialId: restricted ? null : 'z9',
              initialName: restricted ? null : 'Target',
            );
            f.clipboardText = ' https://example.test/new.mkv ';
            await t.tap(find.byTooltip('Add Link'));
            await t.pump();
            await f.until(
              t,
              () =>
                  (f.member('linkController') as TextEditingController).text
                      .trim() ==
                  'https://example.test/new.mkv',
            );
            await t.pump(const Duration(milliseconds: 600));
            await t.tap(find.text('Add'));
            await t.pump();
            await f.until(
              t,
              () =>
                  f.requests.any((r) => r.method == 'POST') &&
                  f.member('isAddingLink') == false,
            );
            if (!failure) {
              await f.until(t, () => f.member('isLoading') == false);
            }
            await t.pump();
            final post = f.requests.singleWhere((r) => r.method == 'POST');
            expect(post.url.path, '/drive/v1/files');
            expect(jsonDecode(post.body), {
              'kind': 'drive#file',
              'name': '',
              'parent_id': restricted ? 'restricted' : 'z9',
              'upload_type': 'UPLOAD_TYPE_URL',
              'url': {'url': 'https://example.test/new.mkv'},
              'folder_type': '',
            });
            expect(f.requests.map((r) => (r.method, r.url.path)), [
              if (restricted) ('GET', '/drive/v1/files/restricted'),
              ('GET', '/drive/v1/files'),
              ('POST', '/drive/v1/files'),
              if (!failure) ('GET', '/drive/v1/files'),
            ]);
            expect(f.observer.popped.length, 2);
            expect(f.member('isAddingLink'), isFalse);
            expect(
              (f.member('linkController') as TextEditingController).text,
              failure ? 'https://example.test/new.mkv' : '',
            );
            expect(
              find.textContaining(
                failure ? 'Failed to add:' : 'Added to PikPak: Fixture added',
              ),
              findsWidgets,
            );
          },
          preferences: {
            if (restricted) 'pikpak_restricted_folder_id': 'restricted',
          },
        ),
      );
    }
  }
  for (final input in ['', 'ftp://invalid', 'magnet:?xt=urn:btih:fixture']) {
    testWidgets(
      'add dialog validation and cancel retain original input behavior $input',
      (t) => pikpakCase(t, (f) async {
        await f.mount(t);
        await t.tap(find.byTooltip('Add Link'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), input);
        if (input.startsWith('magnet:')) {
          await t.tap(find.text('Cancel'));
          await t.pump();
          expect(
            (f.member('linkController') as TextEditingController).text,
            '',
          );
        } else {
          await t.tap(find.text('Add'));
          await t.pump();
          expect(
            find.text(
              input.isEmpty
                  ? 'Please enter a link'
                  : 'Please enter a valid URL or magnet link',
            ),
            findsOneWidget,
          );
          expect(find.byType(AlertDialog), findsOneWidget);
        }
        expect(f.requests.length, 1);
      }),
    );
  }
  testWidgets(
    'selected download loop waits each fresh GET skips null ids and counts missing URLs',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t);
      final held = Completer<http.Response>();
      f.heldDetails['n6'] = held;
      f.details['b3'] = pikpakFile('b3', url: false);
      f.details['m5'] = pikpakFile('m5', url: false);
      final done =
          f.member('downloadSelectedPikPakFiles')([
                pikpakFile('n6'),
                {'name': 'null-id.mkv'},
                pikpakFile('b3'),
                pikpakFile('m5'),
              ], 'Selected folder')
              as Future<void>;
      await f.until(t, () => f.requests.length == 2);
      expect(f.requests.last.url.path, '/drive/v1/files/n6');
      expect(find.text('Queuing 4 files...'), findsOneWidget);
      await t.pump();
      expect(f.requests.length, 2);
      held.complete(f.json(pikpakFile('n6', url: false)));
      await f.until(t, () => f.observer.popped.length == 1);
      await done;
      await t.pump();
      expect(f.requests.map((r) => (r.method, r.url.path)), [
        ('GET', '/drive/v1/files'),
        ('GET', '/drive/v1/files/n6'),
        ('GET', '/drive/v1/files/b3'),
        ('GET', '/drive/v1/files/m5'),
      ]);
      expect(
        find.text('Failed to queue any files for download'),
        findsOneWidget,
      );
      expect(find.text('Queuing 4 files...'), findsNothing);
    }),
  );
  for (final series in [false, true]) {
    for (final acrossSeasons in [false, if (series) true]) {
      testWidgets(
        'multi video preparation resolves only sorted start URL series=$series'
        '${acrossSeasons ? ' across seasons' : ''}',
        (t) => pikpakCase(t, (f) async {
          await f.mount(t);
          final rows = series
              ? [
                  pikpakFile(
                    'z9',
                    name: acrossSeasons ? 'A.S02E01.mkv' : 'A.S01E03.mkv',
                  ),
                  pikpakFile('m5', name: 'B.S01E02.mkv'),
                  pikpakFile('a2', name: 'C.S01E01.mkv'),
                ]
              : [
                  pikpakFile('z9', name: 'Zebra.mkv'),
                  pikpakFile('m5', name: 'Beta.mkv'),
                  pikpakFile('a2', name: 'Alpha.mkv'),
                ];
          expect(
            SeriesParser.isSeriesPlaylist(
              rows.map((row) => row['name'] as String).toList(),
            ),
            series,
          );
          for (final row in rows) {
            final id = row['id'] as String;
            f.details[id] = pikpakFile(id, url: id != 'a2');
          }
          f.onRequest = (request) async {
            if (request.url.path.startsWith('/drive/v1/files/')) {
              expect(request.url.path, '/drive/v1/files/a2');
            }
          };
          final done =
              f.member('playPikPakVideos')(rows, 'Collection') as Future<void>;
          await f.until(t, () => f.requests.length == 2);
          await done;
          await t.pump();
          expect(f.requests.map((r) => (r.method, r.url.path)), [
            ('GET', '/drive/v1/files'),
            ('GET', '/drive/v1/files/a2'),
          ]);
          expect(find.text('Could not get streaming URL'), findsOneWidget);
          expect(
            f.member('findFirstEpisodeIndex')(
              SeriesParser.parsePlaylist([
                'Show.S02E10.mkv',
                'Show.S01E02.mkv',
                'Show.S01E01.mkv',
              ]),
            ),
            2,
          );
          if (series) {
            expect(
              f.member('findFirstEpisodeIndex')(
                SeriesParser.parsePlaylist(
                  rows.map((row) => row['name'] as String).toList(),
                ),
              ),
              2,
            );
          }
          expect(
            f.member('findFirstEpisodeIndex')(
              SeriesParser.parsePlaylist(['Alpha.mkv', 'Beta.mkv']),
            ),
            0,
          );
        }),
      );
    }
  }
  for (final ignoreSmall in [false, true]) {
    testWidgets(
      'real folder playlist action conditional 99 versus exactly 100 MiB ignore=$ignoreSmall with paging',
      (t) => pikpakCase(t, (f) async {
        f.pages['z9|'] = f.page([
          pikpakFile('n6', mib: 99),
        ], next: 'playlist-page');
        f.pages['z9|playlist-page'] = f.page([pikpakFile('b3', mib: 100)]);
        await f.mount(t);
        final done =
            f.member('handleAddToPlaylist')(pikpakFile('z9', folder: true))
                as Future<void>;
        await f.until(t, () => f.requests.length == 3);
        await t.runAsync(() => done);
        await t.pump();
        final items = await t.runAsync(PlaylistStorage.getPlaylistItemsRaw);
        expect(items!.length, 1);
        final item = items.single;
        expect(item['provider'], 'pikpak');
        expect(item['kind'], ignoreSmall ? 'single' : 'collection');
        expect(item['pikpakFileId'], ignoreSmall ? 'b3' : 'z9');
        if (ignoreSmall) {
          expect(item['sizeBytes'], 104857600);
          expect(item['pikpakFile'], {
            'id': 'b3',
            'name': 'Video b3.mkv',
            'size': '104857600',
            'mime_type': 'video/x-matroska',
          });
        } else {
          expect(item['pikpakFileIds'], ['n6', 'b3']);
          expect((item['pikpakFiles'] as List).map((dynamic r) => r['size']), [
            '103809024',
            '104857600',
          ]);
          expect(item['count'], 2);
        }
        expect(
          f.requests.map(
            (r) => (
              r.method,
              r.url.path,
              r.url.queryParameters['parent_id'],
              r.url.queryParameters['page_token'],
            ),
          ),
          [
            ('GET', '/drive/v1/files', '', null),
            ('GET', '/drive/v1/files', 'z9', null),
            ('GET', '/drive/v1/files', 'z9', 'playlist-page'),
          ],
        );
      }, preferences: {'pikpak_ignore_small_videos': ignoreSmall}),
    );
  }
  testWidgets(
    'direct small-file playlist action accepted with ignore setting on',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t);
      final done =
          f.member('handleAddToPlaylist')(pikpakFile('m5', mib: 99))
              as Future<void>;
      await t.runAsync(() => done);
      await t.pump();
      final items = await t.runAsync(PlaylistStorage.getPlaylistItemsRaw);
      expect(items!.single['provider'], 'pikpak');
      expect(items.single['kind'], 'single');
      expect(items.single['pikpakFileId'], 'm5');
      expect(items.single['sizeBytes'], 103809024);
      expect(f.requests.length, 1);
    }),
  );
}

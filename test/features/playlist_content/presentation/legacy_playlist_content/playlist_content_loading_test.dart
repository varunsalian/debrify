import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/playlist_content_fixture.dart';

void main() {
  final requests = <String, List<String>>{
    'realdebrid': ['GET api.real-debrid.com/rest/1.0/torrents/info/rd9'],
    'alldebrid': [
      'POST api.alldebrid.com/v4/magnet/upload',
      'POST api.alldebrid.com/v4/magnet/files',
    ],
    'torbox': ['GET api.torbox.app/v1/api/torrents/mylist'],
    'pikpak': ['GET api-drive.mypikpak.com/drive/v1/files'],
    'premiumize': ['POST www.premiumize.me/api/transfer/directdl'],
    'webdav': [],
  };
  for (final provider in requests.keys) {
    for (final upperCase in [false, true]) {
      testWidgets(
        'load dispatch $provider uppercase=$upperCase exact requests and files',
        (t) => playlistContentCase(t, (f) async {
          await f.mount(
            t,
            provider: upperCase ? provider.toUpperCase() : provider,
          );
          expect(f.log, requests[provider]);
          expect(f.root.getAllFiles().map((n) => n.name), [
            '10. Ten.mkv',
            '2. Two.mkv',
            'readme.txt',
          ]);
          expect(f.root.getAllFiles().map((n) => n.bytes), [
            200000000,
            300000000,
            7,
          ]);
          if (provider == 'realdebrid') {
            expect(f.root.getAllFiles().map((n) => n.fileId), [9, 2, 5]);
            expect(
              f.requests.single.headers['Authorization'],
              'Bearer fixture-rd',
            );
          }
          if (provider == 'alldebrid') {
            expect(
              f.requests[0].body,
              'magnets%5B%5D=magnet%3A%3Fxt%3Durn%3Abtih%3Aabc123',
            );
            expect(f.requests[1].body, 'id%5B%5D=71');
            expect(
              f.requests[0].headers['Authorization'],
              'Bearer fixture-alldebrid',
            );
          }
          if (provider == 'pikpak') {
            expect(f.requests.single.url.queryParameters['limit'], '100');
            expect(
              f.requests.single.url.queryParameters['parent_id'],
              'folder-z9',
            );
          }
          if (provider == 'torbox') {
            expect(f.requests.single.url.queryParameters['id'], '91');
          }
          if (provider == 'premiumize') {
            expect(
              f.requests.single.body,
              'src=magnet%3A%3Fxt%3Durn%3Abtih%3Aabc123',
            );
          }
        }),
      );
    }
  }
  for (final provider in ['rd', 'torbox_webdl', 'real_debrid', 'unknown']) {
    testWidgets(
      'noncanonical $provider loads through RD',
      (t) => playlistContentCase(t, (f) async {
        await f.mount(t, provider: provider);
        expect(f.log, requests['realdebrid']);
        expect(f.root.getAllFiles().map((n) => n.fileId), [9, 2, 5]);
      }),
    );
  }
  testWidgets(
    'absent provider defaults to RD',
    (t) => playlistContentCase(t, (f) async {
      f.item.remove('provider');
      await f.mount(t);
      expect(f.log, requests['realdebrid']);
    }),
  );
  testWidgets(
    'AllDebrid Refresh reuploads but does not reparse or reapply view',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t, provider: 'alldebrid');
      final root = f.root;
      final nodes = f.member('currentViewNodes');
      final series = f.member('seriesPlaylist');
      await t.tap(find.byTooltip('Refresh'));
      await f.until(
        t,
        () => f.requests.length == 4 && f.member('isLoading') == false,
      );
      expect(f.log, [...requests['alldebrid']!, ...requests['alldebrid']!]);
      expect(identical(f.root, root), isFalse);
      expect(identical(f.member('currentViewNodes'), nodes), isTrue);
      expect(identical(f.member('seriesPlaylist'), series), isTrue);
    }),
  );
  testWidgets(
    'Retry loads content alone and retains absent view and series',
    (t) => playlistContentCase(t, (f) async {
      f.failures.add('/rest/1.0/torrents/info/rd9');
      await f.mount(t);
      expect(f.member('rootContent'), isNull);
      expect(f.member('currentViewNodes'), isNull);
      expect(find.text('Retry'), findsOneWidget);
      f.failures.clear();
      await t.tap(find.text('Retry'));
      await f.until(
        t,
        () => f.member('isLoading') == false && f.requests.length == 2,
      );
      expect(f.root.getAllFiles(), hasLength(3));
      expect(f.member('currentViewNodes'), isNull);
      expect(f.member('seriesPlaylist'), isNull);
      expect(f.log, [...requests['realdebrid']!, ...requests['realdebrid']!]);
    }),
  );
  testWidgets(
    'TorBox retains internal retry and integer id request',
    (t) => playlistContentCase(t, (f) async {
      f.torboxFailures = 2;
      await f.mount(t, provider: 'torbox');
      expect(f.log, List.filled(3, requests['torbox']!.single));
      expect(f.requests.map((r) => r.url.queryParameters['id']), [
        '91',
        '91',
        '91',
      ]);
    }),
  );
  testWidgets(
    'PikPak recursive traversal is sequential and indices reset per folder',
    (t) => playlistContentCase(t, (f) async {
      f.pages['folder-z9'] = [
        contentPikpakFile('z', 'Season 2', folder: true),
        contentPikpakFile('a', 'Root.mkv'),
        contentPikpakFile('m', 'Season 1', folder: true),
      ];
      f.pages['z'] = [contentPikpakFile('z9', 'Show.S02E02.mkv')];
      f.pages['m'] = [contentPikpakFile('m5', 'Show.S01E01.mkv')];
      await f.mount(t, provider: 'pikpak');
      expect(
        f.requests
            .where((r) => r.url.host == 'api-drive.mypikpak.com')
            .map((r) => r.url.queryParameters['parent_id']),
        ['folder-z9', 'z', 'm'],
      );
      expect(
        f.requests
            .where((r) => r.url.host == 'api-drive.mypikpak.com')
            .map((r) => r.url.queryParameters['limit']),
        ['100', '100', '100'],
      );
      expect(f.root.getAllFiles().map((n) => n.relativePath), [
        'Season 2/Show.S02E02.mkv',
        'Root.mkv',
        'Season 1/Show.S01E01.mkv',
      ]);
      expect(f.root.getAllFiles().map((n) => n.fileId), [0, 0, 0]);
    }),
  );
  testWidgets(
    'PikPak depth beyond four fails before fifth child request',
    (t) => playlistContentCase(t, (f) async {
      f.pages['folder-z9'] = [contentPikpakFile('depth-1', 'D1', folder: true)];
      for (var i = 1; i <= 5; i++) {
        f.pages['depth-$i'] = [
          contentPikpakFile('depth-${i + 1}', 'D${i + 1}', folder: true),
        ];
      }
      await f.mount(t, provider: 'pikpak');
      expect(f.requests.map((r) => r.url.queryParameters['parent_id']), [
        'folder-z9',
        'depth-1',
        'depth-2',
        'depth-3',
        'depth-4',
      ]);
      expect(
        f.member('errorMessage'),
        contains('Folder hierarchy too deep (max 4 levels)'),
      );
      expect(f.member('rootContent'), isNull);
    }),
  );
  testWidgets(
    'cached PikPak fallback flat skips folders and keeps absent relative paths',
    (t) => playlistContentCase(t, (f) async {
      f.item.remove('pikpakFileId');
      f.item['pikpakFiles'] = [
        contentPikpakFile('z9', 'Folder', folder: true),
        contentPikpakFile('a2', '2. Two.mkv'),
        contentPikpakFile('m5', '10. Ten.mkv'),
      ];
      await f.mount(t, provider: 'pikpak');
      expect(f.log, isEmpty);
      expect(f.root.children.map((n) => n.fileId), [1, 2]);
      expect(f.root.children.map((n) => n.relativePath), [null, null]);
      expect(f.root.children.map((n) => n.path), [
        'pikpak://a2|2. Two.mkv',
        'pikpak://m5|10. Ten.mkv',
      ]);
    }),
  );
  for (final single in [false, true]) {
    testWidgets(
      'Premiumize cloud metadata no request single=$single',
      (t) => playlistContentCase(t, (f) async {
        f.item.remove('torrent_hash');
        final rows = [
          {'id': 'z9', 'name': 'Cloud.mkv', 'size': '123'},
          {'id': 'a2', 'name': '2. Cloud.mkv', 'size': 456},
        ];
        f.item[single ? 'premiumizeFile' : 'premiumizeFiles'] = single
            ? rows.first
            : rows;
        await f.mount(t, provider: 'premiumize');
        expect(f.log, isEmpty);
        expect(
          f.root.children.map((n) => n.path),
          single ? ['z9'] : ['z9', 'a2'],
        );
        expect(
          f.root.children.map((n) => n.bytes),
          single ? [123] : [123, 456],
        );
      }),
    );
  }
  for (final kind in ['single', 'path', 'empty']) {
    testWidgets(
      'WebDAV metadata $kind no request',
      (t) => playlistContentCase(t, (f) async {
        f.item.remove('webdavFiles');
        if (kind == 'single') {
          f.item['webdavFile'] = {
            'path': '/Pack/Folder/Single.mkv',
            'sizeBytes': '123',
          };
        } else if (kind == 'path') {
          f.item['webdavPath'] = '/Pack/Folder/Fallback.mkv';
          f.item['sizeBytes'] = 456;
        }
        await f.mount(t, provider: 'webdav');
        expect(f.log, isEmpty);
        if (kind == 'empty') {
          expect(
            f.member('errorMessage'),
            contains('No WebDAV file data found'),
          );
        } else {
          final file = f.root.getAllFiles().single;
          expect(file.name, kind == 'single' ? 'Single.mkv' : 'Fallback.mkv');
          expect(
            file.relativePath,
            kind == 'single' ? 'Folder/Single.mkv' : 'Folder/Fallback.mkv',
          );
          expect(file.bytes, kind == 'single' ? 123 : 456);
          expect(f.root.children.single.isFolder, isTrue);
        }
      }),
    );
  }
  testWidgets(
    'held load after unmount records unguarded error setState',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t);
      final held = Completer<http.Response>();
      f.held['/rest/1.0/torrents/info/rd9'] = held;
      final error = Completer<Object>();
      runZonedGuarded<void>(
        () {
          f.member('initializeScreen')();
        },
        (value, stack) {
          error.complete(value);
        },
      );
      await f.until(t, () => f.requests.length == 2);
      await t.pumpWidget(const SizedBox.shrink());
      await t.runAsync(() async {
        held.complete(f.json({'error': 'held failure'}, 500));
        final value = await error.future;
        expect(value, isFlutterError);
        expect(value.toString(), contains('setState() called after dispose'));
      });
      await t.pump();
    }),
  );
}

import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/playlist_content_fixture.dart';

Future<void> drainRoutes(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await t.pump();
}

void main() {
  for (final provider in [
    'realdebrid',
    'alldebrid',
    'torbox',
    'pikpak',
    'premiumize',
    'premiumize-cloud',
    'webdav',
  ]) {
    testWidgets(
      'rejection path $provider resolves exact start and callback before notify',
      (t) => playlistContentCase(t, (f) async {
        if (provider == 'premiumize-cloud') {
          f.item.remove('torrent_hash');
          f.item['premiumizeFiles'] = [
            {'id': 'z9', 'name': '10. Ten.mkv', 'size': 200000000},
            {'id': 'a2', 'name': '2. Two.mkv', 'size': 300000000},
          ];
        }
        await f.mount(
          t,
          provider: provider == 'premiumize-cloud' ? 'premiumize' : provider,
          started: () => f.events.add('callback'),
        );
        f.requests.clear();
        final probe = PlaylistContentProbe(f)..install();
        try {
          final file = f.root.getAllFiles().firstWhere(
            (n) => n.name == '2. Two.mkv',
          );
          await f.invoke(t, () => f.member('playFile')(file));
          await drainRoutes(t);
          expect(f.events, ['callback', 'launch 1', 'launch 2', 'stopped']);
          expect(probe.stops, 1);
          expect(
            find.text('Player settings could not be loaded. Please try again.'),
            findsOneWidget,
          );
          expect(f.observer.pushed.whereType<DialogRoute>(), hasLength(1));
          expect(f.observer.popped.whereType<DialogRoute>(), hasLength(1));
          switch (provider) {
            case 'realdebrid':
              expect(f.log, [
                'GET api.real-debrid.com/rest/1.0/torrents/info/rd9',
                'POST api.real-debrid.com/rest/1.0/unrestrict/link',
              ]);
              expect(
                f.requests.last.body,
                'link=https%3A%2F%2Flocked.test%2F2',
              );
            case 'alldebrid':
              expect(f.log, ['POST api.alldebrid.com/v4/link/unlock']);
              expect(
                f.requests.single.body,
                'link=https%3A%2F%2Flocked.test%2F2',
              );
            case 'torbox':
              expect(f.log, ['GET api.torbox.app/v1/api/torrents/requestdl']);
              expect(f.requests.single.url.queryParameters['file_id'], '2');
              expect(f.requests.single.url.queryParameters['torrent_id'], '91');
            case 'pikpak':
              expect(f.log, [
                'GET api-drive.mypikpak.com/drive/v1/files/file-2',
              ]);
            case 'premiumize':
              expect(f.log, ['POST www.premiumize.me/api/transfer/directdl']);
            case 'premiumize-cloud':
              expect(f.log, ['GET www.premiumize.me/api/item/details']);
              expect(f.requests.single.url.queryParameters['id'], 'a2');
            case 'webdav':
              expect(f.log, isEmpty);
          }
        } finally {
          probe.remove();
        }
      }),
    );
  }
  for (final provider in [
    'REALDEBRID',
    'ALLDEBRID',
    'TORBOX',
    'PIKPAK',
    'PREMIUMIZE',
    'WEBDAV',
  ]) {
    testWidgets(
      'play dispatch lowercases uppercase $provider',
      (t) => playlistContentCase(t, (f) async {
        await f.mount(
          t,
          provider: provider.toLowerCase(),
          started: () => f.events.add('callback'),
        );
        f.item['provider'] = provider;
        f.requests.clear();
        final probe = PlaylistContentProbe(f)..install();
        try {
          await f.invoke(
            t,
            () => f.member('playFile')(f.root.getAllFiles()[1]),
          );
          await drainRoutes(t);
          expect(probe.calls, 2);
          expect(f.events, ['callback', 'launch 1', 'launch 2', 'stopped']);
          expect(
            find.text('Player settings could not be loaded. Please try again.'),
            findsOneWidget,
          );
        } finally {
          probe.remove();
        }
      }),
    );
  }
  for (final provider in ['rd', 'torbox_webdl', 'real_debrid', 'unknown']) {
    testWidgets(
      'noncanonical $provider prepares pops reloads without launching',
      (t) => playlistContentCase(t, (f) async {
        await f.mount(t, provider: provider);
        final cache = f.member('fileProgressCache');
        final probe = PlaylistContentProbe(f)..install();
        try {
          await f.invoke(
            t,
            () => f.member('playFile')(f.root.getAllFiles().first),
          );
          await drainRoutes(t);
          expect(probe.calls, 0);
          expect(f.log, ['GET api.real-debrid.com/rest/1.0/torrents/info/rd9']);
          expect(f.observer.pushed.whereType<DialogRoute>(), hasLength(1));
          expect(f.observer.popped.whereType<DialogRoute>(), hasLength(1));
          expect(identical(f.member('fileProgressCache'), cache), isFalse);
        } finally {
          probe.remove();
        }
      }),
    );
  }
  for (final playlistCaller in [false, true]) {
    testWidgets(
      'rejection return caller playlist=$playlistCaller route and dialog ownership',
      (t) => playlistContentCase(t, (f) async {
        await f.mount(t, pushed: true, playlistCaller: playlistCaller);
        final probe = PlaylistContentProbe(f)..install();
        try {
          await f.invoke(
            t,
            () => f.member('playFile')(f.root.getAllFiles()[1]),
          );
          await drainRoutes(t);
          expect(probe.calls, 2);
          expect(probe.stops, 1);
          expect(f.observer.popped.whereType<DialogRoute>(), hasLength(1));
          expect(
            f.observer.popped.whereType<MaterialPageRoute>(),
            hasLength(playlistCaller ? 1 : 0),
          );
          expect(f.key.currentState == null, playlistCaller);
          expect(
            f.observer.events.where((s) => s.endsWith('pop')),
            playlistCaller ? ['dialog pop', 'route pop'] : ['dialog pop'],
          );
        } finally {
          probe.remove();
        }
      }),
    );
  }
  for (final sorted in [false, true]) {
    for (final originalIndex in [0, 900]) {
      testWidgets(
        'playEpisode chooses filename sorted=$sorted originalIndex=$originalIndex',
        (t) => playlistContentCase(t, (f) async {
          await f.mount(t, started: () => f.events.add('callback'));
          if (sorted) {
            f.member('applyViewMode')(FolderViewMode.sortedAZ);
          }
          final episode = SeriesEpisode(
            url: '',
            title: 'Episode',
            filename: '2. Two.mkv',
            seriesInfo: const SeriesInfo(isSeries: false),
            originalIndex: originalIndex,
          );
          final probe = PlaylistContentProbe(f)..install();
          try {
            await f.invoke(t, () => f.member('playEpisode')(episode));
            await drainRoutes(t);
            expect(probe.calls, 2);
            expect(
              f.requests.last.body,
              !sorted && originalIndex == 0
                  ? 'link=https%3A%2F%2Flocked.test%2F9'
                  : 'link=https%3A%2F%2Flocked.test%2F2',
            );
          } finally {
            probe.remove();
          }
        }),
      );
    }
  }
  testWidgets(
    'AllDebrid start unlock failure is swallowed and still rejects through launcher',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t, provider: 'alldebrid');
      f.failUnlock = true;
      f.requests.clear();
      final probe = PlaylistContentProbe(f)..install();
      try {
        await f.invoke(t, () => f.member('playFile')(f.root.getAllFiles()[1]));
        await drainRoutes(t);
        expect(probe.calls, 2);
        expect(f.log, ['POST api.alldebrid.com/v4/link/unlock']);
        expect(
          find.text('Player settings could not be loaded. Please try again.'),
          findsOneWidget,
        );
      } finally {
        probe.remove();
      }
    }),
  );
  testWidgets(
    'Premiumize cloud clamps before skipped null paths and can throw',
    (t) => playlistContentCase(t, (f) async {
      f.item.remove('torrent_hash');
      f.item['premiumizeFiles'] = [
        {'id': 'a2', 'name': 'Cloud.mkv'},
      ];
      await f.mount(
        t,
        provider: 'premiumize',
        started: () => f.events.add('started'),
      );
      final nodes = [
        RDFileNode(
          name: 'Skipped.mkv',
          isFolder: false,
          children: [],
          fileId: 9,
          bytes: 1,
          linkIndex: 0,
        ),
        RDFileNode.file(
          name: 'Cloud.mkv',
          fileId: 2,
          path: 'a2',
          bytes: 1,
          linkIndex: 1,
        ),
      ];
      final probe = PlaylistContentProbe(f)..install();
      try {
        await t.runAsync(
          () => expectLater(
            f.member('playPremiumizePlaylist')(nodes, 1),
            throwsA(isA<RangeError>()),
          ),
        );
        expect(probe.calls, 1);
        expect(probe.stops, 0);
        expect(f.events, ['started', 'launch 1']);
        expect(f.requests.last.url.queryParameters['id'], 'a2');
      } finally {
        probe.remove();
      }
    }),
  );
  for (final provider in ['premiumize', 'webdav']) {
    testWidgets(
      '$provider clamps against built entries',
      (t) => playlistContentCase(t, (f) async {
        await f.mount(t, provider: provider);
        final probe = PlaylistContentProbe(f)..install();
        try {
          final nodes = f.root
              .getAllFiles()
              .where((n) => n.name.endsWith('.mkv'))
              .toList();
          await f.invoke(
            t,
            () => f.member(
              provider == 'premiumize'
                  ? 'playPremiumizePlaylist'
                  : 'playWebDavPlaylist',
            )(nodes, 900),
          );
          expect(probe.calls, 2);
        } finally {
          probe.remove();
        }
      }),
    );
  }
  testWidgets(
    'empty video list closes preparing dialog without reload or launch',
    (t) => playlistContentCase(t, (f) async {
      f.files = [
        {'id': 5, 'path': '/Pack/readme.txt', 'bytes': 7, 'selected': 1},
      ];
      await f.mount(t);
      final cache = f.member('fileProgressCache');
      final probe = PlaylistContentProbe(f)..install();
      try {
        await f.invoke(
          t,
          () => f.member('playFile')(f.root.getAllFiles().single),
        );
        await drainRoutes(t);
        expect(probe.calls, 0);
        expect(f.observer.popped.whereType<DialogRoute>(), hasLength(1));
        expect(identical(f.member('fileProgressCache'), cache), isTrue);
      } finally {
        probe.remove();
      }
    }),
  );
  testWidgets(
    'resolution catch closes dialog reloads and shows failure snackbar',
    (t) => playlistContentCase(t, (f) async {
      await f.mount(t);
      f.failures.add('/rest/1.0/torrents/info/rd9');
      final cache = f.member('fileProgressCache');
      await f.invoke(t, () => f.member('playFile')(f.root.getAllFiles()[1]));
      await drainRoutes(t);
      expect(f.observer.popped.whereType<DialogRoute>(), hasLength(1));
      expect(identical(f.member('fileProgressCache'), cache), isFalse);
      expect(find.textContaining('Failed to play file:'), findsOneWidget);
    }),
  );
}

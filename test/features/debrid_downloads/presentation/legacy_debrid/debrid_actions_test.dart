import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/debrid_downloads_fixture.dart';

const magnet = 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567';
void main() {
  for (final mode in [
    'default',
    'smart',
    'largest',
    'video',
    'all',
    'uncached',
    'uncached-advanced',
  ]) {
    testWidgets(
      'magnet $mode exact selected values request order flags and cleanup',
      (t) => debridCase(t, (f) async {
        await f.mount(t);
        if (mode == 'default' || mode == 'uncached') {
          await RealDebridStorage.saveFileSelection('largest');
        }
        final uncached = mode.startsWith('uncached');
        f.noLinks = uncached;
        f.member('showAddMagnetDialog')();
        await t.pumpAndSettle();
        (f.member('magnetController') as TextEditingController).text = magnet;
        final before = f.requests.length;
        var done = false;
        final action =
            (mode == 'default' || mode == 'uncached'
                    ? f.member('addMagnetWithDefaultSelection')()
                    : f.member('addMagnetWithSelection')(
                        magnet,
                        mode == 'uncached-advanced' ? 'video' : mode,
                      ))
                as Future<void>;
        action.then((_) => done = true);
        await f.until(
          t,
          () => f.requests
              .skip(before)
              .any((r) => r.url.path.contains('/selectFiles/')),
        );
        expect(f.member('isAddingMagnet'), isTrue);
        await t.pump(const Duration(seconds: 2));
        await f.until(t, () => done);
        await action;
        await t.pumpAndSettle();
        final req = f.requests.skip(before).toList();
        expect(
          req.map((r) => '${r.method} ${r.url.path}'),
          uncached
              ? [
                  'POST /rest/1.0/torrents/addMagnet',
                  'GET /rest/1.0/torrents/info/new-torrent',
                  'POST /rest/1.0/torrents/selectFiles/new-torrent',
                  'GET /rest/1.0/torrents/info/new-torrent',
                  'DELETE /rest/1.0/torrents/delete/new-torrent',
                ]
              : [
                  'POST /rest/1.0/torrents/addMagnet',
                  'GET /rest/1.0/torrents/info/new-torrent',
                  'POST /rest/1.0/torrents/selectFiles/new-torrent',
                  'GET /rest/1.0/torrents/info/new-torrent',
                  'POST /rest/1.0/unrestrict/link',
                  'GET /rest/1.0/torrents',
                ],
        );
        expect(Uri.splitQueryString(req.first.body), {'magnet': magnet});
        expect(Uri.splitQueryString(req[2].body), {
          'files': ['default', 'largest', 'uncached'].contains(mode)
              ? '71'
              : '71,4,39',
        });
        expect(f.member('isAddingMagnet'), isFalse);
        if (!uncached) {
          expect(
            (f.member('magnetController') as TextEditingController).text,
            '',
          );
        }
        if (uncached) {
          expect(req.last.body, '');
          expect(
            find.text('File is not readily available in Real Debrid'),
            findsOneWidget,
          );
        }
      }),
    );
  }
  testWidgets(
    'real link add unrestrict payload refresh and cleared flag',
    (t) => debridCase(t, (f) async {
      await f.mount(t);
      final opening = f.member('showAddLinkDialog')() as Future<void>;
      await t.pumpAndSettle();
      (f.member('linkController') as TextEditingController).text =
          'https://example.test/archive';
      final before = f.requests.length;
      final action = f.member('addLink')() as Future<void>;
      await t.pumpAndSettle();
      await action;
      await opening;
      final req = f.requests.skip(before).toList();
      expect(req.map((r) => '${r.method} ${r.url.path}'), [
        'POST /rest/1.0/unrestrict/link',
        'GET /rest/1.0/downloads',
      ]);
      expect(Uri.splitQueryString(req.first.body), {
        'link': 'https://example.test/archive',
      });
      expect(f.member('isAddingLink'), isFalse);
      expect((f.member('linkController') as TextEditingController).text, '');
    }),
  );
  for (final kind in [
    'torrent-single',
    'torrent-collection',
    'node-single',
    'node-folder',
  ]) {
    testWidgets(
      'real playlist $kind persists exact provider map and enrichment',
      (t) => debridCase(t, (f) async {
        await f.mount(t);
        await f.member('navigateIntoTorrent')(f.torrent('z9'));
        await t.pumpAndSettle();
        final before = DateTime.now().millisecondsSinceEpoch;
        if (kind.startsWith('torrent')) {
          final row = debridTorrent('z9');
          if (kind == 'torrent-single') {
            row['links'] = ['https://example.test/restricted/z9/0'];
          }
          await f.member('handleAddTorrentToPlaylist')(RDTorrent.fromJson(row));
        } else {
          final nodes = f.member('currentViewNodes') as List<RDFileNode>;
          await f.member(
            kind == 'node-single'
                ? 'addNodeFileToPlaylist'
                : 'addFolderToPlaylist',
          )(nodes.firstWhere((n) => n.isFolder == (kind == 'node-folder')));
        }
        final entries = await PlaylistStorage.getPlaylistItemsRaw();
        final after = DateTime.now().millisecondsSinceEpoch;
        expect(entries.length, 1);
        final entry = entries.single;
        expect(
          entry['provider'],
          kind.startsWith('torrent') ? 'realdebrid' : 'rd',
        );
        expect(entry['rdTorrentId'], 'z9');
        expect(entry['torrent_hash'], 'hash-z9');
        expect(entry['addedAt'], inInclusiveRange(before, after));
        expect(
          entry['kind'],
          kind.endsWith('single') ? 'single' : 'collection',
        );
        if (kind == 'torrent-single') {
          expect(
            entry['restrictedLink'],
            'https://example.test/restricted/z9/0',
          );
          expect(entry['url'], '');
        }
        if (kind == 'torrent-collection') expect(entry['count'], 3);
        if (kind == 'node-single') {
          expect(entry['rdLinkIndex'], 0);
          expect(entry['sizeBytes'], 1000);
        }
        if (kind == 'node-folder') {
          expect(entry['fileCount'], 1);
          expect(entry['totalBytes'], 1000);
          expect((entry['rdFileNodes'] as List).single['linkIndex'], 2);
          expect((entry['rdFileNodes'] as List).single['fileId'], 39);
        }
        expect(f.requests.last.url.path, '/rest/1.0/torrents/info/z9');
      }),
    );
  }
}

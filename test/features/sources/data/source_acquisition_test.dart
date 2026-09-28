import 'dart:convert';
import 'dart:async';

import 'package:debrify/features/sources/data/manual_source_preparation.dart';
import 'package:debrify/features/sources/data/source_acquisition.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final torrent = Torrent(
  rowid: 0,
  infohash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  name: 'Fixture',
  sizeBytes: 1024,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
);

class Fixture {
  Fixture(this.provider, this.scenario);
  final String provider;
  final String scenario;
  final paths = <String>[];
  final requests = <http.Request>[];
  bool active = true;
  String? retireAt;
  void Function(http.Request)? onRequest;
  bool get single => scenario == 'single';
  bool get uncached => scenario == 'uncached';
  List<int> get episodes => single ? [2] : [2, 1];

  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    paths.add(path);
    onRequest?.call(request);
    if (retireAt != null && path.endsWith(retireAt!)) active = false;
    if (scenario == 'retired' && paths.length == 1) active = false;
    Object body;
    if (provider == 'premiumize') {
      body = path.endsWith('/cache/check')
          ? {
              'status': 'success',
              'response': [!uncached],
            }
          : {
              'status': 'success',
              'content': [
                for (final e in episodes)
                  {
                    'path': 'Fixture.S01E0$e.mkv',
                    'size': e * 100,
                    'link': 'https://stream.test/$e',
                  },
              ],
            };
    } else if (provider == 'torbox') {
      if (path.endsWith('/createtorrent')) {
        body = {
          'success': !uncached,
          'error': uncached ? 'NOT_CACHED' : '',
          'data': {'torrent_id': 7},
        };
      } else if (path.endsWith('/mylist')) {
        body = {
          'success': true,
          'data': {
            'id': 7,
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
            'download_state': scenario == 'lookupPending'
                ? 'downloading'
                : 'cached',
            'files': [
              for (final e in episodes)
                {'id': e, 'name': 'Fixture.S01E0$e.mkv', 'size': e * 100},
            ],
          },
        };
      } else {
        expect(path, endsWith('/requestdl'));
        body = {
          'success': true,
          'data':
              'https://stream.test/${request.url.queryParameters['file_id']}',
        };
      }
    } else if (provider == 'alldebrid') {
      final Object data;
      if (path.endsWith('/magnet/upload')) {
        data = {
          'magnets': [
            {'id': 'owned', 'ready': !uncached},
          ],
        };
      } else if (path.endsWith('/magnet/files')) {
        data = {
          'magnets': [
            {
              'files': [
                for (final e in episodes)
                  {'n': 'Fixture.S01E0$e.mkv', 's': e * 100, 'l': 'locked-$e'},
              ],
            },
          ],
        };
      } else if (path.endsWith('/link/unlock')) {
        data = scenario == 'delayed'
            ? {'delayed': 'pending'}
            : {
                'link':
                    'https://stream.test/${request.bodyFields['link']!.split('-').last}',
              };
      } else {
        expect(path, endsWith('/magnet/delete'));
        expect(request.bodyFields['id'], 'owned');
        data = <String, Object>{};
      }
      body = {'status': 'success', 'data': data};
    } else {
      if (path.endsWith('/torrents/addMagnet')) {
        body = {'id': 'owned'};
      } else if (path.contains('/torrents/info/')) {
        body = {
          'id': 'owned',
          'files': [
            for (final e in episodes)
              {
                'id': e,
                'name': 'Fixture.S01E0$e.mkv',
                'path': '/Fixture.S01E0$e.mkv',
                'bytes': e * 100,
                'selected': 1,
              },
          ],
          'links': uncached ? [] : [for (final e in episodes) 'locked-$e'],
        };
      } else if (path.endsWith('/unrestrict/link')) {
        body = {
          'download':
              'https://stream.test/${request.bodyFields['link']!.split('-').last}',
        };
      } else {
        expect(
          path,
          anyOf(endsWith('/selectFiles/owned'), endsWith('/delete/owned')),
        );
        return http.Response('', 204);
      }
    }
    return http.Response(
      jsonEncode(body),
      provider == 'debrid' && path.endsWith('/addMagnet') ? 201 : 200,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SecretVault.debugReset(deviceIdOverride: 'source-acquisition-fixture');
    SharedPreferences.setMockInitialValues({
      'real_debrid_api_key': 'rd-fixture',
      'torbox_api_key': 'tb-fixture',
      'premiumize_api_key': 'pm-fixture',
      'alldebrid_api_key': 'ad-fixture',
      'file_selection': 'all',
    });
  });
  tearDown(SecretVault.debugReset);

  for (final provider in ['debrid', 'torbox', 'premiumize', 'alldebrid']) {
    for (final scenario in ['single', 'pack', 'uncached']) {
      test(
        '$provider acquisition preserves $scenario requests and payload',
        () async {
          final f = Fixture(provider, scenario);
          final client = MockClient(f.respond);
          addTearDown(client.close);
          await http.runWithClient(() async {
            if (scenario == 'uncached') {
              final result = await const ManualSourcePreparation().prepare(
                provider,
                torrent,
              );
              expect(result.ready, isFalse);
              expect(result.failureMessage, isNull);
              expect(
                f.paths.where((p) => p.contains('/delete')).length,
                ['debrid', 'alldebrid'].contains(provider) ? 1 : 0,
              );
              return;
            }
            final result = await const SourceAcquisition().acquire(
              provider,
              'magnet:?xt=fixture',
              torrent,
            );
            expect(
              result.playUrl,
              'https://stream.test/${scenario == 'single' ? 2 : 1}',
            );
            if (scenario == 'single') {
              expect(result.playlist, isNull);
              expect(result.fileName, 'Fixture.S01E02.mkv');
            } else {
              final entries = result.playlist!;
              expect(entries, hasLength(2));
              expect(entries[result.startIndex].title, 'Fixture.S01E01.mkv');
              expect(entries[result.startIndex].url, 'https://stream.test/1');
              expect(
                entries.where((e) => e.url.isNotEmpty).length,
                provider == 'premiumize' ? 2 : 1,
              );
            }
            expect(f.paths.where((p) => p.contains('/delete')), isEmpty);
            if (provider == 'debrid') {
              expect(result.rdFolder!.id, 'owned');
              expect(result.rdTorrentId, 'owned');
              expect(
                f.paths.where((p) => p.endsWith('/unrestrict/link')),
                hasLength(2),
              );
            } else if (provider == 'torbox') {
              expect(result.torboxFolder!.id, 7);
              expect(result.torboxTorrentId, 7);
              expect(
                f.requests.first.body,
                contains('name="add_only_if_cached"\r\n\r\ntrue'),
              );
              expect(
                f.paths.where((p) => p.endsWith('/requestdl')),
                hasLength(1),
              );
            }
          }, () => client);
        },
      );
    }
  }
  for (final provider in ['debrid', 'torbox', 'premiumize', 'alldebrid']) {
    test(
      '$provider retirement prevents subsequent provider operation',
      () async {
        final f = Fixture(provider, 'retired');
        final client = MockClient(f.respond);
        addTearDown(client.close);
        final result = await http.runWithClient(
          () => const ManualSourcePreparation().prepare(
            provider,
            torrent,
            canContinue: () => f.active,
          ),
          () => client,
        );
        expect(result.ready, isFalse);
        expect(f.paths, hasLength(1));
      },
    );
  }
  for (final path in [
    '/torrents/info/owned',
    '/torrents/selectFiles/owned',
    '/unrestrict/link',
  ]) {
    test('RD retirement at $path stops later acquisition steps', () async {
      final f = Fixture('debrid', 'pack')..retireAt = path;
      final client = MockClient(f.respond);
      addTearDown(client.close);
      final result = await http.runWithClient(
        () => const ManualSourcePreparation().prepare(
          'debrid',
          torrent,
          canContinue: () => f.active,
        ),
        () => client,
      );
      expect(result.ready, isFalse);
      expect(f.paths.last, endsWith(path));
      if (path == '/unrestrict/link') {
        expect(f.paths.where((p) => p.endsWith(path)), hasLength(1));
      }
      expect(f.paths.where((p) => p.contains('/delete')), isEmpty);
    });
  }

  test(
    'TorBox retirement during lookup prevents retries and download requests',
    () async {
      final f = Fixture('torbox', 'lookupPending')
        ..retireAt = '/torrents/mylist';
      final client = MockClient(f.respond);
      addTearDown(client.close);
      final result = await http.runWithClient(
        () => const ManualSourcePreparation().prepare(
          'torbox',
          torrent,
          canContinue: () => f.active,
        ),
        () => client,
      );
      expect(result.ready, isFalse);
      expect(f.paths.map((p) => p.split('/').last), [
        'createtorrent',
        'mylist',
      ]);
    },
  );

  test(
    'AllDebrid retirement during delayed unlock wait prevents polling',
    () async {
      final f = Fixture('alldebrid', 'delayed');
      f.onRequest = (request) {
        if (request.url.path.endsWith('/link/unlock')) {
          Timer(const Duration(milliseconds: 100), () => f.active = false);
        }
      };
      final client = MockClient(f.respond);
      addTearDown(client.close);
      final result = await http.runWithClient(
        () => const ManualSourcePreparation().prepare(
          'alldebrid',
          torrent,
          canContinue: () => f.active,
        ),
        () => client,
      );
      expect(result.ready, isFalse);
      expect(f.paths.map((p) => p.split('/').last), [
        'upload',
        'files',
        'unlock',
      ]);
    },
  );
}

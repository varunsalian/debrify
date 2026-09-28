import 'dart:convert';

import 'package:debrify/features/sources/data/provider_cloud_source.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CloudFixture {
  CloudFixture(
    this.provider, {
    this.kind = SeriesSource.cloudKindFolder,
    this.retireAt,
    this.refreshFails = false,
  });
  final String provider;
  final String kind;
  final int? retireAt;
  final bool refreshFails;
  final requests = <http.Request>[];
  static const locked = 'https://locked.test/movie';
  SeriesSource get pin => SeriesSource(
    torrentHash: '',
    torrentName: 'Saved title',
    debridService: provider,
    debridTorrentId: provider == 'alldebrid'
        ? SeriesSource.opaqueCloudReference(locked)
        : (provider == 'torbox' ? '42' : 'root'),
    cloudSourceKind: ['rd', 'torbox', 'alldebrid'].contains(provider)
        ? SeriesSource.cloudKindWebDownload
        : kind,
    boundAt: 1,
  );
  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    if (requests.length == retireAt) ProfileSessionMemory.clearAll();
    final path = request.url.path;
    Object body;
    if (provider == 'rd') {
      if (path.endsWith('/downloads')) {
        body = [
          {
            'id': 'root',
            'filename': 'Movie.mkv',
            'link': locked,
            'download': 'https://stream.test/listed',
          },
        ];
      } else {
        expect(path, endsWith('/unrestrict/link'));
        if (refreshFails) return http.Response('unavailable', 503);
        body = {'download': 'https://stream.test/refreshed'};
      }
    } else if (provider == 'torbox') {
      if (path.endsWith('/mylist')) {
        body = {
          'success': true,
          'data': [
            {
              'id': 42,
              'download_finished': true,
              'files': [
                for (final episode in [2, 1])
                  {
                    'id': episode,
                    'name': 'Show.S01E0$episode.mkv',
                    'size': episode * 100,
                  },
                {'id': 3, 'name': 'notes.txt', 'size': 1000},
                {'id': 4, 'name': 'archive.mkv', 'size': 2000, 'zipped': true},
              ],
            },
          ],
        };
      } else {
        expect(path, endsWith('/requestdl'));
        expect(request.url.queryParameters['web_id'], '42');
        body = {
          'success': true,
          'data':
              'https://stream.test/${request.url.queryParameters['file_id']}',
        };
      }
    } else if (provider == 'alldebrid') {
      body = {
        'status': 'success',
        'data': path.endsWith('/user/links')
            ? {
                'links': [
                  {'link': locked, 'filename': 'Movie.mkv'},
                ],
              }
            : {'link': 'https://stream.test/unlocked'},
      };
    } else if (provider == 'premiumize') {
      if (path.endsWith('/item/details')) {
        body = {
          'status': 'success',
          'name': 'Movie.mkv',
          'link': 'https://stream.test/file',
        };
      } else {
        expect(path, endsWith('/folder/list'));
        body = {
          'status': 'success',
          'content': request.url.queryParameters['id'] == 'root'
              ? [
                  {'id': 'season', 'type': 'folder', 'name': 'Season 1'},
                ]
              : [
                  for (final episode in [2, 1])
                    {
                      'id': '$episode',
                      'type': 'file',
                      'name': 'Show.S01E0$episode.mkv',
                      'size': episode * 100,
                      'link': 'https://stream.test/$episode',
                    },
                  {
                    'id': 'text',
                    'type': 'file',
                    'name': 'notes.txt',
                    'size': 1000,
                  },
                ],
        };
      }
    } else {
      if (path.endsWith('/files')) {
        body = {
          'files': request.url.queryParameters['parent_id'] == 'root'
              ? [
                  {'id': 'season', 'kind': 'drive#folder', 'name': 'Season 1'},
                ]
              : [
                  for (final episode in [2, 1])
                    {
                      'id': '$episode',
                      'kind': 'drive#file',
                      'name': 'Show.S01E0$episode.mkv',
                      'size': '${episode * 100}',
                      'mime_type': 'video/x-matroska',
                    },
                  {
                    'id': 'text',
                    'kind': 'drive#file',
                    'name': 'notes.txt',
                    'size': '1000',
                  },
                ],
          'next_page_token': '',
        };
      } else {
        final id = request.url.pathSegments.last;
        body = {
          'id': id,
          'name': 'Movie.mkv',
          'phase': 'PHASE_TYPE_COMPLETE',
          'web_content_link': 'https://stream.test/$id',
        };
      }
    }
    return http.Response(jsonEncode(body), 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'provider-cloud-fixture');
    SharedPreferences.setMockInitialValues({
      'real_debrid_api_key': 'rd',
      'torbox_api_key': 'tb',
      'premiumize_api_key': 'pm',
      'alldebrid_api_key': 'ad',
      'pikpak_access_token': 'access',
      'pikpak_refresh_token': 'refresh',
      'pikpak_device_id': 'device',
      'pikpak_user_id': 'user',
      'pikpak_captcha_token': 'captcha',
    });
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  });

  for (final provider in [
    'rd',
    'torbox',
    'alldebrid',
    'premiumize',
    'pikpak',
  ]) {
    for (final series in [false, true]) {
      test(
        '$provider cloud refresh preserves ${series ? 'series' : 'movie'} selection',
        () async {
          final f = CloudFixture(provider);
          final client = MockClient(f.respond);
          addTearDown(client.close);
          final result = await http.runWithClient(
            () => const ProviderCloudSource().resolve(
              f.pin,
              PlaybackMeta(contentType: series ? 'series' : 'movie'),
              owner: ProfileSessionMemory.captureOwner(),
              canContinue: () => true,
            ),
            () => client,
          );
          expect(result, isNotNull);
          expect(result!.title, 'Saved title');
          final expected = switch (provider) {
            'rd' => 'refreshed',
            'alldebrid' => 'unlocked',
            _ => series ? '1' : '2',
          };
          expect(result.playUrl, 'https://stream.test/$expected');
          if (series && !['rd', 'alldebrid'].contains(provider)) {
            expect(result.playlist, hasLength(2));
            expect(
              result.playlist![result.startIndex].title,
              contains('S01E01'),
            );
            expect(result.playlist!.last.title, contains('S01E02'));
          } else {
            expect(result.playlist, isNull);
          }
          expect(
            f.requests.every(
              (r) =>
                  r.method == 'GET' ||
                  r.url.path.endsWith('/unrestrict/link') ||
                  r.url.path.endsWith('/link/unlock'),
            ),
            isTrue,
          );
          expect(
            f.requests.any(
              (r) =>
                  r.url.path.contains('delete') ||
                  r.url.path.contains('addMagnet'),
            ),
            isFalse,
          );
        },
      );
    }
    test(
      '$provider retirement after first response stops follow-up preparation',
      () async {
        final f = CloudFixture(provider, retireAt: 1);
        final client = MockClient(f.respond);
        addTearDown(client.close);
        final result = await http.runWithClient(
          () => const ProviderCloudSource().resolve(
            f.pin,
            const PlaybackMeta(contentType: 'series'),
            owner: ProfileSessionMemory.captureOwner(),
            canContinue: () => true,
          ),
          () => client,
        );
        expect(result, isNull);
        expect(f.requests, hasLength(1));
      },
    );
  }
  for (final provider in ['premiumize', 'pikpak']) {
    test(
      '$provider file identity bypasses recursive folder enumeration',
      () async {
        final f = CloudFixture(provider, kind: SeriesSource.cloudKindFile);
        final client = MockClient(f.respond);
        addTearDown(client.close);
        final result = await http.runWithClient(
          () => const ProviderCloudSource().resolve(
            f.pin,
            const PlaybackMeta(contentType: 'movie'),
            owner: ProfileSessionMemory.captureOwner(),
            canContinue: () => true,
          ),
          () => client,
        );
        expect(
          result!.playUrl,
          'https://stream.test/${provider == 'pikpak' ? 'root' : 'file'}',
        );
        expect(f.requests, hasLength(1));
      },
    );
  }
  test('RD refresh failure retains the freshly listed fallback URL', () async {
    final f = CloudFixture('rd', refreshFails: true);
    final client = MockClient(f.respond);
    addTearDown(client.close);
    final result = await http.runWithClient(
      () => const ProviderCloudSource().resolve(
        f.pin,
        const PlaybackMeta(contentType: 'movie'),
        owner: ProfileSessionMemory.captureOwner(),
        canContinue: () => true,
      ),
      () => client,
    );
    expect(result!.playUrl, 'https://stream.test/listed');
    expect(f.requests, hasLength(2));
  });
  for (final retired in [false, true]) {
    test(
      'RD paginated lookup stops between pages when retired=$retired',
      () async {
        final f = CloudFixture('rd');
        var pages = 0;
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/downloads')) {
            pages++;
            if (pages == 1) {
              if (retired) ProfileSessionMemory.clearAll();
              return http.Response(
                jsonEncode([
                  for (var i = 0; i < 100; i++)
                    {'id': '$i', 'filename': 'Other.mkv'},
                ]),
                200,
              );
            }
          }
          return f.respond(request);
        });
        addTearDown(client.close);
        final result = await http.runWithClient(
          () => const ProviderCloudSource().resolve(
            f.pin,
            const PlaybackMeta(contentType: 'movie'),
            owner: ProfileSessionMemory.captureOwner(),
            canContinue: () => true,
          ),
          () => client,
        );
        expect(pages, retired ? 1 : 2);
        expect(
          result?.playUrl,
          retired ? null : 'https://stream.test/refreshed',
        );
      },
    );
  }
}

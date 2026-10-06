import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/play_loader_style.dart';
import 'package:debrify/services/storage/stremio_tv_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/stremio_tv_fixture.dart';
import '../../../../support/stremio_tv_handoff.dart';

Finder get picker => find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == '_ManualSourcePickerSheet',
);

void main() {
  testWidgets('C3 (O) series P1 preserves episode title and non-null start', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      f.type = 'series';
      f.rdFails = true;
      await t.runAsync(() => StremioTvStorage.setStremioTvMaxStartPercent(-1));
      await f.mount(t);
      await f.play(t);
      expect(picker, findsOneWidget);
      f.rdFails = false;
      await f.tap(t, find.textContaining('Original.720p.mkv'));
      await f.until(t, () => f.observer.players.isNotEmpty);
      final p = f.observer.players.single;
      expectStremioTvPlayer(p, 'P1', {
        'videoUrl': 'https://video.test/original.mp4',
        'title': '${f.meta(1).name} (S1E1)',
        'startAtPercent': isA<double>(),
        'contentImdbId': f.meta(1).effectiveImdbId,
        'contentTitle': f.meta(1).name,
        'contentType': 'series',
        'contentSeason': 1,
        'contentEpisode': 1,
        'stremioSources': hasLength(2),
        'stremioCurrentSourceIndex': 1,
        'resolveStremioSource': isNotNull,
        'stremioTvChannels': hasLength(2),
        'stremioTvCurrentChannelId': f.channelId(1),
        'stremioTvGuideDataProvider': isNotNull,
        'stremioTvChannelSwitchProvider': isNotNull,
        'stremioTvNextProvider': isNotNull,
      });
      expect(p.startAtPercent, inInclusiveRange(0.0, 1.0));
    });
  });

  testWidgets('C3 (O) direct attempts continue after first invalid HEAD', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      f.streams = [
        for (final name in ['bad', 'good'])
          {
            'name': 'Direct $name',
            'title': 'Original.$name.1080p.mkv',
            'url': 'https://direct.test/$name.mp4',
            'behaviorHints': {'videoSize': 100000000},
          },
      ];
      f.onRequest = (r) async => r.method == 'HEAD'
          ? http.Response(
              '',
              r.url.path.contains('bad') ? 404 : 200,
              headers: {
                'content-length': '100000000',
                'content-type': 'video/mp4',
              },
            )
          : f.providerResponse(r);
      await f.mount(t);
      await f.play(t);
      expect(
        f.observer.players,
        hasLength(1),
        reason: 'second valid direct stream launches',
      );
      expect(
        f.observer.players.single.videoUrl,
        'https://direct.test/good.mp4',
      );
      expect(
        f.requests.where((r) => r.method == 'HEAD').map((r) => r.url.path),
        ['/bad.mp4', '/good.mp4'],
      );
      expect(f.observer.players.single.stremioCurrentSourceIndex, 1);
    });
  });

  for (final provider in ['torbox', 'premiumize', 'realdebrid']) {
    testWidgets(
      'C3 (R) $provider loader cache chip matches provider capability',
      (t) async {
        await stremioTvCase(t, (f) async {
          if (provider != 'realdebrid') {
            await t.runAsync(() => f.provider(provider));
          }
          final oldStyle = PlayLoaderStyleController.cached;
          final held = Completer<http.Response>();
          f.onRequest = (r) => r.url.path.contains('/stream/')
              ? held.future
              : f.providerResponse(r);
          try {
            await t.runAsync(() => PlayLoaderStyleController.select('classic'));
            await f.mount(t);
            f.tuner(t).onPlay(f.channel(t));
            await f.until(
              t,
              () => f.requests.any((r) => r.url.path.contains('/stream/')),
            );
            await f.settle(t);
            expect(
              find.text("Checking what's cached"),
              provider == 'realdebrid' ? findsNothing : findsOneWidget,
              reason:
                  'cache stage chip is present only for cache-check providers',
            );
            expect(
              find.text(
                provider == 'torbox'
                    ? 'TorBox'
                    : provider == 'premiumize'
                    ? 'Premiumize'
                    : 'Real-Debrid',
              ),
              findsWidgets,
            );
          } finally {
            if (!held.isCompleted) {
              held.complete(f.jsonResponse({'streams': []}));
            }
            await f.settle(t, frames: 20);
            await t.runAsync(() => PlayLoaderStyleController.select(oldStyle));
          }
        });
      },
    );
  }

  testWidgets(
    'C3 (O) series Next and switch maps retain episode and start values',
    (t) async {
      await stremioTvCase(t, (f) async {
        f.type = 'series';
        await t.runAsync(
          () => StremioTvStorage.setStremioTvMaxStartPercent(-1),
        );
        await f.mount(t);
        await f.play(t);
        final p = f.observer.players.single;
        final next = await t.runAsync(
          () => p.stremioTvNextProvider!(f.channelId(1)),
        );
        final switched = await t.runAsync(
          () => p.stremioTvChannelSwitchProvider!(f.channelId(2)),
        );
        for (final result in [next!, switched!]) {
          expect(result.keys.toSet(), {
            'channelId',
            'url',
            'title',
            'contentType',
            'contentImdbId',
            'contentSeason',
            'contentEpisode',
            'startAtPercent',
            'stremioSources',
            'stremioCurrentSourceIndex',
            'sourceResolver',
            'nowPlaying',
            'nextUp',
          });
          expect(result['contentType'], 'series');
          expect(
            result['contentSeason'],
            1,
            reason: 'series map retains resolved season',
          );
          expect(result['contentEpisode'], 1);
          expect(result['title'], endsWith('(S1E1)'));
          expect(
            result['startAtPercent'],
            isA<double>(),
            reason: 'map retains computed start progress',
          );
          expect(
            result['startAtPercent'],
            closeTo((result['nowPlaying'] as Map)['progress'] as double, 0.001),
          );
        }
        expect(next['startAtPercent'], 0.0);
        expect(switched['channelId'], f.channelId(2));
      });
    },
  );

  testWidgets(
    'C3 (O) captured direct resolver returns the supplied direct URL',
    (t) async {
      await stremioTvCase(t, (f) async {
        f.streams.insert(0, {
          'name': 'Direct fixture',
          'title': 'Original.Direct.1080p.mkv',
          'url': 'https://direct.test/original.mp4',
          'behaviorHints': {'videoSize': 100000000},
        });
        await f.mount(t);
        await f.play(t);
        final p = f.observer.players.single;
        final direct = p.stremioSources!.singleWhere((s) => s.isDirectStream);
        f.requests.clear();
        expect(
          await t.runAsync(() => p.resolveStremioSource!(direct)),
          direct.directUrl,
          reason: 'direct source resolver returns its original direct URL',
        );
        expect(f.requests, isEmpty);
      });
    },
  );

  testWidgets('C3 (O) RD movie unrestricts the larger selected video file', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      f.onRequest = (r) async => r.url.path.contains('/torrents/info/')
          ? f.jsonResponse({
              'id': r.url.pathSegments.last,
              'status': 'downloaded',
              'filename': 'Original.mkv',
              'files': [
                {
                  'id': 1,
                  'path': '/Small.mkv',
                  'bytes': 10000000,
                  'selected': 1,
                },
                {
                  'id': 2,
                  'path': '/Large.mkv',
                  'bytes': 100000000,
                  'selected': 1,
                },
              ],
              'links': [
                'https://restricted.test/small',
                'https://restricted.test/large',
              ],
              'bytes': 110000000,
            })
          : f.providerResponse(r);
      await f.mount(t);
      await f.play(t);
      expect(f.observer.players, hasLength(1));
      final request = f.requests.lastWhere(
        (r) => r.url.path.endsWith('/unrestrict/link'),
      );
      expect(
        Uri.splitQueryString(request.body)['link'],
        'https://restricted.test/large',
        reason: 'largest selected movie file is unrestricted',
      );
    });
  });

  testWidgets(
    'C3 (O) PikPak mismatched episode trashes prepared root before retry',
    (t) async {
      await stremioTvCase(t, (f) async {
        f.type = 'series';
        await t.runAsync(() => f.provider('pikpak'));
        var adds = 0;
        f.onRequest = (r) async {
          if (r.url.host.contains('mypikpak')) {
            if (r.method == 'POST' &&
                r.url.path.endsWith('/files') &&
                r.body.contains('magnet:')) {
              adds++;
            }
            if (r.url.path.endsWith('/files/original-folder')) {
              return f.jsonResponse({
                'id': 'original-folder',
                'name': 'debrify-tv',
                'kind': 'drive#folder',
                'parent_id': '',
              });
            }
            if (r.url.path.endsWith('/files/original-video')) {
              return f.jsonResponse({
                'id': 'original-video',
                'kind': 'drive#file',
                'name': adds == 1
                    ? 'Original.S01E02.mkv'
                    : 'Original.S01E01.mkv',
                'phase': 'PHASE_TYPE_COMPLETE',
                'web_content_link': 'https://streams.test/original.mp4',
              });
            }
            if (r.url.path.endsWith('/files:batchTrash')) {
              return f.jsonResponse({});
            }
          }
          return f.providerResponse(r);
        };
        await f.mount(t);
        await f.play(t);
        expect(f.observer.players, hasLength(1));
        final trash = f.requests.where(
          (r) => r.url.path.endsWith('/files:batchTrash'),
        );
        expect(
          trash,
          hasLength(1),
          reason:
              'rejected PikPak episode issues exactly one root trash request',
        );
        expect(jsonDecode(trash.single.body), {
          'ids': ['original-video'],
        });
        expect(
          f.requests
              .where(
                (r) => r.method == 'POST' && r.url.host.contains('mypikpak'),
              )
              .map((r) => r.url.path),
          ['/drive/v1/files', '/drive/v1/files:batchTrash', '/drive/v1/files'],
          reason: 'prepared root is trashed before the next source is added',
        );
      });
    },
  );

  testWidgets(
    'C3 (O) AllDebrid mismatched series file is deleted before retry',
    (t) async {
      await stremioTvCase(t, (f) async {
        f.type = 'series';
        await t.runAsync(() => f.provider('alldebrid'));
        f.onRequest = (r) async => r.url.path.endsWith('/magnet/files')
            ? f.jsonResponse({
                'status': 'success',
                'data': {
                  'magnets': [
                    {
                      'files': [
                        {
                          'n': f.allDebridAdds == 1
                              ? 'Original.S01E02.mkv'
                              : 'Original.S01E01.mkv',
                          's': 100000000,
                          'l': 'https://locked.test/original',
                        },
                      ],
                    },
                  ],
                },
              })
            : f.providerResponse(r);
        await f.mount(t);
        await f.play(t);
        expect(f.observer.players, hasLength(1));
        expect(
          f.requests
              .where((r) => r.url.host.contains('alldebrid'))
              .map((r) => r.url.path),
          [
            '/v4/magnet/upload',
            '/v4/magnet/files',
            '/v4/magnet/delete',
            '/v4/magnet/upload',
            '/v4/magnet/files',
            '/v4/link/unlock',
          ],
          reason:
              'mismatched episode is deleted before another source is tried',
        );
      });
    },
  );
}

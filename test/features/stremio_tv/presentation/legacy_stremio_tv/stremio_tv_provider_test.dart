import 'dart:async';

import 'package:debrify/features/home/presentation/home_hero_shell_bridge.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/stremio_tv_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/stremio_tv_fixture.dart';
import '../../../../support/stremio_tv_handoff.dart';

Finder get picker => find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == '_ManualSourcePickerSheet',
);
Finder get pickerItems => find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == '_SourcePickerItem',
);

void main() {
  for (final provider in ['torbox', 'premiumize', 'alldebrid', 'pikpak']) {
    testWidgets('C3 (O) $provider production resolver transport and cleanup', (
      t,
    ) async {
      await stremioTvCase(t, (f) async {
        await t.runAsync(() => f.provider(provider));
        if (provider == 'torbox') {
          f.onRequest = (r) async {
            f.torboxReject = f.torboxCreates == 71;
            return f.providerResponse(r);
          };
        }
        if (provider == 'alldebrid') {
          f.allDebridRejects = 1;
        }
        await f.mount(t);
        await f.play(t);
        expect(f.observer.players, hasLength(1));
        final paths = f.requests.map((r) => r.url.path).toList();
        if (provider == 'torbox') {
          expect(paths.where((p) => p.contains('/torrents/')), [
            '/v1/api/torrents/checkcached',
            '/v1/api/torrents/createtorrent',
            '/v1/api/torrents/mylist',
            '/v1/api/torrents/controltorrent',
            '/v1/api/torrents/createtorrent',
            '/v1/api/torrents/mylist',
            '/v1/api/torrents/requestdl',
          ]);
        } else if (provider == 'premiumize') {
          expect(
            paths,
            containsAllInOrder(['/api/cache/check', '/api/transfer/directdl']),
          );
        } else if (provider == 'alldebrid') {
          expect(
            paths,
            containsAllInOrder([
              '/v4/magnet/upload',
              '/v4/magnet/delete',
              '/v4/magnet/upload',
              '/v4/magnet/files',
              '/v4/link/unlock',
            ]),
          );
        } else {
          expect(
            paths,
            containsAllInOrder([
              '/drive/v1/files',
              '/drive/v1/tasks/original-task',
              '/drive/v1/files/original-video',
            ]),
          );
        }
      });
    });
  }

  testWidgets(
    'C3 (O) Auto skips RD blocked source then follows provider ladder',
    (t) async {
      await stremioTvCase(t, (f) async {
        f.streams = [
          {
            'name': 'Fixture',
            'title': 'Original.WEB-DL.1080p.mkv',
            'infoHash': 'a' * 40,
          },
        ];
        await t.runAsync(() async {
          await f.provider('torbox');
          await f.provider('premiumize');
          await f.provider('alldebrid');
          await RealDebridStorage.setRdSkipBlockedTorrents(true);
          await StremioTvStorage.setStremioTvDebridProvider('auto');
        });
        f.torboxReject = true;
        await f.mount(t);
        await f.play(t);
        expect(
          f.requests.any((r) => r.url.host.contains('real-debrid')),
          isFalse,
        );
        final paths = f.requests.map((r) => r.url.path).toList();
        expect(
          paths,
          containsAllInOrder([
            '/v1/api/torrents/checkcached',
            '/v1/api/torrents/createtorrent',
            '/v1/api/torrents/mylist',
            '/v1/api/torrents/controltorrent',
            '/api/transfer/directdl',
          ]),
        );
        expect(f.observer.players, hasLength(1));
      });
    },
  );

  testWidgets(
    'C3 (O) Cancel during held TorBox cache completes only that request',
    (t) async {
      await stremioTvCase(t, (f) async {
        await t.runAsync(() => f.provider('torbox'));
        final held = Completer<http.Response>();
        f.onRequest = (r) => r.url.path.endsWith('/checkcached')
            ? held.future
            : f.providerResponse(r);
        await f.mount(t);
        f.tuner(t).onPlay(f.channel(t));
        await f.until(
          t,
          () => f.requests.any((r) => r.url.path.endsWith('/checkcached')),
        );
        await f.tap(t, find.text('Cancel'));
        held.complete(
          f.jsonResponse({
            'success': true,
            'data': [
              {'hash': 'a' * 40},
            ],
          }),
        );
        await f.settle(t, frames: 30);
        expect(
          f.requests.any((r) => r.url.path.endsWith('/createtorrent')),
          isFalse,
        );
        expect(f.observer.players, isEmpty);
      });
    },
  );

  testWidgets(
    'C3/C8 (R/O) P1 failed pick remains open then chosen source passes full ledger',
    (t) async {
      await stremioTvCase(t, (f) async {
        f.rdFails = true;
        f.headValid = false;
        f.streams.insert(0, {
          'name': 'Direct fixture',
          'title': 'Original.Direct.1080p.mkv',
          'url': 'https://direct.test/original.mp4',
          'behaviorHints': {'videoSize': 100000000},
        });
        HomeHeroShellBridge.playSavedStremioChannel(f.channelId(1));
        await f.mount(t);
        await f.until(t, () => picker.evaluate().isNotEmpty, frames: 400);
        expect(find.text('All (3)'), findsOneWidget);
        expect(find.text('Direct (1)'), findsOneWidget);
        expect(find.text('Torrent (2)'), findsOneWidget);
        expect(f.probes.where((p) => p == 'hide overlay'), hasLength(1));
        await f.settle(t);
        final itemFocus = t
            .widget<Focus>(
              find
                  .descendant(
                    of: pickerItems.first,
                    matching: find.byType(Focus),
                  )
                  .first,
            )
            .focusNode;
        expect(FocusManager.instance.primaryFocus, same(itemFocus));
        await f.key(t, LogicalKeyboardKey.arrowUp);
        final firstTab = find
            .byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_SourcePickerTab',
            )
            .first;
        final tabFocus = t
            .widget<Focus>(
              find.descendant(of: firstTab, matching: find.byType(Focus)).first,
            )
            .focusNode;
        expect(FocusManager.instance.primaryFocus, same(tabFocus));
        await f.tap(t, find.text('Direct (1)'));
        await f.tap(t, pickerItems.first);
        await f.until(
          t,
          () => find.byIcon(Icons.error_outline).evaluate().isNotEmpty,
        );
        expect(picker, findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        f.rdFails = false;
        await f.tap(t, find.text('All (3)'));
        await f.tap(t, find.textContaining('Original.720p.mkv'));
        await f.until(t, () => f.observer.players.isNotEmpty);
        final p = f.observer.players.single;
        expect(p.stremioCurrentSourceIndex, 1);
        expectStremioTvPlayer(p, 'P1', {
          'videoUrl': 'https://video.test/original.mp4',
          'title': f.meta(1).name,
          'startAtPercent': null,
          'contentImdbId': f.meta(1).effectiveImdbId,
          'contentTitle': f.meta(1).name,
          'contentType': 'movie',
          'contentSeason': null,
          'contentEpisode': null,
          'stremioSources': hasLength(3),
          'stremioCurrentSourceIndex': 1,
          'resolveStremioSource': isNotNull,
          'stremioTvChannels': hasLength(2),
          'stremioTvCurrentChannelId': f.channelId(1),
          'stremioTvGuideDataProvider': isNotNull,
          'stremioTvChannelSwitchProvider': isNotNull,
          'stremioTvNextProvider': isNotNull,
        });
      });
    },
  );

  testWidgets(
    'C3/C9 (O) episode mismatch and 480p filter quality order and title',
    (t) async {
      await stremioTvCase(t, (f) async {
        f.type = 'series';
        f.streams = [
          {
            'name': 'Fixture',
            'title': 'Original.S01E02.2160p.mkv',
            'infoHash': 'c' * 40,
          },
          {
            'name': 'Fixture',
            'title': 'Original.S01E01.480p.mkv',
            'infoHash': 'd' * 40,
          },
          {
            'name': 'Fixture',
            'title': 'Original.S01E01.1080p.mkv',
            'infoHash': 'a' * 40,
          },
          {
            'name': 'Fixture',
            'title': 'Original.S01E01.720p.mkv',
            'infoHash': 'b' * 40,
          },
        ];
        await t.runAsync(
          () => StremioTvStorage.setStremioTvPreferredQuality('720p'),
        );
        await t.runAsync(() async {
          await StremioTvStorage.setStremioTvRandomEpisodes(true);
          await StremioTvStorage.setStremioTvSeriesRotationMinutes(60);
        });
        await f.mount(t);
        expect(f.tuner(t).rotationFor(f.channel(t)), 60);
        await f.play(t);
        final p = f.observer.players.single;
        expect(p.contentSeason, 1);
        expect(p.contentEpisode, 1);
        expect(p.title, '${f.meta(1).name} (S1E1)');
        expect(p.stremioSources!.map((s) => s.infohash), ['a' * 40, 'b' * 40]);
        expect(p.stremioCurrentSourceIndex, 1);
        expect(
          f.requests.firstWhere((r) => r.url.path.endsWith('/addMagnet')).body,
          contains('b' * 40),
        );
        expect(
          f.requests.any(
            (r) => r.url.pathSegments.last == '${f.meta(1).id}:1:1.json',
          ),
          isTrue,
        );
      });
    },
  );

  testWidgets('C9 (O) direct-first preference reaches HEAD before debrid', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      f.streams.insert(0, {
        'name': 'Direct fixture',
        'title': 'Original.Direct.1080p.mkv',
        'url': 'https://direct.test/original.mp4',
        'behaviorHints': {'videoSize': 100000000},
      });
      await t.runAsync(() => StremioTvStorage.setStremioTvTorrentsFirst(false));
      await f.mount(t);
      await f.play(t);
      expect(
        f.observer.players.single.videoUrl,
        'https://direct.test/original.mp4',
      );
      expect(f.requests.any((r) => r.method == 'HEAD'), isTrue);
      expect(
        f.requests.any((r) => r.url.host.contains('real-debrid')),
        isFalse,
      );
    });
  });
  testWidgets('C8 (R/O) picker Escape pops without a player push', (t) async {
    await stremioTvCase(t, (f) async {
      f.rdFails = true;
      await f.mount(t);
      await f.play(t);
      expect(picker, findsOneWidget);
      await f.key(t, LogicalKeyboardKey.escape);
      expect(picker, findsNothing);
      expect(f.observer.players, isEmpty);
    });
  });
}

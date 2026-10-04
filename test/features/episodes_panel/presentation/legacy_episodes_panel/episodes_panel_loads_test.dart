import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/episodes_panel_fixture.dart';

Future<void> localPlayback(
  EpisodesPanelFixture f,
  Map<String, double> progress,
) async {
  final prefs = await ProfilePreferences.instance();
  await prefs.setString(
    'playback_state_v1',
    jsonEncode({
      'series_original_episodes': {
        'type': 'series',
        'imdbId': f.id,
        'seasons': {
          for (final season in [1, 2])
            '$season': {
              for (final entry in progress.entries)
                if (entry.key.startsWith('$season-'))
                  entry.key.split('-').last: {
                    'positionMs': entry.value.toInt(),
                    'durationMs': 100,
                    'updatedAt': 1000,
                  },
            },
        },
      },
    }),
  );
}

void main() {
  final landings = [
    (
      name: 'explicit pair wins',
      season: 2,
      episode: 2,
      next: true,
      local: true,
      expected: '2-2',
    ),
    (
      name: 'tracker before local',
      season: null,
      episode: null,
      next: true,
      local: true,
      expected: '2-1',
    ),
    (
      name: 'local fallback',
      season: null,
      episode: null,
      next: false,
      local: true,
      expected: '1-2',
    ),
    (
      name: 'first fallback',
      season: null,
      episode: null,
      next: false,
      local: false,
      expected: '1-1',
    ),
    (
      name: 'missing season never imports episode',
      season: 9,
      episode: 2,
      next: false,
      local: false,
      expected: '1-1',
    ),
    (
      name: 'season only never mixes tracker episode',
      season: 1,
      episode: null,
      next: true,
      local: true,
      expected: '1-1',
    ),
    (
      name: 'episode only never mixes tracker season',
      season: null,
      episode: 2,
      next: true,
      local: true,
      expected: '1-2',
    ),
  ];
  for (var index = 0; index < landings.length; index++) {
    final c = landings[index];
    testWidgets('landing ${c.name}', (t) async {
      await episodesPanelCase(t, 'landing-$index', 100 + index, (f) async {
        f.initialSeason = c.season;
        f.initialEpisode = c.episode;
        if (c.next) f.trackerNext = (season: 2, episode: 1);
        await t.runAsync(() async {
          if (c.next) await f.authenticate({TrackingSource.trakt});
          if (c.local) await localPlayback(f, {'1-2': 30});
        });
        await f.mount(t);
        final landing = f.view.landing!;
        expect('${landing.season}-${landing.number}', c.expected);
        expect(f.view.selectedSeasonNumber, landing.season);
        expect(
          f.requests
              .where((r) => r.url.host == 'api.tvmaze.com')
              .map((r) => r.url.path),
          ['/shows/1', '/lookup/shows'],
        );
      });
    });
  }
  for (final progress in [0.0, 94.9, 95.0, 100.0]) {
    testWidgets('direct landing threshold $progress', (t) async {
      await episodesPanelCase(t, 'direct-$progress', 120 + progress.toInt(), (
        f,
      ) async {
        f.direct = true;
        f.progress = {'1-2': progress};
        await f.mount(t);
        expect(
          (f.view.landing!.season, f.view.landing!.number),
          progress == 0
              ? (1, 1)
              : progress < 95
              ? (1, 2)
              : (2, 1),
        );
        expect(f.requests.map(f.requestIdentity), [
          'GET episodes-original.invalid/meta/series/${f.id}.json',
        ]);
      });
    });
  }
  final sources = [
    WatchProgressSource.smart,
    WatchProgressSource.local,
    WatchProgressSource.trakt,
    WatchProgressSource.simkl,
    WatchProgressSource.mdblist,
  ];
  for (var index = 0; index < sources.length; index++) {
    final source = sources[index];
    testWidgets(
      'progress policy ${source.name} preserves floors and completion',
      (t) async {
        await episodesPanelCase(t, 'policy-${source.name}', 230 + index, (
          f,
        ) async {
          await t.runAsync(() async {
            await f.authenticate({
              TrackingSource.trakt,
              TrackingSource.simkl,
              TrackingSource.mdblist,
            });
            await TrackingSourceStorage.setWatchProgressSource(source);
            await localPlayback(f, {'1-1': 100, '1-2': 20});
          });
          f.traktPlayback = {'1-1': 40, '1-2': 30, '2-1': 5, '2-2': 6};
          f.simklPlayback = {'1-1': 50, '1-2': 35, '2-1': 5, '2-2': 7};
          f.mdblistPlayback = {'1-1': 4, '1-2': 2, '2-1': 3, '2-2': 8};
          await f.mount(t);
          final expected = switch (source) {
            WatchProgressSource.smart => [100.0, 35.0, 3.0, 8.0],
            WatchProgressSource.local => [100.0, 20.0, null, null],
            WatchProgressSource.trakt => [40.0, 30.0, null, 6.0],
            WatchProgressSource.simkl => [50.0, 35.0, null, 7.0],
            WatchProgressSource.mdblist => [4.0, 2.0, 3.0, 8.0],
          };
          expect([
            for (final season in f.view.seasons)
              for (final episode in season.episodes) f.view.progressOf(episode),
          ], expected);
          final hosts = f.requests
              .where((r) => r.url.path.contains('/sync/playback'))
              .map((r) => r.url.host)
              .toSet();
          expect(hosts, switch (source) {
            WatchProgressSource.smart => {
              'api.trakt.tv',
              'api.simkl.com',
              'api.mdblist.com',
            },
            WatchProgressSource.local => <String>{},
            WatchProgressSource.trakt => {'api.trakt.tv'},
            WatchProgressSource.simkl => {'api.simkl.com'},
            WatchProgressSource.mdblist => {'api.mdblist.com'},
          });
        });
      },
    );
  }
  testWidgets(
    'grouping keeps specials last, numeric values, metadata and thumbnail size',
    (t) async {
      await episodesPanelCase(t, 'grouping', 240, (f) async {
        f.videosOverride = [
          {'season': 0, 'episode': 2, 'title': 'Special'},
          {
            'season': 2.0,
            'number': 3.0,
            'name': 'Named',
            'rating': '8.1',
            'thumbnail': 'https://episodes.metahub.space/test/w780.jpg',
          },
          {
            'season': 1,
            'episode': 2,
            'title': 'Second',
            'thumbnail': 'https://unchanged.invalid/w780.jpg',
          },
          {'season': 1, 'episode': 1, 'title': 'First'},
          {'season': -1, 'episode': 1, 'title': 'Invalid season'},
          {'season': 1, 'title': 'Missing number'},
        ];
        await f.mount(t);
        expect(f.view.seasons.map((s) => s.number), [1, 2, 0]);
        expect(f.view.seasons.map((s) => s.episodeCount), [2, 1, 1]);
        expect(f.view.seasons.first.episodes.map((e) => e.number), [1, 2]);
        final named = f.view.seasons[1].episodes.single;
        expect(
          (named.title, named.rating, named.thumbnailUrl),
          ('Named', 8.1, 'https://episodes.metahub.space/test/w300.jpg'),
        );
        expect(
          f.view.seasons.first.episodes.last.thumbnailUrl,
          'https://unchanged.invalid/w780.jpg',
        );
      });
    },
  );
  testWidgets(
    'scope StateError shows original snackbar without starting seasons',
    (t) async {
      await episodesPanelCase(t, 'scope-error', 241, (f) async {
        f.failMeta = true;
        f.scopeError = true;
        await f.mount(t, wait: false);
        await f.until(
          t,
          () => find
              .text('Could not verify series episodes. Please retry.')
              .evaluate()
              .isNotEmpty,
        );
        expect(f.requests.where((r) => r.url.host == 'api.trakt.tv'), isEmpty);
        expect(f.view.seasons, isEmpty);
      });
    },
  );
  testWidgets(
    'newer retry rejects stale seasons and keeps current generation',
    (t) async {
      await episodesPanelCase(t, 'stale-retry', 242, (f) async {
        f.direct = true;
        var loads = 0;
        // Keep the typed result while holding only the first original request.
        final stale = Completer<void>();
        f.injectedSeasons = () async {
          final request = ++loads;
          if (request == 1) await stale.future;
          return request == 1 ? [] : f.directSeasons;
        };
        await f.mount(t, wait: false);
        await f.until(t, () => loads == 1);
        f.view.onRetry();
        await f.finish(t);
        final generation = f.view.generation;
        stale.complete();
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(loads, 2);
        expect(f.view.generation, generation);
        expect(f.view.episodes.map((e) => e.title), ['Pilot', 'Second']);
        expect(f.view.unavailable, isFalse);
      });
    },
  );
}

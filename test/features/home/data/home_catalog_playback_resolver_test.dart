import 'dart:async';
import 'package:debrify/models/mdblist_continue_watching.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';

import 'package:debrify/features/home/data/home_catalog_playback_readers.dart';
import 'package:debrify/features/home/data/home_catalog_playback_resolver.dart';
import 'package:debrify/features/home/data/home_series_resume_resolver.dart';
import 'package:debrify/features/home/models/home_series_resume_result.dart';
import 'package:debrify/features/home/models/home_series_resume_signals.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/trakt_continue_watching_item.dart';
import 'package:debrify/services/native_series_metadata_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

import 'home_series_resume_repository_test.dart' as signals;
import 'home_tracker_resume_repository_test.dart' as trackers;

class Series extends Fake implements HomeSeriesResumeResolver {
  int calls = 0;
  HomeSeriesResumeResult? answer = (
    started: false,
    season: 1,
    episode: 1,
    simklProgress: null,
    selection: null,
    sourcePrio: null,
  );
  @override
  Future<HomeSeriesResumeResult?> resolve(
    StremioMeta item, {
    required HomeResumeAvailability Function() availability,
    required TraktContinueWatchingItem? Function() cachedTrakt,
    required bool Function() isCurrent,
    bool isTraktSource = false,
    bool preferBuiltIn = false,
    StremioMeta? catalogItem,
  }) async {
    calls++;
    return answer;
  }
}

class Readers extends Fake implements HomeCatalogPlaybackReaders {
  Map<String, dynamic>? byId, byTitle;
  final calls = <String>[];
  Completer<void>? gate;
  final entered = Completer<void>();
  ({int season, int episode})? next;
  @override
  Future<Map<String, dynamic>?> localById(
    String id, {
    required bool Function() isCurrent,
  }) async {
    calls.add('id:$id');
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    return byId;
  }

  @override
  Future<Map<String, dynamic>?> localByTitle(
    String title, {
    required bool Function() isCurrent,
  }) async {
    calls.add('title:$title');
    return byTitle;
  }

  @override
  Future<void> prepareMovieRewatch(
    StremioMeta item,
    String id, {
    required bool Function() isCurrent,
  }) async {
    calls.add('rewatch:$id');
  }

  @override
  Future<({int season, int episode})?> nextEpisode(
    StremioMeta item,
    StremioAddon addon,
    String id,
    int season,
    int episode, {
    required bool Function() isCurrent,
  }) async {
    calls.add('next:$id:$season:$episode');
    return next;
  }
}

class Fixture {
  final series = Series(), readers = Readers();
  final signal = signals.Fixture();
  final tracker = trackers.Fixture();
  bool current = true;
  HomeResumeAvailability available = (
    trakt: false,
    simkl: false,
    mdblist: false,
  );
  WatchProgressSource progress = WatchProgressSource.smart;
  Set<TrackingSource> scrobble = {};
  late final resolver = HomeCatalogPlaybackResolver(
    seriesResume: series,
    signals: signal.repository,
    trackers: tracker.repository,
    readers: readers,
    log: (_) {},
  );
  Future<HomeCatalogPlaybackTarget?> read({
    StremioMeta item = signals.show,
    bool rewatch = false,
    bool prefer = false,
    bool trakt = false,
    bool mdblist = false,
    bool skip = false,
    ({bool started, int season, int episode})? promised,
  }) => resolver.resolve(
    item,
    NativeSeriesMetadataService.addon,
    trackingPolicy: TrackingSourcePolicy(
      scrobbleTargets: scrobble,
      progressSource: progress,
      homeTickSources: {},
    ),
    availability: () => available,
    cachedTrakt: () => signals.card(),
    isCurrent: () => current,
    startFromBeginning: rewatch,
    preferTraktResume: prefer,
    isTraktSource: trakt,
    isMdblistSource: mdblist,
    skipEpisodeFallback: skip,
    promisedTarget: promised,
  );
}

const movie = StremioMeta(id: 'tt123', type: 'movie', name: 'Movie');

void main() {
  test(
    'MDBList owned selection bypasses reconciliation when no promise conflicts',
    () async {
      final f = Fixture();
      final owned = trackers.candidate('tt123', 40, series: true);
      f.tracker.mdb = () async => MdblistResult.success(
        MdblistContinueWatchingSnapshot(shows: [owned]),
      );
      final result = await f.read(mdblist: true, prefer: true);
      expect(result!.selection, same(owned.selection));
      expect(f.series.calls, 0);
      expect(f.readers.calls, isEmpty);
    },
  );

  test(
    'movie tracker reads start concurrently and keep provider percentages',
    () async {
      final f = Fixture();
      f.available = (trakt: true, simkl: true, mdblist: true);
      final trakt = Completer<double?>(), simkl = Completer<double?>();
      f.tracker.trakt = () => trakt.future;
      f.tracker.simkl = () => simkl.future;
      final pending = f.read(item: movie, prefer: true);
      await Future<void>.delayed(Duration.zero);
      expect(f.tracker.calls, ['trakt:tt123', 'simkl:tt123', 'mdb']);
      trakt.complete(44);
      simkl.complete(55);
      final selection = (await pending)!.selection!;
      expect(selection.traktProgressPercent, 44);
      expect(selection.simklProgressPercent, 55);
    },
  );

  test(
    'rewatch bypasses every reader and clears all percentages for movies and series',
    () async {
      for (final item in [movie, signals.show]) {
        final f = Fixture();
        final result = (await f.read(
          item: item,
          rewatch: true,
          prefer: true,
          trakt: true,
        ))!.selection!;
        expect(result.season, item.type == 'series' ? 1 : null);
        expect(result.episode, item.type == 'series' ? 1 : null);
        expect(
          [
            result.traktProgressPercent,
            result.simklProgressPercent,
            result.mdblistProgressPercent,
          ],
          [0, 0, 0],
        );
        expect(f.series.calls, 0);
        expect(f.signal.calls, isEmpty);
        expect(f.tracker.calls, isEmpty);
        expect(f.readers.calls, isEmpty);
      }
    },
  );

  test(
    'reconciled selection is retained by identity without a conflicting promise',
    () async {
      final f = Fixture();
      f.series.answer = (
        started: true,
        season: 2,
        episode: 3,
        simklProgress: null,
        selection: signals.selected,
        sourcePrio: 0,
      );
      expect((await f.read(prefer: true))!.selection, same(signals.selected));
    },
  );

  test(
    'promised episode wins and drops the previous episode percentage',
    () async {
      final f = Fixture();
      f.series.answer = (
        started: true,
        season: 2,
        episode: 3,
        simklProgress: 70,
        selection: signals.selected,
        sourcePrio: 1,
      );
      final selection = (await f.read(
        prefer: true,
        promised: (started: true, season: 4, episode: 5),
      ))!.selection!;
      expect((selection.season, selection.episode), (4, 5));
      expect(selection.simklSource, isTrue);
      expect(selection.simklProgressPercent, isNull);
      expect(f.readers.calls, isEmpty);
    },
  );

  test('matching S1E1 promise still counts as started evidence', () async {
    final f = Fixture();
    final selection = (await f.read(
      prefer: true,
      promised: (started: true, season: 1, episode: 1),
    ))!.selection!;
    expect((selection.season, selection.episode), (1, 1));
    expect(f.readers.calls, isEmpty);
  });

  test('cancelled reconciliation never becomes an S1E1 launch', () async {
    final f = Fixture();
    f.series.answer = null;
    expect(await f.read(prefer: true), isNull);
    expect(f.readers.calls, isEmpty);
  });

  test(
    'local tail fills only missing coordinates and retains ID finished marker',
    () async {
      final f = Fixture();
      f.readers.byId = {'season': 2, 'finished': true};
      f.readers.byTitle = {'season': 9, 'episode': 4};
      f.readers.next = (season: 2, episode: 5);
      final selection = (await f.read())!.selection!;
      expect((selection.season, selection.episode), (2, 5));
      expect(f.readers.calls, [
        'id:tt123',
        'title:Exact Title',
        'next:tt123:2:4',
      ]);
    },
  );

  test(
    'unresolved raw series opens episodes unless caller owns an inline guide',
    () async {
      const raw = StremioMeta(id: 'addon:raw', type: 'series', name: 'Raw');
      final f = Fixture();
      expect((await f.read(item: raw))!.openEpisodes, isTrue);
      expect(f.readers.calls, isEmpty);
      expect((await f.read(item: raw, skip: true))!.selection!.episode, 1);
    },
  );

  test(
    'native series does not use title fallback or manual episode screen',
    () async {
      final f = Fixture();
      final target = await f.read(
        item: const StremioMeta(id: 'tmdb:123', type: 'series', name: 'Native'),
      );
      expect(target!.openEpisodes, isFalse);
      expect(target.selection!.episode, 1);
      expect(f.readers.calls, ['id:tmdb:123']);
    },
  );

  test(
    'retirement during local read suppresses later reads and launch',
    () async {
      final f = Fixture();
      f.readers.gate = Completer<void>();
      final pending = f.read();
      await f.readers.entered.future;
      f.current = false;
      f.readers.gate!.complete();
      expect(await pending, isNull);
      expect(f.readers.calls, ['id:tt123']);
    },
  );

  test(
    'row movie play keeps local-only payload without tracker requests',
    () async {
      final f = Fixture();
      f.available = (trakt: true, simkl: true, mdblist: true);
      final selection = (await f.read(item: movie))!.selection!;
      expect(selection.traktProgressPercent, isNull);
      expect(f.tracker.calls, isEmpty);
      expect(f.readers.calls, isEmpty);
    },
  );

  test(
    'Simkl rewatch preparation follows scrobble policy independently of progress',
    () async {
      for (final enabled in [true, false]) {
        final f = Fixture()..progress = WatchProgressSource.local;
        f.available = (trakt: false, simkl: true, mdblist: false);
        if (enabled) f.scrobble = {TrackingSource.simkl};
        await f.read(item: movie, prefer: true);
        expect(f.readers.calls, enabled ? ['rewatch:tt123'] : isEmpty);
        expect(f.tracker.calls, isEmpty);
      }
    },
  );

  test(
    'degraded movie tracker times out at four seconds without delaying launch further',
    () {
      fakeAsync((clock) {
        final f = Fixture();
        f.available = (trakt: true, simkl: false, mdblist: false);
        f.tracker.trakt = () => Completer<double?>().future;
        HomeCatalogPlaybackTarget? result;
        f.read(item: movie, prefer: true).then((value) => result = value);
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 3999));
        expect(result, isNull);
        clock.elapse(const Duration(milliseconds: 1));
        clock.flushMicrotasks();
        expect(result!.selection!.traktProgressPercent, isNull);
      });
    },
  );
}

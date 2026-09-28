import 'dart:async';

import 'package:debrify/features/home/models/home_series_resume_signals.dart';
import 'package:debrify/models/mdblist_continue_watching.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/native_series_metadata_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_catalog_playback_resolver_test.dart';
import 'home_series_resume_repository_test.dart' as signals;
import 'home_tracker_resume_repository_test.dart' as trackers;

Future<HomeResumePosition> label(
  Fixture f, {
  StremioMeta item = movie,
  bool trakt = false,
  bool mdblist = false,
}) => f.resolver.label(
  item,
  NativeSeriesMetadataService.addon,
  trackingPolicy: TrackingSourcePolicy(
    scrobbleTargets: {},
    progressSource: f.progress,
    homeTickSources: {},
  ),
  availability: () => f.available,
  cachedTrakt: () => signals.card(),
  isCurrent: () => f.current,
  isTraktSource: trakt,
  isMdblistSource: mdblist,
);

void main() {
  test('series label uses the shared reconciled episode', () async {
    final f = Fixture();
    f.series.answer = (
      started: true,
      season: 3,
      episode: 4,
      simklProgress: null,
      selection: null,
      sourcePrio: 1,
    );
    expect(await label(f, item: signals.show), (
      started: true,
      season: 3,
      episode: 4,
    ));
    expect(f.series.calls, 1);
    expect(f.readers.calls, isEmpty);
  });
  test('MDBList source retains its exact fast-path coordinates', () async {
    final f = Fixture();
    final owned = trackers.candidate('tt123', 40, series: true);
    f.tracker.mdb = () async =>
        MdblistResult.success(MdblistContinueWatchingSnapshot(shows: [owned]));
    final result = await label(f, item: signals.show, mdblist: true);
    expect(result, (
      started: true,
      season: owned.selection.season,
      episode: owned.selection.episode,
    ));
    expect(f.series.calls, 0);
    expect(f.readers.calls, isEmpty);
  });
  test(
    'Trakt movie source preserves cached nullable position contract',
    () async {
      final f = Fixture();
      final result = await label(f, trakt: true);
      expect(result, (
        started: true,
        season: signals.selected.season,
        episode: signals.selected.episode,
      ));
      expect(f.signal.calls, ['select']);
      expect(f.readers.calls, isEmpty);
    },
  );
  for (final winner in ['local', 'trakt', 'simkl', 'mdblist', 'none']) {
    test('movie label stops at first usable $winner position', () async {
      final f = Fixture();
      f.available = (trakt: true, simkl: true, mdblist: true);
      f.readers.movie = winner == 'local';
      f.tracker.trakt = () async => winner == 'trakt' ? 40 : null;
      f.tracker.simkl = () async => winner == 'simkl' ? 40 : null;
      f.tracker.mdb = () async => MdblistResult.success(
        MdblistContinueWatchingSnapshot(
          movies: winner == 'mdblist' ? [trackers.candidate('tt123', 40)] : [],
        ),
      );
      expect(await label(f), (
        started: winner != 'none',
        season: null,
        episode: null,
      ));
      expect(f.readers.calls, ['movie:tt123']);
      expect(f.tracker.calls, switch (winner) {
        'local' => [],
        'trakt' => ['trakt:tt123'],
        'simkl' => ['trakt:tt123', 'simkl:tt123'],
        _ => ['trakt:tt123', 'simkl:tt123', 'mdb'],
      });
    });
  }
  test(
    'disconnected trackers are not queried by an ordinary movie label',
    () async {
      final f = Fixture();
      expect((await label(f)).started, isFalse);
      expect(f.tracker.calls, isEmpty);
    },
  );
  test('local-only policy does not query connected trackers', () async {
    final f = Fixture();
    f.progress = WatchProgressSource.local;
    f.available = (trakt: true, simkl: true, mdblist: true);
    expect((await label(f)).started, isFalse);
    expect(f.tracker.calls, isEmpty);
  });
  test(
    'retired local read cannot publish started or continue to a tracker',
    () async {
      final f = Fixture();
      f.available = (trakt: true, simkl: true, mdblist: true);
      f.readers.movie = true;
      f.readers.gate = Completer<void>();
      final pending = label(f);
      await f.readers.entered.future;
      f.current = false;
      f.readers.gate!.complete();
      expect((await pending).started, isFalse);
      expect(f.tracker.calls, isEmpty);
    },
  );
  test('authentication remains live between sequential reads', () async {
    final f = Fixture();
    f.available = (trakt: true, simkl: false, mdblist: false);
    f.tracker.trakt = () async {
      f.available = (trakt: true, simkl: true, mdblist: false);
      return null;
    };
    expect((await label(f)).started, isTrue);
    expect(f.tracker.calls, ['trakt:tt123', 'simkl:tt123']);
  });
}

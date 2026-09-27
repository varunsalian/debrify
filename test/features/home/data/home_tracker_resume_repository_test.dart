import 'dart:async';

import 'package:debrify/features/home/data/home_tracker_resume_repository.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/mdblist_continue_watching.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:flutter_test/flutter_test.dart';

MdblistContinueWatchingItem candidate(
  String id,
  double? percent, {
  bool paused = true,
  bool series = false,
}) => MdblistContinueWatchingItem(
  selection: AdvancedSearchSelection(
    imdbId: id,
    title: id,
    isSeries: series,
    mdblistProgressPercent: percent,
  ),
  paused: paused,
);

class Fixture {
  var time = DateTime.utc(2026);
  bool owner = true, view = true;
  final calls = <String>[];
  Future<double?> Function() trakt = () async => 40;
  Future<double?> Function() simkl = () async => 50;
  Future<MdblistResult<MdblistContinueWatchingSnapshot>> Function() mdb =
      () async =>
          const MdblistResult.success(MdblistContinueWatchingSnapshot());
  late final repository = HomeTrackerResumeRepository(
    readTraktMovie: (id) {
      calls.add('trakt:$id');
      return trakt();
    },
    readSimklMovie: (id) {
      calls.add('simkl:$id');
      return simkl();
    },
    readMdblist: () {
      calls.add('mdb');
      return mdb();
    },
    isOwnerCurrent: () => owner,
    now: () => time,
  );
  Future<double?> read(String source, [String id = 'tt123']) =>
      switch (source) {
        'trakt' => repository.traktMovie(id, isCurrent: () => view),
        'simkl' => repository.simklMovie(id, isCurrent: () => view),
        _ => repository.mdblistMovie(id, isCurrent: () => view),
      };
}

void main() {
  test(
    'Trakt caches null and values for strictly less than 30 seconds',
    () async {
      for (final value in [null, 45.0]) {
        final f = Fixture()..trakt = (() async => value);
        expect(await f.read('trakt'), value);
        f.time = f.time.add(const Duration(milliseconds: 29999));
        expect(await f.read('trakt'), value);
        expect(f.calls, ['trakt:tt123']);
        f.time = f.time.add(const Duration(milliseconds: 1));
        expect(await f.read('trakt'), value);
        expect(f.calls, ['trakt:tt123', 'trakt:tt123']);
      }
    },
  );

  test('Trakt TTL begins at completion and cache keys stay exact', () async {
    final pending = Completer<double?>();
    final f = Fixture()..trakt = (() => pending.future);
    final first = f.read('trakt');
    f.time = f.time.add(const Duration(minutes: 2));
    pending.complete(42);
    expect(await first, 42);
    f.time = f.time.add(const Duration(seconds: 29));
    expect(await f.read('trakt'), 42);
    expect(f.calls.length, 1);
    await f.read('trakt', 'tt124');
    expect(f.calls.length, 2);
  });

  test(
    'overlapping reads remain independent and last completion populates memo',
    () async {
      final a = Completer<double?>(), b = Completer<double?>();
      var count = 0;
      final f = Fixture()..trakt = (() => ++count == 1 ? a.future : b.future);
      final first = f.read('trakt'), second = f.read('trakt');
      expect(count, 2);
      b.complete(60);
      expect(await second, 60);
      a.complete(20);
      expect(await first, 20);
      expect(await f.read('trakt'), 20);
      expect(count, 2);
    },
  );

  test(
    'identity eligibility and normalization remain source-specific',
    () async {
      final f = Fixture();
      for (final id in ['', 'TT123', 'tmdb:123', 'custom:1']) {
        expect(await f.read('trakt', id), isNull);
      }
      expect(await f.read('trakt', 'ttarbitrary'), 40);
      for (final id in ['tt123', 'tmdb:123', 'simkl:456']) {
        expect(await f.read('simkl', id), 50);
      }
      for (final id in ['', 'custom:1', 'tmdb:series:123']) {
        expect(await f.read('simkl', id), isNull);
      }
      f.mdb = () async => MdblistResult.success(
        MdblistContinueWatchingSnapshot(movies: [candidate('tt123', 45)]),
      );
      expect(await f.read('mdb', 'TT123'), 45);
      expect(await f.read('mdb', 'tmdb:123'), isNull);
      expect(f.calls, [
        'trakt:ttarbitrary',
        'simkl:tt123',
        'simkl:tmdb:123',
        'simkl:simkl:456',
        'mdb',
      ]);
    },
  );

  for (final source in ['trakt', 'simkl', 'mdb']) {
    test(
      '$source preserves its resume band and non-finite legacy comparisons',
      () async {
        for (final value in [
          null,
          -1.0,
          0.99,
          1.0,
          79.99,
          80.0,
          89.99,
          90.0,
          double.infinity,
          double.nan,
        ]) {
          final f = Fixture()
            ..trakt = (() async => value)
            ..simkl = (() async => value)
            ..mdb = (() async => MdblistResult.success(
              MdblistContinueWatchingSnapshot(
                movies: [candidate('tt123', value)],
              ),
            ));
          final result = await f.read(source);
          if (value?.isNaN ?? false) {
            expect(
              result,
              isNaN,
            ); // Structural extraction does not add new validation.
          } else {
            expect(
              result,
              value == null || value < 1 || value >= (source == 'mdb' ? 80 : 90)
                  ? null
                  : value,
            );
          }
        }
      },
    );
    for (final retirement in ['view', 'owner', 'dispose']) {
      test(
        '$source rejects $retirement during read and before later work',
        () async {
          final pending = Completer<double?>();
          final f = Fixture()
            ..trakt = (() => pending.future)
            ..simkl = (() => pending.future)
            ..mdb = (() async => MdblistResult.success(
              MdblistContinueWatchingSnapshot(
                movies: [candidate('tt123', await pending.future)],
              ),
            ));
          final operation = f.read(source);
          if (retirement == 'view') f.view = false;
          if (retirement == 'owner') f.owner = false;
          if (retirement == 'dispose') f.repository.dispose();
          pending.complete(55);
          expect(await operation, isNull);
          expect(await f.read(source), isNull);
          expect(f.calls.length, 1);
          if (retirement == 'view') {
            f.view = true;
            expect(await f.read(source), 55);
            expect(
              f.calls.length,
              2,
            ); // Retired result did not populate Trakt memo.
          }
        },
      );
    }
    test(
      '$source errors propagate without automatic retries or cached failure',
      () async {
        final f = Fixture()
          ..trakt = (() async => throw StateError('fixture'))
          ..simkl = (() async => throw StateError('fixture'))
          ..mdb = (() async => throw StateError('fixture'));
        await expectLater(f.read(source), throwsStateError);
        await expectLater(f.read(source), throwsStateError);
        expect(f.calls.length, 2);
      },
    );
  }

  test(
    'MDBList retains first-match feed order, series lookup and partial data',
    () async {
      final movie = candidate('TT123', 33);
      final show = candidate('tt123', 44, series: true);
      final f = Fixture()
        ..mdb = (() async => MdblistResult.partial(
          MdblistContinueWatchingSnapshot(movies: [movie], shows: [show]),
        ));
      expect(
        await f.repository.mdblistItem('tt123', isCurrent: () => true),
        same(movie),
      );
      f.mdb = () async =>
          MdblistResult.success(MdblistContinueWatchingSnapshot(shows: [show]));
      expect(
        await f.repository.mdblistItem('TT123', isCurrent: () => true),
        same(show),
      );
      expect(await f.read('mdb'), isNull);
      f.mdb = () async =>
          const MdblistResult.failure(MdblistResultKind.transientFailure);
      expect(
        await f.repository.mdblistItem('tt123', isCurrent: () => true),
        isNull,
      );
      f.mdb = () async => MdblistResult.success(
        MdblistContinueWatchingSnapshot(
          movies: [candidate('tt123', 45, paused: false)],
        ),
      );
      expect(await f.read('mdb'), isNull);
    },
  );
}

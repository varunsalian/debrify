import 'dart:async';

import 'package:debrify/features/home/data/home_series_resume_resolution.dart';
import 'package:debrify/features/home/models/home_series_resume_result.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/mdblist_continue_watching.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

AdvancedSearchSelection selection({
  int? season = 2,
  int? episode = 3,
  double? progress = 25,
}) => AdvancedSearchSelection(
  imdbId: 'tt123',
  title: 'Show',
  isSeries: true,
  season: season,
  episode: episode,
  traktProgressPercent: progress,
  mdblistProgressPercent: progress,
  traktSource: true,
  mdblistSource: true,
  stremioAddonId: 'configured-origin',
  stremioVideoId: 'exact-video',
);

class Harness {
  ({AdvancedSearchSelection sel, int? tsMs})? trakt;
  ({int season, int episode, double? progress, DateTime? pausedAt})? simkl;
  MdblistContinueWatchingItem? mdb;
  ({int season, int episode, double? pct, int? tsMs, bool finished})? local;
  EpisodeCoordinate? simklNext;
  EpisodeCoordinate? guideNext;
  Completer<EpisodeCoordinate?>? pending;
  Object? guideError;
  final events = <String>[];
  final guideCalls = <EpisodeCoordinate>[];
  final winners = <HomeSeriesResumeCandidate>[];
  final advances =
      <
        ({
          EpisodeCoordinate from,
          EpisodeCoordinate? guide,
          EpisodeCoordinate? adjacent,
          EpisodeCoordinate? target,
        })
      >[];
  bool? willAdvance;
  bool? frontierAhead;

  void source(
    int priority, {
    int? timestamp,
    double? progress = 25,
    int season = 2,
    int episode = 3,
    bool finished = false,
  }) {
    switch (priority) {
      case 0:
        trakt = (
          sel: selection(season: season, episode: episode, progress: progress),
          tsMs: timestamp,
        );
      case 1:
        simkl = (
          season: season,
          episode: episode,
          progress: progress,
          pausedAt: timestamp == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(timestamp),
        );
      case 2:
        mdb = MdblistContinueWatchingItem(
          selection: selection(
            season: season,
            episode: episode,
            progress: progress,
          ),
          paused: true,
          updatedAt: timestamp == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(timestamp),
        );
      case 3:
        local = (
          season: season,
          episode: episode,
          pct: progress,
          tsMs: timestamp,
          finished: finished,
        );
    }
  }

  Future<HomeSeriesResumeResult> run() => resolveHomeSeriesResume(
    trakt: trakt,
    simkl: simkl,
    mdb: mdb,
    local: local,
    simklNext: simklNext,
    findNextEpisode: (season, episode) {
      events.add('guide');
      guideCalls.add((season: season, episode: episode));
      if (guideError case final error?) return Future.error(error);
      return pending?.future ?? Future.value(guideNext);
    },
    onWinner: (winner, {required trackerFrontierAhead, required willAdvance}) {
      events.add('winner');
      winners.add(winner);
      frontierAhead = trackerFrontierAhead;
      this.willAdvance = willAdvance;
    },
    onAdvance: (from, guide, adjacent, target) {
      events.add('advance');
      advances.add((
        from: from,
        guide: guide,
        adjacent: adjacent,
        target: target,
      ));
    },
  );
}

void main() {
  test(
    'no signals gives unstarted S1E1 without guide or winner callbacks',
    () async {
      final h = Harness();
      expect(await h.run(), (
        started: false,
        season: 1,
        episode: 1,
        simklProgress: null,
        selection: null,
        sourcePrio: null,
      ));
      expect(h.events, isEmpty);
    },
  );

  test(
    'computed next outranks unpaused MDBList fallback without attribution',
    () async {
      final h = Harness()
        ..simklNext = (season: 4, episode: 5)
        ..mdb = MdblistContinueWatchingItem(
          selection: selection(season: 6, episode: 7),
          paused: false,
        );
      final result = await h.run();
      expect((result.started, result.season, result.episode), (true, 4, 5));
      expect(
        (result.selection, result.simklProgress, result.sourcePrio),
        (null, null, null),
      );
      expect(h.events, isEmpty);
    },
  );

  test(
    'unpaused MDBList coordinate is a weak fallback, not a paused session',
    () async {
      final h = Harness()
        ..mdb = MdblistContinueWatchingItem(
          selection: selection(),
          paused: false,
        );
      final result = await h.run();
      expect((result.started, result.season, result.episode), (true, 2, 3));
      expect(result.sourcePrio, isNull);
      expect(result.selection, isNull);
      expect(h.events, isEmpty);
    },
  );

  test(
    'incomplete tracker coordinates cannot create a resume candidate',
    () async {
      final h = Harness()
        ..trakt = (sel: selection(season: null), tsMs: 999)
        ..mdb = MdblistContinueWatchingItem(
          selection: selection(episode: null),
          paused: true,
        );
      expect((await h.run()).started, false);
      expect(h.events, isEmpty);
    },
  );

  for (var priority = 0; priority < 4; priority++) {
    test(
      'timestampless fallback starts with source $priority and keeps its payload',
      () async {
        final h = Harness();
        for (var p = priority; p < 4; p++) {
          h.source(p, episode: p + 3);
        }
        h.simklNext = (season: 9, episode: 9);
        final result = await h.run();
        expect(result.sourcePrio, priority);
        expect((result.season, result.episode), (2, priority + 3));
        expect(
          result.selection,
          priority == 0
              ? same(h.trakt!.sel)
              : priority == 2
              ? same(h.mdb!.selection)
              : isNull,
        );
        expect(result.simklProgress, priority == 1 ? 25 : isNull);
        expect(h.events, ['winner']);
        expect(h.willAdvance, false);
      },
    );

    test('source $priority wins with the newest actual timestamp', () async {
      final h = Harness();
      for (var p = 0; p < 4; p++) {
        h.source(p, timestamp: p == priority ? 1000 : 500, episode: p + 3);
      }
      final result = await h.run();
      expect(result.sourcePrio, priority);
      expect(result.episode, priority + 3);
      expect(h.guideCalls, isEmpty);
    });

    test(
      'advancing source $priority keeps attribution and clears old progress',
      () async {
        final h = Harness()..guideNext = (season: 3, episode: 1);
        h.source(priority, progress: 80, finished: priority == 3);
        final original = priority == 0
            ? h.trakt!.sel
            : priority == 2
            ? h.mdb!.selection
            : null;
        final result = await h.run();
        expect(result.sourcePrio, priority);
        expect((result.season, result.episode), (3, 1));
        expect(result.selection, isNull);
        expect(result.simklProgress, isNull);
        expect(h.guideCalls, [(season: 2, episode: 3)]);
        expect(h.events, ['winner', 'guide', 'advance']);
        if (original != null) {
          expect(original.episode, 3);
          expect(original.traktProgressPercent, 80);
        }
      },
    );
  }

  test('even zero timestamp beats every absent timestamp', () async {
    final h = Harness();
    h.source(0);
    h.source(3, timestamp: 0, episode: 7);
    final result = await h.run();
    expect((result.sourcePrio, result.episode), (3, 7));
  });

  test(
    'equal timestamps retain the preceding four-candidate ordering',
    () async {
      final h = Harness();
      for (var p = 0; p < 4; p++) {
        h.source(p, timestamp: 1000, episode: p + 3);
      }
      expect((await h.run()).sourcePrio, 0);
    },
  );

  test(
    'local near-complete pause stays resumable without a later tracker',
    () async {
      final h = Harness()..guideNext = (season: 2, episode: 4);
      h.source(3, progress: 97);
      h.simklNext = (season: 2, episode: 3);
      final result = await h.run();
      expect((result.season, result.episode), (2, 3));
      expect(h.guideCalls, isEmpty);
      expect(h.frontierAhead, false);
    },
  );

  test(
    'local near-complete winner advances with a weaker tracker frontier',
    () async {
      final h = Harness()..guideNext = (season: 2, episode: 4);
      h.source(3, timestamp: 2000, progress: 97);
      h.source(0, timestamp: 1000, episode: 4);
      final result = await h.run();
      expect((result.sourcePrio, result.episode), (3, 4));
      expect(h.frontierAhead, true);
      expect(h.willAdvance, true);
    },
  );

  test(
    'explicitly finished local position advances even with low percentage',
    () async {
      final h = Harness()..guideNext = (season: 2, episode: 4);
      h.source(3, progress: 1, finished: true);
      expect((await h.run()).episode, 4);
      expect(h.guideCalls, hasLength(1));
    },
  );

  test(
    'below tracker threshold does not fetch guide; exact threshold does',
    () async {
      final h = Harness();
      h.source(1, progress: 79.999);
      expect((await h.run()).simklProgress, 79.999);
      expect(h.guideCalls, isEmpty);
      h.source(1, progress: 80);
      expect((await h.run()).simklProgress, 80);
      expect(h.guideCalls, hasLength(1));
    },
  );

  for (final frontier in [(season: 2, episode: 4), (season: 3, episode: 1)]) {
    test('unknown guide accepts direct frontier $frontier', () async {
      final h = Harness()..simklNext = frontier;
      h.source(0, progress: 80);
      final result = await h.run();
      expect((season: result.season, episode: result.episode), frontier);
      expect(result.selection, isNull);
      expect(result.sourcePrio, 0);
    });
  }

  test(
    'far-away rewatch frontier cannot teleport a completed winner',
    () async {
      final h = Harness()..simklNext = (season: 5, episode: 1);
      h.source(0, progress: 95);
      final result = await h.run();
      expect((result.season, result.episode), (2, 3));
      expect(result.selection, same(h.trakt!.sel));
      expect(h.advances.single.target, isNull);
    },
  );

  test(
    'guide wins over frontier; fallback picks first in recency-sorted order',
    () async {
      final h = Harness()..guideNext = (season: 4, episode: 1);
      h.source(3, timestamp: 3000, finished: true);
      h.source(0, timestamp: 1000, episode: 4);
      h.source(1, timestamp: 2000, season: 3, episode: 1);
      expect((await h.run()).season, 4);
      expect(h.advances.single.adjacent, (season: 3, episode: 1));
      h.guideNext = null;
      expect((await h.run()).season, 3);
    },
  );

  test(
    'guide error propagates after winner event without inventing a fallback',
    () async {
      final error = StateError('guide failed');
      final h = Harness()..guideError = error;
      h.source(0, progress: 95);
      await expectLater(h.run(), throwsA(same(error)));
      expect(h.events, ['winner', 'guide']);
    },
  );

  test(
    'stalled guide times out at four seconds; late result cannot revise target',
    () {
      fakeAsync((clock) {
        final h = Harness()
          ..pending = Completer<EpisodeCoordinate?>()
          ..simklNext = (season: 2, episode: 4);
        h.source(1, progress: 80);
        HomeSeriesResumeResult? result;
        h.run().then((value) => result = value);
        clock.flushMicrotasks();
        expect(h.events, ['winner', 'guide']);
        clock.elapse(const Duration(milliseconds: 3999));
        expect(result, isNull);
        clock.elapse(const Duration(milliseconds: 1));
        clock.flushMicrotasks();
        expect((result!.season, result!.episode), (2, 4));
        expect(result!.simklProgress, isNull);
        h.pending!.complete((season: 9, episode: 9));
        clock.flushMicrotasks();
        expect((result!.season, result!.episode), (2, 4));
        expect(h.advances, hasLength(1));
      });
    },
  );
}

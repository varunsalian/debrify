// The stats page's notifier: one load per match, live polling only while
// live and allowed, failures that keep what is shown, stale loads that cannot
// overwrite newer ones, and cleanup on disposal.
import 'dart:async';
import 'dart:convert';

import 'package:debrify/features/sports/application/sports_match_stats_notifier.dart';
import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/data/sports_match_stats_client.dart';
import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../sports_match_stats_fixtures.dart';

const _key = SportsMatchKey(leagueId: 'nfl', eventId: '401873066');

/// The NFL fixture as a [state] match with the home score [score].
String _body({String state = 'in', String score = '26', String? date}) {
  final json =
      withoutArtwork(readSummaryFixture('espn_summary_nfl_final.json')) as Map;
  final competition =
      ((json['header'] as Map)['competitions'] as List).first as Map;
  final type = (competition['status'] as Map)['type'] as Map;
  type['state'] = state;
  type['completed'] = state == 'post';
  ((competition['competitors'] as List).first as Map)['score'] = score;
  if (date != null) competition['date'] = date;
  return jsonEncode(json);
}

/// A container over [fetch]. The client keeps nothing (`maxEntries: 0`), so
/// every load reaches [fetch] and a failure reaches the notifier rather than
/// the client's stale fallback.
ProviderContainer _container(
  Future<String> Function(Uri) fetch, {
  DateTime Function()? clock,
}) => _over(SportsMatchStatsClient(fetch: fetch, maxEntries: 0), clock: clock);

ProviderContainer _over(
  SportsMatchStatsClient client, {
  DateTime Function()? clock,
}) => ProviderContainer.test(
  overrides: [
    sportsMatchStatsClientProvider.overrideWithValue(client),
    if (clock != null) sportsMatchStatsClockProvider.overrideWithValue(clock),
  ],
);

/// Answers each load with its own completer, so a test decides the order.
class _ScriptedClient extends SportsMatchStatsClient {
  _ScriptedClient() : super(fetch: (_) => throw UnimplementedError());

  final List<Completer<SportsMatchStats>> answers = [];

  @override
  Future<SportsMatchStats> load(SportsMatchKey key) {
    final answer = Completer<SportsMatchStats>();
    answers.add(answer);
    return answer.future;
  }
}

SportsMatchStats _stats(String score) => SportsMatchStats(
  status: SportsEventStatus.finished,
  statusDetail: 'Final',
  home: SportsMatchSide(
    teamId: '1',
    abbreviation: 'HOM',
    name: 'Home',
    score: score,
  ),
  away: const SportsMatchSide(teamId: '2', abbreviation: 'AWY', name: 'Away'),
);

void main() {
  test('loads the match through the client', () async {
    final fetch = FakeSummaryFetch(_body(state: 'post'));
    final container = _container(fetch.call);
    final stats = await container.read(sportsMatchStatsProvider(_key).future);
    expect(stats.home.abbreviation, 'HOU');
    expect(fetch.calls.single.queryParameters['event'], '401873066');
  });

  test('a live match refreshes every poll interval while open', () {
    fakeAsync((time) {
      final fetch = FakeSummaryFetch(_body(score: '7'));
      final container = _container(fetch.call);
      container.listen(sportsMatchStatsProvider(_key), (_, _) {});
      time.flushMicrotasks();
      expect(
        container.read(sportsMatchStatsProvider(_key)).value!.home.score,
        '7',
      );

      fetch.body = _body(score: '14');
      time.elapse(
        SportsMatchStatsNotifier.pollInterval - const Duration(seconds: 1),
      );
      expect(fetch.calls, hasLength(1));
      time.elapse(const Duration(seconds: 1));
      expect(fetch.calls, hasLength(2));
      expect(
        container.read(sportsMatchStatsProvider(_key)).value!.home.score,
        '14',
      );

      // Full time: polling stops.
      fetch.body = _body(state: 'post', score: '21');
      time.elapse(SportsMatchStatsNotifier.pollInterval);
      expect(fetch.calls, hasLength(3));
      time.elapse(SportsMatchStatsNotifier.pollInterval * 5);
      expect(fetch.calls, hasLength(3));
    });
  });

  test('scheduled and finished matches never poll', () {
    for (final state in ['pre', 'post']) {
      fakeAsync((time) {
        // Kick-off far ahead: a preview only wakes at kick-off.
        final fetch = FakeSummaryFetch(
          _body(state: state, date: '2031-01-01T00:00Z'),
        );
        final container = _container(fetch.call);
        container.listen(sportsMatchStatsProvider(_key), (_, _) {});
        time.elapse(SportsMatchStatsNotifier.pollInterval * 3);
        expect(fetch.calls, hasLength(1), reason: state);
      });
    }
  });

  test('a poll waits while the page says it may not run', () {
    fakeAsync((time) {
      final fetch = FakeSummaryFetch(_body());
      final container = _container(fetch.call);
      container.listen(sportsMatchStatsProvider(_key), (_, _) {});
      time.flushMicrotasks();
      var allowed = false;
      container.read(sportsMatchStatsProvider(_key).notifier).canPoll = () =>
          allowed;
      time.elapse(SportsMatchStatsNotifier.pollInterval * 2);
      expect(fetch.calls, hasLength(1));
      allowed = true;
      time.elapse(SportsMatchStatsNotifier.pollInterval);
      expect(fetch.calls, hasLength(2));
    });
  });

  test('a failed poll keeps the shown stats and polls again', () {
    fakeAsync((time) {
      final fetch = FakeSummaryFetch(_body(score: '7'));
      final container = _container(fetch.call);
      container.listen(sportsMatchStatsProvider(_key), (_, _) {});
      time.flushMicrotasks();
      final shown = container.read(sportsMatchStatsProvider(_key)).value;

      fetch.body = TimeoutException('offline');
      time.elapse(SportsMatchStatsNotifier.pollInterval);
      final state = container.read(sportsMatchStatsProvider(_key));
      expect(state.hasError, isFalse);
      expect(state.value, same(shown));

      fetch.body = _body(score: '10');
      time.elapse(SportsMatchStatsNotifier.pollInterval);
      expect(
        container.read(sportsMatchStatsProvider(_key)).value!.home.score,
        '10',
      );
    });
  });

  test('a first load that fails is an error until Retry succeeds', () async {
    final fetch = FakeSummaryFetch(TimeoutException('offline'));
    final container = _container(fetch.call);
    final sub = container.listen(sportsMatchStatsProvider(_key), (_, _) {});
    await expectLater(
      container.read(sportsMatchStatsProvider(_key).future),
      throwsA(anything),
    );
    expect(container.read(sportsMatchStatsProvider(_key)).hasError, isTrue);

    fetch.body = _body(state: 'post');
    final retry = container
        .read(sportsMatchStatsProvider(_key).notifier)
        .refresh();
    expect(container.read(sportsMatchStatsProvider(_key)).isLoading, isTrue);
    await retry;
    final state = container.read(sportsMatchStatsProvider(_key));
    expect(state.hasError, isFalse);
    expect(state.value!.home.abbreviation, 'HOU');
    sub.close();
  });

  test('an older load cannot overwrite a newer one', () async {
    final client = _ScriptedClient();
    final container = _over(client);
    final sub = container.listen(sportsMatchStatsProvider(_key), (_, _) {});
    client.answers.single.complete(_stats('1'));
    await container.read(sportsMatchStatsProvider(_key).future);

    final notifier = container.read(sportsMatchStatsProvider(_key).notifier);
    final older = notifier.refresh();
    final newer = notifier.refresh();
    expect(client.answers, hasLength(3));
    client.answers[2].complete(_stats('3'));
    await newer;
    client.answers[1].complete(_stats('2'));
    await older;
    expect(
      container.read(sportsMatchStatsProvider(_key)).value!.home.score,
      '3',
    );
    sub.close();
  });

  test('an older failure cannot clear a newer load', () async {
    final client = _ScriptedClient();
    final container = _over(client);
    final sub = container.listen(sportsMatchStatsProvider(_key), (_, _) {});
    client.answers.single.completeError(TimeoutException('offline'));
    await expectLater(
      container.read(sportsMatchStatsProvider(_key).future),
      throwsA(anything),
    );
    // Retry pressed twice: the first retry fails while the second is still
    // loading. The page must stay on its loading state, not flip to error.
    final notifier = container.read(sportsMatchStatsProvider(_key).notifier);
    final older = notifier.refresh();
    final newer = notifier.refresh();
    client.answers[1].completeError(TimeoutException('late failure'));
    await older;
    // Riverpod keeps the first load's error alongside the loading flag; the
    // late failure must neither end the loading nor replace that error.
    final loading = container.read(sportsMatchStatsProvider(_key));
    expect(loading.isLoading, isTrue);
    expect('${loading.error}', isNot(contains('late failure')));

    client.answers[2].complete(_stats('5'));
    await newer;
    final state = container.read(sportsMatchStatsProvider(_key));
    expect(state.hasError, isFalse);
    expect(state.value!.home.score, '5');
    sub.close();
  });

  test('a preview left open wakes at kick-off and turns live', () {
    fakeAsync((time) {
      final base = DateTime.utc(2030, 3, 3, 20);
      final fetch = FakeSummaryFetch(
        _body(state: 'pre', date: '2030-03-03T20:30Z'),
      );
      final container = _container(
        fetch.call,
        clock: () => base.add(time.elapsed),
      );
      container.listen(sportsMatchStatsProvider(_key), (_, _) {});
      time.flushMicrotasks();

      time.elapse(const Duration(minutes: 29));
      expect(fetch.calls, hasLength(1), reason: 'no polling before kick-off');
      // At kick-off the feed may still say "pre": keep checking each poll.
      time.elapse(const Duration(minutes: 1));
      expect(fetch.calls, hasLength(2));
      fetch.body = _body(state: 'in', score: '3');
      time.elapse(SportsMatchStatsNotifier.pollInterval);
      expect(fetch.calls, hasLength(3));
      final stats = container.read(sportsMatchStatsProvider(_key)).value!;
      expect(stats.status, SportsEventStatus.live);
      time.elapse(SportsMatchStatsNotifier.pollInterval);
      expect(fetch.calls, hasLength(4), reason: 'now polling as live');
    });
  });

  test('closing the page stops polling', () {
    fakeAsync((time) {
      final fetch = FakeSummaryFetch(_body());
      final container = _container(fetch.call);
      final sub = container.listen(sportsMatchStatsProvider(_key), (_, _) {});
      time.flushMicrotasks();
      sub.close();
      time.elapse(SportsMatchStatsNotifier.pollInterval * 3);
      expect(fetch.calls, hasLength(1));
    });
  });

  test('two matches keep separate state', () async {
    final fetch = FakeSummaryFetch(_body(state: 'post'));
    final container = _container(fetch.call);
    const other = SportsMatchKey(leagueId: 'nfl', eventId: '2');
    await container.read(sportsMatchStatsProvider(_key).future);
    await container.read(sportsMatchStatsProvider(other).future);
    expect(fetch.calls.map((u) => u.queryParameters['event']), [
      '401873066',
      '2',
    ]);
    expect(
      container.read(sportsMatchStatsProvider(other)).value!.status,
      SportsEventStatus.finished,
    );
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:debrify/models/stream_badge_rules.dart';
import 'package:debrify/services/stream_badge_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

StreamBadgeMatcher matcher(String pattern) => StreamBadgeMatcher([
  StreamBadgeRuleset.parse(
    jsonEncode({
      'filters': [
        {'name': 'Match', 'pattern': pattern},
      ],
    }),
  ),
]);
void main() {
  test(
    'worker matches formatter markers after a newline with inline flags',
    () async {
      const marker = '\u2063\u200c\u200d\u2064';
      final m = matcher('(?is)^(?=.*remux)(?=.*$marker)');
      addTearDown(m.dispose);
      final result = await m.matchResultFor(
        name: 'Movie.mkv',
        description: 'REMUX\n$marker',
      );
      expect(result.status, StreamBadgeMatchStatus.resolved);
      expect(result.badges.map((b) => b.name), ['Match']);
      expect(await m.matchesFor(name: 'REMUX without marker'), isEmpty);
    },
  );

  test(
    'saturation defers new requests without evicting admitted matches',
    () async {
      final m = matcher('Movie');
      addTearDown(m.dispose);
      final admitted = [
        for (var i = 0; i < StreamBadgeMatcher.maxPending; i++)
          m.matchResultFor(name: 'Movie $i'),
      ];
      final overflow = await m.matchResultFor(name: 'Movie overflow');
      expect(overflow.status, StreamBadgeMatchStatus.deferred);
      final results = await Future.wait(admitted);
      expect(
        results.every(
          (r) =>
              r.status == StreamBadgeMatchStatus.resolved &&
              r.badges.length == 1,
        ),
        true,
      );
      expect(
        (await m.matchResultFor(name: 'Movie overflow')).badges,
        hasLength(1),
      );
    },
  );
  test('preparation and the first match have separate cold budgets', () async {
    final m = StreamBadgeMatcher.withWorker([
      StreamBadgeRuleset.parse(
        jsonEncode({
          'filters': [
            {'name': 'test', 'pattern': 'x'},
          ],
        }),
      ),
    ], _slowColdWorker);
    addTearDown(m.dispose);
    expect(await m.matchesFor(name: 'cold'), hasLength(1));
    expect(m.failed, false);
    // After the first result, the ordinary 500ms execution limit applies.
    expect(await m.matchesFor(name: 'slow'), isEmpty);
    expect(m.failureReason, StreamBadgeFailure.matching);
  });
  test(
    'an uncaught error fails immediately even when the worker stays alive',
    () async {
      final m = StreamBadgeMatcher.withWorker([
        StreamBadgeRuleset.parse(
          jsonEncode({
            'filters': [
              {'name': 'test', 'pattern': 'x'},
            ],
          }),
        ),
      ], _errorWorker);
      addTearDown(m.dispose);
      expect(
        await m.matchesFor(name: 'x').timeout(const Duration(seconds: 1)),
        isEmpty,
      );
      expect(m.failureReason, StreamBadgeFailure.worker);
    },
  );
  test(
    'existing oversized inventories report the rule limit without truncation',
    () async {
      final m = StreamBadgeMatcher([
        StreamBadgeRuleset.parse(
          jsonEncode({
            'filters': [
              for (var i = 0; i < 513; i++) {'name': '$i', 'pattern': 'x'},
            ],
          }),
        ),
      ]);
      expect(m.failure.value, true);
      expect(m.failureReason, StreamBadgeFailure.tooManyRules);
      expect(m.failureMessage, contains('maximum 512'));
      expect(m.rules, hasLength(513));
      expect(await m.matchesFor(name: 'x'), isEmpty);
      m.dispose();
      m.dispose();
    },
  );

  test(
    'pathological rules are killed without blocking the calling isolate',
    () async {
      final m = matcher(r'^(a+)+$');
      addTearDown(m.dispose);
      final result = m.matchesFor(name: '${'a' * 40}!');
      var responded = false;
      Timer(const Duration(milliseconds: 20), () => responded = true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(responded, true);
      expect(await result.timeout(const Duration(seconds: 4)), isEmpty);
      expect(m.failed, true);
      expect(m.failure.value, true);
      expect(await m.matchesFor(name: 'a'), isEmpty);
    },
  );
  test(
    'disposal completes active and queued work without stale results',
    () async {
      final m = matcher(r'^(a+)+$');
      final active = m.matchesFor(name: '${'a' * 40}!');
      final queued = m.matchesFor(name: 'a');
      m.dispose();
      expect(await active, isEmpty);
      expect(await queued, isEmpty);
      final replacement = matcher('HDR');
      addTearDown(replacement.dispose);
      expect(await replacement.matchesFor(name: 'HDR'), hasLength(1));
    },
  );
  test(
    'bounded inputs do not get truncated into false positive matches',
    () async {
      final m = matcher(r'^a+$');
      addTearDown(m.dispose);
      expect(
        await m.matchesFor(name: '${'a' * StreamBadgeMatcher.maxInputLength}!'),
        isEmpty,
      );
      expect(m.failed, false);
    },
  );
  test('queued work stays bounded and completes when disposed', () async {
    final m = matcher(r'^(a+)+$');
    final jobs = [
      for (var i = 0; i < 150; i++) m.matchesFor(name: '${'a' * 40}!$i'),
    ];
    m.dispose();
    expect((await Future.wait(jobs)).every((result) => result.isEmpty), true);
  });
}

// A live worker with deliberately slow preparation and cold execution.
void _slowColdWorker(SendPort output) {
  final input = ReceivePort();
  output.send(input.sendPort);
  var prepared = false;
  input.listen((message) async {
    if (!prepared) {
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      prepared = true;
      output.send('ready');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    output.send([
      (message as List).first,
      [0],
    ]);
  });
}

void _errorWorker(SendPort output) {
  Isolate.current.setErrorsFatal(false);
  final input = ReceivePort();
  output.send(input.sendPort);
  var prepared = false;
  input.listen((message) {
    if (!prepared) {
      prepared = true;
      output.send('ready');
    } else {
      throw StateError('Worker failure');
    }
  });
}

import 'dart:async';

import 'package:debrify/services/prepared_stream_requests.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'foreground searches share only active work; retries fetch fresh',
    () async {
      final cache = PreparedStreamRequests<int>();
      final gate = Completer<int>();
      var calls = 0;
      Future<int> load() {
        calls++;
        return gate.future;
      }

      final a = cache.get('episode', load);
      final b = cache.get('episode', load);
      gate.complete(42);
      expect(await a, 42);
      expect(await b, 42);
      expect(calls, 1);
      await cache.get('episode', load);
      expect(calls, 2);
    },
  );

  test(
    'prepared result is consumed once, never reused on failure recovery',
    () async {
      final cache = PreparedStreamRequests<int>();
      var calls = 0;
      Future<int> load() async => ++calls;
      await cache.get('episode', load, prepare: true);
      expect(await cache.get('episode', load), 1);
      expect(await cache.get('episode', load), 2);
    },
  );

  test(
    'Next during preparation joins it without leaving a stale copy',
    () async {
      final cache = PreparedStreamRequests<int>();
      final gate = Completer<int>();
      final prepare = cache.get('episode', () => gate.future, prepare: true);
      final play = cache.get('episode', () async => 99);
      gate.complete(1);
      expect(await prepare, 1);
      expect(await play, 1);
      expect(await cache.get('episode', () async => 2), 2);
    },
  );

  test('honors TTL and explicit earlier expiry', () async {
    var now = DateTime.utc(2026);
    final cache = PreparedStreamRequests<int>(now: () => now);
    await cache.get('a', () async => 1, prepare: true);
    await cache.get(
      'b',
      () async => 2,
      prepare: true,
      expiresAt: (_) => now.add(const Duration(seconds: 10)),
    );
    now = now.add(const Duration(seconds: 11));
    expect(await cache.get('b', () async => 3), 3);
    now = now.add(const Duration(minutes: 2));
    expect(await cache.get('a', () async => 4), 4);
  });

  test('different profiles, configurations and episodes never share', () async {
    final cache = PreparedStreamRequests<int>();
    const key = ('profile1', 'addon1', 1, 2);
    await cache.get(key, () async => 1, prepare: true);
    for (final other in [
      ('profile2', 'addon1', 1, 2),
      ('profile1', 'addon2', 1, 2),
      ('profile1', 'addon1', 1, 3),
    ]) {
      expect(await cache.get(other, () async => 2), 2);
    }
    expect(await cache.get(key, () async => 3), 1);
  });

  test('errors do not poison later requests', () async {
    final cache = PreparedStreamRequests<int>();
    await expectLater(
      cache.get('a', () async => throw StateError('offline'), prepare: true),
      throwsStateError,
    );
    expect(await cache.get('a', () async => 1), 1);
  });

  test(
    'invalidating during preparation prevents late result resurrection',
    () async {
      final cache = PreparedStreamRequests<int>();
      final gate = Completer<int>();
      final old = cache.get('a', () => gate.future, prepare: true);
      cache.clear();
      gate.complete(1);
      await old;
      expect(await cache.get('a', () async => 2), 2);
    },
  );

  test('bounds speculative results to four entries', () async {
    final cache = PreparedStreamRequests<int>();
    for (var i = 0; i < 5; i++) {
      await cache.get(i, () async => i, prepare: true);
    }
    expect(await cache.get(0, () async => 100), 100);
    expect(await cache.get(4, () async => 100), 4);
  });
}

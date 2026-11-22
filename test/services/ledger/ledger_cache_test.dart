import 'dart:async';

import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/services/ledger/ledger_cache.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Ledger is behind a feature flag (off in builds).
  setUp(() => debugLedgerEnabled = true);
  tearDown(() => debugLedgerEnabled = null);

  var now = DateTime(2026);
  LedgerCache<List<int>> cache() =>
      LedgerCache(const Duration(seconds: 30), now: () => now);

  setUp(() {
    now = DateTime(2026);
    ProfileRuntime.debugReset();
    ProfileSessionMemory.debugReset();
  });
  tearDown(ProfileRuntime.debugReset);

  test(
    'concurrent readers share one request; a hit skips the network',
    () async {
      final c = cache();
      var calls = 0;
      final gate = Completer<List<int>>();
      Future<List<int>?> fetch() {
        calls++;
        return gate.future;
      }

      final a = c.read(fetch);
      final b = c.read(fetch);
      gate.complete([1]);
      expect(await a, [1]);
      expect(await b, [1]);
      expect(await c.read(fetch), [1]);
      expect(calls, 1);
      now = now.add(const Duration(seconds: 31));
      await c.read(() async => [2]);
      expect(await c.read(fetch), [2]);
    },
  );

  test('a write during a fetch keeps its stale result out', () async {
    final c = cache();
    final gate = Completer<List<int>>();
    final stale = c.read(() => gate.future);
    c.invalidate();
    // A reader after the invalidation must not join the stale request.
    var fresh = 0;
    final next = c.read(() async {
      fresh++;
      return [2];
    });
    gate.complete([1]);
    expect(await stale, [1]);
    expect(await next, [2]);
    expect(fresh, 1);
    expect(await c.read(() async => [3]), [2]);
  });

  test('failures are not cached', () async {
    final c = cache();
    expect(await c.read(() async => null), isNull);
    expect(await c.read(() async => [1]), [1]);
  });

  test('a value is never reused by another profile session', () async {
    final c = cache();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: 'a', dataGeneration: 1, sessionEpoch: 1),
    );
    expect(await c.read(() async => [1]), [1]);
    ProfileRuntime.publish(
      ProfileScope(profileId: 'b', dataGeneration: 1, sessionEpoch: 2),
    );
    expect(await c.read(() async => [2]), [2]);
  });
}

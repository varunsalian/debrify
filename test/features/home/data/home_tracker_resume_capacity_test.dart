import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'home_tracker_resume_repository_test.dart' show Fixture;

Future<void> fill(Fixture fixture, {int start = 0, int end = 512}) async {
  for (var index = start; index < end; index++) {
    await fixture.read('trakt', 'tt$index');
  }
}

void main() {
  test(
    'capacity evicts the least recently used title while retaining hot results',
    () async {
      final f = Fixture();
      await fill(f);
      expect(f.calls.length, 512);
      expect(await f.read('trakt', 'tt0'), 40);
      expect(f.calls.length, 512);
      await f.read('trakt', 'tt512');
      expect(f.calls.length, 513);
      expect(await f.read('trakt', 'tt0'), 40);
      expect(f.calls.length, 513);
      expect(await f.read('trakt', 'tt1'), 40);
      expect(f.calls.length, 514);
      expect(await f.read('trakt', 'tt512'), 40);
      expect(f.calls.length, 514);
    },
  );

  test('cached misses count toward the same bound', () async {
    final f = Fixture()..trakt = (() async => null);
    await fill(f, end: 513);
    expect(f.calls.length, 513);
    expect(await f.read('trakt', 'tt512'), isNull);
    expect(f.calls.length, 513);
    expect(await f.read('trakt', 'tt0'), isNull);
    expect(f.calls.length, 514);
  });

  test('a recency touch does not extend the completion-based TTL', () async {
    final f = Fixture();
    expect(await f.read('trakt', 'tt0'), 40);
    f.time = f.time.add(const Duration(seconds: 29));
    expect(await f.read('trakt', 'tt0'), 40);
    expect(f.calls.length, 1);
    f.time = f.time.add(const Duration(seconds: 1));
    expect(await f.read('trakt', 'tt0'), 40);
    expect(f.calls.length, 2);
  });

  test(
    'refreshing an expired key at capacity does not evict a different fresh key',
    () async {
      final f = Fixture();
      await f.read('trakt', 'tt0');
      f.time = f.time.add(const Duration(seconds: 1));
      await fill(f, start: 1);
      f.time = f.time.add(const Duration(seconds: 29));
      await f.read('trakt', 'tt0');
      expect(f.calls.length, 513);
      await f.read('trakt', 'tt1');
      expect(f.calls.length, 513);
    },
  );

  test('retired and failed reads cannot evict accepted entries', () async {
    final f = Fixture();
    await fill(f);
    final pending = Completer<double?>();
    f.trakt = () => pending.future;
    final retired = f.read('trakt', 'tt512');
    f.view = false;
    pending.complete(60);
    expect(await retired, isNull);
    f.view = true;
    f.trakt = () async => throw StateError('fixture');
    await expectLater(f.read('trakt', 'tt513'), throwsStateError);
    expect(f.calls.length, 514);
    expect(await f.read('trakt', 'tt0'), 40);
    expect(await f.read('trakt', 'tt1'), 40);
    expect(f.calls.length, 514);
  });
}

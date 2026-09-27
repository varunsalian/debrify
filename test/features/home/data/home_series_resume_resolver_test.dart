import 'dart:async';

import 'package:debrify/features/home/data/home_series_resume_resolver.dart';
import 'package:debrify/features/home/data/home_tracking_policy_repository.dart';
import 'package:debrify/features/home/models/home_series_resume_result.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/stremio_addon.dart';

import 'home_series_resume_repository_test.dart' as signals;
import 'home_tracker_resume_repository_test.dart' as trackers;

class Fixture {
  final source = signals.Fixture();
  final tracker = trackers.Fixture();
  var time = DateTime.utc(2026);
  var owner = true, view = true;
  var policy = WatchProgressSource.local;
  var available = (trakt: false, simkl: false, mdblist: false);
  final revisions = <String, int>{};
  final logs = <String>[];
  int policyReads = 0, availabilityReads = 0;
  Completer<void>? policyGate;
  Completer<({int season, int episode})?>? guideGate;
  final guideEntered = Completer<void>();

  Fixture() {
    source.byId!['finished'] = false;
  }

  late final resolver = HomeSeriesResumeResolver(
    signals: source.repository,
    trackers: tracker.repository,
    policies: HomeTrackingPolicyRepository(
      readTargets: (_) async {
        policyReads++;
        await policyGate?.future;
        return {};
      },
      readProgress: () async => policy,
      hasCredential: (_, _) async => true,
      fallbackDisconnected: (_, _) async => false,
      readTicks: () async => {},
      isOwnerCurrent: () => owner,
    ),
    findNextEpisode:
        (id, season, episode, {required preferBuiltIn, catalogItem}) async {
          if (!guideEntered.isCompleted) guideEntered.complete();
          return guideGate == null ? null : await guideGate!.future;
        },
    readRevision: (provider, id) => revisions[provider] ?? 0,
    isOwnerCurrent: () => owner,
    now: () => time,
    log: logs.add,
  );

  Future<HomeSeriesResumeResult?> read({
    StremioMeta item = signals.show,
    bool builtIn = false,
    bool traktSource = false,
  }) => resolver.resolve(
    item,
    availability: () {
      availabilityReads++;
      return available;
    },
    cachedTrakt: () => signals.card(),
    isCurrent: () => view,
    preferBuiltIn: builtIn,
    isTraktSource: traktSource,
  );
  int get localReads => source.calls.where((call) => call == 'id:tt123').length;
}

void main() {
  test(
    '512-entry cache evicts least recently used without flushing hot titles',
    () async {
      final f = Fixture();
      StremioMeta item(int index) =>
          StremioMeta(id: 'tt$index', type: 'series', name: 'Show $index');
      for (var i = 0; i < 512; i++) {
        await f.read(item: item(i));
      }
      await f.read(item: item(0));
      await f.read(item: item(512));
      await f.read(item: item(0));
      expect(f.source.calls.where((call) => call == 'id:tt0').length, 1);
      await f.read(item: item(1));
      expect(f.source.calls.where((call) => call == 'id:tt1').length, 2);
    },
  );

  test(
    '45-second cache does not renew on hits; policy remains fresh',
    () async {
      final f = Fixture();
      final first = await f.read();
      expect(first!.season, 2);
      f.time = f.time.add(const Duration(milliseconds: 44999));
      expect(await f.read(), first);
      expect(f.localReads, 1);
      f.time = f.time.add(const Duration(milliseconds: 1));
      await f.read();
      expect(f.localReads, 2);
      expect(f.policyReads, 3);
    },
  );

  test('TTL starts before signal I/O, not at completion', () async {
    final f = Fixture();
    f.source.gateStep = 'id:tt123';
    final pending = f.read();
    await f.source.entered.future;
    f.time = f.time.add(const Duration(seconds: 30));
    f.source.release.complete();
    await pending;
    f.time = f.time.add(const Duration(seconds: 15));
    await f.read();
    expect(f.localReads, 2);
  });

  test(
    'revision, auth, source and guide configuration invalidate cached results',
    () async {
      final f = Fixture();
      await f.read();
      for (final provider in ['trakt', 'simkl', 'mdblist', 'local']) {
        f.revisions[provider] = 1;
        await f.read();
      }
      expect(f.localReads, 5);
      f.available = (trakt: true, simkl: false, mdblist: false);
      await f.read();
      await f.read(builtIn: true);
      await f.read(builtIn: true, traktSource: true);
      expect(f.localReads, 8);
      // A dedicated tracker policy must not reuse a local answer.
      f.policy = WatchProgressSource.trakt;
      final result = await f.read(builtIn: true, traktSource: true);
      expect(result!.sourcePrio, 0);
      expect(f.source.calls, contains('select'));
    },
  );

  test('availability is evaluated after policy settles', () async {
    final f = Fixture()..policyGate = Completer<void>();
    f.policy = WatchProgressSource.smart;
    final pending = f.read();
    expect(f.availabilityReads, 0);
    f.available = (trakt: true, simkl: false, mdblist: false);
    f.policyGate!.complete();
    await pending;
    expect(f.source.calls, contains('select'));
    expect(f.logs.join(), contains('traktAuth=true simklAuth=false'));
  });

  for (final retirement in ['clear', 'dispose', 'profile', 'view']) {
    test(
      '$retirement during read returns cancellation and cannot refill cache',
      () async {
        final f = Fixture();
        f.source.gateStep = 'id:tt123';
        final pending = f.read();
        await f.source.entered.future;
        switch (retirement) {
          case 'clear':
            f.resolver.clear();
          case 'dispose':
            f.resolver.dispose();
          case 'profile':
            f.owner = false;
          case 'view':
            f.view = false;
        }
        f.source.release.complete();
        expect(await pending, isNull);
        if (retirement == 'clear') {
          expect(await f.read(), isNotNull);
          expect(f.localReads, 2);
        } else {
          expect(await f.read(), isNull);
          expect(f.localReads, 1);
        }
      },
    );
  }

  test('clear while policy loads prevents all signal reads', () async {
    final f = Fixture()..policyGate = Completer<void>();
    final pending = f.read();
    f.resolver.clear();
    f.policyGate!.complete();
    expect(await pending, isNull);
    expect(f.source.calls, isEmpty);
    expect(f.availabilityReads, 0);
  });

  test(
    'disposal during episode advancement rejects the late guide answer',
    () async {
      final f = Fixture();
      f.source.byId!['finished'] = true;
      f.guideGate = Completer<({int season, int episode})?>();
      final pending = f.read();
      await f.guideEntered.future;
      f.resolver.dispose();
      f.guideGate!.complete((season: 2, episode: 4));
      expect(await pending, isNull);
    },
  );

  test(
    'concurrent tracker error is observed while an earlier read is pending',
    () async {
      final f = Fixture()..policy = WatchProgressSource.smart;
      f.available = (trakt: true, simkl: true, mdblist: true);
      f.source.gateStep = 'select';
      f.source.failureStep = 'paused:tt123';
      final pending = f.read();
      final assertion = expectLater(pending, throwsA(same(f.source.error)));
      await f.source.entered.future;
      await Future<void>.delayed(Duration.zero);
      expect(
        f.source.calls,
        containsAll(['select', 'paused:tt123', 'id:tt123', 'next:tt123']),
      );
      expect(f.tracker.calls, ['mdb']);
      f.source.release.complete();
      await assertion;
      f.source.failureStep = null;
      await f.read();
      expect(f.localReads, 2);
    },
  );
}

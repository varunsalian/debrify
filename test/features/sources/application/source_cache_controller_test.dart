import 'package:debrify/features/sources/application/source_cache_controller.dart';
import 'package:debrify/features/sources/application/source_cache_dependencies.dart';
import '../fakes/fake_source_cache_repository.dart';
import 'package:debrify/features/sources/models/source_cache_state.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent row(String hash, {bool real = true}) => Torrent(
  rowid: 0,
  infohash: hash,
  name: hash,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  hasRealInfoHash: real,
);

void main() {
  late FakeSourceCacheRepository repository;
  late ProviderContainer container;
  late SourceCacheController controller;
  late ProviderSubscription<SourceCacheState> subscription;
  late SourcesSession session;
  setUp(() {
    repository = FakeSourceCacheRepository();
    session = SourcesSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      selection: const AdvancedSearchSelection(
        imdbId: 'tt-fixture',
        title: 'Fixture',
        isSeries: true,
      ),
    );
    container = ProviderContainer.test(
      overrides: [
        sourceCacheRepositoryProvider.overrideWith((ref, key) => repository),
      ],
    );
    subscription = container.listen(sourceCacheProvider(session), (_, _) {});
    controller = container.read(sourceCacheProvider(session).notifier);
  });
  Future<FakeSourceCacheSession> configure({
    bool tb = true,
    bool pm = true,
  }) async {
    final cache = FakeSourceCacheSession(
      torboxEnabled: tb,
      premiumizeEnabled: pm,
    );
    final pending = controller.configure();
    repository.opens.last.complete(cache);
    expect(await pending, isTrue);
    return cache;
  }

  test(
    'initialization performs no IO and checks wait for explicit configuration',
    () async {
      expect(repository.opens, isEmpty);
      await controller.check([row('a')]);
      expect(repository.opens, isEmpty);
      final cache = await configure(tb: false, pm: false);
      await controller.check([row('a')]);
      expect(cache.tb, isEmpty);
      expect(cache.pm, isEmpty);
    },
  );

  test(
    'normalizes real hashes, preserves duplicates and sequential repaint timing',
    () async {
      final cache = await configure();
      final pending = controller.check([
        row(' A '),
        row('a'),
        row(' '),
        row('synthetic', real: false),
        row('b'),
      ]);
      expect(cache.tb.single.$1, ['a', 'a', 'b']);
      expect(cache.pm, isEmpty);
      cache.tb.single.$2.complete({'a'});
      await Future<void>.delayed(Duration.zero);
      expect(subscription.read().label(row(' A ')), 'TB');
      expect(subscription.read().label(row('a', real: false)), isNull);
      expect(subscription.read().repaintRevision, 0);
      expect(cache.pm.single.$1, ['a', 'a', 'b']);
      cache.pm.single.$2.complete([true, true]);
      await pending;
      expect(subscription.read().label(row('a')), 'TB | PM');
      expect(subscription.read().premiumize['b'], isFalse);
      expect(subscription.read().repaintRevision, 1);
      expect(() => subscription.read().torbox.clear(), throwsUnsupportedError);
      await controller.check([row('a'), row('b')]);
      expect(cache.tb, hasLength(1));
      expect(cache.pm, hasLength(1));
    },
  );

  for (final fails in ['torbox', 'premiumize']) {
    test(
      '$fails failure retains other badges and keeps hashes retryable',
      () async {
        final cache = await configure();
        final initial = controller.check([row('a')]);
        if (fails == 'torbox') {
          cache.tb.last.$2.completeError(StateError('fixture'));
        } else {
          cache.tb.last.$2.complete({'a'});
        }
        await Future<void>.delayed(Duration.zero);
        if (fails == 'premiumize') {
          cache.pm.last.$2.completeError(StateError('fixture'));
        } else {
          cache.pm.last.$2.complete([true]);
        }
        await initial;
        expect(
          subscription.read().label(row('a')),
          fails == 'torbox' ? 'PM' : 'TB',
        );
        final retry = controller.check([row('a'), row('b')]);
        expect(cache.tb.last.$1, ['a', 'b']);
        cache.tb.last.$2.complete({'a', 'b'});
        await Future<void>.delayed(Duration.zero);
        cache.pm.last.$2.complete([true, false]);
        await retry;
        expect(subscription.read().label(row('a')), 'TB | PM');
        expect(subscription.read().label(row('b')), 'TB');
        await controller.check([row('a'), row('b')]);
        expect(cache.tb, hasLength(2));
      },
    );
  }

  test(
    'batches merge badges while a re-search clears maps and memoization',
    () async {
      final cache = await configure(pm: false);
      for (final hash in ['a', 'b']) {
        final pending = controller.check([row(hash)]);
        cache.tb.last.$2.complete({hash});
        await pending;
      }
      expect(subscription.read().torbox, {'a': true, 'b': true});
      controller.beginSearch();
      expect(subscription.read().torbox, isEmpty);
      final repeated = controller.check([row('a')]);
      expect(cache.tb, hasLength(3));
      cache.tb.last.$2.complete({});
      await repeated;
      expect(subscription.read().label(row('a')), isNull);
      expect(repository.opens, hasLength(1));
    },
  );

  for (final retire in ['query', 'profile', 'dispose', 'dependency']) {
    for (final failure in [false, true]) {
      test(
        '$retire rejects delayed TorBox ${failure ? 'failure' : 'success'} before Premiumize dispatch',
        () async {
          final cache = await configure();
          final pending = controller.check([row('a')]);
          if (retire == 'query') {
            controller.beginSearch();
          } else if (retire == 'profile') {
            repository.isCurrent = false;
          } else if (retire == 'dispose') {
            container.dispose();
          } else {
            repository = FakeSourceCacheRepository();
            container.invalidate(sourceCacheRepositoryProvider(session));
            expect(subscription.read().torbox, isEmpty);
          }
          if (failure) {
            cache.tb.single.$2.completeError(StateError('fixture'));
          } else {
            cache.tb.single.$2.complete({'a'});
          }
          await pending;
          expect(cache.pm, isEmpty);
          if (retire != 'dispose') {
            expect(subscription.read().torbox, isEmpty);
          }
        },
      );
    }
  }

  test(
    'configuration arriving after a new search still configures that search',
    () async {
      final cache = FakeSourceCacheSession(premiumizeEnabled: false);
      final pending = controller.configure();
      controller.beginSearch();
      repository.opens.single.complete(cache);
      expect(await pending, isTrue);
      final check = controller.check([row('a')]);
      cache.tb.single.$2.complete({'a'});
      await check;
      expect(subscription.read().label(row('a')), 'TB');
    },
  );

  for (final retire in ['profile', 'dispose']) {
    for (final failure in [false, true]) {
      test(
        '$retire rejects late credential ${failure ? 'error' : 'configuration'}',
        () async {
          final pending = controller.configure();
          if (retire == 'profile') {
            repository.isCurrent = false;
          } else {
            container.dispose();
          }
          if (failure) {
            repository.opens.single.completeError(StateError('fixture'));
          } else {
            repository.opens.single.complete(FakeSourceCacheSession());
          }
          expect(await pending, isFalse);
          if (retire != 'dispose') {
            expect(subscription.read().torboxEnabled, isFalse);
          }
        },
      );
    }
  }

  test('older configuration cannot replace the latest one', () async {
    final old = controller.configure();
    await configure(tb: false, pm: false);
    repository.opens.first.complete(FakeSourceCacheSession());
    expect(await old, isFalse);
    expect(subscription.read().torboxEnabled, isFalse);
  });
}

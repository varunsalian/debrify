import 'package:debrify/features/search/data/memory_keyword_snapshot_repository.dart';
import 'package:debrify/features/search/models/keyword_cache_state.dart';
import 'package:debrify/features/search/models/keyword_providers.dart';
import 'package:debrify/features/search/models/keyword_results_state.dart';
import 'package:debrify/features/search/models/keyword_snapshot.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_test/flutter_test.dart';

import '../keyword_torrent_fixture.dart';

void main() {
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.clearAll();
  });
  tearDown(() {
    ProfileSessionMemory.clearAll();
    ProfileRuntime.debugReset();
  });

  MemoryKeywordSnapshotRepository repository() =>
      MemoryKeywordSnapshotRepository(
        owner: ProfileSessionMemory.captureOwner(),
      );
  KeywordSnapshot snapshot({
    String variant = 'search',
    String query = 'query',
  }) => KeywordSnapshot(
    variant: variant,
    query: query,
    projection: KeywordResultsState(
      all: [keywordTorrent(query)],
      results: [keywordTorrent(query)],
    ),
    cache: const KeywordCacheState.empty(),
    scrollOffset: 42,
  );

  test('fresh adapters borrow the same consume-once store', () {
    final saved = snapshot();
    repository().store(saved);
    for (var i = 0; i < 100; i++) {
      expect(repository().take('discover', allowed: true), isNull);
    }
    expect(repository().take('search', allowed: true), same(saved));
    expect(repository().take('search', allowed: true), isNull);
  });

  test('a different tab does not consume the matching variant snapshot', () {
    final saved = snapshot(variant: 'home');
    final repo = repository();
    repo.store(saved);
    expect(repo.take('search', allowed: true), isNull);
    expect(repo.take('home', allowed: true), same(saved));
  });

  test(
    'denied matching snapshot is consumed, but a wrong variant is retained',
    () {
      final saved = snapshot();
      final repo = repository();
      repo.store(saved);
      expect(repo.take('home', allowed: false), isNull);
      expect(repo.take('search', allowed: true), same(saved));
      repo.store(saved);
      expect(repo.take('search', allowed: false), isNull);
      expect(repo.take('search', allowed: true), isNull);
    },
  );

  test('empty query never restores', () {
    final repo = repository();
    repo.store(snapshot(query: ''));
    expect(repo.take('search', allowed: true), isNull);
  });

  test(
    'profile handoff rejects outgoing data and late outgoing stores/takes',
    () {
      final origin = ProfileScope(
        profileId: 'origin',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final incoming = ProfileScope(
        profileId: 'incoming',
        dataGeneration: 1,
        sessionEpoch: 2,
      );
      ProfileRuntime.initializeCommitted(origin);
      final old = repository();
      old.store(snapshot(query: 'private origin'));
      ProfileRuntime.publish(incoming);
      final active = repository();
      expect(active.take('search', allowed: true), isNull);
      final saved = snapshot(query: 'incoming');
      active.store(saved);
      old.store(snapshot(query: 'late outgoing'));
      expect(old.take('search', allowed: true), isNull);
      expect(active.take('search', allowed: true), same(saved));
    },
  );

  test(
    'lifecycle clear invalidates both retained data and the old adapter owner',
    () {
      final old = repository();
      old.store(snapshot());
      ProfileSessionMemory.clearAll();
      expect(repository().take('search', allowed: true), isNull);
      old.store(snapshot(query: 'stale revision'));
      expect(repository().take('search', allowed: true), isNull);
    },
  );

  test(
    'snapshot retains only the legacy persistent choices and immutable data',
    () {
      final row = keywordTorrent('Result', source: 'one');
      final filters = TorrentFilterState(qualities: {QualityTier.fullHd});
      final projection = KeywordResultsState(
        all: [row],
        results: [row],
        pending: [keywordTorrent('pending')],
        frozen: true,
        selectionMode: true,
        selected: {'Result'},
        filters: filters,
        sort: 'size',
        sortAscending: true,
        sourceTab: 'one',
        providers: KeywordProviders(
          directCounts: {},
          torrentCounts: {'one': 1},
          selectedDirect: {},
          selectedTorrent: {},
          seen: {'t:one'},
        ),
      );
      final cache = KeywordCacheState(
        badges: {
          'result': ['TB'],
        },
        cachedOnly: true,
      );
      final saved = KeywordSnapshot(
        variant: 'search',
        query: 'query',
        projection: projection,
        cache: cache,
        scrollOffset: 420,
      );
      repository().store(saved);
      final restored = repository().take('search', allowed: true)!;
      expect(restored.query, 'query');
      expect(restored.scrollOffset, 420);
      expect(restored.cache, same(cache));
      expect(restored.projection.all, [row]);
      expect(restored.projection.results, [row]);
      expect(restored.projection.filters, same(filters));
      expect(restored.projection.sort, 'size');
      expect(restored.projection.sortAscending, isTrue);
      expect(restored.projection.sourceTab, 'one');
      expect(restored.projection.providers.torrentCounts, {'one': 1});
      expect(restored.projection.providers.selectedTorrent, isEmpty);
      expect(restored.projection.pending, isNull);
      expect(restored.projection.frozen, isFalse);
      expect(restored.projection.selectionMode, isFalse);
      expect(restored.projection.selected, isEmpty);
      expect(restored.projection.providers.seen, isEmpty);
      expect(() => restored.projection.all.clear(), throwsUnsupportedError);
      expect(
        () => restored.cache.badges['result']!.clear(),
        throwsUnsupportedError,
      );
      expect(projection.frozen, isTrue);
      expect(projection.pending, isNotEmpty);
    },
  );
}

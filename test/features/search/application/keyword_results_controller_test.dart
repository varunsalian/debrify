import 'package:debrify/features/search/application/keyword_cache_controller.dart';
import 'package:debrify/features/search/application/search_providers.dart';
import 'package:debrify/features/search/application/keyword_result_snapshot.dart';
import 'package:debrify/features/search/application/keyword_results_controller.dart';
import 'package:debrify/features/search/models/keyword_cache_state.dart';
import 'package:debrify/features/search/models/keyword_results_state.dart';
import 'package:debrify/features/search/models/search_session.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_keyword_cache_repository.dart';
import '../fakes/fake_keyword_search_repository.dart';
import '../keyword_torrent_fixture.dart';

void main() {
  late FakeKeywordSearchRepository repository;
  late FakeKeywordCacheRepository cache;
  late ProviderContainer container;
  late SearchSession key;
  late KeywordResultsController controller;
  late ProviderSubscription<KeywordResultsState> subscription;
  KeywordResultsState current() => subscription.read();

  setUp(() {
    repository = FakeKeywordSearchRepository();
    cache = FakeKeywordCacheRepository();
    key = SearchSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container = ProviderContainer.test(
      overrides: [
        keywordSearchRepositoryProvider.overrideWith((ref, key) => repository),
        keywordCacheRepositoryProvider.overrideWith((ref, key) => cache),
      ],
    );
    container.listen(keywordCacheProvider(key), (_, _) {});
    subscription = container.listen(keywordResultsProvider(key), (_, _) {});
    controller = container.read(keywordResultsProvider(key).notifier);
  });

  test('present, freeze and adopt keep a stable displayed projection', () {
    final old = keywordTorrent('old', source: 'one');
    final added = keywordTorrent('added', source: 'two');
    controller.present([old]);
    final displayed = current().results;
    controller.freeze();
    controller.present([added, old]);
    expect(current().results, same(displayed));
    expect(current().all, [old]);
    expect(current().pending, [added, old]);
    expect(current().providers.torrentCounts, {'one': 1});
    expect(controller.adopt(), isTrue);
    expect(current().results, [added, old]);
    expect(current().pending, isNull);
    expect(current().frozen, isTrue);
    expect(current().providers.selectedTorrent, {'one', 'two'});
    expect(controller.adopt(), isFalse);
    expect(repository.requests, isEmpty);
    expect(cache.opens, 0);
  });

  test('provider unticks survive arrivals; vanished sources are forgotten', () {
    final a = keywordTorrent('a', source: 'one');
    final b = keywordTorrent('b', source: 'two');
    controller.present([a]);
    controller.toggleProvider(false, 'one');
    final unticked = current();
    controller.present([a, b]);
    expect(current().results, [b]);
    expect(current().providers.selectedTorrent, {'two'});
    expect(unticked.providers.selectedTorrent, isEmpty);
    controller.present([b]);
    controller.present([a, b]);
    expect(current().providers.selectedTorrent, {'one', 'two'});
  });

  test(
    'Direct and Torrent choices stay independent for the same source name',
    () {
      final torrent = keywordTorrent('torrent', source: 'shared');
      final direct = keywordTorrent(
        'direct',
        source: 'shared',
        type: StreamType.directUrl,
      );
      controller.present([torrent, direct]);
      controller.toggleProviderGroup(true);
      expect(current().results, [torrent]);
      expect(current().providers.selectedTorrent, {'shared'});
      controller.toggleProviderGroup(false);
      expect(current().results, isEmpty);
      controller.toggleProviderGroup(true);
      expect(current().results, [direct]);
    },
  );

  test(
    'final vanished tab clears against pending rows, filtering displayed rows',
    () {
      final a = keywordTorrent('a', source: 'one');
      final b = keywordTorrent('b', source: 'two');
      controller.present([a, b]);
      controller.freeze();
      controller.setSourceTab('two');
      expect(current().results, [b]);
      controller.present([a]);
      expect(current().sourceTab, 'two');
      expect(controller.finish(), isTrue);
      expect(current().sourceTab, isNull);
      expect(current().results, [a, b]);
      controller.adopt();
      expect(current().results, [a]);
      expect(controller.setSourceTab('missing'), isFalse);
    },
  );

  test('sort defaults and direction apply to the filtered displayed rows', () {
    final small = keywordTorrent('Small.1080p', seeders: 1, size: 10);
    final large = keywordTorrent('Large.2160p', seeders: 20, size: 100);
    controller.present([small, large]);
    controller.setSort('seeders');
    expect(current().sortAscending, isFalse);
    expect(current().results, [large, small]);
    controller.setSortAscending(true);
    expect(current().results, [small, large]);
    controller.setFilters(TorrentFilterState(qualities: {QualityTier.ultraHd}));
    expect(current().results, [large]);
    controller.setSort('relevance');
    expect(current().results, [large]);
    controller.setFilters(const TorrentFilterState.empty());
    expect(current().results, [small, large]);
  });

  test(
    'cache badges do not re-filter until explicit accepted completion',
    () async {
      final a = keywordTorrent('a');
      final b = keywordTorrent('b');
      controller.present([a, b]);
      final rows = current().results;
      final checker = container.read(keywordCacheProvider(key).notifier);
      cache.session.tb = (_) async => {'a'};
      await checker.begin(1);
      await checker.check([a, b], 1);
      expect(current().results, same(rows));
      expect(await checker.finish([a, b], 1), isTrue);
      expect(current().results, same(rows));
      controller.recompute();
      expect(current().results, [a]);
    },
  );

  test('bulk selection uses visible eligible rows and exact hash identity', () {
    final a = keywordTorrent('a', hash: 'HASH', source: 'one');
    final b = keywordTorrent('b', hash: 'hash', source: 'two');
    final direct = keywordTorrent('direct', type: StreamType.directUrl);
    final external = keywordTorrent('external', type: StreamType.externalUrl);
    controller.present([a, b, direct, external]);
    controller.setSelectionMode(true);
    controller.setSourceTab('one');
    controller.selectAll();
    expect(current().selected, {'HASH'});
    controller.setSourceTab(null);
    controller.selectAll();
    expect(current().selected, {'HASH', 'hash'});
    final selected = current().selected;
    controller.toggleSelection('hash');
    expect(current().selected, {'HASH'});
    expect(selected, {'HASH', 'hash'});
    controller.deselectAll();
    expect(current().selectionMode, isTrue);
    expect(current().selected, isEmpty);
    controller.setSelectionMode(false);
    expect(current().selectionMode, isFalse);
  });

  test(
    'begin resets per-search choices but retains hidden old rows and filters',
    () {
      final row = keywordTorrent('Result.1080p', source: 'one');
      final filters = TorrentFilterState(qualities: {QualityTier.fullHd});
      controller.present([row]);
      controller.setFilters(filters);
      controller.setSort('size');
      controller.freeze();
      controller.setSelectionMode(true);
      controller.selectAll();
      controller.present([keywordTorrent('pending')]);
      controller.begin();
      expect(current().all, [row]);
      expect(current().results, [row]);
      expect(current().filters, same(filters));
      expect(current().sort, 'size');
      expect(current().pending, isNull);
      expect(current().frozen, isFalse);
      expect(current().providers.seen, isEmpty);
      expect(current().selected, isEmpty);
      expect(current().selectionMode, isFalse);
    },
  );

  test(
    'clear empties rows and selections while retaining filter preferences',
    () {
      controller.present([keywordTorrent('a')]);
      controller.setSort('size');
      controller.freeze();
      controller.setSelectionMode(true);
      controller.selectAll();
      controller.clear();
      expect(current().all, isEmpty);
      expect(current().results, isEmpty);
      expect(current().pending, isNull);
      expect(current().selectionMode, isFalse);
      expect(current().selected, isEmpty);
      expect(current().sort, 'size');
    },
  );

  test('retired actions cannot mutate results or user choices', () {
    controller.present([keywordTorrent('a')]);
    final prior = current();
    repository.isCurrent = false;
    controller.begin();
    controller.present([keywordTorrent('private')]);
    controller.freeze();
    controller.adopt();
    controller.finish();
    controller.recompute();
    controller.setSourceTab('one');
    controller.setFilters(TorrentFilterState(qualities: {QualityTier.hd}));
    controller.setSort('name');
    controller.setSortAscending(true);
    controller.toggleProvider(false, 'one');
    controller.toggleProviderGroup(false);
    controller.setSelectionMode(true);
    controller.toggleSelection('a');
    controller.selectAll();
    controller.deselectAll();
    expect(current(), same(prior));
  });

  test('snapshot fold is pure and preserves legacy displayed rows', () {
    final old = keywordTorrent('old', source: 'one');
    final added = keywordTorrent('added', source: 'two');
    controller.present([old]);
    controller.freeze();
    controller.present([added]);
    final before = current();
    final snapshot = keywordResultsSnapshot(before);
    expect(snapshot.all, [added]);
    expect(snapshot.results, [old]);
    expect(snapshot.pending, isNull);
    expect(snapshot.providers.torrentCounts, {'two': 1});
    expect(current(), same(before));
    expect(current().all, [old]);
    expect(current().pending, [added]);
    expect(cache.opens, 0);
  });

  test('seed is immutable and restores without IO or recomputation', () {
    final rows = [keywordTorrent('old')];
    final seed = KeywordResultsState(all: rows, results: rows, sort: 'size');
    rows.clear();
    final seededKey = SearchSession(
      owner: key.owner,
      viewIdentity: Object(),
      initialKeywordResults: seed,
      initialKeywordCache: KeywordCacheState(badges: {}, cachedOnly: true),
    );
    final seeded = container.listen(
      keywordResultsProvider(seededKey),
      (_, _) {},
    );
    expect(seeded.read().results.single.name, 'old');
    expect(seeded.read().sort, 'size');
    expect(() => seeded.read().all.clear(), throwsUnsupportedError);
    expect(() => seeded.read().selected.add('x'), throwsUnsupportedError);
    expect(cache.opens, 0);
    seeded.close();
  });
}

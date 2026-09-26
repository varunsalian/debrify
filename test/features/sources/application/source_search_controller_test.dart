import 'dart:async';
import 'package:debrify/features/sources/application/source_cache_controller.dart';
import 'package:debrify/features/sources/application/source_cache_dependencies.dart';
import 'package:debrify/features/sources/application/source_results_controller.dart';
import 'package:debrify/features/sources/application/source_retry_controller.dart';
import 'package:debrify/features/sources/data/source_cache_repository.dart';
import 'package:debrify/features/sources/application/source_search_controller.dart';
import 'package:debrify/features/sources/application/source_search_dependencies.dart';
import 'package:debrify/features/sources/data/source_search_repository.dart';
import 'package:debrify/features/sources/models/source_search_request.dart';
import 'package:debrify/features/sources/models/source_search_result.dart';
import 'package:debrify/features/sources/models/source_search_state.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const selection = AdvancedSearchSelection(
  imdbId: 'tt1',
  isSeries: false,
  title: 'One',
);
Torrent row(String name) => Torrent(
  rowid: 0,
  infohash: name,
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: 'engine',
);
AddonSearchStatus status(String key) => AddonSearchStatus(
  addonId: 'addon',
  addonKey: key,
  name: key,
  sourceKey: key,
  count: 0,
  error: 'timeout',
);

class PendingSearch {
  PendingSearch(this.batch, this.iptv, this.active);
  final SourceSearchBatch batch;
  final void Function(IptvSourceResult) iptv;
  final bool Function() active;
  final result = Completer<SourceSearchResult?>();
}

class SearchRepository implements SourceSearchRepository {
  SearchRepository(this.session);
  final SourcesSession session;
  final List<PendingSearch> calls = [];
  final retries = <Completer<List<Torrent>?>>[];
  @override
  bool get isCurrent => session.owner == ProfileSessionMemory.captureOwner();
  @override
  Future<SourceSearchResult?> search(
    SourceSearchRequest request, {
    required SourceSearchBatch onBatch,
    required void Function(IptvSourceResult) onIptvResult,
    required bool Function() shouldContinue,
  }) {
    final call = PendingSearch(onBatch, onIptvResult, shouldContinue);
    calls.add(call);
    return call.result.future;
  }

  @override
  Future<List<Torrent>?> retry(
    AdvancedSearchSelection selection,
    String requestKey, {
    required bool Function() shouldContinue,
  }) {
    final pending = Completer<List<Torrent>?>();
    retries.add(pending);
    return pending.future;
  }
}

class CacheRepository implements SourceCacheRepository, SourceCacheSession {
  final checks = <Completer<Set<String>>>[];
  @override
  bool get isCurrent => true;
  @override
  bool get torboxEnabled => true;
  @override
  bool get premiumizeEnabled => false;
  @override
  Future<SourceCacheSession> open() async => this;
  @override
  Future<Set<String>> torbox(List<String> hashes) {
    final pending = Completer<Set<String>>();
    checks.add(pending);
    return pending.future;
  }

  @override
  Future<List<bool>> premiumize(List<String> hashes) =>
      throw StateError('Disabled');
}

void main() {
  late ProviderContainer container;
  late SourcesSession session;
  late SearchRepository repository;
  late CacheRepository cacheRepository;
  late SourceSearchController controller;
  late ProviderSubscription<SourceSearchState> subscription;
  late List<(List<Torrent>, bool)> rows;
  late List<List<Torrent>> cacheBatches;
  setUp(() {
    session = SourcesSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      selection: selection,
    );
    repository = SearchRepository(session);
    cacheRepository = CacheRepository();
    container = ProviderContainer.test(
      overrides: [
        sourceCacheRepositoryProvider.overrideWith(
          (ref, key) => cacheRepository,
        ),
        sourceSearchRepositoryProvider.overrideWith(
          (ref, session) => repository,
        ),
      ],
    );
    subscription = container.listen(sourceSearchProvider(session), (_, _) {});
    controller = container.read(sourceSearchProvider(session).notifier);
    rows = [];
    cacheBatches = [];
  });
  Future<void> search() => controller.search(
    SourceSearchRequest(selection: selection),
    priority: ['second', 'first'],
    aliases: {},
    onRows: (batch, complete) => rows.add((batch, complete)),
    onBatchAccepted: cacheBatches.add,
  );

  test(
    'construction is inert; batches stream and final rows are authoritative',
    () async {
      expect(repository.calls, isEmpty);
      final pending = search();
      final call = repository.calls.single;
      final early = row('early');
      final finalRow = row('final');
      call.batch('engine', []);
      expect(rows, isEmpty);
      call.batch('engine', [early]);
      expect(rows.single.$1, [same(early)]);
      expect(rows.single.$2, isFalse);
      expect(subscription.read().searching, isTrue);
      expect(cacheBatches, [
        [early],
      ]);
      call.result.complete(SourceSearchResult(torrents: [finalRow]));
      await pending;
      expect(rows.last.$1, [same(finalRow)]);
      expect(rows.last.$2, isTrue);
      expect(subscription.read().searching, isFalse);
      call.batch('engine', [early]);
      expect(rows, hasLength(2));
      expect(cacheBatches, hasLength(1));
      expect(call.active(), isFalse);
    },
  );

  test(
    'IPTV can expose status before rows; final statuses follow priority',
    () async {
      final pending = search();
      final call = repository.calls.single;
      const early = IptvSourceResult('one', 'One', 'Loading', []);
      const finalStatus = IptvSourceResult('two', 'Two', 'Empty', []);
      call.iptv(early);
      expect(subscription.read().iptv, [early]);
      expect(rows, isEmpty);
      call.result.complete(
        SourceSearchResult(
          iptv: [finalStatus],
          addonStatuses: [status('first'), status('second')],
        ),
      );
      await pending;
      expect(subscription.read().iptv, [finalStatus]);
      expect(subscription.read().addonStatuses.map((s) => s.sourceKey), [
        'second',
        'first',
      ]);
      expect(
        () => subscription.read().addonStatuses.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'new search rejects old batches, IPTV, completion and loading changes',
    () async {
      final old = search();
      final first = repository.calls.single;
      final next = search();
      first.batch('engine', [row('old')]);
      first.iptv(const IptvSourceResult('old', 'Old', '', []));
      first.result.complete(SourceSearchResult(torrents: [row('old')]));
      await old;
      expect(rows, isEmpty);
      expect(subscription.read().iptv, isEmpty);
      expect(subscription.read().searching, isTrue);
      repository.calls.last.result.complete(SourceSearchResult());
      await next;
      expect(rows, hasLength(1));
    },
  );

  test(
    'current error retains IPTV state and does not automatically retry',
    () async {
      final pending = search();
      final call = repository.calls.single;
      const iptv = IptvSourceResult('one', 'One', '', []);
      call.iptv(iptv);
      call.result.completeError(StateError('fixture'));
      await pending;
      expect(subscription.read().searching, isFalse);
      expect(subscription.read().error, contains('fixture'));
      expect(subscription.read().iptv, [iptv]);
      await Future<void>.delayed(Duration.zero);
      expect(repository.calls, hasLength(1));
    },
  );

  test(
    'retry merges original batches, not the authoritative final-only rows',
    () async {
      final pending = search();
      final early = row('early');
      final finalOnly = row('final');
      repository.calls.single.batch('engine', [early]);
      repository.calls.single.result.complete(
        SourceSearchResult(
          torrents: [finalOnly],
          addonStatuses: [status('first'), status('second')],
        ),
      );
      await pending;
      final retry = row('retry');
      expect(controller.acceptRetry(status('first'), [retry]), [
        same(early),
        same(retry),
      ]);
      expect(subscription.read().addonStatuses.last.failed, isFalse);
      expect(subscription.read().addonStatuses.first.failed, isTrue);
      expect(controller.acceptRetry(status('second'), []), isNull);
      expect(subscription.read().addonStatuses.first.failed, isFalse);
    },
  );

  test('caller cancellation rejects work before provider disposal', () async {
    var mounted = true;
    final pending = controller.search(
      SourceSearchRequest(selection: selection),
      priority: [],
      aliases: {},
      shouldContinue: () => mounted,
      onRows: (batch, complete) => rows.add((batch, complete)),
      onBatchAccepted: cacheBatches.add,
    );
    final call = repository.calls.single;
    mounted = false;
    expect(call.active(), isFalse);
    call.batch('engine', [row('late')]);
    call.iptv(const IptvSourceResult('late', 'Late', '', []));
    call.result.complete(SourceSearchResult(torrents: [row('late')]));
    await pending;
    expect(rows, isEmpty);
    expect(cacheBatches, isEmpty);
    expect(subscription.read().iptv, isEmpty);
  });

  test(
    'retry batch accumulation snapshots input and clears on a new search',
    () async {
      final pending = search();
      final early = row('early');
      final input = [early];
      repository.calls.single.batch('engine', input);
      input.clear();
      repository.calls.single.result.complete(SourceSearchResult());
      await pending;
      final retry = row('retry');
      expect(controller.acceptRetry(status('first'), [retry]), [
        same(early),
        same(retry),
      ]);
      final next = search();
      repository.calls.last.result.complete(SourceSearchResult());
      await next;
      final fresh = row('fresh');
      expect(controller.acceptRetry(status('first'), [fresh]), [same(fresh)]);
    },
  );

  for (final retirement in ['profile', 'dispose', 'dependency', 'new search']) {
    test('$retirement rejects stale errors and subsequent callbacks', () async {
      final pending = search();
      final call = repository.calls.single;
      Future<void>? next;
      if (retirement == 'profile') {
        ProfileSessionMemory.clearAll();
      } else if (retirement == 'dispose') {
        container.dispose();
      } else if (retirement == 'dependency') {
        repository = SearchRepository(session);
        cacheRepository = CacheRepository();
        container.invalidate(sourceSearchRepositoryProvider(session));
        subscription.read();
      } else {
        next = search();
      }
      call.batch('engine', [row('late')]);
      call.iptv(const IptvSourceResult('late', 'Late', '', []));
      call.result.completeError(StateError('stale'));
      await pending;
      expect(rows, isEmpty);
      expect(cacheBatches, isEmpty);
      expect(call.active(), isFalse);
      if (retirement != 'dispose') expect(subscription.read().error, isNull);
      if (next != null) {
        repository.calls.last.result.complete(SourceSearchResult());
        await next;
      }
    });
  }
  test(
    'preparation resets cache/retry/results in order and retires old work',
    () async {
      final cacheState = container.listen(
        sourceCacheProvider(session),
        (_, _) {},
      );
      final retryState = container.listen(
        sourceRetryProvider(session),
        (_, _) {},
      );
      final resultState = container.listen(
        sourceResultsProvider(session),
        (_, _) {},
      );
      final cache = container.read(sourceCacheProvider(session).notifier);
      final retry = container.read(sourceRetryProvider(session).notifier);
      final results = container.read(sourceResultsProvider(session).notifier);
      await cache.configure();
      final previous = row('previous');
      final initialCheck = cache.check([previous]);
      cacheRepository.checks.last.complete({'previous'});
      await initialCheck;
      expect(cacheState.read().label(previous), 'TB');
      final lateCache = cache.check([row('late')]);
      final oldRetry = retry.retry(selection, status('addon'));
      results.display([previous]);
      results.selectProvider('engine:keep');
      results.freeze();
      results.bufferIfFrozen([row('pending')]);
      final order = <String>[];
      container.listen(
        sourceCacheProvider(session),
        (_, _) => order.add('cache'),
      );
      container.listen(
        sourceRetryProvider(session),
        (_, _) => order.add('retry'),
      );
      container.listen(
        sourceResultsProvider(session),
        (_, _) => order.add('results'),
      );

      expect(controller.prepareSearch(), isTrue);
      expect(order, ['cache', 'retry', 'results']);
      expect(repository.calls, isEmpty);
      expect(cacheState.read().label(previous), isNull);
      expect(cacheState.read().torboxEnabled, isTrue);
      expect(retryState.read(), isEmpty);
      expect(resultState.read().displayed, isEmpty);
      expect(resultState.read().pending, isNull);
      expect(resultState.read().frozen, isFalse);
      expect(resultState.read().toolbar.sourceFilter, 'engine:keep');

      final newRetry = retry.retry(selection, status('addon'));
      repository.retries.first.complete([row('stale')]);
      cacheRepository.checks.last.complete({'late'});
      expect(await oldRetry, isNull);
      await lateCache;
      expect(retryState.read(), {'addon'});
      expect(cacheState.read().torbox, isEmpty);
      final currentRows = [row('current')];
      repository.retries.last.complete(currentRows);
      expect(await newRetry, same(currentRows));
      expect(retryState.read(), isEmpty);
      final repeat = cache.check([previous]);
      expect(cacheRepository.checks, hasLength(3));
      cacheRepository.checks.last.complete({'previous'});
      await repeat;
      expect(cacheState.read().label(previous), 'TB');
    },
  );

  for (final retirement in ['profile', 'dispose']) {
    test('$retirement rejects preparation before provider access', () {
      if (retirement == 'profile') {
        ProfileSessionMemory.clearAll();
        addTearDown(ProfileSessionMemory.debugReset);
      } else {
        container.dispose();
      }
      expect(controller.prepareSearch(), isFalse);
      expect(cacheRepository.checks, isEmpty);
      expect(repository.calls, isEmpty);
      expect(repository.retries, isEmpty);
    });
  }

  test('explicit child preparation retains parent result state', () {
    container.listen(sourceResultsProvider(session), (_, _) {});
    final parentResults = container.read(
      sourceResultsProvider(session).notifier,
    );
    final original = row('parent');
    parentResults.display([original]);
    parentResults.freeze();
    final child = ProviderContainer.test(
      parent: container,
      overrides: [
        sourceSearchProvider(
          session,
        ).overrideWith(() => SourceSearchController(session)),
        sourceCacheProvider(
          session,
        ).overrideWith(() => SourceCacheController(session)),
        sourceRetryProvider(
          session,
        ).overrideWith(() => SourceRetryController(session)),
        sourceResultsProvider(
          session,
        ).overrideWith(() => SourceResultsController(session)),
      ],
    );
    child.listen(sourceSearchProvider(session), (_, _) {});
    child.listen(sourceResultsProvider(session), (_, _) {});
    child.read(sourceResultsProvider(session).notifier).display([row('child')]);
    expect(
      child.read(sourceSearchProvider(session).notifier).prepareSearch(),
      isTrue,
    );
    expect(child.read(sourceResultsProvider(session)).displayed, isEmpty);
    expect(container.read(sourceResultsProvider(session)).displayed, [
      same(original),
    ]);
    expect(container.read(sourceResultsProvider(session)).frozen, isTrue);
  });
}

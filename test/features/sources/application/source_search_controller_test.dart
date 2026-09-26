import 'dart:async';
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
  }) => throw UnimplementedError();
}

void main() {
  late ProviderContainer container;
  late SourcesSession session;
  late SearchRepository repository;
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
    container = ProviderContainer.test(
      overrides: [
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
}

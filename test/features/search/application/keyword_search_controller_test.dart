import 'dart:async';

import 'package:debrify/features/search/application/keyword_cache_dependencies.dart';
import 'package:debrify/features/search/application/keyword_search_controller.dart';
import 'package:debrify/features/search/application/keyword_search_dependencies.dart';
import 'package:debrify/features/search/data/keyword_cache_repository.dart';
import 'package:debrify/features/search/models/keyword_search_state.dart';
import 'package:debrify/features/search/models/search_session.dart';
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
  late KeywordSearchController controller;
  late ProviderSubscription<KeywordSearchState> subscription;
  KeywordSearchState current() => subscription.read();
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    repository = FakeKeywordSearchRepository();
    cache = FakeKeywordCacheRepository();
    key = SearchSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      initialKeywordQuery: 'restored',
    );
    container = ProviderContainer.test(
      overrides: [
        keywordSearchRepositoryProvider.overrideWith((ref, key) => repository),
        keywordCacheRepositoryProvider.overrideWith((ref, key) => cache),
      ],
    );
    subscription = container.listen(keywordSearchProvider(key), (_, _) {});
    controller = container.read(keywordSearchProvider(key).notifier);
  });

  test('construction restores query without starting engines or cache IO', () {
    expect(current().query, 'restored');
    expect(current().searching, isFalse);
    expect(current().loading, isFalse);
    expect(repository.requests, isEmpty);
    expect(cache.opens, 0);
  });

  test('cache configuration resolves before engines start', () async {
    final config = Completer<KeywordCacheSession>();
    cache.configure = () => config.future;
    final search = controller.search('query');
    expect(current().loading, isTrue);
    expect(current().query, 'query');
    await settle();
    expect(repository.requests, isEmpty);
    config.complete(cache.session);
    await settle();
    expect(repository.requests.single.query, 'query');
    repository.requests.single.complete([]);
    await search;
    expect(current().status, KeywordSearchStatus.complete);
    expect(current().error, isNull);
    expect(current().loading, isFalse);
  });

  test(
    'batches merge on arrival; completion replaces them and closes stream',
    () async {
      final search = controller.search('query');
      await settle();
      final request = repository.requests.single;
      request.onBatch('empty', []);
      expect(current().loading, isTrue);
      final low = keywordTorrent('low', hash: 'a', seeders: 1);
      final high = keywordTorrent('high', hash: 'a', seeders: 50);
      final other = keywordTorrent('other', hash: 'b', seeders: 10);
      request.onBatch('first', [low]);
      final first = current();
      expect(first.results, [low]);
      expect(first.loading, isFalse);
      expect(first.searching, isTrue);
      request.onBatch('second', [other, high]);
      expect(current().results, [high, other]);
      expect(first.results, [low]);
      expect(() => current().results!.clear(), throwsUnsupportedError);
      await settle();
      expect(cache.session.torboxCalls, [
        ['a'],
        ['b', 'a'],
      ]);
      request.complete([
        other,
      ]); // e.g. an authoritative timeout/dedupe difference
      await search;
      expect(current().results, [other]);
      expect(current().searching, isFalse);
      request.onBatch('late timed-out engine', [high]);
      expect(current().results, [other]);
      expect(cache.session.torboxCalls, hasLength(2));
    },
  );

  test('new query rejects old batches, completion and failure', () async {
    final oldSearch = controller.search('old');
    await settle();
    final old = repository.requests.single;
    final search = controller.search('new');
    await settle();
    old.onBatch('late', [keywordTorrent('old')]);
    old.completion.completeError(Exception('old failure'));
    await oldSearch;
    expect(current().query, 'new');
    expect(current().loading, isTrue);
    expect(current().error, isNull);
    expect(cache.session.torboxCalls, isEmpty);
    repository.requests.last.complete([keywordTorrent('new')]);
    await search;
    expect(current().results!.single.name, 'new');
  });

  test('superseded configuration never starts its engines', () async {
    final config = Completer<KeywordCacheSession>();
    cache.configure = () => config.future;
    final old = controller.search('old');
    cache.configure = null;
    final search = controller.search('new');
    await settle();
    config.complete(cache.session);
    await old;
    expect(repository.requests.map((request) => request.query), ['new']);
    repository.requests.single.complete([]);
    await search;
  });

  for (final retirement in ['clear', 'profile', 'dispose']) {
    test('$retirement rejects outstanding batches and completion', () async {
      final search = controller.search('old');
      await settle();
      final request = repository.requests.single;
      if (retirement == 'clear') {
        controller.clear();
      } else if (retirement == 'profile') {
        repository.isCurrent = false;
      } else {
        container.dispose();
      }
      request.onBatch('late', [keywordTorrent('late')]);
      request.complete([keywordTorrent('late')]);
      await search;
      expect(cache.session.torboxCalls, isEmpty);
      if (retirement == 'clear') {
        expect(current().query, isEmpty);
        expect(current().results, isNull);
        expect(current().loading, isFalse);
      }
    });
  }

  test(
    'retired initial action and empty query do not change state or call IO',
    () async {
      final initial = current();
      await controller.search('');
      repository.isCurrent = false;
      await controller.search('outgoing');
      expect(current(), same(initial));
      expect(repository.requests, isEmpty);
      expect(cache.opens, 0);
    },
  );

  for (final failure in ['disabled', 'all failed', 'partial success']) {
    test('completion distinguishes $failure', () async {
      final search = controller.search('query');
      await settle();
      repository.requests.single.complete(
        failure == 'partial success' ? [keywordTorrent('ok')] : [],
        anyEngineRan: failure != 'disabled',
        hasEngineErrors: failure != 'disabled',
      );
      await search;
      expect(current().loading, isFalse);
      expect(current().searching, isFalse);
      if (failure == 'partial success') {
        expect(current().error, isNull);
        expect(current().results!.single.name, 'ok');
      } else {
        expect(
          current().error,
          startsWith(
            failure == 'disabled'
                ? 'No sources enabled.'
                : 'Search failed on all sources.',
          ),
        );
      }
    });
  }

  for (final (error, message) in [
    (
      'SocketException (offline)',
      'Network error. Please check your connection.',
    ),
    ('Failed host lookup', 'Network error. Please check your connection.'),
    ('TimeoutException after a delay', 'Search timed out. Please try again.'),
    ('x' * 101, 'Search failed. Please try again.'),
    ('Short error', 'Short error'),
    // Existing replacement strips the embedded Exception prefix too. Keep it
    // during extraction rather than changing the legacy message contract.
    ('SocketException: offline', 'Socketoffline'),
    ('TimeoutException: waited', 'Timeoutwaited'),
  ]) {
    test('legacy error mapping: $message ($error)', () async {
      final search = controller.search('query');
      await settle();
      repository.requests.single.completion.completeError(Exception(error));
      await search;
      expect(current().error, message);
      expect(current().loading, isFalse);
      expect(current().searching, isFalse);
      await settle();
      expect(repository.requests, hasLength(1));
    });
  }

  test(
    'old successful completion cannot replace newer completed rows',
    () async {
      final old = controller.search('old');
      await settle();
      final newer = controller.search('new');
      await settle();
      repository.requests.last.complete([keywordTorrent('new')]);
      await newer;
      final accepted = current();
      repository.requests.first.complete([keywordTorrent('old')]);
      await old;
      expect(current(), same(accepted));
      expect(current().results!.single.name, 'new');
    },
  );

  test(
    'dependency rebuild rejects old work and does not restore bootstrap query',
    () async {
      final search = controller.search('pending');
      await settle();
      final old = repository.requests.single;
      repository = FakeKeywordSearchRepository();
      container.invalidate(keywordSearchRepositoryProvider(key));
      expect(current().query, isEmpty);
      old.onBatch('late', [keywordTorrent('late')]);
      old.complete([keywordTorrent('late')]);
      await search;
      expect(current().results, isNull);
      expect(current().searching, isFalse);
      expect(repository.requests, isEmpty);
    },
  );

  test('two views in the same profile own independent requests', () async {
    final otherKey = SearchSession(owner: key.owner, viewIdentity: Object());
    final otherSubscription = container.listen(
      keywordSearchProvider(otherKey),
      (_, _) {},
    );
    final other = container.read(keywordSearchProvider(otherKey).notifier);
    final first = controller.search('first view');
    final second = other.search('second view');
    await settle();
    repository.requests
        .singleWhere((request) => request.query == 'second view')
        .complete([keywordTorrent('second')]);
    await second;
    expect(current().loading, isTrue);
    expect(otherSubscription.read().results!.single.name, 'second');
    controller.clear();
    repository.requests
        .singleWhere((request) => request.query == 'first view')
        .complete([keywordTorrent('first')]);
    await first;
    expect(current().query, isEmpty);
    expect(otherSubscription.read().results!.single.name, 'second');
    otherSubscription.close();
  });

  test(
    'configuration failure ends loading without starting an engine',
    () async {
      cache.configure = () => Future.error(Exception('Config unavailable'));
      await controller.search('query');
      expect(current().error, 'Config unavailable');
      expect(current().loading, isFalse);
      expect(repository.requests, isEmpty);
      expect(cache.opens, 1);
    },
  );
}

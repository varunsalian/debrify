import 'dart:async';

import 'package:debrify/features/search/application/lists_search_controller.dart';
import 'package:debrify/features/search/application/lists_search_dependencies.dart';
import 'package:debrify/features/search/models/lists_search_session.dart';
import 'package:debrify/features/search/models/lists_search_state.dart';
import 'package:debrify/services/mdblist/mdblist_list_source.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_lists_search_repository.dart';

const first = MdblistListChoice(id: 1, name: 'First');
const second = MdblistListChoice(id: 2, name: 'Second');
typedef Result = MdblistResult<List<MdblistListChoice>>;

void main() {
  late ProviderContainer container;
  late FakeListsSearchRepository repository;
  late ListsSearchSession session;
  late ListsSearchController controller;
  late ProviderSubscription<ListsSearchState> subscription;
  ListsSearchState current() => container.read(listsSearchProvider(session));
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    repository = FakeListsSearchRepository();
    session = ListsSearchSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container = ProviderContainer.test(
      overrides: [
        listsSearchRepositoryProvider.overrideWith((ref, key) => repository),
      ],
    );
    subscription = container.listen(listsSearchProvider(session), (_, _) {});
    controller = container.read(listsSearchProvider(session).notifier);
  });

  test('construction and repeated reads do not issue a request', () {
    expect(current().query, isEmpty);
    expect(current().searching, isFalse);
    expect(
      container.read(listsSearchProvider(session).notifier),
      same(controller),
    );
    expect(repository.authCalls, 0);
    expect(repository.queries, isEmpty);
  });

  test(
    'trimmed explicit action publishes a snapshot without mutating results',
    () async {
      final items = [first, second];
      repository.fetch = (_) async => MdblistResult.success(items);
      expect(await controller.search('  movies  '), isTrue);
      expect(repository.queries, ['movies']);
      expect(current().query, 'movies');
      expect(current().results, [first, second]);
      expect(current().error, isNull);
      items.clear();
      expect(current().results, [first, second]);
      expect(() => current().results.clear(), throwsUnsupportedError);
    },
  );

  test('slow old results cannot clear a newer query loading flag', () async {
    final old = Completer<Result>();
    final next = Completer<Result>();
    repository.fetch = (query) => query == 'old' ? old.future : next.future;
    final oldAction = controller.search('old');
    await settle();
    final nextAction = controller.search('new');
    await settle();
    old.complete(const MdblistResult.success([first]));
    expect(await oldAction, isFalse);
    expect(current().query, 'new');
    expect(current().searching, isTrue);
    expect(current().results, isEmpty);
    next.complete(const MdblistResult.success([second]));
    expect(await nextAction, isTrue);
    expect(current().results, [second]);
  });

  test('slow old completion cannot replace fast new results', () async {
    final old = Completer<Result>();
    repository.fetch = (query) => query == 'old'
        ? old.future
        : Future.value(const MdblistResult.success([second]));
    final oldAction = controller.search('old');
    await settle();
    await controller.search('new');
    old.complete(const MdblistResult.success([first]));
    expect(await oldAction, isFalse);
    expect(current().results, [second]);
  });

  test(
    'superseded authentication cannot dispatch an old network request',
    () async {
      final oldAuth = Completer<bool>();
      repository.authenticate = () => oldAuth.future;
      final oldAction = controller.search('old');
      repository.authenticate = () async => true;
      await controller.search('new');
      oldAuth.complete(true);
      expect(await oldAction, isFalse);
      expect(repository.queries, ['new']);
    },
  );

  test(
    'clear invalidates pending results and resets error/query/loading',
    () async {
      final pending = Completer<Result>();
      repository.fetch = (_) => pending.future;
      final action = controller.search('movies');
      await settle();
      controller.clear();
      pending.complete(const MdblistResult.success([first]));
      expect(await action, isFalse);
      expect(current().query, isEmpty);
      expect(current().searching, isFalse);
      expect(current().error, isNull);
      expect(current().results, isEmpty);
      expect(await controller.search('  '), isFalse);
      expect(repository.queries, ['movies']);
    },
  );

  test(
    'profile expiration while authenticating prevents network dispatch',
    () async {
      final auth = Completer<bool>();
      repository.authenticate = () => auth.future;
      final action = controller.search('movies');
      repository.isCurrent = false;
      auth.complete(true);
      expect(await action, isFalse);
      expect(repository.queries, isEmpty);
    },
  );

  test(
    'profile expiration rejects results and subsequent stale actions',
    () async {
      final pending = Completer<Result>();
      repository.fetch = (_) => pending.future;
      final action = controller.search('movies');
      await settle();
      repository.isCurrent = false;
      controller.clear();
      pending.complete(const MdblistResult.success([first]));
      expect(await action, isFalse);
      expect(await controller.search('new'), isFalse);
      expect(current().results, isEmpty);
      expect(repository.queries, ['movies']);
    },
  );

  test(
    'last listener disposal releases the provider and ignores late results',
    () async {
      final pending = Completer<Result>();
      repository.fetch = (_) => pending.future;
      final action = controller.search('movies');
      await settle();
      subscription.close();
      await container.pump();
      expect(container.exists(listsSearchProvider(session)), isFalse);
      expect(container.exists(listsSearchRepositoryProvider(session)), isFalse);
      pending.complete(const MdblistResult.success([first]));
      expect(await action, isFalse);
    },
  );

  test(
    'same profile and query in different routes keep independent state',
    () async {
      final otherSession = ListsSearchSession(
        owner: session.owner,
        viewIdentity: Object(),
      );
      container.listen(listsSearchProvider(otherSession), (_, _) {});
      final other = container.read(listsSearchProvider(otherSession).notifier);
      repository.fetch = (_) async => const MdblistResult.success([first]);
      await controller.search('movies');
      expect(container.read(listsSearchProvider(otherSession)).query, isEmpty);
      await other.search('movies');
      controller.clear();
      expect(container.read(listsSearchProvider(otherSession)).results, [
        first,
      ]);
      final sameKey = ListsSearchSession(
        owner: session.owner,
        viewIdentity: session.viewIdentity,
      );
      expect(sameKey, session);
      expect(sameKey.hashCode, session.hashCode);
      expect(otherSession, isNot(session));
    },
  );

  test(
    'disconnect shows existing error and reconnect can retry the same query',
    () async {
      repository.connected = false;
      expect(await controller.search('movies'), isTrue);
      expect(
        current().error,
        'Connect MDBList in Settings to search public lists.',
      );
      expect(repository.queries, isEmpty);
      repository.connected = true;
      repository.fetch = (_) async => const MdblistResult.success([first]);
      expect(await controller.search('movies'), isTrue);
      expect(current().error, isNull);
      expect(current().results, [first]);
    },
  );

  test('disabled builds do not authenticate or search', () async {
    repository.enabled = false;
    expect(await controller.search('movies'), isFalse);
    expect(repository.authCalls, 0);
    expect(repository.queries, isEmpty);
  });

  test(
    'transport exception is displayed once without implicit retries',
    () async {
      repository.fetch = (_) async => throw StateError('offline');
      expect(await controller.search('movies'), isTrue);
      expect(current().searching, isFalse);
      expect(
        current().error,
        'MDBList is not responding right now. Try again shortly.',
      );
      await container.pump();
      current();
      expect(repository.queries, ['movies']);
    },
  );

  test(
    'partial results remain usable and rate limit rounding is preserved',
    () async {
      repository.fetch = (_) async => const MdblistResult.partial([first]);
      await controller.search('movies');
      expect(current().results, [first]);
      expect(current().error, isNull);
      repository.fetch = (_) async => const MdblistResult.failure(
        MdblistResultKind.rateLimited,
        retryAfter: Duration(seconds: 61),
      );
      await controller.search('movies');
      expect(
        current().error,
        'MDBList rate limit reached. Try again in 2 minutes.',
      );
      expect(current().results, isEmpty);
    },
  );
}

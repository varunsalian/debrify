import 'dart:async';

import 'package:debrify/features/sources/application/source_seasons_controller.dart';
import 'package:debrify/features/sources/application/source_seasons_dependencies.dart';
import 'package:debrify/features/sources/data/source_seasons_repository.dart';
import 'package:debrify/features/sources/models/source_seasons_state.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class Repository implements SourceSeasonsRepository {
  @override
  bool isCurrent = true;
  final requests = <Completer<SourceSeasonGuide?>>[];
  @override
  Future<SourceSeasonGuide?> load() {
    final request = Completer<SourceSeasonGuide?>();
    requests.add(request);
    return request.future;
  }
}

class Guide implements SourceSeasonGuide {
  Guide(this.seasons);
  @override
  final List<int> seasons;
  int records = 0;
  final recorded = Completer<void>();
  @override
  Future<void> record() {
    records++;
    return recorded.future;
  }
}

void main() {
  late Repository repository;
  late ProviderContainer container;
  late SourceSeasonsController controller;
  late ProviderSubscription<SourceSeasonsState> subscription;
  late SourcesSession session;

  void start({
    bool series = true,
    bool keyword = false,
    int? episode,
    String id = 'tt-fixture',
  }) {
    repository = Repository();
    session = SourcesSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      selection: AdvancedSearchSelection(
        imdbId: id,
        title: 'Fixture',
        isSeries: series,
        season: 2,
        episode: episode,
      ),
      keywordMode: keyword,
    );
    container = ProviderContainer.test(
      overrides: [
        sourceSeasonsRepositoryProvider.overrideWith((ref, key) => repository),
      ],
    );
    subscription = container.listen(sourceSeasonsProvider(session), (_, _) {});
    controller = container.read(sourceSeasonsProvider(session).notifier);
  }

  test(
    'initial selection requires no IO; menu publishes without waiting for inventory',
    () async {
      start();
      expect(subscription.read().selected, 2);
      expect(repository.requests, isEmpty);
      final pending = controller.load();
      final guide = Guide([1, 2, 3]);
      repository.requests.single.complete(guide);
      await pending;
      expect(subscription.read().available, [1, 2, 3]);
      expect(guide.records, 1);
      expect(guide.recorded.isCompleted, isFalse);
      expect(controller.select(3), isTrue);
      expect(controller.select(3), isFalse);
      expect(subscription.read().available, [1, 2, 3]);
      expect(
        () => subscription.read().available.add(4),
        throwsUnsupportedError,
      );
      guide.recorded.complete();
    },
  );

  test('replaced request cannot publish or record inventory', () async {
    start();
    final first = controller.load();
    final second = controller.load();
    final stale = Guide([1]);
    final latest = Guide([2, 3]);
    repository.requests.last.complete(latest);
    await second;
    repository.requests.first.complete(stale);
    await first;
    expect(subscription.read().available, [2, 3]);
    expect(stale.records, 0);
    expect(latest.records, 1);
    latest.recorded.complete();
  });

  for (final retire in ['profile', 'dispose', 'dependency']) {
    test(
      '$retire rejects delayed metadata before inventory dispatch',
      () async {
        start();
        final pending = controller.load();
        final request = repository.requests.single;
        if (retire == 'profile') {
          repository.isCurrent = false;
        } else if (retire == 'dispose') {
          container.dispose();
        } else {
          repository = Repository();
          container.invalidate(sourceSeasonsRepositoryProvider(session));
          expect(subscription.read().available, isEmpty);
        }
        final guide = Guide([1, 2]);
        request.complete(guide);
        await pending;
        expect(guide.records, 0);
        if (retire != 'dispose') expect(subscription.read().available, isEmpty);
      },
    );
  }

  for (final mode in ['movie', 'episode', 'keyword', 'empty id']) {
    test('$mode does not request a season guide', () async {
      start(
        series: mode != 'movie',
        keyword: mode == 'keyword',
        episode: mode == 'episode' ? 1 : null,
        id: mode == 'empty id' ? '' : 'tt-fixture',
      );
      await controller.load();
      expect(repository.requests, isEmpty);
    });
  }

  for (final wholeFamily in [false, true]) {
    test(
      'explicit season scopes isolate menus and inventory: family=$wholeFamily',
      () async {
        start();
        ProviderContainer scoped(Repository repository) =>
            ProviderContainer.test(
              parent: container,
              overrides: [
                sourceSeasonsRepositoryProvider.overrideWith(
                  (ref, key) => repository,
                ),
                if (wholeFamily)
                  sourceSeasonsProvider.overrideWith2(
                    SourceSeasonsController.new,
                  )
                else
                  sourceSeasonsProvider(
                    session,
                  ).overrideWith(() => SourceSeasonsController(session)),
              ],
            );
        final firstRepository = Repository();
        final secondRepository = Repository();
        final first = scoped(firstRepository);
        first.listen(sourceSeasonsProvider(session), (_, _) {});
        final firstController = first.read(
          sourceSeasonsProvider(session).notifier,
        );
        final second = scoped(secondRepository);
        final secondState = second.listen(
          sourceSeasonsProvider(session),
          (_, _) {},
        );
        final secondController = second.read(
          sourceSeasonsProvider(session).notifier,
        );
        expect(
          container.read(sourceSeasonsProvider(session).notifier),
          same(controller),
        );
        expect(
          first.read(sourceSeasonsProvider(session).notifier),
          same(firstController),
        );
        expect(secondController, isNot(same(firstController)));
        final parentLoad = controller.load();
        final firstLoad = firstController.load();
        final secondLoad = secondController.load();
        final retiredGuide = Guide([9]);
        first.dispose();
        firstRepository.requests.single.complete(retiredGuide);
        await firstLoad;
        expect(retiredGuide.records, 0);
        expect(subscription.read().available, isEmpty);
        expect(secondState.read().available, isEmpty);
        final secondGuide = Guide([3, 4]);
        secondRepository.requests.single.complete(secondGuide);
        await secondLoad;
        expect(secondState.read().available, [3, 4]);
        expect(subscription.read().available, isEmpty);
        expect(secondGuide.records, 1);
        secondGuide.recorded.complete();
        final parentGuide = Guide([1, 2]);
        repository.requests.single.complete(parentGuide);
        await parentLoad;
        expect(subscription.read().available, [1, 2]);
        expect(parentGuide.records, 1);
        parentGuide.recorded.complete();
        secondController.select(4);
        expect(secondState.read().selected, 4);
        expect(subscription.read().selected, 2);
      },
    );
  }

  test('metadata failure preserves selection and does not retry', () async {
    start();
    final pending = controller.load();
    controller.select(4);
    repository.requests.single.completeError(StateError('fixture'));
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(subscription.read().selected, 4);
    expect(subscription.read().available, isEmpty);
    expect(repository.requests, hasLength(1));
  });
}

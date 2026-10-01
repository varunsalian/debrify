import 'dart:async';

import 'package:debrify/features/sources/application/saved_sources_controller.dart';
import 'package:debrify/features/sources/application/sources_providers.dart';
import 'package:debrify/features/sources/data/saved_sources_repository.dart';
import 'package:debrify/features/sources/models/saved_sources_state.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class Repository implements SavedSourcesRepository {
  @override
  bool isCurrent = true;
  final reads = <Completer<SavedSourcesState>>[];
  final removals = <(SeriesSource, Completer<bool>)>[];
  @override
  Future<bool> remove(SeriesSource source) {
    final result = Completer<bool>();
    removals.add((source, result));
    return result.future;
  }

  final saves = <SeriesSource>[];
  @override
  Future<bool> save(SeriesSource source) async {
    saves.add(source);
    return isCurrent;
  }

  @override
  Future<SavedSourcesState> load() {
    final next = Completer<SavedSourcesState>();
    reads.add(next);
    return next.future;
  }
}

void main() {
  late Repository repository;
  late ProviderContainer container;
  late SavedSourcesController controller;
  late ProviderSubscription<SavedSourcesState> subscription;
  late SourcesSession session;
  final loaded = SavedSourcesState(
    sources: [
      const SeriesSource(
        torrentHash: 'pin',
        torrentName: 'Fixture',
        debridService: 'rd',
        debridTorrentId: '1',
        boundAt: 1,
      ),
    ],
  );

  setUp(() {
    repository = Repository();
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
        savedSourcesRepositoryProvider.overrideWith((ref, key) => repository),
      ],
    );
    subscription = container.listen(savedSourcesProvider(session), (_, _) {});
    controller = container.read(savedSourcesProvider(session).notifier);
  });

  for (final wholeFamily in [false, true]) {
    test(
      'scoped removal retires reload while sibling persistence continues: family=$wholeFamily',
      () async {
        ProviderContainer scoped(Repository repository) =>
            ProviderContainer.test(
              parent: container,
              overrides: [
                savedSourcesRepositoryProvider.overrideWith(
                  (ref, key) => repository,
                ),
                if (wholeFamily)
                  savedSourcesProvider.overrideWith2(SavedSourcesController.new)
                else
                  savedSourcesProvider(
                    session,
                  ).overrideWith(() => SavedSourcesController(session)),
              ],
            );
        final firstRepository = Repository();
        final secondRepository = Repository();
        final first = scoped(firstRepository);
        first.listen(savedSourcesProvider(session), (_, _) {});
        final firstController = first.read(
          savedSourcesProvider(session).notifier,
        );
        final second = scoped(secondRepository);
        final secondState = second.listen(
          savedSourcesProvider(session),
          (_, _) {},
        );
        final secondController = second.read(
          savedSourcesProvider(session).notifier,
        );
        expect(
          container.read(savedSourcesProvider(session).notifier),
          same(controller),
        );
        expect(
          first.read(savedSourcesProvider(session).notifier),
          same(firstController),
        );
        final parentLoad = controller.reload();
        final firstRemove = firstController.remove(loaded.sources.single);
        final secondRemove = secondController.remove(loaded.sources.single);
        first.dispose();
        firstRepository.removals.single.$2.complete(true);
        await Future<void>.delayed(Duration.zero);
        expect(firstRepository.reads, isEmpty);
        expect(await firstRemove, isFalse);
        expect(await firstController.reload(), isFalse);
        expect(await firstController.remove(loaded.sources.single), isFalse);
        expect(firstRepository.removals, hasLength(1));
        expect(secondRepository.reads, isEmpty);
        expect(subscription.read().sources, isEmpty);
        secondRepository.removals.single.$2.complete(true);
        await Future<void>.delayed(Duration.zero);
        secondRepository.reads.single.complete(SavedSourcesState());
        expect(await secondRemove, isTrue);
        repository.reads.single.complete(loaded);
        expect(await parentLoad, isTrue);
        expect(subscription.read().sources, loaded.sources);
        expect(secondState.read().sources, isEmpty);
        expect(firstRepository.reads, isEmpty);
      },
    );
  }

  test('remove waits for persistence before reloading saved rows', () async {
    final pending = controller.remove(loaded.sources.single);
    expect(repository.removals.single.$1, same(loaded.sources.single));
    expect(repository.reads, isEmpty);
    repository.removals.single.$2.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(repository.reads, hasLength(1));
    repository.reads.single.complete(SavedSourcesState());
    expect(await pending, isTrue);
    expect(subscription.read().sources, isEmpty);
  });

  test(
    'closing the view leaves removal completion owned by the repository',
    () async {
      final pending = controller.remove(loaded.sources.single);
      container.dispose();
      repository.removals.single.$2.complete(true);
      expect(await pending, isFalse);
      expect(repository.reads, isEmpty);
    },
  );

  test('retired removal skips reload; current failures propagate', () async {
    final retired = controller.remove(loaded.sources.single);
    repository.removals.single.$2.complete(false);
    expect(await retired, isFalse);
    expect(repository.reads, isEmpty);
    final failing = controller.remove(loaded.sources.single);
    repository.removals.last.$2.completeError(StateError('fixture'));
    await expectLater(failing, throwsStateError);
    expect(repository.reads, isEmpty);
  });

  test(
    'construction performs no IO and explicit reload publishes once',
    () async {
      expect(repository.reads, isEmpty);
      final pending = controller.reload();
      expect(subscription.read().sources, isEmpty);
      repository.reads.single.complete(loaded);
      expect(await pending, isTrue);
      expect(subscription.read(), same(loaded));
      final additional = container.listen(
        savedSourcesProvider(session),
        (_, _) {},
      );
      additional.close();
      expect(repository.reads, hasLength(1));
    },
  );

  test('overlapping reloads retain the newer snapshot', () async {
    final old = controller.reload();
    final latest = controller.reload();
    repository.reads.last.complete(loaded);
    expect(await latest, isTrue);
    repository.reads.first.complete(SavedSourcesState());
    expect(await old, isFalse);
    expect(subscription.read(), same(loaded));
  });

  for (final retire in ['profile', 'dispose', 'dependency']) {
    for (final failure in [false, true]) {
      test('$retire rejects late ${failure ? 'failure' : 'result'}', () async {
        final pending = controller.reload();
        final request = repository.reads.single;
        if (retire == 'profile') {
          repository.isCurrent = false;
        } else if (retire == 'dispose') {
          container.dispose();
        } else {
          repository = Repository();
          container.invalidate(savedSourcesRepositoryProvider(session));
          expect(subscription.read().sources, isEmpty);
        }
        if (failure) {
          request.completeError(StateError('fixture'));
        } else {
          request.complete(loaded);
        }
        expect(await pending, isFalse);
        if (retire != 'dispose') expect(subscription.read().sources, isEmpty);
      });
    }
  }

  test(
    'current failure propagates without clearing previous pins or retrying',
    () async {
      final initial = controller.reload();
      repository.reads.single.complete(loaded);
      await initial;
      final pending = controller.reload();
      final assertion = expectLater(pending, throwsStateError);
      repository.reads.last.completeError(StateError('fixture'));
      await assertion;
      expect(subscription.read(), same(loaded));
      await Future<void>.delayed(Duration.zero);
      expect(repository.reads, hasLength(2));
    },
  );
}

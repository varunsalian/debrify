import 'dart:async';

import 'package:debrify/features/sources/application/saved_sources_controller.dart';
import 'package:debrify/features/sources/application/saved_sources_dependencies.dart';
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

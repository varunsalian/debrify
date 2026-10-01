import 'dart:async';
import 'package:debrify/features/sources/application/saved_sources_controller.dart';
import 'package:debrify/features/sources/application/source_binding_controller.dart';
import 'package:debrify/features/sources/application/sources_providers.dart';
import 'package:debrify/features/sources/data/saved_sources_repository.dart';
import 'package:debrify/features/sources/models/saved_sources_state.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class Repository implements SavedSourcesRepository {
  @override
  bool isCurrent = true;
  final reads = <Completer<SavedSourcesState>>[];
  final saves = <SeriesSource>[];
  @override
  Future<bool> save(SeriesSource source) async {
    saves.add(source);
    return isCurrent;
  }

  @override
  Future<SavedSourcesState> load() {
    final read = Completer<SavedSourcesState>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<bool> remove(SeriesSource source) => throw UnimplementedError();
}

void main() {
  late ProviderContainer container;
  late SourceBindingController controller;
  late ProviderSubscription<bool> subscription;
  late SourcesSession session;
  late Repository repository;
  setUp(() {
    session = SourcesSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      selection: const AdvancedSearchSelection(
        imdbId: 'tt1',
        isSeries: false,
        title: 'One',
      ),
    );
    repository = Repository();
    container = ProviderContainer.test(
      overrides: [
        savedSourcesRepositoryProvider.overrideWith(
          (ref, session) => repository,
        ),
      ],
    );
    subscription = container.listen(sourceBindingProvider(session), (_, _) {});
    controller = container.read(sourceBindingProvider(session).notifier);
  });
  Future<bool> bind(Future<bool> Function() operation) =>
      controller.bind((_, _) => operation(), viewIsActive: () => true);

  test(
    'one action gate stays busy through binding and the subsequent reload',
    () async {
      expect(subscription.read(), isFalse);
      expect(repository.reads, isEmpty);
      final operation = Completer<bool>();
      final pending = bind(() => operation.future);
      expect(subscription.read(), isTrue);
      var duplicateCalls = 0;
      Future<bool> duplicate() async {
        duplicateCalls++;
        return true;
      }

      expect(await bind(duplicate), isFalse);
      operation.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(repository.reads, hasLength(1));
      expect(subscription.read(), isTrue);
      expect(await bind(duplicate), isFalse);
      expect(duplicateCalls, 0);
      repository.reads.single.complete(SavedSourcesState());
      expect(await pending, isTrue);
      expect(subscription.read(), isFalse);
    },
  );

  test('cancelled binding skips reload and permits the next action', () async {
    expect(await bind(() async => false), isFalse);
    expect(subscription.read(), isFalse);
    expect(repository.reads, isEmpty);
    expect(await bind(() async => false), isFalse);
  });

  test(
    'binding errors propagate and release the gate without automatic retry',
    () async {
      var calls = 0;
      await expectLater(
        bind(() async {
          calls++;
          throw StateError('fixture');
        }),
        throwsStateError,
      );
      expect(subscription.read(), isFalse);
      expect(repository.reads, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
    },
  );

  test('reload errors propagate and release the gate', () async {
    final pending = bind(() async => true);
    await Future<void>.delayed(Duration.zero);
    repository.reads.single.completeError(StateError('reload'));
    await expectLater(pending, throwsStateError);
    expect(subscription.read(), isFalse);
  });

  test('closing the view during reload rejects UI completion', () async {
    var mounted = true;
    final pending = controller.bind(
      (_, _) async => true,
      viewIsActive: () => mounted,
    );
    await Future<void>.delayed(Duration.zero);
    mounted = false;
    repository.reads.single.complete(SavedSourcesState());
    expect(await pending, isFalse);
    expect(subscription.read(), isFalse);
  });

  for (final retirement in ['view', 'profile', 'dispose']) {
    test('$retirement while binding skips reload and UI completion', () async {
      var mounted = true;
      final operation = Completer<bool>();
      final pending = controller.bind(
        (_, _) => operation.future,
        viewIsActive: () => mounted,
      );
      if (retirement == 'view') {
        mounted = false;
      } else if (retirement == 'profile') {
        ProfileSessionMemory.clearAll();
      } else {
        container.dispose();
      }
      operation.complete(true);
      expect(await pending, isFalse);
      expect(repository.reads, isEmpty);
    });
  }

  test(
    'retired controller completion cannot unlock its replacement action',
    () async {
      final old = Completer<bool>();
      final first = bind(() => old.future);
      container.invalidate(sourceBindingProvider(session));
      expect(subscription.read(), isFalse);
      controller = container.read(sourceBindingProvider(session).notifier);
      final replacement = Completer<bool>();
      final second = bind(() => replacement.future);
      old.complete(true);
      expect(await first, isFalse);
      expect(subscription.read(), isTrue);
      expect(repository.reads, isEmpty);
      replacement.complete(false);
      expect(await second, isFalse);
      expect(subscription.read(), isFalse);
    },
  );
  const pin = SeriesSource(
    torrentHash: 'hash',
    torrentName: 'Fixture',
    debridService: 'rd',
    debridTorrentId: 'id',
    boundAt: 1,
  );

  for (final wholeFamily in [false, true]) {
    test(
      'scoped binding closes retained writer without retiring siblings: family=$wholeFamily',
      () async {
        ProviderContainer scoped(
          Repository repository,
        ) => ProviderContainer.test(
          parent: container,
          overrides: [
            savedSourcesRepositoryProvider.overrideWith(
              (ref, key) => repository,
            ),
            if (wholeFamily) ...[
              savedSourcesProvider.overrideWith2(SavedSourcesController.new),
              sourceBindingProvider.overrideWith2(SourceBindingController.new),
            ] else ...[
              savedSourcesProvider(
                session,
              ).overrideWith(() => SavedSourcesController(session)),
              sourceBindingProvider(
                session,
              ).overrideWith(() => SourceBindingController(session)),
            ],
          ],
        );
        final firstRepository = Repository();
        final secondRepository = Repository();
        final first = scoped(firstRepository);
        first.listen(sourceBindingProvider(session), (_, _) {});
        final firstController = first.read(
          sourceBindingProvider(session).notifier,
        );
        final second = scoped(secondRepository);
        final secondBusy = second.listen(
          sourceBindingProvider(session),
          (_, _) {},
        );
        final secondController = second.read(
          sourceBindingProvider(session).notifier,
        );
        expect(
          container.read(sourceBindingProvider(session).notifier),
          same(controller),
        );
        expect(
          first.read(sourceBindingProvider(session).notifier),
          same(firstController),
        );
        final parentOperation = Completer<bool>();
        final firstOperation = Completer<bool>();
        final secondOperation = Completer<bool>();
        late SourceBindingWriter parentWriter;
        late SourceBindingWriter firstWriter;
        late SourceBindingWriter secondWriter;
        late bool Function() firstActive;
        final parentBind = controller.bind((save, _) {
          parentWriter = save;
          return parentOperation.future;
        }, viewIsActive: () => true);
        final firstBind = firstController.bind((save, active) {
          firstWriter = save;
          firstActive = active;
          return firstOperation.future;
        }, viewIsActive: () => true);
        final secondBind = secondController.bind((save, _) {
          secondWriter = save;
          return secondOperation.future;
        }, viewIsActive: () => true);
        first.dispose();
        expect(firstActive(), isFalse);
        expect(await firstWriter(pin), isFalse);
        expect(firstRepository.saves, isEmpty);
        firstOperation.complete(true);
        expect(await firstBind, isFalse);
        expect(firstRepository.reads, isEmpty);
        expect(subscription.read(), isTrue);
        expect(secondBusy.read(), isTrue);
        expect(await secondWriter(pin), isTrue);
        expect(secondRepository.saves, [same(pin)]);
        expect(repository.saves, isEmpty);
        secondOperation.complete(true);
        await Future<void>.delayed(Duration.zero);
        secondRepository.reads.single.complete(
          SavedSourcesState(sources: [pin]),
        );
        expect(await secondBind, isTrue);
        expect(secondBusy.read(), isFalse);
        expect(subscription.read(), isTrue);
        expect(second.read(savedSourcesProvider(session)).sources, [same(pin)]);
        expect(container.read(savedSourcesProvider(session)).sources, isEmpty);
        expect(await parentWriter(pin), isTrue);
        parentOperation.complete(true);
        await Future<void>.delayed(Duration.zero);
        repository.reads.single.complete(SavedSourcesState(sources: [pin]));
        expect(await parentBind, isTrue);
        expect(subscription.read(), isFalse);
        expect(repository.saves, [same(pin)]);
        expect(container.read(savedSourcesProvider(session)).sources, [
          same(pin),
        ]);
        expect(await secondWriter(pin), isFalse);
        expect(secondRepository.saves, hasLength(1));
      },
    );
  }

  for (final retirement in [
    'view',
    'profile',
    'dispose',
    'completion',
    'error',
  ]) {
    test(
      '$retirement closes the preparation guard and retained writer',
      () async {
        var mounted = true;
        late bool Function() canContinue;
        late SourceBindingWriter writer;
        final operation = Completer<bool>();
        final pending = controller.bind((save, current) {
          writer = save;
          canContinue = current;
          return operation.future;
        }, viewIsActive: () => mounted);
        expect(canContinue(), isTrue);
        if (retirement == 'view') {
          mounted = false;
        } else if (retirement == 'profile') {
          ProfileSessionMemory.clearAll();
        } else if (retirement == 'dispose') {
          container.dispose();
        }
        if (retirement == 'error') {
          final check = expectLater(pending, throwsStateError);
          operation.completeError(StateError('preparation failed'));
          await check;
        } else {
          if (retirement != 'completion') expect(canContinue(), isFalse);
          operation.complete(false);
          expect(await pending, isFalse);
        }
        expect(canContinue(), isFalse);
        expect(await writer(pin), isFalse);
        expect(repository.saves, isEmpty);
        expect(repository.reads, isEmpty);
      },
    );
  }

  test(
    'binding writer saves through the repository and closes before UI completion',
    () async {
      late SourceBindingWriter writer;
      final pending = controller.bind((save, _) {
        writer = save;
        return save(pin);
      }, viewIsActive: () => true);
      await Future<void>.delayed(Duration.zero);
      expect(repository.saves, [same(pin)]);
      expect(repository.reads, hasLength(1));
      expect(await writer(pin), isFalse);
      expect(repository.saves, hasLength(1));
      repository.reads.single.complete(SavedSourcesState());
      expect(await pending, isTrue);
      expect(await writer(pin), isFalse);
    },
  );

  for (final retirement in ['view', 'profile', 'dispose']) {
    test('$retirement rejects a delayed writer before persistence', () async {
      var mounted = true;
      late SourceBindingWriter writer;
      final operation = Completer<bool>();
      final pending = controller.bind((save, _) {
        writer = save;
        return operation.future;
      }, viewIsActive: () => mounted);
      if (retirement == 'view') {
        mounted = false;
      } else if (retirement == 'profile') {
        ProfileSessionMemory.clearAll();
      } else {
        container.dispose();
      }
      expect(await writer(pin), isFalse);
      expect(repository.saves, isEmpty);
      operation.complete(false);
      expect(await pending, isFalse);
      expect(repository.reads, isEmpty);
    });
  }
}

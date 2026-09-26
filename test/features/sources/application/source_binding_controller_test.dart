import 'dart:async';
import 'package:debrify/features/sources/application/source_binding_controller.dart';
import 'package:debrify/features/sources/application/saved_sources_dependencies.dart';
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
      controller.bind(operation, viewIsActive: () => true);

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
      () async => true,
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
        () => operation.future,
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
}

import 'dart:async';

import 'package:debrify/features/home/application/home_continuation_layout_controller.dart';
import 'package:debrify/features/home/application/home_continuation_providers.dart';
import 'package:debrify/features/home/data/home_continuation_layout_repository.dart';
import 'package:debrify/features/home/models/home_continuation_layout.dart';
import 'package:debrify/features/home/models/home_continuation_session.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

HomeContinuationSession session() => HomeContinuationSession(
  owner: ProfileSessionMemory.captureOwner(),
  viewIdentity: Object(),
);
HomeContinuationLayoutController mount(
  ProviderContainer container,
  HomeContinuationSession key,
) {
  container.listen(homeContinuationLayoutProvider(key), (_, _) {});
  return container.read(homeContinuationLayoutProvider(key).notifier);
}

void main() {
  test(
    'loaders share one read; refresh preserves independent provider flags',
    () async {
      final calls = <String>[];
      final pending = Completer<bool>();
      var refreshed = false;
      final container = ProviderContainer.test(
        overrides: [
          homeContinuationLayoutRepositoryProvider.overrideWithValue(
            HomeContinuationLayoutRepository(
              readMerged: (provider) {
                calls.add(provider);
                if (refreshed) return Future.value(provider == 'simkl');
                return provider == 'local'
                    ? pending.future
                    : Future.value(provider == 'mdblist');
              },
            ),
          ),
        ],
      );
      final controller = mount(container, session());
      expect(calls, isEmpty);
      final first = controller.ensureLoaded(isCurrent: () => true);
      final second = controller.ensureLoaded(isCurrent: () => true);
      expect(identical(first, second), isTrue);
      expect(calls, ['local', 'trakt', 'simkl', 'mdblist']);
      expect(controller.current, const HomeContinuationLayout());
      pending.complete(true);
      await first;
      expect(
        controller.current,
        const HomeContinuationLayout(local: true, mdblist: true),
      );
      refreshed = true;
      expect(await controller.refresh(isCurrent: () => true), isTrue);
      expect(controller.current, const HomeContinuationLayout(simkl: true));
      expect(await controller.refresh(isCurrent: () => true), isFalse);
      await controller.ensureLoaded(isCurrent: () => true);
      expect(calls.length, 12);
    },
  );

  test(
    'initial failure is memoized; explicit refresh retries and propagates errors',
    () async {
      var reads = 0;
      var fail = true;
      final error = StateError('preferences');
      final container = ProviderContainer.test(
        overrides: [
          homeContinuationLayoutRepositoryProvider.overrideWithValue(
            HomeContinuationLayoutRepository(
              readMerged: (_) async {
                reads++;
                if (fail) throw error;
                return true;
              },
            ),
          ),
        ],
      );
      final controller = mount(container, session());
      await controller.ensureLoaded(isCurrent: () => true);
      await controller.ensureLoaded(isCurrent: () => true);
      expect(reads, 4);
      expect(controller.current, const HomeContinuationLayout());
      fail = false;
      expect(await controller.refresh(isCurrent: () => true), isTrue);
      final accepted = controller.current;
      fail = true;
      await expectLater(
        controller.refresh(isCurrent: () => true),
        throwsA(same(error)),
      );
      expect(controller.current, same(accepted));
      expect(reads, 12);
    },
  );

  test('settings refresh retires a slower initial read', () async {
    final old = Completer<bool>();
    var reads = 0;
    final container = ProviderContainer.test(
      overrides: [
        homeContinuationLayoutRepositoryProvider.overrideWithValue(
          HomeContinuationLayoutRepository(
            readMerged: (_) => ++reads <= 4 ? old.future : Future.value(false),
          ),
        ),
      ],
    );
    final controller = mount(container, session());
    final initial = controller.ensureLoaded(isCurrent: () => true);
    expect(await controller.refresh(isCurrent: () => true), isFalse);
    old.complete(true);
    await initial;
    expect(controller.current, const HomeContinuationLayout());
    expect(reads, 8);
  });

  test(
    'a settings refresh started during startup does not drop the first read',
    () async {
      final initial = Completer<bool>();
      final refreshed = Completer<bool>();
      var reads = 0;
      final container = ProviderContainer.test(
        overrides: [
          homeContinuationLayoutRepositoryProvider.overrideWithValue(
            HomeContinuationLayoutRepository(
              readMerged: (_) =>
                  ++reads <= 4 ? initial.future : refreshed.future,
            ),
          ),
        ],
      );
      final controller = mount(container, session());
      final first = controller.ensureLoaded(isCurrent: () => true);
      final refresh = controller.refresh(isCurrent: () => true);
      initial.complete(true);
      await first;
      // Loaders awaiting the first read size their rows with the real flags.
      expect(
        controller.current,
        const HomeContinuationLayout(
          local: true,
          trakt: true,
          simkl: true,
          mdblist: true,
        ),
      );
      refreshed.complete(false);
      expect(await refresh, isTrue);
      expect(controller.current, const HomeContinuationLayout());
      expect(reads, 8);
    },
  );

  for (final reason in ['dispose', 'profile', 'recompute', 'view']) {
    test('$reason rejects pending layout reads', () async {
      final pending = Completer<bool>();
      var reads = 0;
      final container = ProviderContainer.test(
        overrides: [
          homeContinuationLayoutRepositoryProvider.overrideWithValue(
            HomeContinuationLayoutRepository(
              readMerged: (_) {
                reads++;
                return pending.future;
              },
            ),
          ),
        ],
      );
      final key = session();
      final controller = mount(container, key);
      var visible = true;
      final request = controller.refresh(isCurrent: () => visible);
      switch (reason) {
        case 'dispose':
          container.dispose();
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'recompute':
          container.invalidate(homeContinuationLayoutProvider(key));
          container.read(homeContinuationLayoutProvider(key));
        case 'view':
          visible = false;
      }
      pending.complete(true);
      expect(await request, isFalse);
      expect(controller.current, const HomeContinuationLayout());
      expect(reads, 4);
    });
  }

  test(
    'child scopes and sibling views retain independent preferences',
    () async {
      HomeContinuationLayoutRepository repository(bool value) =>
          HomeContinuationLayoutRepository(readMerged: (_) async => value);
      final key = session();
      final parent = ProviderContainer.test(
        overrides: [
          homeContinuationLayoutRepositoryProvider.overrideWithValue(
            repository(true),
          ),
        ],
      );
      final root = mount(parent, key);
      await root.ensureLoaded(isCurrent: () => true);
      final sibling = mount(parent, session());
      final child = ProviderContainer.test(
        parent: parent,
        overrides: [
          homeContinuationLayoutRepositoryProvider.overrideWithValue(
            repository(false),
          ),
          homeContinuationLayoutProvider(
            key,
          ).overrideWith(() => HomeContinuationLayoutController(key)),
        ],
      );
      final scoped = mount(child, key);
      await scoped.ensureLoaded(isCurrent: () => true);
      expect(root.current.local, isTrue);
      expect(sibling.current.local, isFalse);
      expect(scoped.current.local, isFalse);
    },
  );
}

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'dart:async';
import 'package:debrify/features/home/application/home_mdblist_continuation_controller.dart';
import 'package:debrify/features/home/application/home_mdblist_continuation_dependencies.dart';
import 'package:debrify/features/home/data/home_mdblist_continuation_repository.dart';
import 'package:debrify/features/home/models/home_continuation_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/mdblist_continue_watching.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const paused = MdblistContinueWatchingItem(
  selection: AdvancedSearchSelection(
    imdbId: 'tt1',
    isSeries: false,
    title: 'Paused',
  ),
  paused: true,
  playbackId: 42,
  clearTarget: MdblistScrobbleTarget.movie(MdblistMediaIds(imdb: 'tt1')),
);
const upNext = MdblistContinueWatchingItem(
  selection: AdvancedSearchSelection(
    imdbId: 'tt2',
    isSeries: true,
    title: 'Next',
  ),
  paused: false,
);

class Fixture {
  Fixture(Future<bool> Function(MdblistContinueWatchingItem) clear) {
    container = ProviderContainer.test(
      overrides: [
        homeMdblistContinuationRepositoryProvider.overrideWithValue(
          HomeMdblistContinuationRepository(
            clear: clear,
            invalidate: () {},
            synchronizeInvalidations: () async => true,
            fetch: ({required force}) async => const MdblistResult.success(
              MdblistContinueWatchingSnapshot(
                movies: [paused],
                shows: [upNext],
              ),
            ),
          ),
        ),
      ],
    );
    container.listen(homeMdblistContinuationProvider(key), (_, _) {});
    controller = container.read(homeMdblistContinuationProvider(key).notifier);
  }
  final key = HomeContinuationSession(
    owner: ProfileSessionMemory.captureOwner(),
    viewIdentity: Object(),
  );
  late final ProviderContainer container;
  late final HomeMdblistContinuationController controller;
  bool active = true;
  Future<void> load() => controller.load(
    enabled: true,
    force: false,
    refreshBound: false,
    isCurrent: () => active,
    ensureLayout: () async {},
    now: DateTime.now,
    trace: (_) {},
    beforeRows: (_) {},
    onRows: (_, _) {},
    onDisabled: () {},
  );
  Future<bool> remove([String? id = 'tt1']) =>
      controller.remove(id, isCurrent: () => active);
}

void main() {
  test(
    'clear retains originating scope across foreign zone and retirement',
    () async {
      final origin = ProfileScope(
        profileId: 'origin',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final other = ProfileScope(
        profileId: 'other',
        dataGeneration: 1,
        sessionEpoch: 2,
      );
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeCommitted(origin);
      addTearDown(ProfileRuntime.debugReset);
      final entered = Completer<void>(), release = Completer<void>();
      final scopes = <ProfileScope?>[];
      final f = Fixture((_) async {
        scopes.add(ProfileRuntime.capture());
        entered.complete();
        await release.future;
        scopes.add(ProfileRuntime.capture());
        return true;
      });
      await f.load();
      final pending = ProfileRuntime.withCapturedScope(other, f.remove);
      await entered.future;
      ProfileSessionMemory.clearAll();
      ProfileRuntime.publish(other);
      release.complete();
      expect(await pending, isFalse);
      expect(scopes, [origin, origin]);
    },
  );

  test(
    'only a paused accepted descriptor reaches clear, with its identity intact',
    () async {
      final calls = <MdblistContinueWatchingItem>[];
      final f = Fixture((item) async {
        calls.add(item);
        return true;
      });
      expect(await f.remove(), isFalse);
      await f.load();
      expect(await f.remove(null), isFalse);
      expect(await f.remove('missing'), isFalse);
      expect(await f.remove('tt2'), isFalse);
      expect(calls, isEmpty);
      final rows = f.controller.current;
      expect(await f.remove(), isTrue);
      expect(calls.single, same(paused));
      // The view refreshes authoritative rows after feedback; no optimistic deletion.
      expect(f.controller.current, same(rows));
    },
  );

  test('clear failure retains accepted rows and does not retry', () async {
    var calls = 0;
    final f = Fixture((_) async {
      calls++;
      return false;
    });
    await f.load();
    final rows = f.controller.current;
    expect(await f.remove(), isFalse);
    expect(calls, 1);
    expect(f.controller.current, same(rows));
  });

  test('clear exceptions propagate without retries or state changes', () async {
    var calls = 0;
    final error = StateError('clear');
    final f = Fixture((_) async {
      calls++;
      throw error;
    });
    await f.load();
    final rows = f.controller.current;
    await expectLater(f.remove(), throwsA(same(error)));
    expect(calls, 1);
    expect(f.controller.current, same(rows));
  });

  for (final reason in ['profile', 'view', 'dispose', 'recompute']) {
    test('$reason while clearing suppresses feedback eligibility', () async {
      final pending = Completer<bool>();
      final f = Fixture((_) => pending.future);
      await f.load();
      final request = f.remove();
      switch (reason) {
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'view':
          f.active = false;
        case 'dispose':
          f.container.dispose();
        case 'recompute':
          f.container.invalidate(homeMdblistContinuationProvider(f.key));
          f.container.read(homeMdblistContinuationProvider(f.key));
      }
      pending.complete(true);
      expect(await request, isFalse);
    });
  }

  test('outgoing profile cannot dispatch a removal', () async {
    var calls = 0;
    final f = Fixture((_) async {
      calls++;
      return true;
    });
    await f.load();
    ProfileSessionMemory.clearAll();
    expect(await f.remove(), isFalse);
    expect(calls, 0);
  });

  test(
    'ordinary refresh and independent removals do not retire issued commands',
    () async {
      final first = Completer<bool>();
      final second = Completer<bool>();
      var calls = 0;
      final f = Fixture((_) => ++calls == 1 ? first.future : second.future);
      await f.load();
      final older = f.remove();
      await f.load();
      final newer = f.remove();
      second.complete(true);
      expect(await newer, isTrue);
      first.complete(true);
      expect(await older, isTrue);
      expect(calls, 2);
    },
  );
}

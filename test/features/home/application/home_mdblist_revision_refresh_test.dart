import 'dart:async';
import 'package:debrify/features/home/application/home_mdblist_continuation_controller.dart';
import 'package:debrify/features/home/application/home_continuation_providers.dart';
import 'package:debrify/features/home/data/home_mdblist_continuation_repository.dart';
import 'package:debrify/features/home/models/home_continuation_session.dart';
import 'package:debrify/models/mdblist_continue_watching.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class Fixture {
  Fixture() {
    container = ProviderContainer.test(
      overrides: [
        homeMdblistContinuationRepositoryProvider.overrideWithValue(
          HomeMdblistContinuationRepository(
            clear: (_) async => false,
            invalidate: () => invalidations++,
            synchronizeInvalidations: () async => true,
            fetch: ({required force}) async =>
                const MdblistResult.success(MdblistContinueWatchingSnapshot()),
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
  bool visible = true;
  int invalidations = 0;
  int reloads = 0;
  final waits = <Duration>[];
  Future<void> refresh({
    Future<void> Function(Duration)? wait,
    Future<void> Function()? reload,
  }) => controller.refreshAfterRevision(
    isCurrent: () => active,
    isVisible: () => visible,
    wait: (duration) {
      waits.add(duration);
      return wait?.call(duration) ?? Future.value();
    },
    reload:
        reload ??
        () async {
          reloads++;
        },
  );
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'visible revision invalidates immediately, delays and stays pending through reload',
    () async {
      final f = Fixture();
      final delay = Completer<void>();
      final reload = Completer<void>();
      final request = f.refresh(
        wait: (_) => delay.future,
        reload: () {
          f.reloads++;
          return reload.future;
        },
      );
      expect(f.invalidations, 1);
      expect(f.waits, [const Duration(milliseconds: 750)]);
      expect(f.reloads, 0);
      expect(
        f.controller.shouldRefreshAfterPlayback(DateTime.utc(2026)),
        isFalse,
      );
      delay.complete();
      await flush();
      expect(f.reloads, 1);
      expect(f.controller.revisionPending, isTrue);
      reload.complete();
      await request;
      expect(f.controller.revisionPending, isFalse);
      expect(
        f.controller.shouldRefreshAfterPlayback(DateTime.utc(2026)),
        isTrue,
      );
    },
  );

  test(
    'covered Home polls twenty times then abandons without propagation wait',
    () async {
      final f = Fixture()..visible = false;
      await f.refresh();
      expect(f.waits, List.filled(20, const Duration(milliseconds: 100)));
      expect(f.invalidations, 1);
      expect(f.reloads, 0);
      expect(f.controller.revisionPending, isFalse);
    },
  );

  test(
    'returning Home enters propagation delay; later cover does not change legacy reload policy',
    () async {
      final f = Fixture()..visible = false;
      await f.refresh(
        wait: (duration) async {
          f.visible = duration == const Duration(milliseconds: 100);
        },
      );
      expect(f.waits, [
        const Duration(milliseconds: 100),
        const Duration(milliseconds: 750),
      ]);
      expect(f.visible, isFalse);
      expect(f.reloads, 1);
    },
  );

  test(
    'superseded revision cannot reload or clear successor pending marker',
    () async {
      final f = Fixture();
      final oldDelay = Completer<void>();
      final newDelay = Completer<void>();
      final old = f.refresh(wait: (_) => oldDelay.future);
      final newer = f.refresh(wait: (_) => newDelay.future);
      oldDelay.complete();
      await old;
      expect(f.reloads, 0);
      expect(f.controller.revisionPending, isTrue);
      newDelay.complete();
      await newer;
      expect(f.invalidations, 2);
      expect(f.reloads, 1);
      expect(f.controller.revisionPending, isFalse);
    },
  );

  for (final stage in ['poll', 'propagation']) {
    for (final reason in [
      'dispose',
      'profile',
      'recompute',
      'view',
      'cancel',
    ]) {
      test('$reason during $stage prevents reload', () async {
        final f = Fixture()..visible = stage != 'poll';
        final delay = Completer<void>();
        final request = f.refresh(wait: (_) => delay.future);
        switch (reason) {
          case 'dispose':
            f.container.dispose();
          case 'profile':
            ProfileSessionMemory.clearAll();
          case 'recompute':
            f.container.invalidate(homeMdblistContinuationProvider(f.key));
            f.container.read(homeMdblistContinuationProvider(f.key));
          case 'view':
            f.active = false;
          case 'cancel':
            f.controller.cancelRevisionRefresh();
        }
        delay.complete();
        await request;
        expect(f.reloads, 0);
        expect(f.controller.revisionPending, isFalse);
      });
    }
  }

  test(
    'outgoing profile cannot invalidate implicitly active service state',
    () async {
      final f = Fixture();
      ProfileSessionMemory.clearAll();
      await f.refresh();
      expect(f.invalidations, 0);
      expect(f.waits, isEmpty);
      expect(f.reloads, 0);
    },
  );

  test('reload error propagates once and releases pending ownership', () async {
    final f = Fixture();
    final error = StateError('refresh');
    await expectLater(
      f.refresh(
        reload: () async {
          f.reloads++;
          throw error;
        },
      ),
      throwsA(same(error)),
    );
    expect(f.reloads, 1);
    expect(f.invalidations, 1);
    expect(f.controller.revisionPending, isFalse);
  });

  test(
    'accepted forced load suppresses return refresh for strictly less than three seconds',
    () async {
      final f = Fixture();
      final stamp = DateTime.utc(2026);
      await f.controller.load(
        enabled: true,
        force: true,
        refreshBound: false,
        isCurrent: () => true,
        ensureLayout: () async {},
        now: () => stamp,
        trace: (_) {},
        beforeRows: (_) {},
        onRows: (_, _) {},
        onDisabled: () {},
      );
      expect(f.controller.shouldRefreshAfterPlayback(stamp), isFalse);
      expect(
        f.controller.shouldRefreshAfterPlayback(
          stamp.add(const Duration(milliseconds: 2999)),
        ),
        isFalse,
      );
      expect(
        f.controller.shouldRefreshAfterPlayback(
          stamp.add(const Duration(seconds: 3)),
        ),
        isTrue,
      );
      expect(
        f.controller.shouldRefreshAfterPlayback(
          stamp.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    },
  );
}

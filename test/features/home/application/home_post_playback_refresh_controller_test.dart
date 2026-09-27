import 'dart:async';
import 'package:debrify/features/home/application/home_post_playback_refresh_controller.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class RefreshHarness {
  final container = ProviderContainer.test();
  final session = HomeCatalogSession(
    owner: ProfileSessionMemory.captureOwner(),
    viewIdentity: Object(),
  );
  late final HomePostPlaybackRefreshController controller;
  final calls = <String>[];
  final errors = <Object>[];
  final steps = <String, Future<void> Function()>{};
  bool current = true;
  bool mdblistEligible = true;

  RefreshHarness() {
    container.listen(homePostPlaybackRefreshProvider(session), (_, _) {});
    controller = container.read(
      homePostPlaybackRefreshProvider(session).notifier,
    );
  }

  Future<void> step(String name) {
    calls.add(name);
    return steps[name]?.call() ?? Future<void>.value();
  }

  Future<void> run({bool search = false, bool force = false}) =>
      controller.refresh(
        searchMode: search,
        trackers: force,
        isCurrent: () => current,
        clearResume: () => calls.add('clear'),
        watchlist: () => step('watchlist'),
        local: () => step('local'),
        iptv: () => step('iptv'),
        trakt: () => step('trakt'),
        simkl: () => step('simkl'),
        shouldRefreshMdblist: () {
          calls.add('eligible');
          return mdblistEligible;
        },
        mdblist: () => step('mdblist'),
        boundSources: () => step('bound'),
        onError: errors.add,
      );
}

void main() {
  late RefreshHarness refresh;
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    refresh = RefreshHarness();
  });
  tearDown(ProfileRuntime.debugReset);

  test(
    'plain return refreshes locals in order and bound badges last without tracker reads',
    () async {
      expect(refresh.calls, isEmpty);
      await refresh.run();
      expect(refresh.calls, ['clear', 'watchlist', 'local', 'iptv', 'bound']);
      expect(refresh.controller.playedSinceRefresh, isFalse);
    },
  );

  test(
    'playback consumes latch synchronously and waits for all parallel trackers before badges',
    () async {
      final trakt = Completer<void>(),
          simkl = Completer<void>(),
          mdblist = Completer<void>();
      refresh.steps.addAll({
        'trakt': () => trakt.future,
        'simkl': () => simkl.future,
        'mdblist': () => mdblist.future,
      });
      refresh.controller.markPlaybackStarted();
      final pending = refresh.run();
      expect(refresh.controller.playedSinceRefresh, isFalse);
      expect(refresh.calls, ['clear', 'watchlist']);
      await pumpEventQueue();
      expect(refresh.calls, [
        'clear',
        'watchlist',
        'local',
        'iptv',
        'trakt',
        'simkl',
        'eligible',
        'mdblist',
      ]);
      trakt.complete();
      simkl.complete();
      await pumpEventQueue();
      expect(refresh.calls, isNot(contains('bound')));
      mdblist.complete();
      await pending;
      expect(refresh.calls.last, 'bound');
    },
  );

  test(
    'dedicated Search consumes even an explicitly forced latch without tracker work',
    () async {
      refresh.controller.markPlaybackStarted();
      await refresh.run(search: true, force: true);
      expect(refresh.calls, ['clear', 'watchlist', 'local', 'iptv', 'bound']);
      expect(refresh.controller.playedSinceRefresh, isFalse);
    },
  );

  test(
    'forced refresh evaluates current MDBList scrobble eligibility after local reads',
    () async {
      final iptv = Completer<void>();
      refresh.steps['iptv'] = () => iptv.future;
      final pending = refresh.run(force: true);
      await pumpEventQueue();
      expect(refresh.calls, isNot(contains('eligible')));
      refresh.mdblistEligible = false;
      iptv.complete();
      await pending;
      expect(refresh.calls, [
        'clear',
        'watchlist',
        'local',
        'iptv',
        'trakt',
        'simkl',
        'eligible',
        'bound',
      ]);
    },
  );

  test(
    'overlapping returns keep both local refreshes and only the consumed tracker batch',
    () async {
      final reads = <Completer<void>>[];
      refresh.steps['watchlist'] = () {
        final next = Completer<void>();
        reads.add(next);
        return next.future;
      };
      refresh.controller.markPlaybackStarted();
      final first = refresh.run();
      final second = refresh.run();
      reads[1].complete();
      await second;
      expect(refresh.calls.where((call) => call == 'trakt'), isEmpty);
      reads[0].complete();
      await first;
      expect(refresh.calls.where((call) => call == 'trakt').length, 1);
      expect(refresh.calls.where((call) => call == 'bound').length, 2);
    },
  );

  test(
    'playback arriving during refresh remains latched for the next return',
    () async {
      final wait = Completer<void>();
      refresh.steps['watchlist'] = () => wait.future;
      final pending = refresh.run();
      refresh.controller.markPlaybackStarted();
      wait.complete();
      await pending;
      expect(refresh.controller.playedSinceRefresh, isTrue);
      expect(refresh.calls, isNot(contains('trakt')));
      await refresh.run();
      expect(refresh.controller.playedSinceRefresh, isFalse);
      expect(refresh.calls.where((call) => call == 'trakt').length, 1);
    },
  );

  for (final retirement in ['dispose', 'profile', 'handoff', 'unmounted']) {
    test(
      '$retirement stops later steps and rejects new refresh work',
      () async {
        final wait = Completer<void>();
        refresh.steps['watchlist'] = () => wait.future;
        refresh.controller.markPlaybackStarted();
        final pending = refresh.run();
        switch (retirement) {
          case 'dispose':
            refresh.container.dispose();
          case 'profile':
            ProfileRuntime.promoteLegacyToCommitted(
              ProfileScope(
                profileId: 'incoming',
                dataGeneration: 1,
                sessionEpoch: 1,
              ),
            );
          case 'handoff':
            ProfileSessionMemory.clearAll();
          case 'unmounted':
            refresh.current = false;
        }
        wait.complete();
        await pending;
        await refresh.run(force: true);
        expect(refresh.calls, ['clear', 'watchlist']);
      },
    );
  }

  test(
    'failures are reported once, skip later work and do not retry the consumed latch',
    () async {
      for (final failing in [
        'watchlist',
        'local',
        'iptv',
        'trakt',
        'mdblist',
        'bound',
      ]) {
        final attempt = RefreshHarness();
        final error = StateError(failing);
        attempt.steps[failing] = () => Future<void>.error(error);
        attempt.controller.markPlaybackStarted();
        await attempt.run();
        expect(attempt.errors, [same(error)]);
        expect(attempt.controller.playedSinceRefresh, isFalse);
        expect(attempt.calls.where((call) => call == failing).length, 1);
        if (failing != 'bound') expect(attempt.calls, isNot(contains('bound')));
      }
    },
  );

  test(
    'recomputation preserves a new playback latch while retiring an old refresh',
    () async {
      final wait = Completer<void>();
      refresh.steps['watchlist'] = () => wait.future;
      final pending = refresh.run();
      refresh.controller.markPlaybackStarted();
      refresh.container.invalidate(
        homePostPlaybackRefreshProvider(refresh.session),
      );
      expect(
        refresh.container.read(
          homePostPlaybackRefreshProvider(refresh.session),
        ),
        isTrue,
      );
      wait.complete();
      await pending;
      expect(refresh.calls, ['clear', 'watchlist']);
      expect(refresh.controller.playedSinceRefresh, isTrue);
      await refresh.run();
      expect(refresh.calls, contains('trakt'));
    },
  );

  test('two views never consume each other\'s playback latch', () async {
    final other = HomeCatalogSession(
      owner: refresh.session.owner,
      viewIdentity: Object(),
    );
    refresh.container.listen(homePostPlaybackRefreshProvider(other), (_, _) {});
    final second = refresh.container.read(
      homePostPlaybackRefreshProvider(other).notifier,
    );
    second.markPlaybackStarted();
    await refresh.run();
    expect(refresh.calls, isNot(contains('trakt')));
    expect(second.playedSinceRefresh, isTrue);
  });
}

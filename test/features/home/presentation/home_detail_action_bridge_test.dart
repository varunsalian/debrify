import 'dart:async';

import 'package:debrify/features/home/presentation/home_detail_action_bridge.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

class Fixture {
  bool current = true, live = true, search = false;
  final events = <String>[];
  Completer<void>? invocation, refresh;
  Object? failure;
  late final bridge = HomeDetailActionBridge(
    canStart: () => current && live,
    isCurrent: () => current,
    isSearch: () => search,
    clearResume: () => events.add('clear'),
    refreshLocal: () => reload('local'),
    refreshTrakt: () => reload('trakt'),
    refreshSimkl: () => reload('simkl'),
    refreshMdblist: () => reload('mdblist'),
  );
  Future<void> reload(String provider) async {
    events.add(provider);
    await refresh?.future;
  }

  Future<void> invoke([bool clearOnly = false]) async {
    events.add(clearOnly ? 'invoke-clear' : 'invoke');
    await invocation?.future;
    if (failure != null) throw failure!;
  }

  Future<void> trakt(TraktItemMenuAction action) => bridge.trakt(
    action,
    invoke: invoke,
    removeLocal: () async {
      events.add('remove-local');
    },
    removeTrakt: () async {
      events.add('remove-trakt');
    },
  );
  Future<void> simkl(SimklItemMenuAction action) =>
      bridge.simkl(action, invoke: invoke);
  Future<void> mdblist(MdblistItemMenuAction action) => bridge.mdblist(
    action,
    invoke: invoke,
    remove: () async {
      events.add('remove-mdblist');
    },
  );
}

void main() {
  test('leaving the detail page mid-action still refreshes rows', () async {
    // The page closing is not a reason to drop an accepted tracker write or
    // its refresh; only the view/profile being retired is.
    for (final (action, refresh) in [
      (TraktItemMenuAction.markWatched, 'trakt'),
      (TraktItemMenuAction.clearTraktProgress, 'trakt'),
    ]) {
      final f = Fixture()..invocation = Completer<void>();
      final done = f.trakt(action);
      f.live = false;
      f.invocation!.complete();
      await done;
      expect(f.events, ['invoke', refresh], reason: action.name);
    }
    final simkl = Fixture()..invocation = Completer<void>();
    final simklDone = simkl.simkl(SimklItemMenuAction.moveToCompleted);
    simkl.live = false;
    simkl.invocation!.complete();
    await simklDone;
    expect(simkl.events, ['invoke', 'simkl']);
  });

  test('a closed detail page cannot start a new action', () async {
    final f = Fixture()..live = false;
    await f.trakt(TraktItemMenuAction.markWatched);
    await f.simkl(SimklItemMenuAction.moveToCompleted);
    await f.mdblist(MdblistItemMenuAction.markWatched);
    expect(f.events, isEmpty);
  });

  for (final search in [false, true]) {
    test(
      'Trakt dispatch and refresh contracts for every action, search=$search',
      () async {
        for (final action in TraktItemMenuAction.values) {
          final f = Fixture()..search = search;
          await f.trakt(action);
          final expected = switch (action) {
            TraktItemMenuAction.clearWatchProgress => [
              'invoke-clear',
              'clear',
              'local',
              'trakt',
              'simkl',
              'mdblist',
            ],
            TraktItemMenuAction.removeFromPlayback => ['remove-local'],
            TraktItemMenuAction.removeFromTraktPlayback => ['remove-trakt'],
            TraktItemMenuAction.clearTraktProgress ||
            TraktItemMenuAction.markWatched ||
            TraktItemMenuAction.markUnwatched => [
              'invoke',
              if (!search) 'trakt',
            ],
            _ => ['invoke'],
          };
          expect(f.events, expected, reason: action.name);
        }
      },
    );
    test(
      'Simkl membership actions refresh only Home, search=$search',
      () async {
        const membership = {
          SimklItemMenuAction.clearWatchProgress,
          SimklItemMenuAction.removeFromContinueWatching,
          SimklItemMenuAction.removeFromList,
          SimklItemMenuAction.moveToCompleted,
          SimklItemMenuAction.moveToDropped,
          SimklItemMenuAction.moveToOnHold,
          SimklItemMenuAction.moveToWatching,
        };
        for (final action in SimklItemMenuAction.values) {
          final f = Fixture()..search = search;
          await f.simkl(action);
          expect(f.events, [
            'invoke',
            if (!search && membership.contains(action)) 'simkl',
          ], reason: action.name);
        }
      },
    );
    test(
      'MDBList removal is delegated once and watched changes refresh Home, search=$search',
      () async {
        const membership = {
          MdblistItemMenuAction.clearWatchProgress,
          MdblistItemMenuAction.markWatched,
          MdblistItemMenuAction.markUnwatched,
          MdblistItemMenuAction.drop,
          MdblistItemMenuAction.restore,
        };
        for (final action in MdblistItemMenuAction.values) {
          final f = Fixture()..search = search;
          await f.mdblist(action);
          expect(
            f.events,
            action == MdblistItemMenuAction.removeFromContinueWatching
                ? ['remove-mdblist']
                : [
                    'invoke',
                    if (!search && membership.contains(action)) 'mdblist',
                  ],
            reason: action.name,
          );
        }
      },
    );
  }

  test(
    'clear waits for action, then starts all four refreshes together',
    () async {
      final f = Fixture()
        ..invocation = Completer<void>()
        ..refresh = Completer<void>();
      var complete = false;
      final pending = f
          .trakt(TraktItemMenuAction.clearWatchProgress)
          .then((_) => complete = true);
      expect(f.events, ['invoke-clear']);
      f.invocation!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(f.events, [
        'invoke-clear',
        'clear',
        'local',
        'trakt',
        'simkl',
        'mdblist',
      ]);
      expect(complete, isFalse);
      f.refresh!.complete();
      await pending;
      expect(complete, isTrue);
    },
  );

  test('retired entry cannot dispatch handlers or removal', () async {
    final f = Fixture()..current = false;
    for (final action in TraktItemMenuAction.values) {
      await f.trakt(action);
    }
    for (final action in SimklItemMenuAction.values) {
      await f.simkl(action);
    }
    for (final action in MdblistItemMenuAction.values) {
      await f.mdblist(action);
    }
    expect(f.events, isEmpty);
  });

  for (final provider in ['trakt', 'simkl', 'mdblist']) {
    test(
      '$provider retirement during action suppresses refresh and cache invalidation',
      () async {
        final f = Fixture()..invocation = Completer<void>();
        final pending = switch (provider) {
          'trakt' => f.trakt(TraktItemMenuAction.clearWatchProgress),
          'simkl' => f.simkl(SimklItemMenuAction.moveToWatching),
          _ => f.mdblist(MdblistItemMenuAction.markWatched),
        };
        f.current = false;
        f.invocation!.complete();
        await pending;
        expect(f.events, [provider == 'trakt' ? 'invoke-clear' : 'invoke']);
      },
    );
  }

  test(
    'failed handler propagates original failure without refresh or retry',
    () async {
      final error = StateError('tracker failure');
      final f = Fixture()..failure = error;
      await expectLater(
        f.trakt(TraktItemMenuAction.markWatched),
        throwsA(same(error)),
      );
      expect(f.events, ['invoke']);
    },
  );

  test('Search mode is read after action completion', () async {
    final f = Fixture()..invocation = Completer<void>();
    final pending = f.simkl(SimklItemMenuAction.moveToWatching);
    f.search = true;
    f.invocation!.complete();
    await pending;
    expect(f.events, ['invoke']);
  });
}

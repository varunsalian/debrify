import 'dart:async';
import 'dart:convert';

import 'package:debrify/features/home/application/home_local_history_removal_dependencies.dart';
import 'package:debrify/services/playback_recovery_intent.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/local_history_removal.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  final history = jsonEncode([
    {'imdbId': 'tt1', 'title': 'Remove', 'contentType': 'movie'},
    {'imdbId': 'tt2', 'title': 'Keep', 'contentType': 'movie'},
  ]);
  final playback = jsonEncode({
    'imdb:tt1': {
      'imdbId': 'tt1',
      'type': 'movie',
      'positionMs': 50,
      'durationMs': 100,
    },
    'imdb:tt2': {
      'imdbId': 'tt2',
      'type': 'movie',
      'positionMs': 20,
      'durationMs': 100,
    },
  });
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(origin);
    PlaybackRecoveryIntent.debugSupportedOverride = true;
    SharedPreferences.setMockInitialValues({
      for (final scope in [origin, other]) ...{
        scope.preferenceKey('continue_watching_v1'): history,
        scope.preferenceKey('playback_state_v1'): playback,
      },
    });
  });
  tearDown(() async {
    await LocalHistoryRemoval.drain();
    WebDavSyncTombstoneRecorder.debugReset();
    PlaybackRecoveryIntent.debugReset();
    ProfileRuntime.debugReset();
  });

  test(
    'write failure reaches the caller and never strands lifecycle drain',
    () async {
      final release = Completer<void>();
      final error = StateError('storage unavailable');
      final writer = LocalHistoryRemoval(
        write: (_) async {
          await release.future;
          throw error;
        },
        isOwnerCurrent: () => true,
      );
      final operation = writer.remove('tt1', isCurrent: () => true);
      final assertion = expectLater(operation, throwsA(same(error)));
      var drained = false;
      final drain = LocalHistoryRemoval.drain().then((_) => drained = true);
      expect(drained, isFalse);
      release.complete();
      await assertion;
      await drain;
      expect(drained, isTrue);
    },
  );

  test('empty IDs and retired views do not start accepted work', () async {
    var calls = 0;
    final writer = LocalHistoryRemoval(
      write: (_) async {
        calls++;
      },
      isOwnerCurrent: () => true,
    );
    expect(await writer.remove(' ', isCurrent: () => true), isFalse);
    expect(await writer.remove('tt1', isCurrent: () => false), isFalse);
    expect(calls, 0);
    await LocalHistoryRemoval.drain();
  });

  for (final retire in [false, true]) {
    test(
      'accepted deletion finishes all origin records; retired=$retire',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        final journalProfiles = <String>[];
        WebDavSyncTombstoneRecorder.debugInstall(
          sink: (profile, keys) async {
            journalProfiles.add(profile);
            if (!entered.isCompleted) {
              entered.complete();
              await release.future;
            }
          },
        );
        final container = ProviderContainer.test();
        final writer = container.read(
          homeLocalHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
        );
        // Even a foreign ambient scope must not redirect this accepted action.
        final pending = ProfileRuntime.withCapturedScope(
          other,
          () => writer.remove('tt1', isCurrent: () => true),
        );
        await entered.future;
        var drained = false;
        final drain = LocalHistoryRemoval.drain().then((_) => drained = true);
        if (retire) {
          ProfileSessionMemory.clearAll();
          ProfileRuntime.publish(other);
        }
        await Future<void>.delayed(Duration.zero);
        expect(drained, isFalse);
        release.complete();
        expect(await pending, !retire);
        await drain;
        expect(drained, isTrue);
        final prefs = await SharedPreferences.getInstance();
        final remaining =
            jsonDecode(
                  prefs.getString(
                    origin.preferenceKey('continue_watching_v1'),
                  )!,
                )
                as List;
        expect(remaining.map((item) => item['imdbId']), ['tt2']);
        final positions =
            jsonDecode(
                  prefs.getString(origin.preferenceKey('playback_state_v1'))!,
                )
                as Map;
        expect(positions.keys, ['imdb:tt2']);
        expect(
          prefs.getString(other.preferenceKey('continue_watching_v1')),
          history,
        );
        expect(
          prefs.getString(other.preferenceKey('playback_state_v1')),
          playback,
        );
        expect(journalProfiles, isNotEmpty);
        expect(journalProfiles.toSet(), {'origin'});
        expect(
          prefs.getString(
            origin.preferenceKey('remote_tv_playback_recovery_deletions_v1'),
          ),
          isNotNull,
        );
        expect(
          prefs.getString(
            other.preferenceKey('remote_tv_playback_recovery_deletions_v1'),
          ),
          isNull,
        );
      },
    );
  }

  test('retired action cannot start writes or journals', () async {
    var journals = 0;
    WebDavSyncTombstoneRecorder.debugInstall(sink: (_, _) => journals++);
    final container = ProviderContainer.test();
    final writer = container.read(
      homeLocalHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
    );
    ProfileSessionMemory.clearAll();
    expect(await writer.remove('tt1', isCurrent: () => true), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(origin.preferenceKey('continue_watching_v1')),
      history,
    );
    expect(journals, 0);
  });

  test(
    'accepted operation waiting on snapshot does not hold a nested mutation lock',
    () async {
      WebDavSyncTombstoneRecorder.debugInstall(sink: (_, _) {});
      final entered = Completer<void>(), release = Completer<void>();
      final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final container = ProviderContainer.test();
      final writer = container.read(
        homeLocalHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
      );
      final removal = writer.remove('tt1', isCurrent: () => true);
      release.complete();
      await snapshot;
      await removal.timeout(const Duration(seconds: 5));
      await LocalHistoryRemoval.drain();
    },
  );
}

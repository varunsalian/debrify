import 'dart:async';

import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const key = 'default_torrent_provider_v1';
  final first = ProfileScope(
    profileId: 'first',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final second = ProfileScope(
    profileId: 'second',
    dataGeneration: 1,
    sessionEpoch: 2,
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfilePreferences.debugResetMutationTracking();
    ProfileRuntime.initializeCommitted(first);
  });
  tearDown(ProfileRuntime.debugReset);

  test(
    'legacy caller and current guarded choice retain the same scalar key',
    () async {
      await StorageService.setDefaultTorrentProvider('debrid');
      final raw = await SharedPreferences.getInstance();
      expect(raw.getString(first.preferenceKey(key)), 'debrid');
      await StorageService.setDefaultTorrentProvider(
        'torbox',
        canContinue: () => true,
      );
      expect(raw.getString(first.preferenceKey(key)), 'torbox');
      expect(raw.getString(second.preferenceKey(key)), isNull);
    },
  );

  test('retired action does not write a choice', () async {
    await StorageService.setDefaultTorrentProvider(
      'torbox',
      canContinue: () => false,
    );
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('guarded choice ignores a foreign captured profile zone', () async {
    final owner = ProfileSessionMemory.captureOwner();
    await ProfileRuntime.withCapturedScope(
      second,
      () => StorageService.setDefaultTorrentProvider(
        'torbox',
        canContinue: () => owner == ProfileSessionMemory.captureOwner(),
      ),
    );
    final raw = await SharedPreferences.getInstance();
    expect(raw.getString(first.preferenceKey(key)), 'torbox');
    expect(raw.getString(second.preferenceKey(key)), isNull);
  });

  test(
    'current preference failures propagate and leave the mutation queue usable',
    () async {
      await expectLater(
        ProfilePreferences.captureMutationSnapshot(
          (_) => StorageService.setDefaultTorrentProvider(
            'torbox',
            canContinue: () => true,
          ),
        ),
        throwsStateError,
      );
      final raw = await SharedPreferences.getInstance();
      expect(raw.getString(first.preferenceKey(key)), isNull);
      await StorageService.setDefaultTorrentProvider(
        'torbox',
        canContinue: () => true,
      );
      expect(raw.getString(first.preferenceKey(key)), 'torbox');
    },
  );

  for (final retirement in ['view', 'switch', 'clear', 'none']) {
    test('queued choice rechecks ownership after $retirement', () async {
      final raw = await SharedPreferences.getInstance();
      await raw.setString(second.preferenceKey(key), 'incoming');
      final owner = ProfileSessionMemory.captureOwner();
      var viewActive = true;
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final barrier = ProfilePreferences.captureMutationSnapshot((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      var finished = false;
      final write = StorageService.setDefaultTorrentProvider(
        'torbox',
        canContinue: () =>
            viewActive && owner == ProfileSessionMemory.captureOwner(),
      ).whenComplete(() => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      if (retirement == 'view') {
        viewActive = false;
      } else if (retirement == 'switch') {
        ProfileRuntime.publish(second);
      } else if (retirement == 'clear') {
        ProfileSessionMemory.clearAll();
      }
      release.complete();
      await barrier;
      await write;
      expect(
        raw.getString(first.preferenceKey(key)),
        retirement == 'none' ? 'torbox' : null,
      );
      expect(raw.getString(second.preferenceKey(key)), 'incoming');
    });
  }
}

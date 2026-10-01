import 'dart:async';
import 'package:debrify/features/discover/application/discover_providers.dart';
import 'package:debrify/features/discover/data/discover_source_repository.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage/discover_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfilePreferences.debugResetMutationTracking();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfileRuntime.debugReset);
  DiscoverSourceRepository repository() {
    final container = ProviderContainer.test();
    final key = (
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      initialSource: 'cw',
      hasHandoff: false,
    );
    container.listen(discoverSourceRepositoryProvider(key), (_, _) {});
    return container.read(discoverSourceRepositoryProvider(key));
  }

  test(
    'default adapter preserves remembered and fixed preference formats',
    () async {
      final repo = repository();
      expect(await repo.readLanding(), 'cw');
      await DiscoverStorage.setDiscoverLastSource('simkl');
      expect(await repo.readLanding(), 'simkl');
      await DiscoverStorage.setDiscoverDefaultSource('trakt');
      expect(await repo.readLanding(), 'trakt');
      await repo.writeLast('a:fixture', () => true);
      expect(await DiscoverStorage.getDiscoverLastSource(), 'a:fixture');
      await repo.writeLast('invalid-source', () => true);
      expect(await DiscoverStorage.getDiscoverLastSource(), 'a:fixture');
    },
  );
  for (final retirement in ['selection', 'profile']) {
    test(
      '$retirement retirement behind the mutation barrier prevents a stale write',
      () async {
        final repo = repository();
        final entered = Completer<void>();
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        var current = true;
        var finished = false;
        final pending = repo
            .writeLast('trakt', () => current)
            .whenComplete(() => finished = true);
        await Future<void>.delayed(Duration.zero);
        expect(finished, isFalse);
        if (retirement == 'selection') {
          current = false;
        } else {
          ProfileSessionMemory.clearAll();
        }
        release.complete();
        await snapshot;
        await pending;
        expect(await DiscoverStorage.getDiscoverLastSource(), 'cw');
      },
    );
  }
  test(
    'active guarded write still commits after the mutation barrier',
    () async {
      final repo = repository();
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final pending = repo.writeLast('simkl', () => true);
      release.complete();
      await snapshot;
      await pending;
      expect(await DiscoverStorage.getDiscoverLastSource(), 'simkl');
    },
  );
}

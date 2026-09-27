import 'package:debrify/features/home/data/home_return_repository.dart';
import 'package:debrify/features/home/models/home_return_snapshot.dart';
import 'package:debrify/features/home/models/home_board_configuration.dart';
import 'package:debrify/features/home/models/home_catalog_state.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/hide_watched_prefs.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

HomeReturnSnapshot returnSnapshot({DateTime? loadedAt, double scroll = 42}) => (
  sections: [],
  board: HomeCatalogSnapshot([], 0, {}),
  configuration: const HomeBoardConfiguration.empty(),
  hero: null,
  heroResolutionPending: true,
  cardOrientation: HomeCardOrientation.landscape,
  hideCardTitlesAndRatings: true,
  hideCatalogAddonNames: false,
  hideCollectionNames: true,
  loadedAt: loadedAt ?? DateTime.now(),
  scrollOffset: scroll,
);
HomeReturnRepository returnRepository() =>
    HomeReturnRepository(owner: ProfileSessionMemory.captureOwner());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.clearAll();
    HideWatchedPrefs.debugReset();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    ProfileSessionMemory.clearAll();
    ProfileRuntime.debugReset();
    HideWatchedPrefs.debugReset();
  });

  test(
    'fresh adapters share one consume-once store across repeated visits',
    () {
      final initial = returnRepository();
      initial.store(returnSnapshot(), revision: initial.revision);
      initial.take();
      final registered = ProfileSessionMemory.debugRegisteredStoreCount;
      for (var visit = 0; visit < 100; visit++) {
        final outgoing = returnRepository();
        final saved = returnSnapshot(scroll: visit.toDouble());
        outgoing.store(saved, revision: outgoing.revision);
        final incoming = returnRepository();
        expect(incoming.take(), saved);
        expect(returnRepository().take(), isNull);
        expect(ProfileSessionMemory.debugRegisteredStoreCount, registered);
      }
    },
  );
  test(
    'expiry remains anchored to original load, including the five-minute boundary',
    () {
      final loaded = DateTime.utc(2026, 9, 1);
      final saved = returnSnapshot(loadedAt: loaded);
      final repo = returnRepository();
      repo.store(saved, revision: repo.revision);
      expect(repo.take(now: loaded.add(const Duration(minutes: 4))), saved);
      repo.store(saved, revision: repo.revision);
      expect(repo.take(now: loaded.add(const Duration(minutes: 5))), isNull);
      expect(repo.take(now: loaded), isNull);
    },
  );
  test(
    'retired store and take cannot overwrite or consume an incoming snapshot',
    () {
      final old = returnRepository();
      final oldRevision = old.revision;
      ProfileSessionMemory.clearAll();
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'next', dataGeneration: 1, sessionEpoch: 1),
      );
      final current = returnRepository();
      final saved = returnSnapshot(scroll: 99);
      current.store(saved, revision: current.revision);
      old.store(returnSnapshot(), revision: oldRevision);
      expect(old.take(), isNull);
      expect(current.take(), saved);
    },
  );
  test(
    'one metadata listener survives repeated adapters and invalidates late stores',
    () async {
      for (var i = 0; i < 100; i++) {
        returnRepository().observeInvalidation();
      }
      await Future<void>.delayed(Duration.zero);
      final repo = returnRepository();
      final revision = repo.revision;
      repo.store(returnSnapshot(), revision: revision);
      MetadataPreferencesService.revision.value++;
      expect(repo.revision, revision + 1);
      expect(repo.take(), isNull);
      repo.store(returnSnapshot(), revision: revision);
      expect(repo.take(), isNull);
    },
  );
  test(
    'watched changes invalidate only while hidden-watched filtering is enabled',
    () async {
      final repo = returnRepository();
      repo.observeInvalidation();
      await Future<void>.delayed(Duration.zero);
      final before = repo.revision;
      await StorageService.setHomeTickSources({});
      await Future<void>.delayed(Duration.zero);
      expect(repo.revision, before);
      await HideWatchedPrefs.setEnabled(true);
      await StorageService.setHomeTickSources({TrackingSource.local});
      await Future<void>.delayed(Duration.zero);
      expect(repo.revision, before + 1);
    },
  );
}

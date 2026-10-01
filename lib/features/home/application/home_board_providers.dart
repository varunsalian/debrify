import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/metadata/metadata_presentation_cache.dart';
import '../../../models/profiles/profile_policy.dart';
import '../../../services/diagnostic_log.dart';
import '../../../services/hide_watched_prefs.dart';
import '../../../services/home_collections_store.dart';
import '../../../services/home_list_rows.dart';
import '../../../services/metadata_preferences_service.dart';
import '../../../services/metadata_provider_service.dart';
import '../../../services/profiles/profile_policy_guard.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/series_source_service.dart';
import '../../../services/storage_service.dart';
import '../../../services/stremio_service.dart';
import '../../../services/watched_filter.dart';
import '../../../services/watched_status_service.dart';
import '../data/home_board_services.dart';
import '../data/home_bound_counts_repository.dart';
import '../data/home_card_metadata_repository.dart';
import '../data/home_catalog_preferences_repository.dart';
import '../data/home_catalog_repository.dart';
import '../data/home_collections_repository.dart';
import '../data/home_display_preferences_repository.dart';
import '../data/home_layout_preferences.dart';
import '../data/home_pikpak_only_repository.dart';
import '../data/home_return_repository.dart';
import '../models/home_card_metadata.dart';
import '../models/home_catalog_session.dart';
import 'home_default_view.dart';
import 'home_layout_preference.dart';
import 'home_settings_refresh.dart';

final homeBoardServicesProvider = Provider<HomeBoardServices>(
  (ref) => HomeBoardServices(
    hideWatched: () => HideWatchedPrefs.enabled,
    startWatched: () => WatchedStatusService.instance.ensureStarted(),
    firstWatchedSnapshot: () => WatchedStatusService.instance.firstSnapshot,
    resolveLists:
        (extras, {required previous, required isCurrent, required onUpdate}) =>
            HomeListRowsService.instance.resolve(
              extras,
              previous: previous,
              isCurrent: isCurrent,
              onUpdate: onUpdate,
            ),
    claimedCatalogs: HomeCollectionsStore.claimedCatalogKeys,
  ),
  dependencies: const [],
);

final homeBoundCountsRepositoryProvider = Provider.autoDispose
    .family<HomeBoundCountsRepository, HomeCatalogSession>(
      (ref, session) => HomeBoundCountsRepository(
        readCount: (id, current) async {
          bool active() =>
              session.owner == ProfileSessionMemory.captureOwner() && current();
          Future<int> read() async => (await SeriesSourceService.getSources(
            id,
            canContinue: active,
          )).length;
          final scope = session.owner.scope;
          return scope == null
              ? read()
              : ProfileRuntime.withCapturedScope(scope, read);
        },
      ),
      retry: (count, error) => null,
      dependencies: const [],
    );

final homeCardMetadataEpochProvider =
    Provider.autoDispose<HomeCardMetadataEpoch>(
      (ref) {
        void changed() => ref.invalidateSelf();
        MetadataPreferencesService.revision.addListener(changed);
        ProfileRuntime.scope.addListener(changed);
        ref.onDispose(() {
          MetadataPreferencesService.revision.removeListener(changed);
          ProfileRuntime.scope.removeListener(changed);
        });
        return (
          owner: ProfileSessionMemory.captureOwner(),
          revision: MetadataPreferencesService.revision.value,
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );

final homeCardMetadataRepositoryProvider = Provider.autoDispose
    .family<HomeCardMetadataRepository, HomeCardMetadataEpoch>(
      (ref, epoch) {
        bool current() =>
            epoch.owner == ProfileSessionMemory.captureOwner() &&
            epoch.revision == MetadataPreferencesService.revision.value;
        Future<T> read<T>(Future<T> Function() action) {
          if (!current()) {
            return Future.error(StateError('Retired metadata session'));
          }
          final scope = epoch.owner.scope;
          return scope == null
              ? action()
              : ProfileRuntime.withCapturedScope(scope, action);
        }

        return HomeCardMetadataRepository(
          epoch: epoch,
          cache: MetadataPresentationCache.shared,
          isCurrent: current,
          readPreferences: () => read(MetadataPreferencesService.load),
          present: (item, preferences, relevant) => read(
            () => MetadataProviderService.instance.present(
              item,
              preferences: preferences,
              isRelevant: () => current() && relevant(),
            ),
          ),
          recordReady: (diagnostic) => DiagnosticLog.instance.recordEvent(
            source: 'metadata',
            event: 'presentation_ready',
            fields: {
              'elapsed_ms': diagnostic.elapsedMs,
              'retryable': diagnostic.retryable,
              'cache_hit': diagnostic.cacheHit,
              'attempt': diagnostic.attempt,
              'missing': diagnostic.missing,
            },
          ),
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );

final homeCatalogRepositoryProvider = Provider<HomeCatalogRepository>(
  (ref) => HomeCatalogRepository(
    readAddons: StremioService.instance.getCatalogAddons,
    fetchPage: (addon, catalog, skip, onRawCount) => StremioService.instance
        .fetchCatalog(addon, catalog, skip: skip, onRawCount: onRawCount),
    readHides: () => WatchedFilter.predicate,
  ),
  dependencies: const [],
);

final homeCatalogPreferencesRepositoryProvider =
    Provider<HomeCatalogPreferencesRepository>(
      (ref) => const HomeCatalogPreferencesRepository(
        readDisabled: StorageService.getHomeDisabledSections,
        readExtras: StorageService.getHomeExtraRows,
        readRowOrder: StorageService.getHomeRowOrder,
        readHeroSource: StorageService.getHomeHeroSource,
      ),
      dependencies: const [],
    );

final homeCollectionsRepositoryProvider = Provider<HomeCollectionsRepository>(
  (ref) => HomeCollectionsRepository(
    read: HomeCollectionsStore.instance.getCollections,
    signature: HomeCollectionsStore.signatureOfAsync,
    onReadFailure: () =>
        debugPrint('Home: saved collections could not be loaded'),
  ),
  dependencies: const [],
);

final homeDefaultViewReaderProvider = Provider<Future<String?> Function()>(
  (ref) => StorageService.getHomeDefaultSourceType,
  dependencies: const [],
);

/// Shares the mounted Home/catalog view identity, not its inventory or state.
final homeDefaultViewProvider = Provider.autoDispose
    .family<HomeDefaultView, HomeCatalogSession>(
      (ref, session) {
        final operation = HomeDefaultView(
          readSaved: ref.watch(homeDefaultViewReaderProvider),
          keywordAllowed: () =>
              ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch),
          isOwnerCurrent: () =>
              session.owner == ProfileSessionMemory.captureOwner(),
        );
        ref.onDispose(operation.dispose);
        return operation;
      },
      retry: (count, error) => null,
      dependencies: [homeDefaultViewReaderProvider],
    );

final homeDisplayPreferencesRepositoryProvider =
    Provider<HomeDisplayPreferencesRepository>(
      (ref) => const HomeDisplayPreferencesRepository(
        readFocusDetails: StorageService.getSpotlightFocusDetails,
        readAnimationsEnabled: StorageService.getHomeAnimationsEnabled,
        readAnimationStyle: StorageService.getHomeAnimationStyle,
        readOrientation: StorageService.getHomeCardOrientation,
        readHideTitles: StorageService.getHomeHideCardTitlesAndRatings,
        readHideAddonNames: StorageService.getHomeHideCatalogAddonNames,
        readHideCollectionNames: StorageService.getHomeHideCollectionNames,
      ),
      dependencies: const [],
    );

final homeLayoutPreferencesProvider = Provider<HomeLayoutPreferences>(
  (ref) => HomeLayoutPreferences(
    readCached: () => StorageService.tvHomeStyleCached,
    readSaved: StorageService.getTvHomeStyle,
  ),
  dependencies: const [],
);

final homeLayoutPreferenceProvider = Provider.autoDispose
    .family<HomeLayoutPreference, HomeCatalogSession>(
      (ref, session) {
        final preferences = ref.watch(homeLayoutPreferencesProvider);
        final scope = session.owner.scope;
        final operation = HomeLayoutPreference(
          initialStyle: preferences.readCached(),
          readSaved: () => scope == null
              ? preferences.readSaved()
              : ProfileRuntime.withCapturedScope(scope, preferences.readSaved),
          isOwnerCurrent: () =>
              session.owner == ProfileSessionMemory.captureOwner(),
        );
        ref.onDispose(operation.dispose);
        return operation;
      },
      retry: (count, error) => null,
      dependencies: [homeLayoutPreferencesProvider],
    );

final homePikpakOnlyRepositoryProvider = Provider.autoDispose
    .family<HomePikpakOnlyRepository, HomeCatalogSession>(
      (ref, session) {
        bool Function() guarded(bool Function() current) =>
            () =>
                session.owner == ProfileSessionMemory.captureOwner() &&
                current();
        return HomePikpakOnlyRepository(
          readPikpakEnabled: (current) =>
              StorageService.getPikPakEnabled(canContinue: guarded(current)),
          readRealDebrid: (current) =>
              StorageService.getApiKey(canContinue: guarded(current)),
          readTorbox: (current) =>
              StorageService.getTorboxApiKey(canContinue: guarded(current)),
          readPremiumize: (current) =>
              StorageService.getPremiumizeApiKey(canContinue: guarded(current)),
          readAllDebrid: (current) =>
              StorageService.getAllDebridApiKey(canContinue: guarded(current)),
        );
      },
      retry: (count, error) => null,
      dependencies: const [],
    );

/// Consumption precedes catalog-session bootstrap. Provider disposal does not
/// dispose the borrowed process cache or invalidate a completed return snapshot.
final homeReturnRepositoryProvider = Provider.autoDispose
    .family<HomeReturnRepository, ProfileSessionOwner>(
      (ref, owner) => HomeReturnRepository(owner: owner),
      retry: (count, error) => null,
    );

final homeSettingsRefreshProvider = Provider.autoDispose
    .family<HomeSettingsRefresh, HomeCatalogSession>(
      (ref, session) {
        final collectionSession = HomeCollectionsStore.captureSession();
        final operation = HomeSettingsRefresh(
          isOwnerCurrent: () =>
              session.owner == ProfileSessionMemory.captureOwner() &&
              collectionSession == HomeCollectionsStore.captureSession(),
        );
        ref.onDispose(operation.dispose);
        return operation;
      },
      retry: (count, error) => null,
      dependencies: const [],
    );

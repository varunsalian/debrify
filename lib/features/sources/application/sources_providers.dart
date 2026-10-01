import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/platform/system_clipboard.dart';
import '../../../models/profiles/profile_policy.dart';
import '../../../services/iptv_source_search.dart';
import '../../../services/media_server_service.dart';
import '../../../services/profiles/profile_policy_guard.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/automatic_source_bindings.dart';
import '../data/debrid_source_cache_repository.dart';
import '../data/manual_source_preparation.dart';
import '../data/saved_sources_repository.dart';
import '../data/service_source_search_repository.dart';
import '../data/source_acquisition.dart';
import '../data/source_binding_matcher.dart';
import '../data/source_cache_repository.dart';
import '../data/source_download.dart';
import '../data/source_link_copier.dart';
import '../data/source_row_action_policy.dart';
import '../data/source_search_repository.dart';
import '../data/source_seasons_repository.dart';
import '../data/source_settings_repository.dart';
import '../data/stored_saved_sources_repository.dart';
import '../data/stored_source_settings_repository.dart';
import '../data/stremio_source_seasons_repository.dart';
import '../models/sources_session.dart';

final savedSourcesRepositoryProvider = Provider.autoDispose
    .family<SavedSourcesRepository, SourcesSession>(
      (ref, session) => StoredSavedSourcesRepository(session),
      retry: (count, error) => null,
      dependencies: const [],
    );

final sourceAcquisitionProvider = Provider<SourceAcquisition>(
  (ref) => const SourceAcquisition(),
);

final manualSourcePreparationProvider = Provider<ManualSourcePreparation>(
  (ref) => ManualSourcePreparation(
    acquisition: ref.watch(sourceAcquisitionProvider),
  ),
  dependencies: [sourceAcquisitionProvider],
);

/// App-scoped stateless adapter. Identity lookups occur on demand, never cached.
final sourceBindingMatcherProvider = Provider<SourceBindingMatcher>(
  (ref) => SourceBindingMatcher(
    mediaServerKeyFor: (torrent) =>
        MediaServerService.bindingFor(torrent)?.bindingKey,
    isIptv: IptvSourceSearch.owns,
  ),
  dependencies: const [],
);

final sourceCacheRepositoryProvider = Provider.autoDispose
    .family<SourceCacheRepository, SourcesSession>(
      (ref, session) => DebridSourceCacheRepository(owner: session.owner),
      retry: (count, error) => null,
      dependencies: const [],
    );

/// App-scoped immutable dependencies only. Each copy gets its view/session guard.
final sourceLinkCopierProvider = Provider<SourceLinkCopier>(
  (ref) => SourceLinkCopier(
    isDeferredEpisode: IptvSourceSearch.isDeferredXtreamSeries,
    resolveEpisode: IptvSourceSearch.resolveXtreamSeriesEpisode,
    writeText: writeSystemClipboardText,
  ),
);

final automaticSourceBindingsFactoryProvider =
    Provider<AutomaticSourceBindings Function()>(
      (ref) => AutomaticSourceBindings.capture,
    );

final sourceDownloadProvider = Provider<SourceDownload>(
  (ref) => const SourceDownload(),
);

final sourceRowActionPolicyProvider = Provider<SourceRowActionPolicy>(
  (ref) => SourceRowActionPolicy(
    isMediaServer: MediaServerService.owns,
    isIptv: IptvSourceSearch.owns,
    downloadsAllowed: () =>
        ProfilePolicyGuard.allowsSync(ProfileFeature.downloads),
  ),
  dependencies: const [],
);

final sourceSearchRepositoryProvider = Provider.autoDispose
    .family<SourceSearchRepository, SourcesSession>(
      (ref, session) => ServiceSourceSearchRepository(owner: session.owner),
      retry: (count, error) => null,
      dependencies: const [],
    );

final sourceSeasonsRepositoryProvider = Provider.autoDispose
    .family<SourceSeasonsRepository, SourcesSession>(
      (ref, session) => StremioSourceSeasonsRepository(session),
      retry: (count, error) => null,
      dependencies: const [],
    );

final sourcesSessionActiveProvider = Provider.autoDispose
    .family<bool, SourcesSession>(
      (ref, session) {
        void changed() => ref.invalidateSelf();
        ProfileRuntime.scope.addListener(changed);
        ref.onDispose(() => ProfileRuntime.scope.removeListener(changed));
        return session.owner == ProfileSessionMemory.captureOwner();
      },
      retry: (count, error) => null,
      dependencies: const [],
    );

final sourceSettingsRepositoryProvider = Provider.autoDispose
    .family<SourceSettingsRepository, SourcesSession>(
      (ref, session) => StoredSourceSettingsRepository(session),
      retry: (count, error) => null,
      dependencies: const [],
    );

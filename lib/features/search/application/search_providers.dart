import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/source_appearance.dart';
import '../../../services/engine/settings_manager.dart';
import '../../../services/mdblist/mdblist_list_source.dart';
import '../../../services/mdblist/mdblist_service.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/source_appearance_preferences.dart';
import '../../../services/stremio_service.dart';
import '../../../services/torrent_service.dart';
import '../data/catalog_search_repository.dart';
import '../data/debrid_keyword_cache_repository.dart';
import '../data/engine_keyword_search_repository.dart';
import '../data/engine_keyword_sources_repository.dart';
import '../data/keyword_cache_repository.dart';
import '../data/keyword_defaults_repository.dart';
import '../data/keyword_search_repository.dart';
import '../data/keyword_snapshot_repository.dart';
import '../data/keyword_sources_repository.dart';
import '../data/lists_search_repository.dart';
import '../data/mdblist_search_repository.dart';
import '../data/memory_keyword_snapshot_repository.dart';
import '../data/stored_keyword_defaults_repository.dart';
import '../data/stremio_catalog_search_repository.dart';
import '../models/search_session.dart';

final catalogSearchRepositoryProvider = Provider.autoDispose
    .family<CatalogSearchRepository, SearchSession>(
      (ref, session) => StremioCatalogSearchRepository(
        owner: session.owner,
        service: StremioService.instance,
      ),
      retry: (count, error) => null,
    );

final keywordAppearanceReaderProvider = Provider.autoDispose
    .family<SourceAppearanceReader, SearchSession>(
      (ref, session) =>
          () => readSourceAppearance(session.owner),
      retry: (count, error) => null,
      dependencies: const [],
    );

final keywordCacheRepositoryProvider = Provider.autoDispose
    .family<KeywordCacheRepository, SearchSession>(
      (ref, session) => DebridKeywordCacheRepository(owner: session.owner),
      retry: (count, error) => null,
    );

final keywordDefaultsRepositoryProvider = Provider.autoDispose
    .family<KeywordDefaultsRepository, SearchSession>(
      (ref, session) => StoredKeywordDefaultsRepository(owner: session.owner),
      retry: (count, error) => null,
    );

final keywordSearchRepositoryProvider = Provider.autoDispose
    .family<KeywordSearchRepository, SearchSession>(
      (ref, session) => EngineKeywordSearchRepository(owner: session.owner),
      retry: (count, error) => null,
    );

/// Snapshot consumption precedes SearchSession bootstrap. This dependency is
/// keyed by its captured owner; variant matching stays explicit on each take.
/// The screen retains the plain adapter for disposal, without a WidgetRef read.
final keywordSnapshotRepositoryProvider = Provider.autoDispose
    .family<KeywordSnapshotRepository, ProfileSessionOwner>(
      (ref, owner) => MemoryKeywordSnapshotRepository(owner: owner),
      retry: (count, error) => null,
    );

final keywordSourcesRepositoryProvider = Provider.autoDispose
    .family<KeywordSourcesRepository, SearchSession>(
      (ref, session) => EngineKeywordSourcesRepository(
        owner: session.owner,
        settings: SettingsManager(),
        engines: TorrentService.getKeywordSearchEngines,
      ),
      retry: (count, error) => null,
    );

final listsSearchRepositoryProvider = Provider.autoDispose
    .family<ListsSearchRepository, SearchSession>(
      (ref, session) => MdblistSearchRepository(
        owner: session.owner,
        service: MdblistService.instance,
        source: MdblistListSource.instance,
      ),
      retry: (count, error) => null,
    );

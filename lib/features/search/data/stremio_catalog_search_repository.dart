import 'dart:convert';

import 'package:debrify/services/storage/torrent_search_storage.dart';
import '../../../models/stremio_addon.dart';
import '../../../services/profiles/profile_preferences.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/stremio_service.dart';
import '../../../services/watched_filter.dart';
import '../models/catalog_search_row.dart';
import 'catalog_search_repository.dart';

/// Borrows Stremio's existing service/cache and profile-aware preferences. No
/// new retry owner, credentials store or persistence format is introduced.
class StremioCatalogSearchRepository implements CatalogSearchRepository {
  final ProfileSessionOwner owner;
  final StremioService service;

  const StremioCatalogSearchRepository({
    required this.owner,
    required this.service,
  });

  @override
  bool get isCurrent => owner == ProfileSessionMemory.captureOwner();

  Future<T> _inScope<T>(Future<T> Function() action) {
    final scope = owner.scope;
    return scope == null
        ? action()
        : ProfileRuntime.withCapturedScope(scope, action);
  }

  @override
  Future<List<StremioAddon>> searchableAddons() => isCurrent
      ? _inScope(service.getSearchableAddons)
      : Future.value(const []);

  @override
  Future<Set<String>> readDisabledAddons() => isCurrent
      ? _inScope(TorrentSearchStorage.getCatalogSearchDisabledAddons)
      : Future.value(const {});

  @override
  Future<void> writeDisabledAddons(Set<String> disabled) async {
    if (!isCurrent) return;
    final snapshot = Set<String>.of(disabled);
    final prefs = await _inScope(ProfilePreferences.instance);
    if (!isCurrent) return;
    // Preserve StorageService's existing key/JSON format. Acquire the facade
    // under the captured scope, but write OUTSIDE that zone: its live-session
    // assertions then reject a switch during a preference mutation barrier.
    // Keeping the captured zone across the write would mask that handoff.
    const key = 'catalog_search_disabled_addons_v1';
    if (snapshot.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(snapshot.toList()));
    }
  }

  @override
  Future<CatalogSearchRow?> searchCatalog(
    StremioAddon addon,
    StremioAddonCatalog catalog,
    String query,
  ) async {
    if (!isCurrent) return null;
    var rawCount = 0;
    final items = await _inScope(
      () => service.searchSingleCatalog(
        addon,
        catalog,
        query,
        throwOnError: true,
        onRawCount: (count) => rawCount = count,
      ),
    );
    if (!isCurrent) return null;
    // Search does not top up watched-only rows. The expanded catalog receives
    // the RAW first-page offset, including any invalid/hidden metadata entries.
    final visible = WatchedFilter.apply(items);
    if (visible.isEmpty) return null;
    return CatalogSearchRow(
      addon: addon,
      catalog: catalog,
      items: visible,
      query: query,
      nextSkip: rawCount > 0 ? rawCount : visible.length,
    );
  }
}

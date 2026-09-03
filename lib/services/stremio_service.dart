import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/stremio_addon.dart';
import '../models/torrent.dart';
import '../utils/concurrency.dart';
import '../utils/json_isolate.dart';
import '../utils/stremio_url.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_collection_resource_facade.dart';
import 'profiles/connection_resource_service.dart';
import 'profiles/profile_async_authorization.dart';
import '../models/profiles/connection_resource.dart';
import '../models/profiles/profile_policy.dart';

/// One addon's outcome for a single stream search — lets the source provider
/// row retain retry controls for addons that failed or returned nothing (the
/// count maps alone lose zero-count addons once counts are rebuilt from the
/// final rows).
///
/// [sourceKey] matches `Torrent.source` (`stremio:<name>` lowercased);
/// [count] is the addon's RAW stream count before cross-addon dedupe, so
/// "returned something that deduped away" still reads as activity.
class AddonSearchStatus {
  final String addonId;
  final String name;
  final String sourceKey;
  final int count;
  final String? error;

  const AddonSearchStatus({
    required this.addonId,
    required this.name,
    required this.sourceKey,
    required this.count,
    this.error,
  });

  bool get failed => error != null;

  AddonSearchStatus withResult(int count) => AddonSearchStatus(
    addonId: addonId,
    name: name,
    sourceKey: sourceKey,
    count: count,
  );
}

class StremioAddonImportResult {
  final int discovered;
  final int imported;
  final int skippedDuplicates;
  final int skippedUnsupported;
  final int failed;
  final List<String> importedNames;
  final List<String> skippedNames;
  final List<String> errors;

  const StremioAddonImportResult({
    required this.discovered,
    required this.imported,
    required this.skippedDuplicates,
    required this.skippedUnsupported,
    required this.failed,
    this.importedNames = const [],
    this.skippedNames = const [],
    this.errors = const [],
  });

  bool get hasChanges => imported > 0;
}

/// Result of a bulk "update all" addon refresh.
class StremioAddonRefreshResult {
  /// Manifests that came back with a different version string.
  final int updated;

  /// Manifests refreshed successfully but with no version change.
  final int unchanged;

  /// Manifests that could not be fetched.
  final int failed;

  final List<String> updatedNames;
  final List<String> failedNames;

  const StremioAddonRefreshResult({
    required this.updated,
    required this.unchanged,
    required this.failed,
    this.updatedNames = const [],
    this.failedNames = const [],
  });

  int get total => updated + unchanged + failed;
}

/// Service for managing Stremio addons and searching for streams.
///
/// This service provides:
/// - Addon management (add, remove, enable/disable)
/// - Manifest fetching and validation
/// - Stream search across all enabled addons
/// - Conversion of Stremio streams to Torrent objects
class StremioService {
  static const String _addonsKey = 'stremio_addons_v1';
  static const String _metadataProviderKey = 'stremio_metadata_provider_v1';
  static const String automaticMetadataProvider = 'automatic';
  static const Duration _requestTimeout = Duration(seconds: 15);

  /// User-initiated retries can wait longer than the automatic search without
  /// making every source lookup block on a slow addon.
  static const Duration manualRetryTimeout = Duration(minutes: 1);

  // Singleton pattern
  static final StremioService _instance = StremioService._internal();
  static StremioService get instance => _instance;
  factory StremioService() => _instance;
  StremioService._internal();

  // In-memory cache of addons
  List<StremioAddon>? _addonsCache;

  // Resolved "Watch Next" recommendations, keyed by '<type>:<imdbId>'.
  // Session-lived; recommendations are stable enough not to need a TTL.
  final Map<String, List<StremioMeta>> _recommendationsCache = {};

  // Enriched catalog-quality metadata, keyed by provider policy + type + IMDb
  // id. Lets sparse items (e.g. "Watch Next" recommendations) borrow a full
  // preferred-provider meta so their detail screen matches a normal catalog
  // open without leaking a result across provider changes.
  final Map<String, StremioMeta> _metaDetailsCache = {};

  // Series meta videos (episode lists), keyed by '<addonId>:<contentId>'.
  // Short TTL so newly-aired episodes still show up within a session; small
  // cap since each entry can hold hundreds of episode maps.
  final Map<String, ({List<Map<String, dynamic>> videos, DateTime fetchedAt})>
  _seriesMetaCache = {};
  static const _seriesMetaCacheTtl = Duration(minutes: 15);
  static const _seriesMetaCacheMax = 10;

  // Catalog pages, keyed by the full request URL (addon + type + id + genre +
  // skip + extras). Short TTL so returning to the Home board doesn't
  // re-download every row on each tab switch — the board screen is rebuilt on
  // every visit. Empty pages are cached too: the board's batch loop probes
  // catalogs sequentially until one is non-empty, so uncached empty results
  // would cost a serial network round-trip per probe on every visit.
  final Map<
    String,
    ({List<StremioMeta> metas, int rawCount, DateTime fetchedAt})
  >
  _catalogCache = {};
  static const _catalogCacheTtl = Duration(minutes: 5);
  static const _catalogCacheMax = 80;

  // Addon ids that returned streams but zero recommendation links (e.g.
  // torrent indexers). Skipped on later recommendation queries so opening
  // a detail doesn't re-hit every stream addon. A genuine recommendation
  // addon is never added: its non-empty responses are *all* rec links, so
  // it never trips the "has streams but no rec links" rule.
  final Set<String> _nonRecommendationAddonIds = {};

  // Listeners for addon changes (used to refresh UI when addons are added via deep link)
  final List<VoidCallback> _addonsChangedListeners = [];

  @visibleForTesting
  Future<StremioAddon> Function(String manifestUrl)? debugManifestFetcher;

  @visibleForTesting
  http.Client Function()? debugStreamHttpClientFactory;

  /// Add a listener to be notified when addons change
  void addAddonsChangedListener(VoidCallback listener) {
    _addonsChangedListeners.add(listener);
  }

  /// Remove an addons changed listener
  void removeAddonsChangedListener(VoidCallback listener) {
    _addonsChangedListeners.remove(listener);
  }

  /// Notify all listeners that addons have changed
  void _notifyAddonsChanged() {
    for (final listener in _addonsChangedListeners) {
      listener();
    }
  }

  // ============================================================
  // Addon Management
  // ============================================================

  /// Get all stored Stremio addons
  Future<List<StremioAddon>> getAddons({
    bool forSettings = false,
    bool forRemoteTransfer = false,
  }) async {
    // READING addons is an operation every profile keeps ([ProfileFeature
    // .addonUse]) — Home shelves and catalog search must survive "Manage own
    // sources" being off. The management entry points (add/remove/import/
    // refresh/toggle/clear) each demand addonsAndEngines themselves.
    final authorization = await ProfileAsyncAuthorization.capture(
      forRemoteTransfer
          ? ProfileFeature.remoteTransfer
          : ProfileFeature.addonUse,
    );
    if (!forSettings && !forRemoteTransfer && _addonsCache != null) {
      if (authorization != null) {
        await authorization.runIfCurrent(() async {});
      }
      if (ProfileCollectionResourceFacade.active) {
        try {
          for (final addon in _addonsCache!) {
            await ProfileCollectionResourceFacade.authorizeExecution(
              resourceId: addon.connectionResourceId,
              resourceRevision: addon.connectionResourceRevision,
              acceptedTypes: const <ConnectionResourceType>{
                ConnectionResourceType.stremioAddon,
              },
              feature: ProfileFeature.addonUse,
            );
          }
        } on ResourceAuthorizationException {
          // A resource was rotated, revoked, disabled, or deleted without
          // going through this singleton. Never serve its decrypted URL from
          // process memory; rebuild the cache from the current graph below.
          _addonsCache = null;
        }
      }
      if (_addonsCache != null) return List.from(_addonsCache!);
    }

    if (ProfileCollectionResourceFacade.active) {
      Future<List<Map<String, dynamic>>> read() =>
          ProfileCollectionResourceFacade.read(
            types: const <ConnectionResourceType>{
              ConnectionResourceType.stremioAddon,
            },
            feature: ProfileFeature.addonUse,
            forSettings: forSettings,
            forRemoteTransfer: forRemoteTransfer,
          );
      final rows = authorization == null
          ? await read()
          : await authorization.runIfCurrent(read);
      // Restored rows (remote import, file backup) carry only a manifest URL
      // — the restore adapters cannot fetch manifests. The strict parse used
      // to throw on the first such row, which took EVERY catalog down with a
      // type-cast error (caught live on a TV right after a remote import).
      // Split them out and hydrate instead of crashing the whole list.
      final parsed = <StremioAddon>[];
      final restoredRows = <Map<String, dynamic>>[];
      for (final row in rows) {
        if (_isRestoredUrlOnlyRow(row)) {
          restoredRows.add(row);
        } else {
          parsed.add(StremioAddon.fromJson(row));
        }
      }
      var addons = parsed;
      if (restoredRows.isNotEmpty) {
        // Stubs in EVERY mode, not just the manage screen: [_saveAddons]
        // REPLACES the owned collection, so a persisted list must represent
        // every restored row — a partial persist (one row hydrated, one
        // fetch timed out and absent) would silently DELETE the missing
        // resource. [_hydrateRestoredAddons] returns exactly one entry —
        // real or stub — per row, so the invariant holds by construction.
        // The stub is disabled, carries its real resource id (visible and
        // deletable on the manage screen), and re-enters hydration on later
        // reads via its id prefix.
        final hydrated = await _hydrateRestoredAddons(
          restoredRows,
          stubUnfetchable: true,
        );
        addons = <StremioAddon>[...parsed, ...hydrated];
        final anyReal = hydrated.any(
          (a) => !a.id.startsWith(_restoredPendingIdPrefix),
        );
        // Persist only when a fetch actually completed something new, and
        // NEVER from the manage screen's read: its addons-changed listener
        // reloads on every save, and with the failed-URL memo making stub
        // recreation instant, a settings-read persist becomes an endless
        // save→notify→reload loop that re-seals secrets and bumps every
        // addon's authorization revision each turn.
        if (anyReal && !forRemoteTransfer && !forSettings) {
          // Best-effort: a profile allowed to USE addons but not manage
          // them cannot write the collection — serve the hydrated list for
          // this session and let a manager's read repair it durably. The
          // captured authorization rides along so a profile switch during
          // the (network-long) hydration can never publish under the new
          // profile's scope.
          try {
            await _saveAddons(addons, initiatingAuthorization: authorization);
            // _saveAddons reads the complete settings inventory back so its
            // management callers retain disabled rows. Re-read through the
            // execution path here; a playback caller must never receive that
            // settings representation (including redacted shared addons).
            return await getAddons();
          } catch (_) {
            debugPrint(
              'StremioService: could not persist hydrated addons; '
              'serving them unpersisted',
            );
          }
        }
      }
      if (!forSettings && !forRemoteTransfer) {
        if (authorization != null && !authorization.isCurrentlyActive) {
          throw StateError('Profile session changed before addon publication');
        }
        _addonsCache = addons;
      }
      return List<StremioAddon>.from(addons);
    }

    final prefs = await ProfilePreferences.instance();
    final jsonString = prefs.getString(_addonsKey);

    if (jsonString == null || jsonString.isEmpty) {
      _addonsCache = [];
      return [];
    }

    try {
      final List<dynamic> jsonList = await decodeJsonAsync(jsonString);
      _addonsCache = jsonList
          .map((j) => StremioAddon.fromJson(j as Map<String, dynamic>))
          .toList();
      return List.from(_addonsCache!);
    } catch (_) {
      debugPrint('StremioService: Addon storage could not be decoded');
      _addonsCache = [];
      return [];
    }
  }

  /// Returns a complete collection suitable for mutations and identity
  /// checks. Settings reads retain disabled rows but redact borrowed addon
  /// secrets; executable reads contain usable identities for enabled shared
  /// rows. Merge the two by stable connection-resource identity.
  Future<List<StremioAddon>> getAddonsForManagement() async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.addonUse,
    );
    final settings = await getAddons(forSettings: true);
    if (!ProfileCollectionResourceFacade.active) return settings;

    final executable = await getAddons();
    if (authorization != null && !authorization.isCurrentlyActive) {
      throw StateError('Profile session changed while loading addons');
    }
    final executableByResourceId = <String, StremioAddon>{
      for (final addon in executable)
        if (addon.connectionResourceId case final resourceId?)
          resourceId: addon,
    };
    final merged = <StremioAddon>[];
    final seenResourceIds = <String>{};
    for (final addon in settings) {
      final resourceId = addon.connectionResourceId;
      final usable = resourceId == null
          ? addon
          : executableByResourceId[resourceId] ?? addon;
      merged.add(usable);
      if (resourceId != null) seenResourceIds.add(resourceId);
    }
    for (final addon in executable) {
      final resourceId = addon.connectionResourceId;
      if (resourceId == null || seenResourceIds.add(resourceId)) {
        merged.add(addon);
      }
    }
    return merged;
  }

  /// Id prefix marking a placeholder written for a restored addon whose
  /// manifest could not be fetched. Rows carrying it re-enter hydration on
  /// every read, even if a settings-screen save persisted the placeholder.
  static const String _restoredPendingIdPrefix = 'restored-pending:';

  /// A row that a restore wrote from a URL-only payload (or any row missing
  /// the strict-parse fields). `manifestUrl` (camelCase) is the restore
  /// adapters' key; the full records store `manifest_url`.
  static bool _isRestoredUrlOnlyRow(Map<String, dynamic> row) {
    final id = row['id'];
    if (id is String && id.startsWith(_restoredPendingIdPrefix)) return true;
    return id is! String ||
        row['name'] is! String ||
        row['manifest_url'] is! String ||
        row['base_url'] is! String;
  }

  /// URLs whose manifest fetch failed this session — without this memo an
  /// offline device would pay a full network timeout on EVERY catalog load
  /// until the fetch succeeds. Cleared by restart (retry is cheap then).
  static final Set<String> _hydrationFailedUrls = <String>{};

  /// Fetches the real manifest for restored URL-only rows and rebinds each
  /// result to its existing connection resource, so grants and identity are
  /// preserved when [_saveAddons] republishes the collection.
  ///
  /// [stubUnfetchable] (the manage screen) turns rows whose fetch failed
  /// into visible, disabled placeholders that carry the real resource id —
  /// without one, a permanently-dead manifest URL would be an invisible and
  /// therefore undeletable resource.
  Future<List<StremioAddon>> _hydrateRestoredAddons(
    List<Map<String, dynamic>> rows, {
    bool stubUnfetchable = false,
  }) async {
    final result = <StremioAddon>[];
    for (final row in rows) {
      final raw = (row['manifestUrl'] ?? row['manifest_url']) as String?;
      final url = raw?.trim() ?? '';
      void addStub() {
        if (!stubUnfetchable) return;
        final host = Uri.tryParse(url)?.host ?? '';
        result.add(
          StremioAddon(
            id: '$_restoredPendingIdPrefix$url',
            name: host.isEmpty
                ? 'Imported addon (unavailable)'
                : 'Imported addon (unavailable) · $host',
            manifestUrl: url,
            baseUrl: url,
            enabled: false,
            connectionResourceId: row['_connectionResourceId'] as String?,
            connectionResourceRevision:
                row['_connectionResourceRevision'] as int?,
          ),
        );
      }

      if (url.isEmpty || _hydrationFailedUrls.contains(url)) {
        addStub();
        continue;
      }
      try {
        final fetched = await fetchManifest(_normalizeManifestUrl(url));
        result.add(
          fetched.copyWith(
            connectionResourceId: row['_connectionResourceId'] as String?,
            connectionResourceRevision:
                row['_connectionResourceRevision'] as int?,
          ),
        );
      } catch (_) {
        debugPrint('StremioService: could not hydrate restored addon');
        _hydrationFailedUrls.add(url);
        addStub();
      }
    }
    return result;
  }

  /// Get only enabled addons
  Future<List<StremioAddon>> getEnabledAddons() async {
    final addons = await getAddons();
    return addons.where((a) => a.enabled).toList();
  }

  /// The user's metadata-provider choice. Null means the recommended default:
  /// Cinemeta when it is enabled, otherwise Automatic.
  Future<String?> getMetadataProviderPreference() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_metadataProviderKey);
  }

  Future<void> setMetadataProviderPreference(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_metadataProviderKey, value);
    _metaDetailsCache.clear();
  }

  static bool isCinemetaAddon(StremioAddon addon) {
    if (const <String>{
      'cinemeta',
      'com.stremio.cinemeta',
      'com.linvo.cinemeta',
    }.contains(addon.id)) {
      return true;
    }
    return Uri.tryParse(addon.manifestUrl)?.host.toLowerCase() ==
        'v3-cinemeta.strem.io';
  }

  /// Secret-free, configuration-specific value stored by the metadata picker.
  static String metadataProviderValue(StremioAddon addon) =>
      addon.portableConfigurationKey;

  /// Applies the details-metadata policy without affecting stream or episode
  /// addon selection. An explicit provider is strict: if it cannot resolve a
  /// title, callers retain the tracker metadata rather than silently switching
  /// languages. Automatic preserves the legacy enabled-addon order.
  @visibleForTesting
  static List<StremioAddon> metadataCandidatesForPreference(
    List<StremioAddon> candidates,
    String? preference,
  ) {
    if (preference == automaticMetadataProvider) {
      return List<StremioAddon>.of(candidates);
    }
    if (preference != null) {
      for (final addon in candidates) {
        if (metadataProviderValue(addon) == preference) return [addon];
      }
    }
    for (final addon in candidates) {
      if (isCinemetaAddon(addon)) return [addon];
    }
    return List<StremioAddon>.of(candidates);
  }

  /// Get addons that support streaming
  Future<List<StremioAddon>> getStreamingAddons() async {
    final addons = await getEnabledAddons();
    return addons.where((a) => a.supportsStreams).toList();
  }

  /// Save addons to storage
  Future<List<StremioAddon>> _saveAddons(
    List<StremioAddon> addons, {
    ProfileAsyncAuthorization? initiatingAuthorization,
    bool revokeSharedProfiles = false,
  }) async {
    Future<List<StremioAddon>> persist() async {
      if (ProfileCollectionResourceFacade.active) {
        final rows = await ProfileCollectionResourceFacade.replaceAndRead(
          types: const <ConnectionResourceType>{
            ConnectionResourceType.stremioAddon,
          },
          feature: ProfileFeature.addonsAndEngines,
          items: <ResourceCollectionItem>[
            for (final addon in addons)
              ResourceCollectionItem(
                type: ConnectionResourceType.stremioAddon,
                label: addon.name,
                publicConfig: <String, dynamic>{
                  'addonName': addon.name,
                  'contentKinds': addon.types,
                },
                secretConfig: addon.toJson(),
                sourceResourceId: addon.connectionResourceId,
              ),
          ],
          // Collection saves must read disabled entries back too: settings are
          // profile-local and a disabled resource is still part of the saved
          // collection (and may be returned to the management caller).
          forSettings: true,
          revokeBorrowers: revokeSharedProfiles,
        );
        return rows.map(StremioAddon.fromJson).toList(growable: false);
      } else {
        final prefs = await ProfilePreferences.instance();
        final jsonString = json.encode(addons.map((a) => a.toJson()).toList());
        await prefs.setString(_addonsKey, jsonString);
        return List<StremioAddon>.unmodifiable(addons);
      }
    }

    final List<StremioAddon> saved;
    if (initiatingAuthorization == null) {
      saved = await persist();
    } else {
      saved = await initiatingAuthorization.runIfCurrent(persist);
      if (!initiatingAuthorization.isCurrentlyActive) {
        throw StateError('Profile session changed before addon publication');
      }
    }
    // [saved] is the settings representation because management callers need
    // disabled rows. It may also contain redacted borrowed rows, so it must
    // never seed the executable cache; the next playback read rebuilds that
    // cache from an authorized use-mode read.
    _addonsCache = null;
    // Addon set changed — drop recommendation caches so a title viewed
    // before installing a "Watch Next"-style addon picks it up without an
    // app restart (and a removed addon stops contributing).
    _recommendationsCache.clear();
    _metaDetailsCache.clear();
    _nonRecommendationAddonIds.clear();
    // Catalog pages too: a reconfigured addon can serve different content from
    // the same catalog URL, so nothing cached before the change may survive it.
    _catalogCache.clear();
    _notifyAddonsChanged();
    return List<StremioAddon>.from(saved);
  }

  /// Add a new addon by manifest URL
  ///
  /// Returns the addon if successful, throws exception on failure.
  Future<StremioAddon> addAddon(String manifestUrl) async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.addonsAndEngines,
    );
    // Normalize URL
    manifestUrl = _normalizeManifestUrl(manifestUrl);

    // Check if already exists
    // This mutates the installed collection, so it must consider disabled
    // entries too. The normal read path is deliberately playback-filtered.
    final existingAddons = await getAddonsForManagement();
    final existing = existingAddons.where((a) => a.manifestUrl == manifestUrl);
    if (existing.isNotEmpty) {
      throw Exception('Addon already exists: ${existing.first.name}');
    }

    // Fetch and parse manifest
    final addon = await fetchManifest(manifestUrl);

    // Validate addon has useful resources (streams or catalogs)
    final validationError = _validateAddon(addon);
    if (validationError != null) {
      throw Exception(validationError);
    }

    // Check for duplicate by ID
    final duplicateById = existingAddons.where((a) => a.id == addon.id);
    if (duplicateById.isNotEmpty) {
      // Same addon with different config - allow but warn
      debugPrint(
        'StremioService: Adding addon with same ID but different URL: ${addon.id}',
      );
    }

    // Add to list and save
    existingAddons.add(addon);
    final saved = await _saveAddons(
      existingAddons,
      initiatingAuthorization: authorization,
    );
    final canonical = saved.singleWhere(
      (item) => item.manifestUrl == addon.manifestUrl,
    );

    debugPrint('StremioService: Added addon: ${canonical.name}');
    return canonical;
  }

  /// Import addons from a Debrify Stremio Importer JSON file or a raw Stremio
  /// addon collection JSON payload.
  Future<StremioAddonImportResult> importAddonsFromJson(
    String jsonContent, {
    bool replaceExisting = false,
  }) async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.addonsAndEngines,
    );
    final dynamic decoded;
    try {
      decoded = await decodeJsonAsync(jsonContent);
    } catch (e) {
      throw Exception('Invalid JSON file: $e');
    }

    final descriptors = _extractAddonDescriptors(decoded);
    if (descriptors.isEmpty) {
      throw Exception('No Stremio addon descriptors were found in this JSON.');
    }

    // Imports deduplicate against the complete installed collection, not just
    // the enabled playback subset.
    final addons = replaceExisting
        ? <StremioAddon>[]
        : await getAddonsForManagement();
    final knownUrlVariants = <String>{
      for (final addon in addons) ..._duplicateUrlVariants(addon.manifestUrl),
    };

    var imported = 0;
    var skippedDuplicates = 0;
    var skippedUnsupported = 0;
    var failed = 0;
    final importedNames = <String>[];
    final skippedNames = <String>[];
    final errors = <String>[];

    for (final descriptor in descriptors) {
      if (descriptor is! Map) {
        failed++;
        errors.add('Skipped an invalid addon entry.');
        continue;
      }

      final descriptorMap = Map<String, dynamic>.from(descriptor);
      final rawUrl =
          descriptorMap['transportUrl'] ??
          descriptorMap['transport_url'] ??
          descriptorMap['manifestUrl'] ??
          descriptorMap['manifest_url'];

      if (rawUrl is! String || rawUrl.trim().isEmpty) {
        failed++;
        errors.add('Skipped an addon without a manifest URL.');
        continue;
      }

      final manifestUrl = _normalizeImportedTransportUrl(rawUrl);
      final displayName = _addonDisplayNameFromDescriptor(descriptorMap);

      if (_isLocalTransportUrl(manifestUrl)) {
        skippedUnsupported++;
        skippedNames.add(displayName);
        continue;
      }

      final importUrlVariants = _duplicateUrlVariants(manifestUrl);
      if (importUrlVariants.any(knownUrlVariants.contains)) {
        skippedDuplicates++;
        skippedNames.add(displayName);
        continue;
      }

      try {
        final rawManifest = descriptorMap['manifest'];
        final StremioAddon addon;
        if (rawManifest is Map) {
          addon = StremioAddon.fromManifest(
            Map<String, dynamic>.from(rawManifest),
            manifestUrl,
          );
        } else {
          addon = await fetchManifest(manifestUrl);
        }

        final validationError = _validateAddon(addon);
        if (validationError != null) {
          skippedUnsupported++;
          skippedNames.add(addon.name);
          continue;
        }

        addons.add(addon);
        knownUrlVariants.addAll(_duplicateUrlVariants(manifestUrl));
        imported++;
        importedNames.add(addon.name);
      } catch (_) {
        failed++;
        errors.add('$displayName: import failed');
      }
    }

    if (imported > 0 || replaceExisting) {
      await _saveAddons(addons, initiatingAuthorization: authorization);
    }

    return StremioAddonImportResult(
      discovered: descriptors.length,
      imported: imported,
      skippedDuplicates: skippedDuplicates,
      skippedUnsupported: skippedUnsupported,
      failed: failed,
      importedNames: importedNames,
      skippedNames: skippedNames,
      errors: errors,
    );
  }

  Future<int> addonBorrowerCount(String manifestUrl) async {
    final addons = await getAddonsForManagement();
    final target = addons
        .where((a) => a.manifestUrl == manifestUrl)
        .firstOrNull;
    final resourceId = target?.connectionResourceId;
    if (resourceId == null) return 0;
    return ProfileCollectionResourceFacade.ownedBorrowerCount(
      resourceId: resourceId,
      feature: ProfileFeature.addonsAndEngines,
    );
  }

  Future<int> sharedAddonCount() async {
    if (!ProfileCollectionResourceFacade.active) return 0;
    final addons = await getAddonsForManagement();
    var count = 0;
    for (final addon in addons) {
      final resourceId = addon.connectionResourceId;
      if (!addon.canManage || resourceId == null) continue;
      final borrowers =
          await ProfileCollectionResourceFacade.ownedBorrowerCount(
            resourceId: resourceId,
            feature: ProfileFeature.addonsAndEngines,
          );
      if (borrowers > 0) count++;
    }
    return count;
  }

  /// Remove an addon by its manifest URL. Shared profile access is revoked
  /// only after the caller has explicitly confirmed that destructive impact.
  Future<void> removeAddon(
    String manifestUrl, {
    bool revokeSharedProfiles = false,
  }) async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.addonsAndEngines,
    );
    // A disabled addon remains installed and must still be removable.
    final addons = await getAddonsForManagement();
    StremioAddon? target;
    for (final addon in addons) {
      if (addon.manifestUrl == manifestUrl) {
        target = addon;
        break;
      }
    }
    if (target != null && !target.canManage) {
      throw const ResourceAuthorizationException(
        'A shared addon can only be managed by its owner',
      );
    }
    final resourceId = target?.connectionResourceId;
    if (resourceId != null && ProfileCollectionResourceFacade.active) {
      await ProfileCollectionResourceFacade.deleteOwned(
        resourceId: resourceId,
        revokeBorrowers: revokeSharedProfiles,
      );
      if (authorization != null && !authorization.isCurrentlyActive) {
        throw StateError('Profile session changed before addon publication');
      }
      invalidateCache();
      _notifyAddonsChanged();
      debugPrint('StremioService: Removed addon');
      return;
    }
    addons.removeWhere((a) => a.manifestUrl == manifestUrl);
    await _saveAddons(addons, initiatingAuthorization: authorization);
    debugPrint('StremioService: Removed addon');
  }

  /// Toggle addon enabled state
  Future<void> setAddonEnabled(String addonKey, bool enabled) async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.addonsAndEngines,
    );
    // forSettings, because the plain read HIDES disabled addons — the facade
    // drops any row whose local settings say enabled == false. Reading that
    // list here meant a disabled addon was not in it, so the toggle that would
    // turn it back ON could never find it: disable worked once and enable
    // never did.
    final addons = await getAddons(forSettings: true);
    final index = addons.indexWhere((a) => a.storageKey == addonKey);
    if (index < 0) {
      // Returning quietly here is how a caller passing the wrong key — a
      // manifest URL, which IS the storage key until profiles turn addons
      // into connection resources — became an invisible dead toggle rather
      // than a crash. Say so; the key that missed is the whole diagnosis.
      throw ArgumentError.value(
        addonKey,
        'addonKey',
        'No addon with this storage key (expected storageKey, which is the '
            'connection resource id under profiles — not the manifest URL)',
      );
    }
    final addon = addons[index];
    if (ProfileCollectionResourceFacade.active) {
      final resourceId = addon.connectionResourceId;
      final resourceRevision = addon.connectionResourceRevision;
      if (resourceId == null || resourceRevision == null) {
        throw const ResourceAuthorizationException(
          'Addon connection authority is missing',
        );
      }
      await ProfileCollectionResourceFacade.setLocalEnabled(
        resourceId: resourceId,
        resourceRevision: resourceRevision,
        feature: ProfileFeature.addonsAndEngines,
        enabled: enabled,
      );
      if (authorization != null && !authorization.isCurrentlyActive) {
        throw StateError('Profile session changed before addon publication');
      }
      _addonsCache = null;
      _recommendationsCache.clear();
      _metaDetailsCache.clear();
      _nonRecommendationAddonIds.clear();
      _catalogCache.clear();
      _notifyAddonsChanged();
      return;
    }
    addons[index] = addon.copyWith(enabled: enabled);
    await _saveAddons(addons, initiatingAuthorization: authorization);
  }

  /// Refresh an addon's manifest
  Future<StremioAddon?> refreshAddon(String manifestUrl) async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.addonsAndEngines,
    );
    try {
      // Refresh is a management operation; disabled addons still have a
      // manifest and remain eligible for an explicit update.
      final addons = await getAddonsForManagement();
      final index = addons.indexWhere((a) => a.manifestUrl == manifestUrl);
      if (index >= 0) {
        final old = addons[index];
        if (!old.canManage) {
          throw const ResourceAuthorizationException(
            'A shared addon can only be managed by its owner',
          );
        }
        final newManifest = await fetchManifest(manifestUrl);
        // Preserve the profile resource provenance alongside user-owned state.
        // A fresh manifest has no connection-resource metadata, and dropping
        // it would make _saveAddons treat this as a new resource.
        addons[index] = newManifest.copyWith(
          enabled: old.enabled,
          addedAt: old.addedAt,
          connectionResourceId: old.connectionResourceId,
          connectionResourceRevision: old.connectionResourceRevision,
          connectionResourceReadOnly: old.connectionResourceReadOnly,
          connectionResourceCredentialsRedacted:
              old.connectionResourceCredentialsRedacted,
        );
        final saved = await _saveAddons(
          addons,
          initiatingAuthorization: authorization,
        );
        final resourceId = old.connectionResourceId;
        return resourceId == null
            ? saved.singleWhere(
                (item) => item.manifestUrl == newManifest.manifestUrl,
              )
            : saved.singleWhere(
                (item) => item.connectionResourceId == resourceId,
              );
      }
      return null;
    } catch (_) {
      debugPrint('StremioService: Addon refresh failed');
      return null;
    }
  }

  /// Re-fetch every installed addon's manifest, preserving each addon's
  /// enabled state and original add date. Saves once at the end (a single
  /// listener notification) instead of per-addon to avoid N UI reloads.
  Future<StremioAddonRefreshResult> refreshAllAddons() async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.addonsAndEngines,
    );
    // "Update all" means every installed addon, including disabled ones.
    final addons = await getAddonsForManagement();
    var updated = 0;
    var unchanged = 0;
    var failed = 0;
    final updatedNames = <String>[];
    final failedNames = <String>[];

    for (var i = 0; i < addons.length; i++) {
      final old = addons[i];
      if (!old.canManage) {
        unchanged++;
        continue;
      }
      try {
        final fresh = await fetchManifest(old.manifestUrl);
        // Keep the existing connection resource as the replacement source.
        // This is essential for disabled addons and shared resource handling.
        addons[i] = fresh.copyWith(
          enabled: old.enabled,
          addedAt: old.addedAt,
          connectionResourceId: old.connectionResourceId,
          connectionResourceRevision: old.connectionResourceRevision,
          connectionResourceReadOnly: old.connectionResourceReadOnly,
          connectionResourceCredentialsRedacted:
              old.connectionResourceCredentialsRedacted,
        );
        if (fresh.version != old.version) {
          updated++;
          updatedNames.add(old.name);
        } else {
          unchanged++;
        }
      } catch (_) {
        failed++;
        failedNames.add(old.name);
        debugPrint('StremioService: Addon refresh failed');
      }
    }

    await _saveAddons(addons, initiatingAuthorization: authorization);
    return StremioAddonRefreshResult(
      updated: updated,
      unchanged: unchanged,
      failed: failed,
      updatedNames: updatedNames,
      failedNames: failedNames,
    );
  }

  /// Clear all addons
  Future<void> clearAllAddons({bool revokeSharedProfiles = false}) async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.addonsAndEngines,
    );
    await _saveAddons(
      [],
      initiatingAuthorization: authorization,
      revokeSharedProfiles: revokeSharedProfiles,
    );
    debugPrint('StremioService: Cleared all addons');
  }

  // ============================================================
  // Manifest Fetching
  // ============================================================

  /// Fetch and parse a manifest from URL
  Future<StremioAddon> fetchManifest(String manifestUrl) async {
    final testFetcher = debugManifestFetcher;
    if (testFetcher != null) return testFetcher(manifestUrl);
    try {
      final uri = Uri.parse(manifestUrl);
      final response = await http.get(uri).timeout(_requestTimeout);

      if (response.statusCode != 200) {
        throw Exception(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }

      final Map<String, dynamic> manifest = await decodeJsonAsync(
        response.body,
      );

      // Validate required fields
      if (manifest['id'] == null || manifest['name'] == null) {
        throw Exception('Invalid manifest: missing id or name');
      }

      return StremioAddon.fromManifest(manifest, manifestUrl);
    } on FormatException catch (e) {
      throw Exception('Invalid JSON response: $e');
    } catch (e) {
      throw Exception('Failed to fetch manifest: $e');
    }
  }

  // ============================================================
  // Stream Search
  // ============================================================

  /// Search for streams across all enabled addons
  ///
  /// Parameters:
  /// - [type]: Content type ('movie' or 'series')
  /// - [imdbId]: IMDB ID (e.g., 'tt1234567')
  /// - [season]: Season number for series (optional)
  /// - [episode]: Episode number for series (optional)
  /// - [availableSeasons]: Known seasons from IMDbbot API for smart fallback
  ///
  /// For series without specific season/episode:
  /// 1. First tries bare IMDB ID (returns complete series packs)
  /// 2. If results < 5, falls back to season probing (S1E1, S2E1, etc.)
  /// 3. Fallback results are filtered to keep only season/series packs
  ///
  /// Returns a map with:
  /// - 'torrents': `List<Torrent>` - deduplicated and sorted by seeders
  /// - 'addonCounts': `Map<String, int>` - count of results per addon
  /// - 'addonErrors': `Map<String, String>` - error messages per addon
  Future<Map<String, dynamic>> searchStreams({
    required String type,
    required String imdbId,
    int? season,
    int? episode,
    List<int>? availableSeasons,
    Duration? timeout,
    bool preserveOrder = false,
  }) async {
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.torrentSearch,
    );
    final result = capability == null
        ? await _searchStreams(
            type: type,
            imdbId: imdbId,
            season: season,
            episode: episode,
            availableSeasons: availableSeasons,
            timeout: timeout,
            preserveOrder: preserveOrder,
          )
        : await capability.runIfCurrent(
            () => _searchStreams(
              type: type,
              imdbId: imdbId,
              season: season,
              episode: episode,
              availableSeasons: availableSeasons,
              timeout: timeout,
              preserveOrder: preserveOrder,
            ),
          );
    await capability?.runIfCurrent(() async {});
    return result;
  }

  Future<Map<String, dynamic>> _searchStreams({
    required String type,
    required String imdbId,
    int? season,
    int? episode,
    List<int>? availableSeasons,
    Duration? timeout,
    bool preserveOrder = false,
  }) async {
    final Map<String, int> addonCounts = {};
    final Map<String, String> addonErrors = {};

    final addons = await getStreamingAddons();

    if (addons.isEmpty) {
      debugPrint('StremioService: No streaming addons available');
      return {
        'torrents': <Torrent>[],
        'addonCounts': addonCounts,
        'addonErrors': addonErrors,
        'addonStatuses': const <AddonSearchStatus>[],
      };
    }

    // Filter addons that support the content type AND the content ID prefix
    final applicableAddons = addons
        .where((a) => _isApplicable(a, type, imdbId))
        .toList();

    if (applicableAddons.isEmpty) {
      final prefix = StremioAddon.extractIdPrefix(imdbId);
      debugPrint(
        'StremioService: No addons support type: $type with ID prefix: $prefix',
      );
      return {
        'torrents': <Torrent>[],
        'addonCounts': addonCounts,
        'addonErrors': addonErrors,
        'addonStatuses': const <AddonSearchStatus>[],
      };
    }

    // Check if this is a series search without specific season/episode
    // In this case, use smart fallback logic
    final bool needsSmartFallback =
        type == 'series' && season == null && episode == null;

    if (needsSmartFallback) {
      final result = await _searchStreamsWithSmartFallback(
        applicableAddons: applicableAddons,
        imdbId: imdbId,
        availableSeasons: availableSeasons,
        addonCounts: addonCounts,
        addonErrors: addonErrors,
        timeout: timeout,
        preserveOrder: preserveOrder,
      );
      return _withAddonStatuses(
        result,
        applicableAddons,
        addonCounts,
        addonErrors,
      );
    }

    // Standard search with specific season/episode or for movies
    // Build stream ID
    final streamId = _buildStreamId(imdbId, season, episode);

    // Search all applicable addons with bounded concurrency — an unbounded
    // fan-out over a large addon set exhausts sockets/memory on weak hardware.
    // Higher cap than the default: this is the press-Play hot path and stream
    // responses are small.
    final allStreams = await mapWithConcurrency(applicableAddons, (addon) {
      // Use stremio: prefix and lowercase to match Torrent model (which lowercases source)
      final sourceKey = 'stremio:${addon.name}'.toLowerCase();
      return _fetchStreamsFromAddon(addon, type, streamId, timeout: timeout)
          .then((streams) {
            addonCounts[sourceKey] = streams.length;
            debugPrint(
              'StremioService: ${addon.name} returned ${streams.length} streams',
            );
            return streams;
          })
          .catchError((error, _) {
            addonCounts[sourceKey] = 0;
            addonErrors[sourceKey] = 'Stream source failed';
            debugPrint('StremioService: Stream source failed');
            return <StremioStream>[];
          });
    }, concurrency: 16);

    // Flatten and convert to torrents
    final List<StremioStream> flatStreams = [];
    for (final streamList in allStreams) {
      flatStreams.addAll(streamList);
    }

    // Convert to Torrent objects and deduplicate
    final torrents = _convertToTorrents(
      flatStreams,
      preserveOrder: preserveOrder,
    );

    return _withAddonStatuses(
      {
        'torrents': torrents,
        'addonCounts': addonCounts,
        'addonErrors': addonErrors,
      },
      applicableAddons,
      addonCounts,
      addonErrors,
    );
  }

  /// Whether [addon] would be queried for [type]/[contentId] — the stream
  /// search's applicability rule, shared with [applicableStreamingAddons].
  ///
  /// An addon that declares NO types is treated as unrestricted — the same
  /// rule Stremio itself follows. "Saying nothing" is common, not exotic:
  /// manifests that use the object form of `resources` put their types inside
  /// the resource and leave the top level empty (StremThru Torz does), and
  /// fromManifest deliberately leaves those unread — hoisting them would
  /// narrow the filters that treat empty as unrestricted. Handling it HERE
  /// also rescues addons already stored with empty types, with no re-add
  /// needed.
  bool _isApplicable(StremioAddon a, String type, String contentId) {
    bool supportsType = true;
    if (type == 'movie') {
      supportsType = a.supportsMovies || a.types.isEmpty;
    } else if (type == 'series') {
      supportsType = a.supportsSeries || a.types.isEmpty;
    } else {
      // Other types (anime, tv, channel, etc.): allow if declared.
      supportsType = a.types.contains(type) || a.types.isEmpty;
    }
    return supportsType && a.supportsContentId(contentId);
  }

  /// The enabled streaming addons a search for [type]/[contentId] would
  /// query — public so the players' source sheets can show EVERY applicable
  /// addon as a group, zero-result and failed ones included.
  Future<List<StremioAddon>> applicableStreamingAddons({
    required String type,
    required String contentId,
  }) async {
    final addons = await getStreamingAddons();
    return [
      for (final addon in addons)
        if (_isApplicable(addon, type, contentId)) addon,
    ];
  }

  /// Season packs from ONE addon — the lazy half of the sheets' per-addon
  /// fetch, run only after its episode results proved it serves torrents.
  /// A bare-id fetch plus a single S{season}E1 probe (the multi-season probe
  /// ladder belongs to the full search's smart fallback), filtered to packs.
  /// Best-effort by design: a failed half contributes nothing rather than
  /// failing the probe — the episodes tab has already delivered.
  Future<List<Torrent>> fetchAddonSeasonPacks({
    required String addonId,
    required String imdbId,
    required int season,
    Duration? timeout,
  }) async {
    StremioAddon? addon;
    for (final candidate in await getStreamingAddons()) {
      if (candidate.id == addonId) {
        addon = candidate;
        break;
      }
    }
    if (addon == null) return const <Torrent>[];
    final results = await Future.wait([
      _fetchStreamsFromAddon(
        addon,
        'series',
        imdbId,
        timeout: timeout,
      ).catchError((_) => <StremioStream>[]),
      _fetchStreamsFromAddon(
        addon,
        'series',
        _buildStreamId(imdbId, season, 1),
        timeout: timeout,
      ).catchError((_) => <StremioStream>[]),
    ]);
    return _filterToPacksOnly(
      _convertToTorrents([...results[0], ...results[1]]),
    );
  }

  /// Attaches the structured per-addon outcome list — built from the
  /// APPLICABLE addon set, not the count maps, so addons with zero results
  /// (or whose results all deduped away) still appear.
  Map<String, dynamic> _withAddonStatuses(
    Map<String, dynamic> result,
    List<StremioAddon> applicableAddons,
    Map<String, int> addonCounts,
    Map<String, String> addonErrors,
  ) {
    result['addonStatuses'] = <AddonSearchStatus>[
      for (final addon in applicableAddons)
        AddonSearchStatus(
          addonId: addon.id,
          name: addon.name,
          sourceKey: 'stremio:${addon.name}'.toLowerCase(),
          count: addonCounts['stremio:${addon.name}'.toLowerCase()] ?? 0,
          error: addonErrors['stremio:${addon.name}'.toLowerCase()],
        ),
    ];
    return result;
  }

  /// Re-runs the stream fetch for ONE addon — the provider pill's Retry.
  /// Returns the converted rows (empty when the addon genuinely has nothing).
  /// The series smart fallback is deliberately not replayed: a single-addon
  /// retry probes the one streamId the current scope implies, which covers
  /// the recovery case (the addon was down); the full probe ladder belongs
  /// to a full re-search.
  Future<List<Torrent>> retryAddonStreams({
    required String addonId,
    required String type,
    required String imdbId,
    int? season,
    int? episode,
    Duration? timeout,
    bool preserveOrder = false,
  }) async {
    StremioAddon? addon;
    for (final candidate in await getStreamingAddons()) {
      if (candidate.id == addonId) {
        addon = candidate;
        break;
      }
    }
    if (addon == null) return const <Torrent>[];
    final streamId = _buildStreamId(imdbId, season, episode);
    final streams = await _fetchStreamsFromAddon(
      addon,
      type,
      streamId,
      timeout: timeout,
    );
    return _convertToTorrents(streams, preserveOrder: preserveOrder);
  }

  /// Re-fetch the addon behind a pinned direct stream and select the fresh URL
  /// representing the same stream profile. Signed playback URLs are never
  /// persisted. Exact addon configuration identity wins; an id-only fallback
  /// is allowed when there is exactly one installed configuration of that
  /// addon (so a harmless addon reconfiguration can heal an old pin).
  Future<Torrent?> resolvePinnedDirectStream({
    required String addonId,
    required String addonKey,
    required String streamKey,
    required int streamIndex,
    required String type,
    required String contentId,
    int? season,
    int? episode,
    Duration? timeout,
  }) async {
    // Include disabled/non-stream addons while resolving identity so an exact
    // pinned configuration cannot silently fall through to a different
    // enabled configuration with the same manifest id.
    final addons = await getAddons();
    final exact = addons
        .where((addon) => addon.sourceBindingKey == addonKey)
        .toList(growable: false);
    StremioAddon? addon;
    if (exact.length == 1) {
      addon = exact.single;
    } else {
      final sameId = addons
          .where((candidate) => candidate.id == addonId)
          .toList(growable: false);
      if (sameId.length == 1) addon = sameId.single;
    }
    if (addon == null ||
        !addon.enabled ||
        !addon.supportsStreams ||
        !_isApplicable(addon, type, contentId)) {
      return null;
    }

    final streams = await _fetchStreamsFromAddon(
      addon,
      type,
      _buildStreamId(contentId, season, episode),
      timeout: timeout,
    );
    final direct = _convertToTorrents(
      streams,
      preserveOrder: true,
    ).where((torrent) => torrent.isDirectStream).toList(growable: false);
    return selectPinnedDirectStream(
      direct,
      streamKey: streamKey,
      streamIndex: streamIndex,
    );
  }

  /// Pure matching half of [resolvePinnedDirectStream], exposed for regression
  /// tests. Profile identity survives episode-number/URL changes; response
  /// position disambiguates addons that emit multiple identically-labelled
  /// links and is the fallback when an episode-specific filename changes more
  /// substantially than the normalizer can account for.
  @visibleForTesting
  static Torrent? selectPinnedDirectStream(
    List<Torrent> direct, {
    required String streamKey,
    required int streamIndex,
  }) {
    final profileMatches = direct
        .where((torrent) => torrent.stremioStreamKey == streamKey)
        .toList(growable: false);
    if (profileMatches.length == 1) return profileMatches.single;
    if (profileMatches.isNotEmpty) {
      for (final torrent in profileMatches) {
        if (torrent.stremioStreamIndex == streamIndex) return torrent;
      }
      return profileMatches.first;
    }
    for (final torrent in direct) {
      if (torrent.stremioStreamIndex == streamIndex) return torrent;
    }
    return direct.length == 1 ? direct.single : null;
  }

  /// Smart fallback for series search without specific season/episode
  ///
  /// 1. First tries bare IMDB ID
  /// 2. Filters to packs only - if >= 5, done
  /// 3. If < 5 packs, falls back to season probing
  /// 4. Combines and filters to packs - if >= 5, done
  /// 5. If still < 5 packs, returns unfiltered (shows episodes)
  Future<Map<String, dynamic>> _searchStreamsWithSmartFallback({
    required List<StremioAddon> applicableAddons,
    required String imdbId,
    required Map<String, int> addonCounts,
    required Map<String, String> addonErrors,
    List<int>? availableSeasons,
    Duration? timeout,
    bool preserveOrder = false,
  }) async {
    const int minResultsThreshold = 5;
    debugPrint('StremioService: Using smart fallback for series search');

    // Step 1: Try bare IMDB ID first (bounded fan-out, same cap as
    // searchStreams — this is also on the press-Play hot path)
    final initialResults = await mapWithConcurrency(applicableAddons, (addon) {
      final sourceKey = 'stremio:${addon.name}'.toLowerCase();
      return _fetchStreamsFromAddon(addon, 'series', imdbId, timeout: timeout)
          .then((streams) {
            addonCounts[sourceKey] = streams.length;
            debugPrint(
              'StremioService: ${addon.name} (bare IMDB) returned ${streams.length} streams',
            );
            return streams;
          })
          .catchError((e) {
            addonCounts[sourceKey] = 0;
            addonErrors[sourceKey] = 'Stream source failed';
            debugPrint('StremioService: Series stream source failed');
            return <StremioStream>[];
          });
    }, concurrency: 16);
    final List<StremioStream> initialStreams = [];
    for (final streams in initialResults) {
      initialStreams.addAll(streams);
    }

    // Convert initial streams to torrents
    List<Torrent> allTorrents = _convertToTorrents(
      initialStreams,
      preserveOrder: preserveOrder,
    );
    debugPrint(
      'StremioService: Bare IMDB returned ${allTorrents.length} torrents',
    );

    // Step 2: Filter to packs only
    List<Torrent> filteredTorrents = _filterToPacksOnly(allTorrents);
    debugPrint(
      'StremioService: After filtering bare IMDB to packs: ${filteredTorrents.length} torrents',
    );

    // If we have enough packs, return them
    if (filteredTorrents.length >= minResultsThreshold) {
      debugPrint(
        'StremioService: Have ${filteredTorrents.length} packs (>= $minResultsThreshold), returning packs only',
      );
      _updateAddonCounts(addonCounts, filteredTorrents);
      return {
        'torrents': filteredTorrents,
        'addonCounts': addonCounts,
        'addonErrors': addonErrors,
      };
    }

    // Step 3: Not enough packs, fallback to season probing
    debugPrint(
      'StremioService: Only ${filteredTorrents.length} packs (< $minResultsThreshold), '
      'falling back to season probing',
    );

    // Determine seasons to probe (cap at 10 to avoid flooding servers)
    const int maxSeasonsToProbe = 10;
    List<int> seasonsToProbe =
        (availableSeasons != null && availableSeasons.isNotEmpty)
        ? (List<int>.from(availableSeasons)
            ..sort()) // Sort to ensure we get earliest seasons
        : List.generate(5, (i) => i + 1); // Default to seasons 1-5

    // Cap to first 10 seasons - season packs usually appear in early season searches
    if (seasonsToProbe.length > maxSeasonsToProbe) {
      debugPrint(
        'StremioService: Capping seasons from ${seasonsToProbe.length} to $maxSeasonsToProbe',
      );
      seasonsToProbe = seasonsToProbe.take(maxSeasonsToProbe).toList();
    }

    debugPrint(
      'StremioService: Probing ${seasonsToProbe.length} seasons IN PARALLEL: $seasonsToProbe',
    );

    // Probe all season+addon combinations with bounded concurrency — this
    // multiplies seasons × addons (up to 10 × addon count simultaneous
    // requests unbounded), the largest fan-out in the app.
    final seasonProbes = <({int seasonNum, StremioAddon addon})>[
      for (final seasonNum in seasonsToProbe)
        for (final addon in applicableAddons)
          (seasonNum: seasonNum, addon: addon),
    ];
    final List<List<StremioStream>> seasonResults = await mapWithConcurrency(
      seasonProbes,
      (probe) {
        final streamId = _buildStreamId(imdbId, probe.seasonNum, 1); // S{n}E1
        return _fetchStreamsFromAddon(
          probe.addon,
          'series',
          streamId,
          timeout: timeout,
        ).catchError((_) {
          final sourceKey = 'stremio:${probe.addon.name}'.toLowerCase();
          addonErrors[sourceKey] = 'Stream source failed';
          debugPrint('StremioService: Season probe failed');
          return <StremioStream>[];
        });
      },
      concurrency: 16,
    );

    // Flatten results
    final List<StremioStream> fallbackStreams = [];
    for (final streams in seasonResults) {
      fallbackStreams.addAll(streams);
    }

    debugPrint(
      'StremioService: Parallel season probing returned ${fallbackStreams.length} streams',
    );

    // Convert fallback streams to torrents
    final fallbackTorrents = _convertToTorrents(
      fallbackStreams,
      preserveOrder: preserveOrder,
    );
    debugPrint(
      'StremioService: Season probing returned ${fallbackTorrents.length} torrents',
    );

    // Step 4: Combine all torrents and filter to packs. Exact-order profiles
    // retain every row exactly as returned, including repeated hashes from
    // different addons; normal ranking keeps the historical hash dedupe.
    allTorrents = mergeSmartFallbackTorrents(
      allTorrents,
      fallbackTorrents,
      preserveOrder: preserveOrder,
    );
    debugPrint(
      'StremioService: Combined total: ${allTorrents.length} '
      '${preserveOrder ? 'ordered items' : 'unique torrents'}',
    );

    // Filter combined results to packs only
    filteredTorrents = _filterToPacksOnly(allTorrents);
    debugPrint(
      'StremioService: After filtering combined to packs: ${filteredTorrents.length} torrents',
    );

    // Step 5: If we have enough packs now, return them
    if (filteredTorrents.length >= minResultsThreshold) {
      debugPrint(
        'StremioService: Have ${filteredTorrents.length} packs after probing, returning packs only',
      );
      if (!preserveOrder) {
        filteredTorrents.sort((a, b) => b.seeders.compareTo(a.seeders));
      }
      _updateAddonCounts(addonCounts, filteredTorrents);
      return {
        'torrents': filteredTorrents,
        'addonCounts': addonCounts,
        'addonErrors': addonErrors,
      };
    }

    // Step 6: Still not enough packs, return all unfiltered (show episodes)
    debugPrint(
      'StremioService: Only ${filteredTorrents.length} packs after probing, '
      'returning all ${allTorrents.length} torrents (including episodes)',
    );
    if (!preserveOrder) {
      allTorrents.sort((a, b) => b.seeders.compareTo(a.seeders));
    }
    _updateAddonCounts(addonCounts, allTorrents);

    return {
      'torrents': allTorrents,
      'addonCounts': addonCounts,
      'addonErrors': addonErrors,
    };
  }

  /// Update addon counts based on the final torrent list
  void _updateAddonCounts(
    Map<String, int> addonCounts,
    List<Torrent> torrents,
  ) {
    for (final key in addonCounts.keys.toList()) {
      addonCounts[key] = torrents
          .where((t) => t.source.toLowerCase() == key)
          .length;
    }
  }

  /// Filter torrents to keep only season packs and complete series packs
  /// Removes individual episode torrents
  List<Torrent> _filterToPacksOnly(List<Torrent> torrents) {
    return torrents.where((torrent) {
      // Scene names are dot/underscore-separated more often than not —
      // normalize once so the patterns below see "S03.E05" / "Season.3" the
      // same as their spaced forms (mirrors TorrentCoverageDetector).
      final name = torrent.name.toLowerCase().replaceAll(RegExp(r'[._]+'), ' ');

      // Check for individual episode patterns (filter these OUT)
      // Matches: S01E01, S1E1, S01 E01 (formerly dotted), 1x01, etc.
      final episodePattern = RegExp(
        r's\d{1,2}\s*e\d{1,3}|\d{1,2}x\d{1,3}',
        caseSensitive: false,
      );

      // Check for season pack patterns (keep these)
      // Matches: S01 (not followed by an episode), Season 1, S01-S03,
      // Complete, etc.
      final seasonPackPattern = RegExp(
        r'\bs\d{1,2}\b(?!\s*e\d)|season\s*\d+|s\d{1,2}-s\d{1,2}|complete|full.series',
        caseSensitive: false,
      );

      // If it has episode pattern like S01E01, it's an individual episode
      if (episodePattern.hasMatch(name)) {
        // But check if it's actually a season pack that happens to mention an episode
        // e.g., "From.S01.E01-E10" is a season pack
        final multiEpisodePattern = RegExp(
          r'e\d{1,3}-e\d{1,3}|e\d{1,3}\.?-\.?\d{1,3}',
          caseSensitive: false,
        );
        if (multiEpisodePattern.hasMatch(name)) {
          return true; // It's a pack like E01-E10
        }

        // Check if it also has season pack indicators
        if (seasonPackPattern.hasMatch(name)) {
          // Has both episode and season pack patterns - likely a season pack
          // e.g., "Show.S01.Complete.S01E01.mkv" (filename from pack)
          return true;
        }

        // Individual episode - filter out
        return false;
      }

      // No episode pattern — keep it: either it has pack indicators, or the
      // naming is unusual and we keep it rather than over-filter.
      return true;
    }).toList();
  }

  /// Search for movie streams
  Future<Map<String, dynamic>> searchMovieStreams(String imdbId) async {
    return searchStreams(type: 'movie', imdbId: imdbId);
  }

  /// Search for series/episode streams
  Future<Map<String, dynamic>> searchSeriesStreams(
    String imdbId, {
    int? season,
    int? episode,
  }) async {
    return searchStreams(
      type: 'series',
      imdbId: imdbId,
      season: season,
      episode: episode,
    );
  }

  /// Build the stream ID for the API call
  String _buildStreamId(String imdbId, int? season, int? episode) {
    if (season != null && episode != null) {
      return '$imdbId:$season:$episode';
    } else if (season != null) {
      return '$imdbId:$season';
    }
    return imdbId;
  }

  /// Fetch usable streams for an arbitrary content id from one addon —
  /// public entry for non-IMDb lookups (the IPTV bridge resolving live-TV
  /// channels via `/stream/tv/<id>.json`). Errors surface to the caller.
  Future<List<StremioStream>> fetchStreamsForContentId(
    StremioAddon addon,
    String type,
    String contentId, {
    Duration? timeout,
  }) => _fetchStreamsFromAddon(addon, type, contentId, timeout: timeout);

  /// Fetch streams from a single addon
  Future<List<StremioStream>> _fetchStreamsFromAddon(
    StremioAddon addon,
    String type,
    String streamId, {
    Duration? timeout,
  }) async {
    // Decode first (in case already encoded), then encode properly
    // This handles IDs like "vavoo_SKY%20ATLANTIC|group:it" that are partially encoded
    final decodedId = Uri.decodeComponent(streamId);
    final encodedStreamId = Uri.encodeComponent(decodedId);
    final url = buildStremioResourceUri(addon.baseUrl, <String>[
      'stream',
      type,
      '$encodedStreamId.json',
    ]).toString();

    try {
      final uri = Uri.parse(url);
      final effectiveTimeout = timeout ?? _requestTimeout;
      final client = debugStreamHttpClientFactory?.call() ?? http.Client();
      late final http.Response response;
      try {
        response = await client.get(uri).timeout(effectiveTimeout);
      } finally {
        client.close();
      }

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final Map<String, dynamic> data = await decodeJsonAsync(response.body);
      final streamsRaw = data['streams'] as List<dynamic>?;

      if (streamsRaw == null || streamsRaw.isEmpty) {
        return [];
      }

      return streamsRaw
          .asMap()
          .entries
          .map(
            (entry) => StremioStream.fromJson(
              entry.value as Map<String, dynamic>,
              addon.name,
              addonId: addon.id,
              addonKey: addon.sourceBindingKey,
              streamIndex: entry.key,
            ),
          )
          .where(
            (s) => s.isUsable,
          ) // Keep all usable streams (torrent, direct, external)
          .toList();
    } catch (e) {
      debugPrint('StremioService: Stream fetch failed');
      rethrow;
    }
  }

  // ============================================================
  // Recommendations ("Watch Next")
  // ============================================================

  /// Fetches "Watch Next"-style recommendations for [imdbId] / [type].
  ///
  /// Some stream addons (e.g. the "Watch Next" addon) abuse the stream
  /// resource to return Stremio detail deep links instead of playable
  /// streams. We collect those across enabled stream addons and build
  /// [StremioMeta] entries straight from each link — posters/backdrops
  /// from Stremio's MetaHub CDN (keyed by IMDb id, no metadata-addon
  /// dependency), name/overview from the entry itself.
  ///
  /// Best-effort and fail-soft: any failure (no addons, network, parse)
  /// resolves to an empty list so the caller simply renders no rail.
  /// A non-empty result is cached per `<type>:<imdbId>` for the session.
  Future<List<StremioMeta>> getRecommendations({
    required String imdbId,
    required String type,
  }) async {
    if (!imdbId.startsWith('tt') || (type != 'movie' && type != 'series')) {
      return const [];
    }
    final cacheKey = '$type:$imdbId';
    final cached = _recommendationsCache[cacheKey];
    if (cached != null) return cached;

    try {
      final addons = await getStreamingAddons();
      final candidates = addons
          .where(
            (a) =>
                (a.types.isEmpty || a.types.contains(type)) &&
                a.supportsContentId(imdbId) &&
                !_nonRecommendationAddonIds.contains(a.id),
          )
          .toList();
      if (candidates.isEmpty) return const [];

      // Query candidate addons with bounded concurrency; tolerate individual
      // failures. Order is preserved, which the perAddon[i]/candidates[i]
      // alignment below relies on.
      final perAddon = await mapWithConcurrency(candidates, (a) async {
        try {
          return await _fetchStreamsFromAddon(
            a,
            type,
            imdbId,
            timeout: const Duration(seconds: 8),
          );
        } catch (_) {
          return <StremioStream>[];
        }
      });

      // Learn which candidates are not recommendation providers so later
      // detail opens skip them. Rule: returned ≥1 stream but none were rec
      // links ⇒ it's a normal stream addon (e.g. a torrent indexer). An
      // empty response is inconclusive (allow a re-probe next time).
      for (var i = 0; i < candidates.length; i++) {
        final streams = perAddon[i];
        if (streams.isEmpty) continue;
        if (!streams.any((s) => s.isRecommendationLink)) {
          _nonRecommendationAddonIds.add(candidates[i].id);
        }
      }

      // Build recommendations directly from the addon entries. Posters /
      // backdrops come from Stremio's MetaHub CDN keyed purely by IMDb id
      // (no metadata addon dependency — the same source the Trakt path
      // uses); the title and overview come from the entry itself. Unique,
      // first-seen order, capped, excluding the title itself.
      const maxItems = 24;
      final seen = <String>{};
      final recommendations = <StremioMeta>[];
      outer:
      for (final streams in perAddon) {
        for (final s in streams) {
          final t = s.recommendationTarget;
          if (t == null || t.imdbId == imdbId) continue;
          if (!seen.add('${t.type}:${t.imdbId}')) continue;
          final name = s.name?.trim();
          final overview = s.title?.trim();
          recommendations.add(
            StremioMeta(
              id: t.imdbId,
              imdbId: t.imdbId,
              type: t.type,
              name: (name != null && name.isNotEmpty) ? name : t.imdbId,
              poster:
                  'https://images.metahub.space/poster/medium/${t.imdbId}/img',
              background:
                  'https://images.metahub.space/background/medium/${t.imdbId}/img',
              description:
                  (overview != null && overview.isNotEmpty && overview != name)
                  ? overview
                  : null,
            ),
          );
          if (recommendations.length >= maxItems) break outer;
        }
      }

      // Cache only a non-empty result. An empty list usually means the
      // recommendation addon cold-started past its timeout (common on free
      // hosting) — caching that would wedge the rail "broken" for the whole
      // session. Re-probing is cheap: the skip-list already excludes
      // non-recommendation addons after the first probe.
      if (recommendations.isNotEmpty) {
        _recommendationsCache[cacheKey] = recommendations;
      }
      return recommendations;
    } catch (e) {
      debugPrint('StremioService: Recommendation fetch failed');
      return const [];
    }
  }

  /// Fetch full catalog-quality metadata (year, IMDb rating, genres, a
  /// clean overview, and art) for a movie/series by IMDb id.
  ///
  /// Used to enrich sparse items — chiefly "Watch Next" recommendations,
  /// which are built straight from an addon's stream entry and so lack the
  /// structured fields a Cinemeta catalog item carries. Returns null when
  /// no meta-capable addon resolves it (the caller keeps what it had).
  Future<StremioMeta?> fetchMetaDetails({
    required String imdbId,
    required String type,
  }) async {
    if (!imdbId.startsWith('tt') || (type != 'movie' && type != 'series')) {
      return null;
    }
    try {
      final addons = await getEnabledAddons();
      final metadataAddons = addons
          .where((a) => a.resources.contains('meta') && a.baseUrl.isNotEmpty)
          .toList();
      final preference = await getMetadataProviderPreference();
      final preferred = metadataCandidatesForPreference(
        metadataAddons,
        preference,
      );
      final candidates = preferred
          .where(
            (a) =>
                (a.types.isEmpty || a.types.contains(type)) &&
                a.supportsContentId(imdbId),
          )
          .toList();
      if (candidates.isEmpty) return null;

      // Provider policy belongs in the cache identity: changing the picker must
      // never serve a result fetched earlier from a different-language addon.
      final providerCacheKey = preference ?? 'recommended';
      final cacheKey = '$providerCacheKey:$type:$imdbId';
      final cached = _metaDetailsCache[cacheKey];
      if (cached != null) return cached;

      // Probe candidates with bounded concurrency; tolerate individual
      // failures. A short timeout keeps one slow/dead meta addon from holding
      // up enrichment. mapWithConcurrency preserves order, so results stay in
      // addon priority.
      final results = await mapWithConcurrency(candidates, (addon) async {
        final url = buildStremioResourceUri(addon.baseUrl, <String>[
          'meta',
          type,
          '${Uri.encodeComponent(imdbId)}.json',
        ]).toString();
        final client = http.Client();
        try {
          final request = http.Request('GET', Uri.parse(url));
          request.followRedirects = true;
          request.maxRedirects = 5;
          final streamed = await client
              .send(request)
              .timeout(const Duration(seconds: 8));
          final response = await http.Response.fromStream(streamed);
          if (response.statusCode != 200) return null;
          final data =
              await decodeJsonAsync(response.body) as Map<String, dynamic>?;
          final metaJson = data?['meta'] as Map<String, dynamic>?;
          if (metaJson == null) return null;
          return StremioMeta.fromJson(metaJson);
        } catch (_) {
          return null; // addon-specific failure
        } finally {
          client.close();
        }
      });

      // Prefer the first result (by addon priority) that carries real
      // structured metadata. Only fall back to a description-only result
      // if nothing richer came back — otherwise a weaker source ordered
      // first would mask a better one.
      StremioMeta? descriptionOnly;
      for (final meta in results) {
        if (meta == null) continue;
        final hasStructured =
            meta.year != null ||
            meta.imdbRating != null ||
            (meta.genres?.isNotEmpty ?? false);
        if (hasStructured) {
          _metaDetailsCache[cacheKey] = meta;
          return meta;
        }
        if (descriptionOnly == null &&
            (meta.description?.isNotEmpty ?? false)) {
          descriptionOnly = meta;
        }
      }
      if (descriptionOnly != null) {
        _metaDetailsCache[cacheKey] = descriptionOnly;
        return descriptionOnly;
      }
      return null;
    } catch (e) {
      debugPrint('StremioService: Metadata fetch failed');
      return null;
    }
  }

  /// Convert Stremio streams to Torrent objects
  /// Handles all stream types: torrent (infoHash), direct URL, and external URL
  @visibleForTesting
  List<Torrent> convertStreamsForTesting(
    List<StremioStream> streams, {
    bool preserveOrder = false,
  }) => _convertToTorrents(streams, preserveOrder: preserveOrder);

  /// Merge the bare-series and season-probe batches. Public for focused tests
  /// because exact-order's duplicate-preservation contract is easy to regress
  /// when changing the smart fallback independently from normal conversion.
  @visibleForTesting
  List<Torrent> mergeSmartFallbackTorrents(
    List<Torrent> initial,
    List<Torrent> fallback, {
    bool preserveOrder = false,
  }) {
    if (preserveOrder) return [...initial, ...fallback];
    final unique = <String, Torrent>{};
    for (final torrent in initial) {
      unique[torrent.infohash] = torrent;
    }
    for (final torrent in fallback) {
      unique.putIfAbsent(torrent.infohash, () => torrent);
    }
    return unique.values.toList();
  }

  List<Torrent> _convertToTorrents(
    List<StremioStream> streams, {
    bool preserveOrder = false,
  }) {
    final Map<String, Torrent> uniqueTorrents = {};
    final orderedTorrents = <Torrent>[];
    int withInfoHash = 0;
    int withDirectUrl = 0;
    int withExternalUrl = 0;
    int recommendationLinks = 0;
    int skipped = 0;

    for (final stream in streams) {
      // Drop Stremio detail deep links (e.g. the "Watch Next" addon). These
      // are recommendations, not playable sources — surfaced as a separate
      // detail-screen rail (see StremioService.getRecommendations), never as
      // torrent/source rows.
      if (stream.isRecommendationLink) {
        recommendationLinks++;
        continue;
      }

      // Parse size - try behaviorHints.videoSize first, then title
      int sizeBytes = 0;
      if (stream.behaviorHints != null) {
        final videoSize = stream.behaviorHints!['videoSize'];
        if (videoSize is int) {
          sizeBytes = videoSize;
        } else if (videoSize is double) {
          sizeBytes = videoSize.round();
        }
      }
      if (sizeBytes == 0) {
        final sizeStr = stream.sizeFromTitle;
        if (sizeStr != null) {
          sizeBytes = _parseSizeToBytes(sizeStr);
        }
      }

      // Get name - prefer filename from behaviorHints, then title
      String name = stream.title ?? 'Unknown';
      if (stream.behaviorHints != null) {
        final filename = stream.behaviorHints!['filename'] as String?;
        if (filename != null && filename.isNotEmpty) {
          name = filename;
        }
      }

      // A debrid addon may return a ready-to-play URL while retaining the
      // source torrent hash in `infoHash` or `behaviorHints.bingeGroup`.
      // Preserve both transports as separate rows: the URL row plays through
      // the addon, while the hash row remains available to Debrify's provider.
      final variants =
          <
            ({
              String uniqueKey,
              String infohash,
              StreamType streamType,
              String? directUrl,
              bool hasRealInfoHash,
              int seeders,
            })
          >[];
      final playableUrl = stream.url;
      if (stream.isTorrent) {
        if (playableUrl != null && playableUrl.isNotEmpty) {
          final urlKey =
              'url:${playableUrl.hashCode.toRadixString(16).padLeft(40, '0')}';
          variants.add((
            uniqueKey: urlKey,
            infohash: urlKey,
            streamType: StreamType.directUrl,
            directUrl: playableUrl,
            hasRealInfoHash: false,
            seeders: 0,
          ));
          withDirectUrl++;
        }
        final hash = stream.infoHash!.toLowerCase();
        variants.add((
          uniqueKey: hash,
          infohash: hash,
          streamType: StreamType.torrent,
          directUrl: null,
          hasRealInfoHash: true,
          seeders: stream.seedersFromTitle ?? 0,
        ));
        withInfoHash++;
      } else if (stream.isExternalUrl) {
        final externalUrl = stream.externalUrl!;
        final externalKey =
            'ext:${externalUrl.hashCode.toRadixString(16).padLeft(40, '0')}';
        variants.add((
          uniqueKey: externalKey,
          infohash: externalKey,
          streamType: StreamType.externalUrl,
          directUrl: externalUrl,
          hasRealInfoHash: false,
          seeders: 0,
        ));
        withExternalUrl++;
      } else if (playableUrl != null && playableUrl.isNotEmpty) {
        final urlKey =
            'url:${playableUrl.hashCode.toRadixString(16).padLeft(40, '0')}';
        variants.add((
          uniqueKey: urlKey,
          infohash: urlKey,
          streamType: StreamType.directUrl,
          directUrl: playableUrl,
          hasRealInfoHash: false,
          seeders: 0,
        ));
        withDirectUrl++;
      } else {
        skipped++;
        continue;
      }

      for (final variant in variants) {
        final torrent = Torrent(
          rowid: 0,
          infohash: variant.infohash,
          name: name,
          sizeBytes: sizeBytes,
          createdUnix: 0,
          seeders: variant.seeders,
          leechers: 0,
          completed: 0,
          scrapedDate: 0,
          source: 'stremio:${stream.source}',
          streamType: variant.streamType,
          directUrl: variant.directUrl,
          hasRealInfoHash: variant.hasRealInfoHash,
          stremioAddonId: stream.addonId,
          stremioAddonKey: stream.addonKey,
          stremioStreamKey: stream.streamKey,
          stremioStreamIndex: stream.streamIndex,
          streamLabel: stream.name,
          streamDescription: stream.title,
        );

        // Exact addon mode preserves every returned playable entry, including
        // intentional duplicates. The default path keeps its historic dedupe:
        // highest-seeder duplicate for torrents, first direct/external URL.
        if (preserveOrder) {
          orderedTorrents.add(torrent);
          continue;
        }
        final existing = uniqueTorrents[variant.uniqueKey];
        if (existing == null ||
            (variant.streamType == StreamType.torrent &&
                torrent.seeders > existing.seeders)) {
          uniqueTorrents[variant.uniqueKey] = torrent;
        }
      }
    }

    // The default path intentionally keeps its historic torrent-first/seeder
    // ordering. "Follow addon order" opts out so an addon's direct links and
    // torrents stay in the exact sequence returned by its stream endpoint.
    final results = preserveOrder
        ? orderedTorrents
        : uniqueTorrents.values.toList();
    if (!preserveOrder) {
      results.sort((a, b) {
        // First sort by stream type priority (torrent > direct > external)
        final typeCompare = a.streamType.index.compareTo(b.streamType.index);
        if (typeCompare != 0) return typeCompare;
        // Then by seeders (descending)
        return b.seeders.compareTo(a.seeders);
      });
    }

    debugPrint(
      'StremioService: Converted ${streams.length} streams to '
      '${results.length} ${preserveOrder ? 'items' : 'unique items'}',
    );
    debugPrint(
      'StremioService: Stream breakdown - torrents: $withInfoHash, '
      'directUrl: $withDirectUrl, externalUrl: $withExternalUrl, '
      'recommendationLinks: $recommendationLinks, skipped: $skipped',
    );

    return results;
  }

  /// Parse size string to bytes
  int _parseSizeToBytes(String sizeStr) {
    final normalized = sizeStr.toUpperCase().replaceAll(' ', '');
    final pattern = RegExp(r'([\d.]+)(GB|MB|TB|KB)');
    final match = pattern.firstMatch(normalized);

    if (match == null) return 0;

    final value = double.tryParse(match.group(1) ?? '0') ?? 0;
    final unit = match.group(2) ?? '';

    switch (unit) {
      case 'TB':
        return (value * 1024 * 1024 * 1024 * 1024).round();
      case 'GB':
        return (value * 1024 * 1024 * 1024).round();
      case 'MB':
        return (value * 1024 * 1024).round();
      case 'KB':
        return (value * 1024).round();
      default:
        return 0;
    }
  }

  // ============================================================
  // Catalog Methods (Content Discovery)
  // ============================================================

  /// Get all enabled addons that support catalogs
  Future<List<StremioAddon>> getCatalogAddons() async {
    final addons = await getEnabledAddons();
    return addons.where((a) => a.supportsCatalogs).toList();
  }

  /// Get all enabled addons that have catalogs OR search capability
  /// This includes:
  /// - Addons with browseable catalogs
  /// - Addons with search-only capability (no catalogs but can search)
  Future<List<StremioAddon>> getBrowseableOrSearchableAddons() async {
    final addons = await getEnabledAddons();
    return addons
        .where((a) => a.supportsCatalogs || a.hasSearchableCatalogs)
        .toList();
  }

  /// Get all enabled addons with at least one search-capable catalog. Unlike
  /// [getCatalogAddons] this doesn't require the manifest's `resources` to
  /// contain 'catalog', so search-only addons that omit it are still included —
  /// every search entry point should use this so they all agree on the set.
  Future<List<StremioAddon>> getSearchableAddons() async {
    final addons = await getEnabledAddons();
    return addons.where((a) => a.hasSearchableCatalogs).toList();
  }

  /// Get all available catalogs from all enabled catalog addons
  ///
  /// Returns a list of (addon, catalog) pairs for UI display
  Future<List<({StremioAddon addon, StremioAddonCatalog catalog})>>
  getAllCatalogs() async {
    final catalogAddons = await getCatalogAddons();
    final result = <({StremioAddon addon, StremioAddonCatalog catalog})>[];

    for (final addon in catalogAddons) {
      for (final catalog in addon.catalogs) {
        result.add((addon: addon, catalog: catalog));
      }
    }

    return result;
  }

  /// Fetch content from a specific catalog
  ///
  /// Parameters:
  /// - [addon]: The addon to fetch from
  /// - [catalog]: The catalog to fetch
  /// - [skip]: Number of items to skip (for pagination)
  /// - [genre]: Optional genre filter
  /// - [extras]: Additional extra parameters as key-value pairs
  ///
  /// Returns a list of StremioMeta items
  Future<List<StremioMeta>> fetchCatalog(
    StremioAddon addon,
    StremioAddonCatalog catalog, {
    int skip = 0,
    String? genre,
    Map<String, String>? extras,
    // Reports the raw number of metas the addon returned for this window
    // (before invalid-id filtering), so callers can advance `skip` in step with
    // the addon's own paging rather than the filtered count.
    void Function(int rawCount)? onRawCount,
    // Bypass the short-TTL page cache (explicit user refresh). The fresh
    // result still overwrites the cached entry.
    bool forceRefresh = false,
  }) async {
    // Build catalog URL: {baseUrl}/catalog/{type}/{catalogId}.json
    // With extra parameters: {baseUrl}/catalog/{type}/{catalogId}/genre=Action.json
    // Multiple extras are joined with &: /genre=Action&skip=20.json
    // Build extra parameters
    final List<String> extraParts = [];
    if (genre != null && genre.isNotEmpty) {
      extraParts.add('genre=${Uri.encodeComponent(genre)}');
    }
    if (skip > 0) {
      extraParts.add('skip=$skip');
    }
    if (extras != null) {
      for (final entry in extras.entries) {
        extraParts.add('${entry.key}=${Uri.encodeComponent(entry.value)}');
      }
    }

    final endpoint = extraParts.isEmpty
        ? '${Uri.encodeComponent(catalog.id)}.json'
        : Uri.encodeComponent(catalog.id);
    final url = buildStremioResourceUri(addon.baseUrl, <String>[
      'catalog',
      catalog.type,
      endpoint,
      if (extraParts.isNotEmpty) '${extraParts.join("&")}.json',
    ]).toString();

    final cached = forceRefresh ? null : _catalogCache[url];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _catalogCacheTtl) {
      onRawCount?.call(cached.rawCount);
      // Defensive copy — callers sort/filter the returned list.
      return List.of(cached.metas);
    }

    debugPrint('StremioService: Fetching catalog');

    try {
      // Use a client that follows redirects
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(url));
        request.followRedirects = true;
        request.maxRedirects = 5;

        final streamedResponse = await client
            .send(request)
            .timeout(_requestTimeout);
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode != 200) {
          debugPrint(
            'StremioService: Catalog fetch failed: HTTP ${response.statusCode}',
          );
          return [];
        }

        final Map<String, dynamic> data = await decodeJsonAsync(response.body);
        final metasRaw = data['metas'] as List<dynamic>?;
        onRawCount?.call(metasRaw?.length ?? 0);

        if (metasRaw == null || metasRaw.isEmpty) {
          debugPrint('StremioService: Catalog returned no items');
          _cacheCatalogPage(url, const [], 0);
          return [];
        }

        // Keep all items with valid ID (not just IMDB) - supports TV channels, etc.
        final metas = metasRaw
            .map((m) {
              final meta = StremioMeta.fromJson(m as Map<String, dynamic>);
              return meta.sourceAddon == null
                  ? meta.withSourceAddon(addon)
                  : meta;
            })
            .where((m) => m.hasValidId)
            .toList();

        debugPrint(
          'StremioService: Catalog returned ${metas.length} valid items',
        );
        _cacheCatalogPage(url, metas, metasRaw.length);
        return List.of(metas);
      } finally {
        client.close();
      }
    } catch (_) {
      // Errors are deliberately not cached — the next visit retries.
      debugPrint('StremioService: Catalog fetch failed');
      return [];
    }
  }

  void _cacheCatalogPage(String url, List<StremioMeta> metas, int rawCount) {
    if (_catalogCache.length >= _catalogCacheMax) {
      // Evict expired entries first, then the oldest, to stay under the cap.
      final now = DateTime.now();
      _catalogCache.removeWhere(
        (_, e) => now.difference(e.fetchedAt) >= _catalogCacheTtl,
      );
      while (_catalogCache.length >= _catalogCacheMax) {
        _catalogCache.remove(_catalogCache.keys.first);
      }
    }
    _catalogCache[url] = (
      metas: metas,
      rawCount: rawCount,
      fetchedAt: DateTime.now(),
    );
  }

  /// Fetch full meta (including videos/episodes) from an addon's meta endpoint.
  /// Returns the raw videos list, or null if the addon doesn't support meta or the fetch fails.
  Future<List<Map<String, dynamic>>?> fetchSeriesMeta(
    StremioAddon addon,
    String contentId,
  ) async {
    if (!addon.resources.contains('meta') || addon.baseUrl.isEmpty) {
      return null;
    }

    // Serve from the short-TTL cache: the episodes panel and the Sources
    // screen's Season chip both fetch the same series meta back-to-back.
    final cacheKey = '${addon.id}:$contentId';
    final cached = _seriesMetaCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _seriesMetaCacheTtl) {
      return cached.videos;
    }

    final url = buildStremioResourceUri(addon.baseUrl, <String>[
      'meta',
      'series',
      '${Uri.encodeComponent(contentId)}.json',
    ]).toString();
    debugPrint('StremioService: Fetching metadata');

    try {
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(url));
        request.followRedirects = true;
        request.maxRedirects = 5;

        final streamedResponse = await client
            .send(request)
            .timeout(_requestTimeout);
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode != 200) {
          debugPrint(
            'StremioService: Meta fetch failed: HTTP ${response.statusCode}',
          );
          return null;
        }

        final data =
            await decodeJsonAsync(response.body) as Map<String, dynamic>?;
        final meta = data?['meta'] as Map<String, dynamic>?;
        final videos = meta?['videos'] as List<dynamic>?;
        if (videos == null || videos.isEmpty) return null;

        final result = videos.whereType<Map<String, dynamic>>().toList();
        // Evict expired entries, then the oldest beyond the cap.
        final now = DateTime.now();
        _seriesMetaCache.removeWhere(
          (_, c) => now.difference(c.fetchedAt) >= _seriesMetaCacheTtl,
        );
        while (_seriesMetaCache.length >= _seriesMetaCacheMax) {
          String? oldestKey;
          DateTime? oldestAt;
          _seriesMetaCache.forEach((key, c) {
            if (oldestAt == null || c.fetchedAt.isBefore(oldestAt!)) {
              oldestAt = c.fetchedAt;
              oldestKey = key;
            }
          });
          _seriesMetaCache.remove(oldestKey);
        }
        _seriesMetaCache[cacheKey] = (videos: result, fetchedAt: now);
        return result;
      } finally {
        client.close();
      }
    } catch (_) {
      debugPrint('StremioService: Metadata fetch failed');
      return null;
    }
  }

  /// First enabled addon that can serve meta (episode listings / season
  /// numbers). Shared so the episodes panel, detail screens, and the Sources
  /// screen's Season chip pick meta addons with one rule.
  Future<StremioAddon?> firstMetaCapableAddon() async {
    for (final a in await getEnabledAddons()) {
      if (a.resources.contains('meta') && a.baseUrl.isNotEmpty) return a;
    }
    return null;
  }

  /// Fetch content from multiple catalogs at once
  ///
  /// Useful for "Browse" mode to show content from all catalog sources
  Future<Map<String, List<StremioMeta>>> fetchAllCatalogs({
    String? type, // Filter by type ('movie' or 'series')
    int limit = 20, // Limit per catalog
  }) async {
    final catalogAddons = await getCatalogAddons();
    final results = <String, List<StremioMeta>>{};

    for (final addon in catalogAddons) {
      for (final catalog in addon.catalogs) {
        // Skip if type filter is set and doesn't match
        if (type != null && catalog.type != type) continue;

        final key = '${addon.name}: ${catalog.name}';
        try {
          final metas = await fetchCatalog(addon, catalog);
          if (metas.isNotEmpty) {
            results[key] = metas.take(limit).toList();
          }
        } catch (_) {
          debugPrint('StremioService: Homepage source failed');
        }
      }
    }

    return results;
  }

  /// Fetch homepage content from all catalog addons
  ///
  /// Returns a list of sections, each containing items from a specific catalog.
  /// Used for the "All" search source with no query (homepage-like view).
  Future<List<CatalogSection>> fetchHomepageContent({
    int itemsPerCatalog = 10,
    int maxSections = 10,
  }) async {
    final catalogAddons = await getCatalogAddons();
    final sections = <CatalogSection>[];

    if (catalogAddons.isEmpty) {
      debugPrint('StremioService: No catalog addons for homepage');
      return [];
    }

    // Fetch from each addon's catalogs in parallel
    final futures = <Future<CatalogSection?>>[];

    for (final addon in catalogAddons) {
      for (final catalog in addon.catalogs) {
        if (sections.length + futures.length >= maxSections) break;

        futures.add(_fetchCatalogSection(addon, catalog, itemsPerCatalog));
      }
      if (sections.length + futures.length >= maxSections) break;
    }

    final results = await Future.wait(futures);
    for (final section in results) {
      if (section != null && section.items.isNotEmpty) {
        sections.add(section);
      }
    }

    debugPrint('StremioService: Homepage loaded ${sections.length} sections');
    return sections;
  }

  /// Fetch a single catalog section for homepage
  Future<CatalogSection?> _fetchCatalogSection(
    StremioAddon addon,
    StremioAddonCatalog catalog,
    int limit,
  ) async {
    try {
      final items = await fetchCatalog(addon, catalog);
      if (items.isEmpty) return null;

      return CatalogSection(
        title: CatalogSection.rowTitle(catalog),
        addon: addon,
        catalog: catalog,
        items: items.take(limit).toList(),
      );
    } catch (_) {
      debugPrint('StremioService: Catalog section fetch failed');
      return null;
    }
  }

  /// Search within a specific addon's searchable catalogs
  ///
  /// Returns deduplicated results from all searchable catalogs of the addon.
  Future<List<StremioMeta>> searchAddonCatalogs(
    StremioAddon addon,
    String query,
  ) async {
    if (query.trim().isEmpty) return [];

    final encodedQuery = Uri.encodeComponent(query.trim());

    // Find all searchable catalogs in this addon
    final searchableCatalogs = addon.catalogs
        .where((c) => c.supportsSearch)
        .toList();

    if (searchableCatalogs.isEmpty) {
      debugPrint(
        'StremioService: Addon ${addon.name} has no searchable catalogs',
      );
      return [];
    }

    debugPrint(
      'StremioService: Searching ${searchableCatalogs.length} catalogs in ${addon.name} for "$query"',
    );

    // Search all catalogs with bounded concurrency (an addon can declare
    // arbitrarily many searchable catalogs)
    final results = await mapWithConcurrency(
      searchableCatalogs,
      (catalog) => _searchSingleCatalog(addon, catalog, encodedQuery),
    );

    // Flatten and deduplicate by ID
    final seen = <String, StremioMeta>{};
    for (final catalogResults in results) {
      for (final meta in catalogResults) {
        final existing = seen[meta.id];
        if (existing == null ||
            _metadataScore(meta) > _metadataScore(existing)) {
          seen[meta.id] = meta;
        }
      }
    }

    final deduped = seen.values.toList();
    debugPrint(
      'StremioService: Addon search returned ${deduped.length} results',
    );
    return deduped;
  }

  /// Search across all catalogs that support search
  ///
  /// Returns deduplicated results by ID, keeping the best metadata.
  /// Supports all content types: movies, series, TV channels, anime, etc.
  Future<List<StremioMeta>> searchCatalogs(String query) async {
    if (query.trim().isEmpty) return [];

    final encodedQuery = Uri.encodeComponent(query.trim());
    // getSearchableAddons (not getCatalogAddons) so this path queries the same
    // addon set as the Search tab — including search-only addons whose
    // manifest omits 'catalog' from `resources`.
    final catalogAddons = await getSearchableAddons();

    if (catalogAddons.isEmpty) {
      debugPrint('StremioService: No searchable addons found');
      return [];
    }

    // Collect all (addon, catalog) pairs that support search
    // Search ALL addons, not just IMDB ones - supports TV channels, anime, etc.
    final searchableCatalogs =
        <({StremioAddon addon, StremioAddonCatalog catalog})>[];
    for (final addon in catalogAddons) {
      for (final catalog in addon.catalogs) {
        if (catalog.supportsSearch) {
          searchableCatalogs.add((addon: addon, catalog: catalog));
        }
      }
    }

    if (searchableCatalogs.isEmpty) {
      debugPrint('StremioService: No catalogs support search');
      return [];
    }

    debugPrint(
      'StremioService: Searching ${searchableCatalogs.length} catalogs for "$query"',
    );

    // Search catalogs with bounded concurrency (order preserved so the dedup
    // loop below can still map allResults[i] back to searchableCatalogs[i]).
    // Capping the fan-out avoids exhausting sockets/memory on weak hardware
    // (e.g. TVs) when many addons are installed.
    final allResults = await mapWithConcurrency(
      searchableCatalogs,
      (entry) => _searchSingleCatalog(entry.addon, entry.catalog, encodedQuery),
    );

    // Flatten and deduplicate by ID (supports any ID format - IMDB, TV channels, etc.)
    final Map<String, StremioMeta> uniqueResults = {};

    for (int i = 0; i < allResults.length; i++) {
      final addon = searchableCatalogs[i].addon;
      for (final meta in allResults[i]) {
        // Skip results without valid ID
        if (meta.id.isEmpty) continue;

        // Tag with source addon (prefer addon that supports meta for series drill-down)
        final tagged = meta.sourceAddon == null
            ? meta.withSourceAddon(addon)
            : meta;

        final existing = uniqueResults[meta.id];
        if (existing == null) {
          uniqueResults[meta.id] = tagged;
        } else {
          // Keep the one with better metadata (prefer one with poster and rating)
          final existingScore = _metadataScore(existing);
          final newScore = _metadataScore(tagged);
          if (newScore > existingScore) {
            final taggedSource = tagged.sourceAddon;
            final existingSource = existing.sourceAddon;
            final bestAddon =
                taggedSource ??
                ((!addon.supportsMeta && existingSource?.supportsMeta == true)
                    ? existingSource!
                    : addon);
            uniqueResults[meta.id] = tagged.sourceAddon == bestAddon
                ? tagged
                : tagged.withSourceAddon(bestAddon);
          } else if (existing.sourceAddon != null &&
              !existing.sourceAddon!.supportsMeta &&
              addon.supportsMeta) {
            // Keep existing metadata but upgrade to addon that supports meta
            uniqueResults[meta.id] = existing.withSourceAddon(addon);
          }
        }
      }
    }

    final results = uniqueResults.values.toList();
    debugPrint(
      'StremioService: Catalog search returned ${results.length} unique results',
    );

    return results;
  }

  /// Search a single catalog
  /// Public per-catalog search — lets callers group results per catalog (e.g.
  /// separate Movie / Series rows) instead of merging them like
  /// [searchAddonCatalogs]. Returns [] for a non-searchable catalog.
  ///
  /// With [throwOnError] a failed request (non-200 / timeout / network error)
  /// throws instead of collapsing to [] — so callers can tell "no results"
  /// apart from "source failed" and surface it.
  Future<List<StremioMeta>> searchSingleCatalog(
    StremioAddon addon,
    StremioAddonCatalog catalog,
    String query, {
    int skip = 0,
    String? genre,
    bool throwOnError = false,
    void Function(int rawCount)? onRawCount,
  }) async {
    if (query.trim().isEmpty || !catalog.supportsSearch) return [];
    final results = await _searchSingleCatalog(
      addon,
      catalog,
      Uri.encodeComponent(query.trim()),
      skip: skip,
      genre: genre,
      throwOnError: throwOnError,
      onRawCount: onRawCount,
    );
    // Tag with the originating addon, matching fetchCatalog — so a searched
    // title carries its source (for the "source" label + episode-meta addon
    // resolution) exactly like a browsed one. Scoped to this per-catalog path;
    // the merged searchAddonCatalogs does its own best-addon tagging.
    return results
        .map((m) => m.sourceAddon == null ? m.withSourceAddon(addon) : m)
        .toList();
  }

  Future<List<StremioMeta>> _searchSingleCatalog(
    StremioAddon addon,
    StremioAddonCatalog catalog,
    String encodedQuery, {
    int skip = 0,
    String? genre,
    bool throwOnError = false,
    void Function(int rawCount)? onRawCount,
  }) async {
    // Build search URL: {baseUrl}/catalog/{type}/{id}/search={query}.json
    // With genre/paging: /search={query}&genre={g}&skip={n}.json (addons that
    // don't support paged search just re-return page 1, which the caller dedups
    // → stop).
    final extraParts = <String>['search=$encodedQuery'];
    if (genre != null && genre.isNotEmpty) {
      extraParts.add('genre=${Uri.encodeComponent(genre)}');
    }
    if (skip > 0) extraParts.add('skip=$skip');
    final url = buildStremioResourceUri(addon.baseUrl, <String>[
      'catalog',
      catalog.type,
      Uri.encodeComponent(catalog.id),
      '${extraParts.join("&")}.json',
    ]).toString();

    debugPrint(
      'StremioService: Searching catalog ${addon.name}/${catalog.name}',
    );

    try {
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(url));
        request.followRedirects = true;
        request.maxRedirects = 5;

        final streamedResponse = await client
            .send(request)
            .timeout(_requestTimeout);
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode != 200) {
          debugPrint(
            'StremioService: ${addon.name}/${catalog.name} search failed: HTTP ${response.statusCode}',
          );
          if (throwOnError) {
            throw http.ClientException(
              'HTTP ${response.statusCode}',
              Uri.parse(url),
            );
          }
          return [];
        }

        final Map<String, dynamic> data = await decodeJsonAsync(response.body);
        final metasRaw = data['metas'] as List<dynamic>?;
        onRawCount?.call(metasRaw?.length ?? 0);

        if (metasRaw == null || metasRaw.isEmpty) {
          return [];
        }

        // Keep all items with valid ID (not just IMDB) - supports TV channels, etc.
        final metas = metasRaw
            .map((m) => StremioMeta.fromJson(m as Map<String, dynamic>))
            .where((m) => m.hasValidId)
            .toList();

        debugPrint(
          'StremioService: ${addon.name}/${catalog.name} returned ${metas.length} results',
        );

        return metas;
      } finally {
        client.close();
      }
    } catch (_) {
      debugPrint('StremioService: Catalog search failed');
      if (throwOnError) rethrow;
      return [];
    }
  }

  /// Calculate metadata quality score (higher = better)
  int _metadataScore(StremioMeta meta) {
    int score = 0;
    if (meta.poster != null) score += 2;
    if (meta.imdbRating != null) score += 2;
    if (meta.year != null) score += 1;
    if (meta.description != null) score += 1;
    return score;
  }

  // ============================================================
  // Validation Methods
  // ============================================================

  String _normalizeManifestUrl(String manifestUrl) {
    return normalizeStremioManifestUri(manifestUrl).toString();
  }

  String _normalizeImportedTransportUrl(String transportUrl) {
    transportUrl = transportUrl.trim();

    if (transportUrl.startsWith('stremio://')) {
      transportUrl = 'https://${transportUrl.substring('stremio://'.length)}';
    }

    while (transportUrl.length > 1 && transportUrl.endsWith('/')) {
      final candidate = transportUrl.substring(0, transportUrl.length - 1);
      final uri = Uri.tryParse(candidate);
      if (uri != null && uri.hasScheme && uri.host.isEmpty) break;
      transportUrl = candidate;
    }

    return transportUrl;
  }

  bool _isLocalTransportUrl(String transportUrl) {
    try {
      final uri = Uri.parse(transportUrl);
      final host = uri.host.toLowerCase();
      return host == 'localhost' ||
          host == '127.0.0.1' ||
          host == '::1' ||
          host.startsWith('127.');
    } catch (_) {
      return false;
    }
  }

  Set<String> _duplicateUrlVariants(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return const {};

    try {
      final manifest = normalizeStremioManifestUri(trimmed);
      final base = stremioBaseUriFromManifest(manifest.toString());
      final baseWithSlash = base.replace(
        path: base.path.endsWith('/') ? base.path : '${base.path}/',
      );
      return <String>{
        trimmed,
        manifest.toString(),
        base.toString(),
        baseWithSlash.toString(),
      };
    } on FormatException {
      // Preserve the previous best-effort behavior for malformed imported
      // values; validation will report the useful error later.
      return <String>{trimmed};
    }
  }

  List<dynamic> _extractAddonDescriptors(dynamic decoded) {
    if (decoded is List) return decoded;

    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);

      final addons = map['addons'];
      if (addons is List) return addons;

      final result = map['result'];
      if (result is Map) {
        final resultAddons = result['addons'];
        if (resultAddons is List) return resultAddons;
      }

      final collection = map['addonCollection'] ?? map['addon_collection'];
      if (collection is Map) {
        final collectionAddons = collection['addons'];
        if (collectionAddons is List) return collectionAddons;
      }
    }

    return const [];
  }

  String _addonDisplayNameFromDescriptor(Map<String, dynamic> descriptor) {
    final rawManifest = descriptor['manifest'];
    if (rawManifest is Map) {
      final name = rawManifest['name'];
      if (name is String && name.trim().isNotEmpty) return name.trim();

      final id = rawManifest['id'];
      if (id is String && id.trim().isNotEmpty) return id.trim();
    }

    final url =
        descriptor['transportUrl'] ??
        descriptor['transport_url'] ??
        descriptor['manifestUrl'] ??
        descriptor['manifest_url'];
    if (url is String && url.trim().isNotEmpty) return url.trim();

    return 'Unknown addon';
  }

  /// Validate that an addon has useful resources
  ///
  /// Returns null if valid, or an error message if invalid.
  /// Accepts any addon that provides streams, catalogs, or subtitles.
  String? _validateAddon(StremioAddon addon) {
    final hasStreams = addon.supportsStreams;
    final hasCatalogs = addon.supportsCatalogs;
    final hasSubtitles = addon.resources.contains('subtitles');

    // Must have at least one useful resource
    if (!hasStreams && !hasCatalogs && !hasSubtitles) {
      return 'This addon doesn\'t provide streams, catalogs, or subtitles. '
          'Debrify requires addons with stream, catalog, or subtitle support.';
    }

    return null; // Valid
  }

  // ============================================================
  // Utility Methods
  // ============================================================

  /// Check if any addons are configured
  Future<bool> hasAddons() async {
    final addons = await getAddons(forSettings: true);
    return addons.isNotEmpty;
  }

  /// Check if any enabled addons are available
  Future<bool> hasEnabledAddons() async {
    final addons = await getEnabledAddons();
    return addons.isNotEmpty;
  }

  /// Get count of enabled addons
  Future<int> getEnabledAddonCount() async {
    final addons = await getEnabledAddons();
    return addons.length;
  }

  /// Invalidate cache (call after external changes)
  void invalidateCache() {
    _addonsCache = null;
    _catalogCache.clear();
  }
}

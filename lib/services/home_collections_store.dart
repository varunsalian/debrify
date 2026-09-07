import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;

import '../models/home_collection.dart';
import '../models/home_collection_inventory.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_scope.dart';
import '../models/stremio_addon.dart';
import 'profiles/profile_preferences.dart';

/// Outcome of an import, for the settings page's result dialog.
class HomeCollectionImportResult {
  /// Collections new to this profile.
  final List<HomeCollection> added;

  /// Collections whose id already existed and were replaced in place
  /// (keeping their enabled state).
  final List<HomeCollection> replaced;

  /// Addon ids no installed addon can serve (see
  /// [HomeCollectionsStore.resolveAddon]). Their folders still import; they
  /// browse empty until such an addon is installed.
  final Set<String> unresolvedAddonIds;

  const HomeCollectionImportResult({
    required this.added,
    required this.replaced,
    required this.unresolvedAddonIds,
  });

  int get collectionCount => added.length + replaced.length;
  int get folderCount =>
      [...added, ...replaced].fold(0, (sum, c) => sum + c.folders.length);
}

/// Profile-scoped store for imported Home collections, plus the import
/// pipeline (file / URL / paste) and the addon-resolution helpers the board,
/// the folder browser and the settings pages share.
///
/// Persists an atomic inventory under `remote_home_collections_v2`. Deleted IDs
/// remain as null records until sync journals their deletion. Reads salvage
/// valid records; ordinary writes reject corruption until explicit reset or
/// restore. Legacy `home_collections_v1` arrays/envelopes remain readable and
/// are retained as an older-build snapshot when the new store is first written.
class HomeCollectionsStore {
  HomeCollectionsStore({http.Client Function()? httpClientFactory})
    : _httpClientFactory = httpClientFactory ?? http.Client.new;

  static final HomeCollectionsStore instance = HomeCollectionsStore();

  static const String prefsKey = HomeCollectionInventory.prefsKey;

  /// Folder layout preference (`rows` | `tabs`), profile-scoped.
  static const String folderLayoutKey = 'home_collections_folder_layout';
  static const Duration _fetchTimeout = Duration(seconds: 20);

  /// Bound downloaded/imported JSON before decoding, including large packs.
  static const int maxImportBytes = 8 * 1024 * 1024;

  final http.Client Function() _httpClientFactory;

  // ── Read / write ───────────────────────────────────────────────────────

  /// Call before opening a picker/downloading, so completion cannot change
  /// the profile which owns an import. Also captures legacy -> profile changes.
  static ({ProfileScope? scope, ProfileScope? active, bool committed})
  captureSession() => (
    scope: ProfileRuntime.isProfileCommitted ? ProfileRuntime.capture() : null,
    active: ProfileRuntime.scope.value,
    committed: ProfileRuntime.isProfileCommitted,
  );

  static void checkSession(
    ({ProfileScope? scope, ProfileScope? active, bool committed}) session,
  ) {
    if (session != captureSession()) {
      throw StateError('The profile changed. Import the collections again.');
    }
  }

  Future<HomeCollectionInventory> getInventory() async {
    final prefs = await ProfilePreferences.instance();
    final inventory = (await HomeCollectionInventory.readAsync(
      prefs.getString(prefsKey) ??
          prefs.getString(HomeCollectionInventory.legacyPrefsKey),
      recover: true,
    )).inventory;
    inventory.syncDeferred =
        prefs.getBool(HomeCollectionInventory.syncDeferredKey) == true;
    return inventory;
  }

  Future<List<HomeCollection>> getCollections() async =>
      (await getInventory()).collections;

  Future<List<HomeCollection>> getEnabledCollections() async => [
    for (final c in await getCollections())
      if (c.enabled && c.folders.isNotEmpty) c,
  ];

  Future<T> _mutate<T>(
    ({ProfileScope? scope, ProfileScope? active, bool committed}) session,
    T Function(HomeCollectionInventory current) update, {
    bool recoverCorruption = false,
  }) async {
    checkSession(session);
    final prefs = await ProfilePreferences.instance();
    checkSession(session);
    late T result;
    final saved = await prefs.mutateStringAsyncAtomically(prefsKey, (
      old,
    ) async {
      checkSession(session);
      final decoded = await HomeCollectionInventory.readAsync(
        old ?? prefs.getString(HomeCollectionInventory.legacyPrefsKey),
        recover: recoverCorruption,
      );
      checkSession(session);
      final current = decoded.inventory;
      if (current.hadCorruption && !recoverCorruption) {
        throw const FormatException(
          'Recovered collections need to be reset or restored before editing.',
        );
      }
      if (recoverCorruption) current.hadCorruption = false;
      final previousSize = decoded.size;
      final previousCount = decoded.count;
      result = update(current);
      final prepared = await current.prepareAsync();
      checkSession(session);
      final encoded = prepared.encoded;
      final size = prepared.size;
      // Bound live definitions, permitting reductions and visibility changes
      // in an older/merged oversized inventory. Pending deletions are outbox
      // records that sync moves into its separately retained tombstone tier.
      if ((size > HomeCollectionInventory.maxStoredBytes &&
              size > previousSize) ||
          (current.liveCount > HomeCollectionInventory.maxRecords &&
              current.liveCount > previousCount)) {
        throw const FormatException(
          'Collection definitions exceed 8 MiB or 1,024 live collections. Remove a collection or import a smaller file.',
        );
      }
      return encoded;
    });
    if (!saved) {
      throw StateError(
        'Could not save collections: device storage limit reached.',
      );
    }
    return result;
  }

  Future<void> saveCollections(List<HomeCollection> collections) =>
      _mutate<void>(captureSession(), (current) {
        final ids = collections.map((c) => c.id).toSet();
        for (final id in current.records.keys.toList()) {
          if (!ids.contains(id)) current.remove(id);
        }
        for (final c in collections) {
          current.put(c);
        }
        final deletedIds = current.order
            .where((id) => !ids.contains(id))
            .toList();
        current.order
          ..clear()
          ..addAll(ids)
          ..addAll(deletedIds);
      });

  static String signatureOf(List<HomeCollection> collections) => sha256
      .convert(
        utf8.encode(jsonEncode([for (final c in collections) c.toJson()])),
      )
      .toString();

  Future<void> remove(String id) =>
      _mutate<void>(captureSession(), (current) => current.remove(id));

  Future<void> setEnabled(String id, bool enabled) =>
      _mutate<void>(captureSession(), (current) {
        final c = current.records[id];
        if (c != null) current.put(c.copyWith(enabled: enabled));
      });

  Future<void> clear() => _mutate<void>(captureSession(), (current) {
    for (final id in current.records.keys.toList()) {
      current.remove(id);
    }
  }, recoverCorruption: true);

  Future<CollectionFolderLayout> getFolderLayout() async {
    final prefs = await ProfilePreferences.instance();
    return CollectionFolderLayout.parse(prefs.getString(folderLayoutKey));
  }

  Future<void> setFolderLayout(CollectionFolderLayout layout) async {
    final session = captureSession();
    final prefs = await ProfilePreferences.instance();
    checkSession(session);
    if (!await prefs.setString(folderLayoutKey, layout.storageValue)) {
      throw StateError(
        'Could not save folder layout: device storage limit reached.',
      );
    }
  }

  // ── Import ─────────────────────────────────────────────────────────────

  /// Merge parsed collections into the store: a known id is replaced in place
  /// (keeping the user's enabled toggle), a new id is appended. With
  /// [replaceExisting] every stored collection is dropped first.
  Future<HomeCollectionImportResult> importCollections(
    List<HomeCollection> incoming, {
    bool replaceExisting = false,
    List<StremioAddon> installedAddons = const [],
    bool recoverCorruption = false,
  }) async {
    final session = captureSession();
    final now = DateTime.now().millisecondsSinceEpoch;
    return _mutate(session, (current) {
      final added = <HomeCollection>[];
      final replaced = <HomeCollection>[];
      if (replaceExisting) {
        for (final id in current.records.keys.toList()) {
          current.remove(id);
        }
      }
      for (final c in incoming) {
        final existing = current.records[c.id];
        final stamped = c.copyWith(
          importedAtMs: now,
          enabled: existing?.enabled ?? c.enabled,
        );
        current.put(stamped);
        (existing == null ? added : replaced).add(stamped);
      }
      return HomeCollectionImportResult(
        added: added,
        replaced: replaced,
        unresolvedAddonIds: unresolvedAddonIds(incoming, installedAddons),
      );
    }, recoverCorruption: recoverCorruption);
  }

  /// Parse and import a JSON document (file contents, pasted text, or a
  /// fetched URL body). Throws [FormatException] for a bad document.
  Future<HomeCollectionImportResult> importJson(
    String jsonText, {
    bool replaceExisting = false,
    List<StremioAddon> installedAddons = const [],
  }) {
    if (utf8.encode(jsonText).length > maxImportBytes) {
      throw const FormatException('That file is too large to be a collection.');
    }
    final parsed = HomeCollectionParser.parse(jsonText);
    return importCollections(
      parsed,
      replaceExisting: replaceExisting,
      installedAddons: installedAddons,
    );
  }

  /// Download a collections JSON from [url] and import it. Throws
  /// [FormatException] for a bad URL / response / document.
  Future<HomeCollectionImportResult> importFromUrl(
    String url, {
    bool replaceExisting = false,
    List<StremioAddon> installedAddons = const [],
  }) async {
    final session = captureSession();
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const FormatException('Enter an http(s) link to a JSON file.');
    }
    final client = _httpClientFactory();
    try {
      final bytes = await (() async {
        final response = await client.send(http.Request('GET', uri));
        if (response.statusCode != 200) {
          throw FormatException(
            'The server answered ${response.statusCode} for that link.',
          );
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > maxImportBytes) {
            throw const FormatException(
              'That file is too large to be a collection.',
            );
          }
          bytes.addAll(chunk);
        }
        return bytes;
      })().timeout(_fetchTimeout);
      checkSession(session);
      return await importJson(
        utf8.decode(bytes),
        replaceExisting: replaceExisting,
        installedAddons: installedAddons,
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Could not download that link: $e');
    } finally {
      client.close();
    }
  }

  // ── Backup / restore ───────────────────────────────────────────────────

  /// The store as a JSON-ready list (the backup payload's `homeCollections`).
  Future<List<Map<String, dynamic>>> exportJson() async => [
    for (final c in await getCollections()) c.toJson(),
  ];

  /// Restore a backup's `homeCollections` list, merging by id so a device
  /// that already holds some of them keeps the rest.
  Future<({int imported, int alreadyPresent, int failed})> applyBackup(
    List<dynamic> list,
  ) async {
    var failed = 0;
    final parsed = <HomeCollection>[];
    for (final raw in list) {
      final c = HomeCollection.fromJson(raw);
      if (c == null) {
        failed++;
      } else {
        parsed.add(c);
      }
    }
    if (parsed.isEmpty) return (imported: 0, alreadyPresent: 0, failed: failed);
    final result = await importCollections(parsed, recoverCorruption: true);
    return (
      imported: result.added.length,
      alreadyPresent: result.replaced.length,
      failed: failed,
    );
  }

  // ── Addon resolution ───────────────────────────────────────────────────

  /// Resolve within the source's addon identity. Catalog ids are local to an
  /// addon; matching another provider's generic id can silently claim its rows.
  static StremioAddon? resolveAddon(
    CollectionCatalogSource source,
    List<StremioAddon> installed,
  ) {
    if (!source.isAddon) return null;
    for (final a in installed) {
      if (!a.enabled) continue;
      if (((a.manifestId ?? a.id) == source.addonId ||
              a.id == source.addonId) &&
          resolveCatalog(source, a) != null) {
        return a;
      }
    }
    return null;
  }

  /// The catalog of [addon] a source points at (type + id), or null.
  static StremioAddonCatalog? resolveCatalog(
    CollectionCatalogSource source,
    StremioAddon addon,
  ) {
    if (!source.isAddon) return null;
    String normalized(String type) => switch (type.trim().toLowerCase()) {
      'movies' => 'movie',
      'tv' || 'show' || 'shows' => 'series',
      final value => value,
    };
    final candidates = addon.catalogs
        .where((c) => c.id == source.catalogId && c.isBrowsable)
        .toList();
    for (final c in candidates) {
      if (normalized(c.type) == normalized(source.type)) return c;
    }
    // Community packs sometimes use All for a catalog with exactly one type.
    if (normalized(source.type) == 'all' && candidates.length == 1) {
      return candidates.single;
    }
    return null;
  }

  static String? sourceIssue(
    CollectionCatalogSource source,
    List<StremioAddon> installed,
  ) {
    if (source.isNative) return null;
    if (!source.isAddon) return 'Unsupported provider: ${source.provider}';
    if (resolveAddon(source, installed) != null) return null;
    final matches = installed
        .where(
          (a) =>
              (a.manifestId ?? a.id) == source.addonId ||
              a.id == source.addonId,
        )
        .toList();
    if (matches.isNotEmpty && matches.every((a) => !a.enabled)) {
      return 'Enable addon ${source.addonId} to load ${source.catalogId}.';
    }
    final present = matches.isNotEmpty;
    return present
        ? '${source.addonId} is installed, but its configuration has no ${source.type}/${source.catalogId} catalog.'
        : 'Install addon ${source.addonId} to load ${source.catalogId}.';
  }

  /// Home-row keys (`addonId:type:catalogId`) of every catalog an enabled
  /// collection folder resolves to. As in Nuvio, a list lives in its folder
  /// rather than in both places, so these are left off the Home board and
  /// out of the addon groups in the Home Rows manager.
  static Set<String> claimedCatalogKeys(
    List<HomeCollection> collections,
    List<StremioAddon> installed, {
    Set<String> disabledRows = const {},
    bool showsCollectionRows = true,
  }) {
    final out = <String>{};
    if (!showsCollectionRows) return out;
    for (final c in collections) {
      if (!c.enabled || disabledRows.contains(c.rowId)) continue;
      for (final f in c.folders) {
        for (final s in f.sources) {
          final addon = resolveAddon(s, installed);
          if (addon == null) continue;
          final catalog = resolveCatalog(s, addon);
          if (catalog == null) continue;
          out.add('${addon.id}:${catalog.type}:${catalog.id}');
        }
      }
    }
    return out;
  }

  /// Addon ids referenced by [collections] that nothing in [installed] can
  /// serve, by id or by catalog match.
  static Set<String> unresolvedAddonIds(
    List<HomeCollection> collections,
    List<StremioAddon> installed,
  ) {
    final out = <String>{};
    for (final c in collections) {
      for (final f in c.folders) {
        for (final s in f.sources) {
          if (s.isAddon && resolveAddon(s, installed) == null) {
            out.add(s.addonId);
          }
        }
      }
    }
    return out;
  }
}

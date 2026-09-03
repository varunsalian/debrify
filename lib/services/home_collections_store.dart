import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/home_collection.dart';
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
/// Persists one JSON string under `home_collections_v1` with the same
/// conventions as the Home-row stores in `StorageService`: `prefs.remove` on
/// empty, decode failures swallowed to a safe default.
class HomeCollectionsStore {
  HomeCollectionsStore({http.Client Function()? httpClientFactory})
    : _httpClientFactory = httpClientFactory ?? http.Client.new;

  static final HomeCollectionsStore instance = HomeCollectionsStore();

  static const String prefsKey = 'home_collections_v1';

  /// Folder layout preference (`rows` | `tabs`), profile-scoped.
  static const String folderLayoutKey = 'home_collections_folder_layout';
  static const Duration _fetchTimeout = Duration(seconds: 20);

  /// Documents past this are refused before decoding: a collections file is
  /// a few hundred KB at most, so anything larger is a wrong pick.
  static const int maxImportBytes = 8 * 1024 * 1024;

  final http.Client Function() _httpClientFactory;

  // ── Read / write ───────────────────────────────────────────────────────

  Future<List<HomeCollection>> getCollections() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(prefsKey);
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      final seen = <String>{};
      return [
        for (final raw in decoded)
          if (HomeCollection.fromJson(raw) case final c?)
            if (seen.add(c.id)) c,
      ];
    } catch (e) {
      debugPrint('HomeCollectionsStore: error reading collections: $e');
      return const [];
    }
  }

  /// Only the collections the board should show.
  Future<List<HomeCollection>> getEnabledCollections() async => [
    for (final c in await getCollections())
      if (c.enabled && c.folders.isNotEmpty) c,
  ];

  Future<void> saveCollections(List<HomeCollection> collections) async {
    final prefs = await ProfilePreferences.instance();
    if (collections.isEmpty) {
      await prefs.remove(prefsKey);
      return;
    }
    await prefs.setString(
      prefsKey,
      jsonEncode([for (final c in collections) c.toJson()]),
    );
  }

  /// Cheap change token for the Home board's settings-changed listener, which
  /// reloads only when this differs from what it last built from.
  static String signatureOf(List<HomeCollection> collections) => [
    for (final c in collections)
      '${c.id}:${c.enabled ? 1 : 0}:${c.importedAtMs ?? 0}:${c.folders.length}',
  ].join('|');

  Future<void> remove(String collectionId) async {
    final current = await getCollections();
    await saveCollections([
      for (final c in current)
        if (c.id != collectionId) c,
    ]);
  }

  Future<void> setEnabled(String collectionId, bool enabled) async {
    final current = await getCollections();
    await saveCollections([
      for (final c in current)
        if (c.id == collectionId) c.copyWith(enabled: enabled) else c,
    ]);
  }

  Future<void> clear() => saveCollections(const []);

  // ── Folder layout ──────────────────────────────────────────────────────

  Future<CollectionFolderLayout> getFolderLayout() async {
    try {
      final prefs = await ProfilePreferences.instance();
      return CollectionFolderLayout.parse(prefs.getString(folderLayoutKey));
    } catch (_) {
      return CollectionFolderLayout.rows;
    }
  }

  Future<void> setFolderLayout(CollectionFolderLayout layout) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(folderLayoutKey, layout.storageValue);
  }

  // ── Import ─────────────────────────────────────────────────────────────

  /// Merge parsed collections into the store: a known id is replaced in place
  /// (keeping the user's enabled toggle), a new id is appended. With
  /// [replaceExisting] every stored collection is dropped first.
  Future<HomeCollectionImportResult> importCollections(
    List<HomeCollection> incoming, {
    bool replaceExisting = false,
    List<StremioAddon> installedAddons = const [],
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final current = replaceExisting
        ? <HomeCollection>[]
        : List<HomeCollection>.of(await getCollections());
    final byId = {for (final c in current) c.id: c};

    final added = <HomeCollection>[];
    final replaced = <HomeCollection>[];
    for (final c in incoming) {
      final existing = byId[c.id];
      final stamped = c.copyWith(
        importedAtMs: now,
        enabled: existing?.enabled ?? c.enabled,
      );
      if (existing != null) {
        final i = current.indexWhere((e) => e.id == c.id);
        current[i] = stamped;
        replaced.add(stamped);
      } else {
        current.add(stamped);
        added.add(stamped);
      }
      byId[c.id] = stamped;
    }
    await saveCollections(current);

    return HomeCollectionImportResult(
      added: added,
      replaced: replaced,
      unresolvedAddonIds: unresolvedAddonIds(incoming, installedAddons),
    );
  }

  /// Parse and import a JSON document (file contents, pasted text, or a
  /// fetched URL body). Throws [FormatException] for a bad document.
  Future<HomeCollectionImportResult> importJson(
    String jsonText, {
    bool replaceExisting = false,
    List<StremioAddon> installedAddons = const [],
  }) {
    if (jsonText.length > maxImportBytes) {
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
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const FormatException('Enter an http(s) link to a JSON file.');
    }
    final client = _httpClientFactory();
    try {
      final response = await client.get(uri).timeout(_fetchTimeout);
      if (response.statusCode != 200) {
        throw FormatException(
          'The server answered ${response.statusCode} for that link.',
        );
      }
      if (response.bodyBytes.length > maxImportBytes) {
        throw const FormatException(
          'That file is too large to be a collection.',
        );
      }
      return await importJson(
        utf8.decode(response.bodyBytes, allowMalformed: true),
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
    final result = await importCollections(parsed);
    return (
      imported: result.added.length,
      alreadyPresent: result.replaced.length,
      failed: failed,
    );
  }

  // ── Addon resolution ───────────────────────────────────────────────────

  /// The installed addon a source refers to: an exact manifest-id match, else
  /// any installed addon serving a catalog with the same `type` + `catalogId`.
  /// The fallback matters because the file was made against someone else's
  /// install, and the same addon deployed elsewhere can carry another id.
  static StremioAddon? resolveAddon(
    CollectionCatalogSource source,
    List<StremioAddon> installed,
  ) {
    for (final a in installed) {
      if (a.id == source.addonId) return a;
    }
    for (final a in installed) {
      if (a.catalogs.any(
        (c) => c.id == source.catalogId && c.type == source.type,
      )) {
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
    for (final c in addon.catalogs) {
      if (c.id == source.catalogId && c.type == source.type) return c;
    }
    return null;
  }

  /// Home-row keys (`addonId:type:catalogId`) of every catalog an enabled
  /// collection folder resolves to. As in Nuvio, a list lives in its folder
  /// rather than in both places, so these are left off the Home board and
  /// out of the addon groups in the Home Rows manager.
  static Set<String> claimedCatalogKeys(
    List<HomeCollection> collections,
    List<StremioAddon> installed,
  ) {
    final out = <String>{};
    for (final c in collections) {
      if (!c.enabled) continue;
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
          if (resolveAddon(s, installed) == null) out.add(s.addonId);
        }
      }
    }
    return out;
  }
}

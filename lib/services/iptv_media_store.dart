import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/iptv_playlist.dart';
import '../utils/json_isolate.dart';
import 'debrify_tv_database.dart';
import 'diagnostic_log.dart' as app_diagnostics;
import 'iptv_catalog_db.dart';
import 'iptv_channel_order.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_runtime.dart';
import 'webdav_sync/webdav_sync_library_models.dart';
import 'webdav_sync/webdav_sync_library_mutation.dart';

/// SQLite-backed store for IPTV favorites, IPTV watch history and the shared
/// video-resume map.
///
/// All three used to live in SharedPreferences as single JSON blobs, which
/// made every mutation a read-modify-write of the whole store — racy against
/// concurrent writers (the reconcile scan yields mid-flight exactly so users
/// can star things while it runs) and increasingly expensive as they grow.
/// Rows in `debrify_tv.db` give each mutation row-level atomicity via
/// transactions instead. The legacy prefs blobs are imported once on first
/// use and then removed; the prefs keys are only deleted after a successful
/// import, so a failed import simply retries on the next call.
///
/// [StorageService] keeps its public API and delegates here — call sites are
/// unchanged.
/// compute() entry for [IptvMediaStore.reconcileFavoriteUrlsForCatalog]:
/// reads the catalog's current rows from the DB and computes the
/// stored-URL → current-URL renames with the same canonical-match rules the
/// in-memory scan uses, plus the content-type/duration backfill for stored
/// rows that never captured it. Runs entirely on the worker; only the (tiny)
/// result crosses back.
FavoriteRenameResult computeFavoriteRenamesJob(FavoriteRenameJob job) {
  // Set-valued: with per-list membership rows, two different lists can hold
  // two DIFFERENT historical URL forms of the same channel. They collapse to
  // one canonical key, so a single-valued map would keep only one of them and
  // silently leave the other list's row on a dead URL forever.
  final storedByCanonical = <String, Set<String>>{};
  for (final url in job.storedUrls) {
    storedByCanonical
        .putIfAbsent(IptvMediaStore.canonicalChannelKey(url), () => <String>{})
        .add(url);
  }
  // Cheap pre-filter, same as the in-memory scan: a channel can only match
  // a stored row on the same host.
  final storedHosts = <String>{
    for (final url in job.storedUrls)
      if (Uri.tryParse(url)?.host.isNotEmpty ?? false) Uri.parse(url).host,
  };
  final needsMeta = job.urlsNeedingMeta.toSet();
  final renames = <String, String>{};
  final meta = <String, ChannelPresentation>{};
  for (final row in IptvCatalogDb.catalogPresentationRows(
    dbPath: job.dbPath,
    catalogKey: job.catalogKey,
  )) {
    if (storedByCanonical.isEmpty) break;
    if (!storedHosts.any(row.url.contains)) continue;
    final storedUrls = storedByCanonical.remove(
      IptvMediaStore.canonicalChannelKey(row.url),
    );
    if (storedUrls == null) continue;
    for (final storedUrl in storedUrls) {
      if (storedUrl != row.url) renames[storedUrl] = row.url;
      if (needsMeta.contains(storedUrl)) {
        meta[storedUrl] = ChannelPresentation(
          contentType: row.contentType,
          duration: row.duration,
        );
      }
    }
  }
  return FavoriteRenameResult(renames: renames, meta: meta);
}

/// How a stored list channel should present itself when it is rebuilt from
/// storage alone: live vs on-demand, and the runtime a progress bar needs.
class ChannelPresentation {
  final String? contentType;
  final int? duration;

  const ChannelPresentation({this.contentType, this.duration});

  bool get isEmpty => contentType == null && duration == null;
}

class FavoriteRenameResult {
  /// stored URL → current URL.
  final Map<String, String> renames;

  /// stored URL → presentation metadata for rows that had none.
  final Map<String, ChannelPresentation> meta;

  const FavoriteRenameResult({required this.renames, required this.meta});

  bool get isEmpty => renames.isEmpty && meta.isEmpty;
}

class FavoriteRenameJob {
  final String dbPath;
  final String catalogKey;
  final List<String> storedUrls;

  /// The subset of [storedUrls] whose content_type/duration is still unknown
  /// — migrated favorites, which predate those columns.
  final List<String> urlsNeedingMeta;

  const FavoriteRenameJob({
    required this.dbPath,
    required this.catalogKey,
    required this.storedUrls,
    this.urlsNeedingMeta = const [],
  });
}

/// A user-created (or built-in) channel list.
class IptvListMeta {
  final String id;
  final String name;
  final int position;
  final bool isBuiltin;
  final int channelCount;

  const IptvListMeta({
    required this.id,
    required this.name,
    required this.position,
    required this.isBuiltin,
    required this.channelCount,
  });

  bool get isFavorites => id == IptvMediaStore.favoritesListId;
}

class IptvMediaStore {
  IptvMediaStore._();

  /// Bumped after every write to `iptv_lists` / `iptv_list_channels` —
  /// create/rename/delete/reorder, membership toggles, provider-deletion
  /// cleanup and URL reconciliation alike. This is the invalidation signal
  /// for surfaces that mirror list contents OUTSIDE the IPTV page (the Home
  /// board's IPTV list rows): every mutation path funnels through this
  /// store, so signalling here — not in the callers — is what keeps a
  /// renamed, emptied or reconciled list from going stale on a Home that
  /// never remounts.
  static final ValueNotifier<int> listsRevision = ValueNotifier<int>(0);

  /// ValueNotifier listeners run synchronously and may start detached reads.
  /// Call only after the mutation's outer [_runScoped] has completed so those
  /// reads cannot inherit its captured database handle and bypass admission.
  static void _bumpListsRevision() => listsRevision.value++;

  /// Replays list invalidation after exact-stamp sync materialization.
  /// This is UI-only and deliberately does not schedule another sync cycle.
  static void notifyListsChanged() => _bumpListsRevision();

  static const String _legacyFavoritesKey = 'iptv_favorite_channels_v1';
  static const String _legacyWatchHistoryKey = 'iptv_watch_history_v1';
  static const String _legacyVideoResumeKey = 'video_resume_v1';

  /// How many watched on-demand items to remember. A panel can list tens of
  /// thousands of movies, and this backs a short "pick up where you left off"
  /// shelf — not an archive.
  static const int _watchHistoryMax = 100;

  /// How long the reconcile scan may hold the isolate before yielding — a
  /// 50k-channel playlist would otherwise block input on the way in.
  static const _scanYieldBudget = Duration(milliseconds: 8);

  /// SQLite's default host-parameter limit is 999; stay comfortably under it
  /// when batching `IN (...)` lookups.
  static const int _inChunkSize = 500;

  static Future<void>? _migration;
  static String? _migrationScopeKey;

  @visibleForTesting
  static void debugResetMigration() {
    _migration = null;
    _migrationScopeKey = null;
  }

  @visibleForTesting
  static DateTime Function() debugLibraryClock = DateTime.now;

  static final WebDavSyncMonotonicStamp _monotonicStamp =
      WebDavSyncMonotonicStamp();

  /// Stamp time for a user library mutation; strictly increasing per clock so
  /// a backwards clock step cannot reuse a stamp for a different mutation.
  static int _nextStampMs() => _monotonicStamp.next(debugLibraryClock);

  static Future<void> _ensureMigrated() {
    final scopeKey = ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted
        ? ProfileRuntime.capture().preferencePrefix
        : 'legacy';
    if (_migrationScopeKey != scopeKey) {
      _migration = null;
      _migrationScopeKey = scopeKey;
    }
    return _migration ??= _migrateFromPrefs().catchError((Object e) {
      // A failed import must never make favorites or resume unreadable —
      // clear the memo so the next call retries, and carry on with whatever
      // is already in the DB.
      _migration = null;
      debugPrint('IptvMediaStore: legacy prefs import failed: $e');
    });
  }

  /// Keeps first-use migration and the caller's actual operation on the same
  /// captured profile. Without this outer scope a switch could complete in
  /// the await between them and apply an A-originated request to B.
  static Future<T> _runScoped<T>(Future<T> Function(Database db) action) {
    return DebrifyTvDatabase.instance.runScoped((db) async {
      await _ensureMigrated();
      return action(db);
    });
  }

  static Future<void> _migrateFromPrefs() async {
    final prefs = await ProfilePreferences.instance();
    final db = DebrifyTvDatabase.instance;

    // Every family lands through one batch commit per transaction: a restored
    // legacy blob can hold years of entries, and issuing two awaited platform
    // calls per row once froze the shared connection for minutes while every
    // screen queued behind it.
    Map<String, Object?> migrationState({
      required String kind,
      required String ownerKey,
      required String itemKey,
      required int updatedAtMs,
    }) => <String, Object?>{
      'kind': kind,
      'owner_key': ownerKey,
      'item_key': itemKey,
      'updated_at_ms': updatedAtMs,
      'origin_device_id': WebDavSyncMutationOrigin.migration.name,
      'normalized': 0,
      'deleted': 0,
      'aux': null,
    };

    Future<
      ({
        Set<(String, String, String)> keys,
        Set<(String, String)> physicalItems,
      })
    >
    existingStateKeys(DatabaseExecutor txn) async {
      final rows = await txn.query(
        'webdav_sync_record_state',
        columns: const <String>['kind', 'owner_key', 'item_key'],
      );
      return (
        keys: <(String, String, String)>{
          for (final row in rows)
            (
              row['kind']! as String,
              row['owner_key']! as String,
              row['item_key']! as String,
            ),
        },
        physicalItems: <(String, String)>{
          for (final row in rows)
            (row['kind']! as String, row['item_key']! as String),
        },
      );
    }

    Future<void> removeImportedPreference(String key) async {
      if (!await prefs.remove(key)) {
        _recordLegacyPreferenceRemovalFailure();
      }
    }

    final favoritesRaw = prefs.getString(_legacyFavoritesKey);
    if (favoritesRaw != null) {
      final favorites = await _decodeLegacyMap(favoritesRaw);
      await db.runTxn((txn) async {
        // A very old install can reach v5 with the prefs blob still present,
        // so the import lands straight in the built-in Favorites list.
        await DebrifyTvDatabase.seedBuiltinList(txn);
        final existing = await existingStateKeys(txn);
        final batch = txn.batch();
        var imported = false;
        for (final entry in favorites.entries) {
          final stateKey = (
            WebDavSyncLibraryKinds.iptvListChannels,
            favoritesListId,
            entry.key,
          );
          if (existing.keys.contains(stateKey)) continue;
          final row = _favoriteRowFromLegacy(entry.key, entry.value);
          batch.insert(
            'iptv_list_channels',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          batch.insert(
            'webdav_sync_record_state',
            migrationState(
              kind: WebDavSyncLibraryKinds.iptvListChannels,
              ownerKey: favoritesListId,
              itemKey: entry.key,
              updatedAtMs: row['added_at']! as int,
            ),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          existing.keys.add(stateKey);
          existing.physicalItems.add((stateKey.$1, stateKey.$3));
          imported = true;
        }
        await batch.commit(noResult: true);
        if (imported) await _bumpLibraryRevision(txn);
      });
      await removeImportedPreference(_legacyFavoritesKey);
    }

    final historyRaw = prefs.getString(_legacyWatchHistoryKey);
    if (historyRaw != null) {
      final history = await _decodeLegacyMap(historyRaw);
      // The store prunes history to [_watchHistoryMax] rows on every write;
      // importing an unbounded legacy blob beyond that only feeds the prune.
      final rows =
          history.entries
              .map((entry) => _historyRowFromLegacy(entry.key, entry.value))
              .toList(growable: false)
            ..sort(
              (left, right) => (right['last_played_at']! as int).compareTo(
                left['last_played_at']! as int,
              ),
            );
      final kept = rows.take(_watchHistoryMax).toList(growable: false);
      await db.runTxn((txn) async {
        final existing = await existingStateKeys(txn);
        final batch = txn.batch();
        var imported = false;
        for (final row in kept) {
          final stateKey = (
            WebDavSyncLibraryKinds.iptvWatchHistory,
            row['playlist_id']! as String,
            row['url']! as String,
          );
          if (existing.physicalItems.contains((stateKey.$1, stateKey.$3))) {
            continue;
          }
          batch.insert(
            'iptv_watch_history',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          batch.insert(
            'webdav_sync_record_state',
            migrationState(
              kind: WebDavSyncLibraryKinds.iptvWatchHistory,
              ownerKey: row['playlist_id']! as String,
              itemKey: row['url']! as String,
              updatedAtMs: row['last_played_at']! as int,
            ),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          existing.keys.add(stateKey);
          existing.physicalItems.add((stateKey.$1, stateKey.$3));
          imported = true;
        }
        await batch.commit(noResult: true);
        if (imported) await _bumpLibraryRevision(txn);
      });
      await removeImportedPreference(_legacyWatchHistoryKey);
    }

    final resumeRaw = prefs.getString(_legacyVideoResumeKey);
    if (resumeRaw != null) {
      final resume = await _decodeLegacyMap(resumeRaw);
      await db.runTxn((txn) async {
        final existing = await existingStateKeys(txn);
        final historyRows = await txn.query(
          'iptv_watch_history',
          columns: const <String>['url', 'playlist_id'],
        );
        final sourceByUrl = <String, String?>{
          for (final row in historyRows)
            row['url']! as String: row['playlist_id'] as String?,
        };
        final batch = txn.batch();
        var imported = false;
        for (final entry in resume.entries) {
          final value = entry.value;
          if (value is! Map) continue;
          final sourceId = sourceByUrl[entry.key];
          final ownerKey = (sourceId == null || sourceId.isEmpty)
              ? '_'
              : sourceId;
          final stateKey = (
            WebDavSyncLibraryKinds.videoResume,
            ownerKey,
            entry.key,
          );
          if (existing.physicalItems.contains((stateKey.$1, stateKey.$3))) {
            continue;
          }
          final row = _resumeRow(
            entry.key,
            Map<String, dynamic>.from(value),
            sourceId: sourceId,
          );
          batch.insert(
            'video_resume',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          batch.insert(
            'webdav_sync_record_state',
            migrationState(
              kind: WebDavSyncLibraryKinds.videoResume,
              ownerKey: ownerKey,
              itemKey: entry.key,
              updatedAtMs: row['updated_at']! as int,
            ),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          existing.keys.add(stateKey);
          existing.physicalItems.add((stateKey.$1, stateKey.$3));
          imported = true;
        }
        await batch.commit(noResult: true);
        if (imported) await _bumpLibraryRevision(txn);
      });
      await removeImportedPreference(_legacyVideoResumeKey);
    }
  }

  static void _recordLegacyPreferenceRemovalFailure() {
    app_diagnostics.DiagnosticLog.instance.recordEvent(
      source: 'iptv_media_store',
      event: 'legacy_preference_remove_failed',
      level: app_diagnostics.DiagnosticLevel.warning,
      fields: const <String, Object?>{
        'reason': app_diagnostics.DiagnosticLabel(
          'legacy_import_cleanup_failed',
        ),
      },
    );
  }

  /// Decoded off the UI isolate: the resume blob in particular can have
  /// grown large, and this runs exactly when the user first opens IPTV.
  static Future<Map<String, dynamic>> _decodeLegacyMap(String raw) async {
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // A corrupt legacy blob read as empty before the migration too;
      // importing nothing preserves that.
    }
    return {};
  }

  // ── Canonical identity ────────────────────────────────────────────────────

  /// Canonical comparison key for an IPTV channel URL. Xtream Codes stream
  /// URL formats have changed over time (optional /live/ prefix,
  /// percent-encoded credentials, .m3u8 vs .ts extension), so favorites are
  /// matched on a format-insensitive key rather than the raw string.
  static String canonicalChannelKey(String url) {
    // Stremio-addon channel keys (stremio-tv://addon/meta) are already
    // stable synthetic identities — never normalize them (Uri would
    // lowercase the addon-id "host" and decode the meta id).
    if (url.startsWith('stremio-tv://')) return url;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    // pathSegments are percent-decoded, which normalizes credential encoding.
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    // Drop the /live/ prefix only for URLs shaped like Xtream live streams
    // (.../live/<user>/<pass>/<numeric id>.<ext>) — not arbitrary /live/
    // paths, which belong to ordinary playlists where the segment is
    // significant.
    final xtreamLeaf = RegExp(r'^\d+\.\w+$');
    var isXtreamLive = false;
    if (segments.length >= 4 &&
        segments[segments.length - 4] == 'live' &&
        xtreamLeaf.hasMatch(segments.last)) {
      segments.removeAt(segments.length - 4);
      isXtreamLive = true;
    } else if (segments.length == 3 && xtreamLeaf.hasMatch(segments.last)) {
      // Legacy un-prefixed form: /<user>/<pass>/<numeric id>.<ext>.
      isXtreamLive = true;
    }
    // For Xtream live URLs the extension is presentation, not identity: the
    // same channel is served as .m3u8 on HLS panels and .ts on HLS-off ones
    // (VOD /movie/ URLs keep theirs — the container is real there).
    if (isXtreamLive) {
      final leaf = segments.last;
      segments[segments.length - 1] = leaf.substring(0, leaf.indexOf('.'));
    }
    final port = uri.hasPort ? ':${uri.port}' : '';
    // Keep the query: distinct channels can differ only by query params.
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '${uri.scheme}://${uri.host}$port/${segments.join('/')}$query';
  }

  // ── Lists (Favorites is the built-in one) ─────────────────────────────────

  /// Reserved id of the built-in Favorites list.
  static const String favoritesListId = DebrifyTvDatabase.favoritesListId;

  /// Every list, Favorites first, then custom lists in user order.
  static Future<List<IptvListMeta>> lists() {
    return _runScoped((db) async {
      // One query: a per-list COUNT(*) round-trip would be N reads on every
      // settings pass, and the page asks for this on each load.
      final rows = await db.rawQuery('''
        SELECT l.id, l.name, l.position, l.is_builtin,
               (SELECT COUNT(*) FROM iptv_list_channels c WHERE c.list_id = l.id)
                 AS channel_count
        FROM iptv_lists l
        ORDER BY l.position ASC, l.name ASC
      ''');
      return [
        for (final row in rows)
          IptvListMeta(
            id: row['id'] as String,
            name: row['name'] as String,
            position: (row['position'] as num?)?.toInt() ?? 0,
            isBuiltin: ((row['is_builtin'] as num?)?.toInt() ?? 0) != 0,
            channelCount: (row['channel_count'] as num?)?.toInt() ?? 0,
          ),
      ];
    });
  }

  /// Create a list and return its id. Names are not unique-enforced here —
  /// the picker validates before calling, and a duplicate name is a display
  /// annoyance rather than a data problem.
  static Future<String> createList(
    String name, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    var stamped = false;
    final id = await _runScoped((_) async {
      final trimmed = name.trim();
      final now = origin == WebDavSyncMutationOrigin.user
          ? _nextStampMs()
          : DateTime.now().millisecondsSinceEpoch;
      final random = math.Random.secure();
      final suffix = base64UrlEncode(
        List<int>.generate(8, (_) => random.nextInt(256), growable: false),
      ).replaceAll('=', '');
      final id = 'list_${now}_$suffix';
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        final maxRow = await txn.rawQuery(
          'SELECT MAX(position) AS p FROM iptv_lists',
        );
        final nextPosition = ((maxRow.first['p'] as num?)?.toInt() ?? 0) + 1;
        await txn.insert('iptv_lists', {
          'id': id,
          'name': trimmed,
          'position': nextPosition,
          'is_builtin': 0,
          'created_at': now,
          'updated_at': now,
        });
        if (origin == WebDavSyncMutationOrigin.user) {
          await _writeLibraryState(
            txn,
            kind: WebDavSyncLibraryKinds.iptvLists,
            ownerKey: id,
            itemKey: '',
            updatedAtMs: now,
            deleted: false,
            origin: origin,
          );
          await _bumpLibraryRevision(txn);
          stamped = true;
        }
      });
      return id;
    });
    _bumpListsRevision();
    if (stamped) WebDavSyncLibraryMutation.notifyUserMutation();
    return id;
  }

  /// Rename a custom list. The built-in Favorites list is not renameable.
  static Future<void> renameList(
    String listId,
    String name, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    if (listId == favoritesListId) return;
    var changed = false;
    await _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        final now = origin == WebDavSyncMutationOrigin.user
            ? _nextStampMs()
            : DateTime.now().millisecondsSinceEpoch;
        final updated = await txn.update(
          'iptv_lists',
          {'name': name.trim(), 'updated_at': now},
          where: 'id = ? AND is_builtin = 0',
          whereArgs: [listId],
        );
        if (updated == 0) return;
        changed = true;
        if (origin == WebDavSyncMutationOrigin.user) {
          await _writeLibraryState(
            txn,
            kind: WebDavSyncLibraryKinds.iptvLists,
            ownerKey: listId,
            itemKey: '',
            updatedAtMs: now,
            deleted: false,
            origin: origin,
          );
          await _bumpLibraryRevision(txn);
        }
      });
    });
    _bumpListsRevision();
    if (changed && origin == WebDavSyncMutationOrigin.user) {
      WebDavSyncLibraryMutation.notifyUserMutation();
    }
  }

  /// Delete a custom list. Memberships go with it via ON DELETE CASCADE —
  /// the channels themselves are untouched, they just stop being in a list.
  static Future<void> deleteList(
    String listId, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    if (listId == favoritesListId) return;
    var changed = false;
    var stamped = false;
    await _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        final deleted = await txn.delete(
          'iptv_lists',
          where: 'id = ? AND is_builtin = 0',
          whereArgs: [listId],
        );
        changed = deleted != 0;
        if (origin != WebDavSyncMutationOrigin.user) return;
        final liveStates = await txn.query(
          'webdav_sync_record_state',
          columns: const <String>['item_key'],
          where: 'kind = ? AND owner_key = ? AND item_key = ? AND deleted = 0',
          whereArgs: <Object?>[WebDavSyncLibraryKinds.iptvLists, listId, ''],
          limit: 1,
        );
        if (!changed && liveStates.isEmpty) return;
        await _writeLibraryState(
          txn,
          kind: WebDavSyncLibraryKinds.iptvLists,
          ownerKey: listId,
          itemKey: '',
          updatedAtMs: _nextStampMs(),
          deleted: true,
          origin: origin,
        );
        await _bumpLibraryRevision(txn);
        stamped = true;
      });
    });
    if (changed) _bumpListsRevision();
    if (stamped) WebDavSyncLibraryMutation.notifyUserMutation();
  }

  /// Reorder custom lists. Favorites is pinned at position 0 and ignored
  /// here; everything named in [orderedIds] takes 1..n in that order.
  static Future<void> reorderLists(
    List<String> orderedIds, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    var changed = false;
    await _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        final rows = await txn.query(
          'iptv_lists',
          columns: const <String>['id', 'position'],
          where: 'is_builtin = 0',
        );
        final positions = <String, int>{
          for (final row in rows)
            row['id']! as String: (row['position'] as num).toInt(),
        };
        final moved = <(String, int)>[];
        var position = 1;
        for (final id in orderedIds) {
          if (id == favoritesListId) continue;
          final oldPosition = positions[id];
          if (oldPosition != null && oldPosition != position) {
            moved.add((id, position));
          }
          position += 1;
        }
        if (moved.isEmpty) return;
        final now = origin == WebDavSyncMutationOrigin.user
            ? _nextStampMs()
            : DateTime.now().millisecondsSinceEpoch;
        for (final item in moved) {
          await txn.update(
            'iptv_lists',
            {'position': item.$2, 'updated_at': now},
            where: 'id = ? AND is_builtin = 0',
            whereArgs: [item.$1],
          );
          if (origin == WebDavSyncMutationOrigin.user) {
            await _writeLibraryState(
              txn,
              kind: WebDavSyncLibraryKinds.iptvLists,
              ownerKey: item.$1,
              itemKey: '',
              updatedAtMs: now,
              deleted: false,
              origin: origin,
            );
          }
        }
        changed = true;
        if (origin == WebDavSyncMutationOrigin.user) {
          await _bumpLibraryRevision(txn);
        }
      });
    });
    _bumpListsRevision();
    if (changed && origin == WebDavSyncMutationOrigin.user) {
      WebDavSyncLibraryMutation.notifyUserMutation();
    }
  }

  // ── Membership ────────────────────────────────────────────────────────────

  /// Rewrite stored membership URLs to the current format when a fetched
  /// channel matches a stored row canonically but not literally (e.g. rows
  /// saved before the Xtream /live/ URL fix), and backfill the presentation
  /// metadata of rows migrated from the old favorites table.
  ///
  /// This is the in-memory variant, used by local files and Stremio addon
  /// catalogs — the only reconcile path those sources ever take, so the
  /// backfill has to live here too or their migrated VOD favorites would
  /// present as live forever.
  static Future<void> reconcileFavoriteUrls(
    List<IptvChannel> channels, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    final changed = await _runScoped((db) async {
      final urlRows = await db.rawQuery(
        'SELECT DISTINCT url FROM iptv_list_channels',
      );
      if (urlRows.isEmpty) return false;
      final storedUrls = [for (final row in urlRows) row['url'] as String];
      final needsMeta = await _urlsNeedingPresentation(db);

      // Set-valued: two lists can hold two different historical URL forms of
      // the same channel, which collapse to one canonical key. A single-valued
      // map would keep only one and strand the other on a dead URL.
      final storedByCanonical = <String, Set<String>>{};
      for (final url in storedUrls) {
        storedByCanonical
            .putIfAbsent(canonicalChannelKey(url), () => <String>{})
            .add(url);
      }

      // Cheap pre-filter: a channel can only match a stored row on the same
      // host, and canonicalizing tens of thousands of URLs on the UI isolate
      // is not free.
      final storedHosts = <String>{
        for (final url in storedUrls)
          if (Uri.tryParse(url)?.host.isNotEmpty ?? false) Uri.parse(url).host,
      };

      // The scan yields to the event loop, so a concurrent add/remove can land
      // mid-flight. Changes are collected against locals only and applied in
      // one transaction that re-checks each source row — an entry removed
      // during the scan stays gone instead of being resurrected.
      final renames = <String, String>{}; // stored URL → current URL
      final meta = <String, ChannelPresentation>{};
      final chunk = Stopwatch()..start();
      for (final channel in channels) {
        if (storedByCanonical.isEmpty) break;
        if (chunk.elapsedMicroseconds >= _scanYieldBudget.inMicroseconds) {
          await Future<void>.delayed(Duration.zero);
          chunk.reset();
        }
        if (!storedHosts.any(channel.url.contains)) continue;
        // Consume the mapping so a second canonically-equal channel can't
        // re-move an already-migrated entry.
        final matched = storedByCanonical.remove(
          canonicalChannelKey(channel.url),
        );
        if (matched == null) continue;
        for (final storedUrl in matched) {
          if (storedUrl != channel.url) renames[storedUrl] = channel.url;
          if (needsMeta.contains(storedUrl)) {
            meta[storedUrl] = ChannelPresentation(
              contentType: channel.contentType,
              duration: channel.duration,
            );
          }
        }
      }
      return _applyReconcile(renames, meta, origin: origin);
    });
    if (!changed) return;
    _bumpListsRevision();
    if (origin == WebDavSyncMutationOrigin.user) {
      WebDavSyncLibraryMutation.notifyUserMutation();
    }
  }

  /// DB-catalog variant of [reconcileFavoriteUrls]: the fresh rows are read
  /// straight from the catalog on a WORKER isolate — walking a paging
  /// facade here would keep the scan's cost on the UI isolate, which is
  /// tens of near-saturated seconds on a big playlist.
  static Future<void> reconcileFavoriteUrlsForCatalog(
    String catalogKey, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    final changed = await _runScoped((db) async {
      if (!IptvCatalogDb.isOpen) return false;
      final urlRows = await db.rawQuery(
        'SELECT DISTINCT url FROM iptv_list_channels',
      );
      if (urlRows.isEmpty) return false;
      final needsMeta = await _urlsNeedingPresentation(db);

      final result = await compute(
        computeFavoriteRenamesJob,
        FavoriteRenameJob(
          dbPath: IptvCatalogDb.path,
          catalogKey: catalogKey,
          storedUrls: [for (final row in urlRows) row['url'] as String],
          urlsNeedingMeta: needsMeta.toList(),
        ),
      );
      if (result.isEmpty) return false;
      return _applyReconcile(result.renames, result.meta, origin: origin);
    });
    if (!changed) return;
    _bumpListsRevision();
    if (origin == WebDavSyncMutationOrigin.user) {
      WebDavSyncLibraryMutation.notifyUserMutation();
    }
  }

  /// Stored URLs whose presentation metadata is still unknown — rows carried
  /// over from the pre-v5 favorites table, which had no such columns.
  static Future<Set<String>> _urlsNeedingPresentation(
    DatabaseExecutor db,
  ) async {
    final rows = await db.rawQuery(
      'SELECT DISTINCT url FROM iptv_list_channels '
      'WHERE content_type IS NULL OR duration IS NULL',
    );
    return {for (final row in rows) row['url'] as String};
  }

  /// Apply stored-URL → current-URL renames and metadata backfill in one
  /// transaction that re-checks each source row — an entry removed while the
  /// scan ran stays gone instead of being resurrected. A renamed URL can
  /// appear in several lists, so every matching row moves, each keeping its
  /// own list_id.
  static Future<bool> _applyReconcile(
    Map<String, String> renames,
    Map<String, ChannelPresentation> meta, {
    required WebDavSyncMutationOrigin origin,
  }) async {
    // The empty short-circuit doubles as the revision guard: a reconcile
    // that changed nothing must not trigger list-row reloads elsewhere.
    if (renames.isEmpty && meta.isEmpty) return false;
    var changed = false;
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      int? sharedStamp;
      int stamp() => sharedStamp ??= _nextStampMs();
      // One preload plus one batch: a provider-wide URL migration can rename
      // hundreds of stored rows, and per-row awaited calls held the shared
      // database long enough to freeze every screen.
      final renamedRows = <Map<String, Object?>>[];
      final oldUrls = renames.keys.toList(growable: false);
      for (var start = 0; start < oldUrls.length; start += 500) {
        final chunk = oldUrls.sublist(
          start,
          start + 500 > oldUrls.length ? oldUrls.length : start + 500,
        );
        renamedRows.addAll(
          await txn.query(
            'iptv_list_channels',
            where:
                'url IN (${List.filled(chunk.length, '?').join(', ')})',
            whereArgs: chunk,
          ),
        );
      }
      final renameBatch = txn.batch();
      for (final existing in renamedRows) {
        final oldUrl = existing['url']! as String;
        final newUrl = renames[oldUrl];
        if (newUrl == null) continue;
        final row = Map<String, Object?>.from(existing);
        row['url'] = newUrl;
        final backfill = meta[oldUrl];
        if (backfill != null) {
          row['content_type'] ??= backfill.contentType;
          row['duration'] ??= backfill.duration;
        }
        renameBatch.delete(
          'iptv_list_channels',
          where: 'list_id = ? AND url = ?',
          whereArgs: [row['list_id'], oldUrl],
        );
        renameBatch.insert(
          'iptv_list_channels',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        changed = true;
        if (origin == WebDavSyncMutationOrigin.user) {
          final now = stamp();
          renameBatch.insert(
            'webdav_sync_record_state',
            _libraryStateRow(
              kind: WebDavSyncLibraryKinds.iptvListChannels,
              ownerKey: row['list_id']! as String,
              itemKey: oldUrl,
              updatedAtMs: now,
              deleted: true,
              origin: origin,
            ),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          renameBatch.insert(
            'webdav_sync_record_state',
            _libraryStateRow(
              kind: WebDavSyncLibraryKinds.iptvListChannels,
              ownerKey: row['list_id']! as String,
              itemKey: newUrl,
              updatedAtMs: now,
              deleted: false,
              origin: origin,
            ),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      if (changed) await renameBatch.commit(noResult: true);
      // Rows that kept their URL but still need presentation metadata.
      // COALESCE so a known value is never overwritten by a later scan.
      for (final entry in meta.entries) {
        if (renames.containsKey(entry.key)) continue;
        if (entry.value.isEmpty) continue;
        final predicates = <String>[];
        if (entry.value.contentType != null) {
          predicates.add('content_type IS NULL');
        }
        if (entry.value.duration != null) predicates.add('duration IS NULL');
        if (predicates.isEmpty) continue;
        final rows = await txn.query(
          'iptv_list_channels',
          columns: const <String>['list_id'],
          where: 'url = ? AND (${predicates.join(' OR ')})',
          whereArgs: <Object?>[entry.key],
        );
        if (rows.isEmpty) continue;
        final updated = await txn.rawUpdate(
          'UPDATE iptv_list_channels SET '
          'content_type = COALESCE(content_type, ?), '
          'duration = COALESCE(duration, ?) '
          'WHERE url = ? AND (${predicates.join(' OR ')})',
          [entry.value.contentType, entry.value.duration, entry.key],
        );
        if (updated == 0) continue;
        changed = true;
        if (origin == WebDavSyncMutationOrigin.user) {
          final now = stamp();
          for (final row in rows) {
            await _writeLibraryState(
              txn,
              kind: WebDavSyncLibraryKinds.iptvListChannels,
              ownerKey: row['list_id']! as String,
              itemKey: entry.key,
              updatedAtMs: now,
              deleted: false,
              origin: origin,
            );
          }
        }
      }
      if (changed && origin == WebDavSyncMutationOrigin.user) {
        await _bumpLibraryRevision(txn);
      }
    });
    return changed;
  }

  /// Add or remove [channelUrl] in [listId].
  static Future<void> setChannelInList(
    String listId,
    String channelUrl,
    bool inList, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    int? channelNumber,
    String? contentType,
    int? duration,
    Map<String, String>? httpHeaders,
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    var changed = false;
    await _runScoped((_) async {
      final canonical = canonicalChannelKey(channelUrl);
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        // Match older stored URL formats too, so toggling can't leave stale
        // duplicates behind. Scoped to this list: the same channel legitimately
        // belongs to several lists at once. A list holds dozens of rows, so
        // scanning its URLs inside the transaction is cheap.
        final rows = await txn.query(
          'iptv_list_channels',
          columns: ['url', 'position', 'added_at'],
          where: 'list_id = ?',
          whereArgs: [listId],
          orderBy: 'position ASC, added_at ASC, url ASC',
        );
        int? retainedPosition;
        int? retainedAddedAt;
        final removedUrls = <String>[];
        for (final row in rows) {
          final url = row['url'] as String;
          if (canonicalChannelKey(url) == canonical) {
            retainedPosition ??= (row['position'] as num?)?.toInt();
            retainedAddedAt ??= (row['added_at'] as num?)?.toInt();
            removedUrls.add(url);
            await txn.delete(
              'iptv_list_channels',
              where: 'list_id = ? AND url = ?',
              whereArgs: [listId, url],
            );
          }
        }
        changed = removedUrls.isNotEmpty || inList;
        if (inList) {
          if (retainedPosition == null) {
            final maxRows = await txn.rawQuery(
              'SELECT MAX(position) AS p FROM iptv_list_channels '
              'WHERE list_id = ?',
              [listId],
            );
            retainedPosition =
                ((maxRows.first['p'] as num?)?.toInt() ?? -1) + 1;
          }
          await txn.insert('iptv_list_channels', {
            'list_id': listId,
            'url': channelUrl,
            'name': channelName ?? '',
            'logo_url': logoUrl ?? '',
            'channel_group': group ?? '',
            'playlist_id': playlistId ?? '',
            'channel_number': channelNumber,
            // A list view rebuilds channels from this metadata alone (no
            // re-fetch), so anything playback or presentation depends on has to
            // be captured here: a channel needing a specific UA/Referer would
            // otherwise play from its playlist but not from the list, and one
            // without a content type would present as live and lose its
            // resume bar.
            'content_type': contentType,
            'duration': duration,
            'http_headers_json': (httpHeaders != null && httpHeaders.isNotEmpty)
                ? jsonEncode(httpHeaders)
                : null,
            'added_at':
                retainedAddedAt ?? DateTime.now().millisecondsSinceEpoch,
            'position': retainedPosition,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        if (changed && origin == WebDavSyncMutationOrigin.user) {
          final now = _nextStampMs();
          for (final url in removedUrls) {
            if (inList && url == channelUrl) continue;
            await _writeLibraryState(
              txn,
              kind: WebDavSyncLibraryKinds.iptvListChannels,
              ownerKey: listId,
              itemKey: url,
              updatedAtMs: now,
              deleted: true,
              origin: origin,
            );
          }
          if (inList) {
            await _writeLibraryState(
              txn,
              kind: WebDavSyncLibraryKinds.iptvListChannels,
              ownerKey: listId,
              itemKey: channelUrl,
              updatedAtMs: now,
              deleted: false,
              origin: origin,
            );
          }
          await _bumpLibraryRevision(txn);
        }
      });
    });
    if (!changed) return;
    _bumpListsRevision();
    if (origin == WebDavSyncMutationOrigin.user) {
      WebDavSyncLibraryMutation.notifyUserMutation();
    }
  }

  /// Which lists each stored channel belongs to, url → list ids.
  static Future<Map<String, Set<String>>> channelMembership() async {
    return (await membershipSnapshot()).membership;
  }

  /// Everything the page needs about stored channels in ONE read: which lists
  /// each belongs to, and which provider each membership came from. Separate
  /// queries would scan the same table twice on every catalog load.
  ///
  /// Origins are keyed by (list id, url), not url alone: the same channel can
  /// be saved into two lists from two different providers, and collapsing
  /// those would replay one of them under the other's credentials — and
  /// sweep it on the wrong provider's deletion.
  static Future<
    ({
      Map<String, Set<String>> membership,
      Map<(String, String), String> origins,
    })
  >
  membershipSnapshot() {
    return _runScoped((db) async {
      final rows = await db.query(
        'iptv_list_channels',
        columns: ['list_id', 'url', 'playlist_id'],
      );
      final membership = <String, Set<String>>{};
      final origins = <(String, String), String>{};
      for (final row in rows) {
        final url = row['url'] as String;
        final listId = row['list_id'] as String;
        membership.putIfAbsent(url, () => <String>{}).add(listId);
        origins[(listId, url)] = (row['playlist_id'] as String?) ?? '';
      }
      return (membership: membership, origins: origins);
    });
  }

  /// The lists [channelUrl] currently belongs to.
  static Future<Set<String>> listsForChannel(String channelUrl) {
    return _runScoped((db) async {
      final canonical = canonicalChannelKey(channelUrl);
      final rows = await db.query(
        'iptv_list_channels',
        columns: ['list_id', 'url'],
      );
      return {
        for (final row in rows)
          if (canonicalChannelKey(row['url'] as String) == canonical)
            row['list_id'] as String,
      };
    });
  }

  /// Drop every membership belonging to [playlistId], across ALL lists —
  /// the provider is gone, so its channels can't play from anywhere.
  static Future<void> removeListChannelsByPlaylistId(
    String playlistId, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    var changed = false;
    await _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        final rows = await txn.query(
          'iptv_list_channels',
          columns: const <String>['list_id', 'url'],
          where: 'playlist_id = ?',
          whereArgs: [playlistId],
        );
        if (rows.isEmpty) return;
        await txn.delete(
          'iptv_list_channels',
          where: 'playlist_id = ?',
          whereArgs: [playlistId],
        );
        changed = true;
        if (origin == WebDavSyncMutationOrigin.user) {
          final now = _nextStampMs();
          for (final row in rows) {
            await _writeLibraryState(
              txn,
              kind: WebDavSyncLibraryKinds.iptvListChannels,
              ownerKey: row['list_id']! as String,
              itemKey: row['url']! as String,
              updatedAtMs: now,
              deleted: true,
              origin: origin,
            );
          }
          await _bumpLibraryRevision(txn);
        }
      });
    });
    if (!changed) return;
    _bumpListsRevision();
    if (origin == WebDavSyncMutationOrigin.user) {
      WebDavSyncLibraryMutation.notifyUserMutation();
    }
  }

  /// One list's channels, url → metadata, in the same map shape the prefs
  /// store used ('name'/'logoUrl'/'group'/'playlistId'/'httpHeaders'/
  /// 'addedAt', plus 'contentType'/'duration'), in the user's saved order.
  static Future<Map<String, Map<String, dynamic>>> listChannels(String listId) {
    return _runScoped((db) async {
      final rows = await db.query(
        'iptv_list_channels',
        where: 'list_id = ?',
        whereArgs: [listId],
        orderBy: 'position ASC, added_at ASC, url ASC',
      );
      return {for (final row in rows) row['url'] as String: _favoriteMeta(row)};
    });
  }

  /// Reorder one list's channels. Rows added after the editor opened are
  /// appended, rows removed meanwhile are ignored, and duplicates in the
  /// request are collapsed — the save can never resurrect stale membership.
  static Future<void> reorderListChannels(
    String listId,
    Iterable<String> orderedUrls, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    var changed = false;
    await _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        final rows = await txn.query(
          'iptv_list_channels',
          columns: ['url', 'position'],
          where: 'list_id = ?',
          whereArgs: [listId],
          orderBy: 'position ASC, added_at ASC, url ASC',
        );
        final current = [for (final row in rows) row['url'] as String];
        final positions = <String, int>{
          for (final row in rows)
            row['url']! as String: (row['position'] as num).toInt(),
        };
        final currentSet = current.toSet();
        final seen = <String>{};
        final resolved = <String>[
          for (final url in orderedUrls)
            if (currentSet.contains(url) && seen.add(url)) url,
          for (final url in current)
            if (seen.add(url)) url,
        ];
        final moved = <(String, int)>[
          for (var position = 0; position < resolved.length; position++)
            if (positions[resolved[position]] != position)
              (resolved[position], position),
        ];
        if (moved.isEmpty) return;
        final now = origin == WebDavSyncMutationOrigin.user
            ? _nextStampMs()
            : DateTime.now().millisecondsSinceEpoch;
        // One batch commit: a large list reorder must not hold the shared
        // database for one awaited call per moved row.
        final batch = txn.batch();
        for (final item in moved) {
          batch.update(
            'iptv_list_channels',
            {'position': item.$2},
            where: 'list_id = ? AND url = ?',
            whereArgs: [listId, item.$1],
          );
          if (origin == WebDavSyncMutationOrigin.user) {
            batch.insert(
              'webdav_sync_record_state',
              _libraryStateRow(
                kind: WebDavSyncLibraryKinds.iptvListChannels,
                ownerKey: listId,
                itemKey: item.$1,
                updatedAtMs: now,
                deleted: false,
                origin: origin,
              ),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
        await batch.commit(noResult: true);
        changed = true;
        if (origin == WebDavSyncMutationOrigin.user) {
          await _bumpLibraryRevision(txn);
        }
      });
    });
    _bumpListsRevision();
    IptvChannelOrderSignal.notifyListChanged(listId);
    if (changed && origin == WebDavSyncMutationOrigin.user) {
      WebDavSyncLibraryMutation.notifyUserMutation();
    }
  }

  /// Imported-file category rows in their saved order. The parsed provider
  /// list remains the baseline, so rows unknown to an older saved order append
  /// deterministically after the ranked rows.
  static Future<List<IptvChannelOrderEntry>> categoryOrderEntries(
    String sourceId,
    Iterable<IptvChannel> channels,
    String group,
  ) {
    return _runScoped((db) async {
      final entries = iptvCategoryOrderEntries(channels, group);
      final rows = await db.query(
        'iptv_category_channel_orders',
        columns: ['url', 'name', 'occurrence', 'position'],
        where: 'source_id = ? AND channel_group = ?',
        whereArgs: [sourceId, group],
      );
      final ranks = <IptvChannelOrderIdentity, int>{
        for (final row in rows)
          IptvChannelOrderIdentity(
            url: row['url'] as String,
            name: row['name'] as String,
            occurrence: (row['occurrence'] as num).toInt(),
          ): (row['position'] as num)
              .toInt(),
      };
      final baseline = <IptvChannelOrderIdentity, int>{
        for (var i = 0; i < entries.length; i++) entries[i].identity: i,
      };
      entries.sort((a, b) {
        final ar = ranks[a.identity];
        final br = ranks[b.identity];
        if (ar != null && br != null) return ar.compareTo(br);
        if (ar != null) return -1;
        if (br != null) return 1;
        return baseline[a.identity]!.compareTo(baseline[b.identity]!);
      });
      return entries;
    });
  }

  static Future<void> setCategoryChannelOrder(
    String sourceId,
    String group,
    Iterable<IptvChannelOrderIdentity> ordered, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    final items = <IptvChannelOrderIdentity>[];
    final seen = <IptvChannelOrderIdentity>{};
    for (final item in ordered) {
      if (seen.add(item)) items.add(item);
    }
    await _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        await txn.delete(
          'iptv_category_channel_orders',
          where: 'source_id = ? AND channel_group = ?',
          whereArgs: [sourceId, group],
        );
        var position = 0;
        for (final identity in items) {
          await txn.insert('iptv_category_channel_orders', {
            'source_id': sourceId,
            'channel_group': group,
            'url': identity.url,
            'name': identity.name,
            'occurrence': identity.occurrence,
            'position': position++,
          });
        }
        if (origin == WebDavSyncMutationOrigin.user) {
          await _writeLibraryState(
            txn,
            kind: WebDavSyncLibraryKinds.iptvCategoryChannelOrders,
            ownerKey: sourceId,
            itemKey: group,
            updatedAtMs: _nextStampMs(),
            deleted: items.isEmpty,
            origin: origin,
          );
          await _bumpLibraryRevision(txn);
        }
      });
    });
    IptvChannelOrderSignal.notifySourceChanged(sourceId);
    if (origin == WebDavSyncMutationOrigin.user) {
      WebDavSyncLibraryMutation.notifyUserMutation();
    }
  }

  /// Apply every saved per-category order without moving category slots in
  /// the provider's overall sequence. This makes both All and category-filter
  /// views agree while leaving ungrouped channels untouched.
  static Future<List<IptvChannel>> applyCategoryChannelOrders(
    String sourceId,
    List<IptvChannel> channels,
  ) {
    return _runScoped((db) async {
      final rows = await db.query(
        'iptv_category_channel_orders',
        columns: ['channel_group', 'url', 'name', 'occurrence', 'position'],
        where: 'source_id = ?',
        whereArgs: [sourceId],
      );
      if (rows.isEmpty) return channels;
      final ranks = <(String, String, String, int), int>{
        for (final row in rows)
          (
            row['channel_group'] as String,
            row['url'] as String,
            row['name'] as String,
            (row['occurrence'] as num).toInt(),
          ): (row['position'] as num)
              .toInt(),
      };
      final orderedGroups = <String>{
        for (final row in rows) row['channel_group'] as String,
      };
      final occurrences = <(String, String, String), int>{};
      final baseline = <IptvChannel, int>{};
      final rankByChannel = <IptvChannel, int>{};
      final orderedByGroup = <String, List<IptvChannel>>{};
      for (var index = 0; index < channels.length; index++) {
        final channel = channels[index];
        final group = channel.group;
        if (group == null || !orderedGroups.contains(group)) continue;
        final base = iptvChannelOrderIdentityBaseFor(channel);
        final occurrenceKey = (group, base.url, base.name);
        final occurrence = occurrences[occurrenceKey] ?? 0;
        occurrences[occurrenceKey] = occurrence + 1;
        final rank = ranks[(group, base.url, base.name, occurrence)];
        baseline[channel] = index;
        if (rank != null) rankByChannel[channel] = rank;
        orderedByGroup.putIfAbsent(group, () => <IptvChannel>[]).add(channel);
      }
      for (final groupChannels in orderedByGroup.values) {
        groupChannels.sort((a, b) {
          final ar = rankByChannel[a];
          final br = rankByChannel[b];
          if (ar != null && br != null) return ar.compareTo(br);
          if (ar != null) return -1;
          if (br != null) return 1;
          return baseline[a]!.compareTo(baseline[b]!);
        });
      }
      final offsets = <String, int>{};
      return [
        for (final channel in channels)
          if (channel.group == null ||
              !orderedByGroup.containsKey(channel.group))
            channel
          else
            orderedByGroup[channel.group!]![offsets.update(
              channel.group!,
              (value) => value + 1,
              ifAbsent: () => 0,
            )],
      ];
    });
  }

  static Future<void> removeCategoryOrdersForSource(
    String sourceId, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    var changed = false;
    await _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        final physical = await txn.query(
          'iptv_category_channel_orders',
          columns: const <String>['channel_group'],
          where: 'source_id = ?',
          whereArgs: <Object?>[sourceId],
          distinct: true,
        );
        final state = origin == WebDavSyncMutationOrigin.user
            ? await txn.query(
                'webdav_sync_record_state',
                columns: const <String>['item_key'],
                where: 'kind = ? AND owner_key = ? AND deleted = 0',
                whereArgs: <Object?>[
                  WebDavSyncLibraryKinds.iptvCategoryChannelOrders,
                  sourceId,
                ],
              )
            : const <Map<String, Object?>>[];
        final groups = <String>{
          for (final row in physical) row['channel_group']! as String,
          for (final row in state) row['item_key']! as String,
        };
        await txn.delete(
          'iptv_category_channel_orders',
          where: 'source_id = ?',
          whereArgs: <Object?>[sourceId],
        );
        if (groups.isNotEmpty && origin == WebDavSyncMutationOrigin.user) {
          final now = _nextStampMs();
          for (final group in groups) {
            await _writeLibraryState(
              txn,
              kind: WebDavSyncLibraryKinds.iptvCategoryChannelOrders,
              ownerKey: sourceId,
              itemKey: group,
              updatedAtMs: now,
              deleted: true,
              origin: origin,
            );
          }
          await _bumpLibraryRevision(txn);
          changed = true;
        }
      });
    });
    if (changed) WebDavSyncLibraryMutation.notifyUserMutation();
  }

  // ── Favorites compatibility ───────────────────────────────────────────────
  // Favorites is now just the built-in list; these keep the older call sites
  // working unchanged.

  static Future<void> setChannelFavorited(
    String channelUrl,
    bool isFavorited, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    int? channelNumber,
    String? contentType,
    int? duration,
    Map<String, String>? httpHeaders,
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) {
    return setChannelInList(
      favoritesListId,
      channelUrl,
      isFavorited,
      channelName: channelName,
      logoUrl: logoUrl,
      group: group,
      playlistId: playlistId,
      channelNumber: channelNumber,
      contentType: contentType,
      duration: duration,
      httpHeaders: httpHeaders,
      origin: origin,
    );
  }

  /// Deleting a provider sweeps its channels out of EVERY list, not just
  /// Favorites — they have nowhere left to play from.
  static Future<void> removeFavoritesByPlaylistId(
    String playlistId, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) {
    return removeListChannelsByPlaylistId(playlistId, origin: origin);
  }

  static Future<Map<String, Map<String, dynamic>>> favoriteChannels() {
    return listChannels(favoritesListId);
  }

  // ── Watch history ─────────────────────────────────────────────────────────

  static Future<void> recordWatch(
    String channelUrl, {
    String? channelName,
    String? logoUrl,
    String? group,
    String? playlistId,
    Map<String, String>? httpHeaders,
    String? seriesId,
    String? seriesName,
    int? season,
    int? episode,
    bool? hasNextEpisode,
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    if (channelUrl.isEmpty) return Future<void>.value();
    await _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        final now = _nextStampMs();
        await txn.insert('iptv_watch_history', {
          'url': channelUrl,
          'name': channelName ?? '',
          'logo_url': logoUrl ?? '',
          'channel_group': group ?? '',
          'playlist_id': playlistId ?? '',
          'http_headers_json': (httpHeaders != null && httpHeaders.isNotEmpty)
              ? jsonEncode(httpHeaders)
              : null,
          'series_id': (seriesId != null && seriesId.isNotEmpty)
              ? seriesId
              : null,
          'series_name': (seriesName != null && seriesName.isNotEmpty)
              ? seriesName
              : null,
          'season': season,
          'episode': episode,
          'has_next': hasNextEpisode == null ? null : (hasNextEpisode ? 1 : 0),
          'last_played_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (origin == WebDavSyncMutationOrigin.user) {
          await _writeLibraryState(
            txn,
            kind: WebDavSyncLibraryKinds.iptvWatchHistory,
            ownerKey: playlistId ?? '',
            itemKey: channelUrl,
            updatedAtMs: now,
            deleted: false,
            origin: origin,
          );
          await _bumpLibraryRevision(txn);
        }
        await txn.execute(
          '''
          DELETE FROM iptv_watch_history
          WHERE url NOT IN (
            SELECT url FROM iptv_watch_history
            ORDER BY last_played_at DESC
            LIMIT ?
          )
          ''',
          [_watchHistoryMax],
        );
      });
    });
    if (origin == WebDavSyncMutationOrigin.user) {
      WebDavSyncLibraryMutation.notifyUserMutation(playbackCheckpoint: true);
    }
  }

  static Future<void> removeWatchHistoryByPlaylistId(
    String playlistId, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    var changed = false;
    await _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        final physical = await txn.query(
          'iptv_watch_history',
          columns: const <String>['url'],
          where: 'playlist_id = ?',
          whereArgs: <Object?>[playlistId],
        );
        final state = origin == WebDavSyncMutationOrigin.user
            ? await txn.query(
                'webdav_sync_record_state',
                columns: const <String>['item_key'],
                where: 'kind = ? AND owner_key = ? AND deleted = 0',
                whereArgs: <Object?>[
                  WebDavSyncLibraryKinds.iptvWatchHistory,
                  playlistId,
                ],
              )
            : const <Map<String, Object?>>[];
        final urls = <String>{
          for (final row in physical) row['url']! as String,
          for (final row in state) row['item_key']! as String,
        };
        await txn.delete(
          'iptv_watch_history',
          where: 'playlist_id = ?',
          whereArgs: [playlistId],
        );
        if (urls.isNotEmpty && origin == WebDavSyncMutationOrigin.user) {
          final now = _nextStampMs();
          for (final url in urls) {
            await _writeLibraryState(
              txn,
              kind: WebDavSyncLibraryKinds.iptvWatchHistory,
              ownerKey: playlistId,
              itemKey: url,
              updatedAtMs: now,
              deleted: true,
              origin: origin,
            );
          }
          await _bumpLibraryRevision(txn);
          changed = true;
        }
      });
    });
    if (changed) WebDavSyncLibraryMutation.notifyUserMutation();
  }

  /// Drop one on-demand item from Continue Watching: its history row AND its
  /// saved position. The shelf is a join of the two, so the history row alone
  /// would be enough to hide it — but the resume entry is what makes the
  /// removal stick (it still drives the progress bar wherever the item is
  /// listed, and a re-play would silently jump back into the middle).
  static Future<void> removeWatchEntry(
    String url, {
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    if (url.isEmpty) return Future<void>.value();
    var changed = false;
    await _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        final history = await txn.query(
          'iptv_watch_history',
          columns: const <String>['playlist_id'],
          where: 'url = ?',
          whereArgs: <Object?>[url],
          limit: 1,
        );
        final resumes = await txn.query(
          'video_resume',
          columns: const <String>['source_id'],
          where: 'resume_key = ?',
          whereArgs: <Object?>[url],
          limit: 1,
        );
        final historyStates = origin == WebDavSyncMutationOrigin.user
            ? await txn.query(
                'webdav_sync_record_state',
                columns: const <String>['owner_key'],
                where: 'kind = ? AND item_key = ? AND deleted = 0',
                whereArgs: <Object?>[
                  WebDavSyncLibraryKinds.iptvWatchHistory,
                  url,
                ],
              )
            : const <Map<String, Object?>>[];
        final resumeStates = origin == WebDavSyncMutationOrigin.user
            ? await txn.query(
                'webdav_sync_record_state',
                columns: const <String>['owner_key'],
                where: 'kind = ? AND item_key = ? AND deleted = 0',
                whereArgs: <Object?>[WebDavSyncLibraryKinds.videoResume, url],
              )
            : const <Map<String, Object?>>[];
        final historyOwners = <String>{
          for (final row in history) row['playlist_id']! as String,
          for (final row in historyStates) row['owner_key']! as String,
        };
        final resumeOwners = <String>{
          for (final row in resumes)
            ((row['source_id'] as String?)?.isNotEmpty == true)
                ? row['source_id']! as String
                : '_',
          for (final row in resumeStates) row['owner_key']! as String,
        };
        await txn.delete(
          'iptv_watch_history',
          where: 'url = ?',
          whereArgs: [url],
        );
        await txn.delete(
          'video_resume',
          where: 'resume_key = ?',
          whereArgs: [url],
        );
        if (origin == WebDavSyncMutationOrigin.user &&
            (historyOwners.isNotEmpty || resumeOwners.isNotEmpty)) {
          final now = _nextStampMs();
          for (final owner in historyOwners) {
            await _writeLibraryState(
              txn,
              kind: WebDavSyncLibraryKinds.iptvWatchHistory,
              ownerKey: owner,
              itemKey: url,
              updatedAtMs: now,
              deleted: true,
              origin: origin,
            );
          }
          for (final owner in resumeOwners) {
            await _writeLibraryState(
              txn,
              kind: WebDavSyncLibraryKinds.videoResume,
              ownerKey: owner,
              itemKey: url,
              updatedAtMs: now,
              deleted: true,
              origin: origin,
            );
          }
          await _bumpLibraryRevision(txn);
          changed = true;
        }
      });
    });
    if (changed) WebDavSyncLibraryMutation.notifyUserMutation();
  }

  /// The series counterpart of [removeWatchEntry]: a series shows as ONE
  /// Continue Watching card collapsed from all its watched episodes, so
  /// removing that card has to take every episode with it — otherwise the next
  /// most-recent episode simply re-materializes the card.
  static Future<void> removeWatchSeries({
    required String playlistId,
    required String seriesId,
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    if (seriesId.isEmpty) return Future<void>.value();
    var changed = false;
    await _runScoped((_) async {
      // Read the affected URLs and delete both tables in one transaction so
      // the plan cannot be derived from one profile and applied to another.
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        final rows = await txn.query(
          'iptv_watch_history',
          columns: ['url'],
          where: 'playlist_id = ? AND series_id = ?',
          whereArgs: [playlistId, seriesId],
        );
        final urls = [
          for (final row in rows)
            if (row['url'] is String) row['url'] as String,
        ];
        await txn.delete(
          'iptv_watch_history',
          where: 'playlist_id = ? AND series_id = ?',
          whereArgs: [playlistId, seriesId],
        );
        for (var i = 0; i < urls.length; i += _inChunkSize) {
          final chunk = urls.sublist(
            i,
            math.min(i + _inChunkSize, urls.length),
          );
          final placeholders = List.filled(chunk.length, '?').join(',');
          await txn.delete(
            'video_resume',
            where: 'resume_key IN ($placeholders)',
            whereArgs: chunk,
          );
        }
        if (urls.isNotEmpty && origin == WebDavSyncMutationOrigin.user) {
          final now = _nextStampMs();
          for (final url in urls) {
            await _writeLibraryState(
              txn,
              kind: WebDavSyncLibraryKinds.iptvWatchHistory,
              ownerKey: playlistId,
              itemKey: url,
              updatedAtMs: now,
              deleted: true,
              origin: origin,
            );
            final resumeState = await txn.query(
              'webdav_sync_record_state',
              columns: const <String>['owner_key'],
              where: 'kind = ? AND item_key = ?',
              whereArgs: <Object?>[WebDavSyncLibraryKinds.videoResume, url],
              limit: 1,
            );
            final resumeOwner = resumeState.isEmpty
                ? playlistId
                : resumeState.single['owner_key']! as String;
            await _writeLibraryState(
              txn,
              kind: WebDavSyncLibraryKinds.videoResume,
              ownerKey: resumeOwner,
              itemKey: url,
              updatedAtMs: now,
              deleted: true,
              origin: origin,
            );
          }
          await _bumpLibraryRevision(txn);
          changed = true;
        }
      });
    });
    if (changed) WebDavSyncLibraryMutation.notifyUserMutation();
  }

  /// All remembered on-demand items, url → metadata, oldest-played first.
  static Future<Map<String, Map<String, dynamic>>> watchHistory() {
    return _runScoped((db) async {
      final rows = await db.query(
        'iptv_watch_history',
        orderBy: 'last_played_at ASC, url ASC',
      );
      return {for (final row in rows) row['url'] as String: _historyMeta(row)};
    });
  }

  // ── Video resume ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> videoResume(String key) {
    return _runScoped((db) async {
      final rows = await db.query(
        'video_resume',
        where: 'resume_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _resumeMeta(rows.first);
    });
  }

  /// Persists the known resume fields
  /// (positionMs/durationMs/speed/aspect/updatedAt) for [key].
  static Future<void> upsertVideoResume(
    String key,
    Map<String, dynamic> entry, {
    String? sourceId,
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    await _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        var resolvedSourceId = sourceId;
        if (resolvedSourceId == null || resolvedSourceId.isEmpty) {
          final history = await txn.query(
            'iptv_watch_history',
            columns: const <String>['playlist_id'],
            where: 'url = ?',
            whereArgs: <Object?>[key],
            limit: 1,
          );
          if (history.isNotEmpty) {
            resolvedSourceId = history.single['playlist_id'] as String?;
          } else {
            final prior = await txn.query(
              'video_resume',
              columns: const <String>['source_id'],
              where: 'resume_key = ?',
              whereArgs: <Object?>[key],
              limit: 1,
            );
            if (prior.isNotEmpty) {
              resolvedSourceId = prior.single['source_id'] as String?;
            }
          }
        }
        await txn.insert(
          'video_resume',
          _resumeRow(key, entry, sourceId: resolvedSourceId),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (origin == WebDavSyncMutationOrigin.user) {
          await _writeLibraryState(
            txn,
            kind: WebDavSyncLibraryKinds.videoResume,
            ownerKey: (resolvedSourceId == null || resolvedSourceId.isEmpty)
                ? '_'
                : resolvedSourceId,
            itemKey: key,
            updatedAtMs: _nextStampMs(),
            deleted: false,
            origin: origin,
          );
          await _bumpLibraryRevision(txn);
        }
      });
    });
    if (origin == WebDavSyncMutationOrigin.user) {
      WebDavSyncLibraryMutation.notifyUserMutation(playbackCheckpoint: true);
    }
  }

  /// Removes the resume entry for one media item without touching the rest of
  /// the user's IPTV/on-demand playback history.
  static Future<void> removeVideoResume(
    String key, {
    bool playbackCheckpoint = false,
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    if (key.isEmpty) return Future<void>.value();
    var changed = false;
    await _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        final rows = await txn.query(
          'video_resume',
          columns: const <String>['source_id'],
          where: 'resume_key = ?',
          whereArgs: <Object?>[key],
          limit: 1,
        );
        final states = origin == WebDavSyncMutationOrigin.user
            ? await txn.query(
                'webdav_sync_record_state',
                columns: const <String>['owner_key'],
                where: 'kind = ? AND item_key = ? AND deleted = 0',
                whereArgs: <Object?>[WebDavSyncLibraryKinds.videoResume, key],
              )
            : const <Map<String, Object?>>[];
        final owners = <String>{
          for (final row in rows)
            ((row['source_id'] as String?)?.isNotEmpty == true)
                ? row['source_id']! as String
                : '_',
          for (final row in states) row['owner_key']! as String,
        };
        await txn.delete(
          'video_resume',
          where: 'resume_key = ?',
          whereArgs: [key],
        );
        if (owners.isNotEmpty && origin == WebDavSyncMutationOrigin.user) {
          final now = _nextStampMs();
          for (final owner in owners) {
            await _writeLibraryState(
              txn,
              kind: WebDavSyncLibraryKinds.videoResume,
              ownerKey: owner,
              itemKey: key,
              updatedAtMs: now,
              deleted: true,
              origin: origin,
            );
          }
          await _bumpLibraryRevision(txn);
          changed = true;
        }
      });
    });
    if (changed) WebDavSyncLibraryMutation.notifyUserMutation(playbackCheckpoint: playbackCheckpoint);
  }

  /// Stored resume entries for whichever of [keys] exist. Batched `IN`
  /// lookups — callers pass up to thousands of playlist URLs.
  static Future<Map<String, Map<String, dynamic>>> resumeEntries(
    Iterable<String> keys,
  ) {
    final wanted = keys.where((k) => k.isNotEmpty).toSet().toList();
    if (wanted.isEmpty) {
      return Future<Map<String, Map<String, dynamic>>>.value({});
    }
    return _runScoped((db) async {
      final result = <String, Map<String, dynamic>>{};
      for (var i = 0; i < wanted.length; i += _inChunkSize) {
        final chunk = wanted.sublist(
          i,
          math.min(i + _inChunkSize, wanted.length),
        );
        final placeholders = List.filled(chunk.length, '?').join(',');
        final rows = await db.query(
          'video_resume',
          where: 'resume_key IN ($placeholders)',
          whereArgs: chunk,
        );
        for (final row in rows) {
          result[row['resume_key'] as String] = _resumeMeta(row);
        }
      }
      return result;
    });
  }

  static Future<void> clearVideoResume({
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) async {
    var changed = false;
    await _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        final rows = await txn.query(
          'video_resume',
          columns: const <String>['resume_key', 'source_id'],
        );
        final states = origin == WebDavSyncMutationOrigin.user
            ? await txn.query(
                'webdav_sync_record_state',
                columns: const <String>['owner_key', 'item_key'],
                where: 'kind = ? AND deleted = 0',
                whereArgs: const <Object?>[WebDavSyncLibraryKinds.videoResume],
              )
            : const <Map<String, Object?>>[];
        final targets = <(String, String)>{
          for (final row in rows)
            (
              ((row['source_id'] as String?)?.isNotEmpty == true)
                  ? row['source_id']! as String
                  : '_',
              row['resume_key']! as String,
            ),
          for (final row in states)
            (row['owner_key']! as String, row['item_key']! as String),
        };
        await txn.delete('video_resume');
        if (origin != WebDavSyncMutationOrigin.user) {
          // A silent wipe takes its live stamps with it, exactly like the
          // physical rows: a retained exact stamp would otherwise stop the
          // circle's untouched resume records from re-materializing here.
          // Tombstones stay — they are published intent, not row provenance.
          await txn.delete(
            'webdav_sync_record_state',
            where: 'kind = ? AND deleted = 0',
            whereArgs: const <Object?>[WebDavSyncLibraryKinds.videoResume],
          );
        }
        if (targets.isNotEmpty && origin == WebDavSyncMutationOrigin.user) {
          final now = _nextStampMs();
          for (final target in targets) {
            await _writeLibraryState(
              txn,
              kind: WebDavSyncLibraryKinds.videoResume,
              ownerKey: target.$1,
              itemKey: target.$2,
              updatedAtMs: now,
              deleted: true,
              origin: origin,
            );
          }
          await _bumpLibraryRevision(txn);
          changed = true;
        }
      });
    });
    if (changed) WebDavSyncLibraryMutation.notifyUserMutation();
  }

  // ── Row/meta mapping ──────────────────────────────────────────────────────

  static Map<String, Object?> _favoriteRowFromLegacy(String url, Object? meta) {
    final map = meta is Map ? meta : const <String, dynamic>{};
    return {
      'list_id': favoritesListId,
      'url': url,
      'name': map['name']?.toString() ?? '',
      'logo_url': map['logoUrl']?.toString() ?? '',
      'channel_group': map['group']?.toString() ?? '',
      'playlist_id': map['playlistId']?.toString() ?? '',
      'channel_number': (map['channelNumber'] as num?)?.toInt(),
      'http_headers_json': _headersJson(map['httpHeaders']),
      'added_at': (map['addedAt'] as num?)?.toInt() ?? 0,
    };
  }

  static Map<String, Object?> _historyRowFromLegacy(String url, Object? meta) {
    final map = meta is Map ? meta : const <String, dynamic>{};
    final seriesId = map['seriesId']?.toString();
    final seriesName = map['seriesName']?.toString();
    final hasNext = map['hasNext'];
    return {
      'url': url,
      'name': map['name']?.toString() ?? '',
      'logo_url': map['logoUrl']?.toString() ?? '',
      'channel_group': map['group']?.toString() ?? '',
      'playlist_id': map['playlistId']?.toString() ?? '',
      'http_headers_json': _headersJson(map['httpHeaders']),
      'series_id': (seriesId != null && seriesId.isNotEmpty) ? seriesId : null,
      'series_name': (seriesName != null && seriesName.isNotEmpty)
          ? seriesName
          : null,
      'season': (map['season'] as num?)?.toInt(),
      'episode': (map['episode'] as num?)?.toInt(),
      'has_next': hasNext is bool ? (hasNext ? 1 : 0) : null,
      'last_played_at': (map['lastPlayedAt'] as num?)?.toInt() ?? 0,
    };
  }

  static String? _headersJson(Object? raw) {
    if (raw is! Map || raw.isEmpty) return null;
    final headers = <String, String>{};
    raw.forEach((key, value) {
      if (key is String && value != null) headers[key] = value.toString();
    });
    return headers.isEmpty ? null : jsonEncode(headers);
  }

  static Map<String, String>? _decodeHeaders(Object? json) {
    if (json is! String || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {}
    return null;
  }

  static Map<String, dynamic> _favoriteMeta(Map<String, Object?> row) {
    final headers = _decodeHeaders(row['http_headers_json']);
    return {
      'name': row['name'] ?? '',
      'logoUrl': row['logo_url'] ?? '',
      'group': row['channel_group'] ?? '',
      'playlistId': row['playlist_id'] ?? '',
      if (row['channel_number'] != null)
        'channelNumber': (row['channel_number'] as num).toInt(),
      // Absent on rows migrated from the pre-v5 favorites table until the
      // reconcile pass backfills them; consumers fall back to the old
      // live-by-default reading, which is what those rows did before.
      if (row['content_type'] != null)
        'contentType': row['content_type'] as String,
      if (row['duration'] != null) 'duration': (row['duration'] as num).toInt(),
      if (headers != null) 'httpHeaders': headers,
      'addedAt': (row['added_at'] as num?)?.toInt() ?? 0,
    };
  }

  static Map<String, dynamic> _historyMeta(Map<String, Object?> row) {
    final headers = _decodeHeaders(row['http_headers_json']);
    final seriesId = row['series_id'];
    final seriesName = row['series_name'];
    final season = row['season'];
    final episode = row['episode'];
    final hasNext = row['has_next'];
    return {
      'name': row['name'] ?? '',
      'logoUrl': row['logo_url'] ?? '',
      'group': row['channel_group'] ?? '',
      'playlistId': row['playlist_id'] ?? '',
      if (headers != null) 'httpHeaders': headers,
      if (seriesId is String && seriesId.isNotEmpty) 'seriesId': seriesId,
      if (seriesName is String && seriesName.isNotEmpty)
        'seriesName': seriesName,
      if (season is num) 'season': season.toInt(),
      if (episode is num) 'episode': episode.toInt(),
      if (hasNext is num) 'hasNext': hasNext != 0,
      'lastPlayedAt': (row['last_played_at'] as num?)?.toInt() ?? 0,
    };
  }

  static Map<String, Object?> _resumeRow(
    String key,
    Map<String, dynamic> entry, {
    String? sourceId,
  }) {
    return {
      'resume_key': key,
      'source_id': (sourceId == null || sourceId.isEmpty) ? null : sourceId,
      'position_ms': (entry['positionMs'] as num?)?.toInt() ?? 0,
      'duration_ms': (entry['durationMs'] as num?)?.toInt() ?? 0,
      'speed': (entry['speed'] as num?)?.toDouble() ?? 1.0,
      'aspect': entry['aspect']?.toString() ?? 'contain',
      'updated_at': (entry['updatedAt'] as num?)?.toInt() ?? 0,
    };
  }

  static Map<String, dynamic> _resumeMeta(Map<String, Object?> row) {
    final updatedAt = (row['updated_at'] as num?)?.toInt() ?? 0;
    return {
      'positionMs': (row['position_ms'] as num?)?.toInt() ?? 0,
      'durationMs': (row['duration_ms'] as num?)?.toInt() ?? 0,
      'speed': (row['speed'] as num?)?.toDouble() ?? 1.0,
      'aspect': row['aspect']?.toString() ?? 'contain',
      // 0 means the legacy entry never carried a timestamp; omit the key so
      // Continue Watching's fallback to the watch-history timestamp still
      // fires instead of sorting the item to 1970.
      if (updatedAt != 0) 'updatedAt': updatedAt,
    };
  }

  static Map<String, Object?> _libraryStateRow({
    required String kind,
    required String ownerKey,
    required String itemKey,
    required int updatedAtMs,
    required bool deleted,
    required WebDavSyncMutationOrigin origin,
  }) => <String, Object?>{
    'kind': kind,
    'owner_key': ownerKey,
    'item_key': itemKey,
    'updated_at_ms': updatedAtMs,
    'origin_device_id': origin == WebDavSyncMutationOrigin.user
        ? WebDavSyncLibraryMutation.originDeviceId
        : origin.name,
    'normalized': 0,
    'deleted': deleted ? 1 : 0,
    'aux': null,
  };

  static Future<void> _writeLibraryState(
    DatabaseExecutor db, {
    required String kind,
    required String ownerKey,
    required String itemKey,
    required int updatedAtMs,
    required bool deleted,
    required WebDavSyncMutationOrigin origin,
  }) {
    return db.insert(
      'webdav_sync_record_state',
      _libraryStateRow(
        kind: kind,
        ownerKey: ownerKey,
        itemKey: itemKey,
        updatedAtMs: updatedAtMs,
        deleted: deleted,
        origin: origin,
      ),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> _bumpLibraryRevision(DatabaseExecutor db) {
    return db.execute('''
      UPDATE webdav_sync_meta
      SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT)
      WHERE key = 'mutation_revision'
    ''');
  }
}

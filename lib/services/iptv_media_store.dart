import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/iptv_playlist.dart';
import '../utils/json_isolate.dart';
import 'debrify_tv_database.dart';
import 'iptv_catalog_db.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_runtime.dart';

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

  static void _bumpListsRevision() => listsRevision.value++;

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

    final favoritesRaw = prefs.getString(_legacyFavoritesKey);
    if (favoritesRaw != null) {
      final favorites = await _decodeLegacyMap(favoritesRaw);
      await db.runTxn((txn) async {
        // A very old install can reach v5 with the prefs blob still present,
        // so the import lands straight in the built-in Favorites list.
        await DebrifyTvDatabase.seedBuiltinList(txn);
        for (final entry in favorites.entries) {
          await txn.insert(
            'iptv_list_channels',
            _favoriteRowFromLegacy(entry.key, entry.value),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      await prefs.remove(_legacyFavoritesKey);
    }

    final historyRaw = prefs.getString(_legacyWatchHistoryKey);
    if (historyRaw != null) {
      final history = await _decodeLegacyMap(historyRaw);
      await db.runTxn((txn) async {
        for (final entry in history.entries) {
          await txn.insert(
            'iptv_watch_history',
            _historyRowFromLegacy(entry.key, entry.value),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      await prefs.remove(_legacyWatchHistoryKey);
    }

    final resumeRaw = prefs.getString(_legacyVideoResumeKey);
    if (resumeRaw != null) {
      final resume = await _decodeLegacyMap(resumeRaw);
      await db.runTxn((txn) async {
        for (final entry in resume.entries) {
          final value = entry.value;
          if (value is! Map) continue;
          await txn.insert(
            'video_resume',
            _resumeRow(entry.key, Map<String, dynamic>.from(value)),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      await prefs.remove(_legacyVideoResumeKey);
    }
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
  static Future<String> createList(String name) {
    return _runScoped((_) async {
      final trimmed = name.trim();
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = 'list_${now}_${math.Random().nextInt(1 << 20)}';
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
      });
      _bumpListsRevision();
      return id;
    });
  }

  /// Rename a custom list. The built-in Favorites list is not renameable.
  static Future<void> renameList(String listId, String name) {
    if (listId == favoritesListId) return Future<void>.value();
    return _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        await txn.update(
          'iptv_lists',
          {
            'name': name.trim(),
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ? AND is_builtin = 0',
          whereArgs: [listId],
        );
      });
      _bumpListsRevision();
    });
  }

  /// Delete a custom list. Memberships go with it via ON DELETE CASCADE —
  /// the channels themselves are untouched, they just stop being in a list.
  static Future<void> deleteList(String listId) {
    if (listId == favoritesListId) return Future<void>.value();
    return _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        await txn.delete(
          'iptv_lists',
          where: 'id = ? AND is_builtin = 0',
          whereArgs: [listId],
        );
      });
      _bumpListsRevision();
    });
  }

  /// Reorder custom lists. Favorites is pinned at position 0 and ignored
  /// here; everything named in [orderedIds] takes 1..n in that order.
  static Future<void> reorderLists(List<String> orderedIds) {
    return _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        var position = 1;
        for (final id in orderedIds) {
          if (id == favoritesListId) continue;
          await txn.update(
            'iptv_lists',
            {'position': position},
            where: 'id = ? AND is_builtin = 0',
            whereArgs: [id],
          );
          position += 1;
        }
      });
      _bumpListsRevision();
    });
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
  static Future<void> reconcileFavoriteUrls(List<IptvChannel> channels) {
    return _runScoped((db) async {
      final urlRows = await db.rawQuery(
        'SELECT DISTINCT url FROM iptv_list_channels',
      );
      if (urlRows.isEmpty) return;
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
      await _applyReconcile(renames, meta);
    });
  }

  /// DB-catalog variant of [reconcileFavoriteUrls]: the fresh rows are read
  /// straight from the catalog on a WORKER isolate — walking a paging
  /// facade here would keep the scan's cost on the UI isolate, which is
  /// tens of near-saturated seconds on a big playlist.
  static Future<void> reconcileFavoriteUrlsForCatalog(String catalogKey) {
    return _runScoped((db) async {
      if (!IptvCatalogDb.isOpen) return;
      final urlRows = await db.rawQuery(
        'SELECT DISTINCT url FROM iptv_list_channels',
      );
      if (urlRows.isEmpty) return;
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
      if (result.isEmpty) return;
      await _applyReconcile(result.renames, result.meta);
    });
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
  static Future<void> _applyReconcile(
    Map<String, String> renames,
    Map<String, ChannelPresentation> meta,
  ) async {
    // The empty short-circuit doubles as the revision guard: a reconcile
    // that changed nothing must not trigger list-row reloads elsewhere.
    if (renames.isEmpty && meta.isEmpty) return;
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      for (final entry in renames.entries) {
        final rows = await txn.query(
          'iptv_list_channels',
          where: 'url = ?',
          whereArgs: [entry.key],
        );
        if (rows.isEmpty) continue; // removed during the scan
        final backfill = meta[entry.key];
        for (final existing in rows) {
          final row = Map<String, Object?>.from(existing);
          row['url'] = entry.value;
          if (backfill != null) {
            row['content_type'] ??= backfill.contentType;
            row['duration'] ??= backfill.duration;
          }
          await txn.delete(
            'iptv_list_channels',
            where: 'list_id = ? AND url = ?',
            whereArgs: [row['list_id'], entry.key],
          );
          await txn.insert(
            'iptv_list_channels',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      // Rows that kept their URL but still need presentation metadata.
      // COALESCE so a known value is never overwritten by a later scan.
      for (final entry in meta.entries) {
        if (renames.containsKey(entry.key)) continue;
        if (entry.value.isEmpty) continue;
        await txn.rawUpdate(
          'UPDATE iptv_list_channels SET '
          'content_type = COALESCE(content_type, ?), '
          'duration = COALESCE(duration, ?) '
          'WHERE url = ? AND (content_type IS NULL OR duration IS NULL)',
          [entry.value.contentType, entry.value.duration, entry.key],
        );
      }
    });
    _bumpListsRevision();
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
  }) {
    return _runScoped((_) async {
      final canonical = canonicalChannelKey(channelUrl);
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        // Match older stored URL formats too, so toggling can't leave stale
        // duplicates behind. Scoped to this list: the same channel legitimately
        // belongs to several lists at once. A list holds dozens of rows, so
        // scanning its URLs inside the transaction is cheap.
        final rows = await txn.query(
          'iptv_list_channels',
          columns: ['url'],
          where: 'list_id = ?',
          whereArgs: [listId],
        );
        for (final row in rows) {
          final url = row['url'] as String;
          if (canonicalChannelKey(url) == canonical) {
            await txn.delete(
              'iptv_list_channels',
              where: 'list_id = ? AND url = ?',
              whereArgs: [listId, url],
            );
          }
        }
        if (inList) {
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
            'added_at': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      _bumpListsRevision();
    });
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
  static Future<void> removeListChannelsByPlaylistId(String playlistId) {
    return _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        await txn.delete(
          'iptv_list_channels',
          where: 'playlist_id = ?',
          whereArgs: [playlistId],
        );
      });
      _bumpListsRevision();
    });
  }

  /// One list's channels, url → metadata, in the same map shape the prefs
  /// store used ('name'/'logoUrl'/'group'/'playlistId'/'httpHeaders'/
  /// 'addedAt', plus 'contentType'/'duration'), oldest-added first.
  static Future<Map<String, Map<String, dynamic>>> listChannels(String listId) {
    return _runScoped((db) async {
      final rows = await db.query(
        'iptv_list_channels',
        where: 'list_id = ?',
        whereArgs: [listId],
        orderBy: 'added_at ASC, url ASC',
      );
      return {for (final row in rows) row['url'] as String: _favoriteMeta(row)};
    });
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
    );
  }

  /// Deleting a provider sweeps its channels out of EVERY list, not just
  /// Favorites — they have nowhere left to play from.
  static Future<void> removeFavoritesByPlaylistId(String playlistId) {
    return removeListChannelsByPlaylistId(playlistId);
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
  }) {
    if (channelUrl.isEmpty) return Future<void>.value();
    return _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
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
          'last_played_at': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
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
  }

  static Future<void> removeWatchHistoryByPlaylistId(String playlistId) {
    return _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        await txn.delete(
          'iptv_watch_history',
          where: 'playlist_id = ?',
          whereArgs: [playlistId],
        );
      });
    });
  }

  /// Drop one on-demand item from Continue Watching: its history row AND its
  /// saved position. The shelf is a join of the two, so the history row alone
  /// would be enough to hide it — but the resume entry is what makes the
  /// removal stick (it still drives the progress bar wherever the item is
  /// listed, and a re-play would silently jump back into the middle).
  static Future<void> removeWatchEntry(String url) {
    if (url.isEmpty) return Future<void>.value();
    return _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
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
      });
    });
  }

  /// The series counterpart of [removeWatchEntry]: a series shows as ONE
  /// Continue Watching card collapsed from all its watched episodes, so
  /// removing that card has to take every episode with it — otherwise the next
  /// most-recent episode simply re-materializes the card.
  static Future<void> removeWatchSeries({
    required String playlistId,
    required String seriesId,
  }) {
    if (seriesId.isEmpty) return Future<void>.value();
    return _runScoped((_) async {
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
      });
    });
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
    Map<String, dynamic> entry,
  ) {
    return _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        await txn.insert(
          'video_resume',
          _resumeRow(key, entry),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    });
  }

  /// Removes the resume entry for one media item without touching the rest of
  /// the user's IPTV/on-demand playback history.
  static Future<void> removeVideoResume(String key) {
    if (key.isEmpty) return Future<void>.value();
    return _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        await txn.delete(
          'video_resume',
          where: 'resume_key = ?',
          whereArgs: [key],
        );
      });
    });
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

  static Future<void> clearVideoResume() {
    return _runScoped((_) async {
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        await txn.delete('video_resume');
      });
    });
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
    Map<String, dynamic> entry,
  ) {
    return {
      'resume_key': key,
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
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:synchronized/synchronized.dart';

import 'profiles/profile_storage_paths.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_scope.dart';
import 'profiles/profile_database_adoption_gate.dart';
import 'webdav_sync/webdav_sync_circle_models.dart';
import 'webdav_sync/webdav_sync_hot_models.dart';
import 'webdav_sync/webdav_sync_library_models.dart';
import 'webdav_sync/webdav_sync_library_mutation.dart';

typedef _DatabaseScope = ({String key, ProfileScope? scope});

class DebrifyTvDatabase {
  DebrifyTvDatabase._();

  static final DebrifyTvDatabase instance = DebrifyTvDatabase._();
  static const String webDavTvChangesPendingMetaKey = 'tvChangesPending';
  static const String webDavTvPendingRevisionMetaKey = 'tvPendingRevision';
  static const String webDavTvLastSyncedMsMetaKey = 'tvLastSyncedMs';

  /// Tests inject an in-memory database here (sqflite_common_ffi) so store
  /// logic runs against the real schema without path_provider.
  @visibleForTesting
  static Database? debugDatabaseOverride;

  /// Pauses an opened handle before it can become process-global. Race tests
  /// use this to put profile deactivation precisely inside the open window.
  @visibleForTesting
  static Future<void> Function(String scopeKey)? debugBeforeOpenPublish;

  Database? _db;
  String? _dbScopeKey;
  String? _openingScopeKey;
  final Set<String> _deactivatedScopeKeys = <String>{};
  final Lock _scopeLock = Lock();
  final Object _operationZoneKey = Object();
  int _activeOperations = 0;
  Completer<void>? _operationsDrained;

  /// Exposes a handle only for lifecycle tests and schema maintenance.
  /// Production reads must use [runScoped] so [closeScope] cannot close the
  /// handle while an operation is using it.
  @visibleForTesting
  Future<Database> get database async {
    final active = Zone.current[_operationZoneKey] as Database?;
    if (active != null) return active;
    await ProfileDatabaseAdoptionGate.waitUntilReleased();
    final override = debugDatabaseOverride;
    if (override != null) return override;
    final requested = _requestedScope();
    if (_deactivatedScopeKeys.contains(requested.key)) {
      throw StateError('Debrify TV database scope is deactivated');
    }
    final opened = _db;
    if (opened != null && _dbScopeKey == requested.key) {
      return opened;
    }
    return _scopeLock.synchronized(() => _databaseLocked(requested));
  }

  @visibleForTesting
  bool get debugInOperationZone => Zone.current[_operationZoneKey] is Database;

  Future<Database> _databaseLocked(_DatabaseScope requested) async {
    if (_deactivatedScopeKeys.contains(requested.key)) {
      throw StateError('Debrify TV database scope changed while opening');
    }

    final existing = _db;
    if (existing != null) {
      if (_dbScopeKey == requested.key) return existing;
      // A stale handle must never be silently adopted by the next profile.
      _db = null;
      _dbScopeKey = null;
      await existing.close();
    }

    _openingScopeKey = requested.key;
    try {
      return await _openAndPublishDatabase(requested);
    } finally {
      if (_openingScopeKey == requested.key) _openingScopeKey = null;
    }
  }

  Future<Database> _openAndPublishDatabase(_DatabaseScope requested) async {
    final dbPath = requested.scope == null
        ? await ProfileStoragePaths.documentsFile('debrify_tv.db')
        : await ProfileRuntime.withCapturedScope(
            requested.scope!,
            () => ProfileStoragePaths.documentsFile('debrify_tv.db'),
          );

    final opened = await _openAtPath(dbPath);

    // Ensure index exists for fresh creates (onCreate already runs for v2 DB)
    await opened.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_tv_channels_channel_number ON tv_channels(channel_number)',
    );
    await debugBeforeOpenPublish?.call(requested.key);

    // closeScope marks the authoritative owner and any in-flight captured
    // scope synchronously, before it waits for this lock. Captured staging
    // scopes are valid, but a deactivated session can never publish late.
    if (_deactivatedScopeKeys.contains(requested.key)) {
      await opened.close();
      throw StateError('Debrify TV database scope changed while opening');
    }

    _db = opened;
    _dbScopeKey = requested.key;
    return opened;
  }

  Future<void> closeScope([ProfileScope? deactivatingScope]) async {
    final owner = deactivatingScope == null
        ? (ProfileRuntime.isInitialized ? _requestedScope() : null)
        : _scopeOf(deactivatingScope);
    // Set this before awaiting the lock: callers arriving while an open or
    // transaction drains must be denied, not queued to reopen the old scope.
    if (owner != null) _deactivatedScopeKeys.add(owner.key);
    final opening = _openingScopeKey;
    if (opening != null) _deactivatedScopeKeys.add(opening);
    final openedScope = _dbScopeKey;
    if (openedScope != null) _deactivatedScopeKeys.add(openedScope);
    while (true) {
      final drain = await _scopeLock.synchronized<Completer<void>?>(() async {
        if (_activeOperations > 0) {
          return _operationsDrained ??= Completer<void>();
        }
        final opened = _db;
        _db = null;
        _dbScopeKey = null;
        if (opened != null) await opened.close();
        return null;
      });
      if (drain == null) return;
      await drain.future;
    }
  }

  /// Re-enables the authoritative scope after a failed switch rolls back to
  /// it. Successful switches naturally have a different scope key, but call
  /// this too so the lifecycle contract stays explicit.
  void activateScope(ProfileScope scope) {
    if (ProfileRuntime.scope.value != scope) {
      throw StateError('Cannot activate a non-authoritative database scope');
    }
    final key = _scopeOf(scope).key;
    _deactivatedScopeKeys.remove(key);
  }

  /// Runs one complete logical operation against the scope captured at
  /// admission. Operations may overlap, but profile deactivation waits for
  /// every admitted operation to drain before closing the handle. Nested
  /// calls reuse the captured handle so an await can never redirect the
  /// second half of a read/modify/write operation into a newer profile.
  Future<T> runScoped<T>(Future<T> Function(Database db) action) async {
    final active = Zone.current[_operationZoneKey] as Database?;
    if (active != null) return action(active);

    await ProfileDatabaseAdoptionGate.waitUntilReleased();
    final override = debugDatabaseOverride;
    if (override != null) {
      return runZoned(
        () => action(override),
        zoneValues: <Object, Object>{_operationZoneKey: override},
      );
    }
    final requested = _requestedScope();
    late final Database admitted;
    await _scopeLock.synchronized(() async {
      admitted = await _databaseLocked(requested);
      _activeOperations += 1;
    });
    try {
      return await runZoned(
        () => action(admitted),
        zoneValues: <Object, Object>{_operationZoneKey: admitted},
      );
    } finally {
      await _scopeLock.synchronized(() {
        _activeOperations -= 1;
        if (_activeOperations == 0) {
          final drained = _operationsDrained;
          _operationsDrained = null;
          if (drained != null && !drained.isCompleted) drained.complete();
        }
      });
    }
  }

  Future<T> runTxn<T>(Future<T> Function(Transaction txn) action) {
    return runScoped((db) => db.transaction(action, exclusive: false));
  }

  /// Marks a user-authored Debrify TV change in the same transaction as its
  /// sidecar stamp. This marker deliberately has no scheduler callback.
  static Future<void> markWebDavTvChangesPending(DatabaseExecutor db) async {
    await db.execute(
      'UPDATE webdav_sync_meta SET value = ? WHERE key = ?',
      <Object?>['1', webDavTvChangesPendingMetaKey],
    );
    await db.execute('''
      UPDATE webdav_sync_meta
      SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT)
      WHERE key = '$webDavTvPendingRevisionMetaKey'
    ''');
  }

  Future<WebDavSyncTvSyncMetadata> readWebDavTvSyncMetadata() => runScoped((
    db,
  ) async {
    final rows = await db.query(
      'webdav_sync_meta',
      columns: const <String>['key', 'value'],
      where: 'key IN (?, ?, ?)',
      whereArgs: const <Object>[
        webDavTvChangesPendingMetaKey,
        webDavTvPendingRevisionMetaKey,
        webDavTvLastSyncedMsMetaKey,
      ],
    );
    final values = <String, String>{
      for (final row in rows) row['key']! as String: row['value']! as String,
    };
    final pendingRevision = int.tryParse(
      values[webDavTvPendingRevisionMetaKey] ?? '',
    );
    final lastSyncedMs = int.tryParse(
      values[webDavTvLastSyncedMsMetaKey] ?? '',
    );
    if (pendingRevision == null || pendingRevision < 0) {
      throw StateError('Debrify TV pending revision is invalid');
    }
    return WebDavSyncTvSyncMetadata(
      changesPending: values[webDavTvChangesPendingMetaKey] == '1',
      pendingRevision: pendingRevision,
      lastSyncedMs: lastSyncedMs,
    );
  });

  /// Records a completed manifest-last manual sync. A TV write that landed
  /// after the operation's snapshot keeps the pending hint set for next time.
  Future<void> completeWebDavTvSync(
    ProfileScope scope, {
    required int expectedPendingRevision,
    required int syncedAtMs,
  }) => runOneShotScoped(scope, (db) {
    return db.transaction((txn) async {
      final rows = await txn.query(
        'webdav_sync_meta',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object>[webDavTvPendingRevisionMetaKey],
      );
      final current = rows.length == 1
          ? int.tryParse(rows.single['value']! as String)
          : null;
      if (current == null || current < 0) {
        throw StateError('Debrify TV pending revision is invalid');
      }
      if (current == expectedPendingRevision) {
        await txn.update(
          'webdav_sync_meta',
          const <String, Object?>{'value': '0'},
          where: 'key = ?',
          whereArgs: const <Object>[webDavTvChangesPendingMetaKey],
        );
      }
      await txn.insert('webdav_sync_meta', <String, Object?>{
        'key': webDavTvLastSyncedMsMetaKey,
        'value': syncedAtMs.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  });

  /// Opens one temporary connection for [scope] without swapping [_db]. It
  /// participates in the existing active-operation drain, so a profile switch
  /// cannot close or redirect a library snapshot/apply midway through.
  Future<T> runOneShotScoped<T>(
    ProfileScope scope,
    Future<T> Function(Database db) action,
  ) async {
    await ProfileDatabaseAdoptionGate.waitUntilReleased();
    final requested = _scopeOf(scope);
    await _scopeLock.synchronized(() {
      if (_deactivatedScopeKeys.contains(requested.key)) {
        throw StateError('Debrify TV database scope is deactivated');
      }
      _activeOperations += 1;
    });
    Database? opened;
    var ownsHandle = false;
    try {
      opened = debugDatabaseOverride;
      if (opened == null) {
        final dbPath = await ProfileRuntime.withCapturedScope(
          scope,
          () => ProfileStoragePaths.documentsFile('debrify_tv.db'),
        );
        opened = await _openAtPath(dbPath, singleInstance: false);
        ownsHandle = true;
      }
      return await action(opened);
    } finally {
      if (ownsHandle) await opened?.close();
      await _scopeLock.synchronized(() {
        _activeOperations -= 1;
        if (_activeOperations == 0) {
          final drained = _operationsDrained;
          _operationsDrained = null;
          if (drained != null && !drained.isCompleted) drained.complete();
        }
      });
    }
  }

  /// Atomically captures all debrify_tv-backed v3 library families together
  /// with the mutation revision that fences a later materialization.
  Future<WebDavSyncDatabaseStateSnapshot> readWebDavSyncState(
    ProfileScope scope, {
    required int clockOffsetMs,
    required int serverNowMs,
    bool includeTvFamilies = true,
    bool includeAmbientFamilies = true,
  }) => runOneShotScoped(scope, (db) {
    return db.transaction((txn) async {
      if (!includeTvFamilies && !includeAmbientFamilies) {
        throw ArgumentError('At least one WebDAV library family is required');
      }
      final channelRows = includeTvFamilies
          ? await txn.query('tv_channels')
          : const <Map<String, Object?>>[];
      final channelKeywords = <String, List<String>>{};
      if (includeTvFamilies) {
        for (final row in await txn.query(
          'tv_channel_keywords',
          orderBy: 'channel_id, position',
        )) {
          channelKeywords
              .putIfAbsent(row['channel_id']! as String, () => <String>[])
              .add(row['keyword']! as String);
        }
      }
      final channels = <String, Map<String, Object?>>{
        for (final row in channelRows) row['channel_id']! as String: row,
      };
      final listRows = includeAmbientFamilies
          ? await txn.query('iptv_lists')
          : const <Map<String, Object?>>[];
      final lists = <String, Map<String, Object?>>{
        for (final row in listRows) row['id']! as String: row,
      };
      final listChannelRows = includeAmbientFamilies
          ? await txn.query('iptv_list_channels')
          : const <Map<String, Object?>>[];
      final listChannels = <(String, String), Map<String, Object?>>{
        for (final row in listChannelRows)
          (row['list_id']! as String, row['url']! as String): row,
      };
      final orderRows = includeAmbientFamilies
          ? await txn.query(
              'iptv_category_channel_orders',
              orderBy:
                  'source_id, channel_group, position, url, name, occurrence',
            )
          : const <Map<String, Object?>>[];
      final orders = <(String, String), List<Map<String, Object?>>>{};
      for (final row in orderRows) {
        orders
            .putIfAbsent((
              row['source_id']! as String,
              row['channel_group']! as String,
            ), () => <Map<String, Object?>>[])
            .add(<String, Object?>{
              'url': row['url'] as String,
              'name': row['name'] as String,
              'occurrence': (row['occurrence'] as num).toInt(),
            });
      }
      final historyRows = includeAmbientFamilies
          ? await txn.query('iptv_watch_history')
          : const <Map<String, Object?>>[];
      final history = <String, Map<String, Object?>>{
        for (final row in historyRows) row['url']! as String: row,
      };
      final resumeRows = includeAmbientFamilies
          ? await txn.query('video_resume')
          : const <Map<String, Object?>>[];
      final resumes = <String, Map<String, Object?>>{
        for (final row in resumeRows) row['resume_key']! as String: row,
      };
      final rawStates = await txn.query(
        'webdav_sync_record_state',
        orderBy: 'kind, owner_key, item_key',
      );
      final records = <WebDavSyncRecordState>[];
      final poolGenerations = <String, WebDavSyncRecordState>{};
      // Normalization updates land in one batch: after a restore every
      // sidecar row is unnormalized, and one awaited update per row held
      // the shared database for seconds.
      final normalization = txn.batch();
      var normalizationPending = false;
      for (final row in rawStates) {
        final kind = row['kind']! as String;
        final isTv = WebDavSyncLibraryKinds.isTvKind(kind);
        if (isTv ? !includeTvFamilies : !includeAmbientFamilies) continue;
        var updatedAtMs = (row['updated_at_ms'] as num).toInt();
        if (row['normalized'] != 1) {
          updatedAtMs = (updatedAtMs + clockOffsetMs)
              .clamp(0, serverNowMs)
              .toInt();
          normalization.update(
            'webdav_sync_record_state',
            <String, Object?>{'updated_at_ms': updatedAtMs, 'normalized': 1},
            where: 'kind = ? AND owner_key = ? AND item_key = ?',
            whereArgs: <Object?>[
              row['kind'],
              row['owner_key'],
              row['item_key'],
            ],
          );
          normalizationPending = true;
        }
        final owner = row['owner_key']! as String;
        final item = row['item_key']! as String;
        final deleted = row['deleted'] == 1;
        Map<String, Object?>? value;
        if (!deleted) {
          switch (kind) {
            case WebDavSyncLibraryKinds.tvChannels:
              final physical = channels[owner];
              if (physical != null) {
                value = <String, Object?>{
                  'name': physical['name'] as String,
                  'avoidNsfw': physical['avoid_nsfw'] == 1,
                  // Sync apply stores the unchanged desired number in aux;
                  // the UNIQUE physical number may have been reassigned.
                  'channelNumber':
                      int.tryParse(row['aux'] as String? ?? '') ??
                      (physical['channel_number'] as num).toInt(),
                  'createdAt': (physical['created_at'] as num).toInt(),
                  'keywords': channelKeywords[owner] ?? const <String>[],
                };
              }
            case WebDavSyncLibraryKinds.tvPoolGeneration:
              final generationId = row['aux'];
              if (generationId is String && generationId.isNotEmpty) {
                value = <String, Object?>{'generationId': generationId};
              }
            case WebDavSyncLibraryKinds.iptvCategoryChannelOrders:
              final items = orders[(owner, item)];
              if (items != null) {
                value = <String, Object?>{'group': item, 'items': items};
              }
            case WebDavSyncLibraryKinds.iptvLists:
              final physical = lists[owner];
              if (physical != null && physical['is_builtin'] == 0) {
                value = <String, Object?>{
                  'name': physical['name'] as String,
                  // Keep publishing the stamped desired position, not the
                  // compact physical position assigned by sync apply.
                  'position':
                      int.tryParse(row['aux'] as String? ?? '') ??
                      (physical['position'] as num).toInt(),
                  'createdAt': (physical['created_at'] as num).toInt(),
                };
              }
            case WebDavSyncLibraryKinds.iptvListChannels:
              final physical = listChannels[(owner, item)];
              if (physical != null) {
                value = _listChannelSnapshotValue(physical);
              }
            case WebDavSyncLibraryKinds.iptvWatchHistory:
              final physical = history[item];
              if (physical != null && physical['playlist_id'] == owner) {
                value = _watchWireValue(physical);
              }
            case WebDavSyncLibraryKinds.videoResume:
              final physical = resumes[item];
              final physicalOwner = physical == null
                  ? null
                  : ((physical['source_id'] as String?)?.isNotEmpty == true
                        ? physical['source_id'] as String
                        : '_');
              if (physical != null && physicalOwner == owner) {
                value = <String, Object?>{
                  'resumeKey': item,
                  'position': (physical['position_ms'] as num).toInt(),
                  'duration': (physical['duration_ms'] as num).toInt(),
                  'speed': (physical['speed'] as num).toDouble(),
                  'aspectRatio': physical['aspect'] as String,
                };
              }
          }
        }
        final record = WebDavSyncRecordState(
          kind: kind,
          ownerKey: owner,
          itemKey: item,
          stamp: WebDavSyncStamp(
            normalizedTimeMs: updatedAtMs,
            originDeviceId: row['origin_device_id']! as String,
          ),
          deleted: deleted,
          aux: row['aux'] as String?,
          value: value,
        );
        records.add(record);
        if (kind == WebDavSyncLibraryKinds.tvPoolGeneration &&
            !deleted &&
            value != null) {
          poolGenerations[owner] = record;
        }
      }
      if (normalizationPending) await normalization.commit(noResult: true);
      final pools = <WebDavSyncTvPoolSnapshot>[];
      String? rankedChannel;
      var rank = 0;
      final poolRows = includeTvFamilies
          ? await txn.query(
              'tv_cached_torrents',
              orderBy: 'channel_id ASC, added_at DESC, infohash ASC',
            )
          : const <Map<String, Object?>>[];
      for (final row in poolRows) {
        final channelId = row['channel_id']! as String;
        final generation = poolGenerations[channelId];
        final generationId = generation?.value?['generationId'];
        if (generation == null || generationId is! String) continue;
        if (rankedChannel != channelId) {
          rankedChannel = channelId;
          rank = 0;
        }
        pools.add(
          WebDavSyncTvPoolSnapshot(
            channelId: channelId,
            infohash: (row['infohash']! as String).toLowerCase(),
            generationId: generationId,
            name: row['name']! as String,
            sizeBytes: (row['size_bytes'] as num).toInt(),
            keywords: _decodeStringList(row['keywords_json']),
            rank: rank++,
            stamp: generation.stamp,
          ),
        );
      }
      final meta = await txn.query(
        'webdav_sync_meta',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object>['mutation_revision'],
      );
      if (meta.length != 1) {
        throw StateError('Debrify TV sync revision is unavailable');
      }
      var tvPendingRevision = 0;
      if (includeTvFamilies) {
        final pendingRevisionRows = await txn.query(
          'webdav_sync_meta',
          columns: const <String>['value'],
          where: 'key = ?',
          whereArgs: const <Object>[webDavTvPendingRevisionMetaKey],
        );
        if (pendingRevisionRows.length != 1) {
          throw StateError('Debrify TV pending revision is unavailable');
        }
        tvPendingRevision =
            int.tryParse(pendingRevisionRows.single['value']! as String) ?? -1;
        if (tvPendingRevision < 0) {
          throw StateError('Debrify TV pending revision is invalid');
        }
      }
      return WebDavSyncDatabaseStateSnapshot(
        mutationRevision: int.parse(meta.single['value']! as String),
        records: List<WebDavSyncRecordState>.unmodifiable(records),
        tvPools: List<WebDavSyncTvPoolSnapshot>.unmodifiable(pools),
        tvPendingRevision: tvPendingRevision,
      );
    }, exclusive: true);
  });

  /// Exact-stamp materializer for every v3 family stored in debrify_tv.db.
  /// Public mutation APIs are intentionally bypassed: apply never re-stamps,
  /// creates tombstones, or emits local-change/UI notifications.
  Future<({WebDavSyncLibraryApplyResult result, Set<String> touchedNamespaces})>
  applyWebDavSyncFamilies(
    ProfileScope scope, {
    required int expectedRevision,
    required Iterable<WebDavSyncTvChannelTarget> channelTargets,
    required Iterable<WebDavSyncTvPoolGenerationTarget> generationTargets,
    required Iterable<WebDavSyncTvPoolTarget> poolTargets,
    required Iterable<WebDavSyncIptvListTarget> listTargets,
    required Iterable<WebDavSyncIptvListChannelTarget> listChannelTargets,
    required Iterable<WebDavSyncIptvOrderTarget> orderTargets,
    required Iterable<WebDavSyncIptvWatchTarget> watchTargets,
    required Iterable<WebDavSyncVideoResumeTarget> resumeTargets,
    bool includeTvFamilies = true,
  }) => runOneShotScoped(scope, (db) {
    return db.transaction((txn) async {
      final revisionRows = await txn.query(
        'webdav_sync_meta',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object>['mutation_revision'],
      );
      if (revisionRows.length != 1 ||
          int.tryParse(revisionRows.single['value']! as String) !=
              expectedRevision) {
        return (
          result: WebDavSyncLibraryApplyResult.conflict,
          touchedNamespaces: const <String>{},
        );
      }

      final channels = channelTargets.toList(growable: false);
      final generations = generationTargets.toList(growable: false);
      final pools = poolTargets.toList(growable: false);
      final lists = listTargets
          .where((target) => target.listId != favoritesListId)
          .toList(growable: false);
      final listChannels = listChannelTargets.toList(growable: false);
      final orders = orderTargets.toList(growable: false);
      final watches = watchTargets.toList(growable: false);
      final resumes = resumeTargets.toList(growable: false);

      // SQLite's Android implementation crosses the platform channel for each
      // awaited executor call. Materialize every read-side view once, then
      // keep it current while the write batch is assembled below.
      final stateRows = await txn.query('webdav_sync_record_state');
      final stateByKey = <(String, String, String), Map<String, Object?>>{
        for (final row in stateRows)
          (
            row['kind']! as String,
            row['owner_key']! as String,
            row['item_key']! as String,
          ): row,
      };
      final physicalChannelRows = includeTvFamilies
          ? await txn.query('tv_channels')
          : const <Map<String, Object?>>[];
      final physicalById = <String, Map<String, Object?>>{
        for (final row in physicalChannelRows)
          row['channel_id']! as String: row,
      };
      final initialPhysicalChannelIds = physicalById.keys.toSet();
      final keywordsByChannel = <String, List<String>>{};
      if (includeTvFamilies) {
        for (final row in await txn.query(
          'tv_channel_keywords',
          columns: const <String>['channel_id', 'keyword'],
          orderBy: 'channel_id, position',
        )) {
          keywordsByChannel
              .putIfAbsent(row['channel_id']! as String, () => <String>[])
              .add(row['keyword']! as String);
        }
      }
      final physicalListRows = await txn.query('iptv_lists');
      final physicalListsById = <String, Map<String, Object?>>{
        for (final row in physicalListRows) row['id']! as String: row,
      };
      final initialCustomListIds = <String>{
        for (final row in physicalListRows)
          if (row['is_builtin'] == 0) row['id']! as String,
      };
      final physicalListChannels = <(String, String), Map<String, Object?>>{
        for (final row in await txn.query('iptv_list_channels'))
          (row['list_id']! as String, row['url']! as String): row,
      };
      final physicalOrders = <(String, String), List<Map<String, Object?>>>{};
      for (final row in await txn.query(
        'iptv_category_channel_orders',
        orderBy: 'source_id, channel_group, position, url, name, occurrence',
      )) {
        physicalOrders
            .putIfAbsent((
              row['source_id']! as String,
              row['channel_group']! as String,
            ), () => <Map<String, Object?>>[])
            .add(row);
      }
      final physicalWatches = <String, Map<String, Object?>>{
        for (final row in await txn.query('iptv_watch_history'))
          row['url']! as String: row,
      };
      final physicalResumes = <String, Map<String, Object?>>{
        for (final row in await txn.query('video_resume'))
          row['resume_key']! as String: row,
      };
      final poolCountsByChannel = includeTvFamilies
          ? <String, int>{
              for (final row in await txn.rawQuery(
                'SELECT channel_id, COUNT(*) AS row_count '
                'FROM tv_cached_torrents GROUP BY channel_id',
              ))
                row['channel_id']! as String: (row['row_count'] as num).toInt(),
            }
          : <String, int>{};

      final touched = <String>{};
      final batch = txn.batch();
      bool needsWrite(
        String kind,
        String owner,
        String item,
        WebDavSyncCircleLeaf<Map<String, Object?>> leaf, {
        String? aux,
      }) {
        final row = stateByKey[(kind, owner, item)];
        return row == null ||
            (row['updated_at_ms'] as num).toInt() !=
                leaf.stamp.normalizedTimeMs ||
            row['origin_device_id'] != leaf.stamp.originDeviceId ||
            row['normalized'] != 1 ||
            row['deleted'] != (leaf.value == null ? 1 : 0) ||
            aux != null && row['aux'] != aux;
      }

      void writeState(
        String kind,
        String owner,
        String item,
        WebDavSyncCircleLeaf<Map<String, Object?>> leaf, {
        String? aux,
      }) {
        final row = <String, Object?>{
          'kind': kind,
          'owner_key': owner,
          'item_key': item,
          'updated_at_ms': leaf.stamp.normalizedTimeMs,
          'origin_device_id': leaf.stamp.originDeviceId,
          'normalized': 1,
          'deleted': leaf.value == null ? 1 : 0,
          'aux': aux,
        };
        batch.insert(
          'webdav_sync_record_state',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        stateByKey[(kind, owner, item)] = row;
      }

      final liveChannels =
          channels
              .where((target) => target.leaf.value != null)
              .toList(growable: false)
            ..sort((left, right) {
              final desired = left.desiredChannelNumber.compareTo(
                right.desiredChannelNumber,
              );
              return desired != 0
                  ? desired
                  : left.channelId.compareTo(right.channelId);
            });
      final targetIds = channels.map((target) => target.channelId).toSet();
      final usedNumbers = <int>{
        for (final row in physicalChannelRows)
          if (!targetIds.contains(row['channel_id']))
            (row['channel_number'] as num).toInt(),
      };
      final assignedNumbers = <String, int>{};
      for (final target in liveChannels) {
        var assigned = target.desiredChannelNumber;
        while (usedNumbers.contains(assigned)) {
          assigned += 1;
        }
        assignedNumbers[target.channelId] = assigned;
        usedNumbers.add(assigned);
      }

      var writeChannels = false;
      for (final target in channels) {
        final desiredNumber = target.leaf.value == null
            ? null
            : target.desiredChannelNumber.toString();
        final stateChanged = needsWrite(
          WebDavSyncLibraryKinds.tvChannels,
          target.channelId,
          '',
          target.leaf,
          aux: desiredNumber,
        );
        final physical = physicalById[target.channelId];
        final value = target.leaf.value;
        final physicalChanged = value == null
            ? physical != null
            : physical == null ||
                  physical['name'] != target.name ||
                  physical['avoid_nsfw'] != (target.avoidNsfw ? 1 : 0) ||
                  physical['channel_number'] !=
                      assignedNumbers[target.channelId] ||
                  physical['created_at'] != target.createdAtMs ||
                  !_channelKeywordsEqual(
                    keywordsByChannel[target.channelId],
                    target,
                  );
        if (stateChanged || physicalChanged) writeChannels = true;
      }
      if (writeChannels) {
        final occupied = <int>{
          ...physicalChannelRows.map(
            (row) => (row['channel_number'] as num).toInt(),
          ),
          ...assignedNumbers.values,
        };
        var temporary = occupied.isEmpty
            ? 1
            : occupied.reduce((left, right) => left > right ? left : right) + 1;
        // Vacate every target number before canonical insertion. This avoids
        // transient UNIQUE failures when two winners exchange or collide.
        for (final target in liveChannels) {
          if (!physicalById.containsKey(target.channelId)) continue;
          while (occupied.contains(temporary)) {
            temporary += 1;
          }
          batch.update(
            'tv_channels',
            <String, Object?>{'channel_number': temporary},
            where: 'channel_id = ?',
            whereArgs: <Object?>[target.channelId],
          );
          final physical = physicalById[target.channelId];
          if (physical != null) {
            physicalById[target.channelId] = <String, Object?>{
              ...physical,
              'channel_number': temporary,
            };
          }
          occupied.add(temporary++);
        }
        for (final target in channels.where(
          (target) => target.leaf.value == null,
        )) {
          batch.delete(
            'tv_channels',
            where: 'channel_id = ?',
            whereArgs: <Object?>[target.channelId],
          );
          if (physicalById.remove(target.channelId) != null) {
            keywordsByChannel.remove(target.channelId);
            poolCountsByChannel[target.channelId] = 0;
          }
        }
        for (final target in liveChannels) {
          final values = <String, Object?>{
            'name': target.name,
            'avoid_nsfw': target.avoidNsfw ? 1 : 0,
            'channel_number': assignedNumbers[target.channelId],
            'created_at': target.createdAtMs,
            'updated_at': target.leaf.stamp.normalizedTimeMs,
          };
          if (initialPhysicalChannelIds.contains(target.channelId)) {
            batch.update(
              'tv_channels',
              values,
              where: 'channel_id = ?',
              whereArgs: <Object?>[target.channelId],
            );
            final physical = physicalById[target.channelId];
            if (physical != null) {
              physicalById[target.channelId] = <String, Object?>{
                ...physical,
                ...values,
              };
            }
          } else {
            batch.insert('tv_channels', <String, Object?>{
              'channel_id': target.channelId,
              ...values,
            });
            batch.insert(
              'tv_channel_cache_state',
              <String, Object?>{
                'channel_id': target.channelId,
                'status': 'warming',
                'error_message': null,
                'fetched_at': 0,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            physicalById[target.channelId] = <String, Object?>{
              'channel_id': target.channelId,
              ...values,
            };
          }
          batch.delete(
            'tv_channel_keywords',
            where: 'channel_id = ?',
            whereArgs: <Object?>[target.channelId],
          );
          for (
            var position = 0;
            position < target.keywords.length;
            position++
          ) {
            batch.insert('tv_channel_keywords', <String, Object?>{
              'channel_id': target.channelId,
              'position': position,
              'keyword': target.keywords[position],
            });
          }
          if (physicalById.containsKey(target.channelId)) {
            keywordsByChannel[target.channelId] = target.keywords.toList(
              growable: false,
            );
          }
        }
        for (final target in channels) {
          writeState(
            WebDavSyncLibraryKinds.tvChannels,
            target.channelId,
            '',
            target.leaf,
            aux: target.leaf.value == null
                ? null
                : target.desiredChannelNumber.toString(),
          );
        }
        touched.add('tv/ch');
      }

      final poolsByGeneration = <String, List<WebDavSyncTvPoolTarget>>{};
      for (final target in pools) {
        poolsByGeneration
            .putIfAbsent(
              '${target.channelId}\u0000${target.generationId}',
              () => <WebDavSyncTvPoolTarget>[],
            )
            .add(target);
      }
      for (final target in generations) {
        final matching =
            poolsByGeneration['${target.channelId}\u0000${target.generationId}'] ??
            const <WebDavSyncTvPoolTarget>[];
        if (!needsWrite(
          WebDavSyncLibraryKinds.tvPoolGeneration,
          target.channelId,
          '',
          target.leaf,
          aux: target.generationId,
        )) {
          // A sidecar stamp can outlive its physical rows (a snapshot or
          // restore path that splits them). Row count is the cheap integrity
          // probe: a divergent pool re-materializes even under an exact stamp.
          final physicalRows = poolCountsByChannel[target.channelId] ?? 0;
          if (physicalRows == matching.length) continue;
        }
        batch.delete(
          'tv_cached_torrents',
          where: 'channel_id = ?',
          whereArgs: <Object?>[target.channelId],
        );
        final ranked = matching.toList(growable: false)
          ..sort((left, right) {
            final byRank = left.rank.compareTo(right.rank);
            return byRank != 0
                ? byRank
                : left.infohash.compareTo(right.infohash);
          });
        for (var index = 0; index < ranked.length; index++) {
          final pool = ranked[index];
          batch.insert('tv_cached_torrents', <String, Object?>{
            'channel_id': pool.channelId,
            'infohash': pool.infohash,
            'name': pool.name,
            'size_bytes': pool.sizeBytes,
            'created_unix': 0,
            'seeders': 0,
            'leechers': 0,
            'completed': 0,
            'scraped_date': 0,
            'keywords_json': jsonEncode(pool.keywords),
            'sources_json': '[]',
            'added_at': ranked.length - index,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        batch.insert('tv_channel_cache_state', <String, Object?>{
          'channel_id': target.channelId,
          'status': ranked.isEmpty ? 'warming' : 'ready',
          'error_message': null,
          'fetched_at': target.leaf.stamp.normalizedTimeMs,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        poolCountsByChannel[target.channelId] = ranked.length;
        writeState(
          WebDavSyncLibraryKinds.tvPoolGeneration,
          target.channelId,
          '',
          target.leaf,
          aux: target.generationId,
        );
        touched.add('tv/pool');
      }

      final liveLists =
          lists
              .where((target) => target.leaf.value != null)
              .toList(growable: false)
            ..sort((left, right) {
              final desired = left.desiredPosition.compareTo(
                right.desiredPosition,
              );
              return desired != 0
                  ? desired
                  : left.listId.compareTo(right.listId);
            });
      final assignedListPositions = <String, int>{
        for (var index = 0; index < liveLists.length; index++)
          liveLists[index].listId: index + 1,
      };
      var writeLists = false;
      for (final target in lists) {
        final desiredPosition = target.leaf.value == null
            ? null
            : target.desiredPosition.toString();
        final stateChanged = needsWrite(
          WebDavSyncLibraryKinds.iptvLists,
          target.listId,
          '',
          target.leaf,
          aux: desiredPosition,
        );
        final physical = initialCustomListIds.contains(target.listId)
            ? physicalListsById[target.listId]
            : null;
        final physicalChanged = target.leaf.value == null
            ? physical != null
            : physical == null ||
                  physical['name'] != target.name ||
                  physical['position'] !=
                      assignedListPositions[target.listId] ||
                  physical['created_at'] != target.createdAtMs;
        if (stateChanged || physicalChanged) writeLists = true;
      }
      if (writeLists) {
        for (final target in lists.where(
          (target) => target.leaf.value == null,
        )) {
          batch.delete(
            'iptv_lists',
            where: 'id = ? AND is_builtin = 0',
            whereArgs: <Object?>[target.listId],
          );
          final physical = physicalListsById[target.listId];
          if (physical != null && physical['is_builtin'] == 0) {
            physicalListsById.remove(target.listId);
            physicalListChannels.removeWhere(
              (key, _) => key.$1 == target.listId,
            );
          }
        }
        for (final target in liveLists) {
          final values = <String, Object?>{
            'name': target.name,
            'position': assignedListPositions[target.listId],
            'is_builtin': 0,
            'created_at': target.createdAtMs,
            'updated_at': target.leaf.stamp.normalizedTimeMs,
          };
          if (initialCustomListIds.contains(target.listId)) {
            batch.update(
              'iptv_lists',
              values,
              where: 'id = ? AND is_builtin = 0',
              whereArgs: <Object?>[target.listId],
            );
            final physical = physicalListsById[target.listId];
            if (physical != null && physical['is_builtin'] == 0) {
              physicalListsById[target.listId] = <String, Object?>{
                ...physical,
                ...values,
              };
            }
          } else {
            batch.insert('iptv_lists', <String, Object?>{
              'id': target.listId,
              ...values,
            });
            physicalListsById[target.listId] = <String, Object?>{
              'id': target.listId,
              ...values,
            };
          }
        }
        for (final target in lists) {
          writeState(
            WebDavSyncLibraryKinds.iptvLists,
            target.listId,
            '',
            target.leaf,
            aux: target.leaf.value == null
                ? null
                : target.desiredPosition.toString(),
          );
        }
        touched.add('iptv/list');
      }

      final materializedListIds = physicalListsById.keys.toSet();
      for (final target in listChannels) {
        if (!materializedListIds.contains(target.listId)) continue;
        final physicalKey = (target.listId, target.url);
        final physical = physicalListChannels[physicalKey];
        final stateChanged = needsWrite(
          WebDavSyncLibraryKinds.iptvListChannels,
          target.listId,
          target.url,
          target.leaf,
        );
        final physicalChanged = target.leaf.value == null
            ? physical != null
            : physical == null || !_listChannelPhysicalEquals(physical, target);
        if (!stateChanged && !physicalChanged) continue;
        batch.delete(
          'iptv_list_channels',
          where: 'list_id = ? AND url = ?',
          whereArgs: <Object?>[target.listId, target.url],
        );
        physicalListChannels.remove(physicalKey);
        final value = target.leaf.value;
        if (value != null) {
          final headers = value['httpHeaders'];
          final row = <String, Object?>{
            'list_id': target.listId,
            'url': target.url,
            'name': value['name'],
            'logo_url': value['logoUrl'],
            'channel_group': value['group'],
            'playlist_id': target.localSourceId,
            'channel_number': value['channelNumber'],
            'content_type': value['contentType'],
            'duration': value['duration'],
            'http_headers_json': headers is Map && headers.isNotEmpty
                ? jsonEncode(headers)
                : null,
            'added_at': value['addedAt'],
            'position': value['position'],
          };
          batch.insert('iptv_list_channels', row);
          physicalListChannels[physicalKey] = row;
        }
        writeState(
          WebDavSyncLibraryKinds.iptvListChannels,
          target.listId,
          target.url,
          target.leaf,
        );
        touched.add('iptv/list-ch');
      }

      for (final target in orders) {
        if (!needsWrite(
          WebDavSyncLibraryKinds.iptvCategoryChannelOrders,
          target.sourceId,
          target.group,
          target.leaf,
        )) {
          continue;
        }
        final physicalKey = (target.sourceId, target.group);
        batch.delete(
          'iptv_category_channel_orders',
          where: 'source_id = ? AND channel_group = ?',
          whereArgs: <Object?>[target.sourceId, target.group],
        );
        physicalOrders.remove(physicalKey);
        if (target.leaf.value != null) {
          final rows = <Map<String, Object?>>[];
          for (var position = 0; position < target.items.length; position++) {
            final item = target.items[position];
            final row = <String, Object?>{
              'source_id': target.sourceId,
              'channel_group': target.group,
              'url': item.url,
              'name': item.name,
              'occurrence': item.occurrence,
              'position': position,
            };
            batch.insert('iptv_category_channel_orders', row);
            rows.add(row);
          }
          physicalOrders[physicalKey] = rows;
        }
        writeState(
          WebDavSyncLibraryKinds.iptvCategoryChannelOrders,
          target.sourceId,
          target.group,
          target.leaf,
        );
        touched.add('iptv/order');
      }

      for (final target in watches) {
        if (!needsWrite(
          WebDavSyncLibraryKinds.iptvWatchHistory,
          target.sourceId,
          target.url,
          target.leaf,
        )) {
          continue;
        }
        batch.delete(
          'iptv_watch_history',
          where: 'url = ?',
          whereArgs: <Object?>[target.url],
        );
        physicalWatches.remove(target.url);
        final value = target.leaf.value;
        if (value != null) {
          final headers = value['headers'];
          final row = <String, Object?>{
            'url': target.url,
            'name': value['name'],
            'logo_url': value['logoUrl'],
            'channel_group': value['group'],
            'playlist_id': target.sourceId,
            'http_headers_json': headers is Map && headers.isNotEmpty
                ? jsonEncode(headers)
                : null,
            'series_id': value['seriesId'],
            'series_name': value['seriesName'],
            'season': value['season'],
            'episode': value['episode'],
            'has_next': value['hasNext'] == null
                ? null
                : (value['hasNext'] == true ? 1 : 0),
            'last_played_at': value['lastPlayedAt'],
          };
          batch.insert('iptv_watch_history', row);
          physicalWatches[target.url] = row;
        }
        writeState(
          WebDavSyncLibraryKinds.iptvWatchHistory,
          target.sourceId,
          target.url,
          target.leaf,
        );
        touched.add('iptv/watch');
      }

      for (final target in resumes) {
        final owner = target.sourceId ?? '_';
        if (!needsWrite(
          WebDavSyncLibraryKinds.videoResume,
          owner,
          target.resumeKey,
          target.leaf,
        )) {
          continue;
        }
        batch.delete(
          'video_resume',
          where: 'resume_key = ?',
          whereArgs: <Object?>[target.resumeKey],
        );
        physicalResumes.remove(target.resumeKey);
        final value = target.leaf.value;
        if (value != null) {
          final row = <String, Object?>{
            'resume_key': target.resumeKey,
            'source_id': target.sourceId,
            'position_ms': value['position'],
            'duration_ms': value['duration'],
            'speed': value['speed'],
            'aspect': value['aspectRatio'],
            'updated_at': target.leaf.stamp.normalizedTimeMs,
          };
          batch.insert('video_resume', row);
          physicalResumes[target.resumeKey] = row;
        }
        writeState(
          WebDavSyncLibraryKinds.videoResume,
          owner,
          target.resumeKey,
          target.leaf,
        );
        touched.add('resume');
      }

      // Retention is a physical/read-side cap only. State rows remain live so
      // this omission can neither publish a tombstone nor beat the wire winner.
      batch.execute('''
        DELETE FROM iptv_watch_history
        WHERE url NOT IN (
          SELECT url FROM iptv_watch_history
          ORDER BY last_played_at DESC, url DESC
          LIMIT 100
        )
      ''');
      if (touched.isNotEmpty) {
        batch.execute('''
          UPDATE webdav_sync_meta
          SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT)
          WHERE key = 'mutation_revision'
        ''');
      }
      await batch.commit(noResult: true);
      return (
        result: WebDavSyncLibraryApplyResult.applied,
        touchedNamespaces: Set<String>.unmodifiable(touched),
      );
    }, exclusive: true);
  });

  _DatabaseScope _requestedScope() {
    if (!ProfileRuntime.isInitialized) {
      throw StateError('Profile runtime is not initialized');
    }
    if (!ProfileRuntime.isProfileCommitted) {
      return (key: 'legacy', scope: null);
    }
    final scope = ProfileRuntime.capture();
    return _scopeOf(scope);
  }

  _DatabaseScope _scopeOf(ProfileScope scope) => (
    key: '${scope.profileId}:${scope.dataGeneration}:${scope.sessionEpoch}',
    scope: scope,
  );

  @visibleForTesting
  Future<void> debugResetScopeState() => _scopeLock.synchronized(() async {
    final opened = _db;
    _db = null;
    _dbScopeKey = null;
    _openingScopeKey = null;
    _deactivatedScopeKeys.clear();
    debugBeforeOpenPublish = null;
    if (opened != null) await opened.close();
  });

  static Future<Database> _openAtPath(
    String dbPath, {
    bool singleInstance = true,
  }) => openDatabase(
    dbPath,
    version: 10,
    singleInstance: singleInstance,
    onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys = ON');
    },
    // Rebuilding is safer than leaving an older sideload permanently wedged.
    onDowngrade: onDatabaseDowngradeDelete,
    onCreate: _createSchema,
    onUpgrade: runUpgrade,
    onOpen: ensureWebDavSyncMetaDefaults,
  );

  static Future<void> _createSchema(Database db, int _) async {
    await createTvStoreTables(db);
    await createIptvStoreTables(db);
  }

  /// Debrify TV channel/cache tables. Exposed for real-SQLite store fixtures;
  /// production creates the same shape through [_createSchema].
  @visibleForTesting
  static Future<void> createTvStoreTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tv_channels (
        channel_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        avoid_nsfw INTEGER NOT NULL DEFAULT 1,
        channel_number INTEGER NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tv_channel_keywords (
        channel_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        keyword TEXT NOT NULL,
        PRIMARY KEY (channel_id, position),
        FOREIGN KEY (channel_id) REFERENCES tv_channels(channel_id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tv_channel_cache_state (
        channel_id TEXT PRIMARY KEY,
        status TEXT NOT NULL DEFAULT 'warming',
        error_message TEXT,
        fetched_at INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (channel_id) REFERENCES tv_channels(channel_id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tv_cached_torrents (
        channel_id TEXT NOT NULL,
        infohash TEXT NOT NULL,
        name TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        created_unix INTEGER NOT NULL,
        seeders INTEGER NOT NULL,
        leechers INTEGER NOT NULL,
        completed INTEGER NOT NULL,
        scraped_date INTEGER NOT NULL,
        keywords_json TEXT NOT NULL,
        sources_json TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        PRIMARY KEY (channel_id, infohash),
        FOREIGN KEY (channel_id) REFERENCES tv_channels(channel_id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_tv_cached_torrents_channel_added
      ON tv_cached_torrents(channel_id, added_at)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tv_keyword_stats (
        channel_id TEXT NOT NULL,
        keyword TEXT NOT NULL,
        total_fetched INTEGER NOT NULL,
        last_searched_at INTEGER NOT NULL,
        pages_pulled INTEGER NOT NULL,
        pirate_bay_hits INTEGER NOT NULL,
        PRIMARY KEY (channel_id, keyword),
        FOREIGN KEY (channel_id) REFERENCES tv_channels(channel_id) ON DELETE CASCADE
      )
    ''');
  }

  /// Schema migrations. Named (rather than an inline closure) so migration
  /// tests can drive it against a database opened at an older version.
  @visibleForTesting
  static Future<void> runUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE tv_channels ADD COLUMN channel_number INTEGER',
      );

      final rows = await db.query(
        'tv_channels',
        columns: ['channel_id'],
        orderBy: 'updated_at DESC',
      );

      var channelNumber = 1;
      for (final row in rows) {
        final channelId = row['channel_id'] as String?;
        if (channelId == null || channelId.isEmpty) {
          continue;
        }
        await db.update(
          'tv_channels',
          {'channel_number': channelNumber},
          where: 'channel_id = ?',
          whereArgs: [channelId],
        );
        channelNumber += 1;
      }

      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_tv_channels_channel_number ON tv_channels(channel_number)',
      );
    }

    if (oldVersion < 3) {
      await createIptvStoreTables(db);
    }
    // Only a GENUINE v3 database has an iptv_favorites table predating
    // channel_number. v1/v2 databases got their IPTV tables from the call
    // above, which since v5 doesn't create iptv_favorites at all — hence the
    // `== 3` rather than `< 4`, and hence the existence check in the v5 step.
    if (oldVersion == 3) {
      await db.execute(
        'ALTER TABLE iptv_favorites ADD COLUMN channel_number INTEGER',
      );
    }

    if (oldVersion < 5) {
      await migrateFavoritesToLists(db);
    }

    if (oldVersion < 6 && newVersion >= 6) {
      await migrateIptvChannelOrder(db);
    }
    if (oldVersion < 7 && newVersion >= 7) {
      await createWebDavSyncSidecarTables(db);
    }
    if (oldVersion < 8 && newVersion >= 8) {
      await migrateWebDavSyncIptvFamilies(db);
    }
    if (oldVersion < 9 && newVersion >= 9) {
      await migrateWebDavSyncTvFamilies(db);
    }
    if (oldVersion < 10 && newVersion >= 10) {
      await migrateWebDavSyncIptvListFamilies(db);
    }
  }

  /// v6: channels inside Favorites/custom lists gain an explicit position,
  /// and imported-file categories gain their durable order table.
  ///
  /// Existing list rows are backfilled in their former case-insensitive A-Z
  /// presentation order so upgrading cannot visibly reshuffle a user's lists.
  static Future<void> migrateIptvChannelOrder(DatabaseExecutor db) async {
    await createIptvStoreTables(db);
    final columns = await db.rawQuery('PRAGMA table_info(iptv_list_channels)');
    final hasPosition = columns.any((row) => row['name'] == 'position');
    if (!hasPosition) {
      await db.execute(
        'ALTER TABLE iptv_list_channels '
        'ADD COLUMN position INTEGER NOT NULL DEFAULT 0',
      );
    }

    final lists = await db.query('iptv_lists', columns: ['id']);
    for (final list in lists) {
      final listId = list['id'] as String;
      final rows = await db.query(
        'iptv_list_channels',
        columns: ['url', 'name'],
        where: 'list_id = ?',
        whereArgs: [listId],
        orderBy: 'name COLLATE NOCASE ASC, url ASC',
      );
      for (var position = 0; position < rows.length; position++) {
        await db.update(
          'iptv_list_channels',
          {'position': position},
          where: 'list_id = ? AND url = ?',
          whereArgs: [listId, rows[position]['url']],
        );
      }
    }
  }

  /// v5: favorites stop being their own table and become the built-in list
  /// inside the custom-lists schema.
  ///
  /// The `sqlite_master` probe is load-bearing: on a v1/v2 database
  /// [createIptvStoreTables] has already run with the CURRENT schema, so
  /// `iptv_favorites` never existed on that path and a blind `SELECT` from it
  /// would throw mid-upgrade. It also makes a half-completed previous attempt
  /// (tables created, drop not reached) resumable.
  static Future<void> migrateFavoritesToLists(DatabaseExecutor db) async {
    await createIptvStoreTables(db);

    final legacy = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      ['iptv_favorites'],
    );
    if (legacy.isEmpty) return;

    // content_type / duration have no legacy counterpart — they stay NULL and
    // are backfilled by the reconcile pass the first time each playlist is
    // opened (IptvMediaStore). Until then a migrated VOD favorite keeps
    // presenting as live, exactly as it did before this migration.
    await db.execute(
      '''
      INSERT OR IGNORE INTO iptv_list_channels
        (list_id, url, name, logo_url, channel_group, playlist_id,
         channel_number, content_type, duration, http_headers_json, added_at)
      SELECT ?, url, name, logo_url, channel_group, playlist_id,
             channel_number, NULL, NULL, http_headers_json, added_at
      FROM iptv_favorites
    ''',
      [favoritesListId],
    );

    await db.execute('DROP TABLE iptv_favorites');
  }

  /// Reserved id of the built-in Favorites list: always present, never
  /// renamed, never deleted, and the destination of every legacy favorite.
  static const String favoritesListId = 'favorites';

  /// IPTV lists / watch history / video resume tables (schema v6), used by
  /// IptvMediaStore. `IF NOT EXISTS` so it's safe from both onCreate and
  /// onUpgrade, and callable directly by tests on an in-memory database.
  static Future<void> createIptvStoreTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS iptv_lists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        position INTEGER NOT NULL,
        is_builtin INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS iptv_list_channels (
        list_id TEXT NOT NULL,
        url TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        logo_url TEXT NOT NULL DEFAULT '',
        channel_group TEXT NOT NULL DEFAULT '',
        playlist_id TEXT NOT NULL DEFAULT '',
        channel_number INTEGER,
        content_type TEXT,
        duration INTEGER,
        http_headers_json TEXT,
        added_at INTEGER NOT NULL DEFAULT 0,
        position INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (list_id, url),
        FOREIGN KEY (list_id) REFERENCES iptv_lists(id) ON DELETE CASCADE
      )
    ''');

    // CREATE TABLE IF NOT EXISTS does not evolve an existing v5 table. Keep
    // this shape repair next to the table definition so the order index below
    // is never attempted before its column exists (including v1→v6 jumps).
    final listChannelColumns = await db.rawQuery(
      'PRAGMA table_info(iptv_list_channels)',
    );
    if (!listChannelColumns.any((row) => row['name'] == 'position')) {
      await db.execute(
        'ALTER TABLE iptv_list_channels '
        'ADD COLUMN position INTEGER NOT NULL DEFAULT 0',
      );
    }

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_list_channels_playlist
      ON iptv_list_channels(playlist_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_list_channels_url
      ON iptv_list_channels(url)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_list_channels_order
      ON iptv_list_channels(list_id, position)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS iptv_category_channel_orders (
        source_id TEXT NOT NULL,
        channel_group TEXT NOT NULL,
        url TEXT NOT NULL,
        name TEXT NOT NULL,
        occurrence INTEGER NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (source_id, channel_group, url, name, occurrence)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_category_channel_order
      ON iptv_category_channel_orders(source_id, channel_group, position)
    ''');

    await seedBuiltinList(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS iptv_watch_history (
        url TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        logo_url TEXT NOT NULL DEFAULT '',
        channel_group TEXT NOT NULL DEFAULT '',
        playlist_id TEXT NOT NULL DEFAULT '',
        http_headers_json TEXT,
        series_id TEXT,
        series_name TEXT,
        season INTEGER,
        episode INTEGER,
        has_next INTEGER,
        last_played_at INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_watch_history_last_played
      ON iptv_watch_history(last_played_at)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_iptv_watch_history_playlist
      ON iptv_watch_history(playlist_id)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS video_resume (
        resume_key TEXT PRIMARY KEY,
        source_id TEXT,
        position_ms INTEGER NOT NULL DEFAULT 0,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        speed REAL NOT NULL DEFAULT 1.0,
        aspect TEXT NOT NULL DEFAULT 'contain',
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await createWebDavSyncSidecarTables(db);
  }

  /// v8: identify IPTV resumes and seed the v3 library sidecar without
  /// treating imported data as a user mutation.
  @visibleForTesting
  static Future<void> migrateWebDavSyncIptvFamilies(DatabaseExecutor db) async {
    await createIptvStoreTables(db);
    final columns = await db.rawQuery('PRAGMA table_info(video_resume)');
    if (!columns.any((row) => row['name'] == 'source_id')) {
      await db.execute('ALTER TABLE video_resume ADD COLUMN source_id TEXT');
    }
    await db.execute('''
      UPDATE video_resume
      SET source_id = (
        SELECT NULLIF(h.playlist_id, '')
        FROM iptv_watch_history h
        WHERE h.url = video_resume.resume_key
        LIMIT 1
      )
      WHERE source_id IS NULL
        AND EXISTS (
          SELECT 1 FROM iptv_watch_history h
          WHERE h.url = video_resume.resume_key
            AND h.playlist_id <> ''
        )
    ''');
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawInsert(
      '''
      INSERT OR IGNORE INTO webdav_sync_record_state
        (kind, owner_key, item_key, updated_at_ms, origin_device_id,
         normalized, deleted, aux)
      SELECT ?, source_id, channel_group, ?, 'migration', 0, 0, NULL
      FROM iptv_category_channel_orders
      GROUP BY source_id, channel_group
      ''',
      <Object?>[WebDavSyncLibraryKinds.iptvCategoryChannelOrders, now],
    );
    await db.rawInsert(
      '''
      INSERT OR IGNORE INTO webdav_sync_record_state
        (kind, owner_key, item_key, updated_at_ms, origin_device_id,
         normalized, deleted, aux)
      SELECT ?, playlist_id, url, last_played_at, 'migration', 0, 0, NULL
      FROM iptv_watch_history
      ''',
      <Object?>[WebDavSyncLibraryKinds.iptvWatchHistory],
    );
    await db.rawInsert(
      '''
      INSERT OR IGNORE INTO webdav_sync_record_state
        (kind, owner_key, item_key, updated_at_ms, origin_device_id,
         normalized, deleted, aux)
      SELECT ?, COALESCE(NULLIF(source_id, ''), '_'), resume_key, updated_at,
             'migration', 0, 0, NULL
      FROM video_resume
      ''',
      <Object?>[WebDavSyncLibraryKinds.videoResume],
    );
  }

  /// v9: seed one migration-origin channel stamp and one generation stamp per
  /// existing physical pool. Torrent `added_at` is ordering data only; it is
  /// never promoted to the pool's LWW coordinate.
  @visibleForTesting
  static Future<void> migrateWebDavSyncTvFamilies(DatabaseExecutor db) async {
    await createWebDavSyncSidecarTables(db);
    await db.rawInsert(
      '''
      INSERT OR IGNORE INTO webdav_sync_record_state
        (kind, owner_key, item_key, updated_at_ms, origin_device_id,
         normalized, deleted, aux)
      SELECT ?, channel_id, '', updated_at, 'migration', 0, 0, NULL
      FROM tv_channels
      ''',
      <Object?>[WebDavSyncLibraryKinds.tvChannels],
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final poolTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      const <Object>['tv_cached_torrents'],
    );
    final cacheStateTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      const <Object>['tv_channel_cache_state'],
    );
    if (poolTable.isEmpty && cacheStateTable.isEmpty) return;
    final pooledChannels = await db.rawQuery(switch ((
      poolTable.isNotEmpty,
      cacheStateTable.isNotEmpty,
    )) {
      (true, true) =>
        'SELECT channel_id FROM tv_cached_torrents '
            'UNION SELECT channel_id FROM tv_channel_cache_state',
      (true, false) =>
        'SELECT channel_id FROM tv_cached_torrents GROUP BY channel_id',
      (false, true) => 'SELECT channel_id FROM tv_channel_cache_state',
      _ => throw StateError('Unreachable TV pool migration state'),
    });
    for (final row in pooledChannels) {
      final channelId = row['channel_id'] as String?;
      if (channelId == null || channelId.isEmpty) continue;
      await db.insert('webdav_sync_record_state', <String, Object?>{
        'kind': WebDavSyncLibraryKinds.tvPoolGeneration,
        'owner_key': channelId,
        'item_key': '',
        'updated_at_ms': now,
        'origin_device_id': 'migration',
        'normalized': 0,
        'deleted': 0,
        'aux': WebDavSyncLibraryMutation.mintTvGenerationId(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// v10: custom-list metadata and every list membership become live
  /// per-record library families. Favorites itself is a permanent built-in
  /// parent, so only its member rows receive migration-origin stamps.
  @visibleForTesting
  static Future<void> migrateWebDavSyncIptvListFamilies(
    DatabaseExecutor db,
  ) async {
    await createIptvStoreTables(db);
    await createWebDavSyncSidecarTables(db);
    await db.rawInsert(
      '''
      INSERT OR IGNORE INTO webdav_sync_record_state
        (kind, owner_key, item_key, updated_at_ms, origin_device_id,
         normalized, deleted, aux)
      SELECT ?, id, '', updated_at, 'migration', 0, 0, NULL
      FROM iptv_lists
      WHERE is_builtin = 0
      ''',
      <Object?>[WebDavSyncLibraryKinds.iptvLists],
    );
    await db.rawInsert(
      '''
      INSERT OR IGNORE INTO webdav_sync_record_state
        (kind, owner_key, item_key, updated_at_ms, origin_device_id,
         normalized, deleted, aux)
      SELECT ?, list_id, url, added_at, 'migration', 0, 0, NULL
      FROM iptv_list_channels
      ''',
      <Object?>[WebDavSyncLibraryKinds.iptvListChannels],
    );
  }

  /// Private v3 library-sync sidecar. The shape is shared with
  /// `iptv_catalog.db`; family-specific rounds populate their own [kind]s.
  static Future<void> createWebDavSyncSidecarTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS webdav_sync_record_state (
        kind TEXT NOT NULL,
        owner_key TEXT NOT NULL,
        item_key TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        origin_device_id TEXT NOT NULL,
        normalized INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        aux TEXT,
        PRIMARY KEY (kind, owner_key, item_key)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS webdav_sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await ensureWebDavSyncMetaDefaults(db);
  }

  static Future<void> ensureWebDavSyncMetaDefaults(DatabaseExecutor db) async {
    await db.execute(
      "INSERT OR IGNORE INTO webdav_sync_meta (key, value) "
      "VALUES ('mutation_revision', '0')",
    );
    await db.execute(
      "INSERT OR IGNORE INTO webdav_sync_meta (key, value) "
      "VALUES ('$webDavTvChangesPendingMetaKey', '0')",
    );
    await db.execute(
      "INSERT OR IGNORE INTO webdav_sync_meta (key, value) "
      "VALUES ('$webDavTvPendingRevisionMetaKey', '0')",
    );
  }

  static Map<String, Object?> _listChannelSnapshotValue(
    Map<String, Object?> row,
  ) {
    final headers = _decodeHeaders(row['http_headers_json']);
    return <String, Object?>{
      'url': row['url'] as String,
      'name': row['name'] as String,
      'logoUrl': row['logo_url'] as String,
      'group': row['channel_group'] as String,
      // Projected to a circle resource ID by the local adapter. This local
      // field never enters the sealed library document.
      'playlistId': row['playlist_id'] as String,
      if (row['channel_number'] is num)
        'channelNumber': (row['channel_number'] as num).toInt(),
      if (row['content_type'] is String) 'contentType': row['content_type'],
      if (row['duration'] is num) 'duration': (row['duration'] as num).toInt(),
      if (headers != null && headers.isNotEmpty) 'httpHeaders': headers,
      'addedAt': (row['added_at'] as num).toInt(),
      'position': (row['position'] as num).toInt(),
    };
  }

  static bool _listChannelPhysicalEquals(
    Map<String, Object?> physical,
    WebDavSyncIptvListChannelTarget target,
  ) {
    final value = target.leaf.value!;
    return physical['name'] == value['name'] &&
        physical['logo_url'] == value['logoUrl'] &&
        physical['channel_group'] == value['group'] &&
        physical['playlist_id'] == target.localSourceId &&
        physical['channel_number'] == value['channelNumber'] &&
        physical['content_type'] == value['contentType'] &&
        physical['duration'] == value['duration'] &&
        physical['added_at'] == value['addedAt'] &&
        physical['position'] == value['position'] &&
        _headersEqual(
          _decodeHeaders(physical['http_headers_json']),
          value['httpHeaders'],
        );
  }

  static Map<String, String>? _decodeHeaders(Object? source) {
    if (source is! String || source.isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      return <String, String>{
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      return null;
    }
  }

  static bool _headersEqual(Map<String, String>? left, Object? right) {
    if (right == null) return left == null || left.isEmpty;
    if (right is! Map || left == null || left.length != right.length) {
      return false;
    }
    for (final entry in right.entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          left[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  static Map<String, Object?> _watchWireValue(Map<String, Object?> row) {
    Map<String, String>? headers;
    final rawHeaders = row['http_headers_json'];
    if (rawHeaders is String && rawHeaders.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawHeaders);
        if (decoded is Map) {
          headers = <String, String>{
            for (final entry in decoded.entries)
              if (entry.key is String && entry.value is String)
                entry.key as String: entry.value as String,
          };
        }
      } catch (_) {
        // A malformed optional header blob remains absent from the sealed
        // value; diagnostics must never echo credential-bearing content.
      }
    }
    return <String, Object?>{
      'url': row['url'] as String,
      'name': row['name'] as String,
      'logoUrl': row['logo_url'] as String,
      'group': row['channel_group'] as String,
      if (headers != null && headers.isNotEmpty) 'headers': headers,
      if (row['series_id'] is String) 'seriesId': row['series_id'],
      if (row['series_name'] is String) 'seriesName': row['series_name'],
      if (row['season'] is num) 'season': (row['season'] as num).toInt(),
      if (row['episode'] is num) 'episode': (row['episode'] as num).toInt(),
      if (row['has_next'] is num)
        'hasNext': (row['has_next'] as num).toInt() != 0,
      'lastPlayedAt': (row['last_played_at'] as num).toInt(),
    };
  }

  static List<String> _decodeStringList(Object? source) {
    if (source is! String || source.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return const <String>[];
      return List<String>.unmodifiable(
        decoded
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );
    } catch (_) {
      return const <String>[];
    }
  }

  static bool _channelKeywordsEqual(
    List<String>? physicalKeywords,
    WebDavSyncTvChannelTarget target,
  ) {
    final keywords = physicalKeywords ?? const <String>[];
    if (keywords.length != target.keywords.length) return false;
    for (var index = 0; index < keywords.length; index++) {
      if (keywords[index] != target.keywords[index]) return false;
    }
    return true;
  }

  /// Insert the built-in Favorites row if it isn't already there.
  ///
  /// MUST be `INSERT OR IGNORE`, never `OR REPLACE`. The database opens with
  /// `PRAGMA foreign_keys = ON`, and REPLACE resolves a conflict by DELETEing
  /// the conflicting row with foreign-key actions firing — which would
  /// cascade through `iptv_list_channels` and wipe every favorite. This runs
  /// from [createIptvStoreTables], i.e. on every open, so that would be a
  /// data-loss-on-launch bug rather than an edge case.
  static Future<void> seedBuiltinList(DatabaseExecutor db) async {
    await db.execute(
      'INSERT OR IGNORE INTO iptv_lists '
      '(id, name, position, is_builtin, created_at, updated_at) '
      'VALUES (?, ?, 0, 1, 0, 0)',
      [favoritesListId, 'Favorites'],
    );
  }
}

import '../models/series_source.dart';
export '../models/series_source.dart';
import 'dart:convert';
import '../models/custom_series_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profiles/profile_preferences.dart';
import 'stremio_service.dart';
import 'webdav_sync/webdav_sync_hot_merge.dart';
import 'webdav_sync/webdav_sync_tombstones.dart';

/// Manages series-to-torrent source bindings (multiple sources per series).
/// Stores in SharedPreferences with key prefix 'series_source_'.
/// Backward compatible: reads old single-source format and migrates to list.
class SeriesSourceService {
  static const String _prefix = 'series_source_';

  /// Get all bound sources for a series, ordered by priority (first = highest).
  static Future<List<SeriesSource>> getSources(
    String imdbId, {
    bool Function()? canContinue,
  }) async {
    _ensureCurrent(canContinue);
    final prefs = await ProfilePreferences.instance();
    _ensureCurrent(canContinue);
    final raw = prefs.getString('$_prefix$imdbId');
    if (raw == null) {
      final custom = CustomSeriesIdentity.parse(imdbId);
      if (custom == null) return [];
      final addon = await StremioService.instance.addonForCustomProgress(
        imdbId,
      );
      _ensureCurrent(canContinue);
      final bindingKey = addon?.sourceBindingKey ?? custom.addonKey;
      // Old releases stored custom pins in the IMDb bucket, but already saved
      // their exact catalog/configuration scope. Move only proven matches.
      final migrated = <SeriesSource>[];
      for (final key
          in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        final oldId = key.substring(_prefix.length);
        if (CustomSeriesIdentity.isCustom(oldId)) continue;
        final matches = (await getSources(oldId, canContinue: canContinue))
            .where(
              (s) => s.matchesCatalogScope(
                catalogId: custom.catalogId,
                catalogKey: bindingKey,
              ),
            )
            .toList();
        for (final source in matches) {
          if (!migrated.any((s) => s.bindingKey == source.bindingKey)) {
            migrated.add(source);
          }
        }
      }
      if (migrated.isEmpty) return [];
      await _saveSources(prefs, imdbId, migrated, canContinue: canContinue);
      _ensureCurrent(canContinue);
      for (final key
          in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        final oldId = key.substring(_prefix.length);
        if (CustomSeriesIdentity.isCustom(oldId)) continue;
        for (final source
            in (await getSources(oldId, canContinue: canContinue))
                .where(
                  (s) => s.matchesCatalogScope(
                    catalogId: custom.catalogId,
                    catalogKey: bindingKey,
                  ),
                )
                .toList()) {
          await removeSourceEntry(oldId, source, canContinue: canContinue);
          _ensureCurrent(canContinue);
        }
      }
      return migrated;
    }
    try {
      final decoded = jsonDecode(raw);
      // New format: JSON array
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((j) => SeriesSource.fromJson(j))
            .toList();
      }
      // Old format: single JSON object — migrate
      if (decoded is Map<String, dynamic>) {
        final source = SeriesSource.fromJson(decoded);
        // Auto-migrate to list format
        await _saveSources(prefs, imdbId, [source], canContinue: canContinue);
        _ensureCurrent(canContinue);
        return [source];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Get the first (highest priority) source. Convenience for quick checks.
  static Future<SeriesSource?> getSource(String imdbId) async {
    final sources = await getSources(imdbId);
    return sources.isEmpty ? null : sources.first;
  }

  /// Add a source to the list (appends at end = lowest priority).
  /// Hash-backed sources dedupe exactly as before. Provider-native cloud
  /// sources dedupe by provider + kind + stable provider id.
  static Future<void> addSource(
    String imdbId,
    SeriesSource source, {
    bool Function()? canContinue,
  }) async {
    _ensureCurrent(canContinue);
    final prefs = await ProfilePreferences.instance();
    _ensureCurrent(canContinue);
    final sources = await getSources(imdbId, canContinue: canContinue);
    _ensureCurrent(canContinue);
    // Replace if the same stable binding already exists.
    final existingIdx = sources.indexWhere(
      (s) => s.bindingKey == source.bindingKey,
    );
    if (existingIdx >= 0) {
      sources[existingIdx] = source;
    } else {
      sources.add(source);
    }
    await _saveSources(prefs, imdbId, sources, canContinue: canContinue);
  }

  /// Remove a specific source by torrentHash.
  static Future<void> removeSourceByHash(
    String imdbId,
    String torrentHash,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final sources = await getSources(imdbId);
    final removed = sources
        .where((source) => source.torrentHash == torrentHash)
        .toList(growable: false);
    await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
      removed
          .where((source) => !source.isLocal)
          .map(
            (source) => WebDavSyncRecordKey.source(imdbId, source.bindingKey),
          ),
    );
    sources.removeWhere((source) => source.torrentHash == torrentHash);
    if (sources.isEmpty) {
      await prefs.remove('$_prefix$imdbId');
    } else {
      await _saveSources(prefs, imdbId, sources);
    }
  }

  /// Remove one exact source, including a provider-native source with no hash.
  static Future<void> removeSourceEntry(
    String imdbId,
    SeriesSource source, {
    bool Function()? canContinue,
  }) async {
    _ensureCurrent(canContinue);
    final prefs = await ProfilePreferences.instance();
    _ensureCurrent(canContinue);
    final sources = await getSources(imdbId, canContinue: canContinue);
    _ensureCurrent(canContinue);
    final removed = sources.where(
      (candidate) => candidate.bindingKey == source.bindingKey,
    );
    await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
      removed
          .where((source) => !source.isLocal)
          .map(
            (candidate) =>
                WebDavSyncRecordKey.source(imdbId, candidate.bindingKey),
          ),
    );
    _ensureCurrent(canContinue);
    sources.removeWhere((s) => s.bindingKey == source.bindingKey);
    if (sources.isEmpty) {
      await _guardedWrite(canContinue, () => prefs.remove('$_prefix$imdbId'));
    } else {
      await _saveSources(prefs, imdbId, sources, canContinue: canContinue);
    }
  }

  /// Remove all sources for a series.
  static Future<void> removeAllSources(String imdbId) async {
    final prefs = await ProfilePreferences.instance();
    final sources = await getSources(imdbId);
    await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
      sources
          .where((source) => !source.isLocal)
          .map(
            (source) => WebDavSyncRecordKey.source(imdbId, source.bindingKey),
          ),
    );
    await prefs.remove('$_prefix$imdbId');
  }

  /// Replace the entire source list (for reordering).
  static Future<void> setSources(
    String imdbId,
    List<SeriesSource> sources, {
    bool Function()? canContinue,
  }) async {
    _ensureCurrent(canContinue);
    final prefs = await ProfilePreferences.instance();
    _ensureCurrent(canContinue);
    final existing = await getSources(imdbId, canContinue: canContinue);
    _ensureCurrent(canContinue);
    final retained = sources.map((source) => source.bindingKey).toSet();
    await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
      existing
          .where(
            (source) =>
                !source.isLocal && !retained.contains(source.bindingKey),
          )
          .map(
            (source) => WebDavSyncRecordKey.source(imdbId, source.bindingKey),
          ),
    );
    _ensureCurrent(canContinue);
    if (sources.isEmpty) {
      await _guardedWrite(canContinue, () => prefs.remove('$_prefix$imdbId'));
    } else {
      await _saveSources(prefs, imdbId, sources, canContinue: canContinue);
    }
  }

  /// Check if any sources are bound.
  static Future<bool> hasSource(String imdbId) async {
    final sources = await getSources(imdbId);
    return sources.isNotEmpty;
  }

  // Keep old setSource/removeSource for backward compatibility during transition
  /// @deprecated Use addSource instead.
  static Future<void> setSource(String imdbId, SeriesSource source) =>
      addSource(imdbId, source);

  /// @deprecated Use removeAllSources instead.
  static Future<void> removeSource(String imdbId) => removeAllSources(imdbId);

  static Future<void> _saveSources(
    SharedPreferences prefs,
    String imdbId,
    List<SeriesSource> sources, {
    bool Function()? canContinue,
  }) async {
    final jsonList = sources.map((s) => s.toJson()).toList();
    await _guardedWrite(
      canContinue,
      () => prefs.setString('$_prefix$imdbId', jsonEncode(jsonList)),
    );
  }

  static void _ensureCurrent(bool Function()? canContinue) {
    if (canContinue != null && !canContinue()) {
      throw StateError('Saved-source operation belongs to a retired session');
    }
  }

  static Future<void> _guardedWrite(
    bool Function()? canContinue,
    Future<bool> Function() write,
  ) async {
    if (canContinue == null) {
      await write();
      return;
    }
    await ProfilePreferences.synchronizeExternalMutation(() async {
      // Recheck after waiting for a snapshot; the nested preference setter
      // retains its own current-profile checks and mutation accounting.
      _ensureCurrent(canContinue);
      await write();
    }, marksMutation: false);
  }
}

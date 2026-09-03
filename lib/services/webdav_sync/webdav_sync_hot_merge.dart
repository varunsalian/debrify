import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'webdav_sync_codec.dart';
import 'webdav_sync_hot_models.dart';
import '../playlist_dedupe_key.dart';

abstract final class WebDavSyncRecordKey {
  static String playback(String alias) => 'playback/record/${_part(alias)}';

  static String playbackMeta(String alias) => 'playback/meta/${_part(alias)}';

  static String playbackEpisode(String alias, int season, int episode) =>
      'playback/episode/${_part(alias)}/$season/$episode';

  static String playbackFinished(String alias, int season, int episode) =>
      'playback/finished/${_part(alias)}/$season/$episode';

  static String continueWatching(String imdbId) =>
      'continue/${_part(_normalizedId(imdbId))}';

  static String source(String imdbId, String bindingKey) =>
      'source/${_part(_normalizedId(imdbId))}/${_part(bindingKey)}';

  static String sourceOrder(String imdbId) =>
      'source/${_part(_normalizedId(imdbId))}';

  static String finishedMovie(String imdbId) =>
      'completion/movie/${_part(_normalizedId(imdbId))}';

  static String explicitlyWatchedSeries(String imdbId) =>
      'completion/series/${_part(_normalizedId(imdbId))}';

  static String playlistItem(String dedupeKey) =>
      'playlist/item/${_part(dedupeKey)}';

  static String playlistFavorite(String dedupeKey) =>
      'playlist/favorite/${_part(dedupeKey)}';

  static const String playlistOrder = 'playlist/items';
  static const String playlistFavoriteOrder = 'playlist/favorites';

  static String _part(String value) =>
      base64UrlEncode(utf8.encode(value)).replaceAll('=', '');

  static String decodePart(String value) {
    final padding = '=' * ((4 - value.length % 4) % 4);
    try {
      return utf8.decode(base64Url.decode('$value$padding'));
    } on FormatException {
      throw const FormatException('Invalid WebDAV sync record key');
    }
  }

  /// Converts deletion keys captured from local state into their wire form.
  /// A local-file series binding has no portable record, so publishing its
  /// key would only disclose the encoded device path.
  static String? projectLocalTombstoneKey(
    String key,
    WebDavSyncIdentityMaps identityMaps,
  ) {
    final parts = key.split('/');
    if (parts.length == 3 && parts[0] == 'source') {
      final binding = decodePart(parts[2]);
      if (binding.startsWith('local:')) return null;
      final wireBinding = identityMaps.seriesBindingToWire(binding);
      return source(decodePart(parts[1]), wireBinding);
    }
    if (parts.length == 3 &&
        parts[0] == 'playlist' &&
        (parts[1] == 'item' || parts[1] == 'favorite')) {
      final dedupe = decodePart(parts[2]);
      final wireDedupe = identityMaps.playlistDedupeToWire(dedupe);
      return parts[1] == 'item'
          ? playlistItem(wireDedupe)
          : playlistFavorite(wireDedupe);
    }
    return key;
  }

  static String _normalizedId(String value) => value.trim().toLowerCase();
}

final class WebDavSyncIdentityMaps {
  WebDavSyncIdentityMaps({
    required Map<String, String> circleToLocalProfiles,
    required Map<String, String> circleToLocalResources,
  }) : circleToLocalProfiles = Map<String, String>.unmodifiable(
         circleToLocalProfiles,
       ),
       circleToLocalResources = Map<String, String>.unmodifiable(
         circleToLocalResources,
       ),
       localToCircleProfiles = _reverse(circleToLocalProfiles, 'profile'),
       localToCircleResources = _reverse(circleToLocalResources, 'resource') {
    if (circleToLocalProfiles.isEmpty) {
      throw ArgumentError('WebDAV sync requires at least one profile mapping');
    }
    for (final id in <String>{
      ...circleToLocalProfiles.keys,
      ...circleToLocalResources.keys,
    }) {
      if (!_safeCircleId.hasMatch(id)) {
        throw ArgumentError.value(id, 'circleId', 'Invalid circle identity');
      }
    }
    if (circleToLocalProfiles.values.any((value) => value.trim().isEmpty) ||
        circleToLocalResources.values.any((value) => value.trim().isEmpty)) {
      throw ArgumentError('WebDAV sync local mappings cannot be empty');
    }
    if (localToCircleProfiles.keys.any(localToCircleResources.containsKey)) {
      throw ArgumentError('WebDAV sync profile and resource mappings overlap');
    }
    if (circleToLocalProfiles.keys.any(circleToLocalResources.containsKey)) {
      throw ArgumentError(
        'WebDAV sync circle identities overlap across mapping types',
      );
    }
    final localIds = <String>{
      ...localToCircleProfiles.keys,
      ...localToCircleResources.keys,
    };
    if (circleToLocalProfiles.keys.any(localIds.contains) ||
        circleToLocalResources.keys.any(localIds.contains)) {
      throw ArgumentError(
        'WebDAV sync wire and local identity spaces must be disjoint',
      );
    }
    localResourceBindingToCircle = _hashedMappings(localToCircleResources);
    circleResourceBindingToLocal = _hashedMappings(circleToLocalResources);
    _toWireReplacements = _IdentityReplacements(<String, String>{
      ...localToCircleProfiles,
      ...localToCircleResources,
      ...localResourceBindingToCircle,
    });
    _toLocalReplacements = _IdentityReplacements(<String, String>{
      ...circleToLocalProfiles,
      ...circleToLocalResources,
      ...circleResourceBindingToLocal,
    });
    _localIdentityTokens = Set<String>.unmodifiable(
      _toWireReplacements.exact.keys,
    );
    _localCompositeIdentityTokens = Set<String>.unmodifiable(
      _localIdentityTokens.map((id) => id.toLowerCase()),
    );
    _longestLocalIdentity = _localIdentityTokens.fold<int>(
      0,
      (longest, id) => max(longest, id.length),
    );
    _longestLocalCompositeIdentity = _localCompositeIdentityTokens.fold<int>(
      0,
      (longest, id) => max(longest, id.length),
    );
  }

  final Map<String, String> circleToLocalProfiles;
  final Map<String, String> circleToLocalResources;
  final Map<String, String> localToCircleProfiles;
  final Map<String, String> localToCircleResources;
  late final Map<String, String> localResourceBindingToCircle;
  late final Map<String, String> circleResourceBindingToLocal;
  late final _IdentityReplacements _toWireReplacements;
  late final _IdentityReplacements _toLocalReplacements;
  late final Set<String> _localIdentityTokens;
  late final Set<String> _localCompositeIdentityTokens;
  late final int _longestLocalIdentity;
  late final int _longestLocalCompositeIdentity;

  Object? toWire(Object? value) => _rewrite(value, _toWireReplacements);

  Object? toLocal(Object? value) => _rewrite(value, _toLocalReplacements);

  String playlistDedupeToWire(String key) {
    var rewritten = key;
    for (final entry in localToCircleResources.entries) {
      rewritten = rewritten.replaceFirst(
        'server:${entry.key.toLowerCase()}|',
        'server:${entry.value.toLowerCase()}|',
      );
    }
    return rewritten;
  }

  String playlistDedupeToLocal(String key) {
    var rewritten = key;
    for (final entry in circleToLocalResources.entries) {
      rewritten = rewritten.replaceFirst(
        'server:${entry.key.toLowerCase()}|',
        'server:${entry.value.toLowerCase()}|',
      );
    }
    return rewritten;
  }

  String seriesBindingToWire(String key) =>
      _rewriteSeriesBinding(key, localResourceBindingToCircle);

  String seriesBindingToLocal(String key) =>
      _rewriteSeriesBinding(key, circleResourceBindingToLocal);

  void assertContainsNoLocalIds(Object? value) {
    // Inspect the JSON-shaped object directly. Serializing the complete graph
    // and searching it once per identity made a large bootstrap O(bytes × IDs)
    // and could pin Flutter's UI isolate for long enough to trigger an ANR.
    final pending = <Object?>[value];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (current == null || current is bool || current is int) continue;
      if (current is double) {
        if (!current.isFinite) {
          throw const FormatException('Non-finite WebDAV sync number');
        }
        continue;
      }
      if (current is String) {
        _assertStringContainsNoLocalIds(current);
        continue;
      }
      if (current is List) {
        pending.addAll(current);
        continue;
      }
      if (current is Map) {
        for (final entry in current.entries) {
          final key = entry.key;
          if (key is! String) {
            throw const FormatException('WebDAV sync maps require string keys');
          }
          _assertStringContainsNoLocalIds(key);
          pending.add(entry.value);
        }
        continue;
      }
      throw const FormatException('Unsupported WebDAV sync JSON value');
    }
  }

  void _assertStringContainsNoLocalIds(String value) {
    if (value.length <= _longestLocalIdentity &&
        _localIdentityTokens.contains(value)) {
      throw StateError('A local identity remained in WebDAV sync payload');
    }

    const prefix = 'server:';
    var searchFrom = 0;
    while (searchFrom < value.length) {
      final prefixIndex = value.indexOf(prefix, searchFrom);
      if (prefixIndex < 0) return;
      final identityStart = prefixIndex + prefix.length;
      final scanEnd = min(
        value.length,
        identityStart + _longestLocalCompositeIdentity + 1,
      );
      for (var cursor = identityStart; cursor < scanEnd; cursor++) {
        if (value.codeUnitAt(cursor) != 0x7c) continue; // |
        if (_localCompositeIdentityTokens.contains(
          value.substring(identityStart, cursor),
        )) {
          throw StateError(
            'A composite local resource identity remained in WebDAV sync payload',
          );
        }
        break;
      }
      // Search from the candidate body so a nested `server:` token is not
      // skipped when malformed input has no nearby delimiter.
      searchFrom = identityStart;
    }
  }

  static Map<String, String> _reverse(
    Map<String, String> source,
    String label,
  ) {
    final result = <String, String>{};
    for (final entry in source.entries) {
      if (result.putIfAbsent(entry.value, () => entry.key) != entry.key) {
        throw ArgumentError('WebDAV sync $label map is not one-to-one');
      }
    }
    return Map<String, String>.unmodifiable(result);
  }

  static Map<String, String> _hashedMappings(Map<String, String> source) =>
      Map<String, String>.unmodifiable(<String, String>{
        for (final entry in source.entries)
          _digest(entry.key): _digest(entry.value),
      });

  static String _digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static String _rewriteSeriesBinding(
    String value,
    Map<String, String> replacements,
  ) {
    const prefix = 'direct:';
    if (!value.startsWith(prefix)) return value;
    final separator = value.indexOf(':', prefix.length);
    if (separator < 0) return value;
    final binding = value.substring(prefix.length, separator);
    final replacement = replacements[binding];
    return replacement == null
        ? value
        : '$prefix$replacement${value.substring(separator)}';
  }

  static Object? _rewrite(Object? value, _IdentityReplacements replacements) {
    if (value is String) {
      final exact = value.length <= replacements.longestExact
          ? replacements.exact[value]
          : null;
      if (exact != null) return exact;
      final trimmed = value.trimLeft();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          final decoded = jsonDecode(value);
          return WebDavSyncCodec.canonicalJson(_rewrite(decoded, replacements));
        } on FormatException {
          return _rewriteCompositeResourceId(value, replacements);
        }
      }
      return _rewriteCompositeResourceId(value, replacements);
    }
    if (value is List<String>) {
      return <String>[
        for (final item in value) _rewrite(item, replacements)! as String,
      ];
    }
    if (value is List) {
      return <Object?>[for (final item in value) _rewrite(item, replacements)];
    }
    if (value is Map) {
      final rewritten = <String, Object?>{};
      for (final entry in value.entries) {
        final originalKey = entry.key.toString();
        final key =
            replacements.exact[originalKey] ??
            _rewriteCompositeResourceId(originalKey, replacements);
        if (rewritten.containsKey(key)) {
          throw StateError('WebDAV sync identity rewrite caused a key clash');
        }
        rewritten[key] = _rewrite(entry.value, replacements);
      }
      return rewritten;
    }
    return value;
  }

  static String _rewriteCompositeResourceId(
    String value,
    _IdentityReplacements replacements,
  ) {
    const prefix = 'server:';
    var searchFrom = 0;
    var copiedThrough = 0;
    StringBuffer? output;
    while (searchFrom < value.length) {
      final prefixIndex = value.indexOf(prefix, searchFrom);
      if (prefixIndex < 0) break;
      final identityStart = prefixIndex + prefix.length;
      final scanEnd = min(
        value.length,
        identityStart + replacements.longestComposite + 1,
      );
      var delimiter = -1;
      for (var cursor = identityStart; cursor < scanEnd; cursor++) {
        if (value.codeUnitAt(cursor) == 0x7c) {
          delimiter = cursor;
          break;
        }
      }
      if (delimiter >= 0) {
        final replacement =
            replacements.composite[value.substring(identityStart, delimiter)];
        if (replacement != null) {
          output ??= StringBuffer();
          output
            ..write(value.substring(copiedThrough, identityStart))
            ..write(replacement);
          copiedThrough = delimiter;
          searchFrom = delimiter + 1;
          continue;
        }
      }
      searchFrom = identityStart;
    }
    if (output == null) return value;
    output.write(value.substring(copiedThrough));
    return output.toString();
  }
}

final class _IdentityReplacements {
  factory _IdentityReplacements(Map<String, String> source) {
    final exact = Map<String, String>.unmodifiable(source);
    final composite = <String, String>{};
    for (final entry in exact.entries) {
      // Preserve the former ordered replaceAll behavior if malformed legacy
      // IDs differ only by case: the first mapping owns the lowercase token.
      composite.putIfAbsent(
        entry.key.toLowerCase(),
        () => entry.value.toLowerCase(),
      );
    }
    return _IdentityReplacements._(
      exact: exact,
      composite: Map<String, String>.unmodifiable(composite),
      longestExact: exact.keys.fold<int>(
        0,
        (longest, id) => max(longest, id.length),
      ),
      longestComposite: composite.keys.fold<int>(
        0,
        (longest, id) => max(longest, id.length),
      ),
    );
  }

  const _IdentityReplacements._({
    required this.exact,
    required this.composite,
    required this.longestExact,
    required this.longestComposite,
  });

  final Map<String, String> exact;
  final Map<String, String> composite;
  final int longestExact;
  final int longestComposite;
}

final class WebDavSyncBuildInput {
  const WebDavSyncBuildInput({
    required this.circleProfileId,
    required this.deviceId,
    required this.rawPreferences,
    required this.portablePreferences,
    required this.identityMaps,
    required this.localNowMs,
    required this.clockOffsetMs,
    required this.serverNowMs,
    this.previous,
  });

  final String circleProfileId;
  final String deviceId;
  final Map<String, Object?> rawPreferences;
  final Map<String, Object?> portablePreferences;
  final WebDavSyncIdentityMaps identityMaps;
  final int localNowMs;
  final int clockOffsetMs;
  final int serverNowMs;
  final WebDavSyncHotDocument? previous;
}

final class WebDavSyncBuiltHotState {
  const WebDavSyncBuiltHotState({
    required this.document,
    required this.localRichRecords,
    required this.protectedPreferenceKeys,
  });

  final WebDavSyncHotDocument document;
  final Map<String, Object?> localRichRecords;

  /// Raw values that are local-only or whose portable projection was
  /// null/malformed. An empty remote projection must not erase them merely
  /// because they were omitted.
  final Set<String> protectedPreferenceKeys;
}

final class WebDavSyncMergeResult {
  const WebDavSyncMergeResult({
    required this.document,
    required this.tombstones,
  });

  final WebDavSyncHotDocument document;
  final Map<String, WebDavSyncTombstone> tombstones;
}

abstract final class WebDavSyncHotMerge {
  static const String playbackPreference = 'playback_state_v1';
  static const String continueWatchingPreference = 'continue_watching_v1';
  static const String finishedMoviesPreference = 'finished_movies_v1';
  static const String explicitlyWatchedSeriesPreference =
      'explicitly_watched_series_v1';
  static const String playlistPreference = 'user_playlist_v1';
  static const String playlistFavoritesPreference = 'playlist_favorites_v1';
  static const String seriesSourcePrefix = 'series_source_';

  /// Per-device cursor used by MDBList's incremental polling loop.
  ///
  /// It remains portable through explicit backup/restore, but recurring
  /// WebDAV sync must not let an automatic cursor write advance the shared
  /// scalar-settings timestamp or replace another device's cursor.
  static const String mdblistSyncCheckpointPreference =
      'mdblist_sync_checkpoint_v1';

  static const Set<String> _specialKeys = <String>{
    playbackPreference,
    continueWatchingPreference,
    finishedMoviesPreference,
    explicitlyWatchedSeriesPreference,
    playlistPreference,
    playlistFavoritesPreference,
  };

  static const Set<String> _hotLocalOnlyScalarKeys = <String>{
    mdblistSyncCheckpointPreference,
  };

  /// Preference keys consumed locally by the hot builder but never synced.
  static Set<String> get hotLocalOnlyScalarKeys => _hotLocalOnlyScalarKeys;

  static WebDavSyncBuiltHotState build(WebDavSyncBuildInput input) {
    final previous = input.previous;
    if (previous != null && previous.circleProfileId != input.circleProfileId) {
      throw StateError('WebDAV sync baseline belongs to another profile');
    }
    WebDavSyncStamp stamp([int? rawTime]) {
      final local = rawTime == null || rawTime < 0 ? input.localNowMs : rawTime;
      final adjusted = local + input.clockOffsetMs;
      return WebDavSyncStamp(
        normalizedTimeMs: min(max(0, adjusted), input.serverNowMs),
        originDeviceId: input.deviceId,
      );
    }

    final scalarValues = <String, Object>{};
    final scalarEntries = <String, WebDavSyncStampedValue>{};
    final protected = <String>{};
    for (final entry in input.rawPreferences.entries) {
      if (_hotLocalOnlyScalarKeys.contains(entry.key) ||
          !input.portablePreferences.containsKey(entry.key) ||
          input.portablePreferences[entry.key] == null) {
        protected.add(entry.key);
      }
    }
    for (final entry in input.portablePreferences.entries) {
      if (entry.value == null ||
          _hotLocalOnlyScalarKeys.contains(entry.key) ||
          _specialKeys.contains(entry.key) ||
          entry.key.startsWith(seriesSourcePrefix)) {
        continue;
      }
      final wire = input.identityMaps.toWire(entry.value);
      if (wire is bool ||
          wire is int ||
          wire is double && wire.isFinite ||
          wire is String ||
          wire is List<String>) {
        scalarValues[entry.key] = wire as Object;
      } else {
        throw FormatException('Unsupported portable preference ${entry.key}');
      }
      final old = previous?.scalars.entries[entry.key];
      scalarEntries[entry.key] = WebDavSyncStampedValue(
        stamp: old != null && _equalJson(old.value, wire) ? old.stamp : stamp(),
        value: wire,
      );
    }
    input.identityMaps.assertContainsNoLocalIds(scalarValues);
    final scalarDigest = semanticDigestOf(scalarValues);

    final portableRecords = <String, Object?>{};
    final richRecords = <String, Object?>{};
    final intrinsicTimes = <String, int?>{};
    final orderKeys = <String, List<String>>{};
    final playlistDedupeMap = <String, String>{};

    _flattenPlayback(
      input.portablePreferences[playbackPreference],
      portableRecords,
      intrinsicTimes,
    );
    _flattenPlayback(
      input.rawPreferences[playbackPreference],
      richRecords,
      <String, int?>{},
    );
    _flattenContinueWatching(
      input.portablePreferences[continueWatchingPreference],
      portableRecords,
      intrinsicTimes,
    );
    _flattenContinueWatching(
      input.rawPreferences[continueWatchingPreference],
      richRecords,
      <String, int?>{},
    );
    _flattenMembership(
      input.portablePreferences[finishedMoviesPreference],
      WebDavSyncRecordKey.finishedMovie,
      portableRecords,
    );
    _flattenMembership(
      input.portablePreferences[explicitlyWatchedSeriesPreference],
      WebDavSyncRecordKey.explicitlyWatchedSeries,
      portableRecords,
    );
    _flattenSeriesSources(
      input.portablePreferences,
      portableRecords,
      intrinsicTimes,
      orderKeys,
      input.identityMaps,
      retainLocalValue: false,
    );
    _flattenSeriesSources(
      input.rawPreferences,
      richRecords,
      <String, int?>{},
      <String, List<String>>{},
      input.identityMaps,
      retainLocalValue: true,
    );
    _flattenPlaylist(
      input.portablePreferences[playlistPreference],
      portableRecords,
      orderKeys,
      input.identityMaps,
      playlistDedupeMap,
      retainLocalValue: false,
    );
    _flattenPlaylist(
      input.rawPreferences[playlistPreference],
      richRecords,
      <String, List<String>>{},
      input.identityMaps,
      playlistDedupeMap,
      retainLocalValue: true,
    );
    _flattenPlaylistFavorites(
      input.portablePreferences[playlistFavoritesPreference],
      portableRecords,
      orderKeys,
      input.identityMaps,
      playlistDedupeMap,
    );

    final wireRecords = <String, WebDavSyncStampedValue>{};
    for (final entry in portableRecords.entries) {
      final wireValue = input.identityMaps.toWire(entry.value);
      input.identityMaps.assertContainsNoLocalIds(wireValue);
      final old = previous?.watchState.records[entry.key];
      final unchanged = old != null && _equalJson(old.value, wireValue);
      wireRecords[entry.key] = WebDavSyncStampedValue(
        stamp: unchanged ? old.stamp : stamp(intrinsicTimes[entry.key]),
        value: wireValue,
      );
    }

    final orders = <String, WebDavSyncOrderValue>{};
    for (final entry in orderKeys.entries) {
      final old = previous?.watchState.orders[entry.key];
      final unchanged = old != null && _equalLists(old.keys, entry.value);
      orders[entry.key] = WebDavSyncOrderValue(
        stamp: unchanged ? old.stamp : stamp(),
        keys: List<String>.unmodifiable(entry.value),
      );
    }
    final semanticPayload = <String, Object?>{
      'records': <String, Object?>{
        for (final entry in wireRecords.entries)
          entry.key: entry.value.toJson(),
      },
      'orders': <String, Object?>{
        for (final entry in orders.entries) entry.key: entry.value.toJson(),
      },
    };
    final watchDigest = semanticDigestOf(semanticPayload);
    final watchStamp = previous?.watchState.semanticDigest == watchDigest
        ? previous!.watchState.stamp
        : _newestStamp(<WebDavSyncStamp>[
            stamp(),
            ...wireRecords.values.map((entry) => entry.stamp),
            ...orders.values.map((entry) => entry.stamp),
          ]);
    final document = WebDavSyncHotDocument(
      circleProfileId: input.circleProfileId,
      scalars: WebDavSyncScalarPart(
        semanticDigest: scalarDigest,
        entries: Map<String, WebDavSyncStampedValue>.unmodifiable(
          scalarEntries,
        ),
      ),
      watchState: WebDavSyncWatchPart(
        stamp: watchStamp,
        semanticDigest: watchDigest,
        records: Map<String, WebDavSyncStampedValue>.unmodifiable(wireRecords),
        orders: Map<String, WebDavSyncOrderValue>.unmodifiable(orders),
      ),
    );
    input.identityMaps.assertContainsNoLocalIds(document.toJson());
    return WebDavSyncBuiltHotState(
      document: document,
      localRichRecords: Map<String, Object?>.unmodifiable(richRecords),
      protectedPreferenceKeys: Set<String>.unmodifiable(protected),
    );
  }

  static WebDavSyncMergeResult merge({
    required WebDavSyncHotDocument local,
    required Iterable<WebDavSyncHotDocument> peers,
    required Iterable<WebDavSyncTombstoneDocument> tombstoneDocuments,
    required int nowMs,
    Duration tombstoneHorizon = const Duration(days: 90),
    int? dormantSinceMs,
  }) {
    final peerDocs = peers.toList(growable: false);
    final suppressDormantLocal = dormantSinceMs != null && peerDocs.isNotEmpty;
    final docs = <WebDavSyncHotDocument>[
      if (!suppressDormantLocal ||
          local.scalars.entries.values.any(
            (entry) => entry.stamp.normalizedTimeMs > dormantSinceMs,
          ) ||
          local.watchState.records.values.any(
            (entry) => entry.stamp.normalizedTimeMs > dormantSinceMs,
          ) ||
          local.watchState.orders.values.any(
            (entry) => entry.stamp.normalizedTimeMs > dormantSinceMs,
          ))
        local,
      ...peerDocs,
    ];
    if (docs.any((doc) => doc.circleProfileId != local.circleProfileId) ||
        tombstoneDocuments.any(
          (doc) => doc.circleProfileId != local.circleProfileId,
        )) {
      throw StateError(
        'WebDAV sync profile documents do not share an identity',
      );
    }

    final tombstones = <String, WebDavSyncTombstone>{};
    for (final document in tombstoneDocuments) {
      for (final entry in document.items.entries) {
        final published = entry.value.firstPublishedAtMs;
        if (published != null &&
            nowMs - published >= tombstoneHorizon.inMilliseconds) {
          continue;
        }
        final prior = tombstones[entry.key];
        if (prior == null || _compareTombstone(entry.value, prior) > 0) {
          tombstones[entry.key] = entry.value;
        }
      }
    }
    if (tombstones.length > WebDavSyncLimits.maxTombstonesPerProfile) {
      throw const FormatException(
        'Merged WebDAV sync tombstones exceed their safe limit',
      );
    }

    final scalarValues = <String, WebDavSyncStampedValue>{};
    for (final doc in docs) {
      for (final entry in doc.scalars.entries.entries) {
        // Ignore checkpoints from older clients that published this
        // device-local cursor before it was excluded from hot sync.
        if (_hotLocalOnlyScalarKeys.contains(entry.key)) continue;
        // The former part-level dormant filter now applies to each entry.
        if (suppressDormantLocal &&
            identical(doc, local) &&
            entry.value.stamp.normalizedTimeMs <= dormantSinceMs) {
          continue;
        }
        final prior = scalarValues[entry.key];
        if (prior == null || _compareValue(entry.value, prior) > 0) {
          scalarValues[entry.key] = entry.value;
        }
      }
    }
    if (scalarValues.length > WebDavSyncLimits.maxRecordsPerHotDocument) {
      throw const FormatException(
        'Merged WebDAV sync scalar values exceed their safe limit',
      );
    }
    final scalarDigest = semanticDigestOf(<String, Object>{
      for (final entry in scalarValues.entries)
        entry.key: entry.value.value as Object,
    });

    final records = <String, WebDavSyncStampedValue>{};
    for (final doc in docs) {
      for (final entry in doc.watchState.records.entries) {
        if (suppressDormantLocal &&
            identical(doc, local) &&
            entry.value.stamp.normalizedTimeMs <= dormantSinceMs) {
          continue;
        }
        final prior = records[entry.key];
        if (prior == null || _compareValue(entry.value, prior) > 0) {
          records[entry.key] = entry.value;
        }
      }
    }
    for (final entry in tombstones.entries) {
      final record = records[entry.key];
      if (record != null && _tombstoneBeatsRecord(entry.value, record)) {
        records.remove(entry.key);
      }
    }

    final continueEntries =
        records.entries
            .where((entry) => entry.key.startsWith('continue/'))
            .toList()
          ..sort((left, right) => _compareValue(right.value, left.value));
    for (final entry in continueEntries.skip(50)) {
      records.remove(entry.key);
    }

    final orders = <String, WebDavSyncOrderValue>{};
    for (final doc in docs) {
      for (final entry in doc.watchState.orders.entries) {
        if (suppressDormantLocal &&
            identical(doc, local) &&
            entry.value.stamp.normalizedTimeMs <= dormantSinceMs) {
          continue;
        }
        final prior = orders[entry.key];
        if (prior == null || _compareOrder(entry.value, prior) > 0) {
          orders[entry.key] = entry.value;
        }
      }
    }
    if (records.length + orders.length >
        WebDavSyncLimits.maxRecordsPerHotDocument) {
      throw const FormatException(
        'Merged WebDAV sync watch state exceeds its safe limit',
      );
    }
    final normalizedOrders = <String, WebDavSyncOrderValue>{
      for (final entry in orders.entries)
        entry.key: WebDavSyncOrderValue(
          stamp: entry.value.stamp,
          keys: _completeOrder(entry.key, entry.value.keys, records),
        ),
    };

    final watchPayload = <String, Object?>{
      'records': <String, Object?>{
        for (final entry in records.entries) entry.key: entry.value.toJson(),
      },
      'orders': <String, Object?>{
        for (final entry in normalizedOrders.entries)
          entry.key: entry.value.toJson(),
      },
    };
    final allWatchStamps = <WebDavSyncStamp>[
      ...records.values.map((entry) => entry.stamp),
      ...normalizedOrders.values.map((entry) => entry.stamp),
    ];
    final watchStamp = allWatchStamps.isEmpty
        ? local.watchState.stamp
        : _newestStamp(allWatchStamps);
    return WebDavSyncMergeResult(
      document: WebDavSyncHotDocument(
        circleProfileId: local.circleProfileId,
        scalars: WebDavSyncScalarPart(
          semanticDigest: scalarDigest,
          entries: Map<String, WebDavSyncStampedValue>.unmodifiable(
            scalarValues,
          ),
        ),
        watchState: WebDavSyncWatchPart(
          stamp: watchStamp,
          semanticDigest: semanticDigestOf(watchPayload),
          records: Map<String, WebDavSyncStampedValue>.unmodifiable(records),
          orders: Map<String, WebDavSyncOrderValue>.unmodifiable(
            normalizedOrders,
          ),
        ),
      ),
      tombstones: Map<String, WebDavSyncTombstone>.unmodifiable(tombstones),
    );
  }

  /// Applies the final server-time publication clamp to every timestamp that
  /// will leave this device. Local builders already clamp newly changed data,
  /// but an unchanged record can still be ahead of a temporarily backwards
  /// server clock. Clamping the complete merged result here prevents that
  /// inherited stamp from being echoed into a newly published section.
  static WebDavSyncMergeResult clampForPublication(
    WebDavSyncMergeResult source, {
    required int serverNowMs,
  }) {
    if (serverNowMs < 0 || serverNowMs > WebDavSyncLimits.maxTimestampMs) {
      throw ArgumentError.value(serverNowMs, 'serverNowMs');
    }

    WebDavSyncStamp stamp(WebDavSyncStamp source) => WebDavSyncStamp(
      normalizedTimeMs: min(source.normalizedTimeMs, serverNowMs),
      originDeviceId: source.originDeviceId,
    );

    final records = <String, WebDavSyncStampedValue>{
      for (final entry in source.document.watchState.records.entries)
        entry.key: WebDavSyncStampedValue(
          stamp: stamp(entry.value.stamp),
          value: entry.value.value,
        ),
    };
    final scalarValues = <String, WebDavSyncStampedValue>{
      for (final entry in source.document.scalars.entries.entries)
        entry.key: WebDavSyncStampedValue(
          stamp: stamp(entry.value.stamp),
          value: entry.value.value,
        ),
    };
    final orders = <String, WebDavSyncOrderValue>{
      for (final entry in source.document.watchState.orders.entries)
        entry.key: WebDavSyncOrderValue(
          stamp: stamp(entry.value.stamp),
          keys: entry.value.keys,
        ),
    };
    final watchPayload = <String, Object?>{
      'records': <String, Object?>{
        for (final entry in records.entries) entry.key: entry.value.toJson(),
      },
      'orders': <String, Object?>{
        for (final entry in orders.entries) entry.key: entry.value.toJson(),
      },
    };
    final document = WebDavSyncHotDocument(
      circleProfileId: source.document.circleProfileId,
      scalars: WebDavSyncScalarPart(
        semanticDigest: source.document.scalars.semanticDigest,
        entries: Map<String, WebDavSyncStampedValue>.unmodifiable(scalarValues),
      ),
      watchState: WebDavSyncWatchPart(
        stamp: stamp(source.document.watchState.stamp),
        semanticDigest: semanticDigestOf(watchPayload),
        records: Map<String, WebDavSyncStampedValue>.unmodifiable(records),
        orders: Map<String, WebDavSyncOrderValue>.unmodifiable(orders),
      ),
    );
    final tombstones = <String, WebDavSyncTombstone>{
      for (final entry in source.tombstones.entries)
        entry.key: WebDavSyncTombstone(
          key: entry.value.key,
          stamp: stamp(entry.value.stamp),
          firstPublishedAtMs: entry.value.firstPublishedAtMs == null
              ? null
              : min(entry.value.firstPublishedAtMs!, serverNowMs),
          rawLocalTime: entry.value.rawLocalTime,
        ),
    };
    return WebDavSyncMergeResult(
      document: document,
      tombstones: Map<String, WebDavSyncTombstone>.unmodifiable(tombstones),
    );
  }

  static Map<String, Object> materializePreferences({
    required WebDavSyncHotDocument document,
    required WebDavSyncIdentityMaps identityMaps,
    Map<String, Object?> localRichRecords = const <String, Object?>{},
    Map<String, WebDavSyncStampedValue> localPortableRecords =
        const <String, WebDavSyncStampedValue>{},
    Set<String> protectedPreferenceKeys = const <String>{},
  }) {
    Object? chosen(String key, WebDavSyncStampedValue value) {
      final local = localPortableRecords[key];
      final rich = localRichRecords[key];
      final wire =
          local != null && rich != null && _equalJson(local.value, value.value)
          ? rich
          : identityMaps.toLocal(value.value);
      return wire;
    }

    final output = <String, Object>{
      for (final entry in document.scalars.values.entries)
        if (!_hotLocalOnlyScalarKeys.contains(entry.key))
          entry.key: identityMaps.toLocal(entry.value) as Object,
    };
    final playback = <String, dynamic>{};
    final continueWatching = <Map<String, dynamic>>[];
    final sources = <String, Map<String, Object?>>{};
    final movies = <String>{};
    final series = <String>{};
    final playlist = <String, Map<String, Object?>>{};
    final favorites = <String>{};

    for (final entry in document.watchState.records.entries) {
      final parts = entry.key.split('/');
      if (parts.length >= 3 && parts[0] == 'playback') {
        final alias = WebDavSyncRecordKey.decodePart(parts[2]);
        if (parts[1] == 'record' && parts.length == 3) {
          final value = chosen(entry.key, entry.value);
          if (value is Map) {
            playback[alias] = _playbackBaseWithExistingChildren(
              value,
              playback[alias],
            );
          }
        } else if (parts[1] == 'meta' && parts.length == 3) {
          final value = chosen(entry.key, entry.value);
          if (value is Map) {
            playback[alias] = _playbackBaseWithExistingChildren(
              value,
              playback[alias],
            );
          }
        } else if ((parts[1] == 'episode' || parts[1] == 'finished') &&
            parts.length == 5) {
          final value = chosen(entry.key, entry.value);
          if (value is! Map) continue;
          final record = playback.putIfAbsent(alias, () => <String, dynamic>{});
          final containerKey = parts[1] == 'episode'
              ? 'seasons'
              : 'finishedEpisodes';
          final container =
              (record[containerKey] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          record[containerKey] = container;
          final season =
              (container[parts[3]] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          container[parts[3]] = season;
          season[parts[4]] = Map<String, dynamic>.from(value);
        }
      } else if (parts.length == 2 && parts[0] == 'continue') {
        final value = chosen(entry.key, entry.value);
        if (value is Map) {
          continueWatching.add(Map<String, dynamic>.from(value));
        }
      } else if (parts.length == 3 && parts[0] == 'source') {
        final imdb = WebDavSyncRecordKey.decodePart(parts[1]);
        final binding = WebDavSyncRecordKey.decodePart(parts[2]);
        final value = chosen(entry.key, entry.value);
        if (value is Map) {
          sources.putIfAbsent(imdb, () => <String, Object?>{})[binding] =
              Map<String, dynamic>.from(value);
        }
      } else if (parts.length == 3 && parts[0] == 'completion') {
        final id = WebDavSyncRecordKey.decodePart(parts[2]);
        if (parts[1] == 'movie') movies.add(id);
        if (parts[1] == 'series') series.add(id);
      } else if (parts.length == 3 && parts[0] == 'playlist') {
        final key = WebDavSyncRecordKey.decodePart(parts[2]);
        if (parts[1] == 'item') {
          final value = chosen(entry.key, entry.value);
          if (value is Map) playlist[key] = Map<String, dynamic>.from(value);
        } else if (parts[1] == 'favorite') {
          favorites.add(key);
        }
      }
    }

    if (playback.isNotEmpty ||
        !protectedPreferenceKeys.contains(playbackPreference)) {
      output[playbackPreference] = WebDavSyncCodec.canonicalJson(playback);
    }
    continueWatching.sort(
      (left, right) => (_intValue(right['updatedAt']) ?? 0).compareTo(
        _intValue(left['updatedAt']) ?? 0,
      ),
    );
    if (continueWatching.isNotEmpty ||
        !protectedPreferenceKeys.contains(continueWatchingPreference)) {
      output[continueWatchingPreference] = WebDavSyncCodec.canonicalJson(
        continueWatching.take(50).toList(),
      );
    }
    if (movies.isNotEmpty ||
        !protectedPreferenceKeys.contains(finishedMoviesPreference)) {
      output[finishedMoviesPreference] = movies.toList()..sort();
    }
    if (series.isNotEmpty ||
        !protectedPreferenceKeys.contains(explicitlyWatchedSeriesPreference)) {
      output[explicitlyWatchedSeriesPreference] = series.toList()..sort();
    }

    final sourceIds = <String>{...sources.keys};
    for (final orderKey in document.watchState.orders.keys) {
      final parts = orderKey.split('/');
      if (parts.length == 2 && parts[0] == 'source') {
        sourceIds.add(WebDavSyncRecordKey.decodePart(parts[1]));
      }
    }
    final sortedSourceIds = sourceIds.toList()..sort();
    for (final sourceId in sortedSourceIds) {
      final preferenceKey = '$seriesSourcePrefix$sourceId';
      final records = sources[sourceId] ?? const <String, Object?>{};
      if (records.isEmpty && protectedPreferenceKeys.contains(preferenceKey)) {
        continue;
      }
      final order = document
          .watchState
          .orders[WebDavSyncRecordKey.sourceOrder(sourceId)]
          ?.keys;
      output[preferenceKey] = WebDavSyncCodec.canonicalJson(
        _orderedValues(records, order),
      );
    }
    final playlistOrder =
        document.watchState.orders[WebDavSyncRecordKey.playlistOrder]?.keys;
    if (playlist.isNotEmpty ||
        !protectedPreferenceKeys.contains(playlistPreference)) {
      output[playlistPreference] = WebDavSyncCodec.canonicalJson(
        _orderedValues(playlist, playlistOrder),
      );
    }
    if (favorites.isNotEmpty ||
        !protectedPreferenceKeys.contains(playlistFavoritesPreference)) {
      output[playlistFavoritesPreference] =
          WebDavSyncCodec.canonicalJson(<String, bool>{
            for (final key in favorites)
              _localPlaylistDedupeKey(
                wireKey: key,
                localizedItem: playlist[key],
                identityMaps: identityMaps,
              ): true,
          });
    }
    return output;
  }

  static void _flattenPlayback(
    Object? encoded,
    Map<String, Object?> records,
    Map<String, int?> times,
  ) {
    final decoded = _decodeJsonMap(encoded);
    for (final entry in decoded.entries) {
      if (entry.value is! Map) continue;
      final record = Map<String, dynamic>.from(entry.value as Map);
      final seasons = record.remove('seasons');
      final finished = record.remove('finishedEpisodes');
      if (seasons is Map || finished is Map || record['type'] == 'series') {
        final metaKey = WebDavSyncRecordKey.playbackMeta(entry.key);
        records[metaKey] = record;
        times[metaKey] = _latestNestedTime(entry.value, 'updatedAt');
        _flattenEpisodeMap(entry.key, seasons, records, times, finished: false);
        _flattenEpisodeMap(entry.key, finished, records, times, finished: true);
      } else {
        final key = WebDavSyncRecordKey.playback(entry.key);
        records[key] = record;
        times[key] = _intValue(record['updatedAt']);
      }
    }
  }

  static void _flattenEpisodeMap(
    String alias,
    Object? raw,
    Map<String, Object?> records,
    Map<String, int?> times, {
    required bool finished,
  }) {
    if (raw is! Map) return;
    for (final seasonEntry in raw.entries) {
      final season = int.tryParse(seasonEntry.key.toString());
      if (season == null || season < 0 || seasonEntry.value is! Map) continue;
      for (final episodeEntry in (seasonEntry.value as Map).entries) {
        final episode = int.tryParse(episodeEntry.key.toString());
        if (episode == null || episode < 0 || episodeEntry.value is! Map) {
          continue;
        }
        final value = Map<String, dynamic>.from(episodeEntry.value as Map);
        final key = finished
            ? WebDavSyncRecordKey.playbackFinished(alias, season, episode)
            : WebDavSyncRecordKey.playbackEpisode(alias, season, episode);
        records[key] = value;
        times[key] = _intValue(value[finished ? 'finishedAt' : 'updatedAt']);
      }
    }
  }

  static void _flattenContinueWatching(
    Object? encoded,
    Map<String, Object?> records,
    Map<String, int?> times,
  ) {
    final decoded = _decodeJsonList(encoded);
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final value = Map<String, dynamic>.from(raw);
      final id = value['imdbId']?.toString().trim().toLowerCase() ?? '';
      if (id.isEmpty) continue;
      final key = WebDavSyncRecordKey.continueWatching(id);
      records[key] = value;
      times[key] = _intValue(value['updatedAt']);
    }
  }

  static void _flattenMembership(
    Object? raw,
    String Function(String) keyFor,
    Map<String, Object?> records,
  ) {
    final values = raw is List ? raw : const <Object?>[];
    for (final value in values) {
      final id = value?.toString().trim().toLowerCase() ?? '';
      if (id.isNotEmpty) records[keyFor(id)] = true;
    }
  }

  static void _flattenSeriesSources(
    Map<String, Object?> preferences,
    Map<String, Object?> records,
    Map<String, int?> times,
    Map<String, List<String>> orders,
    WebDavSyncIdentityMaps identityMaps, {
    required bool retainLocalValue,
  }) {
    for (final entry in preferences.entries) {
      if (!entry.key.startsWith(seriesSourcePrefix)) continue;
      final imdb = entry.key.substring(seriesSourcePrefix.length).trim();
      if (imdb.isEmpty) continue;
      final decoded = _decodeJsonList(entry.value);
      final order = <String>[];
      for (final raw in decoded) {
        if (raw is! Map) continue;
        final value = Map<String, dynamic>.from(raw);
        final wireObject = identityMaps.toWire(value);
        if (wireObject is! Map) continue;
        final wireValue = Map<String, dynamic>.from(wireObject);
        final binding = _seriesBindingKey(wireValue);
        if (binding.isEmpty || order.contains(binding)) continue;
        order.add(binding);
        final key = WebDavSyncRecordKey.source(imdb, binding);
        records[key] = retainLocalValue ? value : wireValue;
        times[key] = _intValue(value['boundAt']);
      }
      orders[WebDavSyncRecordKey.sourceOrder(imdb)] = order;
    }
  }

  static void _flattenPlaylist(
    Object? encoded,
    Map<String, Object?> records,
    Map<String, List<String>> orders,
    WebDavSyncIdentityMaps identityMaps,
    Map<String, String> localToWireDedupe, {
    required bool retainLocalValue,
  }) {
    final decoded = _decodeJsonList(encoded);
    final order = <String>[];
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final value = Map<String, dynamic>.from(raw);
      final wireObject = identityMaps.toWire(value);
      if (wireObject is! Map) continue;
      final wireValue = Map<String, dynamic>.from(wireObject);
      identityMaps.assertContainsNoLocalIds(wireValue);
      final localDedupe = PlaylistDedupeKey.compute(value);
      final wireDedupe = PlaylistDedupeKey.compute(wireValue);
      if (localDedupe.isNotEmpty) {
        localToWireDedupe[localDedupe] = wireDedupe;
      }
      if (wireDedupe.isEmpty || order.contains(wireDedupe)) continue;
      order.add(wireDedupe);
      records[WebDavSyncRecordKey.playlistItem(wireDedupe)] = retainLocalValue
          ? value
          : wireValue;
    }
    orders[WebDavSyncRecordKey.playlistOrder] = order;
  }

  static void _flattenPlaylistFavorites(
    Object? encoded,
    Map<String, Object?> records,
    Map<String, List<String>> orders,
    WebDavSyncIdentityMaps identityMaps,
    Map<String, String> localToWireDedupe,
  ) {
    final decoded = _decodeJsonMap(encoded);
    final order = <String>[];
    for (final entry in decoded.entries) {
      if (entry.value != true) continue;
      final wireKey =
          localToWireDedupe[entry.key] ??
          identityMaps.playlistDedupeToWire(entry.key);
      if (wireKey.isEmpty || order.contains(wireKey)) continue;
      order.add(wireKey);
      records[WebDavSyncRecordKey.playlistFavorite(wireKey)] = true;
    }
    orders[WebDavSyncRecordKey.playlistFavoriteOrder] = order;
  }

  static String _localPlaylistDedupeKey({
    required String wireKey,
    required Map<String, Object?>? localizedItem,
    required WebDavSyncIdentityMaps identityMaps,
  }) {
    if (localizedItem != null) {
      final computed = PlaylistDedupeKey.compute(
        Map<String, dynamic>.from(localizedItem),
      );
      if (computed.isNotEmpty) return computed;
    }
    return identityMaps.playlistDedupeToLocal(wireKey);
  }

  static Map<String, dynamic> _playbackBaseWithExistingChildren(
    Map<dynamic, dynamic> base,
    Object? existing,
  ) {
    final result = Map<String, dynamic>.from(base);
    if (existing is Map) {
      for (final key in const <String>{'seasons', 'finishedEpisodes'}) {
        if (!result.containsKey(key) && existing[key] is Map) {
          result[key] = existing[key];
        }
      }
    }
    return result;
  }

  static List<String> _completeOrder(
    String orderKey,
    List<String> preferred,
    Map<String, WebDavSyncStampedValue> records,
  ) {
    late final String prefix;
    if (orderKey == WebDavSyncRecordKey.playlistOrder) {
      prefix = 'playlist/item/';
    } else if (orderKey == WebDavSyncRecordKey.playlistFavoriteOrder) {
      prefix = 'playlist/favorite/';
    } else if (orderKey.startsWith('source/')) {
      prefix = '$orderKey/';
    } else {
      return List<String>.unmodifiable(preferred);
    }
    final available = <String, WebDavSyncStampedValue>{};
    for (final entry in records.entries) {
      if (entry.key.startsWith(prefix)) {
        available[WebDavSyncRecordKey.decodePart(entry.key.split('/').last)] =
            entry.value;
      }
    }
    final result = <String>[
      for (final key in preferred)
        if (available.remove(key) != null) key,
    ];
    final extras = available.entries.toList()
      ..sort((left, right) => _compareValue(right.value, left.value));
    result.addAll(extras.map((entry) => entry.key));
    return List<String>.unmodifiable(result);
  }

  static List<Object?> _orderedValues(
    Map<String, Object?> values,
    List<String>? order,
  ) {
    final remaining = Map<String, Object?>.from(values);
    final result = <Object?>[];
    for (final key in order ?? const <String>[]) {
      if (remaining.containsKey(key)) result.add(remaining.remove(key));
    }
    final extras = remaining.entries.toList()
      ..sort((left, right) {
        final leftTime = left.value is Map
            ? _intValue(
                    (left.value as Map)['boundAt'] ??
                        (left.value as Map)['addedAt'],
                  ) ??
                  0
            : 0;
        final rightTime = right.value is Map
            ? _intValue(
                    (right.value as Map)['boundAt'] ??
                        (right.value as Map)['addedAt'],
                  ) ??
                  0
            : 0;
        final time = rightTime.compareTo(leftTime);
        return time != 0 ? time : left.key.compareTo(right.key);
      });
    result.addAll(extras.map((entry) => entry.value));
    return result;
  }

  static int _compareValue(
    WebDavSyncStampedValue left,
    WebDavSyncStampedValue right,
  ) {
    final stamp = _compareStamp(left.stamp, right.stamp);
    if (stamp != 0) return stamp;
    return semanticDigestOf(
      left.value,
    ).compareTo(semanticDigestOf(right.value));
  }

  static int _compareOrder(
    WebDavSyncOrderValue left,
    WebDavSyncOrderValue right,
  ) {
    final stamp = _compareStamp(left.stamp, right.stamp);
    if (stamp != 0) return stamp;
    return semanticDigestOf(left.keys).compareTo(semanticDigestOf(right.keys));
  }

  static int _compareTombstone(
    WebDavSyncTombstone left,
    WebDavSyncTombstone right,
  ) {
    final stamp = _compareStamp(left.stamp, right.stamp);
    if (stamp != 0) return stamp;
    return semanticDigestOf(
      left.toJson(),
    ).compareTo(semanticDigestOf(right.toJson()));
  }

  static bool _tombstoneBeatsRecord(
    WebDavSyncTombstone tombstone,
    WebDavSyncStampedValue record,
  ) {
    final stamp = _compareStamp(tombstone.stamp, record.stamp);
    if (stamp != 0) return stamp > 0;
    return semanticDigestOf(
          tombstone.toJson(),
        ).compareTo(semanticDigestOf(record.value)) >=
        0;
  }

  static int _compareStamp(WebDavSyncStamp left, WebDavSyncStamp right) {
    final time = left.normalizedTimeMs.compareTo(right.normalizedTimeMs);
    return time != 0
        ? time
        : left.originDeviceId.compareTo(right.originDeviceId);
  }

  static WebDavSyncStamp _newestStamp(Iterable<WebDavSyncStamp> values) =>
      values.reduce(
        (left, right) => _compareStamp(left, right) >= 0 ? left : right,
      );

  static bool _equalJson(Object? left, Object? right) =>
      WebDavSyncCodec.canonicalJson(left) ==
      WebDavSyncCodec.canonicalJson(right);

  static bool _equalLists(List<String> left, List<String> right) =>
      left.length == right.length &&
      Iterable<int>.generate(
        left.length,
      ).every((index) => left[index] == right[index]);

  static int? _intValue(Object? value) => value is num ? value.toInt() : null;

  static Map<String, dynamic> _decodeJsonMap(Object? encoded) {
    if (encoded is! String || encoded.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  static List<dynamic> _decodeJsonList(Object? encoded) {
    if (encoded is! String || encoded.isEmpty) return <dynamic>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is List) return decoded;
      if (decoded is Map) return <dynamic>[decoded];
      return <dynamic>[];
    } on FormatException {
      return <dynamic>[];
    }
  }

  static int? _latestNestedTime(Object? value, String field) {
    int? latest;
    void walk(Object? current) {
      if (current is Map) {
        final raw = current[field];
        if (raw is num && (latest == null || raw.toInt() > latest!)) {
          latest = raw.toInt();
        }
        for (final child in current.values) {
          walk(child);
        }
      } else if (current is List) {
        for (final child in current) {
          walk(child);
        }
      }
    }

    walk(value);
    return latest;
  }

  static String _seriesBindingKey(Map<String, dynamic> source) {
    final hash = source['torrentHash']?.toString() ?? '';
    if (hash.isNotEmpty) return 'hash:$hash';
    final service = source['debridService']?.toString() ?? 'rd';
    if (service == 'local') {
      return 'local:${source['localPath'] ?? source['debridTorrentId'] ?? ''}';
    }
    if (service == 'stremio_direct') {
      return 'direct:${source['addonKey'] ?? ''}:${source['streamKey'] ?? ''}';
    }
    return 'cloud:$service:${source['cloudSourceKind'] ?? ''}:'
        '${source['debridTorrentId'] ?? ''}';
  }
}

final RegExp _safeCircleId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$');

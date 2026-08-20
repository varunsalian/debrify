import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/stremio_addon.dart';
import '../models/profiles/user_profile.dart';
import '../utils/platform_util.dart';
import 'main_page_bridge.dart';
import 'storage_service.dart';
import 'stremio_service.dart';
import 'youtube_service.dart';
import 'profiles/profile_bootstrap.dart';
import 'profiles/profile_lock_controller.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_preferences.dart';
import '../models/profiles/profile_policy.dart';

/// Publishes the Apple TV Home Screen's Top Shelf reel.
///
/// The native extension never starts Flutter. It only reads the small JSON
/// snapshot written through this channel, so its memory, networking, and
/// lifecycle remain isolated from the app itself.
class TvosTopShelfService {
  TvosTopShelfService._();

  static final TvosTopShelfService instance = TvosTopShelfService._();
  static const MethodChannel _channel = MethodChannel('debrify/topshelf');
  static const int _maxCachedPreviews = 3;
  static const int _maxPreviewCandidates = 5;
  static const int _previewHeight = 1080;
  static const int _previewDurationSeconds = 120;
  static const String _previewCacheVersion = 'v1';
  static const String _multiProfileOptInKey =
      'tvos_multi_profile_top_shelf_enabled';

  String? _lastSourceContent;
  String? _lastPublishedContent;
  bool _initialized = false;
  int _publishGeneration = 0;
  Future<void> _previewQueue = Future<void>.value();
  Map<String, dynamic>? _pendingProfileAction;

  Future<void> initialize() async {
    if (!PlatformUtil.isTvOS || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'action') return;
      final raw = call.arguments;
      if (raw is Map) {
        final action = Map<String, dynamic>.from(raw);
        _openTopShelfItem(action);
        await _channel.invokeMethod<void>('clearPendingAction', action);
      }
    });

    try {
      final pending = await _channel.invokeMapMethod<String, dynamic>(
        'takePendingAction',
      );
      if (pending != null) _openTopShelfItem(pending);
    } catch (_) {
      // This is optional system furniture. Even a corrupt platform response
      // must not delay the real app from reaching runApp().
      debugPrint('Top Shelf: pending action unavailable');
    }
  }

  /// Replaces the extension snapshot with up to eight items from the exact
  /// reel currently powering Spotlight on the tvOS Home board.
  Future<void> publishSpotlight(
    List<StremioMeta> items, {
    String? sourceTitle,
  }) async {
    if (!PlatformUtil.isTvOS) return;
    try {
      final content = await _attachProfileAuthority(
        buildSnapshot(items, sourceTitle: sourceTitle),
      );
      if (content == null) {
        await clear();
        return;
      }
      final contentJson = jsonEncode(content);
      if (_lastSourceContent == contentJson) return;
      final generation = ++_publishGeneration;

      // Artwork is immediately useful and must never wait on trailer metadata,
      // YouTube resolution, downloading, or muxing. Preview paths are layered
      // into subsequent snapshots one at a time as their local files become
      // ready; tvOS keeps showing this image-only version in the meantime.
      await _publishSnapshot(content);
      _lastSourceContent = contentJson;

      // Serialize preview work across rapid Home reloads. A stale generation
      // exits before its next expensive operation, while an export already in
      // flight is allowed to finish as a harmless future cache hit.
      _previewQueue = _previewQueue
          .then((_) => _preparePreviews(generation, items, content))
          .catchError((Object _) {
            debugPrint('Top Shelf: preview preparation failed');
          });
    } catch (_) {
      // Top Shelf is optional furniture. A missing entitlement/channel must
      // never interfere with loading or navigating the real Home board.
      debugPrint('Top Shelf: snapshot publish failed');
    }
  }

  Future<void> clear() async {
    _lastSourceContent = null;
    _lastPublishedContent = null;
    _publishGeneration++;
    _pendingProfileAction = null;
    if (!PlatformUtil.isTvOS) return;
    try {
      await _channel.invokeMethod<void>('clear');
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _attachProfileAuthority(
    Map<String, dynamic> source,
  ) async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return source;
    }
    if (!ProfileLockController.instance.isUnlocked) {
      return null;
    }
    final scope = ProfileRuntime.capture();
    final profile = await ProfileBootstrap.registry.getProfile(scope.profileId);
    if (profile == null || !profile.allows(ProfileFeature.incomingLinks)) {
      return null;
    }
    final profiles = await ProfileBootstrap.registry.listProfiles();
    if (profiles.length > 1 &&
        !((await DevicePreferences.instance()).getBool(_multiProfileOptInKey) ??
            false)) {
      return null;
    }
    final revision = DateTime.now().microsecondsSinceEpoch;
    final expiresAt = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    final actions = <String, dynamic>{};
    final decorated = <Map<String, dynamic>>[];
    for (final raw in (source['items'] as List).take(8)) {
      final item = Map<String, dynamic>.from(raw as Map);
      final token = _opaqueToken();
      item['actionToken'] = token;
      actions[token] = <String, dynamic>{
        'ownerProfileId': scope.profileId,
        'profileAuthorizationRevision': profile.authorizationRevision,
        'expiresAtMs': expiresAt,
        'consumed': false,
        'action': <String, dynamic>{
          'imdbId': item['imdbId'],
          'type': item['type'],
          'title': item['title'],
          'posterURL': item['posterURL'],
          'year': item['year'],
        },
      };
      decorated.add(item);
    }
    return <String, dynamic>{
      ...source,
      'version': 2,
      'snapshotRevision': revision,
      'ownerProfileId': scope.profileId,
      'profileAuthorizationRevision': profile.authorizationRevision,
      'privacySafe': false,
      'items': decorated,
      'actions': actions,
    };
  }

  static String _opaqueToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<void> _publishSnapshot(Map<String, dynamic> content) async {
    final canonical = jsonEncode(content);
    if (_lastPublishedContent == canonical) return;
    final snapshot = Map<String, dynamic>.from(content)
      ..['generatedAt'] = DateTime.now().toUtc().toIso8601String();
    await _channel.invokeMethod<void>('publish', jsonEncode(snapshot));
    _lastPublishedContent = canonical;
  }

  Future<void> _preparePreviews(
    int generation,
    List<StremioMeta> metas,
    Map<String, dynamic> baseSnapshot,
  ) async {
    if (generation != _publishGeneration) return;

    bool trailersEnabled;
    bool includeAudio;
    try {
      final preferences = await Future.wait<Object>([
        StorageService.getHomeHeroTrailerEnabled(),
        StorageService.getAmbientTrailerAudioEnabled(
          AmbientTrailerSurface.homeHero,
        ),
      ]);
      trailersEnabled = preferences[0] as bool;
      includeAudio = preferences[1] as bool;
    } catch (_) {
      // Match Home's safe defaults when preferences are temporarily
      // unavailable: trailers and their audio start enabled.
      trailersEnabled = true;
      includeAudio = true;
    }
    if (!trailersEnabled || generation != _publishGeneration) return;

    final metaByImdb = <String, StremioMeta>{};
    for (final meta in metas) {
      final imdbId = _imdbIdOf(meta);
      if (imdbId != null) metaByImdb.putIfAbsent(imdbId, () => meta);
    }

    var snapshot = _copySnapshot(baseSnapshot);
    var prepared = 0;
    var attempted = 0;
    final rawItems = snapshot['items'];
    if (rawItems is! List) return;

    for (final rawItem in rawItems) {
      if (prepared >= _maxCachedPreviews ||
          attempted >= _maxPreviewCandidates ||
          generation != _publishGeneration) {
        break;
      }
      if (rawItem is! Map<String, dynamic>) continue;
      final imdbId = rawItem['imdbId'] as String?;
      final meta = imdbId == null ? null : metaByImdb[imdbId];
      if (imdbId == null || meta == null) continue;
      attempted++;

      try {
        var youtubeId = _validYoutubeId(meta.trailerYtId);
        if (youtubeId == null) {
          final enriched = await StremioService.instance.fetchMetaDetails(
            imdbId: imdbId,
            type: meta.type,
          );
          if (generation != _publishGeneration) return;
          youtubeId = _validYoutubeId(enriched?.trailerYtId);
        }
        if (youtubeId == null) continue;

        final streams = await YoutubeService.resolveStreams(
          youtubeId,
          maxHeightOverride: _previewHeight,
        );
        if (generation != _publishGeneration) return;
        final videoUrl = streams?.playUrl;
        if (videoUrl == null || videoUrl.isEmpty) continue;

        final arguments = <String, dynamic>{
          'cacheKey':
              '$imdbId-$youtubeId-$_previewCacheVersion-'
              '${_previewHeight}p-${_previewDurationSeconds}s-'
              '${includeAudio ? 'audio' : 'silent'}',
          'videoURL': videoUrl,
          if (streams?.audioUrl case final audioUrl?) 'audioURL': audioUrl,
          'includeAudio': includeAudio,
          'maxDurationSeconds': _previewDurationSeconds,
        };
        final previewFile = await _channel.invokeMethod<String>(
          'cachePreview',
          arguments,
        );
        if (generation != _publishGeneration) return;
        if (previewFile == null || !isValidPreviewPath(previewFile)) continue;

        snapshot = withPreviewFile(snapshot, imdbId, previewFile);
        await _publishSnapshot(snapshot);
        prepared++;
      } catch (_) {
        // One unavailable/restricted trailer must not prevent later titles in
        // the reel from receiving previews.
        debugPrint('Top Shelf: preview unavailable');
      }
    }
  }

  static String? _validYoutubeId(String? raw) {
    final value = raw?.trim();
    if (value == null || !RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(value)) {
      return null;
    }
    return value;
  }

  @visibleForTesting
  static bool isValidPreviewPath(String value) => RegExp(
    r'^Library/Caches/TopShelfPreviews/[A-Za-z0-9._-]+\.mp4$',
  ).hasMatch(value);

  @visibleForTesting
  static Map<String, dynamic> withPreviewFile(
    Map<String, dynamic> snapshot,
    String imdbId,
    String previewFile,
  ) {
    if (!isValidPreviewPath(previewFile)) return _copySnapshot(snapshot);
    final copy = _copySnapshot(snapshot);
    final items = copy['items'];
    if (items is! List) return copy;
    for (final raw in items) {
      if (raw is Map<String, dynamic> && raw['imdbId'] == imdbId) {
        raw['previewFile'] = previewFile;
        break;
      }
    }
    return copy;
  }

  static Map<String, dynamic> _copySnapshot(Map<String, dynamic> snapshot) {
    final copy = Map<String, dynamic>.from(snapshot);
    final items = snapshot['items'];
    if (items is List) {
      copy['items'] = [
        for (final raw in items)
          if (raw is Map) Map<String, dynamic>.from(raw),
      ];
    }
    return copy;
  }

  @visibleForTesting
  static Map<String, dynamic> buildSnapshot(
    List<StremioMeta> metas, {
    String? sourceTitle,
  }) {
    final items = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final meta in metas) {
      final imdbId = _imdbIdOf(meta);
      if (imdbId == null || meta.name.trim().isEmpty || !seen.add(imdbId)) {
        continue;
      }
      // MetaHub negotiates WebP for its extensionless `/img` endpoint. Top
      // Shelf artwork is decoded by tvOS rather than Flutter, so request its
      // explicit JPEG variant for the broadest system-image compatibility.
      final background =
          _topShelfImage(meta.background) ??
          'https://images.metahub.space/background/medium/$imdbId/img.jpg';
      final poster = _topShelfImage(meta.poster);
      final image = _firstNonEmpty(background) ?? poster;
      if (image == null) continue;

      items.add({
        'identifier': '${_normalizedType(meta.type)}:$imdbId',
        'imdbId': imdbId,
        'type': _normalizedType(meta.type),
        'title': meta.name.trim(),
        'imageURL': image,
        if (poster != null) 'posterURL': poster,
        if (_firstNonEmpty(meta.description) case final description?)
          'summary': description,
        if (_firstNonEmpty(meta.year) case final year?) 'year': year,
        if (meta.imdbRating case final rating?
            when rating.isFinite && rating > 0)
          'rating': rating,
        if (meta.genres?.where((genre) => genre.trim().isNotEmpty).toList()
            case final genres? when genres.isNotEmpty)
          'genres': genres.take(3).toList(),
        if (_runtimeMinutes(meta.runtime) case final minutes?)
          'runtimeMinutes': minutes,
      });
      if (items.length == 8) break;
    }

    return {
      'version': 1,
      'contextTitle': _topShelfContext(sourceTitle),
      'items': items,
    };
  }

  static String? _imdbIdOf(StremioMeta meta) {
    final value = meta.imdbId ?? (meta.id.startsWith('tt') ? meta.id : null);
    return value != null && RegExp(r'^tt\d{7,10}$').hasMatch(value)
        ? value
        : null;
  }

  static String _normalizedType(String value) =>
      value.toLowerCase() == 'movie' ? 'movie' : 'series';

  static String _topShelfContext(String? sourceTitle) {
    final source = sourceTitle?.trim();
    if (source == null || source.isEmpty) return 'Spotlight on Debrify';
    return 'Spotlight · $source';
  }

  static String? _firstNonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _topShelfImage(String? value) {
    final image = _firstNonEmpty(value);
    if (image == null) return null;
    final uri = Uri.tryParse(image);
    if (uri != null &&
        uri.host.toLowerCase() == 'images.metahub.space' &&
        uri.path.endsWith('/img')) {
      return uri.replace(path: '${uri.path}.jpg').toString();
    }
    return image;
  }

  static int? _runtimeMinutes(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    final hours = RegExp(r'(\d+)\s*h').firstMatch(value);
    final minutes = RegExp(r'(\d+)\s*m').firstMatch(value);
    if (hours != null) {
      final total =
          int.parse(hours.group(1)!) * 60 +
          (minutes == null ? 0 : int.parse(minutes.group(1)!));
      return total > 0 ? total : null;
    }
    final leading = RegExp(r'^(\d+)').firstMatch(value);
    if (leading == null) return null;
    final total = int.parse(leading.group(1)!);
    return total > 0 ? total : null;
  }

  static void _openTopShelfItem(Map<String, dynamic> payload) {
    unawaited(_openTopShelfItemAuthorized(payload));
  }

  static Future<void> _openTopShelfItemAuthorized(
    Map<String, dynamic> payload,
  ) async {
    final owner = payload['ownerProfileId'] as String?;
    if (ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted) {
      final revision = int.tryParse(
        payload['profileAuthorizationRevision']?.toString() ?? '',
      );
      final profile = owner == null
          ? null
          : await ProfileBootstrap.registry.getProfile(owner);
      if (profile == null ||
          revision == null ||
          !profile.isEnabled ||
          profile.authorizationRevision != revision ||
          !profile.allows(ProfileFeature.incomingLinks)) {
        await instance.clear();
        return;
      }
      if (owner == null ||
          ProfileRuntime.capture().profileId != owner ||
          !ProfileLockController.instance.isUnlocked) {
        instance._pendingProfileAction = Map<String, dynamic>.from(payload);
        MainPageBridge.showProfilePicker?.call();
        return;
      }
    }
    final imdbId = payload['imdbId'] as String?;
    if (imdbId == null || !RegExp(r'^tt\d{7,10}$').hasMatch(imdbId)) return;
    final yearText = payload['year'] as String?;
    final year = yearText == null
        ? null
        : int.tryParse(RegExp(r'\d{4}').firstMatch(yearText)?.group(0) ?? '');
    MainPageBridge.requestCatalogDetailOpen({
      'imdbId': imdbId,
      'type': _normalizedType(payload['type'] as String? ?? 'series'),
      'title': payload['title'] as String? ?? '',
      'poster': payload['posterURL'] as String?,
      'year': year,
    });
  }

  Future<bool> multiProfilePersonalizationEnabled() async =>
      (await DevicePreferences.instance()).getBool(_multiProfileOptInKey) ??
      false;

  /// The same authority predicate used by both the settings surface and the
  /// write boundary. Keeping it here prevents a visible control from drifting
  /// away from what the service will actually accept.
  static bool canManageMultiProfilePersonalization(UserProfile? profile) =>
      profile != null &&
      profile.role == UserProfileRole.admin &&
      profile.allows(ProfileFeature.manageProfiles);

  Future<void> setMultiProfilePersonalizationEnabled(bool enabled) async {
    final profile = await ProfileBootstrap.registry.getProfile(
      ProfileRuntime.capture().profileId,
    );
    if (!canManageMultiProfilePersonalization(profile)) {
      throw StateError('Only an Admin can change Top Shelf privacy');
    }
    if (!await (await DevicePreferences.instance()).setBool(
      _multiProfileOptInKey,
      enabled,
    )) {
      throw StateError('Could not save Top Shelf privacy preference');
    }
    if (!enabled) await clear();
  }

  void onProfileUnlocked() {
    final pending = _pendingProfileAction;
    if (pending == null) return;
    final owner = pending['ownerProfileId'] as String?;
    if (owner != null &&
        ProfileRuntime.isInitialized &&
        ProfileRuntime.isProfileCommitted &&
        ProfileRuntime.capture().profileId == owner &&
        ProfileLockController.instance.isUnlocked) {
      _pendingProfileAction = null;
      _openTopShelfItem(pending);
    }
  }
}

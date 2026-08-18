import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/stremio_addon.dart';
import '../models/stremio_subtitle.dart';
import '../utils/stremio_url.dart';
import 'stremio_service.dart';

/// Service for fetching subtitles from Stremio addons.
///
/// This service provides:
/// - Fetching subtitles from addons that support the 'subtitles' resource
/// - Parallel fetching from multiple addons
/// - Deduplication of subtitle results
class StremioSubtitleService {
  static const Duration _requestTimeout = Duration(seconds: 15);
  static const int _maxAttempts = 3;
  static const Duration _initialBackoff = Duration(milliseconds: 500);
  static const int _backoffMultiplier = 3;

  // Singleton pattern
  static final StremioSubtitleService _instance =
      StremioSubtitleService._internal();
  static StremioSubtitleService get instance => _instance;
  factory StremioSubtitleService() => _instance;
  StremioSubtitleService._internal();

  final StremioService _stremioService = StremioService.instance;

  /// Get addons that support subtitles
  Future<List<StremioAddon>> getSubtitleAddons() async {
    final addons = await _stremioService.getEnabledAddons();
    debugPrint(
      'StremioSubtitleService: Total enabled addons: ${addons.length}',
    );
    for (final addon in addons) {
      debugPrint(
        'StremioSubtitleService: Addon "${addon.name}" resources: ${addon.resources}',
      );
    }
    final subtitleAddons = addons
        .where((a) => a.resources.contains('subtitles'))
        .toList();
    debugPrint(
      'StremioSubtitleService: Subtitle addons: ${subtitleAddons.map((a) => a.name).toList()}',
    );
    return subtitleAddons;
  }

  /// Fetch subtitles for content from all enabled subtitle addons.
  ///
  /// Parameters:
  /// - [type]: Content type ('movie' or 'series')
  /// - [imdbId]: IMDB ID (e.g., 'tt1234567')
  /// - [season]: Season number for series (optional)
  /// - [episode]: Episode number for series (optional)
  ///
  /// Returns [StremioSubtitleResult] containing all fetched subtitles
  /// and any addons that failed.
  Future<StremioSubtitleResult> fetchSubtitles({
    required String type,
    required String imdbId,
    int? season,
    int? episode,
  }) async {
    final addons = await getSubtitleAddons();

    if (addons.isEmpty) {
      debugPrint('StremioSubtitleService: No subtitle addons available');
      return const StremioSubtitleResult(subtitles: []);
    }

    // Build subtitle ID
    final subtitleId = _buildSubtitleId(imdbId, season, episode);

    debugPrint(
      'StremioSubtitleService: Fetching subtitles for $type/$subtitleId from ${addons.length} addons',
    );

    // Fetch from every subtitle addon in parallel. We intentionally don't
    // filter by the addon's declared `types` — that field describes an
    // addon's catalogs/metas, not its subtitle endpoint, and many addons
    // misconfigure it. If an addon has the `subtitles` resource, we ask it;
    // empty responses are cheap and handled gracefully.
    final List<String> failedAddons = [];
    final List<Future<List<StremioSubtitle>>> futures = [];

    for (final addon in addons) {
      futures.add(
        _fetchSubtitlesFromAddon(addon, type, subtitleId).catchError((error) {
          debugPrint('StremioSubtitleService: ${addon.name} error: $error');
          failedAddons.add(addon.name);
          return <StremioSubtitle>[];
        }),
      );
    }

    final allResults = await Future.wait(futures);

    // Flatten and deduplicate
    final List<StremioSubtitle> allSubtitles = [];
    final Set<String> seenUrls = {};

    for (final subtitleList in allResults) {
      for (final sub in subtitleList) {
        // Deduplicate by URL
        if (!seenUrls.contains(sub.url)) {
          seenUrls.add(sub.url);
          allSubtitles.add(sub);
        }
      }
    }

    // Sort by language
    allSubtitles.sort((a, b) => a.displayName.compareTo(b.displayName));

    debugPrint(
      'StremioSubtitleService: Found ${allSubtitles.length} unique subtitles',
    );

    return StremioSubtitleResult(
      subtitles: allSubtitles,
      failedAddons: failedAddons,
    );
  }

  /// Fetch subtitles keeping per-addon grouping, one [AddonSubtitleSlot] per
  /// enabled subtitle addon (mirrors the Android TV player's per-addon model).
  ///
  /// [onUpdate] fires with a fresh snapshot of the full slot list first when
  /// all slots enter LOADING, then again as each addon settles (ok/failed).
  /// The returned future completes with the final list once every addon has
  /// settled — callers that only want the end state can just await it.
  Future<List<AddonSubtitleSlot>> fetchSubtitleSlots({
    required String type,
    required String imdbId,
    int? season,
    int? episode,
    void Function(List<AddonSubtitleSlot> slots)? onUpdate,
  }) async {
    final addons = await getSubtitleAddons();
    final slots = [
      for (final a in addons)
        AddonSubtitleSlot(
          addonId: a.id,
          addonName: a.name,
          status: AddonSubtitleStatus.loading,
        ),
    ];
    onUpdate?.call(List.unmodifiable(slots));
    if (addons.isEmpty) return const [];

    final subtitleId = _buildSubtitleId(imdbId, season, episode);
    await Future.wait([
      for (var i = 0; i < addons.length; i++)
        () async {
          AddonSubtitleSlot updated;
          try {
            final subs = await _fetchSubtitlesFromAddon(
              addons[i],
              type,
              subtitleId,
            );
            updated = slots[i].copyWith(
              status: AddonSubtitleStatus.ok,
              subtitles: subs,
            );
          } catch (e) {
            updated = slots[i].copyWith(
              status: AddonSubtitleStatus.failed,
              error: '$e',
            );
          }
          slots[i] = updated;
          onUpdate?.call(List.unmodifiable(slots));
        }(),
    ]);
    return List.unmodifiable(slots);
  }

  /// Re-fetch a single addon by id (the per-addon "Retry" action). Returns
  /// the settled slot — ok with subtitles, or failed with the error message.
  Future<AddonSubtitleSlot> fetchSingleAddonSlot({
    required String addonId,
    required String type,
    required String imdbId,
    int? season,
    int? episode,
  }) async {
    final addons = await getSubtitleAddons();
    StremioAddon? addon;
    for (final a in addons) {
      if (a.id == addonId) {
        addon = a;
        break;
      }
    }
    if (addon == null) {
      return AddonSubtitleSlot(
        addonId: addonId,
        addonName: addonId,
        status: AddonSubtitleStatus.failed,
        error: 'Addon not found',
      );
    }
    final subtitleId = _buildSubtitleId(imdbId, season, episode);
    try {
      final subs = await _fetchSubtitlesFromAddon(addon, type, subtitleId);
      return AddonSubtitleSlot(
        addonId: addon.id,
        addonName: addon.name,
        status: AddonSubtitleStatus.ok,
        subtitles: subs,
      );
    } catch (e) {
      return AddonSubtitleSlot(
        addonId: addon.id,
        addonName: addon.name,
        status: AddonSubtitleStatus.failed,
        error: '$e',
      );
    }
  }

  /// Build the subtitle ID for API request
  String _buildSubtitleId(String imdbId, int? season, int? episode) {
    if (season != null && episode != null) {
      return '$imdbId:$season:$episode';
    }
    return imdbId;
  }

  /// Fetch subtitles from a single addon, retrying on any failure.
  ///
  /// Stremio addon quality varies — some return incorrect status codes,
  /// intermittently time out, or briefly 5xx. We retry any thrown exception
  /// (HTTP non-200, timeout, socket error, JSON parse error) up to
  /// [_maxAttempts] times with exponential backoff. A valid JSON response
  /// with no subtitles is NOT treated as failure — it just means the addon
  /// has nothing for this content.
  Future<List<StremioSubtitle>> _fetchSubtitlesFromAddon(
    StremioAddon addon,
    String type,
    String subtitleId,
  ) async {
    final url = buildStremioResourceUri(addon.baseUrl, <String>[
      'subtitles',
      type,
      '$subtitleId.json',
    ]).toString();
    debugPrint('StremioSubtitleService: Fetching from ${addon.name}: $url');

    Object? lastError;
    Duration backoff = _initialBackoff;

    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        return await _attemptFetch(addon, url);
      } catch (e) {
        lastError = e;
        debugPrint(
          'StremioSubtitleService: ${addon.name} attempt $attempt/$_maxAttempts failed: $e',
        );
        if (attempt < _maxAttempts) {
          await Future.delayed(backoff);
          backoff *= _backoffMultiplier;
        }
      }
    }

    debugPrint(
      'StremioSubtitleService: ${addon.name} exhausted $_maxAttempts attempts, giving up',
    );
    throw lastError ?? Exception('All retry attempts failed');
  }

  /// Single fetch attempt. Throws on HTTP non-200, timeout, socket error,
  /// or JSON parse failure. Returns an empty list if the addon responds
  /// successfully with no subtitles.
  Future<List<StremioSubtitle>> _attemptFetch(
    StremioAddon addon,
    String url,
  ) async {
    final uri = Uri.parse(url);
    final response = await http.get(uri).timeout(_requestTimeout);
    debugPrint(
      'StremioSubtitleService: ${addon.name} response: ${response.statusCode}',
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final Map<String, dynamic> data = json.decode(response.body);
    final subtitlesRaw = data['subtitles'] as List<dynamic>?;

    if (subtitlesRaw == null || subtitlesRaw.isEmpty) {
      debugPrint('StremioSubtitleService: ${addon.name} returned no subtitles');
      return [];
    }

    final subtitles = subtitlesRaw
        .map(
          (s) =>
              StremioSubtitle.fromJson(s as Map<String, dynamic>, addon.name),
        )
        .where((s) => s.url.isNotEmpty)
        .toList();

    debugPrint(
      'StremioSubtitleService: ${addon.name} returned ${subtitles.length} subtitles',
    );
    return subtitles;
  }

  /// Check if any subtitle addons are available
  Future<bool> hasSubtitleAddons() async {
    final addons = await getSubtitleAddons();
    return addons.isNotEmpty;
  }
}

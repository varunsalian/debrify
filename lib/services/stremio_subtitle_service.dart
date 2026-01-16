import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/stremio_addon.dart';
import '../models/stremio_subtitle.dart';
import 'stremio_service.dart';

/// Service for fetching subtitles from Stremio addons.
///
/// This service provides:
/// - Fetching subtitles from addons that support the 'subtitles' resource
/// - Parallel fetching from multiple addons
/// - Deduplication of subtitle results
class StremioSubtitleService {
  static const Duration _requestTimeout = Duration(seconds: 10);

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
    debugPrint('StremioSubtitleService: Total enabled addons: ${addons.length}');
    for (final addon in addons) {
      debugPrint('StremioSubtitleService: Addon "${addon.name}" resources: ${addon.resources}');
    }
    final subtitleAddons = addons.where((a) => a.resources.contains('subtitles')).toList();
    debugPrint('StremioSubtitleService: Subtitle addons: ${subtitleAddons.map((a) => a.name).toList()}');
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

    // Filter addons that support the content type
    final applicableAddons = addons.where((a) {
      if (type == 'movie') return a.supportsMovies;
      if (type == 'series') return a.supportsSeries;
      return a.types.contains(type) || a.types.isEmpty;
    }).toList();

    if (applicableAddons.isEmpty) {
      debugPrint(
          'StremioSubtitleService: No addons support type: $type for subtitles');
      return const StremioSubtitleResult(subtitles: []);
    }

    // Build subtitle ID
    final subtitleId = _buildSubtitleId(imdbId, season, episode);

    debugPrint(
        'StremioSubtitleService: Fetching subtitles for $type/$subtitleId from ${applicableAddons.length} addons');

    // Fetch from all applicable addons in parallel
    final List<String> failedAddons = [];
    final List<Future<List<StremioSubtitle>>> futures = [];

    for (final addon in applicableAddons) {
      futures.add(
        _fetchSubtitlesFromAddon(addon, type, subtitleId).catchError((error) {
          debugPrint(
              'StremioSubtitleService: ${addon.name} error: $error');
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
        'StremioSubtitleService: Found ${allSubtitles.length} unique subtitles');

    return StremioSubtitleResult(
      subtitles: allSubtitles,
      failedAddons: failedAddons,
    );
  }

  /// Build the subtitle ID for API request
  String _buildSubtitleId(String imdbId, int? season, int? episode) {
    if (season != null && episode != null) {
      return '$imdbId:$season:$episode';
    }
    return imdbId;
  }

  /// Fetch subtitles from a single addon
  Future<List<StremioSubtitle>> _fetchSubtitlesFromAddon(
    StremioAddon addon,
    String type,
    String subtitleId,
  ) async {
    final url = '${addon.baseUrl}/subtitles/$type/$subtitleId.json';
    debugPrint('StremioSubtitleService: Fetching from ${addon.name}: $url');

    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(_requestTimeout);
      debugPrint('StremioSubtitleService: ${addon.name} response: ${response.statusCode}');

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
          .map((s) => StremioSubtitle.fromJson(
                s as Map<String, dynamic>,
                addon.name,
              ))
          .where((s) => s.url.isNotEmpty)
          .toList();

      debugPrint(
          'StremioSubtitleService: ${addon.name} returned ${subtitles.length} subtitles');
      return subtitles;
    } catch (e) {
      debugPrint(
          'StremioSubtitleService: Error fetching subtitles from ${addon.name}: $e');
      rethrow;
    }
  }

  /// Check if any subtitle addons are available
  Future<bool> hasSubtitleAddons() async {
    final addons = await getSubtitleAddons();
    return addons.isNotEmpty;
  }
}

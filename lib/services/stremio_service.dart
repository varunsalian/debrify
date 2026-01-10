import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/stremio_addon.dart';
import '../models/torrent.dart';

/// Service for managing Stremio addons and searching for streams.
///
/// This service provides:
/// - Addon management (add, remove, enable/disable)
/// - Manifest fetching and validation
/// - Stream search across all enabled addons
/// - Conversion of Stremio streams to Torrent objects
class StremioService {
  static const String _addonsKey = 'stremio_addons_v1';
  static const Duration _requestTimeout = Duration(seconds: 15);

  // Singleton pattern
  static final StremioService _instance = StremioService._internal();
  static StremioService get instance => _instance;
  factory StremioService() => _instance;
  StremioService._internal();

  // In-memory cache of addons
  List<StremioAddon>? _addonsCache;

  // ============================================================
  // Addon Management
  // ============================================================

  /// Get all stored Stremio addons
  Future<List<StremioAddon>> getAddons() async {
    if (_addonsCache != null) return List.from(_addonsCache!);

    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_addonsKey);

    if (jsonString == null || jsonString.isEmpty) {
      _addonsCache = [];
      return [];
    }

    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      _addonsCache = jsonList
          .map((j) => StremioAddon.fromJson(j as Map<String, dynamic>))
          .toList();
      return List.from(_addonsCache!);
    } catch (e) {
      debugPrint('StremioService: Error loading addons: $e');
      _addonsCache = [];
      return [];
    }
  }

  /// Get only enabled addons
  Future<List<StremioAddon>> getEnabledAddons() async {
    final addons = await getAddons();
    return addons.where((a) => a.enabled).toList();
  }

  /// Get addons that support streaming
  Future<List<StremioAddon>> getStreamingAddons() async {
    final addons = await getEnabledAddons();
    return addons.where((a) => a.supportsStreams).toList();
  }

  /// Save addons to storage
  Future<void> _saveAddons(List<StremioAddon> addons) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(addons.map((a) => a.toJson()).toList());
    await prefs.setString(_addonsKey, jsonString);
    _addonsCache = addons;
  }

  /// Add a new addon by manifest URL
  ///
  /// Returns the addon if successful, throws exception on failure.
  Future<StremioAddon> addAddon(String manifestUrl) async {
    // Normalize URL
    manifestUrl = manifestUrl.trim();
    if (!manifestUrl.endsWith('/manifest.json')) {
      if (manifestUrl.endsWith('/')) {
        manifestUrl = '${manifestUrl}manifest.json';
      } else {
        manifestUrl = '$manifestUrl/manifest.json';
      }
    }

    // Check if already exists
    final existingAddons = await getAddons();
    final existing = existingAddons.where(
      (a) => a.manifestUrl == manifestUrl,
    );
    if (existing.isNotEmpty) {
      throw Exception('Addon already exists: ${existing.first.name}');
    }

    // Fetch and parse manifest
    final addon = await fetchManifest(manifestUrl);

    // Check for duplicate by ID
    final duplicateById = existingAddons.where((a) => a.id == addon.id);
    if (duplicateById.isNotEmpty) {
      // Same addon with different config - allow but warn
      debugPrint(
        'StremioService: Adding addon with same ID but different URL: ${addon.id}',
      );
    }

    // Add to list and save
    existingAddons.add(addon);
    await _saveAddons(existingAddons);

    debugPrint('StremioService: Added addon: ${addon.name}');
    return addon;
  }

  /// Remove an addon by its manifest URL
  Future<void> removeAddon(String manifestUrl) async {
    final addons = await getAddons();
    addons.removeWhere((a) => a.manifestUrl == manifestUrl);
    await _saveAddons(addons);
    debugPrint('StremioService: Removed addon: $manifestUrl');
  }

  /// Toggle addon enabled state
  Future<void> setAddonEnabled(String manifestUrl, bool enabled) async {
    final addons = await getAddons();
    final index = addons.indexWhere((a) => a.manifestUrl == manifestUrl);
    if (index >= 0) {
      addons[index] = addons[index].copyWith(enabled: enabled);
      await _saveAddons(addons);
    }
  }

  /// Refresh an addon's manifest
  Future<StremioAddon?> refreshAddon(String manifestUrl) async {
    try {
      final newManifest = await fetchManifest(manifestUrl);
      final addons = await getAddons();
      final index = addons.indexWhere((a) => a.manifestUrl == manifestUrl);
      if (index >= 0) {
        // Preserve enabled state
        addons[index] = newManifest.copyWith(
          enabled: addons[index].enabled,
          addedAt: addons[index].addedAt,
        );
        await _saveAddons(addons);
        return addons[index];
      }
      return newManifest;
    } catch (e) {
      debugPrint('StremioService: Error refreshing addon: $e');
      return null;
    }
  }

  /// Clear all addons
  Future<void> clearAllAddons() async {
    await _saveAddons([]);
    debugPrint('StremioService: Cleared all addons');
  }

  // ============================================================
  // Manifest Fetching
  // ============================================================

  /// Fetch and parse a manifest from URL
  Future<StremioAddon> fetchManifest(String manifestUrl) async {
    try {
      final uri = Uri.parse(manifestUrl);
      final response = await http.get(uri).timeout(_requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final Map<String, dynamic> manifest = json.decode(response.body);

      // Validate required fields
      if (manifest['id'] == null || manifest['name'] == null) {
        throw Exception('Invalid manifest: missing id or name');
      }

      return StremioAddon.fromManifest(manifest, manifestUrl);
    } on FormatException catch (e) {
      throw Exception('Invalid JSON response: $e');
    } catch (e) {
      throw Exception('Failed to fetch manifest: $e');
    }
  }

  // ============================================================
  // Stream Search
  // ============================================================

  /// Search for streams across all enabled addons
  ///
  /// Parameters:
  /// - [type]: Content type ('movie' or 'series')
  /// - [imdbId]: IMDB ID (e.g., 'tt1234567')
  /// - [season]: Season number for series (optional)
  /// - [episode]: Episode number for series (optional)
  ///
  /// Returns a map with:
  /// - 'torrents': List<Torrent> - deduplicated and sorted by seeders
  /// - 'addonCounts': Map<String, int> - count of results per addon
  /// - 'addonErrors': Map<String, String> - error messages per addon
  Future<Map<String, dynamic>> searchStreams({
    required String type,
    required String imdbId,
    int? season,
    int? episode,
  }) async {
    final Map<String, int> addonCounts = {};
    final Map<String, String> addonErrors = {};

    final addons = await getStreamingAddons();

    if (addons.isEmpty) {
      debugPrint('StremioService: No streaming addons available');
      return {
        'torrents': <Torrent>[],
        'addonCounts': addonCounts,
        'addonErrors': addonErrors,
      };
    }

    // Filter addons that support the content type
    final applicableAddons = addons.where((a) {
      if (type == 'movie') return a.supportsMovies;
      if (type == 'series') return a.supportsSeries;
      return true; // Unknown type, try anyway
    }).toList();

    if (applicableAddons.isEmpty) {
      debugPrint('StremioService: No addons support type: $type');
      return {
        'torrents': <Torrent>[],
        'addonCounts': addonCounts,
        'addonErrors': addonErrors,
      };
    }

    // Build stream ID
    final streamId = _buildStreamId(imdbId, season, episode);

    // Search all applicable addons in parallel
    final List<Future<List<StremioStream>>> futures = [];

    for (final addon in applicableAddons) {
      // Use stremio: prefix and lowercase to match Torrent model (which lowercases source)
      final sourceKey = 'stremio:${addon.name}'.toLowerCase();
      futures.add(
        _fetchStreamsFromAddon(addon, type, streamId).then((streams) {
          addonCounts[sourceKey] = streams.length;
          debugPrint(
            'StremioService: ${addon.name} returned ${streams.length} streams',
          );
          return streams;
        }).catchError((error, _) {
          addonCounts[sourceKey] = 0;
          addonErrors[sourceKey] = error.toString();
          debugPrint('StremioService: ${addon.name} error: $error');
          return <StremioStream>[];
        }),
      );
    }

    final allStreams = await Future.wait(futures);

    // Flatten and convert to torrents
    final List<StremioStream> flatStreams = [];
    for (final streamList in allStreams) {
      flatStreams.addAll(streamList);
    }

    // Convert to Torrent objects and deduplicate
    final torrents = _convertToTorrents(flatStreams);

    return {
      'torrents': torrents,
      'addonCounts': addonCounts,
      'addonErrors': addonErrors,
    };
  }

  /// Search for movie streams
  Future<Map<String, dynamic>> searchMovieStreams(String imdbId) async {
    return searchStreams(type: 'movie', imdbId: imdbId);
  }

  /// Search for series/episode streams
  Future<Map<String, dynamic>> searchSeriesStreams(
    String imdbId, {
    int? season,
    int? episode,
  }) async {
    return searchStreams(
      type: 'series',
      imdbId: imdbId,
      season: season,
      episode: episode,
    );
  }

  /// Build the stream ID for the API call
  String _buildStreamId(String imdbId, int? season, int? episode) {
    if (season != null && episode != null) {
      return '$imdbId:$season:$episode';
    } else if (season != null) {
      return '$imdbId:$season';
    }
    return imdbId;
  }

  /// Fetch streams from a single addon
  Future<List<StremioStream>> _fetchStreamsFromAddon(
    StremioAddon addon,
    String type,
    String streamId,
  ) async {
    final url = '${addon.baseUrl}/stream/$type/$streamId.json';

    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(_requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final Map<String, dynamic> data = json.decode(response.body);
      final streamsRaw = data['streams'] as List<dynamic>?;

      if (streamsRaw == null || streamsRaw.isEmpty) {
        return [];
      }

      return streamsRaw
          .map((s) => StremioStream.fromJson(
                s as Map<String, dynamic>,
                addon.name,
              ))
          .where((s) => s.isTorrent) // Only keep torrent streams
          .toList();
    } catch (e) {
      debugPrint('StremioService: Error fetching from ${addon.name}: $e');
      rethrow;
    }
  }

  /// Convert Stremio streams to Torrent objects
  List<Torrent> _convertToTorrents(List<StremioStream> streams) {
    final Map<String, Torrent> uniqueTorrents = {};
    int withInfoHash = 0;
    int withUrlOnly = 0;
    int skipped = 0;

    for (final stream in streams) {
      // Get unique key - prefer infoHash, fall back to URL hash
      String? uniqueKey;
      if (stream.infoHash != null && stream.infoHash!.isNotEmpty) {
        uniqueKey = stream.infoHash!.toLowerCase();
        withInfoHash++;
      } else if (stream.url != null && stream.url!.isNotEmpty) {
        // Use URL hash as unique key for debrid streams
        uniqueKey = stream.url.hashCode.toRadixString(16).padLeft(40, '0');
        withUrlOnly++;
      }

      if (uniqueKey == null) {
        skipped++;
        continue;
      }

      // Parse seeders from title
      final seeders = stream.seedersFromTitle ?? 0;

      // Parse size - try behaviorHints.videoSize first, then title
      int sizeBytes = 0;
      if (stream.behaviorHints != null) {
        final videoSize = stream.behaviorHints!['videoSize'];
        if (videoSize is int) {
          sizeBytes = videoSize;
        } else if (videoSize is double) {
          sizeBytes = videoSize.round();
        }
      }
      if (sizeBytes == 0) {
        final sizeStr = stream.sizeFromTitle;
        if (sizeStr != null) {
          sizeBytes = _parseSizeToBytes(sizeStr);
        }
      }

      // Get name - prefer filename from behaviorHints, then title
      String name = stream.title ?? 'Unknown';
      if (stream.behaviorHints != null) {
        final filename = stream.behaviorHints!['filename'] as String?;
        if (filename != null && filename.isNotEmpty) {
          name = filename;
        }
      }

      // Create torrent object
      final torrent = Torrent(
        rowid: 0,
        infohash: stream.infoHash?.toLowerCase() ?? uniqueKey,
        name: name,
        sizeBytes: sizeBytes,
        createdUnix: 0,
        seeders: seeders,
        leechers: 0,
        completed: 0,
        scrapedDate: 0,
        source: 'stremio:${stream.source}',
      );

      // Deduplicate by unique key, keeping highest seeder count
      final existing = uniqueTorrents[uniqueKey];
      if (existing == null || torrent.seeders > existing.seeders) {
        uniqueTorrents[uniqueKey] = torrent;
      }
    }

    // Sort by seeders descending
    final results = uniqueTorrents.values.toList();
    results.sort((a, b) => b.seeders.compareTo(a.seeders));

    debugPrint(
      'StremioService: Converted ${streams.length} streams to '
      '${results.length} unique torrents',
    );
    debugPrint(
      'StremioService: Stream breakdown - withInfoHash: $withInfoHash, '
      'withUrlOnly: $withUrlOnly, skipped: $skipped',
    );

    // Log a few sample infohashes for debugging
    if (results.isNotEmpty) {
      final samples = results.take(3).map((t) => '${t.infohash.substring(0, 8)}... (${t.source})').toList();
      debugPrint('StremioService: Sample infohashes: $samples');
    }

    return results;
  }

  /// Parse size string to bytes
  int _parseSizeToBytes(String sizeStr) {
    final normalized = sizeStr.toUpperCase().replaceAll(' ', '');
    final pattern = RegExp(r'([\d.]+)(GB|MB|TB|KB)');
    final match = pattern.firstMatch(normalized);

    if (match == null) return 0;

    final value = double.tryParse(match.group(1) ?? '0') ?? 0;
    final unit = match.group(2) ?? '';

    switch (unit) {
      case 'TB':
        return (value * 1024 * 1024 * 1024 * 1024).round();
      case 'GB':
        return (value * 1024 * 1024 * 1024).round();
      case 'MB':
        return (value * 1024 * 1024).round();
      case 'KB':
        return (value * 1024).round();
      default:
        return 0;
    }
  }

  // ============================================================
  // Utility Methods
  // ============================================================

  /// Check if any addons are configured
  Future<bool> hasAddons() async {
    final addons = await getAddons();
    return addons.isNotEmpty;
  }

  /// Check if any enabled addons are available
  Future<bool> hasEnabledAddons() async {
    final addons = await getEnabledAddons();
    return addons.isNotEmpty;
  }

  /// Get count of enabled addons
  Future<int> getEnabledAddonCount() async {
    final addons = await getEnabledAddons();
    return addons.length;
  }

  /// Invalidate cache (call after external changes)
  void invalidateCache() {
    _addonsCache = null;
  }
}

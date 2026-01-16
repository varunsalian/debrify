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

  // Listeners for addon changes (used to refresh UI when addons are added via deep link)
  final List<VoidCallback> _addonsChangedListeners = [];

  /// Add a listener to be notified when addons change
  void addAddonsChangedListener(VoidCallback listener) {
    _addonsChangedListeners.add(listener);
  }

  /// Remove an addons changed listener
  void removeAddonsChangedListener(VoidCallback listener) {
    _addonsChangedListeners.remove(listener);
  }

  /// Notify all listeners that addons have changed
  void _notifyAddonsChanged() {
    for (final listener in _addonsChangedListeners) {
      listener();
    }
  }

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
    _notifyAddonsChanged();
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

    // Validate addon has useful resources (streams or catalogs)
    final validationError = _validateAddon(addon);
    if (validationError != null) {
      throw Exception(validationError);
    }

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
  /// - [availableSeasons]: Known seasons from IMDbbot API for smart fallback
  ///
  /// For series without specific season/episode:
  /// 1. First tries bare IMDB ID (returns complete series packs)
  /// 2. If results < 5, falls back to season probing (S1E1, S2E1, etc.)
  /// 3. Fallback results are filtered to keep only season/series packs
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
    List<int>? availableSeasons,
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

    // Filter addons that support the content type AND the content ID prefix
    final applicableAddons = addons.where((a) {
      // Check content type support
      bool supportsType = true;
      if (type == 'movie') supportsType = a.supportsMovies;
      else if (type == 'series') supportsType = a.supportsSeries;
      // For other types (anime, tv, channel, etc.), allow if addon declares that type
      else supportsType = a.types.contains(type) || a.types.isEmpty;

      // Check if addon supports the content ID prefix (smart routing)
      final supportsId = a.supportsContentId(imdbId);

      return supportsType && supportsId;
    }).toList();

    if (applicableAddons.isEmpty) {
      final prefix = StremioAddon.extractIdPrefix(imdbId);
      debugPrint('StremioService: No addons support type: $type with ID prefix: $prefix');
      return {
        'torrents': <Torrent>[],
        'addonCounts': addonCounts,
        'addonErrors': addonErrors,
      };
    }

    // Check if this is a series search without specific season/episode
    // In this case, use smart fallback logic
    final bool needsSmartFallback = type == 'series' && season == null && episode == null;

    if (needsSmartFallback) {
      return _searchStreamsWithSmartFallback(
        applicableAddons: applicableAddons,
        imdbId: imdbId,
        availableSeasons: availableSeasons,
        addonCounts: addonCounts,
        addonErrors: addonErrors,
      );
    }

    // Standard search with specific season/episode or for movies
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

  /// Smart fallback for series search without specific season/episode
  ///
  /// 1. First tries bare IMDB ID
  /// 2. Filters to packs only - if >= 5, done
  /// 3. If < 5 packs, falls back to season probing
  /// 4. Combines and filters to packs - if >= 5, done
  /// 5. If still < 5 packs, returns unfiltered (shows episodes)
  Future<Map<String, dynamic>> _searchStreamsWithSmartFallback({
    required List<StremioAddon> applicableAddons,
    required String imdbId,
    required Map<String, int> addonCounts,
    required Map<String, String> addonErrors,
    List<int>? availableSeasons,
  }) async {
    const int minResultsThreshold = 5;
    const int maxConsecutiveEmpty = 3;

    debugPrint('StremioService: Using smart fallback for series search');

    // Step 1: Try bare IMDB ID first (parallel)
    final List<Future<List<StremioStream>>> initialFutures = [];

    for (final addon in applicableAddons) {
      final sourceKey = 'stremio:${addon.name}'.toLowerCase();
      initialFutures.add(
        _fetchStreamsFromAddon(addon, 'series', imdbId).then((streams) {
          addonCounts[sourceKey] = streams.length;
          debugPrint(
            'StremioService: ${addon.name} (bare IMDB) returned ${streams.length} streams',
          );
          return streams;
        }).catchError((e) {
          addonCounts[sourceKey] = 0;
          addonErrors[sourceKey] = e.toString();
          debugPrint('StremioService: ${addon.name} (bare IMDB) error: $e');
          return <StremioStream>[];
        }),
      );
    }

    // Execute all bare IMDB searches in parallel
    final initialResults = await Future.wait(initialFutures);
    final List<StremioStream> initialStreams = [];
    for (final streams in initialResults) {
      initialStreams.addAll(streams);
    }

    // Convert initial streams to torrents
    List<Torrent> allTorrents = _convertToTorrents(initialStreams);
    debugPrint('StremioService: Bare IMDB returned ${allTorrents.length} torrents');

    // Step 2: Filter to packs only
    List<Torrent> filteredTorrents = _filterToPacksOnly(allTorrents);
    debugPrint(
      'StremioService: After filtering bare IMDB to packs: ${filteredTorrents.length} torrents',
    );

    // If we have enough packs, return them
    if (filteredTorrents.length >= minResultsThreshold) {
      debugPrint(
        'StremioService: Have ${filteredTorrents.length} packs (>= $minResultsThreshold), returning packs only',
      );
      _updateAddonCounts(addonCounts, filteredTorrents);
      return {
        'torrents': filteredTorrents,
        'addonCounts': addonCounts,
        'addonErrors': addonErrors,
      };
    }

    // Step 3: Not enough packs, fallback to season probing
    debugPrint(
      'StremioService: Only ${filteredTorrents.length} packs (< $minResultsThreshold), '
      'falling back to season probing',
    );

    // Determine seasons to probe (cap at 10 to avoid flooding servers)
    const int maxSeasonsToProbe = 10;
    List<int> seasonsToProbe =
        (availableSeasons != null && availableSeasons.isNotEmpty)
            ? (List<int>.from(availableSeasons)..sort()) // Sort to ensure we get earliest seasons
            : List.generate(5, (i) => i + 1); // Default to seasons 1-5

    // Cap to first 10 seasons - season packs usually appear in early season searches
    if (seasonsToProbe.length > maxSeasonsToProbe) {
      debugPrint(
        'StremioService: Capping seasons from ${seasonsToProbe.length} to $maxSeasonsToProbe',
      );
      seasonsToProbe = seasonsToProbe.take(maxSeasonsToProbe).toList();
    }

    debugPrint(
      'StremioService: Probing ${seasonsToProbe.length} seasons IN PARALLEL: $seasonsToProbe',
    );

    // Create parallel futures for all season+addon combinations
    final List<Future<List<StremioStream>>> seasonFutures = [];

    for (final seasonNum in seasonsToProbe) {
      final streamId = _buildStreamId(imdbId, seasonNum, 1); // S{n}E1

      for (final addon in applicableAddons) {
        seasonFutures.add(
          _fetchStreamsFromAddon(addon, 'series', streamId).catchError((e) {
            debugPrint(
              'StremioService: ${addon.name} error probing S${seasonNum}E1: $e',
            );
            return <StremioStream>[];
          }),
        );
      }
    }

    // Execute all season probes in parallel
    final List<List<StremioStream>> seasonResults = await Future.wait(seasonFutures);

    // Flatten results
    final List<StremioStream> fallbackStreams = [];
    for (final streams in seasonResults) {
      fallbackStreams.addAll(streams);
    }

    debugPrint(
      'StremioService: Parallel season probing returned ${fallbackStreams.length} streams',
    );

    // Convert fallback streams to torrents
    final fallbackTorrents = _convertToTorrents(fallbackStreams);
    debugPrint(
      'StremioService: Season probing returned ${fallbackTorrents.length} torrents',
    );

    // Step 4: Combine all torrents and filter to packs
    final Map<String, Torrent> uniqueTorrents = {};

    // Add initial torrents
    for (final torrent in allTorrents) {
      uniqueTorrents[torrent.infohash] = torrent;
    }

    // Add fallback torrents
    for (final torrent in fallbackTorrents) {
      if (!uniqueTorrents.containsKey(torrent.infohash)) {
        uniqueTorrents[torrent.infohash] = torrent;
      }
    }

    allTorrents = uniqueTorrents.values.toList();
    debugPrint('StremioService: Combined total: ${allTorrents.length} unique torrents');

    // Filter combined results to packs only
    filteredTorrents = _filterToPacksOnly(allTorrents);
    debugPrint(
      'StremioService: After filtering combined to packs: ${filteredTorrents.length} torrents',
    );

    // Step 5: If we have enough packs now, return them
    if (filteredTorrents.length >= minResultsThreshold) {
      debugPrint(
        'StremioService: Have ${filteredTorrents.length} packs after probing, returning packs only',
      );
      filteredTorrents.sort((a, b) => b.seeders.compareTo(a.seeders));
      _updateAddonCounts(addonCounts, filteredTorrents);
      return {
        'torrents': filteredTorrents,
        'addonCounts': addonCounts,
        'addonErrors': addonErrors,
      };
    }

    // Step 6: Still not enough packs, return all unfiltered (show episodes)
    debugPrint(
      'StremioService: Only ${filteredTorrents.length} packs after probing, '
      'returning all ${allTorrents.length} torrents (including episodes)',
    );
    allTorrents.sort((a, b) => b.seeders.compareTo(a.seeders));
    _updateAddonCounts(addonCounts, allTorrents);

    return {
      'torrents': allTorrents,
      'addonCounts': addonCounts,
      'addonErrors': addonErrors,
    };
  }

  /// Update addon counts based on the final torrent list
  void _updateAddonCounts(Map<String, int> addonCounts, List<Torrent> torrents) {
    for (final key in addonCounts.keys.toList()) {
      addonCounts[key] = torrents.where((t) => t.source.toLowerCase() == key).length;
    }
  }

  /// Filter torrents to keep only season packs and complete series packs
  /// Removes individual episode torrents
  List<Torrent> _filterToPacksOnly(List<Torrent> torrents) {
    return torrents.where((torrent) {
      final name = torrent.name.toLowerCase();

      // Check for individual episode patterns (filter these OUT)
      // Matches: S01E01, S1E1, 1x01, etc.
      final episodePattern = RegExp(
        r's\d{1,2}e\d{1,3}|\d{1,2}x\d{1,3}',
        caseSensitive: false,
      );

      // Check for season pack patterns (keep these)
      // Matches: S01, Season 1, S01-S03, Complete, etc.
      final seasonPackPattern = RegExp(
        r'\.s\d{1,2}\.|season\s*\d+|s\d{1,2}-s\d{1,2}|complete|full.series',
        caseSensitive: false,
      );

      // If it has episode pattern like S01E01, it's an individual episode
      if (episodePattern.hasMatch(name)) {
        // But check if it's actually a season pack that happens to mention an episode
        // e.g., "From.S01.E01-E10" is a season pack
        final multiEpisodePattern = RegExp(
          r'e\d{1,3}-e\d{1,3}|e\d{1,3}\.?-\.?\d{1,3}',
          caseSensitive: false,
        );
        if (multiEpisodePattern.hasMatch(name)) {
          return true; // It's a pack like E01-E10
        }

        // Check if it also has season pack indicators
        if (seasonPackPattern.hasMatch(name)) {
          // Has both episode and season pack patterns - likely a season pack
          // e.g., "Show.S01.Complete.S01E01.mkv" (filename from pack)
          return true;
        }

        // Individual episode - filter out
        return false;
      }

      // No episode pattern, check if it has season pack indicators
      if (seasonPackPattern.hasMatch(name)) {
        return true;
      }

      // Fallback: check for S01 without E pattern
      final seasonOnlyPattern = RegExp(r'\.s\d{1,2}\.', caseSensitive: false);
      if (seasonOnlyPattern.hasMatch(name)) {
        return true;
      }

      // When in doubt, keep it (might be a pack with unusual naming)
      return true;
    }).toList();
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
    // Decode first (in case already encoded), then encode properly
    // This handles IDs like "vavoo_SKY%20ATLANTIC|group:it" that are partially encoded
    final decodedId = Uri.decodeComponent(streamId);
    final encodedStreamId = Uri.encodeComponent(decodedId);
    final url = '${addon.baseUrl}/stream/$type/$encodedStreamId.json';

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
          .where((s) => s.isUsable) // Keep all usable streams (torrent, direct, external)
          .toList();
    } catch (e) {
      debugPrint('StremioService: Error fetching from ${addon.name}: $e');
      rethrow;
    }
  }

  /// Convert Stremio streams to Torrent objects
  /// Handles all stream types: torrent (infoHash), direct URL, and external URL
  List<Torrent> _convertToTorrents(List<StremioStream> streams) {
    final Map<String, Torrent> uniqueTorrents = {};
    int withInfoHash = 0;
    int withDirectUrl = 0;
    int withExternalUrl = 0;
    int skipped = 0;

    for (final stream in streams) {
      // Determine stream type and get unique key
      String? uniqueKey;
      StreamType streamType;
      String? directUrl;

      if (stream.isTorrent) {
        // Torrent stream - has infoHash
        uniqueKey = stream.infoHash!.toLowerCase();
        streamType = StreamType.torrent;
        withInfoHash++;
      } else if (stream.isExternalUrl) {
        // External URL - opens in browser
        uniqueKey = 'ext:${stream.externalUrl.hashCode.toRadixString(16).padLeft(40, '0')}';
        streamType = StreamType.externalUrl;
        directUrl = stream.externalUrl;
        withExternalUrl++;
      } else if (stream.isDirectUrl) {
        // Direct URL - playable without debrid
        uniqueKey = 'url:${stream.url.hashCode.toRadixString(16).padLeft(40, '0')}';
        streamType = StreamType.directUrl;
        directUrl = stream.url;
        withDirectUrl++;
      } else {
        skipped++;
        continue;
      }

      // Parse seeders from title (only relevant for torrents, but parse anyway)
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

      // Create torrent object with stream type info
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
        streamType: streamType,
        directUrl: directUrl,
      );

      // Deduplicate by unique key, keeping highest seeder count (for torrents)
      // For direct/external URLs, just keep first occurrence
      final existing = uniqueTorrents[uniqueKey];
      if (existing == null ||
          (streamType == StreamType.torrent && torrent.seeders > existing.seeders)) {
        uniqueTorrents[uniqueKey] = torrent;
      }
    }

    // Sort: torrents first (by seeders), then direct URLs, then external URLs
    final results = uniqueTorrents.values.toList();
    results.sort((a, b) {
      // First sort by stream type priority (torrent > direct > external)
      final typeCompare = a.streamType.index.compareTo(b.streamType.index);
      if (typeCompare != 0) return typeCompare;
      // Then by seeders (descending)
      return b.seeders.compareTo(a.seeders);
    });

    debugPrint(
      'StremioService: Converted ${streams.length} streams to '
      '${results.length} unique items',
    );
    debugPrint(
      'StremioService: Stream breakdown - torrents: $withInfoHash, '
      'directUrl: $withDirectUrl, externalUrl: $withExternalUrl, skipped: $skipped',
    );

    // Log a few samples for debugging
    if (results.isNotEmpty) {
      final samples = results.take(3).map((t) =>
        '${t.streamType.name}:${t.infohash.substring(0, 8)}... (${t.source})'
      ).toList();
      debugPrint('StremioService: Samples: $samples');
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
  // Catalog Methods (Content Discovery)
  // ============================================================

  /// Get all enabled addons that support catalogs
  Future<List<StremioAddon>> getCatalogAddons() async {
    final addons = await getEnabledAddons();
    return addons.where((a) => a.supportsCatalogs).toList();
  }

  /// Get all enabled addons that have catalogs OR search capability
  /// This includes:
  /// - Addons with browseable catalogs
  /// - Addons with search-only capability (no catalogs but can search)
  Future<List<StremioAddon>> getBrowseableOrSearchableAddons() async {
    final addons = await getEnabledAddons();
    return addons.where((a) => a.supportsCatalogs || a.hasSearchableCatalogs).toList();
  }

  /// Get all available catalogs from all enabled catalog addons
  ///
  /// Returns a list of (addon, catalog) pairs for UI display
  Future<List<({StremioAddon addon, StremioAddonCatalog catalog})>>
      getAllCatalogs() async {
    final catalogAddons = await getCatalogAddons();
    final result = <({StremioAddon addon, StremioAddonCatalog catalog})>[];

    for (final addon in catalogAddons) {
      for (final catalog in addon.catalogs) {
        result.add((addon: addon, catalog: catalog));
      }
    }

    return result;
  }

  /// Fetch content from a specific catalog
  ///
  /// Parameters:
  /// - [addon]: The addon to fetch from
  /// - [catalog]: The catalog to fetch
  /// - [skip]: Number of items to skip (for pagination)
  /// - [genre]: Optional genre filter
  /// - [extras]: Additional extra parameters as key-value pairs
  ///
  /// Returns a list of StremioMeta items
  Future<List<StremioMeta>> fetchCatalog(
    StremioAddon addon,
    StremioAddonCatalog catalog, {
    int skip = 0,
    String? genre,
    Map<String, String>? extras,
  }) async {
    // Build catalog URL: {baseUrl}/catalog/{type}/{catalogId}.json
    // With extra parameters: {baseUrl}/catalog/{type}/{catalogId}/genre=Action.json
    // Multiple extras are joined with &: /genre=Action&skip=20.json
    String url = '${addon.baseUrl}/catalog/${catalog.type}/${catalog.id}';

    // Build extra parameters
    final List<String> extraParts = [];
    if (genre != null && genre.isNotEmpty) {
      extraParts.add('genre=${Uri.encodeComponent(genre)}');
    }
    if (skip > 0) {
      extraParts.add('skip=$skip');
    }
    if (extras != null) {
      for (final entry in extras.entries) {
        extraParts.add('${entry.key}=${Uri.encodeComponent(entry.value)}');
      }
    }

    if (extraParts.isNotEmpty) {
      url += '/${extraParts.join("&")}';
    }
    url += '.json';

    debugPrint('StremioService: Fetching catalog from $url');

    try {
      // Use a client that follows redirects
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(url));
        request.followRedirects = true;
        request.maxRedirects = 5;

        final streamedResponse = await client.send(request).timeout(_requestTimeout);
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode != 200) {
          debugPrint('StremioService: Catalog fetch failed: HTTP ${response.statusCode}');
          return [];
        }

        final Map<String, dynamic> data = json.decode(response.body);
        final metasRaw = data['metas'] as List<dynamic>?;

        if (metasRaw == null || metasRaw.isEmpty) {
          debugPrint('StremioService: Catalog returned no items');
          return [];
        }

        // Keep all items with valid ID (not just IMDB) - supports TV channels, etc.
        final metas = metasRaw
            .map((m) => StremioMeta.fromJson(m as Map<String, dynamic>))
            .where((m) => m.hasValidId)
            .toList();

        debugPrint('StremioService: Catalog returned ${metas.length} valid items');
        return metas;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('StremioService: Error fetching catalog: $e');
      return [];
    }
  }

  /// Fetch content from multiple catalogs at once
  ///
  /// Useful for "Browse" mode to show content from all catalog sources
  Future<Map<String, List<StremioMeta>>> fetchAllCatalogs({
    String? type, // Filter by type ('movie' or 'series')
    int limit = 20, // Limit per catalog
  }) async {
    final catalogAddons = await getCatalogAddons();
    final results = <String, List<StremioMeta>>{};

    for (final addon in catalogAddons) {
      for (final catalog in addon.catalogs) {
        // Skip if type filter is set and doesn't match
        if (type != null && catalog.type != type) continue;

        final key = '${addon.name}: ${catalog.name}';
        try {
          final metas = await fetchCatalog(addon, catalog);
          if (metas.isNotEmpty) {
            results[key] = metas.take(limit).toList();
          }
        } catch (e) {
          debugPrint('StremioService: Error fetching $key: $e');
        }
      }
    }

    return results;
  }

  /// Fetch homepage content from all catalog addons
  ///
  /// Returns a list of sections, each containing items from a specific catalog.
  /// Used for the "All" search source with no query (homepage-like view).
  Future<List<CatalogSection>> fetchHomepageContent({
    int itemsPerCatalog = 10,
    int maxSections = 10,
  }) async {
    final catalogAddons = await getCatalogAddons();
    final sections = <CatalogSection>[];

    if (catalogAddons.isEmpty) {
      debugPrint('StremioService: No catalog addons for homepage');
      return [];
    }

    // Fetch from each addon's catalogs in parallel
    final futures = <Future<CatalogSection?>>[];

    for (final addon in catalogAddons) {
      for (final catalog in addon.catalogs) {
        if (sections.length + futures.length >= maxSections) break;

        futures.add(_fetchCatalogSection(addon, catalog, itemsPerCatalog));
      }
      if (sections.length + futures.length >= maxSections) break;
    }

    final results = await Future.wait(futures);
    for (final section in results) {
      if (section != null && section.items.isNotEmpty) {
        sections.add(section);
      }
    }

    debugPrint('StremioService: Homepage loaded ${sections.length} sections');
    return sections;
  }

  /// Fetch a single catalog section for homepage
  Future<CatalogSection?> _fetchCatalogSection(
    StremioAddon addon,
    StremioAddonCatalog catalog,
    int limit,
  ) async {
    try {
      final items = await fetchCatalog(addon, catalog);
      if (items.isEmpty) return null;

      return CatalogSection(
        title: '${addon.name}: ${catalog.name}',
        addon: addon,
        catalog: catalog,
        items: items.take(limit).toList(),
      );
    } catch (e) {
      debugPrint('StremioService: Error fetching section ${addon.name}/${catalog.name}: $e');
      return null;
    }
  }

  /// Search within a specific addon's searchable catalogs
  ///
  /// Returns deduplicated results from all searchable catalogs of the addon.
  Future<List<StremioMeta>> searchAddonCatalogs(
    StremioAddon addon,
    String query,
  ) async {
    if (query.trim().isEmpty) return [];

    final encodedQuery = Uri.encodeComponent(query.trim());

    // Find all searchable catalogs in this addon
    final searchableCatalogs = addon.catalogs
        .where((c) => c.supportsSearch)
        .toList();

    if (searchableCatalogs.isEmpty) {
      debugPrint('StremioService: Addon ${addon.name} has no searchable catalogs');
      return [];
    }

    debugPrint(
      'StremioService: Searching ${searchableCatalogs.length} catalogs in ${addon.name} for "$query"',
    );

    // Search all catalogs in parallel
    final futures = <Future<List<StremioMeta>>>[];
    for (final catalog in searchableCatalogs) {
      futures.add(_searchSingleCatalog(addon, catalog, encodedQuery));
    }

    final results = await Future.wait(futures);

    // Flatten and deduplicate by ID
    final seen = <String, StremioMeta>{};
    for (final catalogResults in results) {
      for (final meta in catalogResults) {
        final existing = seen[meta.id];
        if (existing == null || _metadataScore(meta) > _metadataScore(existing)) {
          seen[meta.id] = meta;
        }
      }
    }

    final deduped = seen.values.toList();
    debugPrint('StremioService: Addon search returned ${deduped.length} results');
    return deduped;
  }

  /// Search across all catalogs that support search
  ///
  /// Returns deduplicated results by ID, keeping the best metadata.
  /// Supports all content types: movies, series, TV channels, anime, etc.
  Future<List<StremioMeta>> searchCatalogs(String query) async {
    if (query.trim().isEmpty) return [];

    final encodedQuery = Uri.encodeComponent(query.trim());
    final catalogAddons = await getCatalogAddons();

    if (catalogAddons.isEmpty) {
      debugPrint('StremioService: No catalog addons found');
      return [];
    }

    // Collect all (addon, catalog) pairs that support search
    // Search ALL addons, not just IMDB ones - supports TV channels, anime, etc.
    final searchableCatalogs = <({StremioAddon addon, StremioAddonCatalog catalog})>[];
    for (final addon in catalogAddons) {
      for (final catalog in addon.catalogs) {
        if (catalog.supportsSearch) {
          searchableCatalogs.add((addon: addon, catalog: catalog));
        }
      }
    }

    if (searchableCatalogs.isEmpty) {
      debugPrint('StremioService: No catalogs support search');
      return [];
    }

    debugPrint(
      'StremioService: Searching ${searchableCatalogs.length} catalogs for "$query"',
    );

    // Search all catalogs in parallel
    final futures = <Future<List<StremioMeta>>>[];

    for (final entry in searchableCatalogs) {
      futures.add(_searchSingleCatalog(entry.addon, entry.catalog, encodedQuery));
    }

    final allResults = await Future.wait(futures);

    // Flatten and deduplicate by ID (supports any ID format - IMDB, TV channels, etc.)
    final Map<String, StremioMeta> uniqueResults = {};

    for (final results in allResults) {
      for (final meta in results) {
        // Skip results without valid ID
        if (meta.id.isEmpty) continue;

        final existing = uniqueResults[meta.id];
        if (existing == null) {
          uniqueResults[meta.id] = meta;
        } else {
          // Keep the one with better metadata (prefer one with poster and rating)
          final existingScore = _metadataScore(existing);
          final newScore = _metadataScore(meta);
          if (newScore > existingScore) {
            uniqueResults[meta.id] = meta;
          }
        }
      }
    }

    final results = uniqueResults.values.toList();
    debugPrint('StremioService: Catalog search returned ${results.length} unique results');

    return results;
  }

  /// Search a single catalog
  Future<List<StremioMeta>> _searchSingleCatalog(
    StremioAddon addon,
    StremioAddonCatalog catalog,
    String encodedQuery,
  ) async {
    // Build search URL: {baseUrl}/catalog/{type}/{id}/search={query}.json
    final url =
        '${addon.baseUrl}/catalog/${catalog.type}/${catalog.id}/search=$encodedQuery.json';

    debugPrint('StremioService: Searching catalog ${addon.name}/${catalog.name}');

    try {
      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(url));
        request.followRedirects = true;
        request.maxRedirects = 5;

        final streamedResponse = await client.send(request).timeout(_requestTimeout);
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode != 200) {
          debugPrint(
            'StremioService: ${addon.name}/${catalog.name} search failed: HTTP ${response.statusCode}',
          );
          return [];
        }

        final Map<String, dynamic> data = json.decode(response.body);
        final metasRaw = data['metas'] as List<dynamic>?;

        if (metasRaw == null || metasRaw.isEmpty) {
          return [];
        }

        // Keep all items with valid ID (not just IMDB) - supports TV channels, etc.
        final metas = metasRaw
            .map((m) => StremioMeta.fromJson(m as Map<String, dynamic>))
            .where((m) => m.hasValidId)
            .toList();

        debugPrint(
          'StremioService: ${addon.name}/${catalog.name} returned ${metas.length} results',
        );

        return metas;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('StremioService: ${addon.name}/${catalog.name} search error: $e');
      return [];
    }
  }

  /// Calculate metadata quality score (higher = better)
  int _metadataScore(StremioMeta meta) {
    int score = 0;
    if (meta.poster != null) score += 2;
    if (meta.imdbRating != null) score += 2;
    if (meta.year != null) score += 1;
    if (meta.description != null) score += 1;
    return score;
  }

  // ============================================================
  // Validation Methods
  // ============================================================

  /// Validate that an addon has useful resources
  ///
  /// Returns null if valid, or an error message if invalid.
  /// Accepts any addon that provides streams, catalogs, or subtitles.
  String? _validateAddon(StremioAddon addon) {
    final hasStreams = addon.supportsStreams;
    final hasCatalogs = addon.supportsCatalogs;
    final hasSubtitles = addon.resources.contains('subtitles');

    // Must have at least one useful resource
    if (!hasStreams && !hasCatalogs && !hasSubtitles) {
      return 'This addon doesn\'t provide streams, catalogs, or subtitles. '
          'Debrify requires addons with stream, catalog, or subtitle support.';
    }

    return null; // Valid
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

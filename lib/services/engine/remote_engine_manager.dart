import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

/// Information about a remote engine available for import
class RemoteEngineInfo {
  final String id;
  final String fileName;
  final String displayName;
  final String? description;
  final String? icon;

  const RemoteEngineInfo({
    required this.id,
    required this.fileName,
    required this.displayName,
    this.description,
    this.icon,
  });

  @override
  String toString() => 'RemoteEngineInfo(id: $id, displayName: $displayName)';
}

/// Cached metadata information
class _MetadataCache {
  final List<RemoteEngineInfo> engines;
  final DateTime fetchedAt;

  _MetadataCache({
    required this.engines,
    required this.fetchedAt,
  });

  bool get isExpired {
    final now = DateTime.now();
    final age = now.difference(fetchedAt);
    return age.inMinutes >= 5; // 5-minute TTL
  }
}

/// Manages fetching engine configurations from remote GitLab repository
class RemoteEngineManager {
  static const String _gitlabProject = 'mediacontent%2Fsearch-engines';
  static const String _branch = 'main';
  static const String _enginePath = 'torrents';
  static const String _metadataFileName = 'metadata.yaml';

  /// GitLab API URL to list files in the torrents directory
  static const String _apiBaseUrl = 'https://gitlab.com/api/v4/projects';

  /// Raw file URL for downloading YAML content
  static const String _rawBaseUrl = 'https://gitlab.com/mediacontent/search-engines/-/raw';

  http.Client _client;

  // In-memory cache for metadata.yaml with 5-minute TTL
  _MetadataCache? _metadataCache;

  RemoteEngineManager({http.Client? client}) : _client = client ?? http.Client();

  /// Helper method to fetch HTTP requests with proper timeout handling
  ///
  /// The Dart http package doesn't support direct request cancellation.
  /// When .timeout() throws, the underlying HTTP request continues running,
  /// creating orphaned connections that waste bandwidth and server resources.
  ///
  /// This method addresses the issue by:
  /// 1. Wrapping the HTTP call in a timeout
  /// 2. On timeout, closing the current client to terminate connections
  /// 3. Creating a new client for future requests
  /// 4. Providing clear error messages
  ///
  /// Note: This ensures that on timeout, the HTTP client is closed which
  /// terminates all active connections, preventing resource leaks.
  Future<http.Response> _fetchWithTimeout(
    Uri url, {
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? headers,
  }) async {
    try {
      // Perform the HTTP request with timeout
      final response = await _client.get(url, headers: headers).timeout(
        timeout,
        onTimeout: () {
          // This callback is called when timeout occurs
          // Close the client to terminate all active connections
          _client.close();

          // Create a new client for future requests
          _client = http.Client();

          // Throw a clear timeout error
          throw TimeoutException(
            'Request to ${url.host} timed out after ${timeout.inSeconds} seconds',
            timeout,
          );
        },
      );

      return response;
    } on TimeoutException {
      // Re-throw timeout exceptions with clear messaging
      rethrow;
    } catch (e) {
      // Handle other errors (network errors, etc.)
      debugPrint('RemoteEngineManager: HTTP request failed: $e');
      rethrow;
    }
  }

  /// Fetch list of available engines from GitLab repository
  ///
  /// NEW APPROACH: Fetches metadata.yaml (1 request) instead of fetching
  /// all individual YAML files (5+ requests). Falls back to old method if
  /// metadata.yaml is unavailable.
  ///
  /// Returns a list of [RemoteEngineInfo] with basic metadata
  Future<List<RemoteEngineInfo>> fetchAvailableEngines() async {
    try {
      // Check cache first
      if (_metadataCache != null && !_metadataCache!.isExpired) {
        debugPrint('RemoteEngineManager: Using cached metadata (age: ${DateTime.now().difference(_metadataCache!.fetchedAt).inSeconds}s)');
        return _metadataCache!.engines;
      }

      debugPrint('RemoteEngineManager: Fetching metadata.yaml from GitLab...');

      // Try new approach: fetch metadata.yaml
      try {
        final engines = await _fetchEnginesFromMetadata();

        // Cache the result
        _metadataCache = _MetadataCache(
          engines: engines,
          fetchedAt: DateTime.now(),
        );

        debugPrint('RemoteEngineManager: Successfully fetched ${engines.length} engines from metadata.yaml');
        return engines;
      } catch (e) {
        debugPrint('RemoteEngineManager: Failed to fetch metadata.yaml, falling back to old method: $e');

        // Fallback to old method: fetch file list and download all YAMLs
        return await _fetchEnginesLegacy();
      }
    } catch (e) {
      debugPrint('RemoteEngineManager: Failed to fetch available engines: $e');
      rethrow;
    }
  }

  /// NEW: Fetch engines from metadata.yaml file
  /// This is the optimized approach that requires only 1 HTTP request
  Future<List<RemoteEngineInfo>> _fetchEnginesFromMetadata() async {
    final metadataContent = await _fetchMetadata();

    // Parse metadata.yaml
    final yaml = loadYaml(metadataContent);
    if (yaml == null) {
      throw Exception('metadata.yaml is empty or invalid');
    }

    final version = yaml['version'] as String?;
    debugPrint('RemoteEngineManager: metadata.yaml version: $version');

    final enginesYaml = yaml['engines'];
    if (enginesYaml == null || enginesYaml is! List) {
      throw Exception('metadata.yaml missing "engines" list');
    }

    final engines = <RemoteEngineInfo>[];
    for (final engineEntry in enginesYaml) {
      if (engineEntry is! Map) continue;

      final name = engineEntry['name'] as String?;
      final path = engineEntry['path'] as String?;

      if (name == null || path == null) {
        debugPrint('RemoteEngineManager: Skipping invalid entry: $engineEntry');
        continue;
      }

      // Extract ID and fileName from path
      // Example: "torrents/pirate_bay.yaml" -> fileName="pirate_bay.yaml", id="pirate_bay"
      final fileName = path.split('/').last;
      final id = fileName.replaceAll('.yaml', '');

      engines.add(RemoteEngineInfo(
        id: id,
        fileName: fileName,
        displayName: name,
        // Note: metadata.yaml doesn't include icons or descriptions
        // These can be added to metadata.yaml in the future if needed
        icon: null,
        description: null,
      ));
    }

    return engines;
  }

  /// Fetch metadata.yaml from GitLab
  Future<String> _fetchMetadata() async {
    final url = '$_rawBaseUrl/$_branch/$_enginePath/$_metadataFileName';
    debugPrint('RemoteEngineManager: Fetching metadata from: $url');

    final response = await _fetchWithTimeout(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch metadata.yaml: HTTP ${response.statusCode}');
    }

    return response.body;
  }

  /// LEGACY: Old method that fetches file list then downloads all YAMLs
  /// Used as fallback if metadata.yaml is unavailable
  Future<List<RemoteEngineInfo>> _fetchEnginesLegacy() async {
    debugPrint('RemoteEngineManager: Using legacy method (fetching all YAML files)');

    // Step 1: Get file list from GitLab API
    final fileList = await _fetchFileList();

    // Step 2: Filter for .yaml files (exclude _defaults.yaml and metadata.yaml)
    final yamlFiles = fileList
        .where((file) =>
            file['name'].toString().endsWith('.yaml') &&
            !file['name'].toString().startsWith('_') &&
            file['name'].toString() != _metadataFileName)
        .toList();

    debugPrint('RemoteEngineManager: Found ${yamlFiles.length} engine files');

    // Step 3: Fetch metadata for each engine
    final engines = <RemoteEngineInfo>[];
    for (final file in yamlFiles) {
      final fileName = file['name'] as String;
      try {
        final info = await _fetchEngineInfo(fileName);
        if (info != null) {
          engines.add(info);
        }
      } catch (e) {
        debugPrint('RemoteEngineManager: Failed to fetch info for $fileName: $e');
        // Add with basic info if metadata fetch fails
        final id = fileName.replaceAll('.yaml', '');
        engines.add(RemoteEngineInfo(
          id: id,
          fileName: fileName,
          displayName: _formatDisplayName(id),
        ));
      }
    }

    return engines;
  }

  /// Fetch the list of files from GitLab repository
  Future<List<Map<String, dynamic>>> _fetchFileList() async {
    final url = '$_apiBaseUrl/$_gitlabProject/repository/tree?path=$_enginePath&ref=$_branch';
    debugPrint('RemoteEngineManager: Fetching file list from: $url');

    final response = await _fetchWithTimeout(
      Uri.parse(url),
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception('GitLab API returned ${response.statusCode}: ${response.body}');
    }

    final List<dynamic> files = json.decode(response.body);
    return files.cast<Map<String, dynamic>>();
  }

  /// Fetch engine info by downloading and parsing the YAML header
  Future<RemoteEngineInfo?> _fetchEngineInfo(String fileName) async {
    final yamlContent = await downloadEngineYaml(fileName);
    if (yamlContent == null) return null;

    try {
      final yaml = loadYaml(yamlContent);
      if (yaml == null) return null;

      final id = yaml['id'] as String? ?? fileName.replaceAll('.yaml', '');
      final displayName = yaml['display_name'] as String? ?? _formatDisplayName(id);
      final icon = yaml['icon'] as String?;

      return RemoteEngineInfo(
        id: id,
        fileName: fileName,
        displayName: displayName,
        icon: icon,
      );
    } catch (e) {
      debugPrint('RemoteEngineManager: Failed to parse YAML for $fileName: $e');
      return null;
    }
  }

  /// Download the full YAML content for an engine
  ///
  /// Returns the raw YAML string, or null if download fails
  Future<String?> downloadEngineYaml(String fileName) async {
    final url = '$_rawBaseUrl/$_branch/$_enginePath/$fileName';
    debugPrint('RemoteEngineManager: Downloading: $url');

    try {
      final response = await _fetchWithTimeout(Uri.parse(url));

      if (response.statusCode != 200) {
        debugPrint('RemoteEngineManager: Download failed with ${response.statusCode}');
        return null;
      }

      return response.body;
    } on TimeoutException catch (e) {
      debugPrint('RemoteEngineManager: Download timeout: $e');
      return null;
    } catch (e) {
      debugPrint('RemoteEngineManager: Download error: $e');
      return null;
    }
  }

  /// Format an ID into a display name (e.g., "pirate_bay" -> "Pirate Bay")
  String _formatDisplayName(String id) {
    return id
        .split('_')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : '')
        .join(' ');
  }

  /// Clear the metadata cache
  /// Useful for forcing a refresh or testing
  void clearCache() {
    debugPrint('RemoteEngineManager: Clearing metadata cache');
    _metadataCache = null;
  }

  /// Dispose of the HTTP client
  void dispose() {
    _client.close();
  }
}

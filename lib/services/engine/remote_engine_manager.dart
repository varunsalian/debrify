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

/// Manages fetching engine configurations from remote GitLab repository
class RemoteEngineManager {
  static const String _gitlabProject = 'mediacontent%2Fsearch-engines';
  static const String _branch = 'main';
  static const String _enginePath = 'torrents';

  /// GitLab API URL to list files in the torrents directory
  static const String _apiBaseUrl = 'https://gitlab.com/api/v4/projects';

  /// Raw file URL for downloading YAML content
  static const String _rawBaseUrl = 'https://gitlab.com/mediacontent/search-engines/-/raw';

  final http.Client _client;

  RemoteEngineManager({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch list of available engines from GitLab repository
  ///
  /// Returns a list of [RemoteEngineInfo] with basic metadata parsed from each YAML
  Future<List<RemoteEngineInfo>> fetchAvailableEngines() async {
    try {
      // Step 1: Get file list from GitLab API
      final fileList = await _fetchFileList();

      // Step 2: Filter for .yaml files (exclude _defaults.yaml)
      final yamlFiles = fileList
          .where((file) =>
              file['name'].toString().endsWith('.yaml') &&
              !file['name'].toString().startsWith('_'))
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
    } catch (e) {
      debugPrint('RemoteEngineManager: Failed to fetch available engines: $e');
      rethrow;
    }
  }

  /// Fetch the list of files from GitLab repository
  Future<List<Map<String, dynamic>>> _fetchFileList() async {
    final url = '$_apiBaseUrl/$_gitlabProject/repository/tree?path=$_enginePath&ref=$_branch';
    debugPrint('RemoteEngineManager: Fetching file list from: $url');

    final response = await _client.get(
      Uri.parse(url),
      headers: {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 30));

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
      final response = await _client.get(
        Uri.parse(url),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('RemoteEngineManager: Download failed with ${response.statusCode}');
        return null;
      }

      return response.body;
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

  /// Dispose of the HTTP client
  void dispose() {
    _client.close();
  }
}

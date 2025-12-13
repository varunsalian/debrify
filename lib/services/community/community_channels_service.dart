import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'community_channel_model.dart';

/// Service for fetching and managing community channel repositories
class CommunityChannelsService {
  static const String defaultRepoUrl =
      'https://gitlab.com/mediacontent/community-channels';

  /// Fetches the manifest from a given repository URL
  static Future<CommunityChannelManifest> fetchManifest(String repoUrl) async {
    // Ensure we have a valid URL
    final cleanedUrl = repoUrl.trim();
    if (cleanedUrl.isEmpty) {
      throw const FormatException('Repository URL cannot be empty');
    }

    // Construct the manifest URL
    // Support different Git hosting platforms
    final manifestUrl = _constructManifestUrl(cleanedUrl);

    try {
      // Fetch the manifest
      final response = await http.get(
        Uri.parse(manifestUrl),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Debrify TV App',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timed out while fetching manifest');
        },
      );

      if (response.statusCode == 200) {
        // Parse and return the manifest
        return CommunityChannelManifest.fromJsonString(response.body);
      } else if (response.statusCode == 404) {
        throw Exception('Manifest not found at the specified repository');
      } else {
        throw Exception(
          'Failed to fetch manifest. HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      if (e is FormatException) {
        throw Exception('Invalid manifest format: ${e.message}');
      } else if (e is http.ClientException) {
        throw Exception('Network error: ${e.message}');
      }
      rethrow;
    }
  }

  /// Downloads a channel file from the given URL
  static Future<Uint8List> downloadChannelFile(String channelUrl) async {
    if (channelUrl.isEmpty) {
      throw const FormatException('Channel URL cannot be empty');
    }

    try {
      final response = await http.get(
        Uri.parse(channelUrl),
        headers: {
          'User-Agent': 'Debrify TV App',
        },
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception('Request timed out while downloading channel');
        },
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else if (response.statusCode == 404) {
        throw Exception('Channel file not found');
      } else {
        throw Exception(
          'Failed to download channel. HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      if (e is http.ClientException) {
        throw Exception('Network error while downloading channel: ${e.message}');
      }
      rethrow;
    }
  }

  /// Constructs the manifest URL based on the repository URL
  static String _constructManifestUrl(String repoUrl) {
    final url = repoUrl.trim();

    // Handle GitLab URLs
    if (url.contains('gitlab.com')) {
      // Remove trailing slashes
      final cleanUrl = url.replaceAll(RegExp(r'/+$'), '');
      // GitLab raw file format: https://gitlab.com/user/repo/-/raw/main/manifest.json
      return '$cleanUrl/-/raw/main/manifest.json';
    }

    // Handle GitHub URLs
    if (url.contains('github.com')) {
      // Remove trailing slashes
      final cleanUrl = url.replaceAll(RegExp(r'/+$'), '');
      // Convert github.com to raw.githubusercontent.com
      final parts = cleanUrl.replaceFirst('https://github.com/', '').split('/');
      if (parts.length >= 2) {
        final owner = parts[0];
        final repo = parts[1];
        return 'https://raw.githubusercontent.com/$owner/$repo/main/manifest.json';
      }
    }

    // For custom URLs, assume the manifest is at /manifest.json
    if (!url.endsWith('/manifest.json')) {
      return url.endsWith('/') ? '${url}manifest.json' : '$url/manifest.json';
    }

    return url;
  }

  /// Validates a repository URL
  static bool isValidRepoUrl(String url) {
    try {
      final uri = Uri.parse(url.trim());
      return uri.hasScheme &&
             (uri.scheme == 'http' || uri.scheme == 'https') &&
             uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Gets a user-friendly error message for common errors
  static String getErrorMessage(dynamic error) {
    final errorString = error.toString();

    if (errorString.contains('timed out')) {
      return 'Request timed out. Please check your internet connection.';
    }
    if (errorString.contains('404') || errorString.contains('not found')) {
      return 'Channel repository not found. Please check the URL.';
    }
    if (errorString.contains('Network error')) {
      return 'Network error. Please check your internet connection.';
    }
    if (errorString.contains('Invalid manifest')) {
      return 'The repository has an invalid manifest format.';
    }

    return 'Error: ${error.toString()}';
  }
}
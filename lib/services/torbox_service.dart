import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/torbox_torrent.dart';
import '../models/torbox_user.dart';
import '../models/torbox_web_download.dart';

class TorboxService {
  static const String _baseUrl = 'https://api.torbox.app/v1/api';

  static Future<TorboxUser> getUserInfo(String apiKey) async {
    final uri = Uri.parse('$_baseUrl/user/me?settings=false');
    try {
      debugPrint('TorboxService: Requesting user info…');
      final headers = {
        'Authorization': _formatAuthHeader(apiKey),
        'Content-Type': 'application/json',
      };
      debugPrint(
        'TorboxService: Using Authorization header="${headers['Authorization']?.split(' ').first}"',
      );
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
          'TorboxService: Unexpected status ${response.statusCode}. Body: ${response.body}',
        );
        throw Exception('Failed to fetch user info: ${response.statusCode}');
      }

      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      final bool success = payload['success'] as bool? ?? false;
      if (!success) {
        final dynamic error = payload['error'];
        debugPrint(
          'TorboxService: Success flag false. Error: ${error ?? 'unknown'}. Payload: $payload',
        );
        throw Exception(error?.toString() ?? 'Torbox API returned an error');
      }

      final data = payload['data'];
      if (data is Map<String, dynamic>) {
        debugPrint('TorboxService: User info retrieved successfully.');
        return TorboxUser.fromJson(data);
      }

      debugPrint('TorboxService: Unexpected payload structure: $payload');
      throw Exception('Unexpected response format from Torbox');
    } catch (e) {
      debugPrint('TorboxService: Request failed: $e');
      throw Exception('Torbox request failed: $e');
    }
  }

  static Future<Map<String, dynamic>> getTorrents(
    String apiKey, {
    int offset = 0,
    int limit = 50,
    int? torrentId,
  }) async {
    final queryParameters = <String, String>{
      'bypass_cache': 'true',
    };
    if (torrentId != null) {
      queryParameters['id'] = '$torrentId';
    } else {
      queryParameters['offset'] = '$offset';
      queryParameters['limit'] = '$limit';
    }

    final uri = Uri.parse('$_baseUrl/torrents/mylist')
        .replace(queryParameters: queryParameters);

    try {
      if (torrentId != null) {
        debugPrint('TorboxService: Fetching torrent id=$torrentId');
      } else {
        debugPrint(
          'TorboxService: Fetching torrents offset=$offset limit=$limit',
        );
      }
      final headers = {
        'Authorization': _formatAuthHeader(apiKey),
        'Content-Type': 'application/json',
      };

      final response = await http.get(uri, headers: headers);

      if (response.statusCode != 200) {
        debugPrint(
          'TorboxService: Torrent fetch status ${response.statusCode}. Body: ${response.body}',
        );
        throw Exception('Failed to fetch torrents: ${response.statusCode}');
      }

      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      final bool success = payload['success'] as bool? ?? false;
      if (!success) {
        final dynamic error = payload['error'];
        debugPrint(
          'TorboxService: Torrent fetch error: ${error ?? 'unknown'}. Payload: $payload',
        );
        throw Exception(error?.toString() ?? 'Torbox API returned an error');
      }

      final data = payload['data'];
      if (torrentId != null) {
        if (data is Map<String, dynamic>) {
          final torrent = TorboxTorrent.fromJson(data);
          if (!torrent.isCachedOrCompleted) {
            debugPrint(
              'TorboxService: Torrent $torrentId not cached/completed yet',
            );
            return {
              'torrents': <TorboxTorrent>[],
              'hasMore': false,
              'torrent': null,
            };
          }
          return {
            'torrents': <TorboxTorrent>[torrent],
            'hasMore': false,
            'torrent': torrent,
          };
        }
        if (data is List) {
          final rawList = data.whereType<Map<String, dynamic>>().toList();
          final torrents = rawList
              .map(TorboxTorrent.fromJson)
              .where((torrent) => torrent.isCachedOrCompleted)
              .toList();
          final torrent = torrents.isNotEmpty ? torrents.first : null;
          return {
            'torrents': torrents,
            'hasMore': false,
            'torrent': torrent,
          };
        }
      }

      if (data is List) {
        final rawList = data.whereType<Map<String, dynamic>>().toList();
        final torrents = rawList
            .map(TorboxTorrent.fromJson)
            .where((torrent) => torrent.isCachedOrCompleted)
            .toList();
        final bool hasMore = torrentId == null && rawList.length == limit && rawList.isNotEmpty;
        debugPrint(
          'TorboxService: Retrieved ${torrents.length} cached torrents (raw=${rawList.length}). hasMore=$hasMore',
        );
        return {
          'torrents': torrents,
          'hasMore': hasMore,
          'torrent': torrents.isNotEmpty ? torrents.first : null,
        };
      }

      debugPrint('TorboxService: Torrent payload unexpected: $payload');
      throw Exception('Unexpected response format from Torbox');
    } catch (e) {
      debugPrint('TorboxService: Torrent request failed: $e');
      throw Exception('Torbox torrent request failed: $e');
    }
  }

  static Future<Set<String>> checkCachedTorrents({
    required String apiKey,
    required List<String> infoHashes,
    bool listFiles = false,
  }) async {
    if (infoHashes.isEmpty) return const <String>{};

    final headers = {
      'Authorization': _formatAuthHeader(apiKey),
      'Content-Type': 'application/json',
    };

    final sanitized = infoHashes
        .map((hash) => hash.trim().toLowerCase())
        .where((hash) => hash.isNotEmpty)
        .toSet()
        .toList();

    const int chunkSize = 90;
    const int maxConcurrent = 20;
    final Set<String> cached = <String>{};

    Future<void> processChunk(int start) async {
      final chunk = sanitized.sublist(
        start,
        math.min(start + chunkSize, sanitized.length),
      );

      final querySegments = <String>[
        'format=list',
        'list_files=${listFiles ? 'true' : 'false'}',
        ...chunk.map((hash) => 'hash=${Uri.encodeQueryComponent(hash)}'),
      ];
      final uri = Uri.parse(
        '$_baseUrl/torrents/checkcached?${querySegments.join('&')}',
      );

      try {
        debugPrint(
          'TorboxService: Checking cache for ${chunk.length} torrents (chunk start=$start)',
        );
        final response = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 60));

        if (response.statusCode != 200) {
          debugPrint(
            'TorboxService: checkcached status ${response.statusCode}. Body: ${response.body}',
          );
          throw Exception(
            'Failed to check Torbox cache: ${response.statusCode}',
          );
        }

        final Map<String, dynamic> payload =
            json.decode(response.body) as Map<String, dynamic>;
        final bool success = payload['success'] as bool? ?? false;
        if (!success) {
          final dynamic error = payload['error'];
          debugPrint('TorboxService: checkcached error: ${error ?? 'unknown'}');
          throw Exception(error?.toString() ?? 'Torbox cache check failed');
        }

        final data = payload['data'];
        if (data is List) {
          for (final entry in data) {
            if (entry is Map<String, dynamic>) {
              final hash = (entry['hash'] as String?)?.trim().toLowerCase();
              if (hash != null && hash.isNotEmpty) {
                cached.add(hash);
              }
            }
          }
        }
      } catch (e) {
        debugPrint(
          'TorboxService: checkcached chunk failed (ignored): $e',
        );
      }
    }

    final futures = <Future<void>>[];
    for (int start = 0; start < sanitized.length; start += chunkSize) {
      futures.add(processChunk(start));
      if (futures.length == maxConcurrent) {
        await Future.wait(futures);
        futures.clear();
      }
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    debugPrint('TorboxService: Cached hashes found ${cached.length}');
    return cached;
  }

  static String createZipPermalink(String apiKey, int torrentId) {
    final token = apiKey.trim();
    final uri = Uri.parse('$_baseUrl/torrents/requestdl').replace(
      queryParameters: {
        'token': token,
        'torrent_id': '$torrentId',
        'zip_link': 'true',
        'redirect': 'true',
      },
    );
    return uri.toString();
  }

  static Future<Map<String, dynamic>> createTorrent({
    required String apiKey,
    required String magnet,
    bool seed = true,
    bool allowZip = true,
    bool addOnlyIfCached = true,
  }) async {
    final uri = Uri.parse('$_baseUrl/torrents/createtorrent');
    final headers = {'Authorization': _formatAuthHeader(apiKey)};

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers)
      ..fields['magnet'] = magnet
      ..fields['seed'] = seed ? '1' : '0'
      ..fields['allow_zip'] = allowZip ? 'true' : 'false'
      ..fields['add_only_if_cached'] = addOnlyIfCached ? 'true' : 'false';

    try {
      debugPrint(
        'TorboxService: createtorrent magnet hash=${magnet.length >= 80 ? magnet.substring(0, 80) : magnet}',
      );
      final response = await request.send().timeout(
        const Duration(seconds: 20),
      );
      final body = await response.stream.bytesToString();
      debugPrint(
        'TorboxService: createtorrent status=${response.statusCode} body=$body',
      );

      // Parse the response body first
      final Map<String, dynamic> payload =
          json.decode(body) as Map<String, dynamic>;

      // For 400 errors, the body contains useful error info (like DOWNLOAD_NOT_CACHED)
      // Return the payload so the caller can check the error field
      if (response.statusCode == 400) {
        return payload;
      }

      // For other non-200 status codes, throw specific errors
      if (response.statusCode != 200) {
        if (response.statusCode == 401) {
          throw Exception('Invalid Torbox API key');
        } else if (response.statusCode == 403) {
          throw Exception('Access denied by Torbox');
        } else if (response.statusCode == 429) {
          throw Exception('Too many requests to Torbox. Please wait and try again');
        } else if (response.statusCode >= 500) {
          throw Exception('Torbox service is temporarily unavailable');
        }
        throw Exception('Failed to add torrent to Torbox');
      }

      return payload;
    } catch (e) {
      debugPrint('TorboxService: createTorrent failed: $e');
      rethrow;
    }
  }

  static Future<String> requestFileDownloadLink({
    required String apiKey,
    required int torrentId,
    required int fileId,
  }) async {
    final uri = Uri.parse('$_baseUrl/torrents/requestdl').replace(
      queryParameters: {
        'token': apiKey.trim(),
        'torrent_id': '$torrentId',
        'file_id': '$fileId',
        'zip_link': 'false',
        'redirect': 'false',
      },
    );

    final headers = {
      'Authorization': _formatAuthHeader(apiKey),
      'Content-Type': 'application/json',
    };

    try {
      debugPrint(
        'TorboxService: requestdl torrent=$torrentId file=$fileId url=${uri.toString()}',
      );
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
      debugPrint(
        'TorboxService: requestdl status=${response.statusCode} body=${response.body}',
      );
      if (response.isRedirect || response.statusCode == 302) {
        final redirectUrl = response.headers['location'];
        if (redirectUrl != null && redirectUrl.isNotEmpty) {
          debugPrint('TorboxService: requestdl returned redirect $redirectUrl');
          return redirectUrl;
        }
      }

      if (response.statusCode != 200) {
        if (response.statusCode == 401) {
          throw Exception('Invalid Torbox API key');
        } else if (response.statusCode == 403) {
          throw Exception('Access denied by Torbox');
        } else if (response.statusCode == 404) {
          throw Exception('File not found on Torbox');
        } else if (response.statusCode == 429) {
          throw Exception('Too many requests to Torbox. Please wait and try again');
        } else if (response.statusCode >= 500) {
          throw Exception('Torbox service is temporarily unavailable');
        }
        throw Exception('Failed to get download link from Torbox');
      }

      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      final bool success = payload['success'] as bool? ?? false;
      if (!success) {
        final dynamic error = payload['error'];
        throw Exception(error?.toString() ?? 'Torbox API reported an error');
      }

      final dynamic data = payload['data'];
      if (data is String && data.isNotEmpty) {
        return data;
      }

      throw Exception('Torbox API returned an unexpected payload: $payload');
    } catch (e) {
      debugPrint('TorboxService: requestFileDownloadLink failed: $e');
      rethrow;
    }
  }

  static Future<TorboxTorrent?> getTorrentById(
    String apiKey,
    int torrentId, {
    int attempts = 5,
    Duration delayBetweenAttempts = const Duration(milliseconds: 300),
  }) async {
    for (int attempt = 0; attempt < attempts; attempt++) {
      try {
        final result = await getTorrents(
          apiKey,
          torrentId: torrentId,
        );
        final TorboxTorrent? torrent =
            result['torrent'] as TorboxTorrent? ??
                _firstTorrent(result['torrents']);
        if (torrent != null) {
          return torrent;
        }
      } catch (e) {
        debugPrint('TorboxService: getTorrentById attempt ${attempt + 1} failed: $e');
      }
      if (attempt < attempts - 1) {
        await Future.delayed(delayBetweenAttempts);
      }
    }
    return null;
  }

  static TorboxTorrent? _firstTorrent(dynamic value) {
    if (value is List) {
      for (final item in value) {
        if (item is TorboxTorrent) {
          return item;
        }
      }
    }
    return null;
  }

  // ==================== WEB DOWNLOAD API METHODS ====================

  /// Fetch web downloads list with pagination
  static Future<Map<String, dynamic>> getWebDownloads(
    String apiKey, {
    int offset = 0,
    int limit = 50,
    int? webId,
  }) async {
    final queryParameters = <String, String>{
      'bypass_cache': 'true',
    };
    if (webId != null) {
      queryParameters['id'] = '$webId';
    } else {
      queryParameters['offset'] = '$offset';
      queryParameters['limit'] = '$limit';
    }

    final uri = Uri.parse('$_baseUrl/webdl/mylist')
        .replace(queryParameters: queryParameters);

    try {
      if (webId != null) {
        debugPrint('TorboxService: Fetching web download id=$webId');
      } else {
        debugPrint(
          'TorboxService: Fetching web downloads offset=$offset limit=$limit',
        );
      }
      final headers = {
        'Authorization': _formatAuthHeader(apiKey),
        'Content-Type': 'application/json',
      };

      final response = await http.get(uri, headers: headers);

      if (response.statusCode != 200) {
        debugPrint(
          'TorboxService: Web download fetch status ${response.statusCode}. Body: ${response.body}',
        );
        throw Exception('Failed to fetch web downloads: ${response.statusCode}');
      }

      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      final bool success = payload['success'] as bool? ?? false;
      if (!success) {
        final dynamic error = payload['error'];
        debugPrint(
          'TorboxService: Web download fetch error: ${error ?? 'unknown'}. Payload: $payload',
        );
        throw Exception(error?.toString() ?? 'Torbox API returned an error');
      }

      final data = payload['data'];
      if (data is List) {
        final rawList = data.whereType<Map<String, dynamic>>().toList();
        final webDownloads = rawList
            .map(TorboxWebDownload.fromJson)
            .where((wd) => wd.isCompleted)
            .toList();
        final bool hasMore = webId == null && rawList.length == limit && rawList.isNotEmpty;
        debugPrint(
          'TorboxService: Retrieved ${webDownloads.length} completed web downloads (raw=${rawList.length}). hasMore=$hasMore',
        );
        return {
          'webDownloads': webDownloads,
          'hasMore': hasMore,
        };
      }

      debugPrint('TorboxService: Web download payload unexpected: $payload');
      throw Exception('Unexpected response format from Torbox');
    } catch (e) {
      debugPrint('TorboxService: Web download request failed: $e');
      throw Exception('Torbox web download request failed: $e');
    }
  }

  /// Request download link for a web download file
  static Future<String> requestWebDownloadFileLink({
    required String apiKey,
    required int webId,
    required int fileId,
    bool zipLink = false,
  }) async {
    final uri = Uri.parse('$_baseUrl/webdl/requestdl').replace(
      queryParameters: {
        'token': apiKey.trim(),
        'web_id': '$webId',
        'file_id': '$fileId',
        'zip_link': zipLink ? 'true' : 'false',
      },
    );

    final headers = {
      'Authorization': _formatAuthHeader(apiKey),
      'Content-Type': 'application/json',
    };

    try {
      debugPrint(
        'TorboxService: requestWebDownloadFileLink webId=$webId fileId=$fileId zipLink=$zipLink',
      );
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
      debugPrint(
        'TorboxService: requestWebDownloadFileLink status=${response.statusCode}',
      );

      if (response.statusCode != 200) {
        if (response.statusCode == 401) {
          throw Exception('Invalid Torbox API key');
        } else if (response.statusCode == 403) {
          throw Exception('Access denied by Torbox');
        } else if (response.statusCode == 404) {
          throw Exception('File not found on Torbox');
        } else if (response.statusCode == 429) {
          throw Exception('Too many requests to Torbox. Please wait and try again');
        } else if (response.statusCode >= 500) {
          throw Exception('Torbox service is temporarily unavailable');
        }
        throw Exception('Failed to get download link from Torbox');
      }

      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      final bool success = payload['success'] as bool? ?? false;
      if (!success) {
        final dynamic error = payload['error'];
        throw Exception(error?.toString() ?? 'Torbox API reported an error');
      }

      final dynamic data = payload['data'];
      if (data is String && data.isNotEmpty) {
        return data;
      }

      throw Exception('Torbox API returned an unexpected payload: $payload');
    } catch (e) {
      debugPrint('TorboxService: requestWebDownloadFileLink failed: $e');
      rethrow;
    }
  }

  /// Request ZIP download link for entire web download
  static String createWebDownloadZipPermalink(String apiKey, int webId) {
    final token = apiKey.trim();
    final uri = Uri.parse('$_baseUrl/webdl/requestdl').replace(
      queryParameters: {
        'token': token,
        'web_id': '$webId',
        'zip_link': 'true',
        'redirect': 'true',
      },
    );
    return uri.toString();
  }

  /// Create a web download from a URL
  static Future<Map<String, dynamic>> createWebDownload({
    required String apiKey,
    required String link,
    String? name,
    String? password,
    bool asQueued = false,
    bool addOnlyIfCached = false,
  }) async {
    final uri = Uri.parse('$_baseUrl/webdl/createwebdownload');
    final headers = {'Authorization': _formatAuthHeader(apiKey)};

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers)
      ..fields['link'] = link
      ..fields['as_queued'] = asQueued ? 'true' : 'false'
      ..fields['add_only_if_cached'] = addOnlyIfCached ? 'true' : 'false';

    if (name != null && name.isNotEmpty) {
      request.fields['name'] = name;
    }
    if (password != null && password.isNotEmpty) {
      request.fields['password'] = password;
    }

    try {
      debugPrint(
        'TorboxService: createWebDownload link=${link.length >= 80 ? link.substring(0, 80) : link}',
      );
      final response = await request.send().timeout(
        const Duration(seconds: 60), // Longer timeout as per user's request
      );
      final body = await response.stream.bytesToString();
      debugPrint(
        'TorboxService: createWebDownload status=${response.statusCode} body=$body',
      );

      final Map<String, dynamic> payload =
          json.decode(body) as Map<String, dynamic>;

      if (response.statusCode == 400) {
        return payload;
      }

      if (response.statusCode != 200) {
        if (response.statusCode == 401) {
          throw Exception('Invalid Torbox API key');
        } else if (response.statusCode == 403) {
          throw Exception('Access denied by Torbox');
        } else if (response.statusCode == 429) {
          throw Exception('Too many requests to Torbox. Please wait and try again');
        } else if (response.statusCode >= 500) {
          throw Exception('Torbox service is temporarily unavailable');
        }
        throw Exception('Failed to add web download to Torbox');
      }

      return payload;
    } catch (e) {
      debugPrint('TorboxService: createWebDownload failed: $e');
      rethrow;
    }
  }

  /// Delete a web download
  static Future<void> deleteWebDownload({
    required String apiKey,
    required int webId,
  }) async {
    final uri = Uri.parse('$_baseUrl/webdl/controlwebdownload');
    final headers = {
      'Authorization': _formatAuthHeader(apiKey),
      'Content-Type': 'application/json',
    };

    final body = json.encode({
      'webdl_id': webId,
      'operation': 'delete',
    });

    try {
      debugPrint('TorboxService: deleteWebDownload webId=$webId');
      final response = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
          'TorboxService: deleteWebDownload status ${response.statusCode}. Body: ${response.body}',
        );
        throw Exception('Failed to delete web download: ${response.statusCode}');
      }

      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      final bool success = payload['success'] as bool? ?? false;
      if (!success) {
        final dynamic error = payload['error'];
        throw Exception(error?.toString() ?? 'Failed to delete web download');
      }

      debugPrint('TorboxService: Web download $webId deleted successfully');
    } catch (e) {
      debugPrint('TorboxService: deleteWebDownload failed: $e');
      rethrow;
    }
  }

  static String _formatAuthHeader(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.toLowerCase().startsWith('bearer ')) {
      return trimmed;
    }
    return 'Bearer $trimmed';
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/debrid_download.dart';
import '../models/rd_torrent.dart';
import '../services/storage_service.dart';

class DebridService {
  static const String _baseUrl = 'https://api.real-debrid.com/rest/1.0';

  // Get downloads list (legacy method)
  static Future<List<DebridDownload>> getDownloads(String apiKey) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/downloads?auth_token=$apiKey'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => DebridDownload.fromJson(json)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Invalid API key');
      } else {
        throw Exception('Failed to load downloads: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Get torrents list with pagination
  static Future<Map<String, dynamic>> getTorrents(String apiKey, {
    int page = 1,
    int limit = 100,
    String? filter,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };
      
      if (filter != null) {
        queryParams['filter'] = filter;
      }

      final uri = Uri.parse('$_baseUrl/torrents').replace(queryParameters: queryParams);
      
      print('DEBUG: Making API call to: ${uri.toString()}');
      print('DEBUG: Headers: Authorization: Bearer ${apiKey.substring(0, 4)}...');
      
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      );
      
      print('DEBUG: Response status: ${response.statusCode}');
      print('DEBUG: Response headers: ${response.headers}');
      if (response.statusCode == 200) {
        print('DEBUG: Response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final torrents = data.map((json) => RDTorrent.fromJson(json)).toList();
        
        // Get total count from headers
        final totalCount = int.tryParse(response.headers['X-Total-Count'] ?? '0') ?? 0;
        
        return {
          'torrents': torrents,
          'totalCount': totalCount,
          'hasMore': torrents.length >= limit, // If we got a full page, there might be more
        };
      } else if (response.statusCode == 204) {
        // No content - no torrents found
        return {
          'torrents': <RDTorrent>[],
          'totalCount': 0,
          'hasMore': false,
        };
      } else if (response.statusCode == 401) {
        throw Exception('Invalid API key');
      } else {
        throw Exception('Failed to load torrents: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Add magnet to Real Debrid
  static Future<Map<String, dynamic>> addMagnet(String apiKey, String magnetLink) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/torrents/addMagnet'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'magnet': magnetLink,
        },
      );

      if (response.statusCode == 201) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Invalid API key');
      } else {
        throw Exception('Failed to add magnet: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Get torrent info
  static Future<Map<String, dynamic>> getTorrentInfo(String apiKey, String torrentId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/torrents/info/$torrentId'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Invalid API key');
      } else {
        throw Exception('Failed to get torrent info: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Select files (select the largest file or all files)
  static Future<void> selectFiles(String apiKey, String torrentId, List<int> fileIds) async {
    try {
      String fileIdsString;
      if (fileIds.isEmpty) {
        fileIdsString = 'all';
      } else {
        fileIdsString = fileIds.join(',');
      }
      
      final response = await http.post(
        Uri.parse('$_baseUrl/torrents/selectFiles/$torrentId'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'files': fileIdsString,
        },
      );

      if (response.statusCode != 204) {
        if (response.statusCode == 401) {
          throw Exception('Invalid API key');
        } else {
          throw Exception('Failed to select files: ${response.statusCode}');
        }
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Unrestrict link
  static Future<Map<String, dynamic>> unrestrictLink(String apiKey, String link) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/unrestrict/link'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'link': link,
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Invalid API key');
      } else {
        throw Exception('Failed to unrestrict link: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Unrestrict multiple links
  static Future<List<Map<String, dynamic>>> unrestrictLinks(String apiKey, List<String> links) async {
    try {
      final futures = links.map((link) => unrestrictLink(apiKey, link));
      final results = await Future.wait(futures);
      return results;
    } catch (e) {
      throw Exception('Failed to unrestrict links: $e');
    }
  }

  // Delete torrent
  static Future<void> deleteTorrent(String apiKey, String torrentId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/torrents/delete/$torrentId'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      );

      if (response.statusCode != 204) {
        if (response.statusCode == 401) {
          throw Exception('Invalid API key');
        } else {
          throw Exception('Failed to delete torrent: ${response.statusCode}');
        }
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Complete workflow: Add magnet, select largest file, get download link
  static Future<String> addTorrentToDebrid(String apiKey, String magnetLink) async {
    try {
      // Step 1: Add magnet
      final addResponse = await addMagnet(apiKey, magnetLink);
      final torrentId = addResponse['id'];

      // Step 2: Get torrent info
      final torrentInfo = await getTorrentInfo(apiKey, torrentId);
      final files = torrentInfo['files'] as List<dynamic>;

      if (files.isEmpty) {
        await deleteTorrent(apiKey, torrentId);
        throw Exception('No files found in torrent');
      }

      // Step 3: Get file selection preference
      final fileSelection = await StorageService.getFileSelection();
      List<int> fileIdsToSelect = [];

      if (fileSelection == 'all') {
        // Select all files
        fileIdsToSelect = files.map((file) => file['id'] as int).toList();
      } else {
        // Select largest file (default behavior)
        int largestFileId = files[0]['id'];
        int largestSize = files[0]['bytes'];

        for (final file in files) {
          if (file['bytes'] > largestSize) {
            largestSize = file['bytes'];
            largestFileId = file['id'];
          }
        }
        fileIdsToSelect = [largestFileId];
      }

      // Step 4: Select files based on preference
      await selectFiles(apiKey, torrentId, fileIdsToSelect);

      // Step 5: Wait a bit and get updated torrent info
      await Future.delayed(const Duration(seconds: 2));
      final updatedInfo = await getTorrentInfo(apiKey, torrentId);
      final links = updatedInfo['links'] as List<dynamic>;

      if (links.isEmpty) {
        await deleteTorrent(apiKey, torrentId);
        throw Exception('File is not readily available in Real Debrid');
      }

      // Step 6: Unrestrict the link
      final unrestrictResponse = await unrestrictLink(apiKey, links[0]);
      final downloadLink = unrestrictResponse['download'];

      // Don't delete the torrent - let the user keep it in their Real Debrid account
      // The torrent will remain available for future downloads

      return downloadLink;
    } catch (e) {
      throw Exception('Failed to add torrent to Real Debrid: $e');
    }
  }
} 
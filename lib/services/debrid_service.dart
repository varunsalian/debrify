import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/debrid_download.dart';

class DebridService {
  static const String _baseUrl = 'https://api.real-debrid.com/rest/1.0';

  // Get downloads list
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

  // Select files (select the largest file)
  static Future<void> selectFiles(String apiKey, String torrentId, List<int> fileIds) async {
    try {
      final fileIdsString = fileIds.join(',');
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

      // Step 3: Find the largest file
      int largestFileId = files[0]['id'];
      int largestSize = files[0]['bytes'];

      for (final file in files) {
        if (file['bytes'] > largestSize) {
          largestSize = file['bytes'];
          largestFileId = file['id'];
        }
      }

      // Step 4: Select the largest file
      await selectFiles(apiKey, torrentId, [largestFileId]);

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
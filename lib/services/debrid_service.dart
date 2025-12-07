import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/debrid_download.dart';
import '../models/rd_torrent.dart';
import '../models/rd_user.dart';
import '../models/rd_file_node.dart';
import '../services/storage_service.dart';
import '../utils/file_utils.dart';
import '../utils/rd_folder_tree_builder.dart';

class DebridService {
  static const String _baseUrl = 'https://api.real-debrid.com/rest/1.0';

  // Get user information
  static Future<RDUser> getUserInfo(String apiKey) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return RDUser.fromJson(data);
      } else if (response.statusCode == 401) {
        throw Exception('Invalid API key');
      } else if (response.statusCode == 403) {
        throw Exception('Account locked');
      } else {
        throw Exception('Failed to get user info: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Validate API key by calling user endpoint
  static Future<bool> validateApiKey(String apiKey) async {
    try {
      await getUserInfo(apiKey);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Get downloads list with pagination
  static Future<Map<String, dynamic>> getDownloads(String apiKey, {
    int page = 1,
    int limit = 100,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      final uri = Uri.parse('$_baseUrl/downloads').replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        try {
          final List<dynamic> data = json.decode(response.body);
          final downloads = data.map((json) => DebridDownload.fromJson(json)).toList();
          
          // Get total count from headers
          final totalCount = int.tryParse(response.headers['X-Total-Count'] ?? '0') ?? 0;
          
          return {
            'downloads': downloads,
            'totalCount': totalCount,
            'hasMore': downloads.length >= limit, // If we got a full page, there might be more
          };
        } catch (e) {
          throw Exception('Failed to parse response data: $e');
        }
      } else if (response.statusCode == 204) {
        // No content - no downloads found
        return {
          'downloads': <DebridDownload>[],
          'totalCount': 0,
          'hasMore': false,
        };
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
      

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      );


      if (response.statusCode == 200) {
        try {
          final List<dynamic> data = json.decode(response.body);
          final torrents = data.map((json) => RDTorrent.fromJson(json)).toList();
          
          // Get total count from headers
          final totalCount = int.tryParse(response.headers['X-Total-Count'] ?? '0') ?? 0;
          
          return {
            'torrents': torrents,
            'totalCount': totalCount,
            'hasMore': torrents.length >= limit, // If we got a full page, there might be more
          };
        } catch (e) {
          throw Exception('Failed to parse response data: $e');
        }
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
        // Try to parse the error response from Real Debrid
        try {
          final errorData = json.decode(response.body);
          if (errorData is Map<String, dynamic> && errorData.containsKey('error')) {
            throw Exception(errorData['error'].toString());
          } else if (errorData is Map<String, dynamic> && errorData.containsKey('message')) {
            throw Exception(errorData['message'].toString());
          } else {
            throw Exception('Failed to unrestrict link: ${response.statusCode} - ${response.body}');
          }
        } catch (jsonError) {
          // If JSON parsing fails, return the raw response body
          throw Exception('Failed to unrestrict link: ${response.statusCode} - ${response.body}');
        }
      }
    } catch (e) {
      if (e.toString().contains('Exception:')) {
        // Re-throw our custom exceptions
        rethrow;
      } else {
        throw Exception('Network error: $e');
      }
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

  // Delete download
  static Future<void> deleteDownload(String apiKey, String downloadId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/downloads/delete/$downloadId'),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      );

      if (response.statusCode != 204) {
        if (response.statusCode == 401) {
          throw Exception('Invalid API key');
        } else {
          throw Exception('Failed to delete download: ${response.statusCode}');
        }
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Complete workflow: Add magnet, select largest file, get download link
  static Future<Map<String, dynamic>> addTorrentToDebrid(String apiKey, String magnetLink, {String? tempFileSelection}) async {
    try {
      // Step 1: Add magnet
      final addResponse = await addMagnet(apiKey, magnetLink);
      final torrentId = addResponse['id'];

      // Step 2: Get torrent info
      final torrentInfo = await getTorrentInfo(apiKey, torrentId);
      final files = (torrentInfo['files'] as List<dynamic>? ?? const []);

      if (files.isEmpty) {
        await deleteTorrent(apiKey, torrentId);
        throw Exception('No files found in torrent');
      }

      // Step 3: Get file selection preference (use temp selection if provided, otherwise use saved preference)
      final fileSelection = tempFileSelection ?? await StorageService.getFileSelection();
      List<int> fileIdsToSelect = [];

      if (fileSelection == 'all') {
        // Select all files
        fileIdsToSelect = files.map((file) => file['id'] as int).toList();
      } else if (fileSelection == 'video') {
        // Select all video files
        final videoFiles = files.where((file) {
          final fileName = file['name'] as String?;
          return fileName != null && FileUtils.isVideoFile(fileName);
        }).toList();
        fileIdsToSelect = videoFiles.map((file) => file['id'] as int).toList();
      } else if (fileSelection == 'smart') {
        // Smart mode: classify by largest file being a playable video, with game flag override
        // Normalize names using path when needed
        final normalizedFiles = files.map((file) {
          if (file is Map && (file['name'] == null || (file['name'] as String?)?.isEmpty == true)) {
            final path = file['path'] as String?;
            if (path != null && path.isNotEmpty) {
              final nameOnly = FileUtils.getFileName(path);
              return {...file, 'name': nameOnly};
            }
          }
          return file;
        }).toList();

        bool hasGameFlag = false;
        for (final f in normalizedFiles) {
          final name = (f is Map) ? (f['name'] as String? ?? f['path'] as String? ?? '') : '';
          final lower = name.toLowerCase();
          if (lower.endsWith('.iso') || lower.endsWith('.exe') || lower.endsWith('.msi') ||
              lower.endsWith('.dmg') || lower.endsWith('.pkg') || lower.endsWith('.img') ||
              lower.endsWith('.nrg') || lower.endsWith('.bin') || lower.endsWith('.cue') ||
              lower.contains('/crack') || lower.contains('\\crack') ||
              lower.contains('_commonredist')) {
            hasGameFlag = true;
            break;
          }
        }

        if (hasGameFlag) {
          // Non-media: select all files
          fileIdsToSelect = normalizedFiles.map((file) => file['id'] as int).toList();
        } else {
          // Find largest file
          Map largest = normalizedFiles[0] as Map;
          int largestSize = (largest['bytes'] as int?) ?? 0;
          for (final file in normalizedFiles) {
            final size = (file['bytes'] as int?) ?? 0;
            if (size > largestSize) {
              largestSize = size;
              largest = file as Map;
            }
          }

          final largestName = largest['name'] as String?;
          final isLargestVideo = largestName != null && FileUtils.isVideoFile(largestName);

          if (isLargestVideo) {
            // Media path: try all videos first
            final videoFiles = normalizedFiles.where((file) {
              final fileName = (file is Map) ? file['name'] as String? : null;
              return fileName != null && FileUtils.isVideoFile(fileName);
            }).toList();
            fileIdsToSelect = videoFiles.map((file) => file['id'] as int).toList();
          } else {
            // Non-media: select all files
            fileIdsToSelect = normalizedFiles.map((file) => file['id'] as int).toList();
          }
        }
      } else {
        // Select largest file (default behavior)
        int largestFileId = files[0]['id'] as int;
        int largestSize = files[0]['bytes'] as int;

        for (final file in files) {
          final fileSize = file['bytes'] as int?;
          if (fileSize != null && fileSize > largestSize) {
            largestSize = fileSize;
            largestFileId = file['id'] as int;
          }
        }
        fileIdsToSelect = [largestFileId];
      }

      // Step 4: Select files based on preference
      await selectFiles(apiKey, torrentId, fileIdsToSelect);

      // Step 5: Wait a bit and get updated torrent info
      await Future.delayed(const Duration(seconds: 2));
      final updatedInfo = await getTorrentInfo(apiKey, torrentId);
      List<dynamic> links = updatedInfo['links'] as List<dynamic>;

      // Smart media fallback chain if initial 'smart' video selection yielded no links
      if ((tempFileSelection ?? await StorageService.getFileSelection()) == 'smart') {
        // If we selected videos in smart mode and there are no links, try largest video then all files
        // Determine whether we selected videos by checking if fileIdsToSelect is not 'all' and all are videos
        final selectedIdsSet = fileIdsToSelect.toSet();
        final selectedAreVideos = selectedIdsSet.isNotEmpty && files.where((f) => selectedIdsSet.contains(f['id'] as int)).every((f) {
          final name = f['name'] as String?;
          return name != null && FileUtils.isVideoFile(name);
        });

        if (selectedAreVideos && links.isEmpty) {
          // Try largest video
          final videoFiles = files.where((f) {
            final name = f['name'] as String?;
            return name != null && FileUtils.isVideoFile(name);
          }).toList();
          if (videoFiles.isNotEmpty) {
            int largestVideoId = videoFiles.first['id'] as int;
            int largestVideoSize = (videoFiles.first['bytes'] as int?) ?? -1;
            for (final f in videoFiles) {
              final size = (f['bytes'] as int?) ?? -1;
              if (size > largestVideoSize) {
                largestVideoSize = size;
                largestVideoId = f['id'] as int;
              }
            }
            await selectFiles(apiKey, torrentId, [largestVideoId]);
            await Future.delayed(const Duration(seconds: 2));
            final updatedInfo2 = await getTorrentInfo(apiKey, torrentId);
            links = (updatedInfo2['links'] as List<dynamic>? ?? const []);
          }

          // If still empty, try all files
          if (links.isEmpty) {
            await selectFiles(apiKey, torrentId, []); // 'all'
            await Future.delayed(const Duration(seconds: 2));
            final updatedInfo3 = await getTorrentInfo(apiKey, torrentId);
            links = (updatedInfo3['links'] as List<dynamic>? ?? const []);
          }
        }
      }

      if (links.isEmpty) {
        await deleteTorrent(apiKey, torrentId);
        throw Exception('File is not readily available in Real Debrid');
      }

      // Step 6: Unrestrict the link
      final unrestrictResponse = await unrestrictLink(apiKey, links[0]);
      final downloadLink = unrestrictResponse['download'] as String?;
      
      if (downloadLink == null) {
        await deleteTorrent(apiKey, torrentId);
        throw Exception('Failed to get download link from Real Debrid');
      }

      // Don't delete the torrent - let the user keep it in their Real Debrid account
      // The torrent will remain available for future downloads

      return {
        'downloadLink': downloadLink,
        'torrentId': torrentId,
        'fileSelection': fileSelection,
        'links': links,
        'files': files, // Add the files information for lazy loading
        'updatedInfo': updatedInfo, // Add the full updated info
      };
    } catch (e) {
      throw Exception('Failed to add torrent to Real Debrid: $e');
    }
  }

  // Enhanced workflow for Magic TV: Prefer video files (all), fallback to largest video file
  static Future<Map<String, dynamic>> addTorrentToDebridPreferVideos(String apiKey, String magnetLink) async {
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

      // Step 3: Try selecting all video files first
      // Some RD responses might use different keys. If name is missing, try fallback to 'path'
      final normalizedFiles = files.map((file) {
        if (file is Map && (file['name'] == null || (file['name'] as String?)?.isEmpty == true)) {
          final path = file['path'] as String?;
          if (path != null && path.isNotEmpty) {
            final nameOnly = FileUtils.getFileName(path);
            return {...file, 'name': nameOnly};
          }
        }
        return file;
      }).toList();

      final videoFiles = normalizedFiles.where((file) {
        final fileName = (file is Map) ? file['name'] as String? : null;
        final isVideo = fileName != null && FileUtils.isVideoFile(fileName);
        return isVideo;
      }).toList();

      if (videoFiles.isNotEmpty) {
        final allVideoIds = videoFiles.map((file) => file['id'] as int).toList();
        try {
          await selectFiles(apiKey, torrentId, allVideoIds);
        } catch (e) {
          // Selection failed (e.g., 202 or other). Clean up and surface error.
          await deleteTorrent(apiKey, torrentId);
          throw Exception('Failed to select files for Real Debrid torrent: $e');
        }

        // Wait briefly and fetch updated links
        await Future.delayed(const Duration(seconds: 2));
        final updatedInfo = await getTorrentInfo(apiKey, torrentId);
        List<dynamic> links = (updatedInfo['links'] as List<dynamic>? ?? const []);

        // If no links yet, fallback to largest single video file
        if (links.isEmpty) {
          // Find largest video file
          int? largestVideoId;
          int largestVideoSize = -1;
          for (final file in videoFiles) {
            final size = (file['bytes'] as int?) ?? -1;
            if (size > largestVideoSize) {
              largestVideoSize = size;
              largestVideoId = file['id'] as int?;
            }
          }

          if (largestVideoId != null) {
            try {
              await selectFiles(apiKey, torrentId, [largestVideoId]);
            } catch (e) {
              await deleteTorrent(apiKey, torrentId);
              throw Exception('Failed to select files for Real Debrid torrent: $e');
            }
            await Future.delayed(const Duration(seconds: 2));
            final updatedInfo2 = await getTorrentInfo(apiKey, torrentId);
            links = (updatedInfo2['links'] as List<dynamic>? ?? const []);

            if (links.isEmpty) {
              await deleteTorrent(apiKey, torrentId);
              throw Exception('File is not readily available in Real Debrid');
            }

            final unrestrictResponse = await unrestrictLink(apiKey, links[0]);
            final downloadLink = unrestrictResponse['download'] as String?;
            if (downloadLink == null) {
              await deleteTorrent(apiKey, torrentId);
              throw Exception('Failed to get download link from Real Debrid');
            }

            return {
              'downloadLink': downloadLink,
              'torrentId': torrentId,
              'fileSelection': 'largest_video',
              'links': links,
              'files': files,
              'updatedInfo': updatedInfo2,
            };
          } else {
            await deleteTorrent(apiKey, torrentId);
            throw Exception('No video files found in torrent');
          }
        }

        // Unrestrict first link when all videos selection succeeded
        final unrestrictResponse = await unrestrictLink(apiKey, links[0]);
        final downloadLink = unrestrictResponse['download'] as String?;
        if (downloadLink == null) {
          await deleteTorrent(apiKey, torrentId);
          throw Exception('Failed to get download link from Real Debrid');
        }

        return {
          'downloadLink': downloadLink,
          'torrentId': torrentId,
          'fileSelection': 'video',
          'links': links,
          'files': files,
          'updatedInfo': updatedInfo,
        };
      }

      // If no video files found at all, fail early
      await deleteTorrent(apiKey, torrentId);
      throw Exception('No video files found in torrent');
    } catch (e) {
      throw Exception('Failed to add torrent (prefer videos): $e');
    }
  }

  // === New helper methods for folder navigation ===

  /// Get file nodes at root level of torrent
  static Future<List<RDFileNode>> getTorrentRootNodes(String apiKey, String torrentId) async {
    try {
      final info = await getTorrentInfo(apiKey, torrentId);
      final files = (info['files'] as List<dynamic>?) ?? [];

      if (files.isEmpty) {
        return [];
      }

      // Convert to proper Map format
      final filesMaps = files.map((f) => f as Map<String, dynamic>).toList();

      // Build the folder tree
      final tree = RDFolderTreeBuilder.buildTree(filesMaps);

      // Return root level items (handles both folders and files at root)
      return RDFolderTreeBuilder.getRootLevelNodes(tree);
    } catch (e) {
      throw Exception('Failed to get torrent file structure: $e');
    }
  }

  /// Build complete folder tree for a torrent
  static Future<RDFileNode> getTorrentFolderTree(String apiKey, String torrentId) async {
    try {
      final info = await getTorrentInfo(apiKey, torrentId);
      final files = (info['files'] as List<dynamic>?) ?? [];

      if (files.isEmpty) {
        return RDFileNode.folder(name: 'Empty', children: []);
      }

      // Convert to proper Map format
      final filesMaps = files.map((f) => f as Map<String, dynamic>).toList();

      // Build and return the complete folder tree
      final tree = RDFolderTreeBuilder.buildTree(filesMaps);

      return tree;
    } catch (e) {
      throw Exception('Failed to build torrent folder tree: $e');
    }
  }

  /// Unrestrict and get download URL for a specific file in a torrent
  static Future<String> getFileDownloadUrl(String apiKey, String torrentId, int linkIndex) async {
    try {
      // Get torrent info to get the links
      final info = await getTorrentInfo(apiKey, torrentId);
      final links = (info['links'] as List<dynamic>?) ?? [];

      if (linkIndex < 0 || linkIndex >= links.length) {
        throw Exception('Invalid link index: $linkIndex (torrent has ${links.length} links)');
      }

      final link = links[linkIndex] as String;

      // Unrestrict the link to get the download URL
      final unrestrictedData = await unrestrictLink(apiKey, link);
      final downloadUrl = unrestrictedData['download'] as String?;

      if (downloadUrl == null) {
        throw Exception('Failed to get download URL from Real-Debrid');
      }

      return downloadUrl;
    } catch (e) {
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
      throw Exception('Failed to get file download URL: $e');
    }
  }

  /// Get multiple download URLs for a list of files (with linkIndex)
  static Future<List<String>> getMultipleFileDownloadUrls(
    String apiKey,
    String torrentId,
    List<int> linkIndices,
  ) async {
    try {
      // Get torrent info once to get all links
      final info = await getTorrentInfo(apiKey, torrentId);
      final links = (info['links'] as List<dynamic>?) ?? [];

      // Validate all indices first
      for (final index in linkIndices) {
        if (index < 0 || index >= links.length) {
          throw Exception('Invalid link index: $index (torrent has ${links.length} links)');
        }
      }

      // Unrestrict all links in parallel
      final futures = linkIndices.map((index) async {
        final link = links[index] as String;
        final unrestrictedData = await unrestrictLink(apiKey, link);
        final downloadUrl = unrestrictedData['download'] as String?;

        if (downloadUrl == null) {
          throw Exception('Failed to get download URL for link index $index');
        }

        return downloadUrl;
      });

      return await Future.wait(futures);
    } catch (e) {
      if (e.toString().contains('Exception:')) {
        rethrow;
      }
      throw Exception('Failed to get multiple file download URLs: $e');
    }
  }
} 
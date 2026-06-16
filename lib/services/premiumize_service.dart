import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/premiumize_user.dart';
import '../models/premiumize_file.dart';
import '../models/premiumize_folder_item.dart';
import '../models/premiumize_transfer.dart';

class PremiumizeService {
  static const String _baseUrl = 'https://www.premiumize.me/api';

  /// Fetches account info for the given API key. Throws on any failure
  /// (network error, bad key, or an error status from Premiumize).
  static Future<PremiumizeUser> getUserInfo(String apiKey) async {
    final uri = Uri.parse(
      '$_baseUrl/account/info',
    ).replace(queryParameters: {'apikey': apiKey});
    try {
      debugPrint('PremiumizeService: Requesting account info…');
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
          'PremiumizeService: Unexpected status ${response.statusCode}. Body: ${response.body}',
        );
        throw Exception('Failed to fetch account info: ${response.statusCode}');
      }

      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      final String status = payload['status']?.toString() ?? '';
      if (status != 'success') {
        final message = payload['message']?.toString() ?? 'unknown error';
        debugPrint('PremiumizeService: API returned error: $message');
        throw Exception(message);
      }

      debugPrint('PremiumizeService: Account info retrieved successfully.');
      return PremiumizeUser.fromJson(payload);
    } catch (e) {
      debugPrint('PremiumizeService: Request failed: $e');
      throw Exception('Premiumize request failed: $e');
    }
  }

  /// Checks whether each of [items] (magnet links / infohashes / links) is
  /// cached. Returns a list of booleans aligned to [items]. This call does NOT
  /// consume fair-use quota. Returns all-false on any error (so the caller can
  /// degrade gracefully rather than blocking the flow).
  // cache/check is sent as POST (no URL-length ceiling) and chunked so a large
  // batch of search results is split across several requests run with limited
  // concurrency. items may be magnet links OR bare infohashes.
  static const int _cacheChunkSize = 100;
  static const int _cacheMaxConcurrent = 6;

  static Future<List<bool>> checkCache(String apiKey, List<String> items) async {
    if (items.isEmpty) return const [];
    // Default to false; each successful chunk fills in its slots.
    final result = List<bool>.filled(items.length, false);

    Future<void> processChunk(int start) async {
      final end = math.min(start + _cacheChunkSize, items.length);
      final chunk = items.sublist(start, end);
      try {
        // Build the form body manually: package:http's Map body only supports
        // Map<String,String> (no repeated keys / list values), but cache/check
        // needs a repeated items[] array. Keep apikey in the body too so it
        // stays out of the URL.
        final body = StringBuffer('apikey=${Uri.encodeQueryComponent(apiKey)}');
        for (final item in chunk) {
          body.write('&items%5B%5D=${Uri.encodeQueryComponent(item)}');
        }
        final response = await http
            .post(
              Uri.parse('$_baseUrl/cache/check'),
              headers: const {
                'Content-Type': 'application/x-www-form-urlencoded',
              },
              body: body.toString(),
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          debugPrint(
            'PremiumizeService: cache/check status ${response.statusCode} (chunk @$start)',
          );
          return;
        }
        final payload = json.decode(response.body);
        if (payload is! Map || payload['status']?.toString() != 'success') {
          return;
        }
        final responseList = payload['response'];
        if (responseList is List) {
          for (var i = 0; i < chunk.length; i++) {
            if (i < responseList.length && responseList[i] == true) {
              result[start + i] = true;
            }
          }
        }
      } catch (e) {
        // Non-fatal: leave this chunk's slots false so the flow continues.
        debugPrint('PremiumizeService: cache/check chunk @$start failed: $e');
      }
    }

    final futures = <Future<void>>[];
    for (int start = 0; start < items.length; start += _cacheChunkSize) {
      futures.add(processChunk(start));
      if (futures.length == _cacheMaxConcurrent) {
        await Future.wait(futures);
        futures.clear();
      }
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    debugPrint(
      'PremiumizeService: cache/check ${result.where((c) => c).length}/${items.length} cached',
    );
    return result;
  }

  /// Convenience for a single item.
  static Future<bool> isCached(String apiKey, String item) async {
    final results = await checkCache(apiKey, [item]);
    return results.isNotEmpty && results.first;
  }

  /// Re-resolves ready-to-use direct download links for the torrent identified
  /// by [infohash]. Convenience wrapper around [directDownload] that builds the
  /// magnet for the caller. Used to refresh playlist links at playback time.
  static Future<List<PremiumizeFile>> resolveFilesByHash(
    String apiKey,
    String infohash,
  ) {
    return directDownload(apiKey, 'magnet:?xt=urn:btih:$infohash');
  }

  /// Resolves [src] (a magnet link / supported link) into ready-to-use direct
  /// download links for every file it contains. Works for cached content
  /// instantly. Throws on error (bad key, not available, etc.).
  ///
  /// Note: generating direct links consumes fair-use points on success.
  static Future<List<PremiumizeFile>> directDownload(
    String apiKey,
    String src,
  ) async {
    final uri = Uri.parse(
      '$_baseUrl/transfer/directdl',
    ).replace(queryParameters: {'apikey': apiKey});
    try {
      debugPrint('PremiumizeService: Requesting directdl…');
      final response = await http
          .post(uri, body: {'src': src})
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        debugPrint(
          'PremiumizeService: directdl status ${response.statusCode}.',
        );
        throw Exception('Failed to resolve links: ${response.statusCode}');
      }
      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      if (payload['status']?.toString() != 'success') {
        final message = payload['message']?.toString() ?? 'unknown error';
        throw Exception(message);
      }
      final content = payload['content'];
      if (content is! List) {
        throw Exception('Unexpected response format from Premiumize');
      }
      final files = content
          .whereType<Map<String, dynamic>>()
          .map(PremiumizeFile.fromJson)
          .where((f) => f.link.isNotEmpty)
          .toList();
      debugPrint('PremiumizeService: directdl returned ${files.length} files:');
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        // Avoid logging the signed direct link.
        debugPrint('  [$i] path="${f.path}" size=${f.size}');
      }
      return files;
    } catch (e) {
      debugPrint('PremiumizeService: directdl failed: $e');
      throw Exception('Premiumize directdl failed: $e');
    }
  }

  /// Result of looking up a transfer: either a folder/file id is ready,
  /// the transfer is still pending, or it's done but has no cloud item id.
  static Future<_TransferLookup> _lookupTransfer(
    String apiKey,
    String transferId,
  ) async {
    final uri = Uri.parse(
      '$_baseUrl/transfer/list',
    ).replace(queryParameters: {'apikey': apiKey});
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const _TransferLookup.pending();
      final payload = json.decode(response.body);
      if (payload is! Map || payload['status']?.toString() != 'success') {
        return const _TransferLookup.pending();
      }
      final transfers = payload['transfers'];
      if (transfers is! List) return const _TransferLookup.pending();
      for (final t in transfers) {
        if (t is! Map) continue;
        if (t['id']?.toString() != transferId) continue;
        final status = t['status']?.toString() ?? '';
        final folderId = t['folder_id']?.toString();
        final fileId = t['file_id']?.toString();
        if (folderId != null && folderId.isNotEmpty) {
          return _TransferLookup.folder(folderId);
        }
        if (fileId != null && fileId.isNotEmpty) {
          return _TransferLookup.file(fileId);
        }
        // Transfer found but no cloud id yet — still processing unless done.
        final done = status == 'finished' || status == 'seeding';
        return done ? const _TransferLookup.doneNoId() : const _TransferLookup.pending();
      }
      return const _TransferLookup.pending();
    } catch (e) {
      debugPrint('PremiumizeService: _lookupTransfer failed: $e');
      return const _TransferLookup.pending();
    }
  }

  /// Transfers [magnet] to the user's Premiumize cloud, waits up to
  /// [timeoutSeconds] for it to finish, then generates and returns a ZIP
  /// download URL. Throws on error or timeout.
  static Future<String> createTransferAndGenerateZip(
    String apiKey,
    String magnet, {
    int timeoutSeconds = 120,
  }) async {
    // Add to cloud — for cached content Premiumize fills the folder quickly.
    // (Premiumize dedupes, so re-adding an existing item is harmless.)
    final transferId = await createTransfer(apiKey, magnet);
    if (transferId.isEmpty) {
      throw Exception('Premiumize did not return a transfer id');
    }

    // Poll until the transfer has a cloud folder/file id ready.
    var lookup = await _lookupTransfer(apiKey, transferId);
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    while (lookup.isPending && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 4));
      lookup = await _lookupTransfer(apiKey, transferId);
    }

    if (lookup.folderId != null) {
      return _generateZip(apiKey, folderId: lookup.folderId!);
    }
    if (lookup.fileId != null) {
      return _generateZip(apiKey, fileId: lookup.fileId!);
    }
    throw Exception(
      lookup.isPending
          ? 'Timed out waiting for transfer to complete. Try again in a moment.'
          : 'Transfer completed but Premiumize returned no cloud item ID.',
    );
  }

  static Future<String> _generateZip(
    String apiKey, {
    String? folderId,
    String? fileId,
  }) async {
    assert(folderId != null || fileId != null);
    final uri = Uri.parse('$_baseUrl/zip/generate');
    try {
      final body = {'apikey': apiKey};
      if (folderId != null) body['folders[]'] = folderId;
      if (fileId != null) body['files[]'] = fileId;
      final response = await http
          .post(uri, body: body)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      if (payload['status']?.toString() != 'success') {
        final message = payload['message']?.toString() ?? 'unknown error';
        throw Exception(message);
      }
      final zipUrl = payload['location']?.toString() ?? '';
      if (zipUrl.isEmpty) throw Exception('No zip URL in response');
      return zipUrl;
    } catch (e) {
      debugPrint('PremiumizeService: generateZip failed: $e');
      throw Exception('Premiumize zip generation failed: $e');
    }
  }

  /// Adds [src] (a magnet link) to the user's Premiumize cloud for asynchronous
  /// fetching (used when the content is not yet cached). When [folderId] is
  /// supplied the content is placed inside that cloud folder. Returns the
  /// transfer id on success. Throws on error.
  static Future<String> createTransfer(
    String apiKey,
    String src, {
    String? folderId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/transfer/create',
    ).replace(queryParameters: {'apikey': apiKey});
    try {
      debugPrint('PremiumizeService: Creating transfer…');
      final body = {'src': src};
      if (folderId != null && folderId.isNotEmpty) {
        body['folder_id'] = folderId;
      }
      final response = await http
          .post(uri, body: body)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        debugPrint(
          'PremiumizeService: transfer/create status ${response.statusCode}. Body: ${response.body}',
        );
        throw Exception('Failed to add transfer: ${response.statusCode}');
      }
      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      if (payload['status']?.toString() != 'success') {
        final message = payload['message']?.toString() ?? 'unknown error';
        throw Exception(message);
      }
      return payload['id']?.toString() ?? '';
    } catch (e) {
      debugPrint('PremiumizeService: transfer/create failed: $e');
      throw Exception('Premiumize transfer/create failed: $e');
    }
  }

  // ── Cloud library browsing ─────────────────────────────────────────────────

  /// Lists the contents of a cloud folder. Pass a null/empty [folderId] for the
  /// root. Throws on error.
  static Future<PremiumizeFolderListing> listFolder(
    String apiKey, {
    String? folderId,
  }) async {
    final params = <String, String>{'apikey': apiKey};
    if (folderId != null && folderId.isNotEmpty) params['id'] = folderId;
    final uri =
        Uri.parse('$_baseUrl/folder/list').replace(queryParameters: params);
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Failed to list folder: ${response.statusCode}');
      }
      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      if (payload['status']?.toString() != 'success') {
        final message = payload['message']?.toString() ?? 'unknown error';
        throw Exception(message);
      }
      final content = payload['content'];
      final items = content is List
          ? content
              .whereType<Map<String, dynamic>>()
              .map(PremiumizeFolderItem.fromJson)
              .where((i) => i.id.isNotEmpty)
              .toList()
          : <PremiumizeFolderItem>[];
      return PremiumizeFolderListing(
        items: items,
        folderName: payload['name']?.toString(),
        parentId: payload['parent_id']?.toString(),
      );
    } catch (e) {
      debugPrint('PremiumizeService: folder/list failed: $e');
      throw Exception('Premiumize folder/list failed: $e');
    }
  }

  /// Recursively lists every file (no folders) under [folderId], stamping each
  /// with a [PremiumizeFolderItem.relativePath] preserving the folder
  /// structure. Used for folder play/download.
  static Future<List<PremiumizeFolderItem>> listFolderRecursive(
    String apiKey,
    String folderId, {
    String basePath = '',
    int depth = 0,
  }) async {
    // Guard against pathological/cyclic structures.
    if (depth > 12) return const [];
    final result = <PremiumizeFolderItem>[];
    final listing = await listFolder(apiKey, folderId: folderId);
    for (final item in listing.items) {
      if (item.isFolder) {
        final childBase =
            basePath.isEmpty ? item.name : '$basePath/${item.name}';
        result.addAll(
          await listFolderRecursive(
            apiKey,
            item.id,
            basePath: childBase,
            depth: depth + 1,
          ),
        );
      } else {
        final rel = basePath.isEmpty ? item.name : '$basePath/${item.name}';
        result.add(item.copyWith(relativePath: rel));
      }
    }
    return result;
  }

  /// Searches the user's entire cloud by name (server-side, recursive across
  /// all folders). Returns matching folders and files in the same shape as
  /// [listFolder]. Free (no fair-use cost). Throws on error.
  static Future<List<PremiumizeFolderItem>> searchCloud(
    String apiKey,
    String query,
  ) async {
    final uri = Uri.parse('$_baseUrl/folder/search')
        .replace(queryParameters: {'apikey': apiKey, 'q': query});
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Search failed: ${response.statusCode}');
      }
      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      if (payload['status']?.toString() != 'success') {
        final message = payload['message']?.toString() ?? 'unknown error';
        throw Exception(message);
      }
      final content = payload['content'];
      return content is List
          ? content
              .whereType<Map<String, dynamic>>()
              .map(PremiumizeFolderItem.fromJson)
              .where((i) => i.id.isNotEmpty)
              .toList()
          : <PremiumizeFolderItem>[];
    } catch (e) {
      debugPrint('PremiumizeService: folder/search failed: $e');
      throw Exception('Premiumize search failed: $e');
    }
  }

  /// Fetches fresh details (and a fresh direct [PremiumizeFile.link]) for a
  /// cloud file by its item id. Used to re-resolve playlist links that were
  /// saved from the cloud browser. Returns null if the item no longer exists.
  static Future<PremiumizeFile?> resolveItemById(
    String apiKey,
    String itemId,
  ) async {
    final uri = Uri.parse('$_baseUrl/item/details')
        .replace(queryParameters: {'apikey': apiKey, 'id': itemId});
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      if (payload['status']?.toString() != 'success') return null;
      final link = payload['link']?.toString() ?? '';
      final stream = payload['stream_link']?.toString();
      if (link.isEmpty) return null;
      return PremiumizeFile(
        path: payload['name']?.toString() ?? '',
        size: _intFrom(payload['size']),
        link: link,
        streamLink: (stream != null && stream.isNotEmpty) ? stream : null,
      );
    } catch (e) {
      debugPrint('PremiumizeService: item/details failed: $e');
      return null;
    }
  }

  static int _intFrom(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// Deletes a cloud folder. Throws on error.
  static Future<void> deleteFolder(String apiKey, String folderId) =>
      _deleteByEndpoint(apiKey, '/folder/delete', folderId);

  /// Deletes a single cloud file. Throws on error.
  static Future<void> deleteItem(String apiKey, String itemId) =>
      _deleteByEndpoint(apiKey, '/item/delete', itemId);

  static Future<void> _deleteByEndpoint(
    String apiKey,
    String endpoint,
    String id,
  ) async {
    final uri = Uri.parse('$_baseUrl$endpoint');
    try {
      final response = await http
          .post(uri, body: {'apikey': apiKey, 'id': id})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      if (payload['status']?.toString() != 'success') {
        final message = payload['message']?.toString() ?? 'unknown error';
        throw Exception(message);
      }
    } catch (e) {
      debugPrint('PremiumizeService: delete ($endpoint) failed: $e');
      throw Exception('Premiumize delete failed: $e');
    }
  }

  /// Generates a ZIP download URL for an entire cloud folder.
  static Future<String> generateFolderZip(String apiKey, String folderId) =>
      _generateZip(apiKey, folderId: folderId);

  /// Generates a ZIP download URL for a single cloud file.
  static Future<String> generateItemZip(String apiKey, String fileId) =>
      _generateZip(apiKey, fileId: fileId);

  // ── Transfers ───────────────────────────────────────────────────────────────

  /// Lists all transfers (queued/running/finished) on the account.
  static Future<List<PremiumizeTransfer>> listTransfers(String apiKey) async {
    final uri = Uri.parse('$_baseUrl/transfer/list')
        .replace(queryParameters: {'apikey': apiKey});
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Failed to list transfers: ${response.statusCode}');
      }
      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      if (payload['status']?.toString() != 'success') {
        final message = payload['message']?.toString() ?? 'unknown error';
        throw Exception(message);
      }
      final transfers = payload['transfers'];
      if (transfers is! List) return const [];
      return transfers
          .whereType<Map<String, dynamic>>()
          .map(PremiumizeTransfer.fromJson)
          .where((t) => t.id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('PremiumizeService: transfer/list failed: $e');
      throw Exception('Premiumize transfer/list failed: $e');
    }
  }

  /// Deletes a single transfer by id. Throws on error.
  static Future<void> deleteTransfer(String apiKey, String transferId) =>
      _deleteByEndpoint(apiKey, '/transfer/delete', transferId);

  /// Clears all finished transfers from the list. Throws on error.
  static Future<void> clearFinishedTransfers(String apiKey) async {
    final uri = Uri.parse('$_baseUrl/transfer/clearfinished');
    try {
      final response = await http
          .post(uri, body: {'apikey': apiKey})
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      if (payload['status']?.toString() != 'success') {
        final message = payload['message']?.toString() ?? 'unknown error';
        throw Exception(message);
      }
    } catch (e) {
      debugPrint('PremiumizeService: transfer/clearfinished failed: $e');
      throw Exception('Premiumize clear finished failed: $e');
    }
  }
}

class _TransferLookup {
  final String? folderId;
  final String? fileId;
  final bool isPending;

  const _TransferLookup.folder(String id)
      : folderId = id,
        fileId = null,
        isPending = false;

  const _TransferLookup.file(String id)
      : folderId = null,
        fileId = id,
        isPending = false;

  const _TransferLookup.doneNoId()
      : folderId = null,
        fileId = null,
        isPending = false;

  const _TransferLookup.pending()
      : folderId = null,
        fileId = null,
        isPending = true;
}

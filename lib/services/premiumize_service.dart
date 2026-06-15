import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/premiumize_user.dart';
import '../models/premiumize_file.dart';

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
  /// fetching (used when the content is not yet cached). Returns the transfer
  /// id on success. Throws on error.
  static Future<String> createTransfer(String apiKey, String src) async {
    final uri = Uri.parse(
      '$_baseUrl/transfer/create',
    ).replace(queryParameters: {'apikey': apiKey});
    try {
      debugPrint('PremiumizeService: Creating transfer…');
      final response = await http
          .post(uri, body: {'src': src})
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

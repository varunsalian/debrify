import 'dart:async';
import 'dart:convert';
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
  static Future<List<bool>> checkCache(String apiKey, List<String> items) async {
    if (items.isEmpty) return const [];
    try {
      final queryParameters = <String, dynamic>{
        'apikey': apiKey,
        'items[]': items,
      };
      final uri = Uri.parse(
        '$_baseUrl/cache/check',
      ).replace(queryParameters: queryParameters);
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint(
          'PremiumizeService: cache/check status ${response.statusCode}. Body: ${response.body}',
        );
        return List<bool>.filled(items.length, false);
      }
      final Map<String, dynamic> payload =
          json.decode(response.body) as Map<String, dynamic>;
      if (payload['status']?.toString() != 'success') {
        return List<bool>.filled(items.length, false);
      }
      final responseList = payload['response'];
      if (responseList is List) {
        final result = List<bool>.generate(
          items.length,
          (i) => i < responseList.length && responseList[i] == true,
        );
        debugPrint('PremiumizeService: cache/check result=$result');
        return result;
      }
      debugPrint('PremiumizeService: cache/check unexpected payload shape.');
      return List<bool>.filled(items.length, false);
    } catch (e) {
      debugPrint('PremiumizeService: cache/check failed: $e');
      return List<bool>.filled(items.length, false);
    }
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

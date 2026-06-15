import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/premiumize_user.dart';

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
}

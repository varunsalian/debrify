import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/torbox_user.dart';

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
      final response = await http.get(uri, headers: headers);

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

  static String _formatAuthHeader(String apiKey) {
    final trimmed = apiKey.trim();
    if (trimmed.toLowerCase().startsWith('bearer ')) {
      return trimmed;
    }
    return 'Bearer $trimmed';
  }
}

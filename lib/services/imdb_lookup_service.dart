import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ImdbLookupService {
  static const String _baseUrl = 'https://search.imdbot.workers.dev';

  /// Gets detailed information about a specific IMDB title
  /// Returns a Map containing the title's type (Movie or TVSeries)
  static Future<Map<String, dynamic>> getTitleDetails(String imdbId) async {
    if (imdbId.isEmpty) {
      throw ArgumentError('IMDB ID cannot be empty');
    }

    debugPrint('ImdbLookupService: Getting details for $imdbId');
    final uri = Uri.parse('$_baseUrl/?tt=$imdbId');

    try {
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        debugPrint(
          'ImdbLookupService: HTTP ${response.statusCode} for $imdbId body=${response.body}',
        );
        throw Exception('IMDb details lookup failed (HTTP ${response.statusCode})');
      }

      final dynamic payload = json.decode(response.body);
      if (payload is! Map<String, dynamic>) {
        throw Exception('Unexpected IMDb details response');
      }

      debugPrint('ImdbLookupService: Successfully fetched details for $imdbId');
      return payload;
    } catch (e) {
      debugPrint('ImdbLookupService: Error getting details for $imdbId: $e');
      rethrow;
    }
  }
}

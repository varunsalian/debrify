import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/advanced_search_selection.dart';

class ImdbLookupService {
  static const String _baseUrl = 'https://search.imdbot.workers.dev';

  static Future<List<ImdbTitleResult>> searchTitles(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      debugPrint('ImdbLookupService: Ignoring empty query');
      return const [];
    }

    debugPrint('ImdbLookupService: Searching "$trimmed"');
    final uri = Uri.parse('$_baseUrl/?q=${Uri.encodeComponent(trimmed)}');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      debugPrint(
        'ImdbLookupService: HTTP ${response.statusCode} for "$trimmed" body=${response.body}',
      );
      throw Exception('IMDb lookup failed (HTTP ${response.statusCode})');
    }

    final dynamic payload = json.decode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw Exception('Unexpected IMDb lookup response');
    }

    final descriptions = payload['description'];
    if (descriptions is! List) {
      debugPrint('ImdbLookupService: No description list for "$trimmed"');
      return const [];
    }

    final List<ImdbTitleResult> results = [];
    for (final item in descriptions) {
      if (item is Map<String, dynamic>) {
        final imdbId = (item['#IMDB_ID'] ?? '').toString();
        final title = (item['#TITLE'] ?? '').toString();
        if (imdbId.isEmpty || title.isEmpty) {
          continue;
        }
        results.add(ImdbTitleResult.fromJson(item));
      }
    }
    debugPrint('ImdbLookupService: Found ${results.length} match(es) for "$trimmed"');
    return results;
  }

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

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ParentsGuideCategory {
  final String id;
  final String label;
  final String severity;
  final int severityVotes;
  final int totalVotes;
  final List<ParentsGuideItem> items;

  const ParentsGuideCategory({
    required this.id,
    required this.label,
    required this.severity,
    required this.severityVotes,
    required this.totalVotes,
    required this.items,
  });
}

class ParentsGuideItem {
  final String text;
  final bool isSpoiler;

  const ParentsGuideItem({required this.text, this.isSpoiler = false});
}

class ParentsGuideResult {
  final List<ParentsGuideCategory> categories;

  const ParentsGuideResult({required this.categories});

  bool get isEmpty => categories.isEmpty;
}

class ImdbParentsGuideService {
  static const String _endpoint = 'https://graphql.imdb.com/';

  static const String _query = r'''
    query ParentsGuide($id: ID!) {
      title(id: $id) {
        parentsGuide {
          categories {
            category { id text }
            severity { text voteType votedFor }
            totalSeverityVotes
            guideItems(first: 20) {
              edges {
                node {
                  isSpoiler
                  text { plainText }
                }
              }
            }
          }
        }
      }
    }
  ''';

  static final Map<String, ParentsGuideResult> _cache = {};

  static Future<ParentsGuideResult?> fetch(String imdbId) async {
    if (imdbId.isEmpty) return null;

    final cached = _cache[imdbId];
    if (cached != null) return cached;

    try {
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0',
        },
        body: json.encode({
          'query': _query,
          'variables': {'id': imdbId},
        }),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'ParentsGuide: HTTP ${response.statusCode} for $imdbId',
        );
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final title = (data['data'] as Map?)?['title'] as Map?;
      final guide = title?['parentsGuide'] as Map?;
      final rawCategories = guide?['categories'] as List?;

      if (rawCategories == null || rawCategories.isEmpty) return null;

      final categories = <ParentsGuideCategory>[];
      for (final raw in rawCategories) {
        final cat = raw['category'] as Map?;
        final sev = raw['severity'] as Map?;
        final edges =
            (raw['guideItems'] as Map?)?['edges'] as List? ?? const [];

        categories.add(
          ParentsGuideCategory(
            id: cat?['id'] as String? ?? '',
            label: cat?['text'] as String? ?? '',
            severity: sev?['text'] as String? ?? 'None',
            severityVotes: sev?['votedFor'] as int? ?? 0,
            totalVotes: raw['totalSeverityVotes'] as int? ?? 0,
            items: [
              for (final edge in edges)
                ParentsGuideItem(
                  text:
                      (edge['node']?['text'] as Map?)?['plainText']
                          as String? ??
                      '',
                  isSpoiler: edge['node']?['isSpoiler'] as bool? ?? false,
                ),
            ].where((i) => i.text.isNotEmpty).toList(),
          ),
        );
      }

      final result = ParentsGuideResult(categories: categories);
      _cache[imdbId] = result;
      return result;
    } catch (e) {
      debugPrint('ParentsGuide: Error fetching for $imdbId: $e');
      return null;
    }
  }
}

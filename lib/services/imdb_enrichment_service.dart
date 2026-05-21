import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ImdbEnrichment {
  final String? plot;
  final String? runtime;
  final String? certificate;
  final double? rating;
  final int? voteCount;
  final String? director;
  final List<String> stars;
  final List<String> genres;
  final int? awardWins;
  final int? awardNominations;
  final String? tagline;
  final String? year;

  const ImdbEnrichment({
    this.plot,
    this.runtime,
    this.certificate,
    this.rating,
    this.voteCount,
    this.director,
    this.stars = const [],
    this.genres = const [],
    this.awardWins,
    this.awardNominations,
    this.tagline,
    this.year,
  });

  bool get hasAwards =>
      (awardWins != null && awardWins! > 0) ||
      (awardNominations != null && awardNominations! > 0);

  String? get awardsLine {
    if (!hasAwards) return null;
    final parts = <String>[];
    if (awardWins != null && awardWins! > 0) {
      parts.add('$awardWins win${awardWins! == 1 ? '' : 's'}');
    }
    if (awardNominations != null && awardNominations! > 0) {
      parts.add(
        '$awardNominations nomination${awardNominations! == 1 ? '' : 's'}',
      );
    }
    return parts.join(' · ');
  }

  String get voteCountFormatted {
    if (voteCount == null) return '';
    if (voteCount! >= 1000000) {
      return '${(voteCount! / 1000000).toStringAsFixed(1)}M';
    }
    if (voteCount! >= 1000) {
      return '${(voteCount! / 1000).toStringAsFixed(0)}K';
    }
    return voteCount.toString();
  }
}

class ImdbEnrichmentService {
  static const String _endpoint = 'https://graphql.imdb.com/';

  static const String _query = r'''
    query Enrich($id: ID!) {
      title(id: $id) {
        plot { plotText { plainText } }
        runtime { displayableProperty { value { plainText } } }
        certificate { rating }
        ratingsSummary { aggregateRating voteCount }
        titleGenres { genres { genre { text } } }
        principalCredits {
          category { text }
          credits(limit: 5) { name { nameText { text } } }
        }
        releaseYear { year }
        taglines(first: 1) { edges { node { text } } }
        prestigiousAwardSummary { wins nominations }
      }
    }
  ''';

  static final Map<String, ImdbEnrichment> _cache = {};

  static Future<ImdbEnrichment?> fetch(String imdbId) async {
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
        debugPrint('ImdbEnrichment: HTTP ${response.statusCode} for $imdbId');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final title = (data['data'] as Map?)?['title'] as Map?;
      if (title == null) return null;

      final plot =
          (title['plot'] as Map?)?['plotText'] as Map?;
      final runtime =
          ((title['runtime'] as Map?)?['displayableProperty']
              as Map?)?['value'] as Map?;
      final cert = title['certificate'] as Map?;
      final ratings = title['ratingsSummary'] as Map?;
      final genresRaw =
          (title['titleGenres'] as Map?)?['genres'] as List? ?? [];
      final credits = title['principalCredits'] as List? ?? [];
      final releaseYear = title['releaseYear'] as Map?;
      final taglines =
          (title['taglines'] as Map?)?['edges'] as List? ?? [];
      final awards = title['prestigiousAwardSummary'] as Map?;

      String? director;
      final stars = <String>[];
      for (final group in credits) {
        final category =
            (group['category'] as Map?)?['text'] as String? ?? '';
        final names = group['credits'] as List? ?? [];
        if (category == 'Director' || category == 'Directors') {
          if (names.isNotEmpty) {
            director = ((names.first['name'] as Map?)?['nameText']
                as Map?)?['text'] as String?;
          }
        } else if (category == 'Stars' || category == 'Star') {
          for (final c in names) {
            final name =
                ((c['name'] as Map?)?['nameText'] as Map?)?['text']
                    as String?;
            if (name != null) stars.add(name);
          }
        }
      }

      final parsedGenres = <String>[];
      for (final g in genresRaw) {
        final text = (g['genre'] as Map?)?['text'] as String?;
        if (text != null) parsedGenres.add(text);
      }

      String? tagline;
      if (taglines.isNotEmpty) {
        final node = (taglines.first as Map?)?['node'] as Map?;
        tagline = node?['text'] as String?;
      }

      final result = ImdbEnrichment(
        plot: plot?['plainText'] as String?,
        runtime: runtime?['plainText'] as String?,
        certificate: cert?['rating'] as String?,
        rating: (ratings?['aggregateRating'] as num?)?.toDouble(),
        voteCount: ratings?['voteCount'] as int?,
        director: director,
        stars: stars,
        genres: parsedGenres,
        awardWins: awards?['wins'] as int?,
        awardNominations: awards?['nominations'] as int?,
        tagline: tagline,
        year: releaseYear?['year']?.toString(),
      );

      _cache[imdbId] = result;
      return result;
    } catch (e) {
      debugPrint('ImdbEnrichment: Error fetching for $imdbId: $e');
      return null;
    }
  }
}

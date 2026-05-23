import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CastMember {
  final String name;
  final String? character;
  final String? imageUrl;
  const CastMember({required this.name, this.character, this.imageUrl});
}

class ImdbEnrichment {
  final String? plot;
  final String? runtime;
  final String? certificate;
  final double? rating;
  final int? voteCount;
  final String? director;
  final List<String> stars;
  final List<CastMember> cast;
  final List<String> genres;
  final int? awardWins;
  final int? awardNominations;
  final String? tagline;
  final String? year;
  final List<String> countries;
  final List<String> languages;
  final String? productionCompany;
  final String? boxOffice;
  final int? metacriticScore;
  final int? runtimeMinutes;

  const ImdbEnrichment({
    this.plot,
    this.runtime,
    this.certificate,
    this.rating,
    this.voteCount,
    this.director,
    this.stars = const [],
    this.cast = const [],
    this.genres = const [],
    this.awardWins,
    this.awardNominations,
    this.tagline,
    this.year,
    this.countries = const [],
    this.languages = const [],
    this.productionCompany,
    this.boxOffice,
    this.metacriticScore,
    this.runtimeMinutes,
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
        runtime {
          seconds
          displayableProperty { value { plainText } }
        }
        certificate { rating }
        ratingsSummary { aggregateRating voteCount }
        titleGenres { genres { genre { text } } }
        principalCredits {
          category { text }
          credits(limit: 8) {
            name {
              nameText { text }
              primaryImage { url }
            }
            ... on Cast { characters { name } }
          }
        }
        releaseYear { year }
        taglines(first: 1) { edges { node { text } } }
        prestigiousAwardSummary { wins nominations }
        countriesOfOrigin { countries { text } }
        spokenLanguages { spokenLanguages { text } }
        companyCredits(first: 1, filter: { categories: ["production"] }) {
          edges { node { company { companyText { text } } } }
        }
        lifetimeGross(boxOfficeArea: WORLDWIDE) {
          total { amount currency }
        }
        metacritic { metascore { score } }
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
      final runtimeMap = title['runtime'] as Map?;
      final runtimeDisplay =
          ((runtimeMap?['displayableProperty'] as Map?)?['value']
              as Map?)?['plainText'] as String?;
      final runtimeSecs = runtimeMap?['seconds'] as int?;
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
      final castList = <CastMember>[];
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
            final nameMap = c['name'] as Map?;
            final name =
                (nameMap?['nameText'] as Map?)?['text'] as String?;
            if (name == null) continue;
            stars.add(name);
            final imageUrl =
                (nameMap?['primaryImage'] as Map?)?['url'] as String?;
            final chars = c['characters'] as List?;
            String? character;
            if (chars != null && chars.isNotEmpty) {
              character = chars.first['name'] as String?;
            }
            castList.add(CastMember(
              name: name,
              character: character,
              imageUrl: imageUrl,
            ));
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

      // Countries
      final countriesRaw =
          (title['countriesOfOrigin'] as Map?)?['countries'] as List? ?? [];
      final countries = <String>[];
      for (final c in countriesRaw) {
        final t = (c as Map?)?['text'] as String?;
        if (t != null) countries.add(t);
      }

      // Languages
      final langsRaw =
          (title['spokenLanguages'] as Map?)?['spokenLanguages'] as List? ?? [];
      final languages = <String>[];
      for (final l in langsRaw) {
        final t = (l as Map?)?['text'] as String?;
        if (t != null) languages.add(t);
      }

      // Production company
      String? prodCompany;
      final prodEdges =
          (title['companyCredits'] as Map?)?['edges'] as List? ?? [];
      if (prodEdges.isNotEmpty) {
        prodCompany = (((prodEdges.first as Map?)?['node'] as Map?)?['company']
            as Map?)?['companyText']?['text'] as String?;
      }

      // Box office
      String? boxOffice;
      final grossMap = (title['lifetimeGross'] as Map?)?['total'] as Map?;
      if (grossMap != null) {
        final amount = grossMap['amount'] as num?;
        final currency = grossMap['currency'] as String? ?? 'USD';
        if (amount != null) {
          final sym = currency == 'USD' ? '\$' : currency;
          if (amount >= 1e9) {
            boxOffice = '$sym${(amount / 1e9).toStringAsFixed(2)}B';
          } else if (amount >= 1e6) {
            boxOffice = '$sym${(amount / 1e6).toStringAsFixed(1)}M';
          } else if (amount >= 1e3) {
            boxOffice = '$sym${(amount / 1e3).toStringAsFixed(0)}K';
          } else {
            boxOffice = '$sym${amount.toStringAsFixed(0)}';
          }
        }
      }

      // Metacritic
      final metaScore =
          ((title['metacritic'] as Map?)?['metascore'] as Map?)?['score'] as int?;

      final result = ImdbEnrichment(
        plot: plot?['plainText'] as String?,
        runtime: runtimeDisplay,
        certificate: cert?['rating'] as String?,
        rating: (ratings?['aggregateRating'] as num?)?.toDouble(),
        voteCount: ratings?['voteCount'] as int?,
        director: director,
        stars: stars,
        cast: castList,
        genres: parsedGenres,
        awardWins: awards?['wins'] as int?,
        awardNominations: awards?['nominations'] as int?,
        tagline: tagline,
        year: releaseYear?['year']?.toString(),
        countries: countries,
        languages: languages,
        productionCompany: prodCompany,
        boxOffice: boxOffice,
        metacriticScore: metaScore,
        runtimeMinutes: runtimeSecs != null ? (runtimeSecs / 60).round() : null,
      );

      _cache[imdbId] = result;
      return result;
    } catch (e) {
      debugPrint('ImdbEnrichment: Error fetching for $imdbId: $e');
      return null;
    }
  }
}

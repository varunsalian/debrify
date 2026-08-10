import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CastMember {
  final String name;
  final String? character;
  final String? imageUrl;
  const CastMember({required this.name, this.character, this.imageUrl});
}

/// One "Did You Know" card: a piece of trivia, a goof, or a quote.
class DidYouKnowEntry {
  /// 'Trivia' | 'Goof' | 'Quote' — the card eyebrow, ready for display.
  final String kind;
  final String text;
  const DidYouKnowEntry({required this.kind, required this.text});
}

/// A franchise-connected title (Followed by / Spin-off / …), navigable by its
/// IMDb id.
class UniverseTitle {
  final String imdbId;
  final String name;

  /// Display relation, as IMDb words it: 'Followed by', 'Spin-off', …
  final String relation;
  final String? posterUrl;
  final int? year;
  final int? endYear;
  final bool isSeries;

  const UniverseTitle({
    required this.imdbId,
    required this.name,
    required this.relation,
    this.posterUrl,
    this.year,
    this.endYear,
    this.isSeries = false,
  });

  String get yearLabel {
    if (year == null) return '';
    if (isSeries) return endYear != null ? '$year–$endYear' : '$year–';
    return '$year';
  }
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

  /// IMDb Top 250 position, or null when unranked.
  final int? top250Rank;

  /// IMDbPro-style popularity meter: current rank plus signed weekly drift
  /// (positive = climbing, negative = falling, 0/null = flat).
  final int? meterRank;
  final int? meterDelta;

  /// Interleaved trivia / goofs / quotes, spoilers already filtered out.
  final List<DidYouKnowEntry> didYouKnow;
  final int triviaTotal;
  final int goofsTotal;
  final int quotesTotal;

  /// Franchise connections (Followed by / Spin-off / …), deduped by title.
  final List<UniverseTitle> universe;

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
    this.top250Rank,
    this.meterRank,
    this.meterDelta,
    this.didYouKnow = const [],
    this.triviaTotal = 0,
    this.goofsTotal = 0,
    this.quotesTotal = 0,
    this.universe = const [],
  });

  int get didYouKnowTotal => triviaTotal + goofsTotal + quotesTotal;

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
        ratingsSummary { aggregateRating voteCount topRanking { rank } }
        meterRanking {
          currentRank
          rankChange { changeDirection difference }
        }
        trivia(first: 6) {
          total
          edges { node { isSpoiler text { plainText } } }
        }
        goofs(first: 3) {
          total
          edges { node { isSpoiler text { plainText } } }
        }
        quotes(first: 3) {
          total
          edges {
            node { isSpoiler lines { characters { character } text } }
          }
        }
        connections(
          first: 12
          filter: {
            categories: [
              "followed_by"
              "spin_off"
              "follows"
              "spin_off_from"
              "remake_of"
              "remade_as"
            ]
          }
        ) {
          edges {
            node {
              category { text }
              associatedTitle {
                id
                titleText { text }
                primaryImage { url }
                releaseYear { year endYear }
                titleType { id }
              }
            }
          }
        }
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
          // IMDb's edge started rejecting this endpoint with 403 unless the
          // request looks like it came from imdb.com. Without it every fetch
          // fails and the detail pages lose plot / cast / awards / details.
          'Referer': 'https://www.imdb.com/',
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

      // Honors — Top 250 position and the popularity meter.
      final top250 =
          ((ratings?['topRanking'] as Map?)?['rank']) as int?;
      final meter = title['meterRanking'] as Map?;
      final meterRank = meter?['currentRank'] as int?;
      int? meterDelta;
      final rankChange = meter?['rankChange'] as Map?;
      if (rankChange != null) {
        final diff = rankChange['difference'] as int? ?? 0;
        final dir = rankChange['changeDirection'] as String? ?? '';
        meterDelta = dir == 'DOWN' ? -diff : (dir == 'UP' ? diff : 0);
      }

      // Did You Know — trivia / goofs / quotes, spoilers dropped at the door.
      List<String> textsOf(String key) {
        final edges = (title[key] as Map?)?['edges'] as List? ?? [];
        final out = <String>[];
        for (final e in edges) {
          final node = (e as Map?)?['node'] as Map?;
          if (node == null || node['isSpoiler'] == true) continue;
          final text = (node['text'] as Map?)?['plainText'] as String?;
          if (text != null && text.trim().isNotEmpty) out.add(text.trim());
        }
        return out;
      }

      int totalOf(String key) => (title[key] as Map?)?['total'] as int? ?? 0;

      final quoteTexts = <String>[];
      for (final e in (title['quotes'] as Map?)?['edges'] as List? ?? []) {
        final node = (e as Map?)?['node'] as Map?;
        // Quotes carry spoiler flags like trivia and goofs do — same door
        // policy: a spoiler never reaches the card rail at all.
        if (node == null || node['isSpoiler'] == true) continue;
        final lines = node['lines'] as List? ?? [];
        final parts = <String>[];
        for (final l in lines) {
          final line = l as Map?;
          final text = line?['text'] as String?;
          if (text == null || text.trim().isEmpty) continue;
          final chars = line?['characters'] as List?;
          String? speaker;
          if (chars != null && chars.isNotEmpty) {
            speaker = (chars.first as Map?)?['character'] as String?;
          }
          // Single-line quotes read as the line alone; dialogue keeps its
          // speakers or the exchange makes no sense.
          parts.add(
            (lines.length > 1 && speaker != null) ? '$speaker: $text' : text,
          );
        }
        if (parts.isNotEmpty) quoteTexts.add(parts.join('\n'));
      }

      // Interleave so the rail mixes kinds instead of fronting all trivia:
      // trivia, trivia, goof, quote, trivia, goof, quote, trivia…
      final trivias = textsOf('trivia');
      final goofsList = textsOf('goofs');
      final dyk = <DidYouKnowEntry>[];
      var ti = 0, gi = 0, qi = 0;
      void takeTrivia() {
        if (ti < trivias.length) {
          dyk.add(DidYouKnowEntry(kind: 'Trivia', text: trivias[ti++]));
        }
      }

      takeTrivia();
      takeTrivia();
      while (ti < trivias.length ||
          gi < goofsList.length ||
          qi < quoteTexts.length) {
        if (gi < goofsList.length) {
          dyk.add(DidYouKnowEntry(kind: 'Goof', text: goofsList[gi++]));
        }
        if (qi < quoteTexts.length) {
          dyk.add(DidYouKnowEntry(kind: 'Quote', text: quoteTexts[qi++]));
        }
        takeTrivia();
      }

      // Universe — franchise connections, deduped by title id (IMDb lists
      // Better Call Saul under BOTH "Followed by" and "Spin-off").
      final universe = <UniverseTitle>[];
      final seenIds = <String>{};
      for (final e in (title['connections'] as Map?)?['edges'] as List? ?? []) {
        final node = (e as Map?)?['node'] as Map?;
        final assoc = node?['associatedTitle'] as Map?;
        final id = assoc?['id'] as String?;
        final name = (assoc?['titleText'] as Map?)?['text'] as String?;
        final relation = (node?['category'] as Map?)?['text'] as String?;
        if (id == null || name == null || relation == null) continue;
        if (!seenIds.add(id)) continue;
        final relYear = assoc?['releaseYear'] as Map?;
        final typeId = (assoc?['titleType'] as Map?)?['id'] as String? ?? '';
        universe.add(UniverseTitle(
          imdbId: id,
          name: name,
          relation: relation,
          posterUrl: (assoc?['primaryImage'] as Map?)?['url'] as String?,
          year: relYear?['year'] as int?,
          endYear: relYear?['endYear'] as int?,
          isSeries: typeId.startsWith('tv') && typeId != 'tvMovie',
        ));
      }

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
        top250Rank: top250,
        meterRank: meterRank,
        meterDelta: meterDelta,
        didYouKnow: dyk,
        triviaTotal: totalOf('trivia'),
        goofsTotal: totalOf('goofs'),
        quotesTotal: totalOf('quotes'),
        universe: universe,
      );

      _cache[imdbId] = result;
      return result;
    } catch (e) {
      debugPrint('ImdbEnrichment: Error fetching for $imdbId: $e');
      return null;
    }
  }
}

class ChannelHub {
  final String id;
  final String name;
  final List<SeriesInfo> series;
  final List<MovieInfo> movies;
  final DateTime createdAt;

  ChannelHub({
    required this.id,
    required this.name,
    required this.series,
    required this.movies,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'series': series.map((s) => s.toJson()).toList(),
      'movies': movies.map((m) => m.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ChannelHub.fromJson(Map<String, dynamic> json) {
    return ChannelHub(
      id: json['id'],
      name: json['name'],
      series: (json['series'] as List? ?? [])
          .map((s) => SeriesInfo.fromJson(s))
          .toList(),
      movies: (json['movies'] as List? ?? [])
          .map((m) => MovieInfo.fromJson(m))
          .toList(),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class SeriesInfo {
  final int id;
  final String name;
  final String? imageUrl;
  final String? originalImageUrl;
  final String? summary;
  final List<String> genres;
  final String? status;
  final double? rating;
  final String? premiered;
  final String? ended;
  final String? network;
  final String? language;

  SeriesInfo({
    required this.id,
    required this.name,
    this.imageUrl,
    this.originalImageUrl,
    this.summary,
    this.genres = const [],
    this.status,
    this.rating,
    this.premiered,
    this.ended,
    this.network,
    this.language,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imageUrl': imageUrl,
      'originalImageUrl': originalImageUrl,
      'summary': summary,
      'genres': genres,
      'status': status,
      'rating': rating,
      'premiered': premiered,
      'ended': ended,
      'network': network,
      'language': language,
    };
  }

  factory SeriesInfo.fromJson(Map<String, dynamic> json) {
    return SeriesInfo(
      id: json['id'],
      name: json['name'],
      imageUrl: json['imageUrl'],
      originalImageUrl: json['originalImageUrl'],
      summary: json['summary'],
      genres: List<String>.from(json['genres'] ?? []),
      status: json['status'],
      rating: json['rating']?.toDouble(),
      premiered: json['premiered'],
      ended: json['ended'],
      network: json['network'],
      language: json['language'],
    );
  }

  factory SeriesInfo.fromTVMazeShow(Map<String, dynamic> show) {
    final id = show['id'];
    final name = show['name'];
    
    if (id == null || name == null) {
      throw Exception('Invalid show data: missing id or name');
    }
    
    return SeriesInfo(
      id: id,
      name: name.toString(),
      imageUrl: show['image']?['medium']?.toString(),
      originalImageUrl: show['image']?['original']?.toString(),
      summary: show['summary']?.toString().replaceAll(RegExp(r'<[^>]*>'), ''),
      genres: (show['genres'] as List<dynamic>?)?.map((g) => g.toString()).toList() ?? [],
      status: show['status']?.toString(),
      rating: show['rating']?['average']?.toDouble(),
      premiered: show['premiered']?.toString(),
      ended: show['ended']?.toString(),
      network: show['network']?['name']?.toString(),
      language: show['language']?.toString(),
    );
  }
}

class MovieInfo {
  final String id;
  final String name;
  final String? imageUrl;
  final String? originalImageUrl;
  final String? summary;
  final List<String> genres;
  final double? rating;
  final String? year;
  final String? director;
  final List<String> actors;
  final String? duration;
  final String? language;

  MovieInfo({
    required this.id,
    required this.name,
    this.imageUrl,
    this.originalImageUrl,
    this.summary,
    this.genres = const [],
    this.rating,
    this.year,
    this.director,
    this.actors = const [],
    this.duration,
    this.language,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imageUrl': imageUrl,
      'originalImageUrl': originalImageUrl,
      'summary': summary,
      'genres': genres,
      'rating': rating,
      'year': year,
      'director': director,
      'actors': actors,
      'duration': duration,
      'language': language,
    };
  }

  factory MovieInfo.fromJson(Map<String, dynamic> json) {
    return MovieInfo(
      id: json['id'],
      name: json['name'],
      imageUrl: json['imageUrl'],
      originalImageUrl: json['originalImageUrl'],
      summary: json['summary'],
      genres: List<String>.from(json['genres'] ?? []),
      rating: json['rating']?.toDouble(),
      year: json['year'],
      director: json['director'],
      actors: List<String>.from(json['actors'] ?? []),
      duration: json['duration'],
      language: json['language'],
    );
  }

  factory MovieInfo.fromIMDBSearch(Map<String, dynamic> movie) {
    return MovieInfo(
      id: movie['#IMDB_ID'] ?? '',
      name: movie['#TITLE'] ?? '',
      imageUrl: movie['#IMG_POSTER'],
      originalImageUrl: movie['#IMG_POSTER'],
      year: movie['#YEAR']?.toString(),
    );
  }

  factory MovieInfo.fromIMDBDetail(Map<String, dynamic> detail) {
    final short = detail['short'];
    if (short == null || short['@type'] != 'Movie') {
      throw Exception('Not a movie');
    }

    return MovieInfo(
      id: short['url']?.toString().split('/').last ?? '',
      name: short['name']?.toString().replaceAll('&amp;', '&') ?? '',
      imageUrl: short['image'],
      originalImageUrl: short['image'],
      summary: short['description']?.toString().replaceAll('&amp;', '&'),
      genres: short['genre'] != null 
          ? (short['genre'] is List 
              ? List<String>.from(short['genre'])
              : [short['genre'].toString()])
          : [],
      rating: short['aggregateRating']?['ratingValue']?.toDouble(),
      year: short['datePublished']?.toString().substring(0, 4),
      director: short['director']?['name'] ?? short['director'],
      actors: short['actor'] != null
          ? (short['actor'] is List
              ? List<String>.from(short['actor'].map((a) => a['name'] ?? a.toString()))
              : [short['actor']['name'] ?? short['actor'].toString()])
          : [],
      duration: short['duration'],
      language: short['inLanguage'],
    );
  }
} 
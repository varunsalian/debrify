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
  final int createdAt;

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
    required this.createdAt,
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
      'createdAt': createdAt,
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
      createdAt: json['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
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
      createdAt: DateTime.now().millisecondsSinceEpoch,
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
  final int createdAt;
  final int runtimeSeconds;

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
    required this.createdAt,
    required this.runtimeSeconds,
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
      'createdAt': createdAt,
      'runtimeSeconds': runtimeSeconds,
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
      createdAt: json['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      runtimeSeconds: json['runtimeSeconds'] ?? 3600, // Default to 60 minutes (3600 seconds)
    );
  }

  factory MovieInfo.fromIMDBSearch(Map<String, dynamic> movie) {
    return MovieInfo(
      id: movie['#IMDB_ID'] ?? '',
      name: movie['#TITLE'] ?? '',
      imageUrl: movie['#IMG_POSTER'],
      originalImageUrl: movie['#IMG_POSTER'],
      year: movie['#YEAR']?.toString(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      runtimeSeconds: 3600, // Default to 60 minutes (3600 seconds) for search results
    );
  }

  factory MovieInfo.fromIMDBDetail(Map<String, dynamic> detail) {
    final short = detail['short'];
    if (short == null || short['@type'] != 'Movie') {
      throw Exception('Not a movie');
    }

    // Extract runtime from the detail response
    int runtimeSeconds = 3600; // Default to 60 minutes (3600 seconds)
    
    try {
      // Check for runtime in the 'top' section first
      final top = detail['top'];
      if (top != null && top['runtime'] != null && top['runtime']['seconds'] != null) {
        runtimeSeconds = top['runtime']['seconds'] as int;
        print('DEBUG: Movie "${short['name']}" runtime saved: $runtimeSeconds seconds');
      } else {
        // Fallback to root level runtime
        final runtime = detail['runtime'];
        if (runtime != null && runtime['seconds'] != null) {
          runtimeSeconds = runtime['seconds'] as int;
          print('DEBUG: Movie "${short['name']}" runtime saved: $runtimeSeconds seconds');
        } else {
          print('DEBUG: Movie "${short['name']}" - no runtime found, using default: $runtimeSeconds seconds');
        }
      }
    } catch (e) {
      print('DEBUG: Movie "${short['name']}" - error extracting runtime: $e, using default: $runtimeSeconds seconds');
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
      createdAt: DateTime.now().millisecondsSinceEpoch,
      runtimeSeconds: runtimeSeconds,
    );
  }
} 
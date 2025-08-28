class ChannelHub {
  final String id;
  final String name;
  final List<SeriesInfo> series;
  final DateTime createdAt;

  ChannelHub({
    required this.id,
    required this.name,
    required this.series,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'series': series.map((s) => s.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ChannelHub.fromJson(Map<String, dynamic> json) {
    return ChannelHub(
      id: json['id'],
      name: json['name'],
      series: (json['series'] as List)
          .map((s) => SeriesInfo.fromJson(s))
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
    return SeriesInfo(
      id: show['id'],
      name: show['name'],
      imageUrl: show['image']?['medium'],
      originalImageUrl: show['image']?['original'],
      summary: show['summary']?.toString().replaceAll(RegExp(r'<[^>]*>'), ''),
      genres: List<String>.from(show['genres'] ?? []),
      status: show['status'],
      rating: show['rating']?['average']?.toDouble(),
      premiered: show['premiered'],
      ended: show['ended'],
      network: show['network']?['name'],
      language: show['language'],
    );
  }
} 
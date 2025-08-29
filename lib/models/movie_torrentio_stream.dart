class MovieTorrentioStream {
  final String id;
  final String movieId;
  final String title;
  final String infoHash;
  final String? qualityDetails;
  final String? filename;
  final int createdAt;
  final int lastUpdated;

  MovieTorrentioStream({
    required this.id,
    required this.movieId,
    required this.title,
    required this.infoHash,
    this.qualityDetails,
    this.filename,
    required this.createdAt,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'movieId': movieId,
      'title': title,
      'infoHash': infoHash,
      'qualityDetails': qualityDetails,
      'filename': filename,
      'createdAt': createdAt,
      'lastUpdated': lastUpdated,
    };
  }

  factory MovieTorrentioStream.fromJson(Map<String, dynamic> json) {
    return MovieTorrentioStream(
      id: json['id'],
      movieId: json['movieId'],
      title: json['title'],
      infoHash: json['infoHash'],
      qualityDetails: json['qualityDetails'],
      filename: json['filename'],
      createdAt: json['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      lastUpdated: json['lastUpdated'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory MovieTorrentioStream.fromTorrentioResponse(
    Map<String, dynamic> stream,
    String movieId,
  ) {
    final behaviorHints = stream['behaviorHints'] as Map<String, dynamic>?;
    
    return MovieTorrentioStream(
      id: '${movieId}_${stream['infoHash']}',
      movieId: movieId,
      title: stream['title'] ?? '',
      infoHash: stream['infoHash'] ?? '',
      qualityDetails: behaviorHints?['bingeGroup'],
      filename: behaviorHints?['filename'],
      createdAt: DateTime.now().millisecondsSinceEpoch,
      lastUpdated: DateTime.now().millisecondsSinceEpoch,
    );
  }

  MovieTorrentioStream copyWith({
    String? id,
    String? movieId,
    String? title,
    String? infoHash,
    String? qualityDetails,
    String? filename,
    int? createdAt,
    int? lastUpdated,
  }) {
    return MovieTorrentioStream(
      id: id ?? this.id,
      movieId: movieId ?? this.movieId,
      title: title ?? this.title,
      infoHash: infoHash ?? this.infoHash,
      qualityDetails: qualityDetails ?? this.qualityDetails,
      filename: filename ?? this.filename,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MovieTorrentioStream && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
} 
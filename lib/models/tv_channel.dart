class TVChannel {
  final String id;
  final String name;
  final List<String> keywords;
  final DateTime createdAt;
  final DateTime lastUpdated;
  final List<String>? playableTorrentIds;
  final List<String>? failedTorrentIds;
  final DateTime? lastPlayedAt;
  final String? lastPlayedTorrentId;
  final int? playSuccessCount;
  final int? playFailureCount;
  final bool showChannelName;
  final bool showLiveTag;

  TVChannel({
    required this.id,
    required this.name,
    required this.keywords,
    required this.createdAt,
    required this.lastUpdated,
    this.playableTorrentIds,
    this.failedTorrentIds,
    this.lastPlayedAt,
    this.lastPlayedTorrentId,
    this.playSuccessCount,
    this.playFailureCount,
    this.showChannelName = true,
    this.showLiveTag = true,
  });

  factory TVChannel.fromJson(Map<String, dynamic> json) {
    return TVChannel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      keywords: List<String>.from(json['keywords'] ?? []),
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      lastUpdated: DateTime.parse(json['lastUpdated'] ?? DateTime.now().toIso8601String()),
      playableTorrentIds: json['playableTorrentIds'] != null 
          ? List<String>.from(json['playableTorrentIds']) 
          : null,
      failedTorrentIds: json['failedTorrentIds'] != null 
          ? List<String>.from(json['failedTorrentIds']) 
          : null,
      lastPlayedAt: json['lastPlayedAt'] != null 
          ? DateTime.parse(json['lastPlayedAt']) 
          : null,
      lastPlayedTorrentId: json['lastPlayedTorrentId'],
      playSuccessCount: json['playSuccessCount'],
      playFailureCount: json['playFailureCount'],
      showChannelName: json['showChannelName'] ?? true,
      showLiveTag: json['showLiveTag'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'keywords': keywords,
      'createdAt': createdAt.toIso8601String(),
      'lastUpdated': lastUpdated.toIso8601String(),
      'playableTorrentIds': playableTorrentIds,
      'failedTorrentIds': failedTorrentIds,
      'lastPlayedAt': lastPlayedAt?.toIso8601String(),
      'lastPlayedTorrentId': lastPlayedTorrentId,
      'playSuccessCount': playSuccessCount,
      'playFailureCount': playFailureCount,
      'showChannelName': showChannelName,
      'showLiveTag': showLiveTag,
    };
  }

  TVChannel copyWith({
    String? id,
    String? name,
    List<String>? keywords,
    DateTime? createdAt,
    DateTime? lastUpdated,
    List<String>? playableTorrentIds,
    List<String>? failedTorrentIds,
    DateTime? lastPlayedAt,
    String? lastPlayedTorrentId,
    int? playSuccessCount,
    int? playFailureCount,
    bool? showChannelName,
    bool? showLiveTag,
  }) {
    return TVChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      keywords: keywords ?? this.keywords,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      playableTorrentIds: playableTorrentIds ?? this.playableTorrentIds,
      failedTorrentIds: failedTorrentIds ?? this.failedTorrentIds,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      lastPlayedTorrentId: lastPlayedTorrentId ?? this.lastPlayedTorrentId,
      playSuccessCount: playSuccessCount ?? this.playSuccessCount,
      playFailureCount: playFailureCount ?? this.playFailureCount,
      showChannelName: showChannelName ?? this.showChannelName,
      showLiveTag: showLiveTag ?? this.showLiveTag,
    );
  }
} 
class DebrifyTvChannelRecord {
  final String channelId;
  final String name;
  final List<String> keywords;
  final bool avoidNsfw;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DebrifyTvChannelRecord({
    required this.channelId,
    required this.name,
    required this.keywords,
    required this.avoidNsfw,
    required this.createdAt,
    required this.updatedAt,
  });

  DebrifyTvChannelRecord copyWith({
    String? name,
    List<String>? keywords,
    bool? avoidNsfw,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DebrifyTvChannelRecord(
      channelId: channelId,
      name: name ?? this.name,
      keywords: keywords ?? this.keywords,
      avoidNsfw: avoidNsfw ?? this.avoidNsfw,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Default configuration from _defaults.yaml
class DefaultConfig {
  /// Configuration version
  final String version;

  /// Default request settings
  final DefaultRequestConfig request;

  /// Default TV mode settings
  final DefaultTvModeConfig tvMode;

  const DefaultConfig({
    required this.version,
    required this.request,
    required this.tvMode,
  });

  /// Factory constructor to create DefaultConfig from a YAML map
  factory DefaultConfig.fromMap(Map<String, dynamic> map) {
    return DefaultConfig(
      version: map['version'] as String? ?? '1.0',
      request: DefaultRequestConfig.fromMap(
        map['request'] as Map<String, dynamic>? ?? {},
      ),
      tvMode: DefaultTvModeConfig.fromMap(
        map['tv_mode'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  /// Convert the config back to a map for debugging
  Map<String, dynamic> toMap() {
    return {
      'version': version,
      'request': request.toMap(),
      'tv_mode': tvMode.toMap(),
    };
  }
}

/// Default request configuration
class DefaultRequestConfig {
  /// Default timeout in seconds
  final int timeoutSeconds;

  /// Default user agent string
  final String userAgent;

  /// Number of retry attempts
  final int retryAttempts;

  /// Delay between retries in milliseconds
  final int retryDelayMs;

  const DefaultRequestConfig({
    required this.timeoutSeconds,
    required this.userAgent,
    required this.retryAttempts,
    required this.retryDelayMs,
  });

  /// Factory constructor to create DefaultRequestConfig from a YAML map
  factory DefaultRequestConfig.fromMap(Map<String, dynamic> map) {
    return DefaultRequestConfig(
      timeoutSeconds: map['timeout_seconds'] as int? ?? 30,
      userAgent: map['user_agent'] as String? ?? '',
      retryAttempts: map['retry_attempts'] as int? ?? 3,
      retryDelayMs: map['retry_delay_ms'] as int? ?? 1000,
    );
  }

  /// Convert the config back to a map for debugging
  Map<String, dynamic> toMap() {
    return {
      'timeout_seconds': timeoutSeconds,
      'user_agent': userAgent,
      'retry_attempts': retryAttempts,
      'retry_delay_ms': retryDelayMs,
    };
  }
}

/// Default TV mode configuration
class DefaultTvModeConfig {
  /// Keyword length threshold for TV mode optimizations
  final int keywordThreshold;

  /// Batch size for channel operations
  final int channelBatchSize;

  /// Minimum number of torrents per keyword
  final int minTorrentsPerKeyword;

  /// Maximum keywords for quick play
  final int maxKeywords;

  /// Whether to avoid NSFW content
  final bool avoidNsfw;

  /// Patterns to identify NSFW categories
  final List<String> nsfwCategoryPatterns;

  const DefaultTvModeConfig({
    required this.keywordThreshold,
    required this.channelBatchSize,
    required this.minTorrentsPerKeyword,
    required this.maxKeywords,
    required this.avoidNsfw,
    required this.nsfwCategoryPatterns,
  });

  /// Factory constructor to create DefaultTvModeConfig from a YAML map
  factory DefaultTvModeConfig.fromMap(Map<String, dynamic> map) {
    return DefaultTvModeConfig(
      keywordThreshold: map['keyword_threshold'] as int? ?? 10,
      // Support both YAML key names
      channelBatchSize: map['channel_batch_size'] as int? ??
          map['batch_size'] as int? ?? 4,
      minTorrentsPerKeyword: map['min_torrents_per_keyword'] as int? ??
          map['min_torrents'] as int? ?? 5,
      maxKeywords: map['max_keywords'] as int? ?? 5,
      avoidNsfw: map['avoid_nsfw'] as bool? ?? true,
      nsfwCategoryPatterns: (map['nsfw_category_patterns'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  /// Check if a category matches any NSFW pattern
  bool isCategoryNsfw(String category) {
    final lowerCategory = category.toLowerCase();
    return nsfwCategoryPatterns.any(
      (pattern) => lowerCategory.contains(pattern.toLowerCase()),
    );
  }

  /// Convert the config back to a map for debugging
  Map<String, dynamic> toMap() {
    return {
      'keyword_threshold': keywordThreshold,
      'channel_batch_size': channelBatchSize,
      'min_torrents_per_keyword': minTorrentsPerKeyword,
      'max_keywords': maxKeywords,
      'avoid_nsfw': avoidNsfw,
      'nsfw_category_patterns': nsfwCategoryPatterns,
    };
  }
}
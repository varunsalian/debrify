import 'torrent.dart';

class DebrifyTvCacheStatus {
  static const String warming = 'warming';
  static const String ready = 'ready';
  static const String failed = 'failed';
}

class CachedTorrent {
  final int rowid;
  final String infohash;
  final String name;
  final int sizeBytes;
  final int createdUnix;
  final int seeders;
  final int leechers;
  final int completed;
  final int scrapedDate;
  final List<String> sources;
  final List<String> keywords;

  const CachedTorrent({
    required this.rowid,
    required this.infohash,
    required this.name,
    required this.sizeBytes,
    required this.createdUnix,
    required this.seeders,
    required this.leechers,
    required this.completed,
    required this.scrapedDate,
    required this.sources,
    required this.keywords,
  });

  factory CachedTorrent.fromTorrent(
    Torrent torrent, {
    required Iterable<String> keywords,
    required Iterable<String> sources,
  }) {
    return CachedTorrent(
      rowid: torrent.rowid,
      infohash: torrent.infohash,
      name: torrent.name,
      sizeBytes: torrent.sizeBytes,
      createdUnix: torrent.createdUnix,
      seeders: torrent.seeders,
      leechers: torrent.leechers,
      completed: torrent.completed,
      scrapedDate: torrent.scrapedDate,
      keywords: keywords.map((e) => e.toLowerCase()).toSet().toList(),
      sources: sources.map((e) => e.toLowerCase()).toSet().toList(),
    );
  }

  factory CachedTorrent.fromJson(Map<String, dynamic> json) {
    return CachedTorrent(
      rowid: json['rowid'] is int ? json['rowid'] as int : int.tryParse('${json['rowid']}') ?? 0,
      infohash: (json['infohash'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      sizeBytes: json['size_bytes'] is int
          ? json['size_bytes'] as int
          : int.tryParse('${json['size_bytes']}') ?? 0,
      createdUnix: json['created_unix'] is int
          ? json['created_unix'] as int
          : int.tryParse('${json['created_unix']}') ?? 0,
      seeders: json['seeders'] is int
          ? json['seeders'] as int
          : int.tryParse('${json['seeders']}') ?? 0,
      leechers: json['leechers'] is int
          ? json['leechers'] as int
          : int.tryParse('${json['leechers']}') ?? 0,
      completed: json['completed'] is int
          ? json['completed'] as int
          : int.tryParse('${json['completed']}') ?? 0,
      scrapedDate: json['scraped_date'] is int
          ? json['scraped_date'] as int
          : int.tryParse('${json['scraped_date']}') ?? 0,
      sources: (json['sources'] as List?)
              ?.map((e) => (e?.toString() ?? '').toLowerCase())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList() ??
          const <String>[],
      keywords: (json['keywords'] as List?)
              ?.map((e) => (e?.toString() ?? '').toLowerCase())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList() ??
          const <String>[],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rowid': rowid,
      'infohash': infohash,
      'name': name,
      'size_bytes': sizeBytes,
      'created_unix': createdUnix,
      'seeders': seeders,
      'leechers': leechers,
      'completed': completed,
      'scraped_date': scrapedDate,
      'sources': sources,
      'keywords': keywords,
    };
  }

  CachedTorrent merge({
    Iterable<String>? keywords,
    Iterable<String>? sources,
    Torrent? override,
  }) {
    final mergedKeywords = <String>{...this.keywords};
    if (keywords != null) {
      mergedKeywords.addAll(keywords.map((e) => e.toLowerCase()));
    }

    final mergedSources = <String>{...this.sources};
    if (sources != null) {
      mergedSources.addAll(sources.map((e) => e.toLowerCase()));
    }

    final base = override ??
        Torrent(
          rowid: rowid,
          infohash: infohash,
          name: name,
          sizeBytes: sizeBytes,
          createdUnix: createdUnix,
          seeders: seeders,
          leechers: leechers,
          completed: completed,
          scrapedDate: scrapedDate,
        );

    return CachedTorrent(
      rowid: base.rowid,
      infohash: base.infohash,
      name: base.name,
      sizeBytes: base.sizeBytes,
      createdUnix: base.createdUnix,
      seeders: base.seeders,
      leechers: base.leechers,
      completed: base.completed,
      scrapedDate: base.scrapedDate,
      sources: mergedSources.toList(),
      keywords: mergedKeywords.toList(),
    );
  }

  Torrent toTorrent() {
    return Torrent(
      rowid: rowid,
      infohash: infohash,
      name: name,
      sizeBytes: sizeBytes,
      createdUnix: createdUnix,
      seeders: seeders,
      leechers: leechers,
      completed: completed,
      scrapedDate: scrapedDate,
    );
  }
}

class KeywordStat {
  final int totalFetched;
  final int lastSearchedAt;
  final int pagesPulled;
  final int pirateBayHits;

  const KeywordStat({
    required this.totalFetched,
    required this.lastSearchedAt,
    required this.pagesPulled,
    required this.pirateBayHits,
  });

  factory KeywordStat.initial() {
    return const KeywordStat(
      totalFetched: 0,
      lastSearchedAt: 0,
      pagesPulled: 0,
      pirateBayHits: 0,
    );
  }

  factory KeywordStat.fromJson(Map<String, dynamic> json) {
    return KeywordStat(
      totalFetched: json['totalFetched'] is int
          ? json['totalFetched'] as int
          : int.tryParse('${json['totalFetched']}') ?? 0,
      lastSearchedAt: json['lastSearchedAt'] is int
          ? json['lastSearchedAt'] as int
          : int.tryParse('${json['lastSearchedAt']}') ?? 0,
      pagesPulled: json['pagesPulled'] is int
          ? json['pagesPulled'] as int
          : int.tryParse('${json['pagesPulled']}') ?? 0,
      pirateBayHits: json['pirateBayHits'] is int
          ? json['pirateBayHits'] as int
          : int.tryParse('${json['pirateBayHits']}') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalFetched': totalFetched,
      'lastSearchedAt': lastSearchedAt,
      'pagesPulled': pagesPulled,
      'pirateBayHits': pirateBayHits,
    };
  }

  KeywordStat copyWith({
    int? totalFetched,
    int? lastSearchedAt,
    int? pagesPulled,
    int? pirateBayHits,
  }) {
    return KeywordStat(
      totalFetched: totalFetched ?? this.totalFetched,
      lastSearchedAt: lastSearchedAt ?? this.lastSearchedAt,
      pagesPulled: pagesPulled ?? this.pagesPulled,
      pirateBayHits: pirateBayHits ?? this.pirateBayHits,
    );
  }
}

class DebrifyTvChannelCacheEntry {
  final int version;
  final String channelId;
  final List<String> normalizedKeywords;
  final int fetchedAt;
  final String status;
  final String? errorMessage;
  final List<CachedTorrent> torrents;
  final Map<String, KeywordStat> keywordStats;

  const DebrifyTvChannelCacheEntry({
    required this.version,
    required this.channelId,
    required this.normalizedKeywords,
    required this.fetchedAt,
    required this.status,
    required this.errorMessage,
    required this.torrents,
    required this.keywordStats,
  });

  factory DebrifyTvChannelCacheEntry.empty({
    required String channelId,
    required List<String> normalizedKeywords,
    String status = DebrifyTvCacheStatus.warming,
  }) {
    return DebrifyTvChannelCacheEntry(
      version: 1,
      channelId: channelId,
      normalizedKeywords: normalizedKeywords,
      fetchedAt: 0,
      status: status,
      errorMessage: null,
      torrents: const <CachedTorrent>[],
      keywordStats: const <String, KeywordStat>{},
    );
  }

  factory DebrifyTvChannelCacheEntry.fromJson(Map<String, dynamic> json) {
    final String channelId = (json['channelId'] as String?) ?? '';
    final List<String> normalizedKeywords = (json['normalizedKeywords'] as List?)
            ?.map((e) => (e?.toString() ?? '').toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final Map<String, dynamic> statsRaw =
        (json['keywordStats'] as Map?)?.cast<String, dynamic>() ?? const {};

    return DebrifyTvChannelCacheEntry(
      version: json['version'] is int
          ? json['version'] as int
          : int.tryParse('${json['version']}') ?? 1,
      channelId: channelId,
      normalizedKeywords: normalizedKeywords,
      fetchedAt: json['fetchedAt'] is int
          ? json['fetchedAt'] as int
          : int.tryParse('${json['fetchedAt']}') ?? 0,
      status: (json['status'] as String?) ?? DebrifyTvCacheStatus.warming,
      errorMessage: json['errorMessage'] as String?,
      torrents: (json['torrents'] as List?)
              ?.map((entry) => CachedTorrent.fromJson(
                    Map<String, dynamic>.from(entry as Map),
                  ))
              .toList() ??
          const <CachedTorrent>[],
      keywordStats: statsRaw.map((key, value) {
        return MapEntry(
          key.toLowerCase(),
          KeywordStat.fromJson(Map<String, dynamic>.from(value as Map)),
        );
      }),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'channelId': channelId,
      'normalizedKeywords': normalizedKeywords,
      'fetchedAt': fetchedAt,
      'status': status,
      'errorMessage': errorMessage,
      'torrents': torrents.map((t) => t.toJson()).toList(),
      'keywordStats': keywordStats.map((key, value) => MapEntry(key, value.toJson())),
    };
  }

  bool get isReady => status == DebrifyTvCacheStatus.ready;
  bool get isWarming => status == DebrifyTvCacheStatus.warming;
  bool get isFailed => status == DebrifyTvCacheStatus.failed;

  DebrifyTvChannelCacheEntry copyWith({
    List<String>? normalizedKeywords,
    int? fetchedAt,
    String? status,
    String? errorMessage,
    bool clearErrorMessage = false,
    List<CachedTorrent>? torrents,
    Map<String, KeywordStat>? keywordStats,
  }) {
    final String? resolvedError;
    if (clearErrorMessage) {
      resolvedError = null;
    } else if (errorMessage != null) {
      resolvedError = errorMessage;
    } else {
      resolvedError = this.errorMessage;
    }

    return DebrifyTvChannelCacheEntry(
      version: version,
      channelId: channelId,
      normalizedKeywords: normalizedKeywords ?? this.normalizedKeywords,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      status: status ?? this.status,
      errorMessage: resolvedError,
      torrents: torrents ?? this.torrents,
      keywordStats: keywordStats ?? this.keywordStats,
    );
  }
}

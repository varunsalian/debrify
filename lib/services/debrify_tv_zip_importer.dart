import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:yaml/yaml.dart';

import '../models/debrify_tv_cache.dart';

class DebrifyTvZipImportResult {
  final List<DebrifyTvZipImportedChannel> channels;
  final List<DebrifyTvZipImportFailure> failures;

  const DebrifyTvZipImportResult({
    required this.channels,
    required this.failures,
  });
}

class DebrifyTvZipImportFailure {
  final String entryName;
  final String reason;

  const DebrifyTvZipImportFailure({
    required this.entryName,
    required this.reason,
  });
}

class DebrifyTvZipImportedChannel {
  final String sourceName;
  final String channelName;
  final bool avoidNsfw;
  final List<String> displayKeywords;
  final List<String> normalizedKeywords;
  final Map<String, KeywordStat> keywordStats;
  final List<CachedTorrent> torrents;

  const DebrifyTvZipImportedChannel({
    required this.sourceName,
    required this.channelName,
    required this.avoidNsfw,
    required this.displayKeywords,
    required this.normalizedKeywords,
    required this.keywordStats,
    required this.torrents,
  });

  int get keywordCount => normalizedKeywords.length;
  int get torrentCount => torrents.length;
}

class DebrifyTvZipImporter {
  static DebrifyTvZipImportResult parseZip(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    final channels = <DebrifyTvZipImportedChannel>[];
    final failures = <DebrifyTvZipImportFailure>[];

    for (final file in archive) {
      if (!file.isFile) {
        continue;
      }
      final fileName = file.name;
      if (!_isYamlFile(fileName)) {
        continue;
      }
      try {
        final contentBytes = file.content is List<int>
            ? (file.content as List<int>)
            : (file.content as Uint8List).toList();
        final content = utf8.decode(contentBytes);
        final channel = _parseChannelYaml(fileName, content);
        channels.add(channel);
      } catch (error) {
        failures.add(
          DebrifyTvZipImportFailure(
            entryName: fileName,
            reason: _formatError(error),
          ),
        );
      }
    }

    if (channels.isEmpty && failures.isEmpty) {
      failures.add(
        const DebrifyTvZipImportFailure(
          entryName: '(archive)',
          reason: 'No YAML files found in the selected zip.',
        ),
      );
    }

    return DebrifyTvZipImportResult(channels: channels, failures: failures);
  }

  static DebrifyTvZipImportedChannel parseYaml({
    required String sourceName,
    required String content,
  }) {
    return _parseChannelYaml(sourceName, content);
  }

  static DebrifyTvZipImportedChannel _parseChannelYaml(
    String sourceName,
    String content,
  ) {
    final dynamic rootRaw = loadYaml(content);
    if (rootRaw == null) {
      throw const FormatException('YAML document is empty.');
    }

    final dynamic converted = _deepConvert(rootRaw);
    if (converted is! Map) {
      throw const FormatException('Top-level YAML node must be a map.');
    }
    final Map<String, dynamic> root = converted.map(
      (key, value) => MapEntry('$key'.trim(), value),
    );

    final Map<String, dynamic> channelBlock = _extractChannelBlock(root);

    String? channelName = _stringFromMap(channelBlock, const [
      'channel_name',
      'name',
    ]);
    channelName ??= _stringFromMap(root, const [
      'channel_name',
      'channelName',
      'name',
    ]);
    if (channelName == null || channelName.isEmpty) {
      throw const FormatException('Missing channel_name.');
    }
    channelName = channelName.trim();

    bool avoidNsfw =
        _boolFromMap(channelBlock, const ['avoid_nsfw', 'avoidNsfw']) ??
        _boolFromMap(root, const ['avoid_nsfw', 'avoidNsfw']) ??
        true;

    dynamic keywordsSource = root['keywords'];
    if (keywordsSource == null && channelBlock.isNotEmpty) {
      keywordsSource = channelBlock['keywords'];
    }
    if (keywordsSource == null) {
      throw const FormatException('Missing keywords map.');
    }
    final Map<String, dynamic> keywordsMap = _mapify(
      keywordsSource,
      'keywords',
    );

    final Map<String, _MutableKeywordAggregate> keywordAggregates = {};
    final List<String> keywordOrder = [];

    final Map<String, _MutableTorrent> torrentsByHash = {};

    final Map<String, _KeywordStatBaseline> fallbackStats = _parseKeywordStats(
      root,
    );

    keywordsMap.forEach((rawKey, rawValue) {
      final keywordName = rawKey.toString().trim();
      if (keywordName.isEmpty) {
        return;
      }
      final normalizedKeyword = keywordName.toLowerCase();
      final Map<String, dynamic> keywordData = _mapify(
        rawValue,
        'keywords["$keywordName"]',
      );

      final aggregate = keywordAggregates.putIfAbsent(normalizedKeyword, () {
        keywordOrder.add(normalizedKeyword);
        final baseline = fallbackStats[normalizedKeyword];
        return _MutableKeywordAggregate(
          displayName: keywordName,
          totalFetched: baseline?.totalFetched ?? 0,
          lastSearchedAt: baseline?.lastSearchedAt ?? 0,
          pagesPulled: baseline?.pagesPulled ?? 0,
          pirateBayHits: baseline?.pirateBayHits ?? 0,
        );
      });

      final int? totalFetched =
          _readInt(keywordData['total_fetched']) ??
          _readInt(keywordData['totalFetched']);
      if (totalFetched != null) {
        aggregate.totalFetched += totalFetched;
      }

      final int? lastSearchedAt =
          _readInt(keywordData['last_searched_at']) ??
          _readInt(keywordData['lastSearchedAt']);
      if (lastSearchedAt != null) {
        if (lastSearchedAt > aggregate.lastSearchedAt) {
          aggregate.lastSearchedAt = lastSearchedAt;
        }
      }

      final int? pagesPulled =
          _readInt(keywordData['pages_pulled']) ??
          _readInt(keywordData['pagesPulled']);
      if (pagesPulled != null) {
        aggregate.pagesPulled += pagesPulled;
      }

      final int? pirateBayHits =
          _readInt(keywordData['pirate_bay_hits']) ??
          _readInt(keywordData['pirateBayHits']);
      if (pirateBayHits != null) {
        aggregate.pirateBayHits += pirateBayHits;
      }

      final List<dynamic> torrentsList = _listify(
        keywordData['torrents'] ?? const <dynamic>[],
        'keywords["$keywordName"].torrents',
      );

      for (final rawTorrent in torrentsList) {
        final snapshot = _parseTorrentSnapshot(
          rawTorrent,
          keywordName,
          normalizedKeyword,
        );
        if (snapshot == null) {
          continue;
        }

        final aggregateTorrent = torrentsByHash.putIfAbsent(
          snapshot.normalizedInfohash,
          () => _MutableTorrent(snapshot),
        );
        aggregateTorrent.mergeSnapshot(snapshot);
        aggregateTorrent.keywords.add(normalizedKeyword);
      }
    });

    if (keywordAggregates.isEmpty) {
      throw const FormatException('No keywords found in YAML.');
    }

    final Map<String, KeywordStat> keywordStats = {
      for (final key in keywordOrder)
        key: keywordAggregates[key]!.toKeywordStat(),
    };

    final List<String> displayKeywords = [
      for (final key in keywordOrder) keywordAggregates[key]!.displayName,
    ];

    final torrents = torrentsByHash.values
        .map((entry) => entry.toCachedTorrent())
        .toList();
    torrents.sort(_cachedTorrentComparator);

    return DebrifyTvZipImportedChannel(
      sourceName: sourceName,
      channelName: channelName,
      avoidNsfw: avoidNsfw,
      displayKeywords: displayKeywords,
      normalizedKeywords: List<String>.from(keywordOrder),
      keywordStats: keywordStats,
      torrents: torrents,
    );
  }

  static bool _isYamlFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.yaml') || lower.endsWith('.yml');
  }

  static String _formatError(Object error) {
    if (error is FormatException) {
      return error.message;
    }
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  static Map<String, dynamic> _extractChannelBlock(Map<String, dynamic> root) {
    final dynamic rawChannel = root['channel'];
    if (rawChannel == null) {
      return const <String, dynamic>{};
    }
    return _mapify(rawChannel, 'channel');
  }

  static dynamic _deepConvert(dynamic value) {
    if (value is YamlMap) {
      return value.map((key, v) => MapEntry('$key', _deepConvert(v)));
    }
    if (value is Map) {
      return value.map((key, v) => MapEntry('$key', _deepConvert(v)));
    }
    if (value is YamlList) {
      return value.map(_deepConvert).toList();
    }
    if (value is Iterable) {
      return value.map(_deepConvert).toList();
    }
    return value;
  }

  static Map<String, dynamic> _mapify(dynamic value, String context) {
    final converted = _deepConvert(value);
    if (converted is! Map) {
      throw FormatException('$context must be a map.');
    }
    return converted.map((key, v) => MapEntry('$key'.trim(), v));
  }

  static List<dynamic> _listify(dynamic value, String context) {
    final converted = _deepConvert(value);
    if (converted == null) {
      return const <dynamic>[];
    }
    if (converted is Iterable) {
      return converted.toList();
    }
    throw FormatException('$context must be a list.');
  }

  static String? _stringFromMap(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      final stringValue = value.toString().trim();
      if (stringValue.isNotEmpty) {
        return stringValue;
      }
    }
    return null;
  }

  static bool? _boolFromMap(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is bool) {
        return value;
      }
      if (value is String) {
        final lower = value.toLowerCase().trim();
        if (lower == 'true') return true;
        if (lower == 'false') return false;
      }
    }
    return null;
  }

  static int? _readInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse(value.toString());
  }

  static List<String> _readStringList(dynamic value) {
    if (value == null) {
      return const <String>[];
    }
    final List<dynamic> list = _listify(value, 'list');
    final set = <String>{};
    for (final element in list) {
      final text = element?.toString().trim();
      if (text != null && text.isNotEmpty) {
        set.add(text.toLowerCase());
      }
    }
    return set.toList();
  }

  static Map<String, _KeywordStatBaseline> _parseKeywordStats(
    Map<String, dynamic> root,
  ) {
    final dynamic statsRaw = root['keyword_stats'] ?? root['keywordStats'];
    if (statsRaw == null) {
      return const <String, _KeywordStatBaseline>{};
    }
    final Map<String, dynamic> statsMap = _mapify(statsRaw, 'keyword_stats');
    final Map<String, _KeywordStatBaseline> parsed = {};
    statsMap.forEach((key, value) {
      final keyword = key.toString().trim().toLowerCase();
      if (keyword.isEmpty) {
        return;
      }
      final Map<String, dynamic> statData = _mapify(
        value,
        'keyword_stats["$key"]',
      );
      parsed[keyword] = _KeywordStatBaseline(
        totalFetched:
            _readInt(statData['total_fetched']) ??
            _readInt(statData['totalFetched']) ??
            0,
        lastSearchedAt:
            _readInt(statData['last_searched_at']) ??
            _readInt(statData['lastSearchedAt']) ??
            0,
        pagesPulled:
            _readInt(statData['pages_pulled']) ??
            _readInt(statData['pagesPulled']) ??
            0,
        pirateBayHits:
            _readInt(statData['pirate_bay_hits']) ??
            _readInt(statData['pirateBayHits']) ??
            0,
      );
    });
    return parsed;
  }

  static _ParsedTorrentSnapshot? _parseTorrentSnapshot(
    dynamic raw,
    String keywordDisplay,
    String keywordNormalized,
  ) {
    final Map<String, dynamic> map = _mapify(
      raw,
      'keywords["$keywordDisplay"].torrents[...]',
    );
    final String? infohash = _stringFromMap(map, const [
      'infohash',
      'info_hash',
      'hash',
    ]);
    if (infohash == null || infohash.trim().isEmpty) {
      return null;
    }
    final String normalizedHash = infohash.trim().toLowerCase();
    final String name =
        _stringFromMap(map, const ['title', 'name']) ?? infohash;
    final int sizeBytes =
        _readInt(map['size_bytes']) ?? _readInt(map['sizeBytes']) ?? 0;
    final int createdUnix =
        _readInt(map['created_unix']) ?? _readInt(map['createdUnix']) ?? 0;
    final int seeders = _readInt(map['seeders']) ?? 0;
    final int leechers = _readInt(map['leechers']) ?? 0;
    final int completed = _readInt(map['completed']) ?? 0;
    final int scrapedDate =
        _readInt(map['scraped_date']) ?? _readInt(map['scrapedDate']) ?? 0;
    final List<String> sources = _readStringList(map['sources']);
    final List<String> torrentKeywords = _readStringList(map['keywords']);
    final Set<String> keywordSet = {
      ...torrentKeywords.map((k) => k.toLowerCase()),
      keywordNormalized,
    };

    return _ParsedTorrentSnapshot(
      infohash: infohash,
      normalizedInfohash: normalizedHash,
      name: name,
      sizeBytes: sizeBytes,
      createdUnix: createdUnix,
      seeders: seeders,
      leechers: leechers,
      completed: completed,
      scrapedDate: scrapedDate,
      sources: sources.toSet(),
      keywords: keywordSet,
    );
  }

  static int _cachedTorrentComparator(CachedTorrent a, CachedTorrent b) {
    final int seedCompare = b.seeders.compareTo(a.seeders);
    if (seedCompare != 0) {
      return seedCompare;
    }
    return b.completed.compareTo(a.completed);
  }
}

class _KeywordStatBaseline {
  final int totalFetched;
  final int lastSearchedAt;
  final int pagesPulled;
  final int pirateBayHits;

  const _KeywordStatBaseline({
    required this.totalFetched,
    required this.lastSearchedAt,
    required this.pagesPulled,
    required this.pirateBayHits,
  });
}

class _MutableKeywordAggregate {
  final String displayName;
  int totalFetched;
  int lastSearchedAt;
  int pagesPulled;
  int pirateBayHits;

  _MutableKeywordAggregate({
    required this.displayName,
    required this.totalFetched,
    required this.lastSearchedAt,
    required this.pagesPulled,
    required this.pirateBayHits,
  });

  KeywordStat toKeywordStat() {
    return KeywordStat(
      totalFetched: totalFetched,
      lastSearchedAt: lastSearchedAt,
      pagesPulled: pagesPulled,
      pirateBayHits: pirateBayHits,
    );
  }
}

class _ParsedTorrentSnapshot {
  final String infohash;
  final String normalizedInfohash;
  final String name;
  final int sizeBytes;
  final int createdUnix;
  final int seeders;
  final int leechers;
  final int completed;
  final int scrapedDate;
  final Set<String> sources;
  final Set<String> keywords;

  const _ParsedTorrentSnapshot({
    required this.infohash,
    required this.normalizedInfohash,
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
}

class _MutableTorrent {
  final String normalizedInfohash;
  String infohash;
  String name;
  int sizeBytes;
  int createdUnix;
  int seeders;
  int leechers;
  int completed;
  int scrapedDate;
  final Set<String> sources;
  final Set<String> keywords;

  _MutableTorrent(_ParsedTorrentSnapshot snapshot)
    : normalizedInfohash = snapshot.normalizedInfohash,
      infohash = snapshot.infohash,
      name = snapshot.name,
      sizeBytes = snapshot.sizeBytes,
      createdUnix = snapshot.createdUnix,
      seeders = snapshot.seeders,
      leechers = snapshot.leechers,
      completed = snapshot.completed,
      scrapedDate = snapshot.scrapedDate,
      sources = {...snapshot.sources},
      keywords = {...snapshot.keywords};

  void mergeSnapshot(_ParsedTorrentSnapshot snapshot) {
    sources.addAll(snapshot.sources);
    keywords.addAll(snapshot.keywords);

    final bool shouldAdopt =
        snapshot.seeders > seeders ||
        (snapshot.seeders == seeders && snapshot.leechers > leechers) ||
        (snapshot.seeders == seeders &&
            snapshot.leechers == leechers &&
            snapshot.createdUnix > createdUnix);

    if (shouldAdopt) {
      infohash = snapshot.infohash;
      name = snapshot.name;
      sizeBytes = snapshot.sizeBytes;
      createdUnix = snapshot.createdUnix;
      seeders = snapshot.seeders;
      leechers = snapshot.leechers;
      completed = snapshot.completed;
      scrapedDate = snapshot.scrapedDate;
    }
  }

  CachedTorrent toCachedTorrent() {
    final keywordList = keywords.toList()..sort();
    final sourceList = sources.toList()..sort();
    return CachedTorrent(
      rowid: 0,
      infohash: infohash,
      name: name,
      sizeBytes: sizeBytes,
      createdUnix: createdUnix,
      seeders: seeders,
      leechers: leechers,
      completed: completed,
      scrapedDate: scrapedDate,
      keywords: keywordList,
      sources: sourceList,
    );
  }
}

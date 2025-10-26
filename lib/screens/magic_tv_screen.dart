import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/torrent.dart';
import '../models/debrify_tv_cache.dart';
import '../models/torbox_file.dart';
import '../models/torbox_torrent.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';
import '../services/debrify_tv_cache_service.dart';
import '../services/torbox_service.dart';
import '../services/torrent_service.dart';
import '../services/torrents_csv_engine.dart';
import '../services/pirate_bay_engine.dart';
import '../utils/file_utils.dart';
import '../utils/series_parser.dart';
import 'video_player_screen.dart';

const int _randomStartPercentDefault = 40;
const int _randomStartPercentMin = 10;
const int _randomStartPercentMax = 90;

int _clampRandomStartPercent(int? value) {
  final candidate = value ?? _randomStartPercentDefault;
  if (candidate < _randomStartPercentMin) {
    return _randomStartPercentMin;
  }
  if (candidate > _randomStartPercentMax) {
    return _randomStartPercentMax;
  }
  return candidate;
}

int _parseRandomStartPercent(dynamic value) {
  if (value is int) {
    return _clampRandomStartPercent(value);
  }
  if (value is double) {
    return _clampRandomStartPercent(value.round());
  }
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return _clampRandomStartPercent(parsed);
    }
  }
  return _randomStartPercentDefault;
}

class DebrifyTVScreen extends StatefulWidget {
  const DebrifyTVScreen({super.key});

  @override
  State<DebrifyTVScreen> createState() => _DebrifyTVScreenState();
}

class _DebrifyTvChannel {
  final String id;
  final String name;
  final List<String> keywords;
  final String provider;
  final bool startRandom;
  final int randomStartPercent;
  final bool hideSeekbar;
  final bool showWatermark;
  final bool showVideoTitle;
  final bool hideOptions;
  final bool hideBackButton;

  const _DebrifyTvChannel({
    required this.id,
    required this.name,
    required this.keywords,
    required this.provider,
    required this.startRandom,
    required this.randomStartPercent,
    required this.hideSeekbar,
    required this.showWatermark,
    required this.showVideoTitle,
    required this.hideOptions,
    required this.hideBackButton,
  });

  factory _DebrifyTvChannel.fromJson(Map<String, dynamic> json) {
    final hideOptions = json['hideOptions'] is bool
        ? json['hideOptions'] as bool
        : true;
    final dynamic keywordsRaw = json['keywords'];
    final List<String> keywords;
    if (keywordsRaw is List) {
      keywords = keywordsRaw
          .map((e) => (e?.toString() ?? '').trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (keywordsRaw is String && keywordsRaw.isNotEmpty) {
      keywords = keywordsRaw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      keywords = const <String>[];
    }
    return _DebrifyTvChannel(
      id: (json['id'] as String?)?.trim().isNotEmpty ?? false
          ? json['id'] as String
          : DateTime.now().microsecondsSinceEpoch.toString(),
      name: (json['name'] as String?)?.trim().isNotEmpty ?? false
          ? (json['name'] as String).trim()
          : 'Unnamed Channel',
      keywords: keywords,
      provider: (json['provider'] as String?)?.trim().isNotEmpty ?? false
          ? (json['provider'] as String).trim()
          : 'real_debrid',
      startRandom: json['startRandom'] is bool
          ? json['startRandom'] as bool
          : true,
      randomStartPercent: _parseRandomStartPercent(
        json['randomStartPercent'],
      ),
      hideSeekbar: hideOptions,
      showWatermark: json['showWatermark'] is bool
          ? json['showWatermark'] as bool
          : true,
      showVideoTitle: json['showVideoTitle'] is bool
          ? json['showVideoTitle'] as bool
          : false,
      hideOptions: hideOptions,
      hideBackButton: json['hideBackButton'] is bool
          ? json['hideBackButton'] as bool
          : true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'keywords': keywords,
      'provider': provider,
      'startRandom': startRandom,
      'randomStartPercent': randomStartPercent,
      'hideSeekbar': hideOptions,
      'showWatermark': showWatermark,
      'showVideoTitle': showVideoTitle,
      'hideOptions': hideOptions,
      'hideBackButton': hideBackButton,
    };
  }

  _DebrifyTvChannel copyWith({
    String? id,
    String? name,
    List<String>? keywords,
    String? provider,
    bool? startRandom,
    int? randomStartPercent,
    bool? showWatermark,
    bool? showVideoTitle,
    bool? hideOptions,
    bool? hideBackButton,
  }) {
    final nextHideOptions = hideOptions ?? this.hideOptions;
    return _DebrifyTvChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      keywords: keywords ?? this.keywords,
      provider: provider ?? this.provider,
      startRandom: startRandom ?? this.startRandom,
      randomStartPercent: randomStartPercent ?? this.randomStartPercent,
      hideSeekbar: nextHideOptions,
      showWatermark: showWatermark ?? this.showWatermark,
      showVideoTitle: showVideoTitle ?? this.showVideoTitle,
      hideOptions: nextHideOptions,
      hideBackButton: hideBackButton ?? this.hideBackButton,
    );
  }
}

class _DebrifyTVScreenState extends State<DebrifyTVScreen> {
  static const String _providerRealDebrid = 'real_debrid';
  static const String _providerTorbox = 'torbox';
  static const String _torboxFileEntryType = 'torbox_file';
  static const int _torboxMinVideoSizeBytes = 50 * 1024 * 1024; // 50 MB filter threshold

  final TextEditingController _keywordsController = TextEditingController();
  // Mixed queue: can contain Torrent items or RD-restricted link maps
  final List<dynamic> _queue = [];
  bool _isBusy = false;
  String _status = '';
  List<_DebrifyTvChannel> _channels = <_DebrifyTvChannel>[];
  final Map<String, DebrifyTvChannelCacheEntry> _channelCache = {};
  static const Duration _channelCacheTtl = Duration(hours: 24);
  static const int _channelTorrentsCsvMaxResultsSmall = 100;
  static const int _channelTorrentsCsvMaxResultsLarge = 25;
  static const int _channelCsvParallelism = 4;
  static const int _playbackTorrentThreshold = 1000;
  static const int _maxTorrentsPerKeywordPlayback = 25;
  static const int _minimumTorrentsForChannel = 5;
  static const int _maxChannelKeywords = 100;
  final TextEditingController _channelSearchController = TextEditingController();
  String _channelSearchTerm = '';
  final Set<String> _expandedChannelIds = <String>{};
  // Advanced options
  bool _startRandom = true;
  int _randomStartPercent = _randomStartPercentDefault;
  bool _hideSeekbar = true;
  bool _showWatermark = true;
  bool _showVideoTitle = false;
  bool _hideOptions = true;
  bool _hideBackButton = true;
  String _provider = _providerRealDebrid;
  bool _rdAvailable = false;
  bool _torboxAvailable = false;
  // De-dupe sets for RD-restricted entries
  final Set<String> _seenRestrictedLinks = {};
  final Set<String> _seenLinkWithTorrentId = {};
  // Prefetch state
  static const int _minPrepared = 6; // maintain at least 6 prepared items
  static const int _lookaheadWindow = 10; // window near head to keep prepared
  bool _prefetchRunning = false;
  bool _prefetchStopRequested = false;
  Future<void>? _prefetchTask;
  String? _activeApiKey;
  final Set<String> _inflightInfohashes = {};

  // Progress UI state
  final ValueNotifier<List<String>> _progress = ValueNotifier<List<String>>([]);
  BuildContext? _progressSheetContext;
  bool _progressOpen = false;
  int _lastQueueSize = 0;
  DateTime? _lastSearchAt;
  bool _launchedPlayer = false;
  bool _stage2Running = false;
  int? _originalMaxCap;
  bool _capRestoredByStage2 = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadChannels();
    _loadCacheEntries();
    unawaited(DebrifyTvCacheService.pruneExpired(_channelCacheTtl));
  }

  @override
  void dispose() {
    // Ensure prefetch loop is stopped if this screen is disposed mid-run
    _prefetchStopRequested = true;
    _stopPrefetch();
    // Cancel Stage 2 if running
    _stage2Running = false;
    _progress.dispose();
    _keywordsController.dispose();
    _channelSearchController.dispose();
    super.dispose();
  }

  Future<void> _updateProvider(String value) async {
    if (!_isProviderSelectable(value)) {
      return;
    }
    if (_provider == value) return;
    setState(() {
      _provider = value;
    });
    await StorageService.saveDebrifyTvProvider(value);
  }

  void _closeProgressDialog() {
    if (!_progressOpen) {
      return;
    }
    if (_progressSheetContext != null) {
      try {
        Navigator.of(_progressSheetContext!).pop();
      } catch (_) {}
      _progressSheetContext = null;
      _progressOpen = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_progressOpen) {
        return;
      }
      if (_progressSheetContext != null) {
        _closeProgressDialog();
        return;
      }
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }
      _progressSheetContext = null;
      _progressOpen = false;
    });
  }

  String _determineDefaultProvider(
    String? preferred,
    bool rdAvailable,
    bool torboxAvailable,
  ) {
    if (torboxAvailable && rdAvailable) {
      if (preferred == _providerRealDebrid) {
        return _providerRealDebrid;
      }
      if (preferred == _providerTorbox) {
        return _providerTorbox;
      }
      return _providerTorbox;
    }
    if (torboxAvailable) {
      return _providerTorbox;
    }
    if (rdAvailable) {
      return _providerRealDebrid;
    }
    if (preferred == _providerTorbox) {
      return _providerTorbox;
    }
    return _providerRealDebrid;
  }

  bool _isProviderSelectable(String provider) {
    if (provider == _providerTorbox) {
      return _torboxAvailable;
    }
    return _rdAvailable;
  }

  Future<void> _loadSettings() async {
    final startRandom = await StorageService.getDebrifyTvStartRandom();
    final randomStartPercent =
        await StorageService.getDebrifyTvRandomStartPercent();
    final hideOptions = await StorageService.getDebrifyTvHideOptions();
    final showWatermark = await StorageService.getDebrifyTvShowWatermark();
    final showVideoTitle = await StorageService.getDebrifyTvShowVideoTitle();
    final hideBackButton = await StorageService.getDebrifyTvHideBackButton();
    final storedProvider = await StorageService.getDebrifyTvProvider();
    final hasStoredProvider = await StorageService.hasDebrifyTvProvider();
    final rdIntegrationEnabled =
        await StorageService.getRealDebridIntegrationEnabled();
    final rdKey = await StorageService.getApiKey();
    final torboxIntegrationEnabled =
        await StorageService.getTorboxIntegrationEnabled();
    final torboxKey = await StorageService.getTorboxApiKey();

    final rdAvailable =
        rdIntegrationEnabled && rdKey != null && rdKey.isNotEmpty;
    final torboxAvailable = torboxIntegrationEnabled &&
        torboxKey != null &&
        torboxKey.isNotEmpty;
    final defaultProvider = _determineDefaultProvider(
      hasStoredProvider ? storedProvider : null,
      rdAvailable,
      torboxAvailable,
    );

    if (mounted) {
      setState(() {
        _startRandom = startRandom;
        _randomStartPercent = _clampRandomStartPercent(randomStartPercent);
        _hideSeekbar = hideOptions;
        _showWatermark = showWatermark;
        _showVideoTitle = showVideoTitle;
        _hideOptions = hideOptions;
        _hideBackButton = hideBackButton;
        _rdAvailable = rdAvailable;
        _torboxAvailable = torboxAvailable;
        _provider = defaultProvider;
      });
    }

    if (await StorageService.getDebrifyTvHideSeekbar() != hideOptions) {
      unawaited(StorageService.saveDebrifyTvHideSeekbar(hideOptions));
    }

    if (defaultProvider != storedProvider) {
      await StorageService.saveDebrifyTvProvider(defaultProvider);
    }
  }

  void _accumulateCachedTorrent({
    required Map<String, CachedTorrent> accumulator,
    required String infohash,
    required Torrent torrent,
    required String keyword,
    required String source,
  }) {
    if (infohash.isEmpty) {
      return;
    }
    final normalizedKeyword = keyword.toLowerCase();
    final normalizedSource = source.toLowerCase();
    final existing = accumulator[infohash];
    if (existing == null) {
      accumulator[infohash] = CachedTorrent.fromTorrent(
        torrent,
        keywords: [normalizedKeyword],
        sources: [normalizedSource],
      );
      return;
    }

    final shouldOverride = torrent.seeders > existing.seeders;
    accumulator[infohash] = existing.merge(
      keywords: [normalizedKeyword],
      sources: [normalizedSource],
      override: shouldOverride ? torrent : null,
    );
  }

  List<CachedTorrent> _sortedCachedTorrents(
    Map<String, CachedTorrent> accumulator,
  ) {
    final list = accumulator.values.toList();
    list.sort((a, b) {
      final seedCompare = b.seeders.compareTo(a.seeders);
      if (seedCompare != 0) {
        return seedCompare;
      }
      return b.completed.compareTo(a.completed);
    });
    return list;
  }

  Future<void> _loadChannels() async {
    final raw = await StorageService.getDebrifyTvChannels();
    final parsed = <_DebrifyTvChannel>[];
    for (final entry in raw) {
      try {
        parsed.add(_DebrifyTvChannel.fromJson(entry));
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _channels = parsed;
    });
  }

  Future<void> _loadCacheEntries() async {
    final entries = await DebrifyTvCacheService.loadAllEntries();
    if (!mounted) {
      return;
    }
    setState(() {
      _channelCache
        ..clear()
        ..addAll(entries);
    });
  }

  Future<DebrifyTvChannelCacheEntry> _computeChannelCacheEntry(
    _DebrifyTvChannel channel,
    List<String> normalizedKeywords, {
    DebrifyTvChannelCacheEntry? baseline,
    Set<String>? keywordsToSearch,
  }) async {
    final csvEngine = const TorrentsCsvEngine();
    final pirateEngine = const PirateBayEngine();
    final now = DateTime.now().millisecondsSinceEpoch;

    final accumulator = <String, CachedTorrent>{};
    final stats = <String, KeywordStat>{};

    if (baseline != null) {
      for (final cached in _filterCachedTorrentsForKeywords(
        baseline,
        normalizedKeywords,
      )) {
        final normalizedHash = _normalizeInfohash(cached.infohash);
        if (normalizedHash.isEmpty) {
          continue;
        }
        accumulator[normalizedHash] = cached;
      }
      stats.addAll(
        _filterKeywordStats(baseline.keywordStats, normalizedKeywords),
      );
      debugPrint(
        'DebrifyTV: Starting incremental warm for "${channel.name}" – seeded cache with ${accumulator.length} torrent(s).',
      );
    }

    final Set<String> keywordsToWarm = keywordsToSearch != null
        ? keywordsToSearch.map((kw) => kw.toLowerCase()).toSet()
        : normalizedKeywords.toSet();

    if (keywordsToWarm.isEmpty) {
      debugPrint('DebrifyTV: No keywords to warm for "${channel.name}".');
    }

    final pirateFutures = <String, Future<List<Torrent>>>{};
    for (final keyword in keywordsToWarm) {
      pirateFutures[keyword] = pirateEngine.search(keyword);
    }

    bool anySuccess = accumulator.isNotEmpty;
    String? failureMessage;

    List<String> pendingKeywords = List<String>.from(keywordsToWarm);
    while (pendingKeywords.isNotEmpty) {
      final batch = pendingKeywords.take(_channelCsvParallelism).toList();
      pendingKeywords = pendingKeywords.skip(batch.length).toList();

      final futures = batch.map((keyword) async {
        return await _warmKeyword(
          keyword: keyword,
          csvEngine: csvEngine,
          pirateFuture: pirateFutures[keyword],
          accumulator: accumulator,
          stats: stats,
          now: now,
          totalKeywords: normalizedKeywords.length,
        );
      }).toList();

      final results = await Future.wait(futures);

      for (final result in results) {
        if (result == null) {
          continue;
        }
        final keyword = result.keyword;
        debugPrint(
          'DebrifyTV: Warmed keyword "$keyword" – added ${result.addedHashes.length} new torrent(s).',
        );
        anySuccess = anySuccess || result.addedHashes.isNotEmpty;
        stats[keyword] = result.stat;
        failureMessage ??= result.failureMessage;
      }
    }

    if (keywordsToWarm.isEmpty) {
      anySuccess = accumulator.isNotEmpty;
    }

    if (anySuccess) {
      return DebrifyTvChannelCacheEntry(
        version: 1,
        channelId: channel.id,
        normalizedKeywords: normalizedKeywords,
        fetchedAt: DateTime.now().millisecondsSinceEpoch,
        status: DebrifyTvCacheStatus.ready,
        errorMessage: null,
        torrents: _sortedCachedTorrents(accumulator),
        keywordStats: Map<String, KeywordStat>.from(stats),
      );
    }

    failureMessage ??= 'No torrents found for these keywords yet.';
    return DebrifyTvChannelCacheEntry(
      version: 1,
      channelId: channel.id,
      normalizedKeywords: normalizedKeywords,
      fetchedAt: DateTime.now().millisecondsSinceEpoch,
      status: DebrifyTvCacheStatus.failed,
      errorMessage: failureMessage,
      torrents: const <CachedTorrent>[],
      keywordStats: Map<String, KeywordStat>.from(stats),
    );
  }

  Future<_KeywordWarmResult?> _warmKeyword({
    required String keyword,
    required TorrentsCsvEngine csvEngine,
    required Future<List<Torrent>>? pirateFuture,
    required Map<String, CachedTorrent> accumulator,
    required Map<String, KeywordStat> stats,
    required int now,
    required int totalKeywords,
  }) async {
    String? csvFailure;
    TorrentsCsvSearchResult csvResult;
    try {
      csvResult = await csvEngine.searchWithConfig(
        keyword,
        maxResults: totalKeywords < 10
            ? _channelTorrentsCsvMaxResultsSmall
            : _channelTorrentsCsvMaxResultsLarge,
      );
    } catch (e) {
      debugPrint(
          'DebrifyTV: Cache warm Torrents CSV failed for "$keyword": $e');
      csvResult = TorrentsCsvSearchResult(
        torrents: const <Torrent>[],
        pagesPulled: 0,
      );
      csvFailure = 'Torrents CSV is unavailable right now. Please try again later.';
      return _KeywordWarmResult(
        keyword: keyword,
        addedHashes: const <String>{},
        stat: (stats[keyword] ?? KeywordStat.initial()).copyWith(
          totalFetched: 0,
          lastSearchedAt: now,
          pagesPulled: 0,
          pirateBayHits: 0,
        ),
        failureMessage: csvFailure,
      );
    }

    List<Torrent> pirateResult = const <Torrent>[];
    String? pirateFailure;
    try {
      if (pirateFuture != null) {
        pirateResult = await pirateFuture;
      }
    } catch (e) {
      debugPrint(
          'DebrifyTV: Cache warm Pirate Bay failed for "$keyword": $e');
      pirateFailure = 'The Pirate Bay search failed. Some torrents may be missing.';
    }

    final keywordHashes = <String>{};

      for (final torrent in csvResult.torrents) {
        final hash = _normalizeInfohash(torrent.infohash);
        if (hash.isEmpty) {
          continue;
        }
        keywordHashes.add(hash);
        _accumulateCachedTorrent(
          accumulator: accumulator,
          infohash: hash,
          torrent: torrent,
          keyword: keyword,
          source: 'torrents_csv',
        );
      }

      for (final torrent in pirateResult) {
        final hash = _normalizeInfohash(torrent.infohash);
        if (hash.isEmpty) {
          continue;
        }
        keywordHashes.add(hash);
        _accumulateCachedTorrent(
          accumulator: accumulator,
          infohash: hash,
          torrent: torrent,
          keyword: keyword,
          source: 'pirate_bay',
        );
      }

    final updatedStats = stats[keyword] ?? KeywordStat.initial();
    final stat = updatedStats.copyWith(
      totalFetched: keywordHashes.length,
      lastSearchedAt: now,
      pagesPulled: csvResult.pagesPulled,
      pirateBayHits: pirateResult.length,
    );

    String? failureMessage;
    if (csvFailure != null) {
      failureMessage = csvFailure;
    } else if (pirateFailure != null) {
      failureMessage = pirateFailure;
    } else if (csvResult.torrents.isEmpty && pirateResult.isEmpty) {
      failureMessage = 'No torrents found for "$keyword" yet.';
    }

    return _KeywordWarmResult(
      keyword: keyword,
      addedHashes: keywordHashes,
      stat: stat,
      failureMessage: failureMessage,
    );
  }

  Future<void> _persistChannels() async {
    await StorageService.saveDebrifyTvChannels(
      _channels.map((c) => c.toJson()).toList(),
    );
  }

  Future<void> _deleteChannel(String id) async {
    setState(() {
      _channels = _channels.where((c) => c.id != id).toList();
      _expandedChannelIds.remove(id);
    });
    await _persistChannels();
    setState(() {
      _channelCache.remove(id);
    });
    unawaited(DebrifyTvCacheService.removeEntry(id));
  }

  Future<void> _syncProviderAvailability({String? preferred}) async {
    final rdIntegrationEnabled =
        await StorageService.getRealDebridIntegrationEnabled();
    final rdKey = await StorageService.getApiKey();
    final torboxIntegrationEnabled =
        await StorageService.getTorboxIntegrationEnabled();
    final torboxKey = await StorageService.getTorboxApiKey();

    final rdAvailable =
        rdIntegrationEnabled && rdKey != null && rdKey.isNotEmpty;
    final torboxAvailable = torboxIntegrationEnabled &&
        torboxKey != null &&
        torboxKey.isNotEmpty;

    final nextProvider = _determineDefaultProvider(
      preferred ?? _provider,
      rdAvailable,
      torboxAvailable,
    );

    if (!mounted) return;
    final providerChanged = nextProvider != _provider;
    setState(() {
      _rdAvailable = rdAvailable;
      _torboxAvailable = torboxAvailable;
      _provider = nextProvider;
    });

    if (providerChanged) {
      await StorageService.saveDebrifyTvProvider(nextProvider);
    }
  }

  List<String> _parseKeywords(String input) {
    return input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  List<String> _normalizedKeywords(List<String> keywords) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final keyword in keywords) {
      final value = keyword.trim().toLowerCase();
      if (value.isEmpty || seen.contains(value)) {
        continue;
      }
      seen.add(value);
      normalized.add(value);
    }
    return normalized;
  }

  List<CachedTorrent> _filterCachedTorrentsForKeywords(
    DebrifyTvChannelCacheEntry entry,
    List<String> normalizedKeywords,
  ) {
    if (entry.torrents.isEmpty) {
      return const <CachedTorrent>[];
    }
    final allowed = normalizedKeywords.toSet();
    final filtered = <CachedTorrent>[];
    for (final cached in entry.torrents) {
      final matching = cached.keywords.where(allowed.contains).toList();
      if (matching.isEmpty) {
        continue;
      }
      filtered.add(cached.merge(keywords: matching));
    }
    return filtered;
  }

  Map<String, KeywordStat> _filterKeywordStats(
    Map<String, KeywordStat> stats,
    List<String> normalizedKeywords,
  ) {
    if (stats.isEmpty) {
      return const <String, KeywordStat>{};
    }
    final allowed = normalizedKeywords.toSet();
    final filtered = <String, KeywordStat>{};
    for (final entry in stats.entries) {
      if (allowed.contains(entry.key)) {
        filtered[entry.key] = entry.value;
      }
    }
    return filtered;
  }

  List<CachedTorrent> _selectTorrentsForPlayback(
    DebrifyTvChannelCacheEntry entry,
    List<String> normalizedKeywords,
  ) {
    final all = entry.torrents;
    if (all.length <= _playbackTorrentThreshold) {
      return all;
    }

    final selected = <CachedTorrent>[];
    final seenHashes = <String>{};

    if (normalizedKeywords.isNotEmpty) {
      for (final keyword in normalizedKeywords) {
        int count = 0;
        for (final cached in all) {
          if (!cached.keywords.contains(keyword)) continue;
          final hash = _normalizeInfohash(cached.infohash);
          if (hash.isEmpty || seenHashes.contains(hash)) {
            continue;
          }
          selected.add(cached);
          seenHashes.add(hash);
          count++;
          if (count >= _maxTorrentsPerKeywordPlayback) {
            break;
          }
        }
      }
    }

    if (selected.isEmpty) {
      return all.take(_playbackTorrentThreshold).toList();
    }

    if (selected.length < _playbackTorrentThreshold) {
      for (final cached in all) {
        final hash = _normalizeInfohash(cached.infohash);
        if (hash.isEmpty || seenHashes.contains(hash)) {
          continue;
        }
        selected.add(cached);
        seenHashes.add(hash);
        if (selected.length >= _playbackTorrentThreshold) {
          break;
        }
      }
    }

    final random = Random();
    selected.shuffle(random);
    return selected;
  }

  String _providerDisplay(String provider) {
    return provider == _providerTorbox ? 'Torbox' : 'Real Debrid';
  }

  bool _addKeywordsToList(
    String raw,
    List<String> keywordList,
    void Function(void Function()) setState,
  ) {
    if (raw.isEmpty) return false;
    final parsed = _parseKeywords(raw.replaceAll('\n', ','));
    if (parsed.isEmpty) return false;
    var limitReached = false;
    setState(() {
      for (final kw in parsed) {
        if (keywordList.length >= _maxChannelKeywords) {
          limitReached = true;
          break;
        }
        final exists = keywordList.any(
          (existing) => existing.toLowerCase() == kw.toLowerCase(),
        );
        if (!exists) {
          keywordList.add(kw);
        }
      }
    });
    return limitReached || keywordList.length >= _maxChannelKeywords;
  }

  Future<_DebrifyTvChannel?> _openChannelDialog({
    _DebrifyTvChannel? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final keywordInputController = TextEditingController();
    final List<String> keywordList = [];
    final seenKeywords = <String>{};
    final initialKeywords =
        existing?.keywords ?? _parseKeywords(_keywordsController.text);
    for (final kw in initialKeywords) {
      final trimmed = kw.trim();
      if (trimmed.isEmpty) continue;
      final lower = trimmed.toLowerCase();
      if (seenKeywords.contains(lower)) continue;
      seenKeywords.add(lower);
      keywordList.add(trimmed);
      if (keywordList.length >= _maxChannelKeywords) break;
    }
    String providerValue = existing?.provider ?? _provider;
    bool startRandom = existing?.startRandom ?? _startRandom;
    int randomStartPercent =
        existing?.randomStartPercent ?? _randomStartPercent;
    randomStartPercent = _clampRandomStartPercent(randomStartPercent);
    bool hideOptions = existing?.hideOptions ?? _hideOptions;
    bool showWatermark = existing?.showWatermark ?? _showWatermark;
    bool showVideoTitle = existing?.showVideoTitle ?? _showVideoTitle;
    bool hideBackButton = existing?.hideBackButton ?? _hideBackButton;
    String? error;

    final result = await showDialog<_DebrifyTvChannel>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              final pendingRaw = keywordInputController.text.trim();
              if (pendingRaw.isNotEmpty) {
                final pendingKeywords = _parseKeywords(pendingRaw);
                for (final rawKw in pendingKeywords) {
                  final trimmedKw = rawKw.trim();
                  if (trimmedKw.isEmpty) {
                    continue;
                  }
                  final alreadyPresent = keywordList.any(
                    (existing) =>
                        existing.toLowerCase() == trimmedKw.toLowerCase(),
                  );
                  if (alreadyPresent) {
                    continue;
                  }
                  if (keywordList.length >= _maxChannelKeywords) {
                    setModalState(() {
                      error =
                          'You can add up to $_maxChannelKeywords keywords per channel.';
                    });
                    return;
                  }
                  keywordList.add(trimmedKw);
                }
                keywordInputController.clear();
              }

              final name = nameController.text.trim();
              final keywords = <String>[];
              final seen = <String>{};
              for (final raw in keywordList) {
                final trimmed = raw.trim();
                if (trimmed.isEmpty) continue;
                final lower = trimmed.toLowerCase();
                if (seen.contains(lower)) continue;
                seen.add(lower);
                keywords.add(trimmed);
              }
              if (name.isEmpty) {
                setModalState(() {
                  error = 'Give the channel a name';
                });
                return;
              }
              if (keywords.isEmpty) {
                setModalState(() {
                  error = 'Add at least one keyword';
                });
                return;
              }
              if (keywords.length > _maxChannelKeywords) {
                setModalState(() {
                  error =
                      'You can add up to $_maxChannelKeywords keywords per channel.';
                });
                return;
              }
              if (providerValue == _providerRealDebrid && !_rdAvailable) {
                setModalState(() {
                  error = 'Enable Real Debrid in Settings first';
                });
                return;
              }
              if (providerValue == _providerTorbox && !_torboxAvailable) {
                setModalState(() {
                  error = 'Enable Torbox in Settings first';
                });
                return;
              }

              final channel = _DebrifyTvChannel(
                id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                name: name,
                keywords: keywords,
                provider: providerValue,
                startRandom: startRandom,
                randomStartPercent: randomStartPercent,
                hideSeekbar: hideOptions,
                showWatermark: showWatermark,
                showVideoTitle: showVideoTitle,
                hideOptions: hideOptions,
                hideBackButton: hideBackButton,
              );
              Navigator.of(dialogContext).pop(channel);
            }

            return Dialog(
              backgroundColor: const Color(0xFF0F0F0F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520, minWidth: 320),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE50914).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.tv_rounded,
                              color: Color(0xFFE50914),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            existing == null ? 'Create Channel' : 'Edit Channel',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Channel name',
                          prefixIcon: Icon(Icons.label_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Keywords (${keywordList.length}/$_maxChannelKeywords)',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tip: type a keyword and press Enter. Add multiples by separating with commas.',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...keywordList.map(
                            (keyword) => InputChip(
                              label: Text(keyword),
                              onDeleted: () {
                                setModalState(() {
                                  keywordList.remove(keyword);
                                  if (error != null &&
                                      error!
                                          .contains('$_maxChannelKeywords keywords') &&
                                      keywordList.length < _maxChannelKeywords) {
                                    error = null;
                                  }
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 200,
                        child: TextField(
                          controller: keywordInputController,
                          decoration: const InputDecoration(
                            hintText: 'Add keyword',
                            prefixIcon: Icon(Icons.add_rounded),
                          ),
                          style: const TextStyle(color: Colors.white),
                          onSubmitted: (value) {
                            final limitReached = _addKeywordsToList(
                              value,
                                  keywordList,
                                  setModalState,
                                );
                                keywordInputController.clear();
                                if (limitReached) {
                                  setModalState(() {
                                    error =
                                        'You can add up to $_maxChannelKeywords keywords per channel.';
                                  });
                                } else if (error != null &&
                                    error!
                                        .contains('$_maxChannelKeywords keywords')) {
                                  setModalState(() {
                                    error = null;
                                  });
                                }
                              },
                              onChanged: (value) {
                                if (value.contains(',')) {
                                  final limitReached = _addKeywordsToList(
                                    value,
                                    keywordList,
                                    setModalState,
                                  );
                                  keywordInputController.clear();
                                  if (limitReached) {
                                    setModalState(() {
                                      error =
                                          'You can add up to $_maxChannelKeywords keywords per channel.';
                                    });
                                  } else if (error != null &&
                                      error!
                                          .contains('$_maxChannelKeywords keywords')) {
                                    setModalState(() {
                                      error = null;
                                    });
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: submit,
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: const Text('Save Channel'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE50914),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Channel settings',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Content provider',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Tooltip(
                            message: _rdAvailable
                                ? 'Use Real Debrid for this channel'
                                : 'Enable Real Debrid and add an API key in Settings first.',
                            child: ChoiceChip(
                              label: const Text('Real Debrid'),
                              selected: providerValue == _providerRealDebrid,
                              onSelected: (!_rdAvailable)
                                  ? null
                                  : (selected) {
                                      if (selected) {
                                        setModalState(() {
                                          providerValue = _providerRealDebrid;
                                        });
                                      }
                                    },
                            ),
                          ),
                          Tooltip(
                            message: _torboxAvailable
                                ? 'Use Torbox for this channel'
                                : 'Enable Torbox and add an API key in Settings first.',
                            child: ChoiceChip(
                              label: const Text('Torbox'),
                              selected: providerValue == _providerTorbox,
                              onSelected: (!_torboxAvailable)
                                  ? null
                                  : (selected) {
                                      if (selected) {
                                        setModalState(() {
                                          providerValue = _providerTorbox;
                                        });
                                      }
                                    },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _SwitchRow(
                        title: 'Start from random timestamp',
                        subtitle: 'Each video starts at a random point',
                        value: startRandom,
                        onChanged: (v) => setModalState(() => startRandom = v),
                      ),
                      if (startRandom) ...[
                        const SizedBox(height: 8),
                        _RandomStartSlider(
                          value: randomStartPercent,
                          onChanged: (next) => setModalState(
                            () => randomStartPercent = next,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      _SwitchRow(
                        title: 'Show DebrifyTV watermark',
                        subtitle: 'Display watermark in the player',
                        value: showWatermark,
                        onChanged: (v) => setModalState(() => showWatermark = v),
                      ),
                      const SizedBox(height: 8),
                      _SwitchRow(
                        title: 'Show video title',
                        subtitle: 'Display title in player controls',
                        value: showVideoTitle,
                        onChanged: (v) => setModalState(() => showVideoTitle = v),
                      ),
                      const SizedBox(height: 8),
                      _SwitchRow(
                        title: 'Hide all options',
                        subtitle: 'Hide bottom controls inside the player',
                        value: hideOptions,
                        onChanged: (v) => setModalState(() => hideOptions = v),
                      ),
                      const SizedBox(height: 8),
                      _SwitchRow(
                        title: 'Hide back button',
                        subtitle: 'Require device gesture or escape key to exit',
                        value: hideBackButton,
                        onChanged: (v) => setModalState(() => hideBackButton = v),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    keywordInputController.dispose();
    return result;
  }

  Future<void> _handleAddChannel() async {
    await _syncProviderAvailability();
    final channel = await _openChannelDialog();
    if (channel != null) {
      await _createOrUpdateChannel(channel, isEdit: false);
    }
  }

  Future<void> _handleEditChannel(_DebrifyTvChannel channel) async {
    await _syncProviderAvailability(preferred: channel.provider);
    final updated = await _openChannelDialog(existing: channel);
    if (updated != null) {
      await _createOrUpdateChannel(updated, isEdit: true);
    }
  }

  Future<void> _handleDeleteChannel(_DebrifyTvChannel channel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete channel?'),
          content: Text(
            'Remove "${channel.name}" and its saved keywords?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _deleteChannel(channel.id);
      _showSnack('Channel deleted', color: Colors.orange);
    }
  }

  Future<void> _createOrUpdateChannel(
    _DebrifyTvChannel channel, {
    required bool isEdit,
  }) async {
    final normalizedKeywords = _normalizedKeywords(channel.keywords);
    if (normalizedKeywords.isEmpty) {
      _showSnack('Add at least one keyword before saving.',
          color: Colors.orange);
      return;
    }

    debugPrint(
      'DebrifyTV: ${isEdit ? 'Updating' : 'Creating'} channel "${channel.name}" with ${normalizedKeywords.length} keyword(s): ${normalizedKeywords.join(', ')}',
    );

    bool progressShown = false;
    void ensureProgressDialog() {
      if (!progressShown) {
        _showChannelCreationDialog(channel.name);
        progressShown = true;
      }
    }

    try {
      final baseline = isEdit ? _channelCache[channel.id] : null;
      if (normalizedKeywords.length > _maxChannelKeywords) {
        _showSnack(
          'Channels support up to $_maxChannelKeywords keywords. Remove some and try again.',
          color: Colors.orange,
        );
        debugPrint(
          'DebrifyTV: Aborting save for "${channel.name}" – keyword cap exceeded.',
        );
        return;
      }

      DebrifyTvChannelCacheEntry? workingEntry = baseline;
      final currentKeywordSet = normalizedKeywords.toSet();
      Set<String> addedKeywords = const <String>{};
      Set<String> removedKeywords = const <String>{};

      if (isEdit && baseline != null) {
        final previousKeywords = baseline.normalizedKeywords.toSet();
        removedKeywords = previousKeywords.difference(currentKeywordSet);
        addedKeywords = currentKeywordSet.difference(previousKeywords);

        debugPrint(
          'DebrifyTV: Detected keyword changes for "${channel.name}" – added: ${addedKeywords.join(', ')}, removed: ${removedKeywords.join(', ')}',
        );

        if (removedKeywords.isNotEmpty) {
          ensureProgressDialog();
          final filteredTorrents = baseline.torrents.where((cached) {
            final torrentKeywords = cached.keywords.toSet();
            return torrentKeywords.intersection(removedKeywords).isEmpty;
          }).toList();

          final filteredStats = Map<String, KeywordStat>.from(baseline.keywordStats)
            ..removeWhere((key, _) => removedKeywords.contains(key));

          final newStatus = filteredTorrents.isNotEmpty
              ? DebrifyTvCacheStatus.ready
              : DebrifyTvCacheStatus.failed;

          workingEntry = baseline.copyWith(
            normalizedKeywords: normalizedKeywords,
            torrents: filteredTorrents,
            keywordStats: filteredStats,
            status: newStatus,
            clearErrorMessage: filteredTorrents.isNotEmpty,
          );

          debugPrint(
            'DebrifyTV: Pruned ${baseline.torrents.length - filteredTorrents.length} torrent(s) after removing keywords. Remaining: ${filteredTorrents.length}.',
          );
        } else if (baseline.normalizedKeywords.length != normalizedKeywords.length) {
          workingEntry = baseline.copyWith(normalizedKeywords: normalizedKeywords);
        }

        if (addedKeywords.isNotEmpty) {
          ensureProgressDialog();
          debugPrint(
            'DebrifyTV: Warming new keywords for "${channel.name}": ${addedKeywords.join(', ')}',
          );
          workingEntry = await _computeChannelCacheEntry(
            channel,
            normalizedKeywords,
            baseline: workingEntry,
            keywordsToSearch: addedKeywords,
          );
          debugPrint(
            'DebrifyTV: After warming new keywords, cache has ${workingEntry.torrents.length} torrent(s).',
          );
        }

        if (addedKeywords.isEmpty && removedKeywords.isEmpty) {
          debugPrint(
            'DebrifyTV: No keyword changes for "${channel.name}" – reusing existing cache.',
          );
          workingEntry = baseline.copyWith(normalizedKeywords: normalizedKeywords);
        }
      } else {
        ensureProgressDialog();
        debugPrint('DebrifyTV: Running full warm-up for "${channel.name}"');
        workingEntry = await _computeChannelCacheEntry(
          channel,
          normalizedKeywords,
        );
        debugPrint(
          'DebrifyTV: Initial warm-up complete for "${channel.name}" with ${workingEntry.torrents.length} torrent(s).',
        );
      }

      final entry = workingEntry;
      if (entry == null) {
        _showSnack('Failed to build channel cache. Please try again.',
            color: Colors.red);
        return;
      }

      if (!mounted) {
        return;
      }

      if (!entry.isReady || entry.torrents.length < _minimumTorrentsForChannel) {
        final message = entry.isReady
            ? 'Need at least $_minimumTorrentsForChannel torrents to save this channel. Try different keywords.'
            : (entry.errorMessage ??
                'Unable to find torrents for these keywords. Try again later.');

        debugPrint(
          'DebrifyTV: Cache validation failed for "${channel.name}" – ready=${entry.isReady}, torrents=${entry.torrents.length}.',
        );

        if (isEdit && baseline != null) {
          setState(() {
            _channelCache[channel.id] = baseline;
          });
          await DebrifyTvCacheService.saveEntry(baseline);
        } else {
          setState(() {
            _channelCache.remove(channel.id);
          });
          await DebrifyTvCacheService.removeEntry(channel.id);
        }

        _showSnack(message, color: Colors.orange);
        return;
      }

      setState(() {
        final index = _channels.indexWhere((c) => c.id == channel.id);
        if (index == -1) {
          _channels = <_DebrifyTvChannel>[..._channels, channel];
        } else {
          final next = List<_DebrifyTvChannel>.from(_channels);
          next[index] = channel;
          _channels = next;
        }
        _channelCache[channel.id] = entry;
        _expandedChannelIds.add(channel.id);
      });

      await _persistChannels();
      await DebrifyTvCacheService.saveEntry(entry);

      final successMsg =
          isEdit ? 'Channel "${channel.name}" updated' : 'Channel "${channel.name}" saved';
      _showSnack(successMsg, color: Colors.green);
      debugPrint('DebrifyTV: $successMsg (torrents cached: ${entry.torrents.length})');
    } catch (e) {
      debugPrint('DebrifyTV: Channel creation failed for ${channel.name}: $e');
      _showSnack('Failed to build channel cache. Please try again.',
          color: Colors.red);
    } finally {
      if (progressShown) {
        _closeProgressDialog();
      }
    }
  }

  Future<void> _watchChannel(_DebrifyTvChannel channel) async {
    if (channel.keywords.isEmpty) {
      _showSnack('Channel has no keywords yet', color: Colors.orange);
      return;
    }
    await _syncProviderAvailability(preferred: channel.provider);
    final bool providerReady = channel.provider == _providerTorbox
        ? _torboxAvailable
        : _rdAvailable;
    if (!providerReady) {
      final providerName = _providerDisplay(channel.provider);
      _showSnack('Enable $providerName in Settings to watch this channel',
          color: Colors.orange);
      return;
    }

    final cacheEntry = _channelCache[channel.id];
    if (cacheEntry == null) {
      _showSnack('Channel cache not found. Edit the channel to rebuild it.',
          color: Colors.orange);
      return;
    }
    if (!cacheEntry.isReady) {
      final message = cacheEntry.errorMessage ??
          'Channel cache failed to build. Try editing and saving again.';
      _showSnack(message, color: Colors.orange);
      return;
    }
    if (cacheEntry.torrents.isEmpty) {
      _showSnack('No torrents cached yet. Try editing the channel keywords.',
          color: Colors.orange);
      return;
    }

    final previousProvider = _provider;
    final previousStartRandom = _startRandom;
    final previousRandomStartPercent = _randomStartPercent;
    final previousHideSeekbar = _hideSeekbar;
    final previousShowWatermark = _showWatermark;
    final previousShowVideoTitle = _showVideoTitle;
    final previousHideOptions = _hideOptions;
    final previousHideBackButton = _hideBackButton;
    final previousKeywords = _keywordsController.text;

    setState(() {
      _provider = channel.provider;
      _startRandom = channel.startRandom;
      _randomStartPercent = channel.randomStartPercent;
      _hideSeekbar = channel.hideOptions;
      _showWatermark = channel.showWatermark;
      _showVideoTitle = channel.showVideoTitle;
      _hideOptions = channel.hideOptions;
      _hideBackButton = channel.hideBackButton;
    });
    _keywordsController.text = channel.keywords.join(', ');

    final normalizedKeywords = _normalizedKeywords(channel.keywords);
    final playbackSelection = _selectTorrentsForPlayback(
      cacheEntry,
      normalizedKeywords,
    );
    final cachedTorrents =
        playbackSelection.map((cached) => cached.toTorrent()).toList();
    if (channel.provider == _providerTorbox) {
      await _watchTorboxWithCachedTorrents(cachedTorrents);
    } else {
      await _watchWithCachedTorrents(cachedTorrents);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _provider = previousProvider;
      _startRandom = previousStartRandom;
      _randomStartPercent = previousRandomStartPercent;
      _hideSeekbar = previousHideSeekbar;
      _showWatermark = previousShowWatermark;
      _showVideoTitle = previousShowVideoTitle;
      _hideOptions = previousHideOptions;
      _hideBackButton = previousHideBackButton;
    });
    _keywordsController.text = previousKeywords;
  }

  Future<void> _watch() async {
    _launchedPlayer = false;
    await _stopPrefetch();
    _prefetchStopRequested = false;
    _stage2Running = false;
    _capRestoredByStage2 = false;
    _originalMaxCap = null;
    void _log(String m) {
      final copy = List<String>.from(_progress.value)..add(m);
      _progress.value = copy;
      debugPrint('DebrifyTV: ' + m);
    }
    await _syncProviderAvailability();
    if (!_rdAvailable && !_torboxAvailable) {
      if (mounted) {
        setState(() {
          _status =
              'Connect Real Debrid or Torbox in Settings to use Debrify TV.';
        });
      }
      _showSnack(
        'Connect Real Debrid or Torbox in Settings to use Debrify TV.',
        color: Colors.orange,
      );
      return;
    }
    final text = _keywordsController.text.trim();
    debugPrint('DebrifyTV: Watch started. Raw input="$text"');
    if (text.isEmpty) {
      setState(() {
        _status = 'Enter one or more keywords, separated by commas';
      });
      debugPrint('DebrifyTV: Aborting. No keywords provided.');
      return;
    }

    final keywords = _parseKeywords(text);
    debugPrint('DebrifyTV: Parsed ${keywords.length} keyword(s): ${keywords.join(' | ')}');
    if (keywords.isEmpty) {
      setState(() {
        _status = 'Enter valid keywords';
      });
      debugPrint('DebrifyTV: Aborting. Parsed keywords became empty after trimming.');
      return;
    }
    if (keywords.length > 5) {
      setState(() {
        _status = 'Quick Play supports up to 5 keywords. Create a channel for larger sets.';
      });
      _showSnack(
        'Quick Play supports up to 5 keywords. Create a channel for bigger combos.',
        color: Colors.orange,
      );
      debugPrint('DebrifyTV: Aborting. Too many keywords for Quick Play (${keywords.length}).');
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Searching...';
      _queue.clear();
    });

    // show non-dismissible loading modal
    _progress.value = [];
    _progressOpen = true;
    final providerLabel =
        _provider == _providerTorbox ? 'Torbox' : 'Real Debrid';
    // ignore: unawaited_futures
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (ctx) {
        _progressSheetContext = ctx;
        return WillPopScope(
          onWillPop: () async => false, // Prevent dismissing with back button
          child: Dialog(
            backgroundColor: const Color(0xFF0F0F0F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Compact header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE50914), Color(0xFFB71C1C)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE50914).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.tv_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Debrify TV', 
                          style: TextStyle(
                            color: Colors.white, 
                            fontWeight: FontWeight.w800, 
                            fontSize: 18
                          )
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Provider: $providerLabel',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Smaller loading animation
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE50914), Color(0xFFFF6B6B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE50914).withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Compact message
                    const Text(
                      'Debrify TV is working its magic...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    
                    // Compact timing information
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.withOpacity(0.2)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.access_time_rounded, color: Colors.blue[300], size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Usually takes 20-30 seconds',
                                style: TextStyle(
                                  color: Colors.blue[200],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Rare keywords may take longer',
                            style: TextStyle(
                              color: Colors.blue[300],
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Compact cancel button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _isBusy = false;
                            _status = '';
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.1),
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ).whenComplete(() { _progressOpen = false; _progressSheetContext = null; });

    if (_provider == _providerTorbox) {
      await _watchWithTorbox(keywords, _log);
      return;
    }

    // Silent approach - no progress logging needed

    // Stage 1: Use a small cap to get the first playable quickly
    const int _stage1Cap = 50;
    _originalMaxCap = await StorageService.getMaxTorrentsCsvResults();
    debugPrint('DebrifyTV: Temporarily setting Torrents CSV max from ${_originalMaxCap} to $_stage1Cap for Stage 1');
    try {
      await StorageService.setMaxTorrentsCsvResults(_stage1Cap);

      // Require RD API key early so we can prefetch as soon as results arrive
      final apiKeyEarly = await StorageService.getApiKey();
      if (apiKeyEarly == null || apiKeyEarly.isEmpty) {
        if (!mounted) return;
        _log('❌ Real Debrid API key not found - please add it in Settings');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add your Real Debrid API key in Settings first!')),
        );
        debugPrint('DebrifyTV: Missing Real Debrid API key.');
        return;
      }

      // Helper to infer a filename-like title from a URL
      String _inferTitleFromUrl(String url) {
        final uri = Uri.tryParse(url);
        final last = (uri != null && uri.pathSegments.isNotEmpty)
            ? uri.pathSegments.last
            : url;
        return Uri.decodeComponent(last);
      }

      String firstTitle = 'Debrify TV';

      Future<Map<String, String>?> requestMagicNext() async {
        debugPrint('DebrifyTV: requestMagicNext() called. queueSize=${_queue.length}');
        while (_queue.isNotEmpty) {
          final item = _queue.removeAt(0);
          // Case 1: RD-restricted entry (append-only items)
          if (item is Map && item['type'] == 'rd_restricted') {
            final String link = item['restrictedLink'] as String? ?? '';
            final String rdTid = item['torrentId'] as String? ?? '';
            debugPrint('DebrifyTV: Trying RD link from queue: torrentId=$rdTid');
            if (link.isEmpty) continue;
            try {
              // Silent approach - no progress logging needed
              final started = DateTime.now();
              final unrestrict = await DebridService.unrestrictLink(apiKeyEarly, link);
              final elapsed = DateTime.now().difference(started).inSeconds;
              final videoUrl = unrestrict['download'] as String?;
              if (videoUrl != null && videoUrl.isNotEmpty) {
                debugPrint('DebrifyTV: Success (RD link). Unrestricted in ${elapsed}s');
                // Silent approach - no progress logging needed
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final display = (item['displayName'] as String?)?.trim();
                final chosenTitle = inferred.isNotEmpty ? inferred : (display ?? 'Debrify TV');
                firstTitle = chosenTitle;
                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint('DebrifyTV: RD link failed to unrestrict: $e');
              continue;
            }
          }

          // Case 2: Torrent entry
          if (item is Torrent) {
            debugPrint('DebrifyTV: Trying torrent: name="${item.name}", hash=${item.infohash}, size=${item.sizeBytes}, seeders=${item.seeders}');
            final magnetLink = 'magnet:?xt=urn:btih:${item.infohash}';
            try {
              final started = DateTime.now();
              final result = await DebridService.addTorrentToDebridPreferVideos(apiKeyEarly, magnetLink);
              final elapsed = DateTime.now().difference(started).inSeconds;
              final String torrentId = result['torrentId'] as String? ?? '';
              final List<String> rdLinks = (result['links'] as List<dynamic>? ?? const [])
                  .map((link) => link?.toString() ?? '')
                  .where((link) => link.isNotEmpty)
                  .toList();
              if (rdLinks.isEmpty) {
                continue;
              }

              final newLinks = rdLinks
                  .where((link) => !_seenRestrictedLinks.contains(link))
                  .toList();
              if (newLinks.isEmpty) {
                continue;
              }

              newLinks.shuffle(Random());
              final selectedLink = newLinks.removeAt(0);
              _seenRestrictedLinks.add(selectedLink);
              _seenLinkWithTorrentId.add('$torrentId|$selectedLink');

              final unrestrict = await DebridService.unrestrictLink(apiKeyEarly, selectedLink);
              final videoUrl = unrestrict['download'] as String?;
              if (videoUrl != null && videoUrl.isNotEmpty) {
                debugPrint('DebrifyTV: Success. Got unrestricted URL in ${elapsed}s');
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final chosenTitle = inferred.isNotEmpty
                    ? inferred
                    : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
                firstTitle = chosenTitle;

                if (newLinks.isNotEmpty) {
                  _queue.add(item);
                }

                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint('DebrifyTV: Debrid add failed for ${item.infohash}: $e');
            }
          }
        }
        debugPrint('DebrifyTV: requestMagicNext() queue exhausted.');
        return null;
      }

      final Map<String, Torrent> dedupByInfohash = {};

      // Silent approach - no progress logging needed
      
      // Launch per-keyword searches in parallel and process as they complete
      final futures = keywords.map((kw) {
        debugPrint('DebrifyTV: Searching engines for "$kw"...');
        return TorrentService.searchAllEngines(kw, useTorrentsCsv: true, usePirateBay: true);
      }).toList();

      await for (final result in Stream.fromFutures(futures)) {
        final List<Torrent> torrents = (result['torrents'] as List<Torrent>?) ?? <Torrent>[];
        final engineCounts = (result['engineCounts'] as Map<String, int>?) ?? const {};
        debugPrint('DebrifyTV: Partial results received: total=${torrents.length}, engineCounts=$engineCounts');
        int added = 0;
        for (final t in torrents) {
          if (!dedupByInfohash.containsKey(t.infohash)) {
            dedupByInfohash[t.infohash] = t;
            added++;
          }
        }
        if (added > 0) {
          final combined = dedupByInfohash.values.toList();
          combined.shuffle(Random());
          _queue
            ..clear()
            ..addAll(combined);
          _lastQueueSize = _queue.length;
          _lastSearchAt = DateTime.now();
          // Silent approach - no progress logging needed
          setState(() {
            _status = 'Preparing your content...';
          });

          // Do not start prefetch until player launches

          // Try to launch player as soon as a playable stream is available
          if (!_launchedPlayer) {
            final first = await requestMagicNext();
            if (first != null && mounted && !_launchedPlayer) {
              _launchedPlayer = true;
              final firstUrl = first['url'] ?? '';
              final firstTitleResolved = (first['title'] ?? firstTitle).trim().isNotEmpty ? (first['title'] ?? firstTitle) : firstTitle;
              if (_progressOpen && _progressSheetContext != null) {
                Navigator.of(_progressSheetContext!).pop();
              }
              debugPrint('DebrifyTV: Launching player early. Remaining queue=${_queue.length}');

              // Start background prefetch only while player is active
              if (apiKeyEarly != null && apiKeyEarly.isNotEmpty) {
                _activeApiKey = apiKeyEarly;
                _startPrefetch();
              }

              // Stage 2: Expand search in background to full (500) WHILE user watches
              if (!_stage2Running) {
                _stage2Running = true;
                // ignore: unawaited_futures
                (() async {
                  debugPrint('DebrifyTV: Stage 2 expansion starting. Temporarily setting max to 500');
                  try {
                    await StorageService.setMaxTorrentsCsvResults(500);
                    final futures2 = keywords.map((kw) {
                      debugPrint('DebrifyTV: [Stage 2] Searching engines for "$kw"...');
                      return TorrentService.searchAllEngines(kw, useTorrentsCsv: true, usePirateBay: true);
                    }).toList();
                    await for (final res2 in Stream.fromFutures(futures2)) {
                      final List<Torrent> more = (res2['torrents'] as List<Torrent>?) ?? <Torrent>[];
                      int added2 = 0;
                      for (final t in more) {
                        if (!dedupByInfohash.containsKey(t.infohash)) {
                          dedupByInfohash[t.infohash] = t;
                          added2++;
                        }
                      }
                      if (added2 > 0) {
                        final combined2 = dedupByInfohash.values.toList();
                        combined2.shuffle(Random());
                        // Preserve already prepared RD links at the head
                        final preparedOld = _queue
                            .where((e) => e is Map && e['type'] == 'rd_restricted')
                            .take(_minPrepared)
                            .toList();
                        _queue
                          ..clear()
                          ..addAll(preparedOld)
                          ..addAll(combined2);
                        _lastQueueSize = _queue.length;
                        _lastSearchAt = DateTime.now();
                        debugPrint('DebrifyTV: [Stage 2] Queue expanded to ${_queue.length} (preserved ${preparedOld.length} prepared in head)');
                      }
                    }
                  } catch (e) {
                    debugPrint('DebrifyTV: Stage 2 expansion failed: $e');
                  } finally {
                    final restoreTo = _originalMaxCap ?? 50;
                    await StorageService.setMaxTorrentsCsvResults(restoreTo);
                    _stage2Running = false;
                    _capRestoredByStage2 = true;
                    debugPrint('DebrifyTV: Stage 2 done. Restored Torrents CSV max to $restoreTo');
                  }
                })();
              }

              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VideoPlayerScreen(
                    videoUrl: firstUrl,
                    title: firstTitleResolved,
                    startFromRandom: _startRandom,
                    randomStartMaxPercent: _randomStartPercent,
                    hideSeekbar: _hideSeekbar,
                    showWatermark: _showWatermark,
                    showVideoTitle: _showVideoTitle,
                    hideOptions: _hideOptions,
                    hideBackButton: _hideBackButton,
                    requestMagicNext: requestMagicNext,
                  ),
                ),
              );

              // Stop prefetch when player exits
              await _stopPrefetch();
            }
          }
        }
      }

      // Final queue snapshot (if we didn't launch early)
      if (!_launchedPlayer) {
        debugPrint('DebrifyTV: Queue prepared. size=${_queue.length}');
        _lastQueueSize = _queue.length;
        _lastSearchAt = DateTime.now();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Search failed: $e';
      });
      debugPrint('DebrifyTV: Search failed: $e');
    } finally {
      // Restore only if Stage 2 didn't already restore
      if (!_stage2Running && !_capRestoredByStage2) {
        final restoreTo = _originalMaxCap ?? 50;
        await StorageService.setMaxTorrentsCsvResults(restoreTo);
        debugPrint('DebrifyTV: Restored Torrents CSV max to $restoreTo after Stage 1');
      }
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }

    if (!mounted) return;
    if (_queue.isEmpty) {
      if (!mounted) return;
      setState(() {
        _status = 'No results found';
      });
      debugPrint('DebrifyTV: No results found after combining.');
      _log('❌ No results found - trying different search strategies');
      
      // Close popup and show user-friendly message
      if (_progressOpen && _progressSheetContext != null) {
        Navigator.of(_progressSheetContext!).pop();
        _progressOpen = false;
        _progressSheetContext = null;
      }
      
      if (mounted) {
        setState(() {
          _isBusy = false;
          _status = 'No results found. Try different keywords.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No results found. Try different keywords or check your internet connection.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // If we already launched the player early, we're done here
    if (_launchedPlayer) {
      if (!mounted) return;
      setState(() {
        _status = '';
      });
      return;
    }

    // Helper to infer a filename-like title from a URL
    String _inferTitleFromUrl(String url) {
      final uri = Uri.tryParse(url);
      final last = (uri != null && uri.pathSegments.isNotEmpty)
          ? uri.pathSegments.last
          : url;
      return Uri.decodeComponent(last);
    }

    // Build a provider for "next" requests that reuses the same queue and keywords
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add your Real Debrid API key in Settings first!')),
      );
      debugPrint('MagicTV: Missing Real Debrid API key.');
      return;
    }

    String firstTitle = 'Debrify TV';

    Future<Map<String, String>?> requestMagicNext() async {
      debugPrint('MagicTV: requestMagicNext() called. queueSize=${_queue.length}');
      while (_queue.isNotEmpty) {
        final item = _queue.removeAt(0);
        // Case 1: RD-restricted entry (append-only items)
        if (item is Map && item['type'] == 'rd_restricted') {
          final String link = item['restrictedLink'] as String? ?? '';
          final String rdTid = item['torrentId'] as String? ?? '';
          debugPrint('MagicTV: Trying RD link from queue: torrentId=$rdTid');
          if (link.isEmpty) continue;
          try {
            final started = DateTime.now();
            final unrestrict = await DebridService.unrestrictLink(apiKey, link);
            final elapsed = DateTime.now().difference(started).inSeconds;
            final videoUrl = unrestrict['download'] as String?;
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint('MagicTV: Success (RD link). Unrestricted in ${elapsed}s');
              // Prefer filename inferred from URL; fallback to any stored displayName
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final display = (item['displayName'] as String?)?.trim();
              final chosenTitle = inferred.isNotEmpty ? inferred : (display ?? 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('MagicTV: RD link failed to unrestrict: $e');
            continue;
          }
        }

        // Case 2: Torrent entry
        if (item is Torrent) {
          debugPrint('MagicTV: Trying torrent: name="${item.name}", hash=${item.infohash}, size=${item.sizeBytes}, seeders=${item.seeders}');
          final magnetLink = 'magnet:?xt=urn:btih:${item.infohash}';
          try {
            final started = DateTime.now();
            final result = await DebridService.addTorrentToDebridPreferVideos(apiKey, magnetLink);
            final elapsed = DateTime.now().difference(started).inSeconds;
            final videoUrl = result['downloadLink'] as String?;
            // Append other RD-restricted links from this torrent to the END of the queue
            final String torrentId = result['torrentId'] as String? ?? '';
            final List<dynamic> rdLinks = (result['links'] as List<dynamic>? ?? const []);
            if (rdLinks.isNotEmpty) {
              // We assume we used rdLinks[0] to play; enqueue remaining
              for (int i = 1; i < rdLinks.length; i++) {
                final String link = rdLinks[i]?.toString() ?? '';
                if (link.isEmpty) continue;
                final String combined = '$torrentId|$link';
                if (_seenRestrictedLinks.contains(link) || _seenLinkWithTorrentId.contains(combined)) {
                  continue;
                }
                _seenRestrictedLinks.add(link);
                _seenLinkWithTorrentId.add(combined);
                _queue.add({
                  'type': 'rd_restricted',
                  'restrictedLink': link,
                  'torrentId': torrentId,
                  'displayName': item.name,
                });
              }
              if (rdLinks.length > 1) {
                debugPrint('MagicTV: Enqueued ${rdLinks.length - 1} additional RD links to tail. New queueSize=${_queue.length}');
              }
            }
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint('MagicTV: Success. Got unrestricted URL in ${elapsed}s');
              // Prefer filename inferred from URL; fallback to torrent name
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final chosenTitle = inferred.isNotEmpty ? inferred : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('MagicTV: Debrid add failed for ${item.infohash}: $e');
          }
        }
      }
      debugPrint('MagicTV: requestMagicNext() queue exhausted.');
      return null;
    }

    setState(() {
      _status = 'Finding a playable stream...';
      _isBusy = true;
    });
    _log('🎬 Selecting the best quality stream for you');

    try {
      final first = await requestMagicNext();
      if (first == null) {
        // Close popup and show user-friendly message
        if (_progressOpen && _progressSheetContext != null) {
          Navigator.of(_progressSheetContext!).pop();
          _progressOpen = false;
          _progressSheetContext = null;
        }
        
        if (mounted) {
          setState(() {
            _isBusy = false;
            _status = 'No playable torrents found. Try different keywords.';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No playable streams found. Try different keywords or check your internet connection.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
        debugPrint('MagicTV: No playable stream found.');
        return;
      }
      final firstUrl = first['url'] ?? '';
      firstTitle = (first['title'] ?? firstTitle).trim().isNotEmpty ? (first['title'] ?? firstTitle) : firstTitle;
      // Navigate to the player with a Next callback
      if (!mounted) return;
      debugPrint('MagicTV: Launching player. Remaining queue=${_queue.length}');
      // Start background prefetch while player is active
      _activeApiKey = apiKey;
      _startPrefetch();
      if (_progressOpen && _progressSheetContext != null) {
        Navigator.of(_progressSheetContext!).pop();
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: firstUrl,
            title: firstTitle,
            startFromRandom: _startRandom,
            randomStartMaxPercent: _randomStartPercent,
            hideSeekbar: _hideSeekbar,
            showWatermark: _showWatermark,
            showVideoTitle: _showVideoTitle,
            hideOptions: _hideOptions,
            hideBackButton: _hideBackButton,
            requestMagicNext: requestMagicNext,
          ),
        ),
      );
      // Stop prefetch when player exits
      await _stopPrefetch();
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _status = '';
        });
        debugPrint('MagicTV: Watch flow finished.');
      }
    }
  }

  Future<void> _watchWithTorbox(
    List<String> keywords,
    void Function(String message) log,
  ) async {
    final integrationEnabled =
        await StorageService.getTorboxIntegrationEnabled();
    if (!integrationEnabled) {
      _closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _status = 'Enable Torbox in Settings to use this provider.';
        _isBusy = false;
      });
      _showSnack(
        'Enable Torbox in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _status = 'Add your Torbox API key in Settings to use this provider.';
        _isBusy = false;
      });
      _showSnack(
        'Please add your Torbox API key in Settings first!',
        color: Colors.red,
      );
      return;
    }

    log('🌐 Torbox: searching for cached torrents...');
    final originalCap = await StorageService.getMaxTorrentsCsvResults();
    final Map<String, Torrent> dedup = <String, Torrent>{};

    try {
      await StorageService.setMaxTorrentsCsvResults(500);

      final futures = keywords
          .map(
            (kw) => TorrentService.searchAllEngines(
              kw,
              useTorrentsCsv: true,
              usePirateBay: true,
            ),
          )
          .toList();

      await for (final result in Stream.fromFutures(futures)) {
        final torrents =
            (result['torrents'] as List<Torrent>? ?? const <Torrent>[]);
        int added = 0;
        for (final torrent in torrents) {
          final normalizedHash = _normalizeInfohash(torrent.infohash);
          if (normalizedHash.isEmpty) continue;
          if (!dedup.containsKey(normalizedHash)) {
            dedup[normalizedHash] = torrent;
            added++;
          }
        }
        if (added > 0) {
          final combined = dedup.values.toList();
          combined.shuffle(Random());
          _queue
            ..clear()
            ..addAll(combined);
          _lastQueueSize = _queue.length;
          _lastSearchAt = DateTime.now();
          if (mounted) {
            setState(() {
              _status = 'Checking Torbox cache...';
            });
          }
        }
      }

      final combinedList = dedup.values.toList();
      if (combinedList.isEmpty) {
        _closeProgressDialog();
        if (mounted) {
          setState(() {
            _status = 'No results found. Try different keywords.';
          });
          _showSnack(
            'No results found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      final uniqueHashes = combinedList
          .map((torrent) => _normalizeInfohash(torrent.infohash))
          .where((hash) => hash.isNotEmpty)
          .toList();

      if (uniqueHashes.isEmpty) {
        _closeProgressDialog();
        if (mounted) {
          setState(() {
            _status = 'No valid torrents found for Torbox.';
          });
        }
        return;
      }

      Set<String> cachedHashes;
      try {
        cachedHashes = await TorboxService.checkCachedTorrents(
          apiKey: apiKey,
          infoHashes: uniqueHashes,
          listFiles: false,
        );
      } catch (e) {
        log('❌ Torbox cache check failed: $e');
        _closeProgressDialog();
        if (mounted) {
          setState(() {
            _status = 'Torbox cache check failed. Try again.';
          });
          _showSnack(
            'Torbox cache check failed: ${_formatTorboxError(e)}',
            color: Colors.red,
          );
        }
        return;
      }

      final filtered = combinedList
          .where(
            (torrent) =>
                cachedHashes.contains(_normalizeInfohash(torrent.infohash)),
          )
          .toList();

      if (filtered.isEmpty) {
        _closeProgressDialog();
        if (mounted) {
          setState(() {
            _status = 'Torbox has no cached results for these keywords.';
          });
          _showSnack(
            'Torbox has no cached results for these keywords.',
            color: Colors.orange,
          );
        }
        return;
      }

      filtered.shuffle(Random());
      _queue
        ..clear()
        ..addAll(filtered);
      _lastQueueSize = _queue.length;
      _lastSearchAt = DateTime.now();
      if (mounted) {
        setState(() {
          _status =
              'Found ${_queue.length} cached Torbox result${_queue.length == 1 ? '' : 's'}';
        });
      }
      log('✅ Found ${_queue.length} cached Torbox torrent(s)');

      Future<Map<String, String>?> requestTorboxNext() async {
        while (_queue.isNotEmpty) {
          final item = _queue.removeAt(0);
          if (item is Map && item['type'] == _torboxFileEntryType) {
            final resolved = await _resolveTorboxQueuedFile(
              entry: item as Map<String, dynamic>,
              apiKey: apiKey,
              log: log,
            );
            if (resolved != null) {
              if (mounted) {
                setState(() {
                  _status =
                      _queue.isEmpty ? '' : 'Queue has ${_queue.length} remaining';
                });
              }
              return resolved;
            }
            continue;
          }

          if (item is Torrent) {
            final result = await _prepareTorboxTorrent(
              candidate: item,
              apiKey: apiKey,
              log: log,
            );
            if (result != null) {
              if (result.hasMore) {
                _queue.add(item);
              }
              if (mounted) {
                setState(() {
                  _status = _queue.isEmpty
                      ? ''
                      : 'Queue has ${_queue.length} remaining';
                });
              }
              return {
                'url': result.streamUrl,
                'title': result.title,
              };
            }
          }
        }
        if (mounted) {
          setState(() {
            _status = 'No more cached Torbox streams available.';
          });
        }
        return null;
      }

      final first = await requestTorboxNext();
      if (first == null) {
        _closeProgressDialog();
        if (mounted) {
          setState(() {
            _status = 'No playable Torbox streams found. Try different keywords.';
          });
          _showSnack(
            'No playable Torbox streams found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      _closeProgressDialog();
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: first['url'] ?? '',
            title: first['title'] ?? 'Debrify TV',
            startFromRandom: _startRandom,
            randomStartMaxPercent: _randomStartPercent,
            hideSeekbar: _hideSeekbar,
            showWatermark: _showWatermark,
            showVideoTitle: _showVideoTitle,
            hideOptions: _hideOptions,
            hideBackButton: _hideBackButton,
            requestMagicNext: requestTorboxNext,
          ),
        ),
      );

      if (mounted) {
        setState(() {
          _status = _queue.isEmpty ? '' : 'Queue has ${_queue.length} remaining';
        });
      }
    } finally {
      await StorageService.setMaxTorrentsCsvResults(originalCap);
      _closeProgressDialog();
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _watchWithCachedTorrents(List<Torrent> cachedTorrents) async {
    if (cachedTorrents.isEmpty) {
      _showSnack('Cached channel has no torrents yet. Please wait a moment.',
          color: Colors.orange);
      return;
    }

    _launchedPlayer = false;
    await _stopPrefetch();
    _prefetchStopRequested = false;
    _stage2Running = false;
    _capRestoredByStage2 = false;
    _originalMaxCap = null;
    _seenRestrictedLinks.clear();
    _seenLinkWithTorrentId.clear();

    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      _showSnack('Please add your Real Debrid API key in Settings first!',
          color: Colors.orange);
      return;
    }

    _showCachedPlaybackDialog();

    _queue
      ..clear()
      ..addAll(List<Torrent>.from(cachedTorrents)..shuffle(Random()));
    _lastQueueSize = _queue.length;
    _lastSearchAt = DateTime.now();

    String _inferTitleFromUrl(String url) {
      final uri = Uri.tryParse(url);
      final last = (uri != null && uri.pathSegments.isNotEmpty)
          ? uri.pathSegments.last
          : url;
      return Uri.decodeComponent(last);
    }

    String firstTitle = 'Debrify TV';

    Future<Map<String, String>?> requestMagicNext() async {
      debugPrint('DebrifyTV: Cached requestMagicNext() queueSize=${_queue.length}');
      while (_queue.isNotEmpty) {
        final item = _queue.removeAt(0);
        if (item is Map && item['type'] == 'rd_restricted') {
          final String link = item['restrictedLink'] as String? ?? '';
          final String rdTid = item['torrentId'] as String? ?? '';
          debugPrint('DebrifyTV: Cached path trying RD link: torrentId=$rdTid');
          if (link.isEmpty) continue;
          try {
            final started = DateTime.now();
            final unrestrict = await DebridService.unrestrictLink(apiKey, link);
            final elapsed = DateTime.now().difference(started).inSeconds;
            final videoUrl = unrestrict['download'] as String?;
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint('DebrifyTV: Cached success (RD link) in ${elapsed}s');
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final display = (item['displayName'] as String?)?.trim();
              final chosenTitle =
                  inferred.isNotEmpty ? inferred : (display ?? 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('DebrifyTV: Cached RD link failed: $e');
            continue;
          }
        }

        if (item is Torrent) {
          debugPrint(
              'DebrifyTV: Cached trying torrent name="${item.name}" hash=${item.infohash}');
          final magnetLink = 'magnet:?xt=urn:btih:${item.infohash}';
          try {
            final started = DateTime.now();
            final result = await DebridService.addTorrentToDebridPreferVideos(
              apiKey,
              magnetLink,
            );
            final elapsed = DateTime.now().difference(started).inSeconds;
            final String torrentId = result['torrentId'] as String? ?? '';
            final List<String> rdLinks =
                (result['links'] as List<dynamic>? ?? const [])
                    .map((link) => link?.toString() ?? '')
                    .where((link) => link.isNotEmpty)
                    .toList();
            if (rdLinks.isEmpty) {
              continue;
            }

            final newLinks = rdLinks
                .where((link) => !_seenRestrictedLinks.contains(link))
                .toList();
            if (newLinks.isEmpty) {
              continue;
            }

            newLinks.shuffle(Random());
            final selectedLink = newLinks.removeAt(0);
            _seenRestrictedLinks.add(selectedLink);
            _seenLinkWithTorrentId.add('$torrentId|$selectedLink');

            final unrestrict =
                await DebridService.unrestrictLink(apiKey, selectedLink);
            final videoUrl = unrestrict['download'] as String?;
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint('DebrifyTV: Cached success: unrestricted in ${elapsed}s');
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
              firstTitle = chosenTitle;

              if (newLinks.isNotEmpty) {
                _queue.add(item);
              }

              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('DebrifyTV: Cached Debrid add failed: $e');
          }
        }
      }
      debugPrint('DebrifyTV: Cached queue exhausted.');
      return null;
    }

    setState(() {
      _status = 'Finding a playable stream...';
      _isBusy = true;
    });

    try {
      final first = await requestMagicNext();
      if (first == null) {
        _closeProgressDialog();
        if (!mounted) return;
        setState(() {
          _isBusy = false;
          _status =
              'No cached torrents played successfully. Try refreshing the channel.';
        });
        _showSnack(
          'No cached torrents played successfully. Try refreshing the channel.',
          color: Colors.orange,
        );
        return;
      }

      final firstUrl = first['url'] ?? '';
      firstTitle = (first['title'] ?? firstTitle).trim().isNotEmpty
          ? (first['title'] ?? firstTitle)
          : firstTitle;

      if (!mounted) return;
      _activeApiKey = apiKey;
      _startPrefetch();
      _closeProgressDialog();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: firstUrl,
            title: firstTitle,
            startFromRandom: _startRandom,
            randomStartMaxPercent: _randomStartPercent,
            hideSeekbar: _hideSeekbar,
            showWatermark: _showWatermark,
            showVideoTitle: _showVideoTitle,
            hideOptions: _hideOptions,
            hideBackButton: _hideBackButton,
            requestMagicNext: requestMagicNext,
          ),
        ),
      );
      await _stopPrefetch();
    } finally {
      _closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _status = '';
      });
      debugPrint('DebrifyTV: Cached watch flow finished.');
    }
  }

  Future<void> _watchTorboxWithCachedTorrents(
    List<Torrent> cachedTorrents,
  ) async {
    if (cachedTorrents.isEmpty) {
      _showSnack('Cached channel has no torrents yet. Please wait a moment.',
          color: Colors.orange);
      return;
    }

    void log(String message) {
      debugPrint('DebrifyTV: $message');
    }

    final integrationEnabled =
        await StorageService.getTorboxIntegrationEnabled();
    if (!integrationEnabled) {
      _showSnack('Enable Torbox in Settings to use this provider.',
          color: Colors.orange);
      return;
    }

    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _showSnack('Please add your Torbox API key in Settings first!',
          color: Colors.orange);
      return;
    }

    final uniqueHashes = cachedTorrents
        .map((torrent) => _normalizeInfohash(torrent.infohash))
        .where((hash) => hash.isNotEmpty)
        .toSet();

    if (uniqueHashes.isEmpty) {
      _showSnack('Cached torrents look invalid. Try refreshing the channel.',
          color: Colors.orange);
      return;
    }

    _showCachedPlaybackDialog();

    Set<String> cachedHashes;
    try {
      cachedHashes = await TorboxService.checkCachedTorrents(
        apiKey: apiKey,
        infoHashes: uniqueHashes.toList(),
        listFiles: false,
      );
      debugPrint(
        'DebrifyTV: Torbox cache check returned ${cachedHashes.length} cached torrent(s) out of ${uniqueHashes.length}.',
      );
    } catch (e) {
      _closeProgressDialog();
      _showSnack(
        'Torbox cache check failed: ${_formatTorboxError(e)}',
        color: Colors.orange,
      );
      return;
    }

    final filtered = cachedTorrents
        .where(
          (torrent) =>
              cachedHashes.contains(_normalizeInfohash(torrent.infohash)),
        )
        .toList();

    if (filtered.isEmpty) {
      _closeProgressDialog();
      _showSnack(
        'Cached torrents are no longer available on Torbox. Please refresh the channel.',
        color: Colors.orange,
      );
      return;
    }

    _queue
      ..clear()
      ..addAll(List<Torrent>.from(filtered)..shuffle(Random()));
    _lastQueueSize = _queue.length;
    _lastSearchAt = DateTime.now();

    setState(() {
      _status = 'Preparing Torbox stream...';
      _isBusy = true;
    });
    Future<Map<String, String>?> requestTorboxNext() async {
      while (_queue.isNotEmpty) {
        final next = _queue.removeAt(0);
        if (next is Map && next['type'] == _torboxFileEntryType) {
          final resolved = await _resolveTorboxQueuedFile(
            entry: Map<String, dynamic>.from(next as Map),
            apiKey: apiKey,
            log: log,
          );
          if (resolved != null) {
            return resolved;
          }
          continue;
        }

        if (next is! Torrent) {
          continue;
        }

        final prepared = await _prepareTorboxTorrent(
          candidate: next,
          apiKey: apiKey,
          log: log,
        );
        if (prepared == null) {
          continue;
        }

        if (prepared.hasMore) {
          _queue.add(next);
        }
        return {
          'url': prepared.streamUrl,
          'title': prepared.title,
        };
      }
      return null;
    }

    try {
      final first = await requestTorboxNext();
      if (first == null) {
        _closeProgressDialog();
        if (!mounted) return;
        setState(() {
          _status = 'No playable Torbox streams found. Try refreshing.';
          _isBusy = false;
        });
        _showSnack(
          'No cached Torbox streams are playable. Try refreshing the channel.',
          color: Colors.orange,
        );
        return;
      }

      if (!mounted) return;
      _closeProgressDialog();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: first['url'] ?? '',
            title: first['title'] ?? 'Debrify TV',
            startFromRandom: _startRandom,
            randomStartMaxPercent: _randomStartPercent,
            hideSeekbar: _hideSeekbar,
            showWatermark: _showWatermark,
            showVideoTitle: _showVideoTitle,
            hideOptions: _hideOptions,
            hideBackButton: _hideBackButton,
            requestMagicNext: requestTorboxNext,
          ),
        ),
      );
      if (mounted) {
        setState(() {
          _status = _queue.isEmpty
              ? ''
              : 'Queue has ${_queue.length} remaining';
        });
      }
    } finally {
      _closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _isBusy = false;
      });
    }
  }

  void _showChannelCreationDialog(String channelName) {
    if (_progressOpen || !mounted) {
      return;
    }
    _progress.value = [];
    _progressOpen = true;
    Future.microtask(() {
      if (!mounted || !_progressOpen) {
        return;
      }
      showGeneralDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.6),
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (ctx, _, __) {
          return _ChannelCreationDialog(
            channelName: channelName,
            onReady: (dialogCtx) {
              _progressSheetContext = dialogCtx;
            },
          );
        },
        transitionBuilder: (ctx, animation, secondary, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: curved,
              child: child,
            ),
          );
        },
      );
    });
  }

  void _showCachedPlaybackDialog() {
    if (_progressOpen || !mounted) {
      return;
    }
    _progress.value = [];
    _progressOpen = true;
    Future.microtask(() {
      if (!mounted || !_progressOpen) {
        return;
      }
      showGeneralDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.6),
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (ctx, _, __) {
          return _CachedLoadingDialog(
            onReady: (dialogCtx) {
              _progressSheetContext = dialogCtx;
            },
          );
        },
        transitionBuilder: (ctx, animation, secondary, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: curved,
              child: child,
            ),
          );
        },
      );
    });
  }

  Future<void> _playNextFromQueue() async {
    if (_isBusy) return;
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add your Real Debrid API key in Settings first!')),
      );
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Finding a playable stream...';
    });

    try {
      while (_queue.isNotEmpty) {
        final next = _queue.removeAt(0);
        final magnetLink = 'magnet:?xt=urn:btih:${next.infohash}';
        try {
          final result = await DebridService.addTorrentToDebridPreferVideos(apiKey, magnetLink);
          final videoUrl = result['downloadLink'] as String?;
          if (videoUrl != null && videoUrl.isNotEmpty) {
            if (!mounted) return;
            setState(() {
              _status = 'Playing: ${next.name}';
            });
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VideoPlayerScreen(
                  videoUrl: videoUrl,
                  title: next.name,
                  startFromRandom: _startRandom,
                  randomStartMaxPercent: _randomStartPercent,
                  hideSeekbar: _hideSeekbar,
                  showWatermark: _showWatermark,
                  showVideoTitle: _showVideoTitle,
                  hideOptions: _hideOptions,
                  hideBackButton: _hideBackButton,
                ),
              ),
            );
            break;
          }
        } catch (_) {
          // Skip not readily available / failed items and continue
          continue;
        }
      }

      if (_queue.isEmpty) {
        // Close popup and show user-friendly message
        if (_progressOpen && _progressSheetContext != null) {
          Navigator.of(_progressSheetContext!).pop();
          _progressOpen = false;
          _progressSheetContext = null;
        }
        
        if (mounted) {
          setState(() {
            _isBusy = false;
            _status = 'No playable torrents found. Try different keywords.';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All torrents failed to process. Try different keywords or check your internet connection.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        setState(() {
          _status = 'Queue has ${_queue.length} remaining';
        });
      }
    } finally {
      setState(() {
        _isBusy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.tv_rounded, color: Colors.white70),
                SizedBox(width: 8),
                Text(
                  'Debrify TV',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12, width: 1),
                ),
                child: TabBar(
                  indicator: BoxDecoration(
                    color: const Color(0xFFE50914).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  tabs: const [
                    Tab(text: 'Quick Play'),
                    Tab(text: 'Channels'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildQuickPlayTab(bottomInset),
                  _buildChannelsTab(bottomInset),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickPlayTab(double bottomInset) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: Column(
        children: [
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x221E3A8A), Color(0x2214B8A6)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12, width: 1),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _keywordsController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _watch(),
                    decoration: InputDecoration(
                      hintText: 'Comma separated keywords',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: _isBusy
                            ? null
                            : () {
                                _keywordsController.clear();
                              },
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _isBusy ? null : _watch,
                      icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                      label: const Text(
                        'Watch',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                        disabledBackgroundColor: const Color(0x66E50914),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lightbulb_outline_rounded,
                                color: Colors.amber[300], size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Quick Tips',
                              style: TextStyle(
                                color: Colors.amber[200],
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Next Video: Android double tap far right, Mac/Windows press \'N\'',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Quit: Mac/Windows press ESC, Android use back button',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F).withOpacity(0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12, width: 1),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.settings_rounded, color: Colors.white70, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Advanced options',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Content provider',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Tooltip(
                        message: _rdAvailable
                            ? 'Use Real Debrid for Debrify TV'
                            : 'Enable Real Debrid and add an API key in Settings to use this option.',
                        child: ChoiceChip(
                          label: const Text('Real Debrid'),
                          selected: _provider == _providerRealDebrid,
                          disabledColor: Colors.white12,
                          onSelected: (!_rdAvailable || _isBusy)
                              ? null
                              : (selected) {
                                  if (selected) {
                                    _updateProvider(_providerRealDebrid);
                                  }
                                },
                        ),
                      ),
                      Tooltip(
                        message: _torboxAvailable
                            ? 'Use Torbox for Debrify TV'
                            : 'Enable Torbox and add an API key in Settings to use this option.',
                        child: ChoiceChip(
                          label: const Text('Torbox'),
                          selected: _provider == _providerTorbox,
                          disabledColor: Colors.white12,
                          onSelected: (!_torboxAvailable || _isBusy)
                              ? null
                              : (selected) {
                                  if (selected) {
                                    _updateProvider(_providerTorbox);
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SwitchRow(
                    title: 'Start from random timestamp',
                    subtitle: 'Each Debrify TV video starts at a random point',
                    value: _startRandom,
                    onChanged: (v) async {
                      setState(() => _startRandom = v);
                      await StorageService.saveDebrifyTvStartRandom(v);
                    },
                  ),
                  if (_startRandom) ...[
                    const SizedBox(height: 8),
                    _RandomStartSlider(
                      value: _randomStartPercent,
                      onChanged: (next) {
                        setState(() => _randomStartPercent = next);
                      },
                      onChangeEnd: (next) {
                        StorageService.saveDebrifyTvRandomStartPercent(next);
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: 'Show DebrifyTV watermark',
                    subtitle: 'Display a subtle DebrifyTV tag on the video',
                    value: _showWatermark,
                    onChanged: (v) async {
                      setState(() => _showWatermark = v);
                      await StorageService.saveDebrifyTvShowWatermark(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: 'Show video title',
                    subtitle: 'Display video title and subtitle in player controls',
                    value: _showVideoTitle,
                    onChanged: (v) async {
                      setState(() => _showVideoTitle = v);
                      await StorageService.saveDebrifyTvShowVideoTitle(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: 'Hide all options',
                    subtitle: 'Hide all bottom controls (next, audio, etc.) - back button stays',
                    value: _hideOptions,
                    onChanged: (v) async {
                      setState(() {
                        _hideOptions = v;
                        _hideSeekbar = v;
                      });
                      await StorageService.saveDebrifyTvHideOptions(v);
                      await StorageService.saveDebrifyTvHideSeekbar(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: 'Hide back button',
                    subtitle: 'Hide back button - use device back gesture or escape key',
                    value: _hideBackButton,
                    onChanged: (v) async {
                      setState(() => _hideBackButton = v);
                      await StorageService.saveDebrifyTvHideBackButton(v);
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final defaultProvider = _determineDefaultProvider(
                          null,
                          _rdAvailable,
                          _torboxAvailable,
                        );
                        setState(() {
                          _startRandom = true;
                          _hideSeekbar = true;
                          _showWatermark = true;
                          _showVideoTitle = false;
                          _hideOptions = true;
                          _hideBackButton = true;
                          _provider = defaultProvider;
                        });

                        await StorageService.saveDebrifyTvStartRandom(true);
                        await StorageService.saveDebrifyTvHideSeekbar(true);
                        await StorageService.saveDebrifyTvShowWatermark(true);
                        await StorageService.saveDebrifyTvShowVideoTitle(false);
                        await StorageService.saveDebrifyTvHideOptions(true);
                        await StorageService.saveDebrifyTvHideBackButton(true);
                        await StorageService.saveDebrifyTvProvider(
                          defaultProvider,
                        );

                        if (!mounted) {
                          return;
                        }

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Reset to defaults successful'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: const Text('Reset to Defaults'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.1),
                        foregroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_status.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _status,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildChannelsTab(double bottomInset) {
    final searchTerm = _channelSearchTerm.trim().toLowerCase();
    final filteredChannels = searchTerm.isEmpty
        ? _channels
        : _channels
            .where(
              (channel) => channel.name.toLowerCase().contains(searchTerm),
            )
            .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Saved Channels',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _handleAddChannel,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Channel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _channelSearchController,
            onChanged: (value) {
              setState(() {
                _channelSearchTerm = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search channels...',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon:
                  const Icon(Icons.search_rounded, color: Colors.white60),
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filteredChannels.isEmpty
                ? (_channels.isEmpty
                    ? _buildEmptyChannelsState()
                    : _buildNoChannelResultsState())
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: filteredChannels.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final channel = filteredChannels[index];
                      return _buildChannelCard(channel);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChannelsState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.tv_rounded, color: Colors.white54, size: 36),
            SizedBox(height: 12),
            Text(
              'No channels yet',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Save your favorite keyword combos so Debrify TV can play them on demand.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoChannelResultsState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.search_off_rounded, color: Colors.white54, size: 36),
          SizedBox(height: 12),
          Text(
            'No channels match your search',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Try a different name or clear the filter to see all channels.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildChannelCard(_DebrifyTvChannel channel) {
    final keywords = channel.keywords;
    final cacheEntry = _channelCache[channel.id];
    final int cachedCount = cacheEntry?.torrents.length ?? 0;
    final bool isExpanded = _expandedChannelIds.contains(channel.id);
    final optionChips = <Widget>[];
    if (channel.startRandom) {
      optionChips.add(
        _buildOptionChip(
          Icons.shuffle_rounded,
          'Random start (first ${channel.randomStartPercent}%)',
        ),
      );
    }
    if (channel.showWatermark) {
      optionChips.add(_buildOptionChip(Icons.water_drop_outlined, 'Watermark'));
    }
    if (channel.showVideoTitle) {
      optionChips.add(_buildOptionChip(Icons.title_rounded, 'Show title'));
    }
    if (channel.hideOptions) {
      optionChips.add(_buildOptionChip(Icons.tune_rounded, 'Options hidden'));
    }
    if (channel.hideBackButton) {
      optionChips.add(_buildOptionChip(Icons.arrow_back_ios_new_rounded, 'Back hidden'));
    }

    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: isExpanded ? 'Collapse details' : 'Show details',
                onPressed: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedChannelIds.remove(channel.id);
                    } else {
                      _expandedChannelIds.add(channel.id);
                    }
                  });
                },
                icon: Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.white70,
                ),
              ),
              Expanded(
                child: Text(
                  channel.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isBusy ? null : () => _watchChannel(channel),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Watch'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit channel',
                onPressed: () => _handleEditChannel(channel),
                icon: const Icon(Icons.edit_rounded, color: Colors.white70),
              ),
              IconButton(
                tooltip: 'Delete channel',
                onPressed: () => _handleDeleteChannel(channel),
                icon: const Icon(Icons.delete_outline_rounded,
                    color: Colors.redAccent),
              ),
            ],
          ),
          if (isExpanded) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.settings_input_component_rounded,
                  color: Colors.white54,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '${keywords.length} keyword${keywords.length == 1 ? '' : 's'} • ${_providerDisplay(channel.provider)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (keywords.isEmpty)
              const Text(
                'No keywords saved yet',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: keywords
                    .map((keyword) => _buildKeywordChip(keyword))
                    .toList(),
              ),
            if (optionChips.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: optionChips,
              ),
            ],
            if (cacheEntry != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    cachedCount > 0
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_download_rounded,
                    color: cachedCount > 0
                        ? Colors.greenAccent
                        : Colors.blueAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cachedCount > 0
                          ? '$cachedCount cached torrent${cachedCount == 1 ? '' : 's'} ready'
                          : 'Cache will auto-refresh when you edit the channel.',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
    return card;
  }

  Widget _buildKeywordChip(String keyword) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Text(
        keyword,
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
    );
  }

  Widget _buildOptionChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<Map<String, String>?> _resolveTorboxQueuedFile({
    required Map<String, dynamic> entry,
    required String apiKey,
    required void Function(String message) log,
  }) async {
    final torrentId = entry['torrentId'] as int?;
    final TorboxFile? file = entry['file'] as TorboxFile?;
    final String? title = entry['title'] as String?;
    if (torrentId == null || file == null) {
      return null;
    }
    try {
      final streamUrl = await TorboxService.requestFileDownloadLink(
        apiKey: apiKey,
        torrentId: torrentId,
        fileId: file.id,
      );
      final resolvedTitle = title ?? _torboxDisplayName(file);
      log('➡️ Torbox: streaming $resolvedTitle');
      return {
        'url': streamUrl,
        'title': resolvedTitle,
      };
    } catch (e) {
      log('❌ Torbox stream failed: $e');
      return null;
    }
  }

  Future<_TorboxPreparedTorrent?> _prepareTorboxTorrent({
    required Torrent candidate,
    required String apiKey,
    required void Function(String message) log,
  }) async {
    final infohash = _normalizeInfohash(candidate.infohash);
    if (infohash.isEmpty) {
      return null;
    }

    log('⏳ Torbox: preparing ${candidate.name}');

    final magnetLink = 'magnet:?xt=urn:btih:${candidate.infohash}';
    Map<String, dynamic> response;
    try {
      response = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: magnetLink,
        seed: true,
        allowZip: false,
        addOnlyIfCached: true,
      );
    } catch (e) {
      log('❌ Torbox createtorrent failed: $e');
      return null;
    }

    final success = response['success'] as bool? ?? false;
    if (!success) {
      final error = (response['error'] ?? '').toString();
      log('⚠️ Torbox createtorrent error: $error');
      return null;
    }

    final data = response['data'];
    final torrentId = _asIntMapValue(data, 'torrent_id');
    if (torrentId == null) {
      log('⚠️ Torbox createtorrent missing torrent_id');
      return null;
    }

    TorboxTorrent? torboxTorrent;
    for (int attempt = 0; attempt < 6; attempt++) {
      torboxTorrent = await TorboxService.getTorrentById(
        apiKey,
        torrentId,
        attempts: 1,
        pageSize: 100,
      );
      if (torboxTorrent != null && torboxTorrent.files.isNotEmpty) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }

    if (torboxTorrent == null || torboxTorrent.files.isEmpty) {
      log('⚠️ Torbox torrent details not ready for ${candidate.name}');
      return null;
    }

    final currentTorrent = torboxTorrent;

    final playableEntries = _buildTorboxPlayableEntries(
      currentTorrent,
      candidate.name,
    );
    if (playableEntries.isEmpty) {
      log('⚠️ Torbox torrent has no playable files ${candidate.name}');
      return null;
    }

    final random = Random();
    final filteredEntries = playableEntries
        .where((entry) => !_seenLinkWithTorrentId
            .contains('${currentTorrent.id}|${entry.file.id}'))
        .toList();
    if (filteredEntries.isEmpty) {
      log('⚠️ Torbox torrent has no unseen playable files ${candidate.name}');
      return null;
    }

    filteredEntries.shuffle(random);
    final next = filteredEntries.removeAt(0);
    try {
      final streamUrl = await TorboxService.requestFileDownloadLink(
        apiKey: apiKey,
        torrentId: currentTorrent.id,
        fileId: next.file.id,
      );
      log('🎬 Torbox: streaming ${next.title}');
      _seenLinkWithTorrentId.add('${currentTorrent.id}|${next.file.id}');
      return _TorboxPreparedTorrent(
        streamUrl: streamUrl,
        title: next.title,
        hasMore: filteredEntries.isNotEmpty,
      );
    } catch (e) {
      log('❌ Torbox requestdl failed: $e');
      return null;
    }
  }

  List<_TorboxPlayableEntry> _buildTorboxPlayableEntries(
    TorboxTorrent torrent,
    String fallbackTitle,
  ) {
    final entries = <_TorboxPlayableEntry>[];
    final seriesCandidates = <_TorboxPlayableEntry>[];
    final otherCandidates = <_TorboxPlayableEntry>[];

    for (final file in torrent.files) {
      if (!_torboxFileLooksLikeVideo(file)) continue;
      if (file.size < _torboxMinVideoSizeBytes) continue;
      final displayName = _torboxDisplayName(file);
      final info = SeriesParser.parseFilename(displayName);
      final title = info.isSeries
          ? _formatTorboxSeriesTitle(info, fallbackTitle)
          : (displayName.isNotEmpty ? displayName : fallbackTitle);
      final entry = _TorboxPlayableEntry(
        file: file,
        title: title,
        info: info,
      );
      if (info.isSeries && info.season != null && info.episode != null) {
        seriesCandidates.add(entry);
      } else {
        otherCandidates.add(entry);
      }
    }

    seriesCandidates.sort((a, b) {
      final seasonCompare = (a.info.season ?? 0).compareTo(b.info.season ?? 0);
      if (seasonCompare != 0) return seasonCompare;
      return (a.info.episode ?? 0).compareTo(b.info.episode ?? 0);
    });

    otherCandidates.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );

    entries
      ..addAll(seriesCandidates)
      ..addAll(otherCandidates);
    entries.shuffle(Random());
    return entries;
  }

  bool _torboxFileLooksLikeVideo(TorboxFile file) {
    if (file.zipped) return false;
    final name = file.shortName.isNotEmpty
        ? file.shortName
        : FileUtils.getFileName(file.name);
    if (FileUtils.isVideoFile(name)) return true;
    final mime = file.mimetype?.toLowerCase();
    return mime != null && mime.startsWith('video/');
  }

  String _torboxDisplayName(TorboxFile file) {
    if (file.shortName.isNotEmpty) {
      return file.shortName;
    }
    if (file.name.isNotEmpty) {
      return FileUtils.getFileName(file.name);
    }
    return 'File ${file.id}';
  }

  String _formatTorboxSeriesTitle(SeriesInfo info, String fallback) {
    final season = info.season?.toString().padLeft(2, '0');
    final episode = info.episode?.toString().padLeft(2, '0');
    final descriptor = info.episodeTitle?.trim().isNotEmpty == true
        ? info.episodeTitle!.trim()
        : (info.title?.trim().isNotEmpty == true ? info.title!.trim() : fallback);
    if (season != null && episode != null) {
      return 'S${season}E${episode} · $descriptor';
    }
    return fallback;
  }

  String _normalizeInfohash(String hash) {
    return hash.trim().toLowerCase();
  }

  void _showSnack(String message, {Color color = Colors.blueGrey}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  int? _asIntMapValue(dynamic data, String key) {
    if (data is Map<String, dynamic>) {
      final value = data[key];
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is num) return value.toInt();
    }
    return null;
  }

  String _formatTorboxError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  // ===================== Prefetcher =====================

  void _startPrefetch() {
    if (_prefetchRunning || _activeApiKey == null || _activeApiKey!.isEmpty) {
      return;
    }
    _prefetchRunning = true;
    _prefetchStopRequested = false;
    debugPrint('MagicTV: Prefetch started.');
    _prefetchTask = _runPrefetchLoop();
  }

  Future<void> _stopPrefetch() async {
    if (!_prefetchRunning) return;
    _prefetchStopRequested = true;
    try {
      await _prefetchTask;
    } catch (_) {}
    _prefetchRunning = false;
    _prefetchTask = null;
    _inflightInfohashes.clear();
    debugPrint('MagicTV: Prefetch stopped.');
  }

  Future<void> _runPrefetchLoop() async {
    while (mounted && !_prefetchStopRequested) {
      try {
        final prepared = _countPreparedInLookahead();
        if (prepared >= _minPrepared) {
          await Future.delayed(const Duration(milliseconds: 750));
          continue;
        }

        // Find first unprepared torrent within lookahead window and prefetch it
        final idx = _findUnpreparedTorrentIndexInLookahead();
        if (idx == -1) {
          // nothing to prefetch near head; small idle
          await Future.delayed(const Duration(milliseconds: 750));
          continue;
        }

        await _prefetchOneAtIndex(idx);
        // brief yield (faster when under target prepared)
        await Future.delayed(Duration(milliseconds: prepared <= 2 ? 75 : 150));
      } catch (e) {
        debugPrint('MagicTV: Prefetch loop error: $e');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  int _countPreparedInLookahead() {
    final end = _queue.length < _lookaheadWindow ? _queue.length : _lookaheadWindow;
    int count = 0;
    for (int i = 0; i < end; i++) {
      final item = _queue[i];
      if (item is Map && item['type'] == 'rd_restricted') {
        count++;
      }
    }
    return count;
  }

  int _findUnpreparedTorrentIndexInLookahead() {
    final end = _queue.length < _lookaheadWindow ? _queue.length : _lookaheadWindow;
    for (int i = 0; i < end; i++) {
      final item = _queue[i];
      if (item is Torrent && !_inflightInfohashes.contains(item.infohash)) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _prefetchOneAtIndex(int idx) async {
    if (_activeApiKey == null || _activeApiKey!.isEmpty) return;
    if (idx < 0 || idx >= _queue.length) return;
    final item = _queue[idx];
    if (item is! Torrent) return;
    final infohash = item.infohash;
    _inflightInfohashes.add(infohash);
    debugPrint('MagicTV: Prefetching torrent at idx=$idx name="${item.name}"');
    try {
      final magnetLink = 'magnet:?xt=urn:btih:$infohash';
      final result = await DebridService.addTorrentToDebridPreferVideos(_activeApiKey!, magnetLink);
      final String torrentId = result['torrentId'] as String? ?? '';
      final List<dynamic> rdLinks = (result['links'] as List<dynamic>? ?? const []);

      if (rdLinks.isEmpty) {
        // Nothing ready; move to tail to retry later
        if (idx < _queue.length && identical(_queue[idx], item)) {
          _queue.removeAt(idx);
          _queue.add(item);
        }
        debugPrint('MagicTV: Prefetch: no links; moved torrent to tail idx=$idx');
        return;
      }

      // Convert this queue slot to rd_restricted using first link
      final headLinkCandidates = rdLinks
          .map((link) => link?.toString() ?? '')
          .where((link) => link.isNotEmpty && !_seenRestrictedLinks.contains(link))
          .toList();
      if (headLinkCandidates.isEmpty) {
        if (idx < _queue.length && identical(_queue[idx], item)) {
          _queue.removeAt(idx);
          _queue.add(item);
        }
        return;
      }

      headLinkCandidates.shuffle(Random());
      final headLink = headLinkCandidates.removeAt(0);
      _seenRestrictedLinks.add(headLink);
      _seenLinkWithTorrentId.add('$torrentId|$headLink');

      if (idx < _queue.length && identical(_queue[idx], item)) {
        _queue[idx] = {
          'type': 'rd_restricted',
          'restrictedLink': headLink,
          'torrentId': torrentId,
          'displayName': item.name,
        };
      }

      if (headLinkCandidates.isNotEmpty) {
        _queue.add(item);
      }
    } catch (e) {
      // On failure, move to tail for retry later
      if (idx < _queue.length && identical(_queue[idx], item)) {
        _queue.removeAt(idx);
        _queue.add(item);
      }
      debugPrint('MagicTV: Prefetch failed for $infohash: $e (moved to tail)');
    } finally {
      _inflightInfohashes.remove(infohash);
    }
  }
}

class _TorboxPreparedTorrent {
  final String streamUrl;
  final String title;
  final bool hasMore;

  _TorboxPreparedTorrent({
    required this.streamUrl,
    required this.title,
    required this.hasMore,
  });
}

class _TorboxPlayableEntry {
  final TorboxFile file;
  final String title;
  final SeriesInfo info;

  _TorboxPlayableEntry({
    required this.file,
    required this.title,
    required this.info,
  });
}

class _KeywordWarmResult {
  final String keyword;
  final Set<String> addedHashes;
  final KeywordStat stat;
  final String? failureMessage;

  const _KeywordWarmResult({
    required this.keyword,
    required this.addedHashes,
    required this.stat,
    this.failureMessage,
  });
}

class _CachedLoadingDialog extends StatefulWidget {
  final void Function(BuildContext context) onReady;

  const _CachedLoadingDialog({
    required this.onReady,
  });

  @override
  State<_CachedLoadingDialog> createState() => _CachedLoadingDialogState();
}

class _CachedLoadingDialogState extends State<_CachedLoadingDialog> {
  bool _notified = false;
  Timer? _hintTimer;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) {
        setState(() {
          _showHint = true;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_notified) {
      _notified = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onReady(context);
        }
      });
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF1B1B1F), Color(0xFF101014)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _GradientSpinner(),
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: _showHint
                  ? const Text(
                      'Rare keywords can take a little longer.',
                      key: ValueKey('hint'),
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    )
                  : const SizedBox(height: 0, key: ValueKey('no_hint')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelCreationDialog extends StatelessWidget {
  final String channelName;
  final void Function(BuildContext context) onReady;

  const _ChannelCreationDialog({
    required this.channelName,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onReady(context);
    });
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF1B1B1F), Color(0xFF101014)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _GradientSpinner(),
            const SizedBox(height: 18),
            Text(
              'Building "${channelName}"',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const SizedBox(
              width: 240,
              child: Text(
                'Fetching torrents and getting everything ready. Hang tight!',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientSpinner extends StatefulWidget {
  @override
  State<_GradientSpinner> createState() => _GradientSpinnerState();
}

class _GradientSpinnerState extends State<_GradientSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.rotate(
            angle: _controller.value * 6.28318,
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const SweepGradient(
              colors: [
                Color(0x00FFFFFF),
                Color(0xFFE50914),
                Color(0xFFB71C1C),
                Color(0x00FFFFFF),
              ],
              stops: [0.15, 0.45, 0.85, 1.0],
            ),
          ),
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.play_arrow_rounded,
                    color: Colors.white70, size: 22),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoTile({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12, width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsTile extends StatelessWidget {
  final int queue;
  final DateTime? lastSearchedAt;
  const _StatsTile({required this.queue, required this.lastSearchedAt});
  @override
  Widget build(BuildContext context) {
    final last = lastSearchedAt == null ? '—' : '${lastSearchedAt!.hour.toString().padLeft(2,'0')}:${lastSearchedAt!.minute.toString().padLeft(2,'0')}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.insights_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Search snapshot', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Queue prepared: $queue • Last search: $last', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RandomStartSlider extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onChangeEnd;

  const _RandomStartSlider({
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: Colors.white70,
      fontWeight: FontWeight.w600,
    );
    final helperStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white60,
    );
    final divisions =
        (_randomStartPercentMax - _randomStartPercentMin) ~/ 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Random start within first $value%',
          style: textStyle,
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackShape: const RoundedRectSliderTrackShape(),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: Slider(
            value: value.toDouble(),
            min: _randomStartPercentMin.toDouble(),
            max: _randomStartPercentMax.toDouble(),
            divisions: divisions == 0 ? null : divisions,
            label: '$value%',
            onChanged: (raw) {
              final next = _clampRandomStartPercent(raw.round());
              onChanged(next);
            },
            onChangeEnd: onChangeEnd == null
                ? null
                : (raw) => onChangeEnd!(
                      _clampRandomStartPercent(raw.round()),
                    ),
          ),
        ),
        Text(
          'Videos will jump to a random moment inside the first $value% of playback.',
          style: helperStyle,
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFFE50914),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      ),
    );
  }
}

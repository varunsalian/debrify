import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';

import '../models/torrent.dart';
import '../models/debrify_tv_cache.dart';
import '../models/torbox_file.dart';
import '../models/torbox_torrent.dart';
import '../models/debrify_tv_channel_record.dart';
import '../services/android_native_downloader.dart';
import '../services/android_tv_player_bridge.dart';
import '../services/debrid_service.dart';
import '../services/pikpak_tv_service.dart';
import '../services/storage_service.dart';
import '../services/debrify_tv_cache_service.dart';
import '../services/debrify_tv_repository.dart';
import '../services/torbox_service.dart';
import '../services/torrent_service.dart';
import '../services/engine/engine_registry.dart';
import '../services/engine/dynamic_engine.dart';
import '../services/engine/settings_manager.dart';
import '../services/debrify_tv_zip_importer.dart';
import '../services/community/magnet_yaml_service.dart';
import '../services/community/community_channel_model.dart';
import '../services/community/community_channels_service.dart';
import '../services/main_page_bridge.dart';
import '../utils/file_utils.dart';
import '../utils/series_parser.dart';
import '../utils/nsfw_filter.dart';
import 'video_player_screen.dart';
import '../main.dart';

const int _randomStartPercentDefault = 20;
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

enum _SettingsScope { quickPlay, channels }

enum _ImportChannelsMode { device, url, community }

enum _ChannelImportOrigin { device, url }

enum _ChannelImportType { zip, yaml, text, debrify }

String _formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  final exponent = min(units.length - 1, (log(bytes) / log(1024)).floor());
  final value = bytes / pow(1024, exponent);
  final formatted = value >= 10
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$formatted ${units[exponent]}';
}

Future<DebrifyTvZipImportResult> _parseZipInBackground(Uint8List bytes) {
  return compute(_parseZipCompute, bytes);
}

DebrifyTvZipImportResult _parseZipCompute(Uint8List bytes) {
  return DebrifyTvZipImporter.parseZip(bytes);
}

Future<DebrifyTvZipImportedChannel> _parseYamlInBackground(
  String sourceName,
  String content,
) {
  return compute(_parseYamlCompute, <String, String>{
    'sourceName': sourceName,
    'content': content,
  });
}

DebrifyTvZipImportedChannel _parseYamlCompute(Map<String, String> payload) {
  final sourceName = payload['sourceName'] ?? 'channel.yaml';
  final content = payload['content'] ?? '';
  return DebrifyTvZipImporter.parseYaml(
    sourceName: sourceName,
    content: content,
  );
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
  final bool avoidNsfw; // Per-channel NSFW filter setting
  final int channelNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  const _DebrifyTvChannel({
    required this.id,
    required this.name,
    required this.keywords,
    required this.avoidNsfw,
    required this.channelNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  factory _DebrifyTvChannel.fromJson(Map<String, dynamic> json) {
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
      avoidNsfw: json['avoidNsfw'] is bool
          ? json['avoidNsfw'] as bool
          : true, // Default to enabled for backward compatibility
      channelNumber: json['channelNumber'] is int
          ? (json['channelNumber'] as int)
          : 0,
      createdAt: json['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int)
          : DateTime.now(),
      updatedAt: json['updatedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)
          : DateTime.now(),
    );
  }

  factory _DebrifyTvChannel.fromRecord(DebrifyTvChannelRecord record) {
    return _DebrifyTvChannel(
      id: record.channelId,
      name: record.name,
      keywords: record.keywords,
      avoidNsfw: record.avoidNsfw,
      channelNumber: record.channelNumber,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'keywords': keywords,
      'avoidNsfw': avoidNsfw,
      'channelNumber': channelNumber,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  _DebrifyTvChannel copyWith({
    String? id,
    String? name,
    List<String>? keywords,
    bool? avoidNsfw,
    int? channelNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return _DebrifyTvChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      keywords: keywords ?? this.keywords,
      avoidNsfw: avoidNsfw ?? this.avoidNsfw,
      channelNumber: channelNumber ?? this.channelNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  DebrifyTvChannelRecord toRecord() {
    return DebrifyTvChannelRecord(
      channelId: id,
      name: name,
      keywords: keywords,
      avoidNsfw: avoidNsfw,
      channelNumber: channelNumber,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class _DebrifyTVScreenState extends State<DebrifyTVScreen> {
  static const String _providerRealDebrid = 'real_debrid';
  static const String _providerTorbox = 'torbox';
  static const String _providerPikPak = 'pikpak';
  static const String _torboxFileEntryType = 'torbox_file';
  static const int _torboxMinVideoSizeBytes =
      50 * 1024 * 1024; // 50 MB filter threshold

  final SettingsManager _settingsManager = SettingsManager();
  final TextEditingController _keywordsController = TextEditingController();
  // Mixed queue: can contain Torrent items or RD-restricted link maps
  final List<dynamic> _queue = [];
  bool _isBusy = false;
  String _status = '';
  List<_DebrifyTvChannel> _channels = <_DebrifyTvChannel>[];
  final Map<String, DebrifyTvChannelCacheEntry> _channelCache = {};
  // These are now loaded from settings dynamically
  int _channelTorrentsCsvMaxResultsSmall = 100;
  int _channelTorrentsCsvMaxResultsLarge = 25;
  int _channelSolidTorrentsMaxResultsSmall = 100;
  int _channelSolidTorrentsMaxResultsLarge = 100;
  int _channelPirateBayMaxResultsSmall = 100;
  int _channelPirateBayMaxResultsLarge = 100;
  int _channelYtsMaxResultsSmall = 50;
  int _channelYtsMaxResultsLarge = 50;
  int _channelCsvParallelism = 4;
  int _keywordThreshold = 10;
  int _minTorrentsPerKeyword = 5;

  // Engine toggles
  bool _useTorrentsCsv = true;
  bool _usePirateBay = true;
  bool _useYts = false;
  bool _useSolidTorrents = false;

  // Quick Play limits
  int _quickPlayTorrentsCsvMax = 500;
  int _quickPlaySolidTorrentsMax = 200;
  int _quickPlayPirateBayMax = 100;
  int _quickPlayYtsMax = 50;
  int _quickPlayMaxKeywords = 5;

  static const int _playbackTorrentThreshold = 1000;
  static const int _maxTorrentsPerKeywordPlayback = 25;
  static const int _minimumTorrentsForChannel = 5;
  static const int _maxChannelKeywords = 1000;
  static const int _keywordWarmEstimateMs = 1000;
  final TextEditingController _channelSearchController =
      TextEditingController();
  String _channelSearchTerm = '';
  String?
  _currentWatchingChannelId; // Track currently playing channel for switching

  // Advanced options
  bool _startRandom = true;
  int _randomStartPercent = _randomStartPercentDefault;
  bool _hideSeekbar = true;
  bool _showChannelName = true;
  bool _showVideoTitle = true;
  bool _hideOptions = false;
  bool _hideBackButton = false;
  String _provider = _providerRealDebrid;

  // Quick play options
  bool _quickStartRandom = true;
  int _quickRandomStartPercent = _randomStartPercentDefault;
  bool _quickHideSeekbar = true;
  bool _quickShowChannelName = true;
  bool _quickShowVideoTitle = true;
  bool _quickHideOptions = false;
  bool _quickHideBackButton = false;
  bool _quickAvoidNsfw = true;
  String _quickProvider = _providerRealDebrid;

  bool _rdAvailable = false;
  bool _torboxAvailable = false;
  bool _pikpakAvailable = false;
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
  bool _isAndroidTv = false;
  bool _showSearchBar = false;
  late final FocusNode _channelSearchFocusNode;

  // Progress UI state
  final ValueNotifier<List<String>> _progress = ValueNotifier<List<String>>([]);
  BuildContext? _progressSheetContext;
  bool _progressOpen = false;
  int _lastQueueSize = 0;
  DateTime? _lastSearchAt;
  bool _launchedPlayer = false;
  bool _watchCancelled = false;
  int? _originalMaxCap;

  @override
  void initState() {
    super.initState();
    _channelSearchFocusNode = FocusNode(
      debugLabel: 'DebrifyTVChannelSearch',
      onKeyEvent: _handleChannelSearchKeyEvent,
    );
    _loadSettings();
    _loadChannels();

    // Check if this is a startup auto-launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkStartupAutoLaunch();
    });
  }

  @override
  void dispose() {
    // Ensure prefetch loop is stopped if this screen is disposed mid-run
    _prefetchStopRequested = true;
    _stopPrefetch();
    _progress.dispose();
    _keywordsController.dispose();
    _channelSearchController.dispose();
    _channelSearchFocusNode.dispose();
    AndroidTvPlayerBridge.clearTorboxProvider();
    super.dispose();
  }

  KeyEventResult _handleChannelSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (!_isAndroidTv) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      final ctx = node.context;
      if (ctx != null) {
        FocusScope.of(ctx).nextFocus();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      final ctx = node.context;
      if (ctx != null) {
        FocusScope.of(ctx).previousFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Check if there's a startup channel to auto-launch
  Future<void> _checkStartupAutoLaunch() async {
    try {
      debugPrint('🚀 [AUTO-LAUNCH] Starting check...');

      // Check if there's a startup channel to launch
      final startupChannelId = MainPage.getStartupChannelId();
      debugPrint('🚀 [AUTO-LAUNCH] Channel ID: $startupChannelId');

      if (startupChannelId == null) {
        debugPrint('🚀 [AUTO-LAUNCH] No channel configured, skipping');
        return;
      }

      // Wait for channels to be loaded with a timeout
      debugPrint('DebrifyTVScreen: Waiting for channels to load...');
      int attempts = 0;
      const maxAttempts = 50; // 5 seconds max wait (50 * 100ms)

      while (_channels.isEmpty && attempts < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
        if (!mounted) {
          debugPrint(
            'DebrifyTVScreen: Widget unmounted while waiting for channels',
          );
          return;
        }
      }

      if (_channels.isEmpty) {
        debugPrint(
          'DebrifyTVScreen: Channels list is still empty after waiting',
        );
        MainPageBridge.notifyAutoLaunchFailed('Channels not loaded');
        return;
      }

      debugPrint(
        'DebrifyTVScreen: Channels loaded (${_channels.length} channels)',
      );

      // Find the channel in the loaded channels list
      final channel = _channels.firstWhereOrNull(
        (c) => c.id == startupChannelId,
      );

      if (channel == null) {
        debugPrint(
          'DebrifyTVScreen: Channel with ID $startupChannelId not found in ${_channels.length} channels',
        );
        debugPrint(
          'DebrifyTVScreen: Available channel IDs: ${_channels.map((c) => c.id).join(", ")}',
        );
        MainPageBridge.notifyAutoLaunchFailed('Startup channel not found');
        return;
      }

      debugPrint('🚀 [AUTO-LAUNCH] Found channel: ${channel.name}');
      debugPrint(
        '🚀 [AUTO-LAUNCH] Keywords: ${channel.keywords.length}, isAndroidTv: $_isAndroidTv',
      );

      // Small delay to ensure UI is ready
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) {
        debugPrint('🚀 [AUTO-LAUNCH] Widget unmounted, aborting');
        return;
      }

      debugPrint('🚀 [AUTO-LAUNCH] Calling _watchChannel()...');

      // Call the existing watch channel method
      _watchChannel(channel);
    } catch (e, stackTrace) {
      debugPrint('DebrifyTVScreen: Failed to auto-play startup channel: $e');
      debugPrint('DebrifyTVScreen: Stack trace: $stackTrace');
      MainPageBridge.notifyAutoLaunchFailed('Auto-launch exception: $e');
      // Silently fail - user can manually select a channel
    }
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

  void _updateProgress(Iterable<String> messages, {bool replace = false}) {
    final sanitized = messages
        .map((message) => message.trim())
        .where((message) => message.isNotEmpty)
        .toList();
    if (sanitized.isEmpty) {
      return;
    }

    if (replace || _progress.value.isEmpty) {
      _progress.value = sanitized;
      return;
    }

    final copy = List<String>.from(_progress.value)..addAll(sanitized);
    _progress.value = copy;
  }

  void _cancelActiveWatch({
    BuildContext? dialogContext,
    bool clearQueue = true,
  }) {
    if (_watchCancelled) {
      if (dialogContext != null) {
        try {
          Navigator.of(dialogContext).pop();
        } catch (_) {}
      }
      return;
    }
    _watchCancelled = true;
    _prefetchStopRequested = true;
    unawaited(_stopPrefetch());
    if (clearQueue) {
      _queue.clear();
    }
    _progress.value = [];
    if (dialogContext != null) {
      try {
        Navigator.of(dialogContext).pop();
      } catch (_) {}
      _progressOpen = false;
      _progressSheetContext = null;
    } else if (_progressOpen) {
      _closeProgressDialog();
    }
    if (mounted) {
      setState(() {
        _isBusy = false;
        _status = '';
      });
    }
  }

  String _determineDefaultProvider(
    String? preferred,
    bool rdAvailable,
    bool torboxAvailable,
    bool pikpakAvailable,
  ) {
    // If user has a preferred provider that's available, use it
    if (preferred == _providerPikPak && pikpakAvailable) {
      return _providerPikPak;
    }
    if (preferred == _providerTorbox && torboxAvailable) {
      return _providerTorbox;
    }
    if (preferred == _providerRealDebrid && rdAvailable) {
      return _providerRealDebrid;
    }

    // Fallback: pick first available provider
    if (rdAvailable) {
      return _providerRealDebrid;
    }
    if (torboxAvailable) {
      return _providerTorbox;
    }
    if (pikpakAvailable) {
      return _providerPikPak;
    }

    // No provider available, default to RD (will show as unavailable)
    return _providerRealDebrid;
  }

  bool _isProviderSelectable(String provider) {
    if (provider == _providerTorbox) {
      return _torboxAvailable;
    }
    if (provider == _providerPikPak) {
      return _pikpakAvailable;
    }
    return _rdAvailable;
  }

  Future<void> _loadSettings() async {
    final startRandom = await StorageService.getDebrifyTvStartRandom();
    final randomStartPercent =
        await StorageService.getDebrifyTvRandomStartPercent();
    // Hardcoded to false - no longer loading from storage
    const hideOptions = false;
    final showChannelName = await StorageService.getDebrifyTvShowChannelName();
    final showVideoTitle = await StorageService.getDebrifyTvShowVideoTitle();
    // hideBackButton is hardcoded to false - no longer loading from storage
    final avoidNsfw = await _settingsManager.getGlobalAvoidNsfw(true);
    final storedProvider = await StorageService.getDebrifyTvProvider();
    final hasStoredProvider = await StorageService.hasDebrifyTvProvider();
    final rdIntegrationEnabled =
        await StorageService.getRealDebridIntegrationEnabled();
    final rdKey = await StorageService.getApiKey();
    final torboxIntegrationEnabled =
        await StorageService.getTorboxIntegrationEnabled();
    final torboxKey = await StorageService.getTorboxApiKey();

    // Load Debrify TV search settings via SettingsManager
    // Engine enabled states (TV mode)
    final useTorrentsCsv = await _settingsManager.getTvEnabled(
      'torrents_csv',
      true,
    );
    final usePirateBay = await _settingsManager.getTvEnabled(
      'pirate_bay',
      true,
    );
    final useYts = await _settingsManager.getTvEnabled('yts', false);
    final useSolidTorrents = await _settingsManager.getTvEnabled(
      'solid_torrents',
      false,
    );

    // Small channel limits per engine
    final channelSmallTorrentsCsvMax = await _settingsManager
        .getTvSmallChannelMax('torrents_csv', 100);
    final channelSmallSolidTorrentsMax = await _settingsManager
        .getTvSmallChannelMax('solid_torrents', 100);
    final channelSmallPirateBayMax = await _settingsManager
        .getTvSmallChannelMax('pirate_bay', 100);
    final channelSmallYtsMax = await _settingsManager.getTvSmallChannelMax(
      'yts',
      50,
    );

    // Large channel limits per engine
    final channelLargeTorrentsCsvMax = await _settingsManager
        .getTvLargeChannelMax('torrents_csv', 25);
    final channelLargeSolidTorrentsMax = await _settingsManager
        .getTvLargeChannelMax('solid_torrents', 100);
    final channelLargePirateBayMax = await _settingsManager
        .getTvLargeChannelMax('pirate_bay', 100);
    final channelLargeYtsMax = await _settingsManager.getTvLargeChannelMax(
      'yts',
      50,
    );

    // Quick play limits per engine
    final quickPlayTorrentsCsvMax = await _settingsManager.getTvQuickPlayMax(
      'torrents_csv',
      500,
    );
    final quickPlaySolidTorrentsMax = await _settingsManager.getTvQuickPlayMax(
      'solid_torrents',
      200,
    );
    final quickPlayPirateBayMax = await _settingsManager.getTvQuickPlayMax(
      'pirate_bay',
      100,
    );
    final quickPlayYtsMax = await _settingsManager.getTvQuickPlayMax('yts', 50);

    // Global TV settings
    final channelBatchSize = await _settingsManager.getGlobalBatchSize(4);
    final keywordThreshold = await _settingsManager.getGlobalKeywordThreshold(
      10,
    );
    final minTorrentsPerKeyword = await _settingsManager
        .getGlobalMinTorrentsPerKeyword(5);
    final quickPlayMaxKeywords = await _settingsManager.getGlobalMaxKeywords(5);

    final rdAvailable =
        rdIntegrationEnabled && rdKey != null && rdKey.isNotEmpty;
    final torboxAvailable =
        torboxIntegrationEnabled && torboxKey != null && torboxKey.isNotEmpty;
    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    final defaultProvider = _determineDefaultProvider(
      hasStoredProvider ? storedProvider : null,
      rdAvailable,
      torboxAvailable,
      pikpakAvailable,
    );
    final isTv = await AndroidNativeDownloader.isTelevision();

    if (mounted) {
      setState(() {
        _startRandom = startRandom;
        _randomStartPercent = _clampRandomStartPercent(randomStartPercent);
        _hideSeekbar = hideOptions;
        _showChannelName = showChannelName;
        _showVideoTitle = showVideoTitle;
        _hideOptions = false; // Hardcoded to false
        _hideBackButton = false; // Hardcoded to false
        _rdAvailable = rdAvailable;
        _torboxAvailable = torboxAvailable;
        _pikpakAvailable = pikpakAvailable;
        _provider = defaultProvider;
        _isAndroidTv = isTv;

        _quickStartRandom = startRandom;
        _quickRandomStartPercent = _clampRandomStartPercent(randomStartPercent);
        _quickHideSeekbar = hideOptions;
        _quickShowChannelName = showChannelName;
        _quickShowVideoTitle = showVideoTitle;
        _quickHideOptions = false; // Hardcoded to false
        _quickHideBackButton = false; // Hardcoded to false
        _quickAvoidNsfw = avoidNsfw;
        _quickProvider = defaultProvider;

        // Update search settings
        _useTorrentsCsv = useTorrentsCsv;
        _usePirateBay = usePirateBay;
        _useYts = useYts;
        _useSolidTorrents = useSolidTorrents;
        _channelTorrentsCsvMaxResultsSmall = channelSmallTorrentsCsvMax;
        _channelTorrentsCsvMaxResultsLarge = channelLargeTorrentsCsvMax;
        _channelSolidTorrentsMaxResultsSmall = channelSmallSolidTorrentsMax;
        _channelSolidTorrentsMaxResultsLarge = channelLargeSolidTorrentsMax;
        _channelPirateBayMaxResultsSmall = channelSmallPirateBayMax;
        _channelPirateBayMaxResultsLarge = channelLargePirateBayMax;
        _channelYtsMaxResultsSmall = channelSmallYtsMax;
        _channelYtsMaxResultsLarge = channelLargeYtsMax;
        _channelCsvParallelism = channelBatchSize;
        _keywordThreshold = keywordThreshold;
        _minTorrentsPerKeyword = minTorrentsPerKeyword;
        _quickPlayTorrentsCsvMax = quickPlayTorrentsCsvMax;
        _quickPlaySolidTorrentsMax = quickPlaySolidTorrentsMax;
        _quickPlayPirateBayMax = quickPlayPirateBayMax;
        _quickPlayYtsMax = quickPlayYtsMax;
        _quickPlayMaxKeywords = quickPlayMaxKeywords;
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
    final records = await DebrifyTvRepository.instance.fetchAllChannels();
    if (!mounted) return;
    setState(() {
      _channels = records
          .map(_DebrifyTvChannel.fromRecord)
          .toList(growable: false);
    });
  }

  Future<DebrifyTvChannelCacheEntry> _computeChannelCacheEntry(
    _DebrifyTvChannel channel,
    List<String> normalizedKeywords, {
    DebrifyTvChannelCacheEntry? baseline,
    Set<String>? keywordsToSearch,
  }) async {
    // Use channel's own NSFW setting
    final channelAvoidNsfw = channel.avoidNsfw;
    final registry = EngineRegistry.instance;
    await registry.initialize();

    // Get dynamic engines from registry
    final csvEngine = registry.getEngine('torrents_csv');
    final pirateEngine = registry.getEngine('pirate_bay');
    final solidEngine = registry.getEngine('solid_torrents');
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
    final solidFutures = <String, Future<List<Torrent>>>{};

    final bool usePirate = _usePirateBay && pirateEngine != null;
    final bool useSolid = _useSolidTorrents && solidEngine != null;
    final int solidMaxResults = normalizedKeywords.length < _keywordThreshold
        ? _channelSolidTorrentsMaxResultsSmall
        : _channelSolidTorrentsMaxResultsLarge;

    for (final keyword in keywordsToWarm) {
      if (usePirate) {
        pirateFutures[keyword] = pirateEngine!.search(keyword);
      }
      if (useSolid) {
        solidFutures[keyword] = solidEngine!.executeSearch(
          query: keyword,
          maxResults: solidMaxResults,
        );
      }
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
          useTorrentsCsv: _useTorrentsCsv && csvEngine != null,
          csvEngine: csvEngine,
          pirateFuture: pirateFutures[keyword],
          solidFuture: solidFutures[keyword],
          accumulator: accumulator,
          stats: stats,
          now: now,
          totalKeywords: normalizedKeywords.length,
          avoidNsfw: channelAvoidNsfw, // Use channel's NSFW setting
          minTorrentsPerKeyword: _minTorrentsPerKeyword,
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
    required bool useTorrentsCsv,
    required DynamicEngine? csvEngine,
    required Future<List<Torrent>>? pirateFuture,
    required Future<List<Torrent>>? solidFuture,
    required Map<String, CachedTorrent> accumulator,
    required Map<String, KeywordStat> stats,
    required int now,
    required int totalKeywords,
    required bool avoidNsfw, // Use channel's NSFW setting
    required int minTorrentsPerKeyword,
  }) async {
    String? csvFailure;
    List<Torrent> csvTorrentsResult = const <Torrent>[];
    int pagesPulled = 0;
    if (useTorrentsCsv && csvEngine != null) {
      try {
        final maxResults = totalKeywords < _keywordThreshold
            ? _channelTorrentsCsvMaxResultsSmall
            : _channelTorrentsCsvMaxResultsLarge;
        csvTorrentsResult = await csvEngine.executeSearch(
          query: keyword,
          maxResults: maxResults,
        );
        // Estimate pages pulled based on results and page size (25 per page for torrents_csv)
        pagesPulled = (csvTorrentsResult.length + 24) ~/ 25;
      } catch (e) {
        debugPrint(
          'DebrifyTV: Cache warm Torrents CSV failed for "$keyword": $e',
        );
        csvTorrentsResult = const <Torrent>[];
        csvFailure =
            'Torrents CSV is unavailable right now. Please try again later.';
      }
    }

    List<Torrent> pirateResult = const <Torrent>[];
    String? pirateFailure;
    try {
      if (pirateFuture != null) {
        pirateResult = await pirateFuture;
      }
    } catch (e) {
      debugPrint('DebrifyTV: Cache warm Pirate Bay failed for "$keyword": $e');
      pirateFailure =
          'The Pirate Bay search failed. Some torrents may be missing.';
    }

    List<Torrent> solidResult = const <Torrent>[];
    String? solidFailure;
    try {
      if (solidFuture != null) {
        solidResult = await solidFuture;
      }
    } catch (e) {
      debugPrint(
        'DebrifyTV: Cache warm SolidTorrents failed for "$keyword": $e',
      );
      solidFailure =
          'SolidTorrents search failed. Some torrents may be missing.';
    }

    // Apply NSFW filter to search results before caching
    List<Torrent> csvTorrents = List<Torrent>.from(csvTorrentsResult);
    List<Torrent> pirateTorrents = pirateResult;
    List<Torrent> solidTorrents = solidResult;

    if (avoidNsfw) {
      final csvBefore = csvTorrents.length;
      csvTorrents = csvTorrents.where((torrent) {
        if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
          return false;
        }
        return true;
      }).toList();

      final pirateBefore = pirateTorrents.length;
      pirateTorrents = pirateTorrents.where((torrent) {
        if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
          return false;
        }
        return true;
      }).toList();

      final solidBefore = solidTorrents.length;
      solidTorrents = solidTorrents.where((torrent) {
        if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
          return false;
        }
        return true;
      }).toList();

      final totalBefore = csvBefore + pirateBefore + solidBefore;
      final totalAfter =
          csvTorrents.length + pirateTorrents.length + solidTorrents.length;
      if (totalBefore != totalAfter) {
        debugPrint(
          'DebrifyTV: Cache NSFW filter for "$keyword": $totalBefore → $totalAfter torrents',
        );
      }
    }

    // Check minimum torrents per keyword threshold
    final totalTorrents =
        csvTorrents.length + pirateTorrents.length + solidTorrents.length;
    if (totalTorrents < minTorrentsPerKeyword) {
      debugPrint(
        'DebrifyTV: Skipping keyword "$keyword" – only $totalTorrents torrent(s), minimum is $minTorrentsPerKeyword',
      );
      final stat = (stats[keyword] ?? KeywordStat.initial()).copyWith(
        totalFetched: 0,
        lastSearchedAt: now,
        pagesPulled: pagesPulled,
        pirateBayHits: pirateResult.length,
      );
      return _KeywordWarmResult(
        keyword: keyword,
        addedHashes: const <String>{},
        stat: stat,
        failureMessage:
            'Too few torrents for "$keyword" (found $totalTorrents, need $minTorrentsPerKeyword)',
      );
    }

    final keywordHashes = <String>{};

    for (final torrent in csvTorrents) {
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

    for (final torrent in pirateTorrents) {
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

    for (final torrent in solidTorrents) {
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
        source: 'solid_torrents',
      );
    }

    final updatedStats = stats[keyword] ?? KeywordStat.initial();
    final stat = updatedStats.copyWith(
      totalFetched: keywordHashes.length,
      lastSearchedAt: now,
      pagesPulled: pagesPulled,
      pirateBayHits: pirateResult.length,
    );

    String? failureMessage;
    if (csvFailure != null) {
      failureMessage = csvFailure;
    } else if (pirateFailure != null) {
      failureMessage = pirateFailure;
    } else if (solidFailure != null) {
      failureMessage = solidFailure;
    } else if (csvTorrentsResult.isEmpty &&
        pirateResult.isEmpty &&
        solidResult.isEmpty) {
      failureMessage = 'No torrents found for "$keyword" yet.';
    }

    return _KeywordWarmResult(
      keyword: keyword,
      addedHashes: keywordHashes,
      stat: stat,
      failureMessage: failureMessage,
    );
  }

  Future<void> _deleteChannel(String id) async {
    setState(() {
      _channels = _channels.where((c) => c.id != id).toList();
    });
    await DebrifyTvRepository.instance.deleteChannel(id);
    setState(() {
      _channelCache.remove(id);
    });
  }

  Future<void> _syncProviderAvailability() async {
    final rdIntegrationEnabled =
        await StorageService.getRealDebridIntegrationEnabled();
    final rdKey = await StorageService.getApiKey();
    final torboxIntegrationEnabled =
        await StorageService.getTorboxIntegrationEnabled();
    final torboxKey = await StorageService.getTorboxApiKey();
    final pikpakAvailable = await PikPakTvService.instance.isAvailable();

    final rdAvailable =
        rdIntegrationEnabled && rdKey != null && rdKey.isNotEmpty;
    final torboxAvailable =
        torboxIntegrationEnabled && torboxKey != null && torboxKey.isNotEmpty;

    final nextChannelProvider = _determineDefaultProvider(
      _provider,
      rdAvailable,
      torboxAvailable,
      pikpakAvailable,
    );
    final nextQuickProvider = _determineDefaultProvider(
      _quickProvider,
      rdAvailable,
      torboxAvailable,
      pikpakAvailable,
    );

    if (!mounted) return;
    final providerChanged = nextChannelProvider != _provider;
    setState(() {
      _rdAvailable = rdAvailable;
      _torboxAvailable = torboxAvailable;
      _pikpakAvailable = pikpakAvailable;
      _provider = nextChannelProvider;
      _quickProvider = nextQuickProvider;
    });

    if (providerChanged) {
      await StorageService.saveDebrifyTvProvider(nextChannelProvider);
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

  Future<DebrifyTvChannelCacheEntry?> _ensureCacheEntry(
    String channelId,
  ) async {
    final cached = _channelCache[channelId];
    if (cached != null) {
      return cached;
    }
    final fetched = await DebrifyTvCacheService.getEntry(channelId);
    if (fetched != null) {
      _channelCache[channelId] = fetched;
    }
    return fetched;
  }

  Future<List<String>> _getChannelKeywords(String channelId) async {
    final index = _channels.indexWhere((c) => c.id == channelId);
    if (index == -1) {
      return const <String>[];
    }
    final existing = _channels[index];
    if (existing.keywords.isNotEmpty) {
      return existing.keywords;
    }
    final fetched = await DebrifyTvRepository.instance.fetchChannelKeywords(
      channelId,
    );
    if (!mounted) {
      return fetched;
    }
    final updated = existing.copyWith(keywords: fetched);
    setState(() {
      final next = List<_DebrifyTvChannel>.from(_channels);
      next[index] = updated;
      _channels = next;
    });
    return fetched;
  }

  Future<_TorboxCacheWindowResult> _fetchTorboxCacheWindow({
    required List<Torrent> candidates,
    required int startIndex,
    required String apiKey,
  }) async {
    const int chunkSize = 90;
    const int maxCalls = 2;

    int cursor = startIndex;
    int calls = 0;
    final List<Torrent> hits = <Torrent>[];

    while (cursor < candidates.length && calls < maxCalls && hits.isEmpty) {
      final int end = min(cursor + chunkSize, candidates.length);
      final List<Torrent> chunk = candidates.sublist(cursor, end);
      cursor = end;

      final List<String> hashes = chunk
          .map((torrent) => _normalizeInfohash(torrent.infohash))
          .where((hash) => hash.isNotEmpty)
          .toList();

      if (hashes.isEmpty) {
        continue;
      }

      calls += 1;
      final Set<String> cachedHashes = await TorboxService.checkCachedTorrents(
        apiKey: apiKey,
        infoHashes: hashes,
        listFiles: false,
      );

      if (cachedHashes.isEmpty) {
        continue;
      }

      final Set<String> normalized = cachedHashes
          .map((hash) => hash.trim().toLowerCase())
          .where((hash) => hash.isNotEmpty)
          .toSet();

      hits.addAll(
        chunk.where(
          (torrent) =>
              normalized.contains(_normalizeInfohash(torrent.infohash)),
        ),
      );
    }

    final bool exhausted = cursor >= candidates.length;
    return _TorboxCacheWindowResult(
      cachedTorrents: hits,
      nextCursor: cursor,
      exhausted: exhausted,
    );
  }

  int _estimatedWarmDurationSeconds(
    int keywordCount, {
    int? totalKeywordUniverse,
  }) {
    if (keywordCount <= 0) {
      return 0;
    }

    final int effectiveUniverse = max(1, totalKeywordUniverse ?? keywordCount);
    final bool useExpandedCsvFetch = effectiveUniverse < _keywordThreshold;
    final int maxResultsConfig = useExpandedCsvFetch
        ? _channelTorrentsCsvMaxResultsSmall
        : _channelTorrentsCsvMaxResultsLarge;

    final int csvRequestsPerKeyword = max(
      1,
      min(20, ((maxResultsConfig + 24) ~/ 25)),
    );

    final int batches = max(
      1,
      ((keywordCount + _channelCsvParallelism - 1) ~/ _channelCsvParallelism),
    );

    final int csvRequests = batches * csvRequestsPerKeyword;
    final int csvDurationMs = csvRequests * _keywordWarmEstimateMs;

    // Pirate Bay requests run concurrently ahead of the warm loop. Keep a single
    // request's cost so we don't under-estimate tiny workloads.
    final int pirateDurationMs = _keywordWarmEstimateMs;
    final int estimatedMs = max(csvDurationMs, pirateDurationMs);

    return (estimatedMs + 999) ~/ 1000;
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
      final list = List<CachedTorrent>.from(all);
      list.shuffle(Random());
      return list;
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
    if (provider == _providerTorbox) return 'Torbox';
    if (provider == _providerPikPak) return 'PikPak';
    return 'Real Debrid';
  }

  Widget _providerChoiceChips(
    _SettingsScope scope, {
    StateSetter? dialogSetState,
  }) {
    final bool isQuickScope = scope == _SettingsScope.quickPlay;
    final String currentProvider = isQuickScope ? _quickProvider : _provider;

    void handleSelection(String value) {
      if (!_isProviderSelectable(value)) {
        return;
      }
      if (isQuickScope) {
        if (_quickProvider == value) {
          return;
        }
        setState(() {
          _quickProvider = value;
        });
        dialogSetState?.call(() {});
        return;
      }

      if (_provider == value) {
        return;
      }
      setState(() {
        _provider = value;
      });
      dialogSetState?.call(() {});
      unawaited(StorageService.saveDebrifyTvProvider(value));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Tooltip(
          message: _rdAvailable
              ? 'Use Real Debrid for Debrify TV'
              : 'Enable Real Debrid and add an API key in Settings to use this option.',
          child: ChoiceChip(
            label: const Text('Real Debrid'),
            selected: currentProvider == _providerRealDebrid,
            disabledColor: Colors.white12,
            onSelected: (!_rdAvailable || _isBusy)
                ? null
                : (selected) {
                    if (selected) {
                      handleSelection(_providerRealDebrid);
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
            selected: currentProvider == _providerTorbox,
            disabledColor: Colors.white12,
            onSelected: (!_torboxAvailable || _isBusy)
                ? null
                : (selected) {
                    if (selected) {
                      handleSelection(_providerTorbox);
                    }
                  },
          ),
        ),
        Tooltip(
          message: _pikpakAvailable
              ? 'Use PikPak for Debrify TV'
              : 'Login to PikPak in Settings to use this option.',
          child: ChoiceChip(
            label: const Text('PikPak'),
            selected: currentProvider == _providerPikPak,
            disabledColor: Colors.white12,
            onSelected: (!_pikpakAvailable || _isBusy)
                ? null
                : (selected) {
                    if (selected) {
                      handleSelection(_providerPikPak);
                    }
                  },
          ),
        ),
      ],
    );
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
    FocusNode? channelNameFocus;
    FocusNode? channelKeywordFocus;
    KeyEventResult handleNameKey(FocusNode node, KeyEvent event) {
      if (!_isAndroidTv) {
        return KeyEventResult.ignored;
      }
      if (event is! KeyDownEvent) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown) {
        channelKeywordFocus?.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        final ctx = node.context;
        if (ctx != null) {
          FocusScope.of(ctx).previousFocus();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }

    KeyEventResult handleKeywordKey(FocusNode node, KeyEvent event) {
      if (!_isAndroidTv) {
        return KeyEventResult.ignored;
      }
      if (event is! KeyDownEvent) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        channelNameFocus?.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        final ctx = node.context;
        if (ctx != null) {
          FocusScope.of(ctx).nextFocus();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }

    if (_isAndroidTv) {
      channelNameFocus = FocusNode(
        debugLabel: 'DebrifyTVChannelName',
        onKeyEvent: handleNameKey,
      );
      channelKeywordFocus = FocusNode(
        debugLabel: 'DebrifyTVChannelKeyword',
        onKeyEvent: handleKeywordKey,
      );
    }
    final List<String> keywordList = [];
    final seenKeywords = <String>{};
    final initialKeywords = existing != null
        ? existing.keywords
        : const <String>[];
    for (final kw in initialKeywords) {
      final trimmed = kw.trim();
      if (trimmed.isEmpty) continue;
      final lower = trimmed.toLowerCase();
      if (seenKeywords.contains(lower)) continue;
      seenKeywords.add(lower);
      keywordList.add(trimmed);
      if (keywordList.length >= _maxChannelKeywords) break;
    }
    // Channel defaults - keep NSFW preference per channel only
    bool avoidNsfw = existing?.avoidNsfw ?? true;
    String? error;

    _DebrifyTvChannel? result;
    try {
      result = await showDialog<_DebrifyTvChannel>(
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
                final now = DateTime.now();
                final channel = _DebrifyTvChannel(
                  id:
                      existing?.id ??
                      DateTime.now().microsecondsSinceEpoch.toString(),
                  name: name,
                  keywords: keywords,
                  avoidNsfw: avoidNsfw, // Channel's own NSFW setting
                  channelNumber: existing?.channelNumber ?? 0,
                  createdAt: existing?.createdAt ?? now,
                  updatedAt: now,
                );
                Navigator.of(dialogContext).pop(channel);
              }

              return Dialog(
                backgroundColor: const Color(0xFF0F0F0F),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 520,
                    minWidth: 320,
                  ),
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
                              existing == null
                                  ? 'Create Channel'
                                  : 'Edit Channel',
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
                          focusNode: channelNameFocus,
                          autofocus: _isAndroidTv,
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
                          style: TextStyle(color: Colors.white54, fontSize: 11),
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
                                        error!.contains(
                                          '$_maxChannelKeywords keywords',
                                        ) &&
                                        keywordList.length <
                                            _maxChannelKeywords) {
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
                                focusNode: channelKeywordFocus,
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
                                      error!.contains(
                                        '$_maxChannelKeywords keywords',
                                      )) {
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
                                        error!.contains(
                                          '$_maxChannelKeywords keywords',
                                        )) {
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
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
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
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        _SwitchRow(
                          title: 'Avoid NSFW content',
                          subtitle:
                              'Filter adult/inappropriate torrents • Best effort, not 100% accurate',
                          value: avoidNsfw,
                          onChanged: (v) {
                            setModalState(() {
                              avoidNsfw =
                                  v; // Only update local channel setting
                            });
                          },
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
    } finally {
      final disposer = () {
        channelNameFocus?.dispose();
        channelKeywordFocus?.dispose();
        nameController.dispose();
        keywordInputController.dispose();
      };

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => disposer());
      } else {
        disposer();
      }
    }

    return result;
  }

  Future<void> _handleImportChannels() async {
    if (_isBusy) {
      return;
    }

    final mode = await _selectImportMode();
    if (mode == null) {
      return;
    }

    switch (mode) {
      case _ImportChannelsMode.device:
        await _handleImportChannelsFromDevice();
        break;
      case _ImportChannelsMode.url:
        await _handleImportChannelsFromUrl();
        break;
      case _ImportChannelsMode.community:
        await _handleImportChannelsFromCommunity();
        break;
    }
  }

  Future<_ImportChannelsMode?> _selectImportMode() async {
    if (!mounted) {
      return null;
    }

    return showDialog<_ImportChannelsMode>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _ImportChannelsDialog(isAndroidTv: _isAndroidTv);
      },
    );
  }

  Future<void> _handleAddChannel() async {
    await _syncProviderAvailability();
    final channel = await _openChannelDialog();
    if (channel != null) {
      await _createOrUpdateChannel(channel, isEdit: false);
    }
  }

  Future<void> _handleImportChannelsFromDevice() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'yaml', 'yml', 'txt', 'debrify'],
      withData: true,
      withReadStream: true,
    );

    if (selection == null || selection.files.isEmpty) {
      return;
    }

    final pickedFile = selection.files.first;
    Uint8List bytes;
    try {
      bytes = await _readPickedFileBytes(pickedFile);
    } catch (error) {
      _showSnack(
        'Unable to read selected file: ${_formatImportError(error)}',
        color: Colors.red,
      );
      return;
    }

    if (bytes.isEmpty) {
      _showSnack('Selected file appears to be empty.', color: Colors.orange);
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Importing channel from local storage…';
    });

    try {
      await _safeImportChannelBytes(
        sourceName: pickedFile.name,
        bytes: bytes,
        origin: _ChannelImportOrigin.device,
      );
    } catch (error) {
      _showSnack(
        'Import failed: ${_formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _status = '';
        });
        _closeProgressDialog();
      }
    }
  }

  Future<void> _handleImportChannelsFromUrl() async {
    final input = await _promptImportUrl();
    if (input == null) {
      return;
    }

    final trimmedInput = input.trim();

    // Check if it's a debrify link (pasted directly)
    if (MagnetYamlService.isMagnetLink(trimmedInput)) {
      await _importDebrifyLinkDirectly(trimmedInput);
      return;
    }

    // Otherwise, treat as URL
    Uri uri;
    try {
      uri = Uri.parse(trimmedInput);
      if (!uri.hasAbsolutePath ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw const FormatException('invalid');
      }
    } catch (_) {
      _showSnack(
        'Enter a valid debrify:// link or http(s) URL.',
        color: Colors.red,
      );
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Downloading channel file…';
    });

    _showChannelCreationDialog('Importing channel…');
    _updateProgress(['Downloading channel file…']);

    try {
      final streamedResponse = await http.Request('GET', uri).send();
      if (streamedResponse.statusCode != 200) {
        throw FormatException('HTTP ${streamedResponse.statusCode}');
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      int receivedBytes = 0;
      final builder = BytesBuilder(copy: false);

      await for (final chunk in streamedResponse.stream) {
        builder.add(chunk);
        receivedBytes += chunk.length;
        final percent = totalBytes > 0
            ? (receivedBytes / totalBytes * 100).clamp(0, 100)
            : null;
        final progressMessage = percent != null
            ? 'Downloading… ${percent.toStringAsFixed(0)}%'
            : 'Downloading… ${_formatBytes(receivedBytes)}';
        _updateProgress([progressMessage], replace: true);
      }

      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        _updateProgress(['Downloaded file is empty.'], replace: true);
        _showSnack('Downloaded file is empty.', color: Colors.orange);
        return;
      }

      final sourceName = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : 'channel.${_guessExtensionFromHeaders(streamedResponse.headers)}';

      _updateProgress(['Download complete. Processing…'], replace: true);

      await _safeImportChannelBytes(
        sourceName: sourceName,
        bytes: bytes,
        origin: _ChannelImportOrigin.url,
      );
    } catch (error) {
      _showSnack(
        'Import failed: ${_formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _status = '';
        });
        _closeProgressDialog();
      }
    }
  }

  Future<void> _handleImportChannelsFromCommunity() async {
    final selectedChannels = await _promptCommunityChannelsDialog();
    if (selectedChannels == null || selectedChannels.isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Importing community channels...';
    });

    _showChannelCreationDialog('Importing community channels...');

    int successCount = 0;
    int failureCount = 0;
    final List<String> errors = [];

    for (int i = 0; i < selectedChannels.length; i++) {
      final channel = selectedChannels[i];
      _updateProgress([
        'Downloading channel ${i + 1} of ${selectedChannels.length}...',
        channel.name,
      ], replace: true);

      try {
        // Download the channel file
        final bytes = await CommunityChannelsService.downloadChannelFile(
          channel.url,
        );

        if (bytes.isEmpty) {
          throw Exception('Downloaded file is empty');
        }

        // Import using existing method (don't show dialog/summary for each channel)
        final success = await _importDebrifyBytes(
          channel.name,
          bytes,
          showDialog: false,
          showSummary: false,
        );

        if (success) {
          successCount++;
        } else {
          failureCount++;
          errors.add('${channel.name}: Import failed');
        }
      } catch (error) {
        failureCount++;
        errors.add('${channel.name}: ${error.toString()}');
      }
    }

    _updateProgress([
      'Import complete!',
      if (successCount > 0) 'Successfully imported $successCount channel(s)',
      if (failureCount > 0) 'Failed to import $failureCount channel(s)',
      ...errors.take(5), // Show first 5 errors
    ], replace: true);

    // Show summary
    final Color snackColor = successCount > 0
        ? (failureCount > 0 ? Colors.orange : Colors.green)
        : Colors.red;

    final String message = successCount > 0
        ? 'Imported $successCount channel${successCount > 1 ? 's' : ''}${failureCount > 0 ? ', $failureCount failed' : ''}'
        : 'Failed to import channels';

    _showSnack(message, color: snackColor);

    // Keep dialog open for 2 seconds to show summary
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _isBusy = false;
        _status = '';
      });
      _closeProgressDialog();
    }
  }

  Future<List<CommunityChannel>?> _promptCommunityChannelsDialog() async {
    if (!mounted) {
      return null;
    }

    return showDialog<List<CommunityChannel>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _CommunityChannelsDialog(isAndroidTv: _isAndroidTv);
      },
    );
  }

  Future<Uint8List> _readPickedFileBytes(PlatformFile file) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      return Uint8List.fromList(file.bytes!);
    }

    final stream = file.readStream;
    if (stream != null) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    }

    throw const FormatException('Unable to access file bytes.');
  }

  Future<bool> _importChannelBytes({
    required String sourceName,
    required Uint8List bytes,
    required _ChannelImportOrigin origin,
  }) async {
    final type = _determineImportType(sourceName, bytes);
    if (type == null) {
      _showSnack(
        'Unsupported file type. Select a .zip, .yaml, .txt, or .debrify file.',
        color: Colors.orange,
      );
      return false;
    }

    switch (type) {
      case _ChannelImportType.zip:
        return await _importZipBytes(bytes, origin);
      case _ChannelImportType.yaml:
        return await _importYamlBytes(sourceName, bytes, origin);
      case _ChannelImportType.text:
        return await _importTextBytes(sourceName, bytes);
      case _ChannelImportType.debrify:
        return await _importDebrifyBytes(sourceName, bytes);
    }
  }

  Future<bool> _safeImportChannelBytes({
    required String sourceName,
    required Uint8List bytes,
    required _ChannelImportOrigin origin,
  }) async {
    try {
      return await _importChannelBytes(
        sourceName: sourceName,
        bytes: bytes,
        origin: origin,
      );
    } on FormatException catch (error) {
      _showSnack(error.message, color: Colors.red);
      return false;
    }
  }

  _ChannelImportType? _determineImportType(String sourceName, Uint8List bytes) {
    final lower = sourceName.toLowerCase();

    // Check extension first
    if (lower.endsWith('.zip')) {
      return _ChannelImportType.zip;
    }
    if (lower.endsWith('.debrify')) {
      return _ChannelImportType.debrify;
    }
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return _ChannelImportType.yaml;
    }
    if (lower.endsWith('.txt')) {
      return _ChannelImportType.text;
    }

    // Fallback: check file signature for zip
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
      // PK — zip signature
      return _ChannelImportType.zip;
    }

    // Smart content detection for unknown extensions
    try {
      final content = utf8.decode(bytes).trim();
      if (content.startsWith('debrify://')) {
        return _ChannelImportType.debrify;
      }
    } catch (_) {
      // If UTF-8 decode fails, not a text file
    }

    return null;
  }

  Future<bool> _importZipBytes(
    Uint8List bytes,
    _ChannelImportOrigin origin,
  ) async {
    final dialogLabel = origin == _ChannelImportOrigin.device
        ? 'Importing zip…'
        : 'Processing zip…';

    _showChannelCreationDialog(dialogLabel);
    _updateProgress(['Parsing archive…']);

    final parsed = await _parseZipInBackground(bytes);
    _updateProgress([
      'Parsed ${parsed.channels.length} channel(s)',
      'Saving channel data…',
    ]);

    final persistence = await _persistImportedZipChannels(parsed.channels);
    _updateProgress([
      'Saved ${persistence.successes.length} channel(s)',
      if (persistence.failures.isNotEmpty)
        '${persistence.failures.length} channel(s) failed',
    ]);

    await _showZipImportSummary(parsed, persistence);
    return persistence.successes.isNotEmpty;
  }

  Future<bool> _importYamlBytes(
    String sourceName,
    Uint8List bytes,
    _ChannelImportOrigin origin,
  ) async {
    final content = utf8.decode(bytes);
    final dialogLabel = origin == _ChannelImportOrigin.device
        ? 'Importing YAML…'
        : 'Processing YAML…';

    _showChannelCreationDialog(dialogLabel);
    _updateProgress(['Parsing YAML…']);

    final channel = await _parseYamlInBackground(sourceName, content);

    final parsed = DebrifyTvZipImportResult(
      channels: [channel],
      failures: const [],
    );

    _updateProgress(['Saving channel…']);
    final persistence = await _persistImportedZipChannels(parsed.channels);
    _updateProgress([
      'Saved ${persistence.successes.length} channel(s)',
      if (persistence.failures.isNotEmpty)
        '${persistence.failures.length} channel(s) failed',
    ]);

    await _showZipImportSummary(parsed, persistence);
    return persistence.successes.isNotEmpty;
  }

  Future<bool> _importTextBytes(String sourceName, Uint8List bytes) async {
    final content = utf8.decode(bytes);
    final keywords = <String>[];
    final seen = <String>{};

    final lines = const LineSplitter().convert(content);
    for (final rawLine in lines) {
      final parts = rawLine.split(',');
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        if (trimmed.length > 120) {
          throw FormatException(
            'Keyword exceeds 120 characters: "${trimmed.substring(0, trimmed.length > 40 ? 40 : trimmed.length)}${trimmed.length > 40 ? '…' : ''}"',
          );
        }
        final lower = trimmed.toLowerCase();
        if (seen.add(lower)) {
          keywords.add(trimmed);
        }
      }
    }

    if (keywords.isEmpty) {
      throw const FormatException('No keywords found in the selected file.');
    }
    if (keywords.length > 500) {
      throw const FormatException(
        'Channel files must contain 500 keywords or fewer.',
      );
    }

    final baseName = _stripExtension(sourceName);
    final lowerExisting = _channels.map((c) => c.name.toLowerCase()).toSet();
    final channelName = _resolveUniqueChannelName(baseName, lowerExisting);
    final now = DateTime.now();
    final channel = _DebrifyTvChannel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: channelName,
      keywords: keywords,
      avoidNsfw: true,
      channelNumber: 0,
      createdAt: now,
      updatedAt: now,
    );

    await _createOrUpdateChannel(channel, isEdit: false);
    _showSnack('Imported "${channel.name}"', color: Colors.green);
    return true;
  }

  Future<bool> _importDebrifyBytes(
    String sourceName,
    Uint8List bytes, {
    bool showDialog = true,
    bool showSummary = true,
  }) async {
    final content = utf8.decode(bytes).trim();

    // Validate debrify link format
    if (!MagnetYamlService.isMagnetLink(content)) {
      throw const FormatException('Not a valid Debrify link.');
    }

    if (showDialog) {
      _showChannelCreationDialog('Importing channel…');
    }
    _updateProgress(['Decoding debrify link…']);

    // Decode debrify link
    final result = MagnetYamlService.decode(content);

    _updateProgress(['Parsing channel data…']);

    // Parse the decoded YAML
    final channel = await _parseYamlInBackground(
      result.channelName,
      result.yamlContent,
    );

    final parsed = DebrifyTvZipImportResult(
      channels: [channel],
      failures: const [],
    );

    _updateProgress(['Saving channel…']);
    final persistence = await _persistImportedZipChannels(parsed.channels);
    _updateProgress([
      'Saved ${persistence.successes.length} channel(s)',
      if (persistence.failures.isNotEmpty)
        '${persistence.failures.length} channel(s) failed',
    ]);

    if (showSummary) {
      await _showZipImportSummary(parsed, persistence);
    }
    return persistence.successes.isNotEmpty;
  }

  Future<void> _importDebrifyLinkDirectly(String debrifyLink) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Decoding debrify link…';
    });

    try {
      final bytes = utf8.encode(debrifyLink);
      await _safeImportChannelBytes(
        sourceName: 'debrify_link',
        bytes: Uint8List.fromList(bytes),
        origin: _ChannelImportOrigin.url,
      );
    } catch (error) {
      _showSnack(
        'Import failed: ${_formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _status = '';
        });
        _closeProgressDialog();
      }
    }
  }

  String _stripExtension(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex <= 0) {
      return name.trim();
    }
    return name.substring(0, dotIndex).trim();
  }

  String _guessExtensionFromHeaders(Map<String, String> headers) {
    final contentType =
        headers['content-type'] ?? headers['Content-Type'] ?? 'text/plain';
    if (contentType.contains('zip')) {
      return 'zip';
    }
    if (contentType.contains('yaml') || contentType.contains('yml')) {
      return 'yaml';
    }
    return 'txt';
  }

  Future<String?> _promptImportUrl() async {
    if (!mounted) {
      return null;
    }

    final controller = TextEditingController();
    String? errorText;
    final FocusNode urlFocusNode = FocusNode(
      debugLabel: 'ZipUrlField',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        final focusContext = node.context;
        if (focusContext == null) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown) {
          FocusScope.of(focusContext).nextFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          FocusScope.of(focusContext).previousFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Import from Link'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        labelText: 'Debrify Link or File URL',
                        hintText: 'debrify://channel?... or https://...',
                        errorText: errorText,
                      ),
                      autofocus: true,
                      focusNode: urlFocusNode,
                      keyboardType: TextInputType.url,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Paste a debrify:// link or URL to a .zip, .yaml, .txt, or .debrify file.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final candidate = controller.text.trim();
                    if (candidate.isEmpty) {
                      setState(() {
                        errorText = 'Enter a link or URL to continue.';
                      });
                      return;
                    }

                    // Check if it's a debrify link (valid and accepted)
                    if (MagnetYamlService.isMagnetLink(candidate)) {
                      Navigator.of(dialogContext).pop(candidate);
                      return;
                    }

                    // Otherwise validate as http(s) URL
                    try {
                      final parsed = Uri.parse(candidate);
                      if (!parsed.hasAbsolutePath ||
                          (parsed.scheme != 'http' &&
                              parsed.scheme != 'https')) {
                        throw const FormatException('invalid');
                      }
                    } catch (_) {
                      setState(() {
                        errorText =
                            'Enter a valid debrify:// link or http(s) URL.';
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop(candidate);
                  },
                  child: const Text('Import'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    urlFocusNode.dispose();
    return result;
  }

  Future<_ZipImportPersistenceResult> _persistImportedZipChannels(
    List<DebrifyTvZipImportedChannel> channels,
  ) async {
    if (channels.isEmpty) {
      return const _ZipImportPersistenceResult(successes: [], failures: []);
    }

    final successes = <_ZipImportSuccess>[];
    final failures = <_ZipImportSaveFailure>[];

    final List<_DebrifyTvChannel> appendedChannels = [];
    final Map<String, DebrifyTvChannelCacheEntry> appendedCache = {};

    final Set<String> usedNames = _channels
        .map((channel) => channel.name.toLowerCase())
        .toSet();

    for (final channel in channels) {
      if (channel.normalizedKeywords.length > _maxChannelKeywords) {
        failures.add(
          _ZipImportSaveFailure(
            sourceName: channel.sourceName,
            channelName: channel.channelName,
            reason:
                'Channel has ${channel.normalizedKeywords.length} keywords; maximum supported is $_maxChannelKeywords.',
          ),
        );
        continue;
      }

      final uniqueName = _resolveUniqueChannelName(
        channel.channelName,
        usedNames,
      );
      final channelId = DateTime.now().microsecondsSinceEpoch.toString();
      final now = DateTime.now();

      final record = DebrifyTvChannelRecord(
        channelId: channelId,
        name: uniqueName,
        keywords: channel.displayKeywords,
        avoidNsfw: channel.avoidNsfw,
        channelNumber: 0,
        createdAt: now,
        updatedAt: now,
      );

      final entry = DebrifyTvChannelCacheEntry(
        version: 1,
        channelId: channelId,
        normalizedKeywords: channel.normalizedKeywords,
        fetchedAt: now.millisecondsSinceEpoch,
        status: DebrifyTvCacheStatus.ready,
        errorMessage: null,
        torrents: channel.torrents,
        keywordStats: channel.keywordStats,
      );

      try {
        await DebrifyTvRepository.instance.upsertChannel(record);
        await DebrifyTvCacheService.saveEntry(entry);

        appendedChannels.add(
          _DebrifyTvChannel(
            id: channelId,
            name: uniqueName,
            keywords: const <String>[],
            avoidNsfw: channel.avoidNsfw,
            channelNumber: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
        appendedCache[channelId] = entry;

        successes.add(
          _ZipImportSuccess(
            sourceName: channel.sourceName,
            channelName: uniqueName,
            keywordCount: channel.normalizedKeywords.length,
            torrentCount: channel.torrentCount,
          ),
        );

        usedNames.add(uniqueName.toLowerCase());
      } catch (error) {
        failures.add(
          _ZipImportSaveFailure(
            sourceName: channel.sourceName,
            channelName: uniqueName,
            reason: _formatImportError(error),
          ),
        );
      }
    }

    if (appendedChannels.isNotEmpty && mounted) {
      setState(() {
        _channels = [..._channels, ...appendedChannels];
        _channelCache.addAll(appendedCache);
      });
      await _loadChannels();
    }

    return _ZipImportPersistenceResult(
      successes: successes,
      failures: failures,
    );
  }

  Future<void> _showZipImportSummary(
    DebrifyTvZipImportResult parsed,
    _ZipImportPersistenceResult persisted,
  ) async {
    if (!mounted) {
      return;
    }

    final bool hasSuccess = persisted.successes.isNotEmpty;
    final List<_ZipImportFailureDisplay> failureRows = [
      ...parsed.failures.map(
        (failure) => _ZipImportFailureDisplay(
          sourceName: failure.entryName,
          reason: failure.reason,
        ),
      ),
      ...persisted.failures.map(
        (failure) => _ZipImportFailureDisplay(
          sourceName: failure.sourceName.isEmpty
              ? failure.channelName
              : failure.sourceName,
          reason: failure.reason,
        ),
      ),
    ];

    if (!hasSuccess && failureRows.isEmpty) {
      _showSnack(
        'No channels found in the selected zip.',
        color: Colors.orange,
      );
      return;
    }

    final String dialogTitle = hasSuccess
        ? 'Zip import complete'
        : 'Zip import failed';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(dialogTitle),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasSuccess) ...[
                    Text(
                      'Imported ${persisted.successes.length} channel${persisted.successes.length == 1 ? '' : 's'}.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ...persisted.successes.map(
                      (success) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 20,
                        ),
                        title: Text(success.channelName),
                        subtitle: Text(
                          '${success.keywordCount} keyword${success.keywordCount == 1 ? '' : 's'} • ${success.torrentCount} torrent${success.torrentCount == 1 ? '' : 's'}',
                        ),
                      ),
                    ),
                  ] else ...[
                    const Text('No channels were imported.'),
                  ],
                  if (failureRows.isNotEmpty) ...[
                    if (hasSuccess) const SizedBox(height: 12),
                    Text(
                      'Issues detected:',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    ...failureRows.map(
                      (failure) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(
                          Icons.error_outline,
                          color: Colors.orange,
                          size: 20,
                        ),
                        title: Text(failure.sourceName),
                        subtitle: Text(failure.reason),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );

    if (hasSuccess) {
      final String names = persisted.successes
          .map((success) => '"${success.channelName}"')
          .join(', ');
      _showSnack(
        'Imported ${persisted.successes.length} channel${persisted.successes.length == 1 ? '' : 's'}: $names',
        color: Colors.green,
      );
    } else if (failureRows.isNotEmpty) {
      _showSnack(
        'Zip import failed: ${failureRows.first.reason}',
        color: Colors.red,
      );
    }
  }

  String _resolveUniqueChannelName(
    String baseName,
    Set<String> usedLowerCaseNames,
  ) {
    final String trimmed = baseName.trim().isEmpty
        ? 'Imported Channel'
        : baseName.trim();
    String candidate = trimmed;
    int suffix = 2;
    while (usedLowerCaseNames.contains(candidate.toLowerCase())) {
      candidate = '$trimmed ($suffix)';
      suffix++;
    }
    return candidate;
  }

  Future<void> _handleEditChannel(_DebrifyTvChannel channel) async {
    await _syncProviderAvailability();

    // Store current channel's NSFW setting before dialog
    final nsfwBeforeEdit = channel.avoidNsfw;

    final keywords = await _getChannelKeywords(channel.id);
    final hydrated = channel.copyWith(keywords: keywords);
    final updated = await _openChannelDialog(existing: hydrated);
    if (updated != null) {
      // Check if channel's NSFW setting changed
      final nsfwAfterEdit = updated.avoidNsfw;
      final nsfwChanged = nsfwBeforeEdit != nsfwAfterEdit;

      if (nsfwChanged) {
        // NSFW setting changed for this channel - rebuild cache with new filter
        debugPrint(
          'DebrifyTV: Channel NSFW filter changed. Forcing full cache rebuild...',
        );

        // Clear existing cache to force full rebuild
        _channelCache.remove(updated.id);

        // Rebuild cache with new NSFW filter setting (isEdit: false forces full rebuild)
        await _createOrUpdateChannel(updated, isEdit: false);

        _showSnack(
          'Channel cache rebuilt with updated NSFW filter.',
          color: Colors.green,
        );
      } else {
        // No NSFW change, just normal update
        await _createOrUpdateChannel(updated, isEdit: true);
      }
    }
  }

  Future<void> _handleDeleteChannel(_DebrifyTvChannel channel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete channel?'),
          content: Text('Remove "${channel.name}" and its saved keywords?'),
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

  Future<void> _handleShareChannelAsMagnet(_DebrifyTvChannel channel) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Generating magnet link…';
    });

    try {
      // Generate simplified YAML for sharing (without cached torrents)
      final yamlContent = _generateChannelYaml(channel);

      // Encode as magnet link
      final magnetLink = MagnetYamlService.encode(
        yamlContent: yamlContent,
        channelName: channel.name,
      );

      // Estimate sizes for display
      final estimatedSize = MagnetYamlService.estimateMagnetLinkSize(
        yamlContent,
      );
      final compressionRatio = MagnetYamlService.getCompressionRatio(
        yamlContent,
      );

      if (!mounted) {
        return;
      }

      // Show magnet link dialog
      await showDialog(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Channel Magnet Link'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Share this magnet link with others to import your channel configuration:',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black26),
                    ),
                    child: SelectableText(
                      magnetLink,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Size: ${_formatBytes(estimatedSize)} • '
                    'Compression: ${compressionRatio.toStringAsFixed(1)}x',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Channel: ${channel.name}\n'
                    'Keywords: ${channel.keywords.length}',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: magnetLink));
                  _showSnack('Magnet link copied!', color: Colors.green);
                  Navigator.of(dialogContext).pop();
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy Link'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      _showSnack(
        'Failed to generate magnet link: ${_formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _status = '';
        });
      }
    }
  }

  String _generateChannelYaml(_DebrifyTvChannel channel) {
    // Generate simplified YAML with just channel config (no cached data)
    final buffer = StringBuffer();
    buffer.writeln('channel_name: "${channel.name}"');
    buffer.writeln('avoid_nsfw: ${channel.avoidNsfw}');
    buffer.writeln('');
    buffer.writeln('keywords:');

    for (final keyword in channel.keywords) {
      buffer.writeln('  $keyword:');
      buffer.writeln('    torrents: []');
    }

    return buffer.toString();
  }

  Future<void> _handleDeleteAllChannels() async {
    if (_channels.isEmpty) {
      _showSnack('No channels to delete.', color: Colors.orange);
      return;
    }

    if (!mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete all channels?'),
          content: const Text(
            'This will remove every Debrify TV channel along with cached torrents. '
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text('Delete all'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      await DebrifyTvRepository.instance.clearAll();
      await DebrifyTvCacheService.clearAll();
      setState(() {
        _channels = const <_DebrifyTvChannel>[];
        _channelCache.clear();
      });
      _showSnack('All channels deleted.', color: Colors.orange);
    } catch (error) {
      _showSnack(
        'Failed to delete channels: ${_formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _createOrUpdateChannel(
    _DebrifyTvChannel channel, {
    required bool isEdit,
  }) async {
    final normalizedKeywords = _normalizedKeywords(channel.keywords);
    if (normalizedKeywords.isEmpty) {
      _showSnack(
        'Add at least one keyword before saving.',
        color: Colors.orange,
      );
      return;
    }

    debugPrint(
      'DebrifyTV: ${isEdit ? 'Updating' : 'Creating'} channel "${channel.name}" with ${normalizedKeywords.length} keyword(s): ${normalizedKeywords.join(', ')}',
    );

    final int estimatedSeconds = _estimatedWarmDurationSeconds(
      normalizedKeywords.length,
      totalKeywordUniverse: normalizedKeywords.length,
    );
    bool progressShown = false;
    void ensureProgressDialog({int? countdownSeconds}) {
      if (!progressShown) {
        _showChannelCreationDialog(
          channel.name,
          countdownSeconds: countdownSeconds ?? estimatedSeconds,
        );
        progressShown = true;
      }
    }

    try {
      final baseline = isEdit ? await _ensureCacheEntry(channel.id) : null;
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

          final filteredStats = Map<String, KeywordStat>.from(
            baseline.keywordStats,
          )..removeWhere((key, _) => removedKeywords.contains(key));

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
        } else if (baseline.normalizedKeywords.length !=
            normalizedKeywords.length) {
          workingEntry = baseline.copyWith(
            normalizedKeywords: normalizedKeywords,
          );
        }

        if (addedKeywords.isNotEmpty) {
          ensureProgressDialog(
            countdownSeconds: _estimatedWarmDurationSeconds(
              addedKeywords.length,
              totalKeywordUniverse: normalizedKeywords.length,
            ),
          );
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
          workingEntry = baseline.copyWith(
            normalizedKeywords: normalizedKeywords,
          );
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
        _showSnack(
          'Failed to build channel cache. Please try again.',
          color: Colors.red,
        );
        return;
      }

      if (!mounted) {
        return;
      }

      if (!entry.isReady ||
          entry.torrents.length < _minimumTorrentsForChannel) {
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

      final updatedChannel = channel.copyWith(updatedAt: DateTime.now());

      final displayChannel = updatedChannel.copyWith(
        keywords: const <String>[],
      );

      setState(() {
        final index = _channels.indexWhere((c) => c.id == displayChannel.id);
        if (index == -1) {
          _channels = <_DebrifyTvChannel>[..._channels, displayChannel];
        } else {
          final next = List<_DebrifyTvChannel>.from(_channels);
          next[index] = displayChannel;
          _channels = next;
        }
        _channelCache[displayChannel.id] = entry;
      });

      await DebrifyTvRepository.instance.upsertChannel(
        updatedChannel.toRecord(),
      );
      await DebrifyTvCacheService.saveEntry(entry);
      await _loadChannels();

      final successMsg = isEdit
          ? 'Channel "${updatedChannel.name}" updated'
          : 'Channel "${updatedChannel.name}" saved';
      _showSnack(successMsg, color: Colors.green);
      debugPrint(
        'DebrifyTV: $successMsg (torrents cached: ${entry.torrents.length})',
      );
    } catch (e) {
      debugPrint('DebrifyTV: Channel creation failed for ${channel.name}: $e');
      _showSnack(
        'Failed to build channel cache. Please try again.',
        color: Colors.red,
      );
    } finally {
      if (progressShown) {
        _closeProgressDialog();
      }
    }
  }

  Future<void> _watchChannel(_DebrifyTvChannel channel) async {
    debugPrint('🎬 [WATCH] Starting for channel: ${channel.name}');

    final keywords = await _getChannelKeywords(channel.id);
    if (keywords.isEmpty) {
      debugPrint('❌ [WATCH] No keywords');
      MainPageBridge.notifyAutoLaunchFailed('Channel has no keywords');
      _showSnack('Channel has no keywords yet', color: Colors.orange);
      return;
    }
    debugPrint('✅ [WATCH] Keywords: ${keywords.length}');

    await _syncProviderAvailability();
    final bool providerReady = switch (_provider) {
      _providerTorbox => _torboxAvailable,
      _providerPikPak => _pikpakAvailable,
      _ => _rdAvailable,
    };
    if (!providerReady) {
      debugPrint('❌ [WATCH] Provider not ready: $_provider');
      MainPageBridge.notifyAutoLaunchFailed('Provider not configured');
      final providerName = _providerDisplay(_provider);
      _showSnack(
        'Enable $providerName in Settings to watch this channel',
        color: Colors.orange,
      );
      return;
    }
    debugPrint('✅ [WATCH] Provider ready: $_provider');

    final cacheEntry = await _ensureCacheEntry(channel.id);
    if (cacheEntry == null) {
      debugPrint('❌ [WATCH] Cache entry is null');
      MainPageBridge.notifyAutoLaunchFailed('Cache entry not found');
      _showSnack(
        'Channel cache not found. Edit the channel to rebuild it.',
        color: Colors.orange,
      );
      return;
    }
    debugPrint('✅ [WATCH] Cache entry loaded, status: ${cacheEntry.status}');

    if (!cacheEntry.isReady) {
      debugPrint('❌ [WATCH] Cache not ready, status: ${cacheEntry.status}');
      MainPageBridge.notifyAutoLaunchFailed(
        'Cache not ready: ${cacheEntry.status}',
      );
      final message =
          cacheEntry.errorMessage ??
          'Channel cache failed to build. Try editing and saving again.';
      _showSnack(message, color: Colors.orange);
      return;
    }

    if (cacheEntry.torrents.isEmpty) {
      debugPrint('❌ [WATCH] Cache has no torrents');
      MainPageBridge.notifyAutoLaunchFailed('Cache has no torrents');
      _showSnack(
        'No torrents cached yet. Try editing the channel keywords.',
        color: Colors.orange,
      );
      return;
    }
    debugPrint('✅ [WATCH] Cache has ${cacheEntry.torrents.length} torrents');

    final previousKeywords = _keywordsController.text;

    final int resolvedChannelNumber = _resolveChannelNumber(channel);

    setState(() {
      _currentWatchingChannelId = channel.id; // Track for channel switching
    });
    _keywordsController.text = keywords.join(', ');

    final normalizedKeywords = _normalizedKeywords(keywords);
    final playbackSelection = _selectTorrentsForPlayback(
      cacheEntry,
      normalizedKeywords,
    );
    final cachedTorrents = playbackSelection
        .map((cached) => cached.toTorrent())
        .toList();
    debugPrint(
      '✅ [WATCH] Selected ${cachedTorrents.length} torrents for playback',
    );

    if (_provider == _providerTorbox) {
      debugPrint('🎬 [WATCH] Launching Torbox flow...');
      await _watchTorboxWithCachedTorrents(
        cachedTorrents,
        channelName: channel.name,
        channelId: channel.id,
        channelNumber: resolvedChannelNumber,
      );
    } else if (_provider == _providerPikPak) {
      debugPrint('🎬 [WATCH] Launching PikPak flow...');
      await _watchPikPakWithCachedTorrents(
        cachedTorrents,
        channelName: channel.name,
        channelId: channel.id,
        channelNumber: resolvedChannelNumber,
      );
    } else {
      debugPrint('🎬 [WATCH] Launching RealDebrid flow...');
      await _watchWithCachedTorrents(
        cachedTorrents,
        applyNsfwFilter: channel.avoidNsfw,
        channelName: channel.name,
        channelId: channel.id,
        channelNumber: resolvedChannelNumber,
      );
    }

    if (!mounted) {
      return;
    }

    _keywordsController.text = previousKeywords;
  }

  Future<void> _watch() async {
    _launchedPlayer = false;
    await _stopPrefetch();
    _prefetchStopRequested = false;
    _watchCancelled = false;
    _originalMaxCap = null;
    void _log(String m) {
      final copy = List<String>.from(_progress.value)..add(m);
      _progress.value = copy;
      debugPrint('DebrifyTV: ' + m);
    }

    await _syncProviderAvailability();
    if (!_rdAvailable && !_torboxAvailable && !_pikpakAvailable) {
      if (mounted) {
        setState(() {
          _status =
              'Connect Real Debrid, Torbox, or PikPak in Settings to use Debrify TV.';
        });
      }
      _showSnack(
        'Connect Real Debrid, Torbox, or PikPak in Settings to use Debrify TV.',
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
    debugPrint(
      'DebrifyTV: Parsed ${keywords.length} keyword(s): ${keywords.join(' | ')}',
    );
    if (keywords.isEmpty) {
      setState(() {
        _status = 'Enter valid keywords';
      });
      debugPrint(
        'DebrifyTV: Aborting. Parsed keywords became empty after trimming.',
      );
      return;
    }
    if (keywords.length > _quickPlayMaxKeywords) {
      setState(() {
        _status =
            'Quick Play supports up to $_quickPlayMaxKeywords keywords. Create a channel for larger sets.';
      });
      _showSnack(
        'Quick Play supports up to $_quickPlayMaxKeywords keywords. Create a channel for bigger combos.',
        color: Colors.orange,
      );
      debugPrint(
        'DebrifyTV: Aborting. Too many keywords for Quick Play (${keywords.length}).',
      );
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
    final providerLabel = _quickProvider == _providerTorbox
        ? 'Torbox'
        : _quickProvider == _providerPikPak
        ? 'PikPak'
        : 'Real Debrid';
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  Widget content = Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.start,
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
                                  color: const Color(
                                    0xFFE50914,
                                  ).withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.tv_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Debrify TV',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
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
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  color: Colors.blue[300],
                                  size: 14,
                                ),
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
                            _cancelActiveWatch(dialogContext: context);
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
                  );

                  content = Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: content,
                  );

                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: content,
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      _progressOpen = false;
      _progressSheetContext = null;
    });

    if (_quickProvider == _providerTorbox) {
      await _watchWithTorbox(keywords, _log);
      return;
    }

    if (_quickProvider == _providerPikPak) {
      await _watchWithPikPak(keywords, _log);
      return;
    }

    // Silent approach - no progress logging needed

    try {
      // Require RD API key early so we can prefetch as soon as results arrive
      final String? apiKeyEarlyRaw = await StorageService.getApiKey();
      if (apiKeyEarlyRaw == null || apiKeyEarlyRaw.isEmpty) {
        if (!mounted) return;
        _log('❌ Real Debrid API key not found - please add it in Settings');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please add your Real Debrid API key in Settings first!',
            ),
          ),
        );
        debugPrint('DebrifyTV: Missing Real Debrid API key.');
        return;
      }
      final String apiKeyEarly = apiKeyEarlyRaw;

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
        if (_watchCancelled) {
          return null;
        }
        debugPrint(
          'DebrifyTV: requestMagicNext() called. queueSize=${_queue.length}',
        );
        while (_queue.isNotEmpty && !_watchCancelled) {
          final item = _queue.removeAt(0);
          if (_watchCancelled) {
            break;
          }
          // Case 1: RD-restricted entry (append-only items)
          if (item is Map && item['type'] == 'rd_restricted') {
            final String link = item['restrictedLink'] as String? ?? '';
            final String rdTid = item['torrentId'] as String? ?? '';
            debugPrint(
              'DebrifyTV: Trying RD link from queue: torrentId=$rdTid',
            );
            if (link.isEmpty) continue;
            try {
              final started = DateTime.now();
              final unrestrict = await DebridService.unrestrictLink(
                apiKeyEarly,
                link,
              );
              if (_watchCancelled) {
                return null;
              }
              final elapsed = DateTime.now().difference(started).inSeconds;
              final videoUrl = unrestrict['download'] as String?;
              if (videoUrl != null && videoUrl.isNotEmpty) {
                debugPrint(
                  'DebrifyTV: Success (RD link). Unrestricted in ${elapsed}s',
                );
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final display = (item['displayName'] as String?)?.trim();
                final chosenTitle = inferred.isNotEmpty
                    ? inferred
                    : (display ?? 'Debrify TV');
                firstTitle = chosenTitle;
                if (_watchCancelled) {
                  return null;
                }
                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint('DebrifyTV: RD link failed to unrestrict: $e');
              continue;
            }
          }

          // Case 2: Torrent entry
          if (item is Torrent) {
            debugPrint(
              'DebrifyTV: Trying torrent: name="${item.name}", hash=${item.infohash}, size=${item.sizeBytes}, seeders=${item.seeders}',
            );
            final magnetLink = 'magnet:?xt=urn:btih:${item.infohash}';
            try {
              final started = DateTime.now();
              final result = await DebridService.addTorrentToDebridPreferVideos(
                apiKeyEarly,
                magnetLink,
              );
              if (_watchCancelled) {
                return null;
              }
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

              final unrestrict = await DebridService.unrestrictLink(
                apiKeyEarly,
                selectedLink,
              );
              if (_watchCancelled) {
                return null;
              }
              final videoUrl = unrestrict['download'] as String?;
              if (videoUrl != null && videoUrl.isNotEmpty) {
                debugPrint(
                  'DebrifyTV: Success. Got unrestricted URL in ${elapsed}s',
                );
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final chosenTitle = inferred.isNotEmpty
                    ? inferred
                    : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
                firstTitle = chosenTitle;

                if (!_watchCancelled && newLinks.isNotEmpty) {
                  _queue.add(item);
                }

                if (_watchCancelled) {
                  return null;
                }
                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint(
                'DebrifyTV: Debrid add failed for ${item.infohash}: $e',
              );
            }
          }
        }
        debugPrint('DebrifyTV: requestMagicNext() queue exhausted.');
        return null;
      }

      final Map<String, Torrent> dedupByInfohash = {};

      // Launch limited batches of per-keyword searches so we don't overwhelm
      List<String> pendingKeywords = List<String>.from(keywords);
      while (pendingKeywords.isNotEmpty && !_watchCancelled) {
        final batch = pendingKeywords.take(_channelCsvParallelism).toList();
        pendingKeywords = pendingKeywords.skip(batch.length).toList();

        final futures = batch.map((kw) {
          debugPrint('DebrifyTV: Searching engines for "$kw"...');
          return TorrentService.searchAllEngines(
            kw,
            engineStates: {
              'torrents_csv': _useTorrentsCsv,
              'pirate_bay': _usePirateBay,
              'yts': _useYts,
              'solid_torrents': _useSolidTorrents,
            },
            maxResultsOverrides: {
              'torrents_csv': _quickPlayTorrentsCsvMax,
              'pirate_bay': _quickPlayPirateBayMax,
              'yts': _quickPlayYtsMax,
              'solid_torrents': _quickPlaySolidTorrentsMax,
            },
          );
        }).toList();

        await for (final result in Stream.fromFutures(futures)) {
          if (_watchCancelled) {
            break;
          }
          final List<Torrent> torrents =
              (result['torrents'] as List<Torrent>?) ?? <Torrent>[];
          final engineCounts =
              (result['engineCounts'] as Map<String, int>?) ?? const {};
          final Map<String, String> engineErrors = {};
          final rawErrors = result['engineErrors'];
          if (rawErrors is Map) {
            rawErrors.forEach((key, value) {
              engineErrors[key.toString()] = value?.toString() ?? '';
            });
          }
          if (engineErrors.isNotEmpty) {
            engineErrors.forEach((engine, message) {
              debugPrint('DebrifyTV: Search engine "$engine" failed: $message');
            });
          }
          debugPrint(
            'DebrifyTV: Partial results received: total=${torrents.length}, engineCounts=$engineCounts',
          );

          // Apply NSFW filter if enabled
          List<Torrent> torrentsToProcess = torrents;
          if (_quickAvoidNsfw) {
            final beforeCount = torrents.length;
            torrentsToProcess = torrents.where((torrent) {
              if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
                debugPrint('DebrifyTV: Filtered NSFW torrent: ${torrent.name}');
                return false;
              }
              return true;
            }).toList();
            if (beforeCount != torrentsToProcess.length) {
              debugPrint(
                'DebrifyTV: NSFW filter: $beforeCount → ${torrentsToProcess.length} torrents',
              );
            }
          }

          int added = 0;
          for (final t in torrentsToProcess) {
            if (!dedupByInfohash.containsKey(t.infohash)) {
              dedupByInfohash[t.infohash] = t;
              added++;
            }
          }
          if (added > 0) {
            if (_watchCancelled) {
              break;
            }
            final combined = dedupByInfohash.values.toList();
            combined.shuffle(Random());
            _queue
              ..clear()
              ..addAll(combined);
            _lastQueueSize = _queue.length;
            _lastSearchAt = DateTime.now();
            // Silent approach - no progress logging needed
            if (mounted && !_watchCancelled) {
              setState(() {
                _status = 'Preparing your content...';
              });
            }

            // Do not start prefetch until player launches

            // Try to launch player as soon as a playable stream is available
            if (!_launchedPlayer && !_watchCancelled) {
              final first = await requestMagicNext();
              if (_watchCancelled) {
                break;
              }
              if (first != null &&
                  mounted &&
                  !_launchedPlayer &&
                  !_watchCancelled) {
                _launchedPlayer = true;
                final firstUrl = first['url'] ?? '';
                final firstTitleResolved =
                    (first['title'] ?? firstTitle).trim().isNotEmpty
                    ? (first['title'] ?? firstTitle)
                    : firstTitle;
                if (!_watchCancelled &&
                    _progressOpen &&
                    _progressSheetContext != null) {
                  Navigator.of(_progressSheetContext!).pop();
                }
                debugPrint(
                  'DebrifyTV: Launching player early. Remaining queue=${_queue.length}',
                );

                // Start background prefetch only while player is active
                if (!_watchCancelled) {
                  _activeApiKey = apiKeyEarly;
                  _startPrefetch();

                  final String? activeChannelId = _currentWatchingChannelId;
                  final int? activeChannelNumber;
                  if (activeChannelId != null) {
                    final int idx = _channels.indexWhere(
                      (c) => c.id == activeChannelId,
                    );
                    if (idx >= 0) {
                      final int resolvedNumber = _resolveChannelNumber(
                        _channels[idx],
                      );
                      activeChannelNumber = resolvedNumber > 0
                          ? resolvedNumber
                          : null;
                    } else {
                      activeChannelNumber = null;
                    }
                  } else {
                    activeChannelNumber = null;
                  }
                  final List<Map<String, dynamic>>? activeChannelDirectory =
                      _channels.isNotEmpty
                      ? _androidTvChannelMetadata(
                          activeChannelId: activeChannelId,
                        )
                      : null;

                  // Try to launch on Android TV first (early launch path)
                  final launchedOnTv = await _launchRealDebridOnAndroidTv(
                    firstStream: first,
                    requestNext: requestMagicNext,
                    showChannelNameOverride: _quickShowChannelName,
                    channelId: activeChannelId,
                    channelNumber: activeChannelNumber,
                    channelDirectory: activeChannelDirectory,
                  );

                  if (launchedOnTv) {
                    // Successfully launched on Android TV
                    debugPrint(
                      'DebrifyTV: Early launch - Real-Debrid playback started on Android TV',
                    );
                    // Prefetch will continue in background while TV player is active
                    break; // Exit the search loop
                  }

                  // Hide auto-launch overlay before launching player
                  MainPageBridge.notifyPlayerLaunching();

                  // Fall back to Flutter video player
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VideoPlayerScreen(
                        videoUrl: firstUrl,
                        title: firstTitleResolved,
                        startFromRandom: _quickStartRandom,
                        randomStartMaxPercent: _quickRandomStartPercent,
                        hideSeekbar: _quickHideSeekbar,
                        showChannelName: _quickShowChannelName,
                        channelName: null,
                        channelNumber: null,
                        showVideoTitle: _quickShowVideoTitle,
                        hideOptions: _quickHideOptions,
                        requestMagicNext: requestMagicNext,
                        requestNextChannel:
                            _channels.length > 1 &&
                                (_quickProvider == _providerRealDebrid ||
                                    _quickProvider == _providerTorbox ||
                                    _quickProvider == _providerPikPak)
                            ? _requestNextChannel
                            : null,
                      ),
                    ),
                  );

                  // Stop prefetch when player exits
                  await _stopPrefetch();
                }
              }
            }
          }
        }
        if (_watchCancelled) {
          break;
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
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }

    if (_watchCancelled) {
      debugPrint('DebrifyTV: Watch was cancelled before completion.');
      return;
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
            content: Text(
              'No results found. Try different keywords or check your internet connection.',
            ),
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
        const SnackBar(
          content: Text(
            'Please add your Real Debrid API key in Settings first!',
          ),
        ),
      );
      debugPrint('MagicTV: Missing Real Debrid API key.');
      return;
    }

    String firstTitle = 'Debrify TV';

    Future<Map<String, String>?> requestMagicNext() async {
      debugPrint(
        'MagicTV: requestMagicNext() called. queueSize=${_queue.length}',
      );
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
              debugPrint(
                'MagicTV: Success (RD link). Unrestricted in ${elapsed}s',
              );
              // Prefer filename inferred from URL; fallback to any stored displayName
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final display = (item['displayName'] as String?)?.trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (display ?? 'Debrify TV');
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
          debugPrint(
            'MagicTV: Trying torrent: name="${item.name}", hash=${item.infohash}, size=${item.sizeBytes}, seeders=${item.seeders}',
          );
          final magnetLink = 'magnet:?xt=urn:btih:${item.infohash}';
          try {
            final started = DateTime.now();
            final result = await DebridService.addTorrentToDebridPreferVideos(
              apiKey,
              magnetLink,
            );
            final elapsed = DateTime.now().difference(started).inSeconds;
            final videoUrl = result['downloadLink'] as String?;
            // Append other RD-restricted links from this torrent to the END of the queue
            final String torrentId = result['torrentId'] as String? ?? '';
            final List<dynamic> rdLinks =
                (result['links'] as List<dynamic>? ?? const []);
            if (rdLinks.isNotEmpty) {
              // We assume we used rdLinks[0] to play; enqueue remaining
              for (int i = 1; i < rdLinks.length; i++) {
                final String link = rdLinks[i]?.toString() ?? '';
                if (link.isEmpty) continue;
                final String combined = '$torrentId|$link';
                if (_seenRestrictedLinks.contains(link) ||
                    _seenLinkWithTorrentId.contains(combined)) {
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
                debugPrint(
                  'MagicTV: Enqueued ${rdLinks.length - 1} additional RD links to tail. New queueSize=${_queue.length}',
                );
              }
            }
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint(
                'MagicTV: Success. Got unrestricted URL in ${elapsed}s',
              );
              // Prefer filename inferred from URL; fallback to torrent name
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
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
          MainPageBridge.notifyAutoLaunchFailed('No playable streams found');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No playable streams found. Try different keywords or check your internet connection.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
        debugPrint('MagicTV: No playable stream found.');
        return;
      }
      final firstUrl = first['url'] ?? '';
      firstTitle = (first['title'] ?? firstTitle).trim().isNotEmpty
          ? (first['title'] ?? firstTitle)
          : firstTitle;

      if (!mounted) return;
      debugPrint('MagicTV: Launching player. Remaining queue=${_queue.length}');

      // Start background prefetch while player is active
      _activeApiKey = apiKey;
      _startPrefetch();

      if (_progressOpen && _progressSheetContext != null) {
        Navigator.of(_progressSheetContext!).pop();
      }

      final String? activeChannelId = _currentWatchingChannelId;
      final int? activeChannelNumber;
      if (activeChannelId != null) {
        final int idx = _channels.indexWhere((c) => c.id == activeChannelId);
        if (idx >= 0) {
          final int resolvedNumber = _resolveChannelNumber(_channels[idx]);
          activeChannelNumber = resolvedNumber > 0 ? resolvedNumber : null;
        } else {
          activeChannelNumber = null;
        }
      } else {
        activeChannelNumber = null;
      }
      final List<Map<String, dynamic>>? quickChannelDirectory =
          _channels.isNotEmpty
          ? _androidTvChannelMetadata(activeChannelId: activeChannelId)
          : null;

      // Try to launch on Android TV first
      final launchedOnTv = await _launchRealDebridOnAndroidTv(
        firstStream: first,
        requestNext: requestMagicNext,
        showChannelNameOverride: _quickShowChannelName,
        channelId: activeChannelId,
        channelNumber: activeChannelNumber,
        channelDirectory: quickChannelDirectory,
      );

      if (launchedOnTv) {
        // Successfully launched on Android TV
        debugPrint('MagicTV: Real-Debrid playback started on Android TV');
        // Prefetch will continue in background while TV player is active
        return;
      }

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      // Fall back to Flutter video player
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: firstUrl,
            title: firstTitle,
            startFromRandom: _quickStartRandom,
            randomStartMaxPercent: _quickRandomStartPercent,
            hideSeekbar: _quickHideSeekbar,
            showChannelName: _quickShowChannelName,
            channelName: null,
            channelNumber: null,
            showVideoTitle: _quickShowVideoTitle,
            hideOptions: _quickHideOptions,
            requestMagicNext: requestMagicNext,
            requestNextChannel:
                _channels.length > 1 &&
                    (_quickProvider == _providerRealDebrid ||
                        _quickProvider == _providerTorbox ||
                        _quickProvider == _providerPikPak)
                ? _requestNextChannel
                : null,
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
    final Map<String, Torrent> dedup = <String, Torrent>{};

    try {
      final futures = keywords
          .map(
            (kw) => TorrentService.searchAllEngines(
              kw,
              engineStates: {
                'torrents_csv': _useTorrentsCsv,
                'pirate_bay': _usePirateBay,
                'yts': _useYts,
                'solid_torrents': _useSolidTorrents,
              },
              maxResultsOverrides: {
                'torrents_csv': _quickPlayTorrentsCsvMax,
                'pirate_bay': _quickPlayPirateBayMax,
                'yts': _quickPlayYtsMax,
                'solid_torrents': _quickPlaySolidTorrentsMax,
              },
            ),
          )
          .toList();

      await for (final result in Stream.fromFutures(futures)) {
        final torrents =
            (result['torrents'] as List<Torrent>? ?? const <Torrent>[]);
        final Map<String, String> engineErrors = {};
        final rawErrors = result['engineErrors'];
        if (rawErrors is Map) {
          rawErrors.forEach((key, value) {
            engineErrors[key.toString()] = value?.toString() ?? '';
          });
        }
        if (engineErrors.isNotEmpty) {
          engineErrors.forEach((engine, message) {
            debugPrint('Torbox: Search engine "$engine" failed: $message');
          });
        }

        // Apply NSFW filter if enabled
        List<Torrent> torrentsToProcess = torrents;
        if (_quickAvoidNsfw) {
          final beforeCount = torrents.length;
          torrentsToProcess = torrents.where((torrent) {
            if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
              debugPrint('Torbox: Filtered NSFW torrent: ${torrent.name}');
              return false;
            }
            return true;
          }).toList();
          if (beforeCount != torrentsToProcess.length) {
            debugPrint(
              'Torbox: NSFW filter: $beforeCount → ${torrentsToProcess.length} torrents',
            );
          }
        }

        int added = 0;
        for (final torrent in torrentsToProcess) {
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

      combinedList.shuffle(Random());
      if (mounted) {
        setState(() {
          _status = 'Checking Torbox cache...';
        });
      }

      int candidateCursor = 0;

      Future<bool> populateQueue() async {
        while (true) {
          if (candidateCursor >= combinedList.length) {
            return false;
          }
          final _TorboxCacheWindowResult window = await _fetchTorboxCacheWindow(
            candidates: combinedList,
            startIndex: candidateCursor,
            apiKey: apiKey,
          );
          candidateCursor = window.nextCursor;
          if (window.cachedTorrents.isEmpty) {
            if (window.exhausted) {
              return false;
            }
            continue;
          }
          _queue
            ..clear()
            ..addAll(window.cachedTorrents);
          _lastQueueSize = _queue.length;
          _lastSearchAt = DateTime.now();
          if (mounted) {
            setState(() {
              _status = _queue.isEmpty
                  ? ''
                  : 'Queue has ${_queue.length} remaining';
            });
          }
          log('✅ Found ${_queue.length} cached Torbox torrent(s)');
          return true;
        }
      }

      bool seeded;
      try {
        seeded = await populateQueue();
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

      if (!seeded) {
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

      Future<Map<String, String>?> requestTorboxNext() async {
        if (_watchCancelled) {
          return null;
        }
        while (!_watchCancelled) {
          if (_queue.isEmpty) {
            bool replenished;
            try {
              replenished = await populateQueue();
            } catch (e) {
              log('❌ Torbox cache check failed: $e');
              _closeProgressDialog();
              if (mounted && !_watchCancelled) {
                setState(() {
                  _status = 'Torbox cache check failed. Try again.';
                });
                _showSnack(
                  'Torbox cache check failed: ${_formatTorboxError(e)}',
                  color: Colors.red,
                );
              }
              return null;
            }
            if (!replenished) {
              break;
            }
          }
          if (_queue.isEmpty) {
            break;
          }
          final item = _queue.removeAt(0);
          if (_watchCancelled) {
            break;
          }
          if (item is Map && item['type'] == _torboxFileEntryType) {
            final resolved = await _resolveTorboxQueuedFile(
              entry: item as Map<String, dynamic>,
              apiKey: apiKey,
              log: log,
            );
            if (_watchCancelled) {
              return null;
            }
            if (resolved != null) {
              if (mounted && !_watchCancelled) {
                setState(() {
                  _status = _queue.isEmpty
                      ? ''
                      : 'Queue has ${_queue.length} remaining';
                });
              }
              if (_watchCancelled) {
                return null;
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
            if (_watchCancelled) {
              return null;
            }
            if (result != null) {
              if (result.hasMore && !_watchCancelled) {
                combinedList.add(item);
              }
              if (mounted && !_watchCancelled) {
                setState(() {
                  _status = _queue.isEmpty
                      ? ''
                      : 'Queue has ${_queue.length} remaining';
                });
              }
              if (_watchCancelled) {
                return null;
              }
              return {'url': result.streamUrl, 'title': result.title};
            }
          }
        }
        if (mounted && !_watchCancelled) {
          setState(() {
            _status = 'No more cached Torbox streams available.';
          });
        }
        return null;
      }

      final first = await requestTorboxNext();
      if (_watchCancelled) {
        return;
      }
      if (first == null) {
        _closeProgressDialog();
        if (mounted && !_watchCancelled) {
          setState(() {
            _status =
                'No playable Torbox streams found. Try different keywords.';
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

      final launchedOnTv = await _launchTorboxOnAndroidTv(
        firstStream: first,
        requestNext: requestTorboxNext,
        showChannelNameOverride: _quickShowChannelName,
        channelName: null,
        channelId: null,
        channelNumber: null,
        channelDirectory: null,
      );
      if (_watchCancelled) {
        return;
      }
      if (launchedOnTv) {
        return;
      }

      if (!_watchCancelled) {
        // Hide auto-launch overlay before launching player
        MainPageBridge.notifyPlayerLaunching();

        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              videoUrl: first['url'] ?? '',
              title: first['title'] ?? 'Debrify TV',
              startFromRandom: _startRandom,
              randomStartMaxPercent: _randomStartPercent,
              hideSeekbar: _hideSeekbar,
              showChannelName: _showChannelName,
              channelName: null,
              channelNumber: null,
              showVideoTitle: _showVideoTitle,
              hideOptions: _hideOptions,
              requestMagicNext: requestTorboxNext,
              requestNextChannel:
                  _channels.length > 1 &&
                      (_quickProvider == _providerRealDebrid ||
                          _quickProvider == _providerTorbox ||
                          _quickProvider == _providerPikPak)
                  ? _requestNextChannel
                  : null,
            ),
          ),
        );
      }

      if (mounted && !_watchCancelled) {
        setState(() {
          _status = _queue.isEmpty
              ? ''
              : 'Queue has ${_queue.length} remaining';
        });
      }
    } finally {
      _closeProgressDialog();
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _watchWithPikPak(
    List<String> keywords,
    void Function(String message) log,
  ) async {
    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    if (!pikpakAvailable) {
      _closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _status = 'Please login to PikPak in Settings first!';
        _isBusy = false;
      });
      _showSnack(
        'Please login to PikPak in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    log('🌐 PikPak: searching for torrents...');
    final Map<String, Torrent> dedup = <String, Torrent>{};

    try {
      final futures = keywords
          .map(
            (kw) => TorrentService.searchAllEngines(
              kw,
              engineStates: {
                'torrents_csv': _useTorrentsCsv,
                'pirate_bay': _usePirateBay,
                'yts': _useYts,
                'solid_torrents': _useSolidTorrents,
              },
              maxResultsOverrides: {
                'torrents_csv': _quickPlayTorrentsCsvMax,
                'pirate_bay': _quickPlayPirateBayMax,
                'yts': _quickPlayYtsMax,
                'solid_torrents': _quickPlaySolidTorrentsMax,
              },
            ),
          )
          .toList();

      await for (final result in Stream.fromFutures(futures)) {
        final torrents =
            (result['torrents'] as List<Torrent>? ?? const <Torrent>[]);
        final Map<String, String> engineErrors = {};
        final rawErrors = result['engineErrors'];
        if (rawErrors is Map) {
          rawErrors.forEach((key, value) {
            engineErrors[key.toString()] = value?.toString() ?? '';
          });
        }
        if (engineErrors.isNotEmpty) {
          engineErrors.forEach((engine, message) {
            debugPrint('PikPak: Search engine "$engine" failed: $message');
          });
        }

        // Apply NSFW filter if enabled
        List<Torrent> torrentsToProcess = torrents;
        if (_quickAvoidNsfw) {
          final beforeCount = torrents.length;
          torrentsToProcess = torrents.where((torrent) {
            if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
              debugPrint('PikPak: Filtered NSFW torrent: ${torrent.name}');
              return false;
            }
            return true;
          }).toList();
          if (beforeCount != torrentsToProcess.length) {
            debugPrint(
              'PikPak: NSFW filter: $beforeCount → ${torrentsToProcess.length} torrents',
            );
          }
        }

        int added = 0;
        for (final torrent in torrentsToProcess) {
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
              _status = 'Preparing PikPak stream...';
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

      combinedList.shuffle(Random());
      _queue
        ..clear()
        ..addAll(combinedList);
      _lastQueueSize = _queue.length;
      _lastSearchAt = DateTime.now();

      if (mounted) {
        setState(() {
          _status = 'Preparing PikPak stream...';
        });
      }

      Future<Map<String, String>?> requestPikPakNext() async {
        if (_watchCancelled) {
          return null;
        }
        while (_queue.isNotEmpty && !_watchCancelled) {
          final item = _queue.removeAt(0);
          if (_watchCancelled) {
            break;
          }
          if (item is! Torrent) {
            continue;
          }

          log('Trying torrent: ${item.name}');
          final prepared = await PikPakTvService.instance.prepareTorrent(
            infohash: item.infohash,
            torrentName: item.name,
            onLog: (msg) => debugPrint('DebrifyTV/PikPak: $msg'),
          );

          if (_watchCancelled) {
            return null;
          }

          if (prepared == null) {
            log('Torrent not ready, trying next...');
            continue;
          }

          if (mounted && !_watchCancelled) {
            setState(() {
              _status = _queue.isEmpty
                  ? ''
                  : 'Queue has ${_queue.length} remaining';
            });
          }

          return {
            'url': prepared['url']!,
            'title': prepared['title']!,
            'provider': prepared['provider'] ?? 'pikpak',
            'pikpakFileId': prepared['pikpakFileId'] ?? '',
          };
        }
        if (mounted && !_watchCancelled) {
          setState(() {
            _status = 'No more PikPak streams available.';
          });
        }
        return null;
      }

      final first = await requestPikPakNext();
      if (_watchCancelled) {
        return;
      }
      if (first == null) {
        _closeProgressDialog();
        if (mounted && !_watchCancelled) {
          setState(() {
            _status =
                'No playable PikPak streams found. Try different keywords.';
          });
          MainPageBridge.notifyAutoLaunchFailed('No PikPak streams available');
          _showSnack(
            'No playable PikPak streams found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      _closeProgressDialog();
      if (!mounted) return;

      // Try Android TV native player first
      final launchedOnTv = await _launchPikPakOnAndroidTv(
        firstStream: first,
        requestNext: requestPikPakNext,
        showChannelNameOverride: _quickShowChannelName,
        channelName: null,
        channelId: null,
        channelNumber: null,
        channelDirectory: null,
      );
      if (_watchCancelled) {
        return;
      }
      if (launchedOnTv) {
        return;
      }

      if (!_watchCancelled) {
        // Hide auto-launch overlay before launching player
        MainPageBridge.notifyPlayerLaunching();

        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              videoUrl: first['url'] ?? '',
              title: first['title'] ?? 'Debrify TV',
              startFromRandom: _quickStartRandom,
              randomStartMaxPercent: _quickRandomStartPercent,
              hideSeekbar: _quickHideSeekbar,
              showChannelName: _quickShowChannelName,
              channelName: null,
              channelNumber: null,
              showVideoTitle: _quickShowVideoTitle,
              hideOptions: _quickHideOptions,
              requestMagicNext: requestPikPakNext,
              requestNextChannel:
                  _channels.length > 1 &&
                      (_quickProvider == _providerRealDebrid ||
                          _quickProvider == _providerTorbox ||
                          _quickProvider == _providerPikPak)
                  ? _requestNextChannel
                  : null,
            ),
          ),
        );
      }

      if (mounted && !_watchCancelled) {
        setState(() {
          _status = _queue.isEmpty
              ? ''
              : 'Queue has ${_queue.length} remaining';
        });
      }
    } finally {
      _closeProgressDialog();
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _watchWithCachedTorrents(
    List<Torrent> cachedTorrents, {
    required bool applyNsfwFilter,
    String? channelName,
    String? channelId,
    int? channelNumber,
  }) async {
    if (cachedTorrents.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No cached torrents');
      _showSnack(
        'Cached channel has no torrents yet. Please wait a moment.',
        color: Colors.orange,
      );
      return;
    }

    final List<Map<String, dynamic>>? channelDirectory = _channels.isNotEmpty
        ? _androidTvChannelMetadata(
            activeChannelId: channelId ?? _currentWatchingChannelId,
          )
        : null;

    _launchedPlayer = false;
    await _stopPrefetch();
    _prefetchStopRequested = false;
    _originalMaxCap = null;
    _seenRestrictedLinks.clear();
    _seenLinkWithTorrentId.clear();

    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      MainPageBridge.notifyAutoLaunchFailed('No Real Debrid API key');
      _showSnack(
        'Please add your Real Debrid API key in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    _showCachedPlaybackDialog();

    // Apply NSFW filter to cached torrents if enabled
    List<Torrent> torrentsToUse = cachedTorrents;
    if (applyNsfwFilter) {
      final beforeCount = cachedTorrents.length;
      torrentsToUse = cachedTorrents.where((torrent) {
        if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
          debugPrint(
            'DebrifyTV: Filtered cached NSFW torrent: ${torrent.name}',
          );
          return false;
        }
        return true;
      }).toList();
      if (beforeCount != torrentsToUse.length) {
        debugPrint(
          'DebrifyTV: NSFW filter on cached: $beforeCount → ${torrentsToUse.length} torrents',
        );
      }
    }

    _queue
      ..clear()
      ..addAll(List<Torrent>.from(torrentsToUse)..shuffle(Random()));
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
      debugPrint(
        'DebrifyTV: Cached requestMagicNext() queueSize=${_queue.length}',
      );
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
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (display ?? 'Debrify TV');
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
            'DebrifyTV: Cached trying torrent name="${item.name}" hash=${item.infohash}',
          );
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

            final unrestrict = await DebridService.unrestrictLink(
              apiKey,
              selectedLink,
            );
            final videoUrl = unrestrict['download'] as String?;
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint(
                'DebrifyTV: Cached success: unrestricted in ${elapsed}s',
              );
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
        MainPageBridge.notifyAutoLaunchFailed('No cached streams available');
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

      // Try to launch on Android TV first (for cached flow)
      final launchedOnTv = await _launchRealDebridOnAndroidTv(
        firstStream: first,
        requestNext: requestMagicNext,
        channelName: channelName,
        channelId: channelId,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
      );

      if (launchedOnTv) {
        // Successfully launched on Android TV
        debugPrint(
          'DebrifyTV: Cached flow - Real-Debrid playback started on Android TV',
        );
        // Prefetch will continue in background while TV player is active
        return;
      }

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      // Fall back to Flutter video player
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: firstUrl,
            title: firstTitle,
            startFromRandom: _startRandom,
            randomStartMaxPercent: _randomStartPercent,
            hideSeekbar: _hideSeekbar,
            showChannelName: _showChannelName,
            channelName: channelName,
            channelNumber: channelNumber,
            showVideoTitle: _showVideoTitle,
            hideOptions: _hideOptions,
            requestMagicNext: requestMagicNext,
            requestNextChannel:
                _channels.length > 1 &&
                    (_provider == _providerRealDebrid ||
                        _provider == _providerTorbox ||
                        _provider == _providerPikPak)
                ? _requestNextChannel
                : null,
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

  Future<bool> _launchTorboxOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) async {
    if (!_isAndroidTv) {
      return false;
    }
    final initialUrl = firstStream['url'] ?? '';
    if (initialUrl.isEmpty) {
      return false;
    }
    // Torbox native player already receives a prepared stream URL, so skip sending magnet
    // bundles—the binder payload stays small and launch succeeds.
    const List<Map<String, dynamic>> magnets = [];

    final title = (firstStream['title'] ?? '').trim();

    try {
      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      final launched = await AndroidTvPlayerBridge.launchTorboxPlayback(
        initialUrl: initialUrl,
        title: title.isEmpty ? 'Debrify TV' : title,
        magnets: magnets,
        requestNext: requestNext,
        requestChannelSwitch: _channels.length > 1 ? _requestNextChannel : null,
        requestChannelById: _channels.length > 1 ? _requestChannelById : null,
        onFinished: () async {
          AndroidTvPlayerBridge.clearTorboxProvider();
          if (!mounted) {
            return;
          }
          setState(() {
            _status = _queue.isEmpty
                ? ''
                : 'Queue has ${_queue.length} remaining';
          });
        },
        startFromRandom: _startRandom,
        randomStartMaxPercent: _randomStartPercent,
        hideSeekbar: _hideSeekbar,
        hideOptions: _hideOptions,
        showVideoTitle: _showVideoTitle,
        showChannelName: showChannelNameOverride ?? _showChannelName,
        channelName: channelName,
        channels: channelDirectory,
        currentChannelId: channelId ?? _currentWatchingChannelId,
        currentChannelNumber: channelNumber,
      );
      if (launched) {
        if (mounted) {
          setState(() {
            _status = 'Playing via Android TV';
          });
        }
        return true;
      }
    } catch (e) {
      debugPrint('DebrifyTV: Android TV bridge failed: $e');
    }

    AndroidTvPlayerBridge.clearTorboxProvider();
    return false;
  }

  /// Handle channel switching on Android TV - cycles to next channel with looping
  Future<Map<String, dynamic>?> _requestNextChannel() async {
    debugPrint('DebrifyTV: _requestNextChannel() called');

    if (_channels.isEmpty) {
      debugPrint('DebrifyTV: No channels available');
      return null;
    }

    int currentIndex = -1;
    if (_currentWatchingChannelId != null) {
      currentIndex = _channels.indexWhere(
        (c) => c.id == _currentWatchingChannelId,
      );
    }

    final int nextIndex = (currentIndex + 1) % _channels.length;
    final _DebrifyTvChannel targetChannel = _channels[nextIndex];

    debugPrint(
      'DebrifyTV: Switching from channel ${currentIndex + 1} to ${nextIndex + 1} (${targetChannel.name})',
    );

    return _switchToChannel(
      targetChannel,
      fallbackIndex: nextIndex,
      reason: 'next',
    );
  }

  Future<Map<String, dynamic>?> _requestChannelById(String channelId) async {
    debugPrint('DebrifyTV: _requestChannelById($channelId) called');

    if (_channels.isEmpty) {
      debugPrint('DebrifyTV: No channels available for direct selection');
      return null;
    }

    _DebrifyTvChannel? targetChannel;
    int discoveredIndex = -1;
    for (var i = 0; i < _channels.length; i++) {
      final channel = _channels[i];
      if (channel.id == channelId) {
        targetChannel = channel;
        discoveredIndex = i;
        break;
      }
    }

    if (targetChannel == null) {
      debugPrint('DebrifyTV: Channel id $channelId not found');
      return null;
    }

    if (_currentWatchingChannelId == targetChannel.id) {
      debugPrint(
        'DebrifyTV: Selected channel is already active; refreshing playback',
      );
    } else {
      debugPrint(
        'DebrifyTV: Switching directly to channel ${targetChannel.name}',
      );
    }

    return _switchToChannel(
      targetChannel,
      fallbackIndex: discoveredIndex >= 0 ? discoveredIndex : null,
      reason: 'direct',
    );
  }

  Future<Map<String, dynamic>?> _switchToChannel(
    _DebrifyTvChannel targetChannel, {
    int? fallbackIndex,
    String reason = 'direct',
  }) async {
    debugPrint(
      'DebrifyTV: _switchToChannel(${targetChannel.name}) reason=$reason',
    );

    final int computedIndex =
        fallbackIndex ??
        _channels.indexWhere((channel) => channel.id == targetChannel.id);
    final int targetChannelNumber = targetChannel.channelNumber > 0
        ? targetChannel.channelNumber
        : (computedIndex >= 0 ? computedIndex + 1 : 0);

    final cacheEntry = await _ensureCacheEntry(targetChannel.id);
    if (cacheEntry == null) {
      debugPrint(
        'DebrifyTV: Channel "${targetChannel.name}" has no cache entry',
      );
      return null;
    }
    if (!cacheEntry.isReady) {
      debugPrint(
        'DebrifyTV: Channel "${targetChannel.name}" cache not ready. Error: ${cacheEntry.errorMessage}',
      );
      return null;
    }
    if (cacheEntry.torrents.isEmpty) {
      debugPrint('DebrifyTV: Channel "${targetChannel.name}" has no torrents');
      return null;
    }

    debugPrint('DebrifyTV: Stopping old channel prefetcher...');
    await _stopPrefetch();
    debugPrint('DebrifyTV: Prefetcher stopped. Waiting for RD cooldown...');
    await Future.delayed(const Duration(seconds: 5));
    debugPrint('DebrifyTV: Cooldown complete. Proceeding with channel switch.');

    final previousChannelId = _currentWatchingChannelId;
    if (previousChannelId != null) {
      _channelCache.remove(previousChannelId);
      debugPrint(
        'DebrifyTV: Evicted cache entry for previous channel $previousChannelId',
      );
    }

    _seenRestrictedLinks.clear();
    _seenLinkWithTorrentId.clear();
    debugPrint('DebrifyTV: Cleared prefetch state');

    final keywords = await _getChannelKeywords(targetChannel.id);
    if (keywords.isEmpty) {
      debugPrint('DebrifyTV: Channel "${targetChannel.name}" has no keywords');
      if (_provider == _providerRealDebrid) {
        _startPrefetch();
      }
      return null;
    }

    final normalizedKeywords = _normalizedKeywords(keywords);
    final playbackSelection = _selectTorrentsForPlayback(
      cacheEntry,
      normalizedKeywords,
    );

    if (playbackSelection.isEmpty) {
      debugPrint('DebrifyTV: No torrents matched in selected channel');
      if (_provider == _providerRealDebrid) {
        _startPrefetch();
      }
      return null;
    }

    final List<Torrent> allTorrents = playbackSelection
        .map((cached) => cached.toTorrent())
        .toList();
    if (allTorrents.isEmpty) {
      debugPrint('DebrifyTV: No playable torrents resolved for channel');
      if (_provider == _providerRealDebrid) {
        _startPrefetch();
      }
      return null;
    }

    List<Torrent> filteredTorrents = allTorrents;
    if (_provider == _providerTorbox) {
      final apiKey = await StorageService.getTorboxApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('DebrifyTV: ❌ No Torbox API key configured');
        return null;
      }

      final List<Torrent> torboxCandidates = List<Torrent>.from(
        filteredTorrents,
      );
      torboxCandidates.shuffle(Random());

      int candidateCursor = 0;
      List<Torrent> cachedCandidates = <Torrent>[];
      try {
        while (candidateCursor < torboxCandidates.length &&
            cachedCandidates.isEmpty) {
          final _TorboxCacheWindowResult window = await _fetchTorboxCacheWindow(
            candidates: torboxCandidates,
            startIndex: candidateCursor,
            apiKey: apiKey,
          );
          candidateCursor = window.nextCursor;
          if (window.cachedTorrents.isNotEmpty) {
            cachedCandidates = window.cachedTorrents;
            break;
          }
          if (window.exhausted) {
            break;
          }
        }
      } catch (e) {
        debugPrint(
          'DebrifyTV: Torbox cache check failed during channel switch: $e',
        );
        return null;
      }

      if (cachedCandidates.isEmpty) {
        debugPrint(
          'DebrifyTV: Torbox channel has no cached torrents available',
        );
        return null;
      }

      filteredTorrents = cachedCandidates;
    }

    try {
      if (_provider == _providerRealDebrid) {
        debugPrint('DebrifyTV: Selected channel uses Real-Debrid provider');
        final apiKey = await StorageService.getApiKey();
        if (apiKey == null || apiKey.isEmpty) {
          debugPrint('DebrifyTV: ❌ No Real-Debrid API key configured');
          return null;
        }

        for (var index = 0; index < filteredTorrents.length; index++) {
          final candidate = filteredTorrents[index];
          final magnetLink = 'magnet:?xt=urn:btih:${candidate.infohash}';

          Map<String, dynamic> selection;
          try {
            selection = await DebridService.addTorrentToDebridPreferVideos(
              apiKey,
              magnetLink,
            );
          } catch (error) {
            debugPrint(
              'DebrifyTV: Real-Debrid rejected candidate ${candidate.infohash}: $error',
            );
            continue;
          }

          final rdLinks = (selection['links'] as List<dynamic>? ?? const [])
              .map((link) => link?.toString() ?? '')
              .where((link) => link.isNotEmpty)
              .toList();

          if (rdLinks.isEmpty) {
            debugPrint(
              'DebrifyTV: Real-Debrid returned no usable links for candidate ${candidate.infohash}',
            );
            continue;
          }

          final torrentId = selection['torrentId']?.toString() ?? '';
          List<String> newLinks = rdLinks
              .where((link) => !_seenRestrictedLinks.contains(link))
              .toList();
          if (newLinks.isEmpty) {
            newLinks = List<String>.from(rdLinks);
          }
          newLinks.shuffle(Random());
          final String selectedLink = newLinks.first;
          _seenRestrictedLinks.add(selectedLink);
          if (torrentId.isNotEmpty) {
            _seenLinkWithTorrentId.add('$torrentId|$selectedLink');
          }

          Map<String, dynamic> unrestrict;
          try {
            unrestrict = await DebridService.unrestrictLink(
              apiKey,
              selectedLink,
            );
          } catch (error) {
            debugPrint(
              'DebrifyTV: Real-Debrid unrestrict failed for candidate ${candidate.infohash}: $error',
            );
            continue;
          }

          final String? videoUrl = unrestrict['download'] as String?;
          if (videoUrl == null || videoUrl.isEmpty) {
            debugPrint(
              'DebrifyTV: Real-Debrid unrestrict returned empty URL for candidate ${candidate.infohash}',
            );
            continue;
          }

          String title = candidate.name;
          final uri = Uri.tryParse(videoUrl);
          if (uri != null && uri.pathSegments.isNotEmpty) {
            final inferred = Uri.decodeComponent(uri.pathSegments.last);
            if (inferred.isNotEmpty) {
              title = inferred;
            }
          }

          if (mounted) {
            final remaining = filteredTorrents.skip(index + 1).toList();
            setState(() {
              _currentWatchingChannelId = targetChannel.id;
              _queue
                ..clear()
                ..addAll(remaining);
            });
            _keywordsController.text = keywords.join(', ');
          }

          _startPrefetch();
          debugPrint(
            'DebrifyTV: Started Real-Debrid prefetcher for new channel',
          );
          debugPrint('DebrifyTV: Successfully got stream from channel: $title');

          return {
            'channelId': targetChannel.id,
            'channelName': targetChannel.name,
            'channelNumber': targetChannelNumber,
            'firstUrl': videoUrl,
            'firstTitle': title,
          };
        }

        debugPrint('DebrifyTV: All Real-Debrid candidates failed for channel');
        return null;
      }

      if (_provider == _providerTorbox) {
        final apiKey = await StorageService.getTorboxApiKey();
        if (apiKey == null || apiKey.isEmpty) {
          debugPrint('DebrifyTV: ❌ No Torbox API key configured');
          return null;
        }

        for (var index = 0; index < filteredTorrents.length; index++) {
          final candidate = filteredTorrents[index];

          final prepared = await _prepareTorboxTorrent(
            candidate: candidate,
            apiKey: apiKey,
            log: (message) => debugPrint(message),
          );

          if (prepared == null || prepared.streamUrl.isEmpty) {
            debugPrint(
              'DebrifyTV: Torbox preparation failed for candidate ${candidate.infohash}',
            );
            continue;
          }

          if (mounted) {
            final remaining = filteredTorrents.skip(index + 1).toList();
            setState(() {
              _currentWatchingChannelId = targetChannel.id;
              _queue
                ..clear()
                ..addAll(remaining);
              if (prepared.hasMore) {
                _queue.add(candidate);
              }
            });
            _keywordsController.text = keywords.join(', ');
          }

          debugPrint(
            'DebrifyTV: Torbox channel switch ready with stream ${prepared.title}',
          );
          return {
            'channelId': targetChannel.id,
            'channelName': targetChannel.name,
            'channelNumber': targetChannelNumber,
            'firstUrl': prepared.streamUrl,
            'firstTitle': prepared.title,
          };
        }

        debugPrint('DebrifyTV: All Torbox candidates failed for channel');
        return null;
      }

      if (_provider == _providerPikPak) {
        final pikpakAvailable = await PikPakTvService.instance.isAvailable();
        if (!pikpakAvailable) {
          debugPrint('DebrifyTV: PikPak not authenticated');
          return null;
        }

        for (var index = 0; index < filteredTorrents.length; index++) {
          final candidate = filteredTorrents[index];

          final prepared = await PikPakTvService.instance.prepareTorrent(
            infohash: candidate.infohash,
            torrentName: candidate.name,
            onLog: (message) => debugPrint('DebrifyTV/PikPak: $message'),
          );

          if (prepared == null) {
            debugPrint(
              'DebrifyTV: PikPak preparation failed for candidate ${candidate.infohash}',
            );
            continue;
          }

          if (mounted) {
            final remaining = filteredTorrents.skip(index + 1).toList();
            setState(() {
              _currentWatchingChannelId = targetChannel.id;
              _queue
                ..clear()
                ..addAll(remaining);
            });
            _keywordsController.text = keywords.join(', ');
          }

          debugPrint(
            'DebrifyTV: PikPak channel switch ready with stream ${prepared['title']}',
          );
          return {
            'channelId': targetChannel.id,
            'channelName': targetChannel.name,
            'channelNumber': targetChannelNumber,
            'firstUrl': prepared['url']!,
            'firstTitle': prepared['title']!,
          };
        }

        debugPrint('DebrifyTV: All PikPak candidates failed for channel');
        return null;
      }

      debugPrint(
        'DebrifyTV: Unsupported provider for channel switching: $_provider',
      );
      return null;
    } catch (e) {
      debugPrint('DebrifyTV: Error getting stream from channel: $e');
    }

    debugPrint('DebrifyTV: Channel switch failed');
    if (_provider == _providerRealDebrid) {
      _startPrefetch();
      debugPrint(
        'DebrifyTV: Restarted Real-Debrid prefetcher for current channel',
      );
    }
    return null;
  }

  int _resolveChannelNumber(_DebrifyTvChannel channel) {
    if (channel.channelNumber > 0) {
      return channel.channelNumber;
    }
    final int index = _channels.indexWhere(
      (element) => element.id == channel.id,
    );
    if (index >= 0) {
      return index + 1;
    }
    final int fallback = _channels.indexOf(channel);
    return fallback >= 0 ? fallback + 1 : 0;
  }

  List<Map<String, dynamic>> _androidTvChannelMetadata({
    String? activeChannelId,
  }) {
    if (_channels.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final String? highlightId = activeChannelId ?? _currentWatchingChannelId;
    final List<Map<String, dynamic>> payload = <Map<String, dynamic>>[];
    for (var i = 0; i < _channels.length; i++) {
      final channel = _channels[i];
      payload.add({
        'id': channel.id,
        'name': channel.name,
        'channelNumber': channel.channelNumber > 0
            ? channel.channelNumber
            : i + 1,
        'isCurrent': highlightId != null && channel.id == highlightId,
      });
    }
    return payload;
  }

  Future<bool> _launchRealDebridOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) async {
    debugPrint('DebrifyTV: _launchRealDebridOnAndroidTv() called');
    debugPrint('DebrifyTV: _isAndroidTv=$_isAndroidTv');

    if (!_isAndroidTv) {
      debugPrint('DebrifyTV: Not Android TV, skipping native launch');
      return false;
    }

    final initialUrl = firstStream['url'] ?? '';
    debugPrint(
      'DebrifyTV: initialUrl=${initialUrl.substring(0, initialUrl.length > 50 ? 50 : initialUrl.length)}...',
    );

    if (initialUrl.isEmpty) {
      debugPrint('DebrifyTV: Initial URL is empty, cannot launch');
      return false;
    }

    final title = (firstStream['title'] ?? '').trim();
    debugPrint('DebrifyTV: title="$title"');
    debugPrint(
      'DebrifyTV: Calling AndroidTvPlayerBridge.launchRealDebridPlayback()...',
    );

    try {
      final bool canSwitchChannels =
          _currentWatchingChannelId != null &&
          _channels.length > 1 &&
          _provider == _providerRealDebrid;

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      final launched = await AndroidTvPlayerBridge.launchRealDebridPlayback(
        initialUrl: initialUrl,
        title: title.isEmpty ? 'Debrify TV' : title,
        channelName: channelName,
        requestNext: requestNext,
        requestChannelSwitch: canSwitchChannels ? _requestNextChannel : null,
        requestChannelById: canSwitchChannels ? _requestChannelById : null,
        onFinished: () async {
          debugPrint('DebrifyTV: Android TV playback finished callback');

          // Stop prefetcher when exiting player
          await _stopPrefetch();
          debugPrint('DebrifyTV: Stopped prefetcher on player exit');

          AndroidTvPlayerBridge.clearStreamProvider();
          _currentWatchingChannelId = null; // Clear channel tracking
          if (!mounted) return;
          setState(() {
            _status = _queue.isEmpty
                ? ''
                : 'Queue has ${_queue.length} remaining';
          });
        },
        startFromRandom: _startRandom,
        randomStartMaxPercent: _randomStartPercent,
        hideSeekbar: _hideSeekbar,
        hideOptions: _hideOptions,
        showVideoTitle: _showVideoTitle,
        showChannelName: showChannelNameOverride ?? _showChannelName,
        channels: channelDirectory,
        currentChannelId: channelId ?? _currentWatchingChannelId,
        currentChannelNumber: channelNumber,
      );

      debugPrint(
        'DebrifyTV: AndroidTvPlayerBridge.launchRealDebridPlayback() returned: $launched',
      );

      if (launched) {
        if (mounted) {
          setState(() {
            _status = 'Playing via Android TV';
          });
        }
        debugPrint(
          'DebrifyTV: ✅ Successfully launched Real-Debrid on Android TV',
        );
        return true;
      } else {
        debugPrint(
          'DebrifyTV: ❌ AndroidTvPlayerBridge returned false - launch failed',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('DebrifyTV: ❌ Exception during Android TV launch: $e');
      debugPrint('DebrifyTV: Stack trace: $stackTrace');
    }

    AndroidTvPlayerBridge.clearStreamProvider();
    debugPrint('DebrifyTV: Falling back to Flutter player');
    return false;
  }

  Future<void> _watchTorboxWithCachedTorrents(
    List<Torrent> cachedTorrents, {
    String? channelName,
    String? channelId,
    int? channelNumber,
  }) async {
    if (cachedTorrents.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No cached torrents');
      _showSnack(
        'Cached channel has no torrents yet. Please wait a moment.',
        color: Colors.orange,
      );
      return;
    }

    final List<Map<String, dynamic>>? channelDirectory = _channels.isNotEmpty
        ? _androidTvChannelMetadata(
            activeChannelId: channelId ?? _currentWatchingChannelId,
          )
        : null;

    void log(String message) {
      debugPrint('DebrifyTV: $message');
    }

    final integrationEnabled =
        await StorageService.getTorboxIntegrationEnabled();
    if (!integrationEnabled) {
      _showSnack(
        'Enable Torbox in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No Torbox API key');
      _showSnack(
        'Please add your Torbox API key in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    _showCachedPlaybackDialog();

    final List<Torrent> candidatePool = List<Torrent>.from(cachedTorrents);
    candidatePool.shuffle(Random());

    if (mounted) {
      setState(() {
        _status = 'Checking Torbox cache...';
        _isBusy = true;
      });
    }

    int candidateCursor = 0;

    Future<bool> populateQueue() async {
      while (true) {
        if (candidateCursor >= candidatePool.length) {
          return false;
        }
        final _TorboxCacheWindowResult window = await _fetchTorboxCacheWindow(
          candidates: candidatePool,
          startIndex: candidateCursor,
          apiKey: apiKey,
        );
        candidateCursor = window.nextCursor;
        if (window.cachedTorrents.isEmpty) {
          if (window.exhausted) {
            return false;
          }
          continue;
        }
        _queue
          ..clear()
          ..addAll(window.cachedTorrents);
        _lastQueueSize = _queue.length;
        _lastSearchAt = DateTime.now();
        if (mounted) {
          setState(() {
            _status = _queue.isEmpty
                ? ''
                : 'Queue has ${_queue.length} remaining';
          });
        }
        log('✅ Cached Torbox batch ready with ${_queue.length} item(s)');
        return true;
      }
    }

    bool seeded;
    try {
      seeded = await populateQueue();
    } catch (e) {
      _closeProgressDialog();
      _showSnack(
        'Torbox cache check failed: ${_formatTorboxError(e)}',
        color: Colors.orange,
      );
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
      return;
    }

    if (!seeded) {
      _closeProgressDialog();
      _showSnack(
        'Cached torrents are no longer available on Torbox. Please refresh the channel.',
        color: Colors.orange,
      );
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
      return;
    }

    Future<Map<String, String>?> requestTorboxNext() async {
      while (true) {
        if (_queue.isEmpty) {
          bool replenished;
          try {
            replenished = await populateQueue();
          } catch (e) {
            _closeProgressDialog();
            _showSnack(
              'Torbox cache check failed: ${_formatTorboxError(e)}',
              color: Colors.orange,
            );
            if (mounted) {
              setState(() {
                _isBusy = false;
              });
            }
            return null;
          }
          if (!replenished) {
            break;
          }
        }
        if (_queue.isEmpty) {
          break;
        }

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
          candidatePool.add(next);
        }
        return {'url': prepared.streamUrl, 'title': prepared.title};
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
        MainPageBridge.notifyAutoLaunchFailed(
          'No cached Torbox streams available',
        );
        _showSnack(
          'No cached Torbox streams are playable. Try refreshing the channel.',
          color: Colors.orange,
        );
        return;
      }

      if (!mounted) return;
      _closeProgressDialog();

      final launchedOnTv = await _launchTorboxOnAndroidTv(
        firstStream: first,
        requestNext: requestTorboxNext,
        channelName: channelName,
        channelId: channelId,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
      );
      if (launchedOnTv) {
        return;
      }

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: first['url'] ?? '',
            title: first['title'] ?? 'Debrify TV',
            startFromRandom: _startRandom,
            randomStartMaxPercent: _randomStartPercent,
            hideSeekbar: _hideSeekbar,
            showChannelName: _showChannelName,
            channelName: channelName,
            channelNumber: channelNumber,
            showVideoTitle: _showVideoTitle,
            hideOptions: _hideOptions,
            requestMagicNext: requestTorboxNext,
            requestNextChannel:
                _channels.length > 1 &&
                    (_provider == _providerRealDebrid ||
                        _provider == _providerTorbox ||
                        _provider == _providerPikPak)
                ? _requestNextChannel
                : null,
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

  Future<void> _watchPikPakWithCachedTorrents(
    List<Torrent> cachedTorrents, {
    String? channelName,
    String? channelId,
    int? channelNumber,
  }) async {
    if (cachedTorrents.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No cached torrents');
      _showSnack(
        'Cached channel has no torrents yet. Please wait a moment.',
        color: Colors.orange,
      );
      return;
    }

    final List<Map<String, dynamic>>? channelDirectory = _channels.isNotEmpty
        ? _androidTvChannelMetadata(
            activeChannelId: channelId ?? _currentWatchingChannelId,
          )
        : null;

    void log(String message) {
      debugPrint('DebrifyTV/PikPak: $message');
    }

    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    if (!pikpakAvailable) {
      _showSnack(
        'Please login to PikPak in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    _showCachedPlaybackDialog();

    final List<Torrent> candidatePool = List<Torrent>.from(cachedTorrents);
    candidatePool.shuffle(Random());

    if (mounted) {
      setState(() {
        _status = 'Preparing PikPak stream...';
        _isBusy = true;
        _queue
          ..clear()
          ..addAll(candidatePool);
      });
    }

    Future<Map<String, String>?> requestPikPakNext() async {
      while (_queue.isNotEmpty) {
        final next = _queue.removeAt(0);
        if (next is! Torrent) {
          continue;
        }

        log('Trying torrent: ${next.name}');
        final prepared = await PikPakTvService.instance.prepareTorrent(
          infohash: next.infohash,
          torrentName: next.name,
          onLog: log,
        );

        if (prepared == null) {
          log('Torrent not ready, trying next...');
          continue;
        }

        return {
          'url': prepared['url']!,
          'title': prepared['title']!,
          'provider': prepared['provider'] ?? 'pikpak',
          'pikpakFileId': prepared['pikpakFileId'] ?? '',
        };
      }
      return null;
    }

    try {
      final first = await requestPikPakNext();
      if (first == null) {
        _closeProgressDialog();
        if (!mounted) return;
        setState(() {
          _status = 'No playable PikPak streams found. Try refreshing.';
          _isBusy = false;
        });
        MainPageBridge.notifyAutoLaunchFailed('No PikPak streams available');
        _showSnack(
          'No PikPak streams are playable. Try refreshing the channel.',
          color: Colors.orange,
        );
        return;
      }

      if (!mounted) return;
      _closeProgressDialog();

      // Try Android TV native player first
      final launchedOnTv = await _launchPikPakOnAndroidTv(
        firstStream: first,
        requestNext: requestPikPakNext,
        channelName: channelName,
        channelId: channelId,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
      );
      if (launchedOnTv) {
        return;
      }

      // Fall back to Flutter video player (MediaKit)
      MainPageBridge.notifyPlayerLaunching();

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: first['url'] ?? '',
            title: first['title'] ?? 'Debrify TV',
            startFromRandom: _startRandom,
            randomStartMaxPercent: _randomStartPercent,
            hideSeekbar: _hideSeekbar,
            showChannelName: _showChannelName,
            channelName: channelName,
            channelNumber: channelNumber,
            showVideoTitle: _showVideoTitle,
            hideOptions: _hideOptions,
            requestMagicNext: requestPikPakNext,
            requestNextChannel:
                _channels.length > 1 &&
                    (_provider == _providerRealDebrid ||
                        _provider == _providerTorbox ||
                        _provider == _providerPikPak)
                ? _requestNextChannel
                : null,
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

  Future<bool> _launchPikPakOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) async {
    if (!_isAndroidTv) {
      return false;
    }
    final initialUrl = firstStream['url'] ?? '';
    if (initialUrl.isEmpty) {
      return false;
    }

    final title = (firstStream['title'] ?? '').trim();

    try {
      MainPageBridge.notifyPlayerLaunching();

      // Reuse Torbox bridge method - it works for any stream URL
      final launched = await AndroidTvPlayerBridge.launchTorboxPlayback(
        initialUrl: initialUrl,
        title: title.isEmpty ? 'Debrify TV' : title,
        magnets: const [],
        requestNext: requestNext,
        requestChannelSwitch: _channels.length > 1 ? _requestNextChannel : null,
        requestChannelById: _channels.length > 1 ? _requestChannelById : null,
        onFinished: () async {
          AndroidTvPlayerBridge.clearTorboxProvider();
          if (!mounted) {
            return;
          }
          setState(() {
            _status = _queue.isEmpty
                ? ''
                : 'Queue has ${_queue.length} remaining';
          });
        },
        startFromRandom: _startRandom,
        randomStartMaxPercent: _randomStartPercent,
        hideSeekbar: _hideSeekbar,
        hideOptions: _hideOptions,
        showVideoTitle: _showVideoTitle,
        showChannelName: showChannelNameOverride ?? _showChannelName,
        channelName: channelName,
        channels: channelDirectory,
        currentChannelId: channelId ?? _currentWatchingChannelId,
        currentChannelNumber: channelNumber,
      );
      if (launched) {
        if (mounted) {
          setState(() {
            _status = 'Playing via Android TV';
          });
        }
        return true;
      }
    } catch (e) {
      debugPrint('DebrifyTV: Android TV bridge failed for PikPak: $e');
    }

    AndroidTvPlayerBridge.clearTorboxProvider();
    return false;
  }

  void _showChannelCreationDialog(String channelName, {int? countdownSeconds}) {
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
            countdownSeconds: countdownSeconds,
            onReady: (dialogCtx) {
              _progressSheetContext = dialogCtx;
            },
          );
        },
        transitionBuilder: (ctx, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          );
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: curved, child: child),
          );
        },
      );
    });
  }

  void _showCachedPlaybackDialog() {
    if (_progressOpen || !mounted) {
      return;
    }

    // Skip showing dialog during auto-launch (overlay handles loading UI)
    if (MainPage.isAutoLaunchShowingOverlay) {
      debugPrint(
        'DebrifyTVScreen: Skipping progress dialog during auto-launch',
      );
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
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          );
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: curved, child: child),
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
        const SnackBar(
          content: Text(
            'Please add your Real Debrid API key in Settings first!',
          ),
        ),
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
          final result = await DebridService.addTorrentToDebridPreferVideos(
            apiKey,
            magnetLink,
          );
          final videoUrl = result['downloadLink'] as String?;
          if (videoUrl != null && videoUrl.isNotEmpty) {
            if (!mounted) return;
            setState(() {
              _status = 'Playing: ${next.name}';
            });

            // Hide auto-launch overlay before launching player
            MainPageBridge.notifyPlayerLaunching();

            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VideoPlayerScreen(
                  videoUrl: videoUrl,
                  title: next.name,
                  startFromRandom: _quickStartRandom,
                  randomStartMaxPercent: _quickRandomStartPercent,
                  hideSeekbar: _quickHideSeekbar,
                  showChannelName: _quickShowChannelName,
                  channelName: null,
                  channelNumber: null,
                  showVideoTitle: _quickShowVideoTitle,
                  hideOptions: _quickHideOptions,
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
              content: Text(
                'All torrents failed to process. Try different keywords or check your internet connection.',
              ),
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
    // Use TV-optimized grid layout on Android TV, mobile layout otherwise
    return _isAndroidTv
        ? _buildTvGridLayout(bottomInset)
        : _buildChannelsTab(bottomInset);
  }

  // TV-optimized Grid Layout (Apple TV Style)
  Widget _buildTvGridLayout(double bottomInset) {
    final searchTerm = _channelSearchTerm.trim().toLowerCase();
    final filteredChannels = searchTerm.isEmpty
        ? _channels
        : _channels
              .where(
                (channel) => channel.name.toLowerCase().contains(searchTerm),
              )
              .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(40, 24, 40, 24 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top bar with compact action buttons - no title
          SizedBox(
            height: 36, // Fixed height for button bar
            child: Row(
              children: [
                // Quick Play button
                _TvCompactButton(
                  onPressed: _isBusy ? null : _showQuickPlayDialog,
                  icon: Icons.play_arrow_rounded,
                  label: 'Quick Play',
                  backgroundColor: const Color(0xFFE50914),
                ),
                const SizedBox(width: 12),
                // Import button
                _TvCompactButton(
                  onPressed: _isBusy ? null : _handleImportChannels,
                  icon: Icons.cloud_download_rounded,
                  label: 'Import',
                  backgroundColor: const Color(0xFF2563EB),
                ),
                const SizedBox(width: 12),
                // Add Channel button
                _TvCompactButton(
                  onPressed: _isBusy ? null : _handleAddChannel,
                  icon: Icons.add_rounded,
                  label: 'Add',
                  backgroundColor: const Color(0xFF10B981),
                ),
                const SizedBox(width: 12),
                // Delete All button
                _TvCompactButton(
                  onPressed: _isBusy || _channels.isEmpty
                      ? null
                      : _handleDeleteAllChannels,
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete All',
                  backgroundColor: Colors.redAccent,
                ),
                const Spacer(),
                // Search button
                _TvCompactButton(
                  onPressed: () {
                    setState(() {
                      _showSearchBar = !_showSearchBar;
                      if (_showSearchBar) {
                        // Focus on search field when showing
                        Future.delayed(const Duration(milliseconds: 100), () {
                          _channelSearchFocusNode.requestFocus();
                        });
                      } else {
                        // Clear search when hiding
                        _channelSearchController.clear();
                        _channelSearchTerm = '';
                      }
                    });
                  },
                  icon: Icons.search_rounded,
                  label: null, // Icon only for search
                  backgroundColor: const Color(0xFF9333EA), // Purple color
                ),
                const SizedBox(width: 12),
                // Settings button
                _TvCompactButton(
                  onPressed: _showGlobalSettingsDialog,
                  icon: Icons.settings_rounded,
                  label: null, // Icon only for settings
                  backgroundColor: const Color(0xFF64748B), // Slate gray color
                ),
              ],
            ),
          ),
          // Search field for TV (only show when toggled)
          if (_showSearchBar) ...[
            const SizedBox(height: 16),
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: Colors.white.withOpacity(0.5),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      focusNode: _channelSearchFocusNode,
                      controller: _channelSearchController,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'Search channels...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _channelSearchTerm = value;
                        });
                      },
                    ),
                  ),
                  if (_channelSearchTerm.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        Icons.clear_rounded,
                        color: Colors.white.withOpacity(0.5),
                        size: 20,
                      ),
                      onPressed: () {
                        _channelSearchController.clear();
                        setState(() {
                          _channelSearchTerm = '';
                        });
                      },
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Channel grid
          Expanded(
            child: filteredChannels.isEmpty
                ? _buildTvEmptyState()
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4, // 4 columns for TV
                          mainAxisSpacing: 24,
                          crossAxisSpacing: 24,
                          childAspectRatio:
                              1.5, // Width:Height ratio for consistent sizing
                        ),
                    itemCount:
                        filteredChannels.length +
                        1, // +1 for "Add Channel" card
                    itemBuilder: (context, index) {
                      if (index == filteredChannels.length) {
                        // "Add Channel" card at the end
                        return _buildTvAddChannelCard();
                      }
                      final channel = filteredChannels[index];
                      return _buildTvChannelCard(channel);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // TV Empty State
  Widget _buildTvEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.tv_rounded,
            size: 120,
            color: Colors.white.withOpacity(0.2),
          ),
          const SizedBox(height: 24),
          const Text(
            'No channels yet',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Import channels or create your first channel to get started',
            style: TextStyle(fontSize: 16, color: Colors.white54),
          ),
          const SizedBox(height: 32),
          _TvFocusableButton(
            onPressed: _handleAddChannel,
            icon: Icons.add_rounded,
            label: 'Add Channel',
            backgroundColor: const Color(0xFFE50914),
            width: 200,
          ),
        ],
      ),
    );
  }

  // TV Channel Card (Grid item)
  Widget _buildTvChannelCard(_DebrifyTvChannel channel) {
    print('[TV] Building TV channel card for: ${channel.name}');
    return _TvFocusableCard(
      onPressed: () {
        print('[TV] Card onPressed for channel: ${channel.name}');
        _watchChannel(channel);
      },
      onLongPress: () {
        print(
          '[TV] Card onLongPress callback triggered for channel: ${channel.name}',
        );
        _showTvChannelOptionsMenu(channel);
      },
      showLongPressHint: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Channel number badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE50914),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'CH ${channel.channelNumber > 0 ? channel.channelNumber : _channels.indexOf(channel) + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Channel name - centered
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              channel.name.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.2,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // TV Channel Options Menu (Edit/Delete)
  Future<void> _showTvChannelOptionsMenu(_DebrifyTvChannel channel) async {
    print('[TV] _showTvChannelOptionsMenu called for channel: ${channel.name}');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        print('[TV] Building options dialog for channel: ${channel.name}');
        return AlertDialog(
          backgroundColor: const Color(0xFF0F0F0F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('${channel.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Edit button
              _TvFocusableButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _handleEditChannel(channel);
                },
                icon: Icons.edit_rounded,
                label: 'Edit Channel',
                backgroundColor: const Color(0xFF2563EB),
              ),
              const SizedBox(height: 16),
              // Share as Magnet Link button
              _TvFocusableButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _handleShareChannelAsMagnet(channel);
                },
                icon: Icons.share_rounded,
                label: 'Share as Magnet Link',
                backgroundColor: const Color(0xFF10B981),
              ),
              const SizedBox(height: 16),
              // Delete button
              _TvFocusableButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _handleDeleteChannel(channel);
                },
                icon: Icons.delete_outline_rounded,
                label: 'Delete Channel',
                backgroundColor: Colors.red,
              ),
            ],
          ),
        );
      },
    );
  }

  // TV "Add Channel" Card
  Widget _buildTvAddChannelCard() {
    return _TvFocusableCard(
      onPressed: _handleAddChannel,
      child: SizedBox(
        height: double.infinity, // Ensures consistent height
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_rounded,
                size: 32,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Add Channel',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard({
    required _SettingsScope scope,
    required bool includeNsfwToggle,
    required String title,
    StateSetter? dialogSetState,
  }) {
    final bool isQuickScope = scope == _SettingsScope.quickPlay;

    final bool startRandom = isQuickScope ? _quickStartRandom : _startRandom;
    void setStartRandom(bool value) {
      setState(() {
        if (isQuickScope) {
          _quickStartRandom = value;
        } else {
          _startRandom = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(StorageService.saveDebrifyTvStartRandom(value));
      }
    }

    final int randomStartPercent = isQuickScope
        ? _quickRandomStartPercent
        : _randomStartPercent;
    void setRandomStartPercent(int value) {
      setState(() {
        if (isQuickScope) {
          _quickRandomStartPercent = value;
        } else {
          _randomStartPercent = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(StorageService.saveDebrifyTvRandomStartPercent(value));
      }
    }

    final bool showChannelName = isQuickScope
        ? _quickShowChannelName
        : _showChannelName;
    void setShowChannelName(bool value) {
      setState(() {
        if (isQuickScope) {
          _quickShowChannelName = value;
        } else {
          _showChannelName = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(StorageService.saveDebrifyTvShowChannelName(value));
      }
    }

    final bool showVideoTitle = isQuickScope
        ? _quickShowVideoTitle
        : _showVideoTitle;
    void setShowVideoTitle(bool value) {
      setState(() {
        if (isQuickScope) {
          _quickShowVideoTitle = value;
        } else {
          _showVideoTitle = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(StorageService.saveDebrifyTvShowVideoTitle(value));
      }
    }

    // Hardcoded to false - no longer changeable
    const bool hideOptions = false;
    void setHideOptions(bool value) {
      // No-op: hideOptions is now hardcoded to false
      // Keep function for compatibility but it doesn't do anything
    }

    // Hardcoded to false - no longer changeable
    const bool hideBackButton = false;
    void setHideBackButton(bool value) {
      // No-op: hideBackButton is now hardcoded to false
      // Keep function for compatibility but it doesn't do anything
    }

    return ConstrainedBox(
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
              children: [
                const Icon(
                  Icons.settings_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Content provider',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _providerChoiceChips(scope, dialogSetState: dialogSetState),
            const SizedBox(height: 16),
            _SwitchRow(
              title: 'Start from random timestamp',
              subtitle: 'Each Debrify TV video starts at a random point',
              value: startRandom,
              onChanged: (v) => setStartRandom(v),
            ),
            if (startRandom) ...[
              const SizedBox(height: 8),
              _RandomStartSlider(
                value: randomStartPercent,
                isAndroidTv: _isAndroidTv,
                onChanged: (next) => setRandomStartPercent(next),
                onChangeEnd: isQuickScope
                    ? null
                    : (next) =>
                          StorageService.saveDebrifyTvRandomStartPercent(next),
              ),
            ],
            // Removed Hide all options and Hide back button settings
            // These are now hardcoded to false (visible by default)
            if (includeNsfwToggle && isQuickScope) ...[
              const SizedBox(height: 8),
              _SwitchRow(
                title: 'Avoid NSFW content',
                subtitle:
                    'Filter adult/inappropriate torrents • Best effort, not 100% accurate',
                value: _quickAvoidNsfw,
                onChanged: (v) {
                  setState(() {
                    _quickAvoidNsfw = v;
                  });
                  dialogSetState?.call(() {});
                },
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final defaultProvider = _determineDefaultProvider(
                    null,
                    _rdAvailable,
                    _torboxAvailable,
                    _pikpakAvailable,
                  );

                  setState(() {
                    if (isQuickScope) {
                      _quickStartRandom = true;
                      _quickRandomStartPercent = _randomStartPercentDefault;
                      _quickHideSeekbar = true;
                      _quickShowChannelName = true;
                      _quickShowVideoTitle = true;
                      _quickHideOptions = false; // Hardcoded to false
                      _quickHideBackButton = false; // Hardcoded to false
                      _quickAvoidNsfw = true;
                      _quickProvider = defaultProvider;
                    } else {
                      _startRandom = true;
                      _randomStartPercent = _randomStartPercentDefault;
                      _hideSeekbar = true;
                      _showChannelName = true;
                      _showVideoTitle = true;
                      _hideOptions = false; // Hardcoded to false
                      _hideBackButton = false; // Hardcoded to false
                      _provider = defaultProvider;
                    }
                  });
                  dialogSetState?.call(() {});

                  if (!isQuickScope) {
                    await StorageService.saveDebrifyTvStartRandom(true);
                    await StorageService.saveDebrifyTvHideSeekbar(true);
                    await StorageService.saveDebrifyTvShowChannelName(true);
                    await StorageService.saveDebrifyTvShowVideoTitle(true);
                    // No longer saving hideOptions and hideBackButton - they're hardcoded to false
                    await StorageService.saveDebrifyTvProvider(defaultProvider);
                  }

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
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              double horizontal = 20;
              double vertical = 14;
              double iconEdge = 46;
              double gapMain = 12;
              double gapActions = 8;

              if (width < 620) {
                horizontal = 18;
              }
              if (width < 560) {
                horizontal = 16;
                gapMain = 10;
              }
              if (width < 520) {
                horizontal = 14;
                vertical = 12;
                iconEdge = 42;
                gapActions = 6;
              }
              if (width < 470) {
                horizontal = 12;
                vertical = 10;
                iconEdge = 40;
                gapMain = 8;
                gapActions = 4;
              }
              if (width < 430) {
                horizontal = 10;
                vertical = 9;
                iconEdge = 38;
              }
              if (width < 390) {
                horizontal = 8;
                vertical = 8;
                iconEdge = 36;
                gapMain = 6;
              }

              final buttonPadding = EdgeInsets.symmetric(
                horizontal: horizontal,
                vertical: vertical,
              );
              final iconSize = Size.square(iconEdge);

              final leftRow = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: _isBusy ? null : _showQuickPlayDialog,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Quick Play'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914),
                      foregroundColor: Colors.white,
                      padding: buttonPadding,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  SizedBox(width: gapMain),
                  FilledButton.icon(
                    onPressed: _isBusy ? null : _handleImportChannels,
                    icon: const Icon(Icons.cloud_download_rounded),
                    label: const Text('Import'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: buttonPadding,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              );

              final actionsRow = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filled(
                    onPressed: _handleAddChannel,
                    icon: const Icon(Icons.add_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.1),
                      foregroundColor: Colors.white,
                      minimumSize: iconSize,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    tooltip: 'Add Channel',
                  ),
                  SizedBox(width: gapActions),
                  IconButton.filled(
                    onPressed: _isBusy || _channels.isEmpty
                        ? null
                        : _handleDeleteAllChannels,
                    icon: const Icon(Icons.delete_outline_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.08),
                      foregroundColor: Colors.redAccent,
                      minimumSize: iconSize,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    tooltip: 'Delete all channels',
                  ),
                  SizedBox(width: gapActions),
                  IconButton.filled(
                    onPressed: _showGlobalSettingsDialog,
                    icon: const Icon(Icons.settings_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.08),
                      foregroundColor: Colors.white70,
                      minimumSize: iconSize,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    tooltip: 'Global settings',
                  ),
                ],
              );

              return Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: leftRow,
                      ),
                    ),
                  ),
                  SizedBox(width: gapMain),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: actionsRow,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _channelSearchController,
            focusNode: _isAndroidTv ? _channelSearchFocusNode : null,
            onChanged: (value) {
              setState(() {
                _channelSearchTerm = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search channels...',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Colors.white60,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 24),
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

  Future<void> _showQuickPlayDialog() async {
    if (_isBusy) {
      return;
    }

    bool avoidNsfw = _quickAvoidNsfw;
    String? error;
    // Create a separate controller for Quick Play to avoid sharing state with edit dialog
    final TextEditingController controller = TextEditingController();
    final FocusNode keywordFocusNode = FocusNode(
      debugLabel: 'QuickPlayKeywordsField',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        final focusContext = node.context;
        if (focusContext == null) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown) {
          FocusScope.of(focusContext).nextFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          FocusScope.of(focusContext).previousFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F0F0F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Quick Play'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      focusNode: keywordFocusNode,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        labelText: 'Keywords',
                        hintText: 'Comma separated keywords',
                      ),
                      onChanged: (_) {
                        if (error != null) {
                          setDialogState(() => error = null);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFFE50914),
                      title: const Text('Avoid NSFW content'),
                      subtitle: const Text(
                        'Applies a best-effort filter while searching',
                      ),
                      value: avoidNsfw,
                      onChanged: (value) {
                        setDialogState(() => avoidNsfw = value);
                      },
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final keywords = controller.text.trim();
                    if (keywords.isEmpty) {
                      setDialogState(
                        () => error = 'Enter one or more keywords to continue.',
                      );
                      return;
                    }

                    if (mounted) {
                      setState(() {
                        _quickStartRandom = _startRandom;
                        _quickRandomStartPercent = _randomStartPercent;
                        _quickHideSeekbar = _hideSeekbar;
                        _quickShowChannelName = _showChannelName;
                        _quickShowVideoTitle = _showVideoTitle;
                        _quickHideOptions = false; // Always false now
                        _quickHideBackButton = false; // Always false now
                        _quickAvoidNsfw = avoidNsfw;
                        _quickProvider = _provider;
                      });
                      // Copy keywords from Quick Play controller to main controller for _watch()
                      _keywordsController.text = keywords;
                    }

                    Navigator.of(dialogContext).pop();
                    await _watch();
                  },
                  child: const Text('Play'),
                ),
              ],
            );
          },
        );
      },
    );

    keywordFocusNode.dispose();
    controller.dispose();
  }

  Future<void> _showGlobalSettingsDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF0F0F0F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildSettingsCard(
                  scope: _SettingsScope.channels,
                  includeNsfwToggle: false,
                  title: 'Global settings',
                  dialogSetState: setDialogState,
                ),
              ),
            );
          },
        );
      },
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
    final cacheEntry = _channelCache[channel.id];
    final int cachedCount = cacheEntry?.torrents.length ?? 0;
    final String? channelNumberLabel = channel.channelNumber > 0
        ? 'Channel ${channel.channelNumber.toString().padLeft(2, '0')}'
        : null;

    final gestureKey = ValueKey('channel-card-${channel.id}');

    final cardContent = Container(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    if (channelNumberLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        channelNumberLabel,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _isBusy ? null : () => _watchChannel(channel),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Icon(Icons.play_arrow_rounded),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Edit channel',
                onPressed: () => _handleEditChannel(channel),
                icon: const Icon(Icons.edit_rounded, color: Colors.white70),
              ),
              IconButton(
                tooltip: 'Delete channel',
                onPressed: () => _handleDeleteChannel(channel),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (cacheEntry != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
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
                          : 'Cache will refresh on edit.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    Widget interactive = InkWell(
      key: gestureKey,
      borderRadius: BorderRadius.circular(16),
      onTap: _isBusy ? null : () => _watchChannel(channel),
      child: cardContent,
    );

    if (_isAndroidTv) {
      interactive = _FocusHighlightWrapper(
        enabled: true,
        borderRadius: BorderRadius.circular(20),
        debugLabel: 'debrify-tv-channel-card-${channel.id}',
        child: interactive,
      );
    }

    return interactive;
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
      return {'url': streamUrl, 'title': resolvedTitle};
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
        .where(
          (entry) => !_seenLinkWithTorrentId.contains(
            '${currentTorrent.id}|${entry.file.id}',
          ),
        )
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
      final entry = _TorboxPlayableEntry(file: file, title: title, info: info);
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
        : (info.title?.trim().isNotEmpty == true
              ? info.title!.trim()
              : fallback);
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

  String _formatImportError(Object error) {
    if (error is FormatException) {
      return error.message;
    }
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
    final end = _queue.length < _lookaheadWindow
        ? _queue.length
        : _lookaheadWindow;
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
    final end = _queue.length < _lookaheadWindow
        ? _queue.length
        : _lookaheadWindow;
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
      final result = await DebridService.addTorrentToDebridPreferVideos(
        _activeApiKey!,
        magnetLink,
      );
      final String torrentId = result['torrentId'] as String? ?? '';
      final List<dynamic> rdLinks =
          (result['links'] as List<dynamic>? ?? const []);

      if (rdLinks.isEmpty) {
        // Nothing ready; move to tail to retry later
        if (idx < _queue.length && identical(_queue[idx], item)) {
          _queue.removeAt(idx);
          _queue.add(item);
        }
        debugPrint(
          'MagicTV: Prefetch: no links; moved torrent to tail idx=$idx',
        );
        return;
      }

      // Convert this queue slot to rd_restricted using first link
      final headLinkCandidates = rdLinks
          .map((link) => link?.toString() ?? '')
          .where(
            (link) => link.isNotEmpty && !_seenRestrictedLinks.contains(link),
          )
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

class _TorboxCacheWindowResult {
  final List<Torrent> cachedTorrents;
  final int nextCursor;
  final bool exhausted;

  const _TorboxCacheWindowResult({
    required this.cachedTorrents,
    required this.nextCursor,
    required this.exhausted,
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

  const _CachedLoadingDialog({required this.onReady});

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

class _ChannelCreationDialog extends StatefulWidget {
  final String channelName;
  final int? countdownSeconds;
  final void Function(BuildContext context) onReady;

  const _ChannelCreationDialog({
    required this.channelName,
    this.countdownSeconds,
    required this.onReady,
  });

  @override
  State<_ChannelCreationDialog> createState() => _ChannelCreationDialogState();
}

class _ChannelCreationDialogState extends State<_ChannelCreationDialog> {
  Timer? _countdownTimer;
  int? _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.countdownSeconds;
    if (_remainingSeconds != null && _remainingSeconds! > 0) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          final next = (_remainingSeconds ?? 0) - 1;
          if (next <= 0) {
            _remainingSeconds = 0;
            timer.cancel();
          } else {
            _remainingSeconds = next;
          }
        });
      });
    } else if (_remainingSeconds != null && _remainingSeconds! <= 0) {
      _remainingSeconds = 0;
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onReady(context);
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
              'Building "${widget.channelName}"',
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
            if (widget.countdownSeconds != null) ...[
              const SizedBox(height: 12),
              Text(
                _remainingSeconds != null && _remainingSeconds! > 0
                    ? 'About ${_remainingSeconds!}s remaining…'
                    : 'Taking longer than usual…',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
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
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white70,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusHighlightWrapper extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final bool enabled;
  final String debugLabel;

  const _FocusHighlightWrapper({
    required this.child,
    required this.borderRadius,
    required this.debugLabel,
    this.enabled = false,
  });

  @override
  State<_FocusHighlightWrapper> createState() => _FocusHighlightWrapperState();
}

class _FocusHighlightWrapperState extends State<_FocusHighlightWrapper> {
  late final FocusNode _focusNode;
  bool _hasFocusedDescendant = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      debugLabel: widget.debugLabel,
      canRequestFocus: false,
      skipTraversal: true,
    )..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _FocusHighlightWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.debugLabel != oldWidget.debugLabel) {
      _focusNode.debugLabel = widget.debugLabel;
    }
    if (!widget.enabled && _hasFocusedDescendant) {
      setState(() {
        _hasFocusedDescendant = false;
      });
    }
  }

  void _handleFocusChange() {
    final next = _focusNode.hasFocus;
    if (next != _hasFocusedDescendant) {
      setState(() {
        _hasFocusedDescendant = next;
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }
    final highlightColor = Theme.of(context).colorScheme.primary;
    return Focus(
      focusNode: _focusNode,
      canRequestFocus: false,
      skipTraversal: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: Border.all(
            color: _hasFocusedDescendant ? highlightColor : Colors.transparent,
            width: 2,
          ),
          boxShadow: _hasFocusedDescendant
              ? [
                  BoxShadow(
                    color: highlightColor.withValues(alpha: 0.35),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ]
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
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
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
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
    final last = lastSearchedAt == null
        ? '—'
        : '${lastSearchedAt!.hour.toString().padLeft(2, '0')}:${lastSearchedAt!.minute.toString().padLeft(2, '0')}';
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
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Search snapshot',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Queue prepared: $queue • Last search: $last',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RandomStartSlider extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onChangeEnd;
  final bool isAndroidTv;

  const _RandomStartSlider({
    required this.value,
    required this.isAndroidTv,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  State<_RandomStartSlider> createState() => _RandomStartSliderState();
}

class _RandomStartSliderState extends State<_RandomStartSlider> {
  FocusNode? _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    if (widget.isAndroidTv) {
      _focusNode = FocusNode(
        debugLabel: 'RandomStartSlider',
        onKeyEvent: _handleKeyEvent,
      );
      _focusNode!.addListener(_handleFocusChange);
    }
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode?.hasFocus ?? false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _RandomStartSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAndroidTv && _focusNode == null) {
      _focusNode = FocusNode(
        debugLabel: 'RandomStartSlider',
        onKeyEvent: _handleKeyEvent,
      );
      _focusNode!.addListener(_handleFocusChange);
    } else if (!widget.isAndroidTv && _focusNode != null) {
      _focusNode!.removeListener(_handleFocusChange);
      _focusNode!.dispose();
      _focusNode = null;
    }
  }

  @override
  void dispose() {
    _focusNode?.removeListener(_handleFocusChange);
    _focusNode?.dispose();
    super.dispose();
  }

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
    final divisions = (_randomStartPercentMax - _randomStartPercentMin) ~/ 5;

    Widget sliderColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Random start within first ${widget.value}%', style: textStyle),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackShape: const RoundedRectSliderTrackShape(),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: Slider(
            value: widget.value.toDouble(),
            focusNode: widget.isAndroidTv ? _focusNode : null,
            min: _randomStartPercentMin.toDouble(),
            max: _randomStartPercentMax.toDouble(),
            divisions: divisions == 0 ? null : divisions,
            label: '${widget.value}%',
            onChanged: (raw) {
              final next = _clampRandomStartPercent(raw.round());
              widget.onChanged(next);
            },
            onChangeEnd: widget.onChangeEnd == null
                ? null
                : (raw) => widget.onChangeEnd!(
                    _clampRandomStartPercent(raw.round()),
                  ),
          ),
        ),
        Text(
          'Videos will jump to a random moment inside the first ${widget.value}% of playback.',
          style: helperStyle,
        ),
      ],
    );

    // Wrap in focus indicator container for TV
    if (widget.isAndroidTv) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _isFocused ? const Color(0xFF2A2A2A) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isFocused ? Colors.white : Colors.white12,
            width: _isFocused ? 2 : 1,
          ),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.15),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: sliderColumn,
      );
    }

    return sliderColumn;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (node.context != null) {
        FocusScope.of(node.context!).nextFocus();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (node.context != null) {
        FocusScope.of(node.context!).previousFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }
}

// Helper types for zip import persistence and reporting.
class _ZipImportPersistenceResult {
  final List<_ZipImportSuccess> successes;
  final List<_ZipImportSaveFailure> failures;

  const _ZipImportPersistenceResult({
    required this.successes,
    required this.failures,
  });
}

class _ZipImportSuccess {
  final String sourceName;
  final String channelName;
  final int keywordCount;
  final int torrentCount;

  const _ZipImportSuccess({
    required this.sourceName,
    required this.channelName,
    required this.keywordCount,
    required this.torrentCount,
  });
}

class _ZipImportSaveFailure {
  final String sourceName;
  final String channelName;
  final String reason;

  const _ZipImportSaveFailure({
    required this.sourceName,
    required this.channelName,
    required this.reason,
  });
}

class _ZipImportFailureDisplay {
  final String sourceName;
  final String reason;

  const _ZipImportFailureDisplay({
    required this.sourceName,
    required this.reason,
  });
}

class _SwitchRow extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_SwitchRow> createState() => _SwitchRowState();
}

class _SwitchRowState extends State<_SwitchRow> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onChanged(!widget.value);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _isFocused ? const Color(0xFF2A2A2A) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isFocused ? Colors.white : Colors.white12,
            width: _isFocused ? 2 : 1,
          ),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.15),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: SwitchListTile(
          title: Text(
            widget.title,
            style: const TextStyle(color: Colors.white),
          ),
          subtitle: Text(
            widget.subtitle,
            style: const TextStyle(color: Colors.white70),
          ),
          value: widget.value,
          onChanged: widget.onChanged,
          activeColor: const Color(0xFFE50914),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 0,
          ),
        ),
      ),
    );
  }
}

// TV-optimized Compact Button for top bar
class _TvCompactButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String? label;
  final Color backgroundColor;

  const _TvCompactButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.backgroundColor,
  });

  @override
  State<_TvCompactButton> createState() => _TvCompactButtonState();
}

class _TvCompactButtonState extends State<_TvCompactButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;

    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Handle both select and enter keys
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onPressed?.call();
            return KeyEventResult.handled;
          }
          // Also handle context menu button as a secondary action
          if (event.logicalKey == LogicalKeyboardKey.contextMenu &&
              widget.label == null) {
            // Only for settings button
            widget.onPressed?.call();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _isFocused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 36,
            padding: EdgeInsets.symmetric(
              horizontal: widget.label != null ? 12 : 10,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: isDisabled
                  ? Colors.grey.withOpacity(0.3)
                  : widget.backgroundColor.withOpacity(_isFocused ? 1.0 : 0.8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isFocused
                    ? Colors.white
                    : (isDisabled
                          ? Colors.grey.withOpacity(0.2)
                          : Colors.white24),
                width: _isFocused ? 2 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: widget.backgroundColor.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  color: isDisabled ? Colors.grey : Colors.white,
                  size: 16,
                ),
                if (widget.label != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    widget.label!,
                    style: TextStyle(
                      color: isDisabled ? Colors.grey : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// TV-optimized Focusable Button
class _TvFocusableButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final double? width;

  const _TvFocusableButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    this.width,
  });

  @override
  State<_TvFocusableButton> createState() => _TvFocusableButtonState();
}

class _TvFocusableButtonState extends State<_TvFocusableButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onPressed?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: _isFocused ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: Container(
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
            border: _isFocused
                ? Border.all(color: Colors.white, width: 3)
                : null,
          ),
          child: FilledButton.icon(
            onPressed: widget.onPressed,
            icon: Icon(widget.icon, size: 20),
            label: Text(
              widget.label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: widget.backgroundColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// TV-optimized Focusable Card
class _TvFocusableCard extends StatefulWidget {
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final Widget child;
  final bool showLongPressHint;

  const _TvFocusableCard({
    required this.onPressed,
    required this.child,
    this.onLongPress,
    this.showLongPressHint = false,
  });

  @override
  State<_TvFocusableCard> createState() => _TvFocusableCardState();
}

class _TvFocusableCardState extends State<_TvFocusableCard> {
  bool _isFocused = false;
  Timer? _longPressTimer;
  bool _longPressTriggered = false;
  DateTime? _lastLongPressTime;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        print('[TvFocusableCard] Focus changed: $focused');
        setState(() {
          _isFocused = focused;
        });
        if (!focused) {
          _longPressTimer?.cancel();
          _longPressTriggered = false;
        }
      },
      onKeyEvent: (node, event) {
        // Handle Select/Enter button press
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          if (event is KeyDownEvent) {
            print(
              '[TvFocusableCard] Select/Enter key DOWN - starting long press timer',
            );
            _longPressTriggered = false;

            // Start timer for long press (800ms)
            _longPressTimer?.cancel();
            _longPressTimer = Timer(const Duration(milliseconds: 800), () {
              print(
                '[TvFocusableCard] Long press detected! Triggering onLongPress',
              );
              _longPressTriggered = true;
              _lastLongPressTime = DateTime.now();
              if (widget.onLongPress != null) {
                widget.onLongPress!();
              }
            });

            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            print('[TvFocusableCard] Select/Enter key UP');
            _longPressTimer?.cancel();

            // Check if we recently triggered a long press (within last 500ms)
            final timeSinceLongPress = _lastLongPressTime != null
                ? DateTime.now().difference(_lastLongPressTime!).inMilliseconds
                : 999999;

            // If not a long press and not immediately after closing dialog, trigger regular press
            if (!_longPressTriggered && timeSinceLongPress > 500) {
              print('[TvFocusableCard] Short press - triggering onPressed');
              widget.onPressed();
            } else if (timeSinceLongPress <= 500) {
              print(
                '[TvFocusableCard] Ignoring key up - too soon after long press dialog',
              );
            }
            _longPressTriggered = false;

            return KeyEventResult.handled;
          }
        }

        if (event is KeyDownEvent) {
          print(
            '[TvFocusableCard] Other key pressed: ${event.logicalKey.keyLabel} (${event.logicalKey.keyId})',
          );
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          print('[TvFocusableCard] GestureDetector onTap triggered');
          widget.onPressed();
        },
        onLongPress: widget.onLongPress != null
            ? () {
                print(
                  '[TvFocusableCard] GestureDetector onLongPress triggered!',
                );
                widget.onLongPress!();
              }
            : null,
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isFocused
                      ? [const Color(0xFF2A2A2A), const Color(0xFF1A1A1A)]
                      : [const Color(0xFF1A1A1A), const Color(0xFF0F0F0F)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isFocused ? Colors.white : Colors.white12,
                  width: _isFocused ? 3 : 1,
                ),
                boxShadow: _isFocused
                    ? [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.2),
                          blurRadius: 24,
                          spreadRadius: 0,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ],
              ),
              child: widget.child,
            ),
            // Long press hint (bottom-right when focused)
            if (_isFocused &&
                widget.showLongPressHint &&
                widget.onLongPress != null)
              Positioned(
                bottom: 8,
                right: 8,
                child: AnimatedOpacity(
                  opacity: _isFocused ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.more_vert_rounded,
                          size: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Long press for options',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for browsing and selecting community shared channels
class _CommunityChannelsDialog extends StatefulWidget {
  final bool isAndroidTv;

  const _CommunityChannelsDialog({required this.isAndroidTv});

  @override
  State<_CommunityChannelsDialog> createState() =>
      _CommunityChannelsDialogState();
}

class _CommunityChannelsDialogState extends State<_CommunityChannelsDialog> {
  final TextEditingController _repoUrlController = TextEditingController(
    text: CommunityChannelsService.defaultRepoUrl,
  );
  final FocusNode _repoUrlFocusNode = FocusNode();
  final FocusNode _fetchButtonFocusNode = FocusNode();
  final FocusNode _selectAllFocusNode = FocusNode();
  final FocusNode _cancelButtonFocusNode = FocusNode();
  final FocusNode _importButtonFocusNode = FocusNode();
  final ScrollController _channelListScrollController = ScrollController();

  CommunityChannelManifest? _manifest;
  bool _isLoading = false;
  String? _errorMessage;
  bool _selectAll = false;
  Map<String, FocusNode> _channelFocusNodes = {};
  bool _isFetching = false;

  @override
  void initState() {
    super.initState();
    // Set up focus nodes for keyboard navigation
    if (widget.isAndroidTv) {
      _setupFocusNavigation();
    }
    // Auto-fetch channels on dialog open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchChannels();
    });
  }

  void _setupFocusNavigation() {
    // Setup DPAD navigation for URL input field
    _repoUrlFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;

      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown) {
        _fetchButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight &&
          _repoUrlController.selection.baseOffset ==
              _repoUrlController.text.length) {
        _fetchButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // Setup DPAD navigation for fetch button
    _fetchButtonFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;

      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _repoUrlFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _repoUrlFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        if (_manifest != null && _manifest!.channels.isNotEmpty) {
          _selectAllFocusNode.requestFocus();
        } else {
          _cancelButtonFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // Setup DPAD navigation for select all checkbox
    _selectAllFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;

      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        _fetchButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown &&
          _channelFocusNodes.isNotEmpty) {
        _channelFocusNodes.values.first.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
        setState(() {
          _toggleSelectAll();
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // Setup DPAD navigation for Cancel button
    _cancelButtonFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;

      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        if (_channelFocusNodes.isNotEmpty) {
          _channelFocusNodes.values.last.requestFocus();
        } else if (_manifest != null) {
          _selectAllFocusNode.requestFocus();
        } else {
          _fetchButtonFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _importButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    // Setup DPAD navigation for Import button
    _importButtonFocusNode.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;

      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        if (_channelFocusNodes.isNotEmpty) {
          _channelFocusNodes.values.last.requestFocus();
        } else if (_manifest != null) {
          _selectAllFocusNode.requestFocus();
        } else {
          _fetchButtonFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        _cancelButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
        // Trigger import action if there are selected channels
        final selectedChannels = _getSelectedChannels();
        if (selectedChannels.isNotEmpty) {
          Navigator.of(context).pop(selectedChannels);
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _repoUrlController.dispose();
    _repoUrlFocusNode.dispose();
    _fetchButtonFocusNode.dispose();
    _selectAllFocusNode.dispose();
    _cancelButtonFocusNode.dispose();
    _importButtonFocusNode.dispose();
    _channelListScrollController.dispose();
    for (final node in _channelFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _toggleSelectAll() {
    // Track which specific node was focused by finding the focused channel ID
    String? focusedChannelId;
    if (widget.isAndroidTv) {
      for (final entry in _channelFocusNodes.entries) {
        if (entry.value.hasFocus) {
          focusedChannelId = entry.key;
          break;
        }
      }
    }

    setState(() {
      _selectAll = !_selectAll;
      if (_manifest != null) {
        for (final channel in _manifest!.channels) {
          channel.isSelected = _selectAll;
        }
      }
    });

    // Restore focus to the specific channel that was focused
    if (widget.isAndroidTv && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (focusedChannelId != null) {
          final node = _channelFocusNodes[focusedChannelId];
          _safeRequestFocus(node);
        } else {
          // Fallback to select all if no channel was focused
          _safeRequestFocus(_selectAllFocusNode);
        }
      });
    }
  }

  void _toggleChannelSelection(CommunityChannel channel) {
    // Track the specific channel ID that's being toggled
    final channelId = channel.id;

    setState(() {
      channel.isSelected = !channel.isSelected;
      // Update select all state if needed
      if (_manifest != null) {
        _selectAll = _manifest!.channels.every((c) => c.isSelected);
      }
    });

    // Restore focus to the specific channel that was interacted with
    if (widget.isAndroidTv && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        // Use the specific channel's focus node to avoid race conditions
        final node = _channelFocusNodes[channelId];
        _safeRequestFocus(node);
      });
    }
  }

  void _safeRequestFocus(FocusNode? node) {
    if (node != null && mounted) {
      try {
        node.requestFocus();
      } catch (e) {
        // Silently catch any disposal race conditions
        debugPrint('[_CommunityChannelsDialog] Failed to request focus: $e');
      }
    }
  }

  Future<void> _fetchChannels() async {
    // Prevent concurrent fetches
    if (_isFetching) {
      return;
    }

    final url = _repoUrlController.text.trim();
    if (url.isEmpty) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Please enter a repository URL';
      });
      return;
    }

    if (!CommunityChannelsService.isValidRepoUrl(url)) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Please enter a valid URL';
      });
      return;
    }

    _isFetching = true;

    // Keep reference to old focus nodes but DON'T dispose them yet
    final oldFocusNodes = Map<String, FocusNode>.from(_channelFocusNodes);

    if (!mounted) {
      _isFetching = false;
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _manifest = null;
      _selectAll = false;
    });

    try {
      final manifest = await CommunityChannelsService.fetchManifest(url);

      if (!mounted) {
        _isFetching = false;
        return;
      }

      // Create NEW focus nodes BEFORE disposing old ones
      final newFocusNodes = <String, FocusNode>{};
      for (final channel in manifest.channels) {
        if (!mounted) {
          // Clean up any nodes we created if widget was disposed
          for (final node in newFocusNodes.values) {
            node.dispose();
          }
          _isFetching = false;
          return;
        }
        newFocusNodes[channel.id] = FocusNode();
      }

      // Only proceed if still mounted
      if (!mounted) {
        // Dispose new nodes if widget was disposed during async operation
        for (final node in newFocusNodes.values) {
          node.dispose();
        }
        _isFetching = false;
        return;
      }

      // Atomically swap the focus nodes
      _channelFocusNodes = newFocusNodes;

      // Setup navigation between channel items
      if (widget.isAndroidTv) {
        _setupChannelFocusNavigation(manifest.channels);
      }

      if (!mounted) {
        _isFetching = false;
        return;
      }

      setState(() {
        _manifest = manifest;
        _isLoading = false;
      });

      // Dispose old nodes AFTER setState completes and new nodes are in use
      // Schedule disposal for next frame to ensure rebuild is complete
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (final node in oldFocusNodes.values) {
            node.dispose();
          }
        });
      }

      _isFetching = false;
    } catch (e) {
      if (!mounted) {
        _isFetching = false;
        return;
      }

      setState(() {
        _errorMessage = CommunityChannelsService.getErrorMessage(e);
        _isLoading = false;
      });

      _isFetching = false;
    }
  }

  void _setupChannelFocusNavigation(List<CommunityChannel> channels) {
    for (int i = 0; i < channels.length; i++) {
      final channel = channels[i];
      final node = _channelFocusNodes[channel.id];
      if (node == null) continue;

      node.onKeyEvent = (focusNode, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        final key = event.logicalKey;

        // Navigate up
        if (key == LogicalKeyboardKey.arrowUp) {
          if (i > 0) {
            _channelFocusNodes[channels[i - 1].id]?.requestFocus();
          } else {
            _selectAllFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }

        // Navigate down
        if (key == LogicalKeyboardKey.arrowDown) {
          if (i < channels.length - 1) {
            _channelFocusNodes[channels[i + 1].id]?.requestFocus();
          } else {
            _cancelButtonFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }

        // Toggle selection with Enter/Select
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter) {
          _toggleChannelSelection(channel);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      };
    }
  }

  List<CommunityChannel> _getSelectedChannels() {
    if (_manifest == null) return [];
    return _manifest!.channels.where((c) => c.isSelected).toList();
  }

  Widget _buildChannelTile(CommunityChannel channel) {
    final focusNode = _channelFocusNodes[channel.id];

    // Handle null focusNode gracefully - return simple tile without focus handling
    if (focusNode == null) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.3),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: CheckboxListTile(
          value: channel.isSelected,
          onChanged: widget.isAndroidTv ? null : (_) => _toggleChannelSelection(channel),
          activeColor: Theme.of(context).primaryColor,
          checkColor: Colors.white,
          dense: true,
          visualDensity: VisualDensity.compact,
          title: Text(channel.name),
          subtitle: Text(channel.category),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
        ),
      );
    }

    // Define category colors for better visual appeal
    Color getCategoryColor(String category) {
      switch (category.toLowerCase()) {
        case 'movies':
          return const Color(0xFF9C27B0); // Purple
        case 'series':
        case 'tv':
          return const Color(0xFF2196F3); // Blue
        case 'sports':
          return const Color(0xFF4CAF50); // Green
        case 'news':
          return const Color(0xFFFF5722); // Deep Orange
        case 'kids':
          return const Color(0xFFFFC107); // Amber
        case 'documentary':
          return const Color(0xFF00BCD4); // Cyan
        case 'music':
          return const Color(0xFFE91E63); // Pink
        default:
          return const Color(0xFF607D8B); // Blue Grey
      }
    }

    return Focus(
      focusNode: focusNode,
      onFocusChange: (hasFocus) {
        if (hasFocus && mounted) {
          setState(() {}); // Rebuild to show focus highlight

          // Auto-scroll to make focused item visible
          if (widget.isAndroidTv) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Check all conditions before attempting scroll
              if (!mounted) return;
              if (!_channelListScrollController.hasClients) return;

              final context = focusNode.context;
              if (context == null) return;

              final renderObject = context.findRenderObject();
              if (renderObject == null || !renderObject.attached) return;

              try {
                _channelListScrollController.position.ensureVisible(
                  renderObject,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: 0.5, // Center the item in the viewport
                );
              } catch (e) {
                debugPrint('[_CommunityChannelsDialog] Scroll error: $e');
              }
            });
          }
        }
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          final categoryColor = getCategoryColor(channel.category);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            decoration: BoxDecoration(
              color: hasFocus
                  ? Theme.of(context).primaryColor.withOpacity(0.15)
                  : Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: hasFocus
                    ? Theme.of(context).primaryColor
                    : Theme.of(context).dividerColor.withOpacity(0.3),
                width: hasFocus ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: hasFocus
                  ? [
                      BoxShadow(
                        color: Theme.of(context).primaryColor.withOpacity(0.2),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
            ),
            child: CheckboxListTile(
              value: channel.isSelected,
              onChanged: widget.isAndroidTv ? null : (_) => _toggleChannelSelection(channel),
              activeColor: Theme.of(context).primaryColor,
              checkColor: Colors.white,
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(
                channel.name,
                style: TextStyle(
                  fontWeight: hasFocus ? FontWeight.bold : FontWeight.w500,
                  fontSize: hasFocus ? 15 : 14,
                  color: hasFocus
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.9),
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (channel.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      channel.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              categoryColor.withOpacity(hasFocus ? 0.9 : 0.8),
                              categoryColor.withOpacity(hasFocus ? 1.0 : 0.9),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: categoryColor.withOpacity(0.2),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          channel.category.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      if (channel.updated.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.update,
                          size: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          channel.updated,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _getSelectedChannels().length;
    final totalCount = _manifest?.channels.length ?? 0;

    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      title: Row(
        children: [
          Icon(
            Icons.cloud_download,
            color: Theme.of(context).primaryColor,
            size: 28,
          ),
          const SizedBox(width: 12),
          const Text(
            'Import Community Shared Channels',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Container(
        width: 750,
        height: 650,
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // URL Input and Fetch Button - More compact
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _repoUrlController,
                      focusNode: _repoUrlFocusNode,
                      decoration: InputDecoration(
                        labelText: 'Repository URL',
                        hintText: 'Enter community repository URL',
                        errorText: _errorMessage,
                        prefixIcon: Icon(
                          Icons.link,
                          size: 20,
                          color: Theme.of(
                            context,
                          ).primaryColor.withOpacity(0.7),
                        ),
                        isDense: true,
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Theme.of(context).primaryColor,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      autofocus: true,
                      enabled: !_isLoading,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Focus(
                    focusNode: _fetchButtonFocusNode,
                    child: Builder(
                      builder: (context) {
                        final hasFocus = Focus.of(context).hasFocus;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: LinearGradient(
                              colors: _isLoading
                                  ? [Colors.grey.shade400, Colors.grey.shade500]
                                  : hasFocus
                                  ? [
                                      const Color(0xFF2196F3),
                                      const Color(0xFF1976D2),
                                    ]
                                  : [
                                      const Color(0xFF42A5F5),
                                      const Color(0xFF2196F3),
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: hasFocus
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF2196F3,
                                      ).withOpacity(0.3),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _fetchChannels,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: _isLoading
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.download_rounded, size: 18),
                            label: Text(
                              _isLoading ? 'Fetching...' : 'Fetch',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Select All / Channel count - More compact
            if (_manifest != null && _manifest!.channels.isNotEmpty) ...[
              Focus(
                focusNode: _selectAllFocusNode,
                child: Builder(
                  builder: (context) {
                    final hasFocus = Focus.of(context).hasFocus;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: hasFocus
                              ? [
                                  Theme.of(
                                    context,
                                  ).primaryColor.withOpacity(0.1),
                                  Theme.of(
                                    context,
                                  ).primaryColor.withOpacity(0.05),
                                ]
                              : [
                                  Theme.of(
                                    context,
                                  ).colorScheme.surfaceVariant.withOpacity(0.5),
                                  Theme.of(
                                    context,
                                  ).colorScheme.surfaceVariant.withOpacity(0.3),
                                ],
                        ),
                        border: Border.all(
                          color: hasFocus
                              ? Theme.of(context).primaryColor
                              : Theme.of(context).dividerColor.withOpacity(0.3),
                          width: hasFocus ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: hasFocus
                            ? [
                                BoxShadow(
                                  color: Theme.of(
                                    context,
                                  ).primaryColor.withOpacity(0.15),
                                  blurRadius: 6,
                                  spreadRadius: 0,
                                ),
                              ]
                            : [],
                      ),
                      child: CheckboxListTile(
                        value: _selectAll,
                        onChanged: widget.isAndroidTv ? null : (_) => _toggleSelectAll(),
                        activeColor: Theme.of(context).primaryColor,
                        checkColor: Colors.white,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Row(
                          children: [
                            Text(
                              'Select All',
                              style: TextStyle(
                                fontWeight: hasFocus
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: selectedCount > 0
                                    ? Theme.of(
                                        context,
                                      ).primaryColor.withOpacity(0.2)
                                    : Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$selectedCount / $totalCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: selectedCount > 0
                                      ? Theme.of(context).primaryColor
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Divider(
                color: Theme.of(context).dividerColor.withOpacity(0.2),
                thickness: 0.5,
                height: 1,
              ),
              const SizedBox(height: 6),
            ],

            // Channel List - Optimized padding
            if (_manifest != null && _manifest!.channels.isNotEmpty)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.background.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: ListView.builder(
                    controller: _channelListScrollController,
                    itemCount: _manifest!.channels.length,
                    cacheExtent: 200.0, // Pre-cache items for smoother scrolling
                    addRepaintBoundaries: true, // Optimize repainting
                    itemBuilder: (context, index) {
                      return RepaintBoundary(
                        child: _buildChannelTile(_manifest!.channels[index]),
                      );
                    },
                  ),
                ),
              )
            else if (_manifest != null && _manifest!.channels.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('No channels found in this repository'),
                ),
              )
            else if (!_isLoading && _errorMessage == null)
              const Expanded(
                child: Center(
                  child: Text(
                    'Enter a repository URL and click "Fetch Channels" to browse available channels',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (_errorMessage != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              const Spacer(),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.all(12),
      actions: [
        Focus(
          focusNode: _cancelButtonFocusNode,
          child: Builder(
            builder: (context) {
              final hasFocus = Focus.of(context).hasFocus;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    colors: hasFocus
                        ? [Colors.grey.shade600, Colors.grey.shade700]
                        : [Colors.grey.shade500, Colors.grey.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: hasFocus
                      ? [
                          BoxShadow(
                            color: Colors.grey.shade600.withOpacity(0.3),
                            blurRadius: 6,
                            spreadRadius: 0,
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                ),
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: hasFocus ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Focus(
          focusNode: _importButtonFocusNode,
          child: Builder(
            builder: (context) {
              final hasFocus = Focus.of(context).hasFocus;
              final hasSelection = selectedCount > 0;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    colors: !hasSelection
                        ? [
                            Colors.grey.shade400.withOpacity(0.5),
                            Colors.grey.shade500.withOpacity(0.5),
                          ]
                        : hasFocus
                        ? [const Color(0xFF4CAF50), const Color(0xFF45A049)]
                        : [const Color(0xFF66BB6A), const Color(0xFF4CAF50)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: hasSelection
                      ? hasFocus
                            ? [
                                BoxShadow(
                                  color: const Color(
                                    0xFF4CAF50,
                                  ).withOpacity(0.3),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                      : [],
                ),
                child: ElevatedButton.icon(
                  onPressed: hasSelection
                      ? () => Navigator.of(context).pop(_getSelectedChannels())
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    backgroundColor: Colors.transparent,
                    foregroundColor: hasSelection
                        ? Colors.white
                        : Colors.white.withOpacity(0.5),
                    disabledBackgroundColor: Colors.transparent,
                    disabledForegroundColor: Colors.white.withOpacity(0.5),
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: Icon(
                    hasSelection
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                  ),
                  label: Text(
                    selectedCount > 0
                        ? 'Import Selected ($selectedCount)'
                        : 'Import Selected',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: hasFocus ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Dialog for selecting import mode with DPAD support and awesome TV-optimized UI
class _ImportChannelsDialog extends StatefulWidget {
  final bool isAndroidTv;

  const _ImportChannelsDialog({required this.isAndroidTv});

  @override
  State<_ImportChannelsDialog> createState() => _ImportChannelsDialogState();
}

class _ImportChannelsDialogState extends State<_ImportChannelsDialog> {
  // Focus nodes for DPAD navigation
  final FocusNode _deviceFocusNode = FocusNode();
  final FocusNode _linkFocusNode = FocusNode();
  final FocusNode _communityFocusNode = FocusNode();
  final FocusNode _cancelFocusNode = FocusNode();

  // Track current focused index for visual feedback
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();

    // Set up focus listeners
    _deviceFocusNode.addListener(() {
      if (_deviceFocusNode.hasFocus) {
        setState(() => _focusedIndex = 0);
      }
    });

    _linkFocusNode.addListener(() {
      if (_linkFocusNode.hasFocus) {
        setState(() => _focusedIndex = 1);
      }
    });

    _communityFocusNode.addListener(() {
      if (_communityFocusNode.hasFocus) {
        setState(() => _focusedIndex = 2);
      }
    });

    _cancelFocusNode.addListener(() {
      if (_cancelFocusNode.hasFocus) {
        setState(() => _focusedIndex = 3);
      }
    });

    // Auto-focus first option for TV
    if (widget.isAndroidTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _deviceFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _deviceFocusNode.dispose();
    _linkFocusNode.dispose();
    _communityFocusNode.dispose();
    _cancelFocusNode.dispose();
    super.dispose();
  }

  Widget _buildImportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required FocusNode focusNode,
    required VoidCallback onSelect,
    required bool isFocused,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            onSelect();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: isFocused ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isFocused
                ? const Color(0xFF1E293B).withOpacity(0.8)
                : const Color(0xFF0F172A).withOpacity(0.6),
            border: Border.all(
              color: isFocused
                  ? accentColor.withOpacity(0.4)
                  : Colors.white.withOpacity(0.05),
              width: 1,
            ),
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: accentColor.withOpacity(0.15),
                      blurRadius: 16,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                // Left accent strip on focus
                if (isFocused)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accentColor,
                            accentColor.withOpacity(0.6),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.isAndroidTv ? null : onSelect,
                    borderRadius: BorderRadius.circular(12),
                    splashColor: accentColor.withOpacity(0.1),
                    highlightColor: accentColor.withOpacity(0.05),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isFocused ? 16 : 14,
                        12,
                        14,
                        12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            icon,
                            size: 28,
                            color: isFocused
                                ? accentColor
                                : Colors.white.withOpacity(0.7),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: widget.isAndroidTv ? 17 : 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: widget.isAndroidTv ? 13 : 12,
                                    color: Colors.white.withOpacity(0.65),
                                    height: 1.3,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isFocused)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: accentColor.withOpacity(0.8),
                                size: 18,
                              ),
                            ),
                        ],
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
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = widget.isAndroidTv ? 540.0 : 500.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.06),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.download_rounded,
                    color: Colors.white.withOpacity(0.9),
                    size: widget.isAndroidTv ? 24 : 22,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Import Channels',
                    style: TextStyle(
                      fontSize: widget.isAndroidTv ? 22 : 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Column(
                    children: [
                      // Device Import Option
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: _buildImportOption(
                          icon: Icons.sd_storage_rounded,
                          title: 'Import from Device',
                          subtitle:
                              'Load a .zip, .yaml, .txt, or .debrify file',
                          accentColor: const Color(0xFF2563EB),
                          focusNode: _deviceFocusNode,
                          isFocused: _focusedIndex == 0,
                          onSelect: () {
                            Navigator.of(
                              context,
                            ).pop(_ImportChannelsMode.device);
                          },
                        ),
                      ),

                      // Link Import Option
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
                        child: _buildImportOption(
                          icon: Icons.link_rounded,
                          title: 'Import from Link',
                          subtitle:
                              'Paste a debrify:// link or URL to a channel file',
                          accentColor: const Color(0xFF7C3AED),
                          focusNode: _linkFocusNode,
                          isFocused: _focusedIndex == 1,
                          onSelect: () {
                            Navigator.of(context).pop(_ImportChannelsMode.url);
                          },
                        ),
                      ),

                      // Community Import Option
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(3),
                        child: _buildImportOption(
                          icon: Icons.people_rounded,
                          title: 'Import Community Shared Channels',
                          subtitle:
                              'Browse and import channels from community repositories',
                          accentColor: const Color(0xFF10B981),
                          focusNode: _communityFocusNode,
                          isFocused: _focusedIndex == 2,
                          onSelect: () {
                            Navigator.of(
                              context,
                            ).pop(_ImportChannelsMode.community);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Cancel Button
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withOpacity(0.06),
                    width: 1,
                  ),
                ),
              ),
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(4),
                child: Focus(
                  focusNode: _cancelFocusNode,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.space ||
                          event.logicalKey == LogicalKeyboardKey.gameButtonA) {
                        Navigator.of(context).pop();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: _focusedIndex == 3
                          ? Colors.white.withOpacity(0.08)
                          : Colors.transparent,
                      border: Border.all(
                        color: _focusedIndex == 3
                            ? Colors.white.withOpacity(0.2)
                            : Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.isAndroidTv
                            ? null
                            : () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.close_rounded,
                                color: _focusedIndex == 3
                                    ? Colors.white.withOpacity(0.9)
                                    : Colors.white.withOpacity(0.6),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: widget.isAndroidTv ? 16 : 15,
                                  fontWeight: FontWeight.w500,
                                  color: _focusedIndex == 3
                                      ? Colors.white.withOpacity(0.9)
                                      : Colors.white.withOpacity(0.6),
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

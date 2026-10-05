import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:debrify/features/debrify_tv/application/debrify_tv_byte_format.dart';
import 'package:debrify/features/debrify_tv/application/debrify_tv_random_start.dart';
import 'package:debrify/features/debrify_tv/models/debrify_tv_alldebrid_prepared.dart';
import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/models/debrify_tv_kinds.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_import_parsing.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/debrify_tv/cache_results.dart';
import '../models/debrify_tv/channel.dart';
import '../models/debrify_tv/channel_stats.dart';
import '../models/debrify_tv/import_results.dart';
import '../models/debrify_tv/prepared_torrents.dart';
import '../models/debrify_tv_cache.dart';
import '../models/debrify_tv_channel_record.dart';
import '../models/premiumize_file.dart';
import '../models/profiles/profile_policy.dart';
import '../models/torbox_file.dart';
import '../models/torbox_torrent.dart';
import '../models/torrent.dart';
import '../models/torrent_filter_state.dart';
import '../services/alldebrid_service.dart';
import '../services/analytics_service.dart';
import '../services/android_native_downloader.dart';
import '../services/android_tv_player_bridge.dart';
import '../services/community/community_channel_model.dart';
import '../services/community/community_channels_service.dart';
import '../services/community/magnet_yaml_service.dart';
import '../services/debrid_service.dart';
import '../services/debrify_tv_cache_service.dart';
import '../services/debrify_tv_channel_archive_service.dart';
import '../services/debrify_tv_repository.dart';
import '../services/debrify_tv_zip_importer.dart';
import '../services/engine/dynamic_engine.dart';
import '../services/engine/engine_registry.dart';
import '../services/main_page_bridge.dart';
import '../services/pikpak_api_service.dart';
import '../services/pikpak_tv_service.dart';
import '../services/premiumize_service.dart';
import '../services/profiles/profile_async_authorization.dart';
import '../services/torbox_service.dart';
import '../services/torrent_service.dart';
import '../services/video_player_launcher.dart';
import '../services/webdav_sync/webdav_sync_library_models.dart';
import '../theme/app_theme_scope.dart';
import '../theme/overlay_theme.dart';
import '../utils/debrify_tv_filters.dart';
import '../utils/file_utils.dart';
import '../utils/nsfw_filter.dart';
import '../utils/platform_util.dart';
import '../utils/rd_blocked_filter.dart';
import '../utils/series_parser.dart';
import '../utils/tv_keys.dart';
import '../widgets/torrent_result_row.dart' show qualityTierForName;
import '../widgets/tv_text_field.dart';
import 'debrify_tv/dialogs/cached_loading_dialog.dart';
import 'debrify_tv/dialogs/channel_creation_dialog.dart';
import 'debrify_tv/dialogs/community_channels_dialog.dart';
import 'debrify_tv/dialogs/export_channels_dialog.dart';
import 'debrify_tv/dialogs/external_player_notice_dialog.dart';
import 'debrify_tv/dialogs/import_channels_dialog.dart';
import 'debrify_tv/dialogs/spotlight_dialog.dart';
import 'debrify_tv/layouts/debrify_tv_view.dart';
import 'debrify_tv/layouts/spotlight_layout.dart';
import 'debrify_tv/widgets/random_start_slider.dart';
import 'debrify_tv/widgets/switch_row.dart';
import 'debrify_tv/widgets/tv_focusable_button.dart';
import 'debrify_tv/widgets/tv_focusable_card.dart';
import 'settings/profile_backup_flows.dart';
import 'video_player/player_pip_route.dart';
import 'video_player_screen.dart';

class _SpotlightMetaPill extends StatelessWidget {
  final String label;
  final String value;

  const _SpotlightMetaPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: tv.fillWeak,
        borderRadius: app.shape.br(13),
        border: Border.all(color: tv.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: tv.textFaint,
              fontFamily: 'JetBrainsMono',
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: app.core.tx,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightChoiceChip extends StatefulWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;
  final IconData? trailingIcon;

  const _SpotlightChoiceChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
    this.trailingIcon,
  });

  @override
  State<_SpotlightChoiceChip> createState() => _SpotlightChoiceChipState();
}

class _SpotlightChoiceChipState extends State<_SpotlightChoiceChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final focused = _focused && widget.enabled;
    final fill = focused
        ? app.core.tx
        : widget.selected
        ? tv.accent
        : tv.fillWeak;
    final ink = focused
        ? app.inkOn(app.core.tx)
        : widget.selected
        ? app.inkOn(tv.accent)
        : tv.textDim;
    return Focus(
      canRequestFocus: widget.enabled,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowUp) {
            node.previousFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.arrowDown) {
            node.nextFocus();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent && isActivateOrSpaceKey(key)) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        button: true,
        selected: widget.selected,
        enabled: widget.enabled,
        label: widget.label,
        child: GestureDetector(
          onTap: widget.enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: focused
                ? (Matrix4.identity()..translateByDouble(0, -2, 0, 1))
                : Matrix4.identity(),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: widget.enabled ? fill : tv.fillWeak.withValues(alpha: .3),
              borderRadius: app.shape.br(99),
              border: Border.all(
                color: focused
                    ? app.core.tx
                    : widget.selected
                    ? tv.accent
                    : tv.hairline,
              ),
              boxShadow: focused
                  ? const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 18,
                        offset: Offset(0, 9),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.enabled ? ink : tv.textFaint,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.trailingIcon != null) ...[
                  const SizedBox(width: 7),
                  Icon(widget.trailingIcon, size: 14, color: ink),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvEngineWarmResult {
  final DynamicEngine engine;
  final List<Torrent> torrents;
  final int pagesPulled;
  final String? failureMessage;

  const _TvEngineWarmResult({
    required this.engine,
    required this.torrents,
    required this.pagesPulled,
    this.failureMessage,
  });
}

class DebrifyTVScreen extends StatefulWidget {
  const DebrifyTVScreen({super.key});

  @override
  State<DebrifyTVScreen> createState() => _DebrifyTVScreenState();
}

class _DebrifyTVScreenState extends State<DebrifyTVScreen> {
  final DebrifyTvOwners _owners = DebrifyTvOwners();
  DebrifyTvSections? _composition;
  DebrifyTvSections get _sections => _composition ??= DebrifyTvSections(
    DebrifyTvDependencies(
      owners: _owners,
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      loadSettings: loadSettings,
      loadChannels: loadChannels,
      handleSyncedDebrifyTvLibraryChanged: handleSyncedDebrifyTvLibraryChanged,
      loadFavoriteChannels: loadFavoriteChannels,
      watchChannelById: watchChannelById,
      checkPendingAutoPlay: checkPendingAutoPlay,
      buildSpotlightView: buildSpotlightView,
      buildTvGridLayout: buildTvGridLayout,
      stopPrefetch: stopPrefetch,
    ),
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('magic_tv');
    _owners.focus.channelSearchFocusNode = FocusNode(
      debugLabel: 'DebrifyTVChannelSearch',
    );
    _sections.legacy.loadSettings();
    _sections.legacy
        .loadChannels(); // also warms the Spotlight rail health, once per reload
    _sections.legacy.loadFavoriteChannels();

    // Register watch channel handler for external calls (e.g., from home screen)
    MainPageBridge.watchDebrifyTvChannel = _sections.legacy.watchChannelById;
    MainPageBridge.registerDebrifyTvLibraryListener(
      _sections.legacy.handleSyncedDebrifyTvLibraryChanged,
    );

    // Register TV sidebar focus handler (tab index 3 = Debrify TV)
    _owners.focus.tvContentFocusHandler = () {
      _owners.focus.quickPlayFocusNode.requestFocus();
    };
    MainPageBridge.registerTvContentFocusHandler(
      3,
      _owners.focus.tvContentFocusHandler!,
    );

    // Check for pending auto-play from home screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sections.legacy.checkPendingAutoPlay();
    });
  }

  @override
  void dispose() {
    _owners.stage.spotlightStatsDebounce?.cancel();
    // Clear watch channel handler
    MainPageBridge.watchDebrifyTvChannel = null;
    MainPageBridge.unregisterDebrifyTvLibraryListener(
      _sections.legacy.handleSyncedDebrifyTvLibraryChanged,
    );
    if (_owners.focus.tvContentFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(
        3,
        _owners.focus.tvContentFocusHandler!,
      );
    }
    // Ensure prefetch loop is stopped if this screen is disposed mid-run
    _owners.prefetch.prefetchStopRequested = true;
    _sections.legacy.stopPrefetch();
    // Clean up dialog state to avoid dangling context references
    _owners.progress.progressSheetContext = null;
    _owners.progress.progressOpen = false;
    _owners.progress.progress.dispose();
    _owners.library.keywordsController.dispose();
    _owners.focus.channelSearchController.dispose();
    _owners.focus.channelSearchFocusNode.dispose();
    _owners.focus.quickPlayFocusNode.dispose();
    _owners.focus.channelSearchButtonFocusNode.dispose();
    _owners.focus.channelSearchClearFocusNode.dispose();
    _owners.focus.channelMenuFocusNode.dispose();
    AndroidTvPlayerBridge.clearTorboxProvider();
    super.dispose();
  }

  /// Back/Escape ladder for the channel search bar: clear text first, then
  /// close the bar. Sits on an ancestor Focus of the search field so it runs
  /// when the TvTextField shell lets the key bubble.
  KeyEventResult handleChannelSearchBarBack(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (_owners.focus.channelSearchController.text.isNotEmpty) {
        _owners.focus.channelSearchController.clear();
        setState(() {
          _owners.focus.channelSearchTerm = '';
        });
        // Clearing unmounts the suffix ✕ — if IT held focus, focus would be
        // stranded; parking on the field covers both cases.
        _owners.focus.channelSearchFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (_owners.focus.showSearchBar) {
        setState(() {
          _owners.focus.showSearchBar = false;
        });
        _owners.focus.channelSearchButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void closeProgressDialog() {
    if (!_owners.progress.progressOpen) {
      return;
    }
    if (_owners.progress.progressSheetContext != null) {
      try {
        Navigator.of(_owners.progress.progressSheetContext!).pop();
      } catch (_) {}
      _owners.progress.progressSheetContext = null;
      _owners.progress.progressOpen = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_owners.progress.progressOpen) {
        return;
      }
      if (_owners.progress.progressSheetContext != null) {
        closeProgressDialog();
        return;
      }
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }
      _owners.progress.progressSheetContext = null;
      _owners.progress.progressOpen = false;
    });
  }

  void updateProgress(Iterable<String> messages, {bool replace = false}) {
    final sanitized = messages
        .map((message) => message.trim())
        .where((message) => message.isNotEmpty)
        .toList();
    if (sanitized.isEmpty) {
      return;
    }

    if (replace || _owners.progress.progress.value.isEmpty) {
      _owners.progress.progress.value = sanitized;
      return;
    }

    final copy = List<String>.from(_owners.progress.progress.value)
      ..addAll(sanitized);
    _owners.progress.progress.value = copy;
  }

  void cancelActiveWatch({
    BuildContext? dialogContext,
    bool clearQueue = true,
  }) {
    debugPrint(
      '[MagicTV] _cancelActiveWatch called, dialogContext=$dialogContext, clearQueue=$clearQueue, _watchCancelled=${_owners.session.watchCancelled}',
    );
    if (_owners.session.watchCancelled) {
      debugPrint(
        '[MagicTV] _cancelActiveWatch: Already cancelled, just popping dialog',
      );
      if (dialogContext != null) {
        try {
          Navigator.of(dialogContext).pop();
        } catch (e) {
          debugPrint('[MagicTV] _cancelActiveWatch: Error popping dialog: $e');
        }
      }
      return;
    }
    _owners.session.watchCancelled = true;
    _owners.prefetch.prefetchStopRequested = true;
    debugPrint(
      '[MagicTV] _cancelActiveWatch: Set _watchCancelled=true, stopping prefetch',
    );
    unawaited(stopPrefetch());
    if (clearQueue) {
      debugPrint(
        '[MagicTV] _cancelActiveWatch: Clearing queue (had ${_owners.session.queue.length} items)',
      );
      _owners.session.queue.clear();
    }
    _owners.progress.progress.value = [];
    if (dialogContext != null) {
      debugPrint(
        '[MagicTV] _cancelActiveWatch: Popping dialog via dialogContext',
      );
      try {
        Navigator.of(dialogContext).pop();
      } catch (e) {
        debugPrint('[MagicTV] _cancelActiveWatch: Error popping dialog: $e');
      }
      _owners.progress.progressOpen = false;
      _owners.progress.progressSheetContext = null;
    } else if (_owners.progress.progressOpen) {
      debugPrint(
        '[MagicTV] _cancelActiveWatch: No dialogContext, calling _closeProgressDialog',
      );
      closeProgressDialog();
    }
    if (mounted) {
      setState(() {
        _owners.session.isBusy = false;
        _owners.session.status = '';
      });
    }
    debugPrint('[MagicTV] _cancelActiveWatch: Done');
  }

  String determineDefaultProvider(
    String? preferred,
    bool rdAvailable,
    bool torboxAvailable,
    bool pikpakAvailable,
    bool premiumizeAvailable,
    bool allDebridAvailable,
  ) {
    // If user has a preferred provider that's available, use it
    if (preferred == DebrifyTvConstants.providerPremiumize &&
        premiumizeAvailable) {
      return DebrifyTvConstants.providerPremiumize;
    }
    if (preferred == DebrifyTvConstants.providerAllDebrid &&
        allDebridAvailable) {
      return DebrifyTvConstants.providerAllDebrid;
    }
    if (preferred == DebrifyTvConstants.providerPikPak && pikpakAvailable) {
      return DebrifyTvConstants.providerPikPak;
    }
    if (preferred == DebrifyTvConstants.providerTorbox && torboxAvailable) {
      return DebrifyTvConstants.providerTorbox;
    }
    if (preferred == DebrifyTvConstants.providerRealDebrid && rdAvailable) {
      return DebrifyTvConstants.providerRealDebrid;
    }

    // Fallback: pick first available provider
    if (rdAvailable) {
      return DebrifyTvConstants.providerRealDebrid;
    }
    if (torboxAvailable) {
      return DebrifyTvConstants.providerTorbox;
    }
    if (premiumizeAvailable) {
      return DebrifyTvConstants.providerPremiumize;
    }
    if (allDebridAvailable) {
      return DebrifyTvConstants.providerAllDebrid;
    }
    if (pikpakAvailable) {
      return DebrifyTvConstants.providerPikPak;
    }

    // No provider available, default to RD (will show as unavailable)
    return DebrifyTvConstants.providerRealDebrid;
  }

  bool isProviderSelectable(String provider) {
    if (provider == DebrifyTvConstants.providerTorbox) {
      return _owners.settings.torboxAvailable;
    }
    if (provider == DebrifyTvConstants.providerPikPak) {
      return _owners.settings.pikpakAvailable;
    }
    if (provider == DebrifyTvConstants.providerPremiumize) {
      return _owners.settings.premiumizeAvailable;
    }
    if (provider == DebrifyTvConstants.providerAllDebrid) {
      return _owners.settings.allDebridAvailable;
    }
    return _owners.settings.rdAvailable;
  }

  Future<void> loadSettings() async {
    final startRandom = await DebrifyTvStorage.getDebrifyTvStartRandom();
    final randomStartPercent =
        await DebrifyTvStorage.getDebrifyTvRandomStartPercent();
    // Hardcoded to false - no longer loading from storage
    const hideOptions = false;
    final showChannelName =
        await DebrifyTvStorage.getDebrifyTvShowChannelName();
    final showVideoTitle = await DebrifyTvStorage.getDebrifyTvShowVideoTitle();
    // hideBackButton is hardcoded to false - no longer loading from storage
    final avoidNsfw = await _owners.settings.settingsManager.getGlobalAvoidNsfw(
      true,
    );
    final rdSkipBlocked = await RealDebridStorage.getRdSkipBlockedTorrents();
    final tvFilters = await DebrifyTvFilters.load();
    final storedProvider = await DebrifyTvStorage.getDebrifyTvProvider();
    final hasStoredProvider = await DebrifyTvStorage.hasDebrifyTvProvider();
    final rdIntegrationEnabled =
        await RealDebridStorage.getRealDebridIntegrationEnabled();
    final rdKey = await RealDebridStorage.getApiKey();
    final torboxIntegrationEnabled =
        await TorboxStorage.getTorboxIntegrationEnabled();
    final torboxKey = await TorboxStorage.getTorboxApiKey();

    final registry = EngineRegistry.instance;
    await registry.initialize();
    final keywordEngines = registry.getKeywordSearchEngines();
    final tvEngines = registry
        .getTvModeEngines()
        .where((engine) => engine.supportsKeywordSearch)
        .toList();
    final tvEngineStates = <String, bool>{
      for (final engine in keywordEngines) engine.name: false,
    };
    final tvSmallChannelMaxByEngine = <String, int>{};
    final tvLargeChannelMaxByEngine = <String, int>{};
    final tvQuickPlayMaxByEngine = <String, int>{};

    for (final engine in tvEngines) {
      final tvMode = engine.tvModeConfig;
      if (tvMode == null) {
        continue;
      }
      final engineId = engine.name;
      tvEngineStates[engineId] = await _owners.settings.settingsManager
          .getTvEnabled(engineId, tvMode.enabledDefault);
      tvSmallChannelMaxByEngine[engineId] = await _owners
          .settings
          .settingsManager
          .getTvSmallChannelMax(engineId, tvMode.smallChannel.maxResults);
      tvLargeChannelMaxByEngine[engineId] = await _owners
          .settings
          .settingsManager
          .getTvLargeChannelMax(engineId, tvMode.largeChannel.maxResults);
      tvQuickPlayMaxByEngine[engineId] = await _owners.settings.settingsManager
          .getTvQuickPlayMax(engineId, tvMode.quickPlay.maxResults);
    }

    // Global TV settings
    final channelBatchSize = await _owners.settings.settingsManager
        .getGlobalBatchSize(4);
    final keywordThreshold = await _owners.settings.settingsManager
        .getGlobalKeywordThreshold(10);
    final minTorrentsPerKeyword = await _owners.settings.settingsManager
        .getGlobalMinTorrentsPerKeyword(5);
    final quickPlayMaxKeywords = await _owners.settings.settingsManager
        .getGlobalMaxKeywords(5);

    final rdAvailable =
        rdIntegrationEnabled && rdKey != null && rdKey.isNotEmpty;
    final torboxAvailable =
        torboxIntegrationEnabled && torboxKey != null && torboxKey.isNotEmpty;
    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    final premiumizeIntegrationEnabled =
        await PremiumizeStorage.getPremiumizeIntegrationEnabled();
    final premiumizeKey = await PremiumizeStorage.getPremiumizeApiKey();
    final premiumizeAvailable =
        premiumizeIntegrationEnabled &&
        premiumizeKey != null &&
        premiumizeKey.isNotEmpty;
    final allDebridIntegrationEnabled =
        await AllDebridStorage.getAllDebridIntegrationEnabled();
    final allDebridKey = await AllDebridStorage.getAllDebridApiKey();
    final allDebridAvailable =
        allDebridIntegrationEnabled &&
        allDebridKey != null &&
        allDebridKey.isNotEmpty;
    final defaultProvider = determineDefaultProvider(
      hasStoredProvider ? storedProvider : null,
      rdAvailable,
      torboxAvailable,
      pikpakAvailable,
      premiumizeAvailable,
      allDebridAvailable,
    );
    final isTv = await AndroidNativeDownloader.isTelevision();

    if (mounted) {
      setState(() {
        _owners.settings.startRandom = startRandom;
        _owners.settings.randomStartPercent = clampDebrifyTvRandomStartPercent(
          randomStartPercent,
        );
        _owners.settings.hideSeekbar = hideOptions;
        _owners.settings.showChannelName = showChannelName;
        _owners.settings.showVideoTitle = showVideoTitle;
        _owners.settings.hideOptions = false; // Hardcoded to false
        _owners.settings.hideBackButton = false; // Hardcoded to false
        _owners.settings.rdAvailable = rdAvailable;
        _owners.settings.torboxAvailable = torboxAvailable;
        _owners.settings.pikpakAvailable = pikpakAvailable;
        _owners.settings.premiumizeAvailable = premiumizeAvailable;
        _owners.settings.allDebridAvailable = allDebridAvailable;
        _owners.settings.provider = defaultProvider;
        _owners.settings.isAndroidTv = isTv;

        _owners.settings.quickStartRandom = startRandom;
        _owners.settings.quickRandomStartPercent =
            clampDebrifyTvRandomStartPercent(randomStartPercent);
        _owners.settings.quickHideSeekbar = hideOptions;
        _owners.settings.quickShowChannelName = showChannelName;
        _owners.settings.quickShowVideoTitle = showVideoTitle;
        _owners.settings.quickHideOptions = false; // Hardcoded to false
        _owners.settings.quickHideBackButton = false; // Hardcoded to false
        _owners.settings.quickAvoidNsfw = avoidNsfw;
        _owners.settings.rdSkipBlockedTorrents = rdSkipBlocked;
        _owners.settings.quickProvider = defaultProvider;
        _owners.settings.tvFilters = tvFilters;
        // The filter is an INPUT to the memoised stage numbers: anything
        // computed before this load landed used the empty default.
        _owners.stage.spotlightStats.clear();

        // Update search settings
        _owners.settings.tvEngineStates
          ..clear()
          ..addAll(tvEngineStates);
        _owners.settings.tvSmallChannelMaxByEngine
          ..clear()
          ..addAll(tvSmallChannelMaxByEngine);
        _owners.settings.tvLargeChannelMaxByEngine
          ..clear()
          ..addAll(tvLargeChannelMaxByEngine);
        _owners.settings.tvQuickPlayMaxByEngine
          ..clear()
          ..addAll(tvQuickPlayMaxByEngine);
        _owners.settings.channelBatchSize = channelBatchSize;
        _owners.settings.keywordThreshold = keywordThreshold;
        _owners.settings.minTorrentsPerKeyword = minTorrentsPerKeyword;
        _owners.settings.quickPlayMaxKeywords = quickPlayMaxKeywords;
      });
      // Outside the setState callback: recomputing the focused channel's
      // numbers schedules its own rebuild.
      refreshSpotlightStatsIfFocused(_owners.stage.spotlightFocusedId);
    }

    if (await DebrifyTvStorage.getDebrifyTvHideSeekbar() != hideOptions) {
      unawaited(DebrifyTvStorage.saveDebrifyTvHideSeekbar(hideOptions));
    }

    if (defaultProvider != storedProvider) {
      await DebrifyTvStorage.saveDebrifyTvProvider(defaultProvider);
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

  List<DynamicEngine> enabledTvKeywordEngines(EngineRegistry registry) {
    final engines = registry
        .getTvModeEngines()
        .where(
          (engine) =>
              engine.supportsKeywordSearch &&
              (_owners.settings.tvEngineStates[engine.name] ??
                  engine.tvModeConfig?.enabledDefault ??
                  false),
        )
        .toList();
    engines.sort((a, b) => a.name.compareTo(b.name));
    return engines;
  }

  int tvChannelMaxResultsForEngine(DynamicEngine engine, int totalKeywords) {
    final useSmallChannelLimit =
        totalKeywords < _owners.settings.keywordThreshold;
    final storedLimit = useSmallChannelLimit
        ? _owners.settings.tvSmallChannelMaxByEngine[engine.name]
        : _owners.settings.tvLargeChannelMaxByEngine[engine.name];
    if (storedLimit != null) {
      return storedLimit;
    }

    final tvMode = engine.tvModeConfig;
    if (tvMode == null) {
      return 50;
    }
    return useSmallChannelLimit
        ? tvMode.smallChannel.maxResults
        : tvMode.largeChannel.maxResults;
  }

  int estimatePagesPulledForEngine(DynamicEngine engine, int resultCount) {
    if (resultCount <= 0) {
      return 0;
    }

    final pagination = engine.config.pagination;
    final resultsPerPage = pagination.resultsPerPage;
    if (pagination.type == 'none' ||
        resultsPerPage == null ||
        resultsPerPage <= 0) {
      return 1;
    }

    final estimatedPages = (resultCount + resultsPerPage - 1) ~/ resultsPerPage;
    final maxPages = pagination.maxPages;
    if (maxPages != null && maxPages > 0) {
      return min(estimatedPages, maxPages);
    }
    return estimatedPages;
  }

  int _estimatePageRequestsForEngine(DynamicEngine engine, int totalKeywords) {
    final maxResults = tvChannelMaxResultsForEngine(engine, totalKeywords);
    final pagination = engine.config.pagination;
    final resultsPerPage = pagination.resultsPerPage;
    if (pagination.type == 'none' ||
        resultsPerPage == null ||
        resultsPerPage <= 0) {
      return 1;
    }

    final estimatedPages = max(
      1,
      (maxResults + resultsPerPage - 1) ~/ resultsPerPage,
    );
    final maxPages = pagination.maxPages;
    if (maxPages != null && maxPages > 0) {
      return min(estimatedPages, maxPages);
    }
    return estimatedPages;
  }

  Map<String, int> quickPlayMaxResultsOverrides() {
    return Map<String, int>.from(_owners.settings.tvQuickPlayMaxByEngine);
  }

  Future<Map<String, bool>> tvEngineSearchStates() async {
    final registry = EngineRegistry.instance;
    await registry.initialize();
    return <String, bool>{
      for (final engine in registry.getKeywordSearchEngines())
        engine.name:
            _owners.settings.tvEngineStates[engine.name] ??
            engine.tvModeConfig?.enabledDefault ??
            false,
    };
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

  Future<void> loadChannels() async {
    final records = await DebrifyTvRepository.instance.fetchAllChannels();
    if (!mounted) return;
    setState(() {
      _owners.library.channels = records
          .map(DebrifyTvChannel.fromRecord)
          .toList(growable: false);
    });
    // Every path that reloads channels (create, edit, delete-all, ZIP/YAML/
    // community imports) has fresh pools too, so the rail's pips ride along
    // here rather than each call site remembering to refresh them.
    if (_owners.library.debrifyTvStyle == 'spotlight') {
      await loadSpotlightRailHealth();
    }
  }

  void handleSyncedDebrifyTvLibraryChanged() {
    if (!mounted) return;
    setState(() {
      _owners.library.channelCache.clear();
      _owners.stage.spotlightStats.clear();
      _owners.stage.spotlightRailHealth = const <String, DebrifyTvRailHealth>{};
    });
    unawaited(loadChannels());
  }

  Future<void> loadFavoriteChannels() async {
    final favoriteIds = await DebrifyTvStorage.getDebrifyTvFavoriteChannelIds();
    if (!mounted) return;
    setState(() {
      _owners.library.favoriteChannelIds = favoriteIds;
    });
  }

  Future<void> toggleChannelFavorite(DebrifyTvChannel channel) async {
    final isFavorited = _owners.library.favoriteChannelIds.contains(channel.id);
    final newState = !isFavorited;

    await DebrifyTvStorage.setDebrifyTvChannelFavorited(channel.id, newState);

    if (!mounted) return;
    setState(() {
      if (newState) {
        _owners.library.favoriteChannelIds = {
          ..._owners.library.favoriteChannelIds,
          channel.id,
        };
      } else {
        _owners.library.favoriteChannelIds = _owners.library.favoriteChannelIds
            .where((id) => id != channel.id)
            .toSet();
      }
    });
  }

  /// Watch a channel by ID (called from external sources like home screen)
  Future<void> watchChannelById(String channelId) async {
    final channel = _owners.library.channels.firstWhereOrNull(
      (c) => c.id == channelId,
    );
    if (channel != null) {
      watchChannel(channel);
    } else {
      debugPrint('DebrifyTVScreen: Channel with ID $channelId not found');
    }
  }

  /// Check for pending auto-play channel from home screen
  Future<void> checkPendingAutoPlay() async {
    final channelId = MainPageBridge.getAndClearDebrifyTvChannelToAutoPlay();
    if (channelId == null) return;

    // Wait for channels to load
    int attempts = 0;
    const maxAttempts = 50; // 5 seconds max wait
    while (_owners.library.channels.isEmpty && attempts < maxAttempts) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
      if (!mounted) return;
    }

    if (_owners.library.channels.isEmpty) {
      debugPrint('DebrifyTVScreen: Channels not loaded for auto-play');
      return;
    }

    watchChannelById(channelId);
  }

  Future<DebrifyTvChannelCacheEntry> computeChannelCacheEntry(
    DebrifyTvChannel channel,
    List<String> normalizedKeywords, {
    DebrifyTvChannelCacheEntry? baseline,
    Set<String>? keywordsToSearch,
  }) async {
    // The channel's own NSFW setting, FLOORED by the viewer: filtering is
    // role-locked for a child profile no matter who authored the channel or
    // what its stored flag says (the rail is viewer-scoped, evaluated at
    // search/play — never only at creation).
    final channelAvoidNsfw =
        channel.avoidNsfw || _owners.settings.viewerForcesNsfw;
    final registry = EngineRegistry.instance;
    await registry.initialize();
    final enabledTvEngines = enabledTvKeywordEngines(registry);
    final now = DateTime.now().millisecondsSinceEpoch;

    final accumulator = <String, CachedTorrent>{};
    final stats = <String, KeywordStat>{};

    if (baseline != null) {
      for (final cached in _filterCachedTorrentsForKeywords(
        baseline,
        normalizedKeywords,
      )) {
        final normalizedHash = normalizeInfohash(cached.infohash);
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
    if (enabledTvEngines.isEmpty && keywordsToWarm.isNotEmpty) {
      debugPrint(
        'DebrifyTV: No enabled TV search engines for "${channel.name}".',
      );
    }

    bool anySuccess = accumulator.isNotEmpty;
    String? failureMessage;

    List<String> pendingKeywords = List<String>.from(keywordsToWarm);
    while (pendingKeywords.isNotEmpty) {
      final batch = pendingKeywords
          .take(_owners.settings.channelBatchSize)
          .toList();
      pendingKeywords = pendingKeywords.skip(batch.length).toList();

      final futures = batch.map((keyword) async {
        return await _warmKeyword(
          keyword: keyword,
          enabledEngines: enabledTvEngines,
          accumulator: accumulator,
          stats: stats,
          now: now,
          totalKeywords: normalizedKeywords.length,
          avoidNsfw: channelAvoidNsfw, // Use channel's NSFW setting
          minTorrentsPerKeyword: _owners.settings.minTorrentsPerKeyword,
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

  Future<KeywordWarmResult?> _warmKeyword({
    required String keyword,
    required List<DynamicEngine> enabledEngines,
    required Map<String, CachedTorrent> accumulator,
    required Map<String, KeywordStat> stats,
    required int now,
    required int totalKeywords,
    required bool avoidNsfw, // Use channel's NSFW setting
    required int minTorrentsPerKeyword,
  }) async {
    final searchResults = await Future.wait(
      enabledEngines.map((engine) async {
        final maxResults = tvChannelMaxResultsForEngine(engine, totalKeywords);
        try {
          final torrents = await engine.executeSearch(
            query: keyword,
            maxResults: maxResults,
          );
          return _TvEngineWarmResult(
            engine: engine,
            torrents: torrents,
            pagesPulled: estimatePagesPulledForEngine(engine, torrents.length),
          );
        } catch (e) {
          debugPrint(
            'DebrifyTV: Cache warm ${engine.displayName} failed for "$keyword": $e',
          );
          return _TvEngineWarmResult(
            engine: engine,
            torrents: const <Torrent>[],
            pagesPulled: 0,
            failureMessage:
                '${engine.displayName} search failed. Some torrents may be missing.',
          );
        }
      }),
    );

    // Apply NSFW filter to search results before caching
    final filteredByEngine = <DynamicEngine, List<Torrent>>{};
    int totalBefore = 0;
    int totalAfter = 0;
    int pagesPulled = 0;
    final failureMessages = <String>[];

    for (final result in searchResults) {
      pagesPulled += result.pagesPulled;
      if (result.failureMessage != null) {
        failureMessages.add(result.failureMessage!);
      }

      final before = result.torrents.length;
      totalBefore += before;
      if (avoidNsfw) {
        final filtered = result.torrents.where((torrent) {
          if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
            return false;
          }
          return true;
        }).toList();
        totalAfter += filtered.length;
        filteredByEngine[result.engine] = filtered;
      } else {
        totalAfter += before;
        filteredByEngine[result.engine] = result.torrents;
      }
    }

    if (avoidNsfw && totalBefore != totalAfter) {
      debugPrint(
        'DebrifyTV: Cache NSFW filter for "$keyword": $totalBefore → $totalAfter torrents',
      );
    }

    // Check minimum torrents per keyword threshold
    final totalTorrents = filteredByEngine.values.fold<int>(
      0,
      (total, torrents) => total + torrents.length,
    );
    if (totalTorrents < minTorrentsPerKeyword) {
      debugPrint(
        'DebrifyTV: Skipping keyword "$keyword" – only $totalTorrents torrent(s), minimum is $minTorrentsPerKeyword',
      );
      final stat = (stats[keyword] ?? KeywordStat.initial())
          .copyWith(
            totalFetched: 0,
            lastSearchedAt: now,
            pagesPulled: pagesPulled,
          )
          .clearLegacySourceHits();
      return KeywordWarmResult(
        keyword: keyword,
        addedHashes: const <String>{},
        stat: stat,
        failureMessage: enabledEngines.isEmpty
            ? 'No enabled TV search engines.'
            : 'Too few torrents for "$keyword" (found $totalTorrents, need $minTorrentsPerKeyword)',
      );
    }

    final keywordHashes = <String>{};

    for (final entry in filteredByEngine.entries) {
      final source = entry.key.name;
      for (final torrent in entry.value) {
        final hash = normalizeInfohash(torrent.infohash);
        if (hash.isEmpty) {
          continue;
        }
        keywordHashes.add(hash);
        _accumulateCachedTorrent(
          accumulator: accumulator,
          infohash: hash,
          torrent: torrent,
          keyword: keyword,
          source: source,
        );
      }
    }

    final updatedStats = stats[keyword] ?? KeywordStat.initial();
    final stat = updatedStats
        .copyWith(
          totalFetched: keywordHashes.length,
          lastSearchedAt: now,
          pagesPulled: pagesPulled,
        )
        .clearLegacySourceHits();

    String? failureMessage;
    if (failureMessages.isNotEmpty) {
      failureMessage = failureMessages.first;
    } else if (filteredByEngine.values.every((torrents) => torrents.isEmpty)) {
      failureMessage = 'No torrents found for "$keyword" yet.';
    }

    return KeywordWarmResult(
      keyword: keyword,
      addedHashes: keywordHashes,
      stat: stat,
      failureMessage: failureMessage,
    );
  }

  Future<void> deleteChannel(String id) async {
    setState(() {
      _owners.library.channels = _owners.library.channels
          .where((c) => c.id != id)
          .toList();
    });
    await DebrifyTvRepository.instance.deleteChannel(id);
    setState(() {
      _owners.library.channelCache.remove(id);
      _owners.stage.spotlightStats.remove(id);
      _owners.stage.spotlightRailHealth = Map.of(
        _owners.stage.spotlightRailHealth,
      )..remove(id);
      // The layout's staged-channel repair fires onChannelFocused for its
      // replacement; a dangling id here would make that look like a no-move.
      if (_owners.stage.spotlightFocusedId == id)
        _owners.stage.spotlightFocusedId = null;
    });
  }

  Future<void> syncProviderAvailability() async {
    final rdIntegrationEnabled =
        await RealDebridStorage.getRealDebridIntegrationEnabled();
    final rdKey = await RealDebridStorage.getApiKey();
    final torboxIntegrationEnabled =
        await TorboxStorage.getTorboxIntegrationEnabled();
    final torboxKey = await TorboxStorage.getTorboxApiKey();
    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    final premiumizeIntegrationEnabled =
        await PremiumizeStorage.getPremiumizeIntegrationEnabled();
    final premiumizeKey = await PremiumizeStorage.getPremiumizeApiKey();
    final premiumizeAvailable =
        premiumizeIntegrationEnabled &&
        premiumizeKey != null &&
        premiumizeKey.isNotEmpty;
    final allDebridIntegrationEnabled =
        await AllDebridStorage.getAllDebridIntegrationEnabled();
    final allDebridKey = await AllDebridStorage.getAllDebridApiKey();
    final allDebridAvailable =
        allDebridIntegrationEnabled &&
        allDebridKey != null &&
        allDebridKey.isNotEmpty;

    final rdAvailable =
        rdIntegrationEnabled && rdKey != null && rdKey.isNotEmpty;
    final torboxAvailable =
        torboxIntegrationEnabled && torboxKey != null && torboxKey.isNotEmpty;

    final nextChannelProvider = determineDefaultProvider(
      _owners.settings.provider,
      rdAvailable,
      torboxAvailable,
      pikpakAvailable,
      premiumizeAvailable,
      allDebridAvailable,
    );
    final nextQuickProvider = determineDefaultProvider(
      _owners.settings.quickProvider,
      rdAvailable,
      torboxAvailable,
      pikpakAvailable,
      premiumizeAvailable,
      allDebridAvailable,
    );

    if (!mounted) return;
    final providerChanged = nextChannelProvider != _owners.settings.provider;
    setState(() {
      _owners.settings.rdAvailable = rdAvailable;
      _owners.settings.torboxAvailable = torboxAvailable;
      _owners.settings.pikpakAvailable = pikpakAvailable;
      _owners.settings.premiumizeAvailable = premiumizeAvailable;
      _owners.settings.allDebridAvailable = allDebridAvailable;
      _owners.settings.provider = nextChannelProvider;
      _owners.settings.quickProvider = nextQuickProvider;
    });

    if (providerChanged) {
      await DebrifyTvStorage.saveDebrifyTvProvider(nextChannelProvider);
    }
  }

  List<String> parseKeywords(String input) {
    return input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  List<String> normalizedKeywords(List<String> keywords) {
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

  Future<DebrifyTvChannelCacheEntry?> ensureCacheEntry(String channelId) async {
    final cached = _owners.library.channelCache[channelId];
    if (cached != null) {
      return cached;
    }
    final fetched = await DebrifyTvCacheService.getEntry(channelId);
    if (fetched != null) {
      _owners.library.channelCache[channelId] = fetched;
    }
    return fetched;
  }

  Future<List<String>> getChannelKeywords(String channelId) async {
    final index = _owners.library.channels.indexWhere((c) => c.id == channelId);
    if (index == -1) {
      return const <String>[];
    }
    final existing = _owners.library.channels[index];
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
      final next = List<DebrifyTvChannel>.from(_owners.library.channels);
      next[index] = updated;
      _owners.library.channels = next;
    });
    return fetched;
  }

  Future<TorboxCacheWindowResult> fetchTorboxCacheWindow({
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
          .map((torrent) => normalizeInfohash(torrent.infohash))
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
          (torrent) => normalized.contains(normalizeInfohash(torrent.infohash)),
        ),
      );
    }

    final bool exhausted = cursor >= candidates.length;
    return TorboxCacheWindowResult(
      cachedTorrents: hits,
      nextCursor: cursor,
      exhausted: exhausted,
    );
  }

  int estimatedWarmDurationSeconds(
    int keywordCount, {
    int? totalKeywordUniverse,
  }) {
    if (keywordCount <= 0) {
      return 0;
    }

    final int effectiveUniverse = max(1, totalKeywordUniverse ?? keywordCount);
    final enabledEngines = enabledTvKeywordEngines(EngineRegistry.instance);
    if (enabledEngines.isEmpty) {
      return 0;
    }

    final int batches = max(
      1,
      ((keywordCount + _owners.settings.channelBatchSize - 1) ~/
          _owners.settings.channelBatchSize),
    );

    final int requestWavesPerKeyword = enabledEngines.fold<int>(
      1,
      (current, engine) => max(
        current,
        _estimatePageRequestsForEngine(engine, effectiveUniverse),
      ),
    );
    final int estimatedMs =
        batches *
        requestWavesPerKeyword *
        DebrifyTvConstants.keywordWarmEstimateMs;

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

  /// Narrows a channel's cached torrents to the user's quality filter.
  /// Applied at cache READ time (not warm time) so changing the filter takes
  /// effect immediately instead of forcing a full channel rebuild the way the
  /// NSFW toggle does. Returns the input untouched when the filter is off, and
  /// falls back to the unfiltered pool (with a snackbar) when a channel has
  /// nothing at the requested quality — a filtered channel that plays nothing
  /// reads as broken, so it degrades instead of failing.
  List<CachedTorrent> _applyQualityFilterToCached(List<CachedTorrent> all) {
    if (!_owners.settings.tvFilters.hasQuality || all.isEmpty) return all;
    final matched = all
        .where(
          (cached) =>
              _owners.settings.tvFilters.qualityMatchesName(cached.name),
        )
        .toList();
    if (matched.isEmpty) {
      debugPrint(
        'DebrifyTV: Quality filter matched 0/${all.length} cached torrents — '
        'falling back to unfiltered.',
      );
      notifyQualityFallback();
      return all;
    }
    if (matched.length != all.length) {
      debugPrint(
        'DebrifyTV: Quality filter on cached: ${all.length} → ${matched.length} torrents',
      );
    }
    return matched;
  }

  /// Quick-play twin of [_applyQualityFilterToCached], for the live search
  /// results each provider accumulates.
  ///
  /// [allowFallback] must stay false while a search is still streaming in.
  /// Quick play rebuilds this list on every engine that reports, and the RD
  /// flow launches the player from the first rebuild that yields something
  /// playable — so falling back on a partial result set would start playing an
  /// off-filter source just because the fastest engine happened to return
  /// none. Strict here means the queue simply stays empty until a matching
  /// result arrives. Pass true only once the result set is final, where an
  /// empty match genuinely means "this search has nothing".
  List<Torrent> applyQualityFilterToTorrents(
    List<Torrent> torrents, {
    bool allowFallback = false,
  }) {
    if (!_owners.settings.tvFilters.hasQuality || torrents.isEmpty)
      return torrents;
    final matched = torrents
        .where((t) => _owners.settings.tvFilters.qualityMatchesName(t.name))
        .toList();
    if (matched.isEmpty && allowFallback) {
      notifyQualityFallback();
      return torrents;
    }
    return matched;
  }

  /// Tells the user once per playback session that the quality filter was
  /// relaxed. Rate-limited because the quick-play queue is rebuilt per engine
  /// and channel switches re-enter the same path.
  void notifyQualityFallback() {
    if (_owners.session.qualityFallbackNotified) return;
    _owners.session.qualityFallbackNotified = true;
    showSnack(
      'No ${_owners.settings.tvFilters.summary()} sources found — playing anything available.',
      color: Colors.orange,
    );
  }

  /// Whether an unrestricted Real-Debrid link may be played, per the size
  /// rules. RD is the one provider that hands back a flat list of links with
  /// no per-file metadata, so a file's size is only knowable AFTER
  /// unrestricting it — hence the check here rather than up front like the
  /// others. Links whose size RD doesn't report are accepted.
  ///
  /// Because RD can't pre-filter, a strict size choice could otherwise walk
  /// the entire queue rejecting everything. After
  /// [_rdSizeRejectionLimit] consecutive size-only rejections the size filter
  /// is relaxed for the rest of the session (with a snackbar) — the same
  /// degrade-don't-fail contract the other providers get per torrent.
  bool rdLinkPassesSizeRules(Map<String, dynamic> unrestrict) {
    final bytes = (unrestrict['filesize'] as num?)?.toInt() ?? 0;
    if (bytes <= 0) return true; // RD didn't report a size — don't guess.
    // Trailer/sample guard, matching Torbox/Premiumize/PikPak/AllDebrid.
    if (bytes < DebrifyTvConstants.torboxMinVideoSizeBytes) return false;
    if (_owners.session.sizeFilterRelaxed ||
        !_owners.settings.tvFilters.hasSize)
      return true;
    if (_owners.settings.tvFilters.sizeMatchesBytes(bytes)) {
      _owners.session.rdSizeRejections = 0;
      return true;
    }
    _owners.session.rdSizeRejections++;
    if (_owners.session.rdSizeRejections >=
        DebrifyTvConstants.rdSizeRejectionLimit) {
      _owners.session.sizeFilterRelaxed = true;
      showSnack(
        'Few ${_owners.settings.tvFilters.summary()} files here — playing other sizes too.',
        color: Colors.orange,
      );
      return true;
    }
    return false;
  }

  List<CachedTorrent> selectTorrentsForPlayback(
    DebrifyTvChannelCacheEntry entry,
    List<String> normalizedKeywords,
  ) {
    // Filter BEFORE the per-keyword/threshold narrowing below, so the
    // selection draws from the full matching pool rather than from a
    // pre-narrowed sample that the filter then guts.
    final all = _applyQualityFilterToCached(entry.torrents);
    if (all.length <= DebrifyTvConstants.playbackTorrentThreshold) {
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
          final hash = normalizeInfohash(cached.infohash);
          if (hash.isEmpty || seenHashes.contains(hash)) {
            continue;
          }
          selected.add(cached);
          seenHashes.add(hash);
          count++;
          if (count >= DebrifyTvConstants.maxTorrentsPerKeywordPlayback) {
            break;
          }
        }
      }
    }

    if (selected.isEmpty) {
      return all.take(DebrifyTvConstants.playbackTorrentThreshold).toList();
    }

    if (selected.length < DebrifyTvConstants.playbackTorrentThreshold) {
      for (final cached in all) {
        final hash = normalizeInfohash(cached.infohash);
        if (hash.isEmpty || seenHashes.contains(hash)) {
          continue;
        }
        selected.add(cached);
        seenHashes.add(hash);
        if (selected.length >= DebrifyTvConstants.playbackTorrentThreshold) {
          break;
        }
      }
    }

    final random = Random();
    selected.shuffle(random);
    return selected;
  }

  String providerDisplay(String provider) {
    if (provider == DebrifyTvConstants.providerTorbox) return 'Torbox';
    if (provider == DebrifyTvConstants.providerPikPak) return 'PikPak';
    if (provider == DebrifyTvConstants.providerPremiumize) return 'Premiumize';
    if (provider == DebrifyTvConstants.providerAllDebrid) return 'AllDebrid';
    return 'Real Debrid';
  }

  /// Quality + size pickers for Debrify TV playback. One shared setting for
  /// both channels and quick play, so the same feed rules apply wherever you
  /// start watching. Nothing selected in a row = that facet is off.
  Widget tvFilterChips({StateSetter? dialogSetState}) {
    void applyFilters(DebrifyTvFilters next) {
      setState(() => _owners.settings.tvFilters = next);
      // "At your quality" is computed WITH the filter; stale memos would
      // keep the old filter's count while playback uses the new one.
      invalidateSpotlightStats();
      dialogSetState?.call(() {});
    }

    void toggleQuality(QualityTier quality) {
      final next = Set<QualityTier>.from(_owners.settings.tvFilters.qualities);
      if (!next.remove(quality)) next.add(quality);
      applyFilters(
        DebrifyTvFilters(
          qualities: next,
          sizes: _owners.settings.tvFilters.sizes,
        ),
      );
      unawaited(
        DebrifyTvStorage.setDebrifyTvFilterQualities(
          next.map((e) => e.name).toList(),
        ),
      );
    }

    void toggleSize(SizeBucket bucket) {
      final next = Set<SizeBucket>.from(_owners.settings.tvFilters.sizes);
      if (!next.remove(bucket)) next.add(bucket);
      applyFilters(
        DebrifyTvFilters(
          qualities: _owners.settings.tvFilters.qualities,
          sizes: next,
        ),
      );
      unawaited(
        DebrifyTvStorage.setDebrifyTvFilterSizes(
          next.map((e) => e.name).toList(),
        ),
      );
    }

    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: AppThemeScope.of(context).debrifyTv.textMeta,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Playback filters',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          'Applies to channels and quick play. If nothing matches, Debrify TV '
          'plays what it can rather than showing an empty channel.',
          style: labelStyle,
        ),
        const SizedBox(height: 10),
        Text('Quality', style: labelStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final quality in QualityTier.values)
              _SpotlightChoiceChip(
                label: DebrifyTvFilters.qualityLabel(quality),
                selected: _owners.settings.tvFilters.qualities.contains(
                  quality,
                ),
                enabled: !_owners.session.isBusy,
                onPressed: () => toggleQuality(quality),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('File size (per episode/movie)', style: labelStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final bucket in SizeBucket.values)
              _SpotlightChoiceChip(
                label: DebrifyTvFilters.sizeLabel(bucket),
                selected: _owners.settings.tvFilters.sizes.contains(bucket),
                enabled: !_owners.session.isBusy,
                onPressed: () => toggleSize(bucket),
              ),
          ],
        ),
      ],
    );
  }

  Widget providerChoiceChips(
    DebrifyTvSettingsScope scope, {
    StateSetter? dialogSetState,
  }) {
    final bool isQuickScope = scope == DebrifyTvSettingsScope.quickPlay;
    final String currentProvider = isQuickScope
        ? _owners.settings.quickProvider
        : _owners.settings.provider;

    void handleSelection(String value) {
      if (!isProviderSelectable(value)) {
        return;
      }
      if (isQuickScope) {
        if (_owners.settings.quickProvider == value) {
          return;
        }
        setState(() {
          _owners.settings.quickProvider = value;
        });
        dialogSetState?.call(() {});
        return;
      }

      if (_owners.settings.provider == value) {
        return;
      }
      setState(() {
        _owners.settings.provider = value;
      });
      dialogSetState?.call(() {});
      unawaited(DebrifyTvStorage.saveDebrifyTvProvider(value));
    }

    Widget providerChip({
      required String value,
      required String label,
      required bool available,
      required String unavailableMessage,
    }) {
      return Tooltip(
        message: available ? 'Use $label for Debrify TV' : unavailableMessage,
        child: _SpotlightChoiceChip(
          label: label,
          selected: currentProvider == value,
          enabled: available && !_owners.session.isBusy,
          onPressed: () => handleSelection(value),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        providerChip(
          value: DebrifyTvConstants.providerRealDebrid,
          label: 'Real Debrid',
          available: _owners.settings.rdAvailable,
          unavailableMessage:
              'Enable Real Debrid and add an API key in Settings.',
        ),
        providerChip(
          value: DebrifyTvConstants.providerTorbox,
          label: 'Torbox',
          available: _owners.settings.torboxAvailable,
          unavailableMessage: 'Enable Torbox and add an API key in Settings.',
        ),
        providerChip(
          value: DebrifyTvConstants.providerPikPak,
          label: 'PikPak',
          available: _owners.settings.pikpakAvailable,
          unavailableMessage: 'Log in to PikPak in Settings.',
        ),
        providerChip(
          value: DebrifyTvConstants.providerPremiumize,
          label: 'Premiumize',
          available: _owners.settings.premiumizeAvailable,
          unavailableMessage:
              'Enable Premiumize and add an API key in Settings.',
        ),
        providerChip(
          value: DebrifyTvConstants.providerAllDebrid,
          label: 'AllDebrid',
          available: _owners.settings.allDebridAvailable,
          unavailableMessage:
              'Enable AllDebrid and add an API key in Settings.',
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
    final parsed = parseKeywords(raw.replaceAll('\n', ','));
    if (parsed.isEmpty) return false;
    var limitReached = false;
    setState(() {
      for (final kw in parsed) {
        if (keywordList.length >= DebrifyTvConstants.maxChannelKeywords) {
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
    return limitReached ||
        keywordList.length >= DebrifyTvConstants.maxChannelKeywords;
  }

  Future<DebrifyTvChannel?> openChannelDialog({
    DebrifyTvChannel? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final keywordInputController = TextEditingController();
    FocusNode? channelNameFocus;
    FocusNode? channelKeywordFocus;
    if (_owners.settings.isAndroidTv) {
      channelNameFocus = FocusNode(debugLabel: 'DebrifyTVChannelName');
      channelKeywordFocus = FocusNode(debugLabel: 'DebrifyTVChannelKeyword');
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
      if (keywordList.length >= DebrifyTvConstants.maxChannelKeywords) break;
    }
    // Channel defaults - keep NSFW preference per channel only
    bool avoidNsfw = existing?.avoidNsfw ?? true;
    String? error;

    DebrifyTvChannel? result;
    try {
      result = await showDialog<DebrifyTvChannel>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              final app = AppThemeScope.of(context);
              final tv = app.debrifyTv;
              Future<void> submit() async {
                final pendingRaw = keywordInputController.text.trim();
                if (pendingRaw.isNotEmpty) {
                  final pendingKeywords = parseKeywords(pendingRaw);
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
                    if (keywordList.length >=
                        DebrifyTvConstants.maxChannelKeywords) {
                      setModalState(() {
                        error =
                            'You can add up to ${DebrifyTvConstants.maxChannelKeywords} keywords per channel.';
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
                if (keywords.length > DebrifyTvConstants.maxChannelKeywords) {
                  setModalState(() {
                    error =
                        'You can add up to ${DebrifyTvConstants.maxChannelKeywords} keywords per channel.';
                  });
                  return;
                }
                final now = DateTime.now();
                final channel = DebrifyTvChannel(
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

              return DebrifyTvSpotlightDialog(
                eyebrow: existing == null
                    ? 'Channel editor · new'
                    : 'Channel editor · ${existing.channelNumber.toString().padLeft(2, '0')}',
                title: existing == null ? 'Create a channel' : 'Edit channel',
                subtitle:
                    'Keywords are search terms. Add one or several and Debrify will pool the results.',
                icon: Icons.tv_rounded,
                maxWidth: 720,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TvTextField(
                      controller: nameController,
                      focusNode: channelNameFocus,
                      autofocus: _owners.settings.isAndroidTv,
                      textCapitalization: TextCapitalization.words,
                      // The shared TV shell/keyboard chrome follows
                      // settings.accent. NOT debrifyTv.accent: legacy
                      // paints that the channel grid's Netflix red, while
                      // the keyboard's highlight has always been violet.
                      accent: app.settings.accent,
                      keyboardGround: app.youtube.keyboardPanel,
                      keyboardInk: app.core.tx,
                      keyboardInkOnAccent: app.inkOn(app.settings.accent),
                      decoration: const InputDecoration(
                        labelText: 'Channel name',
                        prefixIcon: Icon(Icons.label_rounded),
                      ),
                      onDownArrow: () => channelKeywordFocus?.requestFocus(),
                      onUpArrow: () {
                        final ctx = channelNameFocus?.context;
                        if (ctx != null) {
                          FocusScope.of(ctx).previousFocus();
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Keywords (${keywordList.length}/${DebrifyTvConstants.maxChannelKeywords})',
                      style: TextStyle(
                        color: tv.textDim,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tip: type a keyword and press Enter. Add multiples by separating with commas.',
                      style: TextStyle(color: tv.textFaint, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...keywordList.map(
                          (keyword) => _SpotlightChoiceChip(
                            label: keyword,
                            selected: false,
                            enabled: true,
                            trailingIcon: Icons.close_rounded,
                            onPressed: () {
                              setModalState(() {
                                keywordList.remove(keyword);
                                if (error != null &&
                                    error!.contains(
                                      '${DebrifyTvConstants.maxChannelKeywords} keywords',
                                    ) &&
                                    keywordList.length <
                                        DebrifyTvConstants.maxChannelKeywords) {
                                  error = null;
                                }
                              });
                            },
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: TvTextField(
                            controller: keywordInputController,
                            focusNode: channelKeywordFocus,
                            decoration: const InputDecoration(
                              hintText: 'Add keyword',
                              prefixIcon: Icon(Icons.add_rounded),
                            ),
                            style: TextStyle(color: app.core.tx),
                            // Shared TV shell/keyboard chrome — see the
                            // channel-name field above.
                            accent: app.settings.accent,
                            keyboardGround: app.youtube.keyboardPanel,
                            keyboardInk: app.core.tx,
                            keyboardInkOnAccent: app.inkOn(app.settings.accent),
                            onUpArrow: () => channelNameFocus?.requestFocus(),
                            onDownArrow: () {
                              final ctx = channelKeywordFocus?.context;
                              if (ctx != null) {
                                FocusScope.of(ctx).nextFocus();
                              }
                            },
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
                                      'You can add up to ${DebrifyTvConstants.maxChannelKeywords} keywords per channel.';
                                });
                              } else if (error != null &&
                                  error!.contains(
                                    '${DebrifyTvConstants.maxChannelKeywords} keywords',
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
                                        'You can add up to ${DebrifyTvConstants.maxChannelKeywords} keywords per channel.';
                                  });
                                } else if (error != null &&
                                    error!.contains(
                                      '${DebrifyTvConstants.maxChannelKeywords} keywords',
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
                    const SizedBox(height: 18),
                    DebrifyTvDialogSection(
                      label: 'Channel settings',
                      child: SwitchRow(
                        title: 'Avoid NSFW content',
                        subtitle: _owners.settings.viewerForcesNsfw
                            ? 'Always on for this profile'
                            : 'Best-effort filter while building this channel',
                        value: _owners.settings.viewerForcesNsfw || avoidNsfw,
                        onChanged: (v) {
                          if (_owners.settings.viewerForcesNsfw) return;
                          setModalState(() => avoidNsfw = v);
                        },
                      ),
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
                actions: [
                  DebrifyTvDialogButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                  DebrifyTvDialogButton(
                    label: 'Save channel',
                    icon: Icons.check_rounded,
                    tone: DebrifyTvDialogButtonTone.primary,
                    onPressed: submit,
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      void disposer() {
        channelNameFocus?.dispose();
        channelKeywordFocus?.dispose();
        nameController.dispose();
        keywordInputController.dispose();
      }

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => disposer());
      } else {
        disposer();
      }
    }

    return result;
  }

  Future<void> handleImportChannels() async {
    if (_owners.session.isBusy) {
      return;
    }

    // Set busy to block interactions during dialog
    setState(() {
      _owners.session.isBusy = true;
    });

    final mode = await _selectImportMode();

    // Wait for frames to ensure UI has updated and touch events are processed
    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    if (mode == null || !mounted) {
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
        });
      }
      return;
    }

    switch (mode) {
      case ImportChannelsMode.device:
        await _handleImportChannelsFromDevice();
        break;
      case ImportChannelsMode.url:
        await handleImportChannelsFromUrl();
        break;
      case ImportChannelsMode.community:
        await _handleImportChannelsFromCommunity();
        break;
    }
  }

  Future<ImportChannelsMode?> _selectImportMode() async {
    if (!mounted) {
      return null;
    }

    return showDialog<ImportChannelsMode>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return ImportChannelsDialog(isAndroidTv: _owners.settings.isAndroidTv);
      },
    );
  }

  Future<T> _runChannelExportProgress<T>(
    Future<T> Function(void Function(String) setStage) run,
  ) async {
    if (!mounted) {
      throw StateError('Channel export screen is no longer available');
    }
    final stage = ValueNotifier<String>('Reading selected channel pools…');
    final done = ValueNotifier<bool>(false);
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (_) => ChannelExportProgressDialog(stage: stage, done: done),
    );
    try {
      return await run((value) => stage.value = value);
    } finally {
      done.value = true;
      await dialog;
      stage.dispose();
      done.dispose();
    }
  }

  Future<void> _showChannelExportUnavailableOnAppleTv() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (dialogContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.of(dialogContext).pop();
        },
        child: DebrifyTvSpotlightDialog(
          eyebrow: 'Channel export · Apple TV',
          title: 'Export from another device',
          subtitle:
              'Apple TV does not expose a location where Debrify can save a '
              'portable ZIP. Export the channels from Debrify on a phone or '
              'computer, or send them through Remote.',
          icon: Icons.tv_rounded,
          maxWidth: 580,
          actions: <Widget>[
            DebrifyTvDialogButton(
              autofocus: true,
              label: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }

  Future<void> handleExportChannels() async {
    if (_owners.session.isBusy || !mounted) return;
    if (PlatformUtil.isTvOS) {
      await _showChannelExportUnavailableOnAppleTv();
      return;
    }

    setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Loading channels for export…';
    });

    try {
      final capability = await ProfileAsyncAuthorization.capture(
        ProfileFeature.debrifyTv,
      );
      Future<T> runCaptured<T>(Future<T> Function() body) =>
          capability == null ? body() : capability.runIfCurrent(body);

      final channels = await runCaptured(
        DebrifyTvRepository.instance.fetchAllChannels,
      );
      final health = await runCaptured(DebrifyTvCacheService.loadRailHealth);
      if (!mounted) return;
      if (channels.isEmpty) {
        showSnack('There are no channels to export.', color: Colors.orange);
        return;
      }

      final selectedIds = await showDialog<Set<String>>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: .72),
        builder: (_) => ExportChannelsDialog(
          channels: channels,
          savedHashCounts: <String, int>{
            for (final entry in health.entries) entry.key: entry.value.pooled,
          },
        ),
      );
      if (!mounted || selectedIds == null || selectedIds.isEmpty) return;

      setState(() => _owners.session.status = 'Preparing channel archive…');
      late List<DebrifyTvChannelArchiveSource> sources;
      final bytes = await _runChannelExportProgress<Uint8List>((
        setStage,
      ) async {
        sources = await runCaptured(() async {
          // Re-read after the selection dialog: a channel can be edited or
          // removed while an overlay is open, and the archive must reflect
          // the rows that actually exist at export time.
          final current = await DebrifyTvRepository.instance.fetchAllChannels();
          final selected = current
              .where((channel) => selectedIds.contains(channel.channelId))
              .toList(growable: false);
          final result = <DebrifyTvChannelArchiveSource>[];
          for (var index = 0; index < selected.length; index++) {
            final channel = selected[index];
            setStage(
              'Reading channel ${index + 1} of ${selected.length}: '
              '${channel.name}',
            );
            result.add(
              DebrifyTvChannelArchiveSource(
                channel: channel,
                cacheEntry:
                    await DebrifyTvCacheService.getEntryForPortableExport(
                      channel.channelId,
                    ),
              ),
            );
          }
          return result;
        });
        if (sources.isEmpty) {
          throw StateError('The selected channels are no longer available');
        }
        setStage('Compressing ${sources.length} channels into one ZIP…');
        return DebrifyTvChannelArchiveService.buildZip(sources);
      });
      if (!mounted) return;
      if (bytes.length > DebrifyTvZipImporter.maxPortableFileBytes) {
        showSnack(
          'The ZIP is over 100 MB. Export fewer channels at a time.',
          color: Colors.orange,
        );
        return;
      }

      if (capability != null) {
        await capability.runIfCurrent(() async {});
      }
      if (!mounted) return;
      final now = DateTime.now();
      final stamp = <int>[
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
      ].map((part) => part.toString().padLeft(2, '0')).join();
      final savedPath = await ProfileBackupFlows(context).saveBackupFile(
        fileName: 'debrify-tv-channels-$stamp.zip',
        bytes: bytes,
        mimeType: 'application/zip',
        artifactLabel: 'channel archive',
      );
      if (!mounted || savedPath == null) return;
      final hashes = sources.fold<int>(
        0,
        (sum, source) => sum + source.savedHashCount,
      );
      showSnack(
        'Exported ${sources.length} channel${sources.length == 1 ? '' : 's'} '
        'with $hashes saved hash${hashes == 1 ? '' : 'es'}.',
        color: Colors.green,
      );
    } catch (error) {
      debugPrint(
        'DebrifyTV: channel archive export failed (${error.runtimeType})',
      );
      if (mounted) {
        showSnack('Failed to export channels.', color: Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
          _owners.session.status = '';
        });
      }
    }
  }

  Future<void> handleAddChannel() async {
    await syncProviderAvailability();
    final channel = await openChannelDialog();
    if (channel != null) {
      await createOrUpdateChannel(channel, isEdit: false);
    }
  }

  Future<void> _handleImportChannelsFromDevice() async {
    // FileType.any instead of custom: Android has no MimeTypeMap entry for
    // `yaml`/`yml`/`debrify`, so a custom filter silently greys those files out
    // in the system picker (and throws "Unsupported filter" outright when every
    // extension is unmapped). The importer validates the bytes/format below.
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      withReadStream: true,
    );

    if (selection == null || selection.files.isEmpty) {
      return;
    }

    final pickedFile = selection.files.first;

    // Reject an implausibly large pick before reading it into memory.
    if (pickedFile.size > DebrifyTvZipImporter.maxPortableFileBytes) {
      showSnack('Selected file is too large to import.', color: Colors.orange);
      return;
    }
    Uint8List bytes;
    try {
      bytes = await _readPickedFileBytes(pickedFile);
    } catch (error) {
      showSnack(
        'Unable to read selected file: ${formatImportError(error)}',
        color: Colors.red,
      );
      return;
    }

    if (bytes.isEmpty) {
      showSnack('Selected file appears to be empty.', color: Colors.orange);
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Importing channel from local storage…';
    });

    try {
      await safeImportChannelBytes(
        sourceName: pickedFile.name,
        bytes: bytes,
        origin: DebrifyTvChannelImportOrigin.device,
      );
    } catch (error) {
      showSnack(
        'Import failed: ${formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
          _owners.session.status = '';
        });
        closeProgressDialog();
      }
    }
  }

  Future<void> handleImportChannelsFromUrl() async {
    final input = await _promptImportUrl();
    if (input == null) {
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
        });
      }
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
      showSnack(
        'Enter a valid debrify:// link or http(s) URL.',
        color: Colors.red,
      );
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
        });
      }
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Downloading channel file…';
    });

    showChannelCreationDialog('Importing channel…');
    updateProgress(['Downloading channel file…']);

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
            : 'Downloading… ${formatDebrifyTvBytes(receivedBytes)}';
        updateProgress([progressMessage], replace: true);
      }

      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        updateProgress(['Downloaded file is empty.'], replace: true);
        showSnack('Downloaded file is empty.', color: Colors.orange);
        return;
      }

      final sourceName = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : 'channel.${_guessExtensionFromHeaders(streamedResponse.headers)}';

      updateProgress(['Download complete. Processing…'], replace: true);

      await safeImportChannelBytes(
        sourceName: sourceName,
        bytes: bytes,
        origin: DebrifyTvChannelImportOrigin.url,
      );
    } catch (error) {
      showSnack(
        'Import failed: ${formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
          _owners.session.status = '';
        });
        closeProgressDialog();
      }
    }
  }

  Future<void> _handleImportChannelsFromCommunity() async {
    final selectedChannels = await _promptCommunityChannelsDialog();
    if (selectedChannels == null || selectedChannels.isEmpty) {
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
        });
      }
      return;
    }

    // Wait for frames to ensure UI has updated and touch events are processed
    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Importing community channels...';
    });

    showChannelCreationDialog('Importing community channels...');

    int successCount = 0;
    int failureCount = 0;
    final List<String> errors = [];

    for (int i = 0; i < selectedChannels.length; i++) {
      final channel = selectedChannels[i];
      updateProgress([
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
        final success = await importDebrifyBytes(
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

    updateProgress([
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

    showSnack(message, color: snackColor);

    // Keep dialog open for 2 seconds to show summary
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _owners.session.isBusy = false;
        _owners.session.status = '';
      });
      closeProgressDialog();
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
        return CommunityChannelsDialog(
          isAndroidTv: _owners.settings.isAndroidTv,
        );
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
    required DebrifyTvChannelImportOrigin origin,
  }) async {
    final type = _determineImportType(sourceName, bytes);
    if (type == null) {
      showSnack(
        'Unsupported file type. Select a .zip, .yaml, .txt, or .debrify file.',
        color: Colors.orange,
      );
      return false;
    }

    switch (type) {
      case DebrifyTvChannelImportType.zip:
        return await _importZipBytes(bytes, origin);
      case DebrifyTvChannelImportType.yaml:
        return await _importYamlBytes(sourceName, bytes, origin);
      case DebrifyTvChannelImportType.text:
        return await _importTextBytes(sourceName, bytes);
      case DebrifyTvChannelImportType.debrify:
        return await importDebrifyBytes(sourceName, bytes);
    }
  }

  Future<bool> safeImportChannelBytes({
    required String sourceName,
    required Uint8List bytes,
    required DebrifyTvChannelImportOrigin origin,
  }) async {
    try {
      return await _importChannelBytes(
        sourceName: sourceName,
        bytes: bytes,
        origin: origin,
      );
    } on FormatException catch (error) {
      showSnack(error.message, color: Colors.red);
      return false;
    } catch (error) {
      // Corrupt archives throw ArchiveException/RangeError etc., not just
      // FormatException — surface them the same way instead of leaving the
      // import flow (and any progress dialog) stuck.
      showSnack('Failed to import channel file: $error', color: Colors.red);
      return false;
    }
  }

  DebrifyTvChannelImportType? _determineImportType(
    String sourceName,
    Uint8List bytes,
  ) {
    final lower = sourceName.toLowerCase();

    // Check extension first
    if (lower.endsWith('.zip')) {
      return DebrifyTvChannelImportType.zip;
    }
    if (lower.endsWith('.debrify')) {
      return DebrifyTvChannelImportType.debrify;
    }
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return DebrifyTvChannelImportType.yaml;
    }
    if (lower.endsWith('.txt')) {
      return DebrifyTvChannelImportType.text;
    }

    // Fallback: check file signature for zip
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
      // PK — zip signature
      return DebrifyTvChannelImportType.zip;
    }

    // Smart content detection for unknown extensions
    try {
      final content = utf8.decode(bytes).trim();
      if (content.startsWith('debrify://')) {
        return DebrifyTvChannelImportType.debrify;
      }
    } catch (_) {
      // If UTF-8 decode fails, not a text file
    }

    return null;
  }

  Future<bool> _importZipBytes(
    Uint8List bytes,
    DebrifyTvChannelImportOrigin origin,
  ) async {
    final dialogLabel = origin == DebrifyTvChannelImportOrigin.device
        ? 'Importing zip…'
        : 'Processing zip…';

    showChannelCreationDialog(dialogLabel);
    updateProgress(['Parsing archive…']);

    final parsed = await parseZipInBackground(bytes);
    updateProgress([
      'Parsed ${parsed.channels.length} channel(s)',
      'Saving channel data…',
    ]);

    final persistence = await persistImportedZipChannels(parsed.channels);
    updateProgress([
      'Saved ${persistence.successes.length} channel(s)',
      if (persistence.failures.isNotEmpty)
        '${persistence.failures.length} channel(s) failed',
    ]);

    await showZipImportSummary(parsed, persistence);
    return persistence.successes.isNotEmpty;
  }

  Future<bool> _importYamlBytes(
    String sourceName,
    Uint8List bytes,
    DebrifyTvChannelImportOrigin origin,
  ) async {
    final content = utf8.decode(bytes);
    final dialogLabel = origin == DebrifyTvChannelImportOrigin.device
        ? 'Importing YAML…'
        : 'Processing YAML…';

    showChannelCreationDialog(dialogLabel);
    updateProgress(['Parsing YAML…']);

    final channel = await parseYamlInBackground(sourceName, content);

    final parsed = DebrifyTvZipImportResult(
      channels: [channel],
      failures: const [],
    );

    updateProgress(['Saving channel…']);
    final persistence = await persistImportedZipChannels(parsed.channels);
    updateProgress([
      'Saved ${persistence.successes.length} channel(s)',
      if (persistence.failures.isNotEmpty)
        '${persistence.failures.length} channel(s) failed',
    ]);

    await showZipImportSummary(parsed, persistence);
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
    final lowerExisting = _owners.library.channels
        .map((c) => c.name.toLowerCase())
        .toSet();
    final channelName = resolveUniqueChannelName(baseName, lowerExisting);
    final now = DateTime.now();
    final channel = DebrifyTvChannel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: channelName,
      keywords: keywords,
      avoidNsfw: true,
      channelNumber: 0,
      createdAt: now,
      updatedAt: now,
    );

    await createOrUpdateChannel(channel, isEdit: false);
    showSnack('Imported "${channel.name}"', color: Colors.green);
    return true;
  }

  Future<bool> importDebrifyBytes(
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
      showChannelCreationDialog('Importing channel…');
    }
    updateProgress(['Decoding debrify link…']);

    // Decode debrify link
    final result = MagnetYamlService.decode(content);

    updateProgress(['Parsing channel data…']);

    // Parse the decoded YAML
    final channel = await parseYamlInBackground(
      result.channelName,
      result.yamlContent,
    );

    final parsed = DebrifyTvZipImportResult(
      channels: [channel],
      failures: const [],
    );

    updateProgress(['Saving channel…']);
    final persistence = await persistImportedZipChannels(parsed.channels);
    updateProgress([
      'Saved ${persistence.successes.length} channel(s)',
      if (persistence.failures.isNotEmpty)
        '${persistence.failures.length} channel(s) failed',
    ]);

    if (showSummary) {
      await showZipImportSummary(parsed, persistence);
    }
    return persistence.successes.isNotEmpty;
  }

  Future<void> _importDebrifyLinkDirectly(String debrifyLink) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Decoding debrify link…';
    });

    try {
      final bytes = utf8.encode(debrifyLink);
      await safeImportChannelBytes(
        sourceName: 'debrify_link',
        bytes: Uint8List.fromList(bytes),
        origin: DebrifyTvChannelImportOrigin.url,
      );
    } catch (error) {
      showSnack(
        'Import failed: ${formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
          _owners.session.status = '';
        });
        closeProgressDialog();
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
            final app = AppThemeScope.of(context);
            return DebrifyTvSpotlightDialog(
              eyebrow: 'Import · from a link',
              title: 'Paste a channel link',
              subtitle:
                  'Use a debrify:// share link or an http(s) URL to a supported channel file.',
              icon: Icons.link_rounded,
              maxWidth: 650,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TvTextField(
                    controller: controller,
                    accent: app.settings.accent,
                    keyboardGround: app.youtube.keyboardPanel,
                    keyboardInk: app.core.tx,
                    keyboardInkOnAccent: app.inkOn(app.settings.accent),
                    decoration: InputDecoration(
                      labelText: 'Debrify link or file URL',
                      hintText: 'debrify://channel?... or https://...',
                      errorText: errorText,
                    ),
                    autofocus: true,
                    focusNode: urlFocusNode,
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Supported: .zip · .yaml · .txt · .debrify',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      color: app.debrifyTv.textFaint,
                    ),
                  ),
                ],
              ),
              actions: [
                DebrifyTvDialogButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                DebrifyTvDialogButton(
                  label: 'Import',
                  icon: Icons.download_rounded,
                  tone: DebrifyTvDialogButtonTone.primary,
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

  Future<ZipImportPersistenceResult> persistImportedZipChannels(
    List<DebrifyTvZipImportedChannel> channels,
  ) async {
    if (channels.isEmpty) {
      return const ZipImportPersistenceResult(successes: [], failures: []);
    }

    final successes = <ZipImportSuccess>[];
    final failures = <ZipImportSaveFailure>[];

    final List<DebrifyTvChannel> appendedChannels = [];
    final Map<String, DebrifyTvChannelCacheEntry> appendedCache = {};

    final Set<String> usedNames = _owners.library.channels
        .map((channel) => channel.name.toLowerCase())
        .toSet();

    for (final channel in channels) {
      if (channel.normalizedKeywords.length >
          DebrifyTvConstants.maxChannelKeywords) {
        failures.add(
          ZipImportSaveFailure(
            sourceName: channel.sourceName,
            channelName: channel.channelName,
            reason:
                'Channel has ${channel.normalizedKeywords.length} keywords; maximum supported is ${DebrifyTvConstants.maxChannelKeywords}.',
          ),
        );
        continue;
      }

      final uniqueName = resolveUniqueChannelName(
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
          DebrifyTvChannel(
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
          ZipImportSuccess(
            sourceName: channel.sourceName,
            channelName: uniqueName,
            keywordCount: channel.normalizedKeywords.length,
            torrentCount: channel.torrentCount,
          ),
        );

        usedNames.add(uniqueName.toLowerCase());
      } catch (error) {
        failures.add(
          ZipImportSaveFailure(
            sourceName: channel.sourceName,
            channelName: uniqueName,
            reason: formatImportError(error),
          ),
        );
      }
    }

    if (appendedChannels.isNotEmpty && mounted) {
      setState(() {
        _owners.library.channels = [
          ..._owners.library.channels,
          ...appendedChannels,
        ];
        _owners.library.channelCache.addAll(appendedCache);
      });
      await loadChannels();
    }

    return ZipImportPersistenceResult(successes: successes, failures: failures);
  }

  Future<void> showZipImportSummary(
    DebrifyTvZipImportResult parsed,
    ZipImportPersistenceResult persisted,
  ) async {
    if (!mounted) {
      return;
    }

    final bool hasSuccess = persisted.successes.isNotEmpty;
    final List<ZipImportFailureDisplay> failureRows = [
      ...parsed.failures.map(
        (failure) => ZipImportFailureDisplay(
          sourceName: failure.entryName,
          reason: failure.reason,
        ),
      ),
      ...persisted.failures.map(
        (failure) => ZipImportFailureDisplay(
          sourceName: failure.sourceName.isEmpty
              ? failure.channelName
              : failure.sourceName,
          reason: failure.reason,
        ),
      ),
    ];

    if (!hasSuccess && failureRows.isEmpty) {
      showSnack('No channels found in the selected zip.', color: Colors.orange);
      return;
    }

    final String dialogTitle = hasSuccess
        ? 'Zip import complete'
        : 'Zip import failed';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tv = AppThemeScope.of(dialogContext).debrifyTv;
        return DebrifyTvSpotlightDialog(
          eyebrow: 'Import · summary',
          title: dialogTitle,
          subtitle: hasSuccess
              ? 'Your imported channels are ready to tune.'
              : 'Nothing was changed. Review the issues below and try again.',
          icon: hasSuccess
              ? Icons.check_circle_outline_rounded
              : Icons.error_outline_rounded,
          maxWidth: 680,
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
                    leading: const Icon(Icons.check_circle, size: 20),
                    title: Text(success.channelName),
                    subtitle: Text(
                      '${success.keywordCount} keyword${success.keywordCount == 1 ? '' : 's'} • ${success.torrentCount} torrent${success.torrentCount == 1 ? '' : 's'}',
                      style: TextStyle(color: tv.textDim),
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
          actions: [
            DebrifyTvDialogButton(
              autofocus: true,
              label: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );

    if (hasSuccess) {
      final String names = persisted.successes
          .map((success) => '"${success.channelName}"')
          .join(', ');
      showSnack(
        'Imported ${persisted.successes.length} channel${persisted.successes.length == 1 ? '' : 's'}: $names',
        color: Colors.green,
      );
    } else if (failureRows.isNotEmpty) {
      showSnack(
        'Zip import failed: ${failureRows.first.reason}',
        color: Colors.red,
      );
    }
  }

  String resolveUniqueChannelName(
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

  Future<void> handleEditChannel(DebrifyTvChannel channel) async {
    await syncProviderAvailability();

    // Store current channel's NSFW setting before dialog
    final nsfwBeforeEdit = channel.avoidNsfw;

    final keywords = await getChannelKeywords(channel.id);
    final hydrated = channel.copyWith(keywords: keywords);
    final updated = await openChannelDialog(existing: hydrated);
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
        _owners.library.channelCache.remove(updated.id);

        // Rebuild cache with new NSFW filter setting (isEdit: false forces full rebuild)
        await createOrUpdateChannel(updated, isEdit: false);

        showSnack(
          'Channel cache rebuilt with updated NSFW filter.',
          color: Colors.green,
        );
      } else {
        // No NSFW change, just normal update
        await createOrUpdateChannel(updated, isEdit: true);
      }
    }
  }

  Future<bool> _showDebrifyTvConfirmation({
    required String eyebrow,
    required String title,
    required String message,
    required String confirmLabel,
    IconData icon = Icons.warning_amber_rounded,
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .72),
      builder: (dialogContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) Navigator.of(dialogContext).pop(false);
        },
        child: DebrifyTvSpotlightDialog(
          eyebrow: eyebrow,
          title: title,
          subtitle: message,
          icon: icon,
          maxWidth: 580,
          child: const SizedBox.shrink(),
          actions: [
            DebrifyTvDialogButton(
              autofocus: true,
              label: 'Cancel',
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            DebrifyTvDialogButton(
              label: confirmLabel,
              icon: danger ? Icons.delete_outline_rounded : Icons.check_rounded,
              tone: danger
                  ? DebrifyTvDialogButtonTone.danger
                  : DebrifyTvDialogButtonTone.primary,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> handleDeleteChannel(DebrifyTvChannel channel) async {
    // Set busy immediately to block any other interactions
    setState(() {
      _owners.session.isBusy = true;
    });

    final confirmed = await _showDebrifyTvConfirmation(
      eyebrow: 'Channel library · destructive action',
      title: 'Delete ${channel.name}?',
      message:
          'This removes the channel, its saved keywords, and its cached title pool. This cannot be undone.',
      confirmLabel: 'Delete channel',
      icon: Icons.delete_outline_rounded,
      danger: true,
    );

    // Wait for TWO frames to ensure UI has fully updated and touch events are processed
    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    if (confirmed == true && mounted) {
      await deleteChannel(channel.id);
      showSnack('Channel deleted', color: Colors.orange);
    }

    // Release busy state
    if (mounted) {
      setState(() {
        _owners.session.isBusy = false;
      });
    }
  }

  Future<void> handleShareChannelAsMagnet(DebrifyTvChannel channel) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Generating channel link…';
    });

    try {
      // Generate YAML for sharing (with cached torrents from DB)
      final yamlContent = await _generateChannelYaml(channel);

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
          final app = AppThemeScope.of(dialogContext);
          final tv = app.debrifyTv;
          return DebrifyTvSpotlightDialog(
            eyebrow:
                'Share channel · ${channel.channelNumber.toString().padLeft(2, '0')}',
            title: channel.name,
            subtitle:
                'Anyone on Debrify can paste this link to import the channel and its saved pool.',
            icon: Icons.share_rounded,
            maxWidth: 720,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: tv.dialogDeep.withValues(alpha: .72),
                    borderRadius: app.shape.br(16),
                    border: Border.all(color: tv.hairline),
                  ),
                  child: SelectableText(
                    magnetLink,
                    style: TextStyle(
                      color: tv.textDim,
                      fontSize: 10,
                      height: 1.5,
                      fontFamily: 'JetBrainsMono',
                    ),
                    maxLines: 6,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SpotlightMetaPill(
                      label: 'Link size',
                      value: formatDebrifyTvBytes(estimatedSize),
                    ),
                    _SpotlightMetaPill(
                      label: 'Compression',
                      value: '${compressionRatio.toStringAsFixed(1)}×',
                    ),
                    _SpotlightMetaPill(
                      label: 'Keywords',
                      value: '${channel.keywords.length}',
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              DebrifyTvDialogButton(
                label: 'Close',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              DebrifyTvDialogButton(
                autofocus: true,
                label: 'Copy link',
                icon: Icons.copy_rounded,
                tone: DebrifyTvDialogButtonTone.primary,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: magnetLink));
                  showSnack('Channel link copied!', color: Colors.green);
                  Navigator.of(dialogContext).pop();
                },
              ),
            ],
          );
        },
      );
    } catch (error) {
      showSnack(
        'Failed to generate channel link: ${formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
          _owners.session.status = '';
        });
      }
    }
  }

  Future<String> _generateChannelYaml(DebrifyTvChannel channel) async {
    // Generate YAML with channel config and torrent data from cache
    final buffer = StringBuffer();
    buffer.writeln('channel_name: "${channel.name}"');
    buffer.writeln('avoid_nsfw: ${channel.avoidNsfw}');
    buffer.writeln('');
    buffer.writeln('keywords:');

    // Get cached torrents from database (not in-memory cache)
    final cacheEntry = await DebrifyTvCacheService.getEntry(channel.id);
    final cachedTorrents = cacheEntry?.torrents ?? <CachedTorrent>[];
    for (final keyword in channel.keywords) {
      buffer.writeln('  $keyword:');

      // Find all torrents that match this keyword (case-insensitive)
      final keywordLower = keyword.toLowerCase();
      final matchingTorrents = cachedTorrents
          .where((t) => t.keywords.contains(keywordLower))
          .toList();

      // Dedupe by infohash
      final seen = <String>{};
      final uniqueTorrents = matchingTorrents.where((t) {
        if (seen.contains(t.infohash)) return false;
        seen.add(t.infohash);
        return true;
      }).toList();

      if (uniqueTorrents.isEmpty) {
        buffer.writeln('    torrents: []');
      } else {
        buffer.writeln('    torrents:');
        for (final torrent in uniqueTorrents) {
          // Output full torrent object for proper import
          buffer.writeln('      - infohash: ${torrent.infohash}');
          buffer.writeln('        name: "${_escapeYamlString(torrent.name)}"');
          buffer.writeln('        size_bytes: ${torrent.sizeBytes}');
          buffer.writeln('        created_unix: ${torrent.createdUnix}');
          buffer.writeln('        seeders: ${torrent.seeders}');
          buffer.writeln('        leechers: ${torrent.leechers}');
          buffer.writeln('        completed: ${torrent.completed}');
          buffer.writeln('        scraped_date: ${torrent.scrapedDate}');
          if (torrent.sources.isNotEmpty) {
            buffer.writeln(
              '        sources: [${torrent.sources.map((s) => '"$s"').join(', ')}]',
            );
          }
        }
      }
    }

    return buffer.toString();
  }

  String _escapeYamlString(String value) {
    // Escape special characters for YAML string
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }

  Future<void> handleDeleteAllChannels() async {
    if (_owners.library.channels.isEmpty) {
      showSnack('No channels to delete.', color: Colors.orange);
      return;
    }

    if (!mounted) {
      return;
    }

    // Set busy immediately to block any other interactions
    setState(() {
      _owners.session.isBusy = true;
    });

    final confirmed = await _showDebrifyTvConfirmation(
      eyebrow: 'Channel library · ${_owners.library.channels.length} channels',
      title: 'Delete every channel?',
      message:
          'This removes all ${_owners.library.channels.length} channels and every cached title pool. This cannot be undone.',
      confirmLabel: 'Delete all',
      icon: Icons.delete_sweep_outlined,
      danger: true,
    );

    // Wait for TWO frames to ensure UI has fully updated and touch events are processed
    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
    }

    if (confirmed != true || !mounted) {
      // Release busy state if cancelled
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
        });
      }
      return;
    }

    setState(() {
      _owners.session.isBusy = true;
    });

    try {
      await DebrifyTvRepository.instance.clearAll();
      await DebrifyTvCacheService.clearAll(
        origin: WebDavSyncMutationOrigin.maintenance,
      );
      setState(() {
        _owners.library.channels = const <DebrifyTvChannel>[];
        _owners.library.channelCache.clear();
      });
      showSnack('All channels deleted.', color: Colors.orange);
    } catch (error) {
      showSnack(
        'Failed to delete channels: ${formatImportError(error)}',
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
        });
      }
    }
  }

  Future<void> createOrUpdateChannel(
    DebrifyTvChannel channel, {
    required bool isEdit,
  }) async {
    final normalizedKeywords = this.normalizedKeywords(channel.keywords);
    if (normalizedKeywords.isEmpty) {
      showSnack(
        'Add at least one keyword before saving.',
        color: Colors.orange,
      );
      return;
    }

    debugPrint(
      'DebrifyTV: ${isEdit ? 'Updating' : 'Creating'} channel "${channel.name}" with ${normalizedKeywords.length} keyword(s): ${normalizedKeywords.join(', ')}',
    );

    final int estimatedSeconds = estimatedWarmDurationSeconds(
      normalizedKeywords.length,
      totalKeywordUniverse: normalizedKeywords.length,
    );
    bool progressShown = false;
    void ensureProgressDialog({int? countdownSeconds}) {
      if (!progressShown) {
        showChannelCreationDialog(
          channel.name,
          countdownSeconds: countdownSeconds ?? estimatedSeconds,
        );
        progressShown = true;
      }
    }

    try {
      final baseline = isEdit ? await ensureCacheEntry(channel.id) : null;
      if (normalizedKeywords.length > DebrifyTvConstants.maxChannelKeywords) {
        showSnack(
          'Channels support up to ${DebrifyTvConstants.maxChannelKeywords} keywords. Remove some and try again.',
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
            countdownSeconds: estimatedWarmDurationSeconds(
              addedKeywords.length,
              totalKeywordUniverse: normalizedKeywords.length,
            ),
          );
          debugPrint(
            'DebrifyTV: Warming new keywords for "${channel.name}": ${addedKeywords.join(', ')}',
          );
          workingEntry = await computeChannelCacheEntry(
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
        workingEntry = await computeChannelCacheEntry(
          channel,
          normalizedKeywords,
        );
        debugPrint(
          'DebrifyTV: Initial warm-up complete for "${channel.name}" with ${workingEntry.torrents.length} torrent(s).',
        );
      }

      final entry = workingEntry;
      if (entry == null) {
        showSnack(
          'Failed to build channel cache. Please try again.',
          color: Colors.red,
        );
        return;
      }

      if (!mounted) {
        return;
      }

      if (!entry.isReady ||
          entry.torrents.length <
              DebrifyTvConstants.minimumTorrentsForChannel) {
        final message = entry.isReady
            ? 'Need at least ${DebrifyTvConstants.minimumTorrentsForChannel} torrents to save this channel. Try different keywords.'
            : (entry.errorMessage ??
                  'Unable to find torrents for these keywords. Try again later.');

        debugPrint(
          'DebrifyTV: Cache validation failed for "${channel.name}" – ready=${entry.isReady}, torrents=${entry.torrents.length}.',
        );

        if (isEdit && baseline != null) {
          setState(() {
            _owners.library.channelCache[channel.id] = baseline;
            _owners.stage.spotlightStats.remove(channel.id);
          });
          refreshSpotlightStatsIfFocused(channel.id);
          await DebrifyTvCacheService.saveEntry(
            baseline,
            origin: WebDavSyncMutationOrigin.rollback,
          );
        } else {
          setState(() {
            _owners.library.channelCache.remove(channel.id);
            _owners.stage.spotlightStats.remove(channel.id);
          });
          await DebrifyTvCacheService.removeEntry(
            channel.id,
            origin: WebDavSyncMutationOrigin.rollback,
          );
        }

        showSnack(message, color: Colors.orange);
        return;
      }

      final updatedChannel = channel.copyWith(updatedAt: DateTime.now());

      final displayChannel = updatedChannel.copyWith(
        keywords: const <String>[],
      );

      setState(() {
        final index = _owners.library.channels.indexWhere(
          (c) => c.id == displayChannel.id,
        );
        if (index == -1) {
          _owners.library.channels = <DebrifyTvChannel>[
            ..._owners.library.channels,
            displayChannel,
          ];
        } else {
          final next = List<DebrifyTvChannel>.from(_owners.library.channels);
          next[index] = displayChannel;
          _owners.library.channels = next;
        }
        _owners.library.channelCache[displayChannel.id] = entry;
        _owners.stage.spotlightStats.remove(displayChannel.id);
      });

      await DebrifyTvRepository.instance.upsertChannel(
        updatedChannel.toRecord(),
      );
      await DebrifyTvCacheService.saveEntry(entry);
      await loadChannels();
      // Memo removal alone would leave the stage on its placeholder: only a
      // focus MOVE computes, and editing from the stage doesn't move focus.
      refreshSpotlightStatsIfFocused(displayChannel.id);

      final successMsg = isEdit
          ? 'Channel "${updatedChannel.name}" updated'
          : 'Channel "${updatedChannel.name}" saved';
      showSnack(successMsg, color: Colors.green);
      debugPrint(
        'DebrifyTV: $successMsg (torrents cached: ${entry.torrents.length})',
      );
    } catch (e) {
      debugPrint('DebrifyTV: Channel creation failed for ${channel.name}: $e');
      showSnack(
        'Failed to build channel cache. Please try again.',
        color: Colors.red,
      );
    } finally {
      if (progressShown) {
        closeProgressDialog();
      }
    }
  }

  /// [leadWith] (the Spotlight stage's play-one-title): that torrent plays
  /// FIRST, with the rest of the shuffled selection behind it. NEVER a
  /// single-element queue — the pick may not be cached at the provider, and
  /// a one-item queue has nothing to fall back to, which would make a
  /// deliberate choice fail exactly where Tune in would have succeeded.
  Future<void> watchChannel(
    DebrifyTvChannel channel, {
    CachedTorrent? leadWith,
  }) async {
    debugPrint('🎬 [WATCH] Starting for channel: ${channel.name}');
    _owners.session.qualityFallbackNotified = false;
    _owners.session.rdSizeRejections = 0;
    _owners.session.sizeFilterRelaxed = false;

    final keywords = await getChannelKeywords(channel.id);
    if (keywords.isEmpty) {
      debugPrint('❌ [WATCH] No keywords');
      MainPageBridge.notifyAutoLaunchFailed('Channel has no keywords');
      showSnack('Channel has no keywords yet', color: Colors.orange);
      return;
    }
    debugPrint('✅ [WATCH] Keywords: ${keywords.length}');

    await syncProviderAvailability();
    final bool providerReady = switch (_owners.settings.provider) {
      DebrifyTvConstants.providerTorbox => _owners.settings.torboxAvailable,
      DebrifyTvConstants.providerPikPak => _owners.settings.pikpakAvailable,
      DebrifyTvConstants.providerPremiumize =>
        _owners.settings.premiumizeAvailable,
      DebrifyTvConstants.providerAllDebrid =>
        _owners.settings.allDebridAvailable,
      _ => _owners.settings.rdAvailable,
    };
    if (!providerReady) {
      debugPrint('❌ [WATCH] Provider not ready: ${_owners.settings.provider}');
      MainPageBridge.notifyAutoLaunchFailed('Provider not configured');
      final providerName = providerDisplay(_owners.settings.provider);
      showSnack(
        'Enable $providerName in Settings to watch this channel',
        color: Colors.orange,
      );
      return;
    }
    debugPrint('✅ [WATCH] Provider ready: ${_owners.settings.provider}');

    final cacheEntry = await ensureCacheEntry(channel.id);
    if (cacheEntry == null) {
      debugPrint('❌ [WATCH] Cache entry is null');
      MainPageBridge.notifyAutoLaunchFailed('Cache entry not found');
      showSnack(
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
      showSnack(message, color: Colors.orange);
      return;
    }

    if (cacheEntry.torrents.isEmpty) {
      debugPrint('❌ [WATCH] Cache has no torrents');
      MainPageBridge.notifyAutoLaunchFailed('Cache has no torrents');
      showSnack(
        'No torrents cached yet. Try editing the channel keywords.',
        color: Colors.orange,
      );
      return;
    }
    debugPrint('✅ [WATCH] Cache has ${cacheEntry.torrents.length} torrents');

    final previousKeywords = _owners.library.keywordsController.text;

    final int resolvedChannelNumber = resolveChannelNumber(channel);

    setState(() {
      _owners.library.currentWatchingChannelId =
          channel.id; // Track for channel switching
    });
    _owners.library.keywordsController.text = keywords.join(', ');

    final normalizedKeywords = this.normalizedKeywords(keywords);
    final playbackSelection = selectTorrentsForPlayback(
      cacheEntry,
      normalizedKeywords,
    );
    if (leadWith != null) {
      // The chosen title to the front; behaviour after it ends is unchanged.
      playbackSelection.removeWhere((t) => t.infohash == leadWith.infohash);
      playbackSelection.insert(0, leadWith);
      if (playbackSelection.length == 1 && cacheEntry.torrents.length > 1) {
        // The filter narrowed the selection to the pick alone while the pool
        // holds more: refill behind it from the wider pool (same cap the
        // selector uses), or an uncached pick would have nothing to fall
        // through to — the single-element queue the plan forbids.
        final rest =
            cacheEntry.torrents
                .where((t) => t.infohash != leadWith.infohash)
                .toList()
              ..shuffle(Random());
        playbackSelection.addAll(
          rest.take(DebrifyTvConstants.playbackTorrentThreshold),
        );
      }
    }
    final cachedTorrents = playbackSelection
        .map((cached) => cached.toTorrent())
        .toList();
    debugPrint(
      '✅ [WATCH] Selected ${cachedTorrents.length} torrents for playback',
    );

    if (_owners.settings.provider == DebrifyTvConstants.providerTorbox) {
      debugPrint('🎬 [WATCH] Launching Torbox flow...');
      await watchTorboxWithCachedTorrents(
        cachedTorrents,
        channelName: channel.name,
        channelId: channel.id,
        channelNumber: resolvedChannelNumber,
      );
    } else if (_owners.settings.provider == DebrifyTvConstants.providerPikPak) {
      debugPrint('🎬 [WATCH] Launching PikPak flow...');
      await watchPikPakWithCachedTorrents(
        cachedTorrents,
        channelName: channel.name,
        channelId: channel.id,
        channelNumber: resolvedChannelNumber,
      );
    } else if (_owners.settings.provider ==
        DebrifyTvConstants.providerPremiumize) {
      debugPrint('🎬 [WATCH] Launching Premiumize flow...');
      await watchPremiumizeWithCachedTorrents(
        cachedTorrents,
        channelName: channel.name,
        channelId: channel.id,
        channelNumber: resolvedChannelNumber,
      );
    } else if (_owners.settings.provider ==
        DebrifyTvConstants.providerAllDebrid) {
      debugPrint('🎬 [WATCH] Launching AllDebrid flow...');
      await watchAllDebridWithCachedTorrents(
        cachedTorrents,
        applyNsfwFilter: channel.avoidNsfw || _owners.settings.viewerForcesNsfw,
        channelName: channel.name,
        channelId: channel.id,
        channelNumber: resolvedChannelNumber,
      );
    } else {
      debugPrint('🎬 [WATCH] Launching RealDebrid flow...');
      await watchWithCachedTorrents(
        cachedTorrents,
        applyNsfwFilter: channel.avoidNsfw || _owners.settings.viewerForcesNsfw,
        channelName: channel.name,
        channelId: channel.id,
        channelNumber: resolvedChannelNumber,
      );
    }

    if (!mounted) {
      return;
    }

    _owners.library.keywordsController.text = previousKeywords;
  }

  Future<void> watch() async {
    _owners.session.launchedPlayer = false;
    await stopPrefetch();
    _owners.prefetch.prefetchStopRequested = false;
    _owners.session.watchCancelled = false;
    _owners.session.qualityFallbackNotified = false;
    _owners.session.rdSizeRejections = 0;
    _owners.session.sizeFilterRelaxed = false;
    _owners.session.originalMaxCap = null;
    void _log(String m) {
      final copy = List<String>.from(_owners.progress.progress.value)..add(m);
      _owners.progress.progress.value = copy;
      debugPrint('DebrifyTV: ' + m);
    }

    await syncProviderAvailability();
    if (!_owners.settings.rdAvailable &&
        !_owners.settings.torboxAvailable &&
        !_owners.settings.pikpakAvailable &&
        !_owners.settings.premiumizeAvailable &&
        !_owners.settings.allDebridAvailable) {
      if (mounted) {
        setState(() {
          _owners.session.status =
              'Connect Real Debrid, Torbox, Premiumize, AllDebrid, or PikPak in Settings to use Debrify TV.';
        });
      }
      showSnack(
        'Connect Real Debrid, Torbox, Premiumize, AllDebrid, or PikPak in Settings to use Debrify TV.',
        color: Colors.orange,
      );
      return;
    }
    final text = _owners.library.keywordsController.text.trim();
    debugPrint('DebrifyTV: Watch started. Raw input="$text"');
    if (text.isEmpty) {
      setState(() {
        _owners.session.status =
            'Enter one or more keywords, separated by commas';
      });
      debugPrint('DebrifyTV: Aborting. No keywords provided.');
      return;
    }

    final keywords = parseKeywords(text);
    debugPrint(
      'DebrifyTV: Parsed ${keywords.length} keyword(s): ${keywords.join(' | ')}',
    );
    if (keywords.isEmpty) {
      setState(() {
        _owners.session.status = 'Enter valid keywords';
      });
      debugPrint(
        'DebrifyTV: Aborting. Parsed keywords became empty after trimming.',
      );
      return;
    }
    if (keywords.length > _owners.settings.quickPlayMaxKeywords) {
      setState(() {
        _owners.session.status =
            'Quick Play supports up to ${_owners.settings.quickPlayMaxKeywords} keywords. Create a channel for larger sets.';
      });
      showSnack(
        'Quick Play supports up to ${_owners.settings.quickPlayMaxKeywords} keywords. Create a channel for bigger combos.',
        color: Colors.orange,
      );
      debugPrint(
        'DebrifyTV: Aborting. Too many keywords for Quick Play (${keywords.length}).',
      );
      return;
    }

    setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Searching...';
      _owners.session.queue.clear();
    });

    // show non-dismissible loading modal
    _owners.progress.progress.value = [];
    _owners.progress.progressOpen = true;
    final providerLabel =
        _owners.settings.quickProvider == DebrifyTvConstants.providerTorbox
        ? 'Torbox'
        : _owners.settings.quickProvider == DebrifyTvConstants.providerPikPak
        ? 'PikPak'
        : _owners.settings.quickProvider ==
              DebrifyTvConstants.providerPremiumize
        ? 'Premiumize'
        : _owners.settings.quickProvider == DebrifyTvConstants.providerAllDebrid
        ? 'AllDebrid'
        : 'Real Debrid';
    // ignore: unawaited_futures
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (ctx) {
        _owners.progress.progressSheetContext = ctx;
        return CachedLoadingDialog(
          eyebrow: 'Quick play · $providerLabel',
          title: 'Searching for something to play',
          subtitle:
              'Debrify is searching your keywords, applying filters, and checking $providerLabel.',
          onCancel: () => cancelActiveWatch(dialogContext: ctx),
        );
      },
    ).whenComplete(() {
      _owners.progress.progressOpen = false;
      _owners.progress.progressSheetContext = null;
    });

    if (_owners.settings.quickProvider == DebrifyTvConstants.providerTorbox) {
      await watchWithTorbox(keywords, _log);
      return;
    }

    if (_owners.settings.quickProvider == DebrifyTvConstants.providerPikPak) {
      await watchWithPikPak(keywords, _log);
      return;
    }

    if (_owners.settings.quickProvider ==
        DebrifyTvConstants.providerPremiumize) {
      await watchWithPremiumize(keywords, _log);
      return;
    }

    if (_owners.settings.quickProvider ==
        DebrifyTvConstants.providerAllDebrid) {
      await watchWithAllDebrid(keywords, _log);
      return;
    }

    // Silent approach - no progress logging needed

    try {
      // Require RD API key early so we can prefetch as soon as results arrive
      final String? apiKeyEarlyRaw = await RealDebridStorage.getApiKey();
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
        if (_owners.session.watchCancelled) {
          return null;
        }
        debugPrint(
          'DebrifyTV: requestMagicNext() called. queueSize=${_owners.session.queue.length}',
        );
        while (_owners.session.queue.isNotEmpty &&
            !_owners.session.watchCancelled) {
          final item = _owners.session.queue.removeAt(0);
          if (_owners.session.watchCancelled) {
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
              if (_owners.session.watchCancelled) {
                return null;
              }
              if (!rdLinkPassesSizeRules(unrestrict)) continue;
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
                if (_owners.session.watchCancelled) {
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
              if (_owners.session.watchCancelled) {
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
                  .where(
                    (link) =>
                        !_owners.session.seenRestrictedLinks.contains(link),
                  )
                  .toList();
              if (newLinks.isEmpty) {
                continue;
              }

              newLinks.shuffle(Random());
              // Walk THIS torrent's own links until one is playable, rather
              // than re-queuing the torrent after a single reject — that would
              // cost another add+info round trip per sibling file (see the
              // cached-channel flow for the same reasoning).
              while (newLinks.isNotEmpty && !_owners.session.watchCancelled) {
                final selectedLink = newLinks.removeAt(0);
                _owners.session.seenRestrictedLinks.add(selectedLink);
                _owners.session.seenLinkWithTorrentId.add(
                  '$torrentId|$selectedLink',
                );

                final unrestrict = await DebridService.unrestrictLink(
                  apiKeyEarly,
                  selectedLink,
                );
                if (_owners.session.watchCancelled) {
                  return null;
                }
                if (!rdLinkPassesSizeRules(unrestrict)) continue;
                final videoUrl = unrestrict['download'] as String?;
                if (videoUrl == null || videoUrl.isEmpty) continue;

                debugPrint(
                  'DebrifyTV: Success. Got unrestricted URL in ${elapsed}s',
                );
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final chosenTitle = inferred.isNotEmpty
                    ? inferred
                    : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
                firstTitle = chosenTitle;

                if (!_owners.session.watchCancelled && newLinks.isNotEmpty) {
                  _owners.session.queue.add(item);
                }

                if (_owners.session.watchCancelled) {
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
      final engineStates = await tvEngineSearchStates();
      final maxResultsOverrides = quickPlayMaxResultsOverrides();

      // Launch limited batches of per-keyword searches so we don't overwhelm
      List<String> pendingKeywords = List<String>.from(keywords);
      while (pendingKeywords.isNotEmpty && !_owners.session.watchCancelled) {
        final batch = pendingKeywords
            .take(_owners.settings.channelBatchSize)
            .toList();
        pendingKeywords = pendingKeywords.skip(batch.length).toList();

        final futures = batch.map((kw) {
          debugPrint('DebrifyTV: Searching engines for "$kw"...');
          return TorrentService.searchAllEngines(
            kw,
            engineStates: engineStates,
            maxResultsOverrides: maxResultsOverrides,
          );
        }).toList();

        await for (final result in Stream.fromFutures(futures)) {
          if (_owners.session.watchCancelled) {
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
          if (_owners.settings.quickAvoidNsfw ||
              _owners.settings.viewerForcesNsfw) {
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

          // Filter out RD-blocked torrents
          if (_owners.settings.rdSkipBlockedTorrents) {
            torrentsToProcess = torrentsToProcess
                .where((t) => !isRdBlockedTorrent(t.name))
                .toList();
          }

          int added = 0;
          for (final t in torrentsToProcess) {
            if (!dedupByInfohash.containsKey(t.infohash)) {
              dedupByInfohash[t.infohash] = t;
              added++;
            }
          }
          if (added > 0) {
            if (_owners.session.watchCancelled) {
              break;
            }
            final combined = applyQualityFilterToTorrents(
              dedupByInfohash.values.toList(),
            );
            combined.shuffle(Random());
            _owners.session.queue
              ..clear()
              ..addAll(combined);
            _owners.session.lastQueueSize = _owners.session.queue.length;
            _owners.session.lastSearchAt = DateTime.now();
            // Silent approach - no progress logging needed
            if (mounted && !_owners.session.watchCancelled) {
              setState(() {
                _owners.session.status = 'Preparing your content...';
              });
            }

            // Do not start prefetch until player launches

            // Try to launch player as soon as a playable stream is available
            if (!_owners.session.launchedPlayer &&
                !_owners.session.watchCancelled) {
              final first = await requestMagicNext();
              if (_owners.session.watchCancelled) {
                break;
              }
              if (first != null &&
                  mounted &&
                  !_owners.session.launchedPlayer &&
                  !_owners.session.watchCancelled) {
                _owners.session.launchedPlayer = true;
                final firstUrl = first['url'] ?? '';
                final firstTitleResolved =
                    (first['title'] ?? firstTitle).trim().isNotEmpty
                    ? (first['title'] ?? firstTitle)
                    : firstTitle;
                if (!_owners.session.watchCancelled &&
                    _owners.progress.progressOpen &&
                    _owners.progress.progressSheetContext != null) {
                  Navigator.of(_owners.progress.progressSheetContext!).pop();
                }
                debugPrint(
                  'DebrifyTV: Launching player early. Remaining queue=${_owners.session.queue.length}',
                );

                // Start background prefetch only while player is active
                if (!_owners.session.watchCancelled) {
                  _owners.prefetch.activeApiKey = apiKeyEarly;
                  _owners.prefetch.activeProvider =
                      DebrifyTvConstants.providerRealDebrid;
                  unawaited(startPrefetch());

                  final String? activeChannelId =
                      _owners.library.currentWatchingChannelId;
                  final int? activeChannelNumber;
                  if (activeChannelId != null) {
                    final int idx = _owners.library.channels.indexWhere(
                      (c) => c.id == activeChannelId,
                    );
                    if (idx >= 0) {
                      final int resolvedNumber = resolveChannelNumber(
                        _owners.library.channels[idx],
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
                      _owners.library.channels.isNotEmpty
                      ? androidTvChannelMetadata(
                          activeChannelId: activeChannelId,
                        )
                      : null;

                  // External player set as the default: hand this one title
                  // over and stop the search — nothing rotates past it.
                  if (await handOffToExternalPlayer(
                    firstUrl,
                    firstTitleResolved,
                  )) {
                    break; // Exit the search loop
                  }

                  // Try to launch on Android TV first (early launch path)
                  final launchedOnTv = await launchRealDebridOnAndroidTv(
                    firstStream: first,
                    requestNext: requestMagicNext,
                    showChannelNameOverride:
                        _owners.settings.quickShowChannelName,
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
                    videoPlayerRoute(
                      builder: (_) => VideoPlayerScreen(
                        videoUrl: firstUrl,
                        title: firstTitleResolved,
                        startFromRandom: _owners.settings.quickStartRandom,
                        randomStartMaxPercent:
                            _owners.settings.quickRandomStartPercent,
                        hideSeekbar: _owners.settings.quickHideSeekbar,
                        showChannelName: _owners.settings.quickShowChannelName,
                        channelName: null,
                        channelNumber: null,
                        showVideoTitle: _owners.settings.quickShowVideoTitle,
                        hideOptions: _owners.settings.quickHideOptions,
                        requestMagicNext: requestMagicNext,
                        requestNextChannel:
                            _owners.library.channels.length > 1 &&
                                (_owners.settings.quickProvider ==
                                        DebrifyTvConstants.providerRealDebrid ||
                                    _owners.settings.quickProvider ==
                                        DebrifyTvConstants.providerTorbox ||
                                    _owners.settings.quickProvider ==
                                        DebrifyTvConstants.providerPikPak ||
                                    _owners.settings.quickProvider ==
                                        DebrifyTvConstants.providerPremiumize)
                            ? requestNextChannel
                            : null,
                        channelDirectory: activeChannelDirectory,
                        requestChannelById: _owners.library.channels.length > 1
                            ? requestChannelById
                            : null,
                      ),
                    ),
                  );

                  // Stop prefetch when player exits
                  await stopPrefetch();
                }
              }
            }
          }
        }
        if (_owners.session.watchCancelled) {
          break;
        }
      }
      // Final queue snapshot (if we didn't launch early)
      if (!_owners.session.launchedPlayer) {
        // The per-batch rebuilds above filter strictly, so an empty queue here
        // means nothing in the whole search matched the quality filter. This
        // is the point where that's genuinely known — degrade to unfiltered
        // rather than reporting "no results" for a search that found plenty.
        if (_owners.session.queue.isEmpty &&
            _owners.settings.tvFilters.hasQuality &&
            dedupByInfohash.isNotEmpty &&
            !_owners.session.watchCancelled) {
          notifyQualityFallback();
          final fallback = dedupByInfohash.values.toList()..shuffle(Random());
          _owners.session.queue
            ..clear()
            ..addAll(fallback);
        }
        debugPrint(
          'DebrifyTV: Queue prepared. size=${_owners.session.queue.length}',
        );
        _owners.session.lastQueueSize = _owners.session.queue.length;
        _owners.session.lastSearchAt = DateTime.now();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _owners.session.status = 'Search failed: $e';
      });
      debugPrint('DebrifyTV: Search failed: $e');
      if (e is NativePlayerSettingsUnavailable) {
        showNativeSettingsFailure(e);
        return;
      }
    } finally {
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
        });
      }
    }

    if (_owners.session.watchCancelled) {
      debugPrint('DebrifyTV: Watch was cancelled before completion.');
      return;
    }

    if (!mounted) return;
    if (_owners.session.queue.isEmpty) {
      if (!mounted) return;
      setState(() {
        _owners.session.status = 'No results found';
      });
      debugPrint('DebrifyTV: No results found after combining.');
      _log('❌ No results found - trying different search strategies');

      // Close popup and show user-friendly message
      if (_owners.progress.progressOpen &&
          _owners.progress.progressSheetContext != null) {
        Navigator.of(_owners.progress.progressSheetContext!).pop();
        _owners.progress.progressOpen = false;
        _owners.progress.progressSheetContext = null;
      }

      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
          _owners.session.status = 'No results found. Try different keywords.';
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
    if (_owners.session.launchedPlayer) {
      if (!mounted) return;
      setState(() {
        _owners.session.status = '';
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
    final apiKey = await RealDebridStorage.getApiKey();
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
        'MagicTV: requestMagicNext() called. queueSize=${_owners.session.queue.length}',
      );
      while (_owners.session.queue.isNotEmpty) {
        final item = _owners.session.queue.removeAt(0);
        // Case 1: RD-restricted entry (append-only items)
        if (item is Map && item['type'] == 'rd_restricted') {
          final String link = item['restrictedLink'] as String? ?? '';
          final String rdTid = item['torrentId'] as String? ?? '';
          debugPrint('MagicTV: Trying RD link from queue: torrentId=$rdTid');
          if (link.isEmpty) continue;
          try {
            final started = DateTime.now();
            final unrestrict = await DebridService.unrestrictLink(apiKey, link);
            if (!rdLinkPassesSizeRules(unrestrict)) continue;
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
                if (_owners.session.seenRestrictedLinks.contains(link) ||
                    _owners.session.seenLinkWithTorrentId.contains(combined)) {
                  continue;
                }
                _owners.session.seenRestrictedLinks.add(link);
                _owners.session.seenLinkWithTorrentId.add(combined);
                _owners.session.queue.add({
                  'type': 'rd_restricted',
                  'restrictedLink': link,
                  'torrentId': torrentId,
                  'displayName': item.name,
                });
              }
              if (rdLinks.length > 1) {
                debugPrint(
                  'MagicTV: Enqueued ${rdLinks.length - 1} additional RD links to tail. New queueSize=${_owners.session.queue.length}',
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
      _owners.session.status = 'Finding a playable stream...';
      _owners.session.isBusy = true;
    });
    _log('🎬 Selecting the best quality stream for you');

    try {
      final first = await requestMagicNext();
      if (first == null) {
        // Close popup and show user-friendly message
        if (_owners.progress.progressOpen &&
            _owners.progress.progressSheetContext != null) {
          Navigator.of(_owners.progress.progressSheetContext!).pop();
          _owners.progress.progressOpen = false;
          _owners.progress.progressSheetContext = null;
        }

        if (mounted) {
          setState(() {
            _owners.session.isBusy = false;
            _owners.session.status =
                'No playable torrents found. Try different keywords.';
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
      debugPrint(
        'MagicTV: Launching player. Remaining queue=${_owners.session.queue.length}',
      );

      // Start background prefetch while player is active
      _owners.prefetch.activeApiKey = apiKey;
      _owners.prefetch.activeProvider = DebrifyTvConstants.providerRealDebrid;
      unawaited(startPrefetch());

      if (_owners.progress.progressOpen &&
          _owners.progress.progressSheetContext != null) {
        Navigator.of(_owners.progress.progressSheetContext!).pop();
      }

      final String? activeChannelId = _owners.library.currentWatchingChannelId;
      final int? activeChannelNumber;
      if (activeChannelId != null) {
        final int idx = _owners.library.channels.indexWhere(
          (c) => c.id == activeChannelId,
        );
        if (idx >= 0) {
          final int resolvedNumber = resolveChannelNumber(
            _owners.library.channels[idx],
          );
          activeChannelNumber = resolvedNumber > 0 ? resolvedNumber : null;
        } else {
          activeChannelNumber = null;
        }
      } else {
        activeChannelNumber = null;
      }
      final List<Map<String, dynamic>>? quickChannelDirectory =
          _owners.library.channels.isNotEmpty
          ? androidTvChannelMetadata(activeChannelId: activeChannelId)
          : null;

      if (await handOffToExternalPlayer(firstUrl, firstTitle)) {
        return;
      }

      // Try to launch on Android TV first
      final launchedOnTv = await launchRealDebridOnAndroidTv(
        firstStream: first,
        requestNext: requestMagicNext,
        showChannelNameOverride: _owners.settings.quickShowChannelName,
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
        videoPlayerRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: firstUrl,
            title: firstTitle,
            startFromRandom: _owners.settings.quickStartRandom,
            randomStartMaxPercent: _owners.settings.quickRandomStartPercent,
            hideSeekbar: _owners.settings.quickHideSeekbar,
            showChannelName: _owners.settings.quickShowChannelName,
            channelName: null,
            channelNumber: null,
            showVideoTitle: _owners.settings.quickShowVideoTitle,
            hideOptions: _owners.settings.quickHideOptions,
            requestMagicNext: requestMagicNext,
            requestNextChannel:
                _owners.library.channels.length > 1 &&
                    (_owners.settings.quickProvider ==
                            DebrifyTvConstants.providerRealDebrid ||
                        _owners.settings.quickProvider ==
                            DebrifyTvConstants.providerTorbox ||
                        _owners.settings.quickProvider ==
                            DebrifyTvConstants.providerPikPak)
                ? requestNextChannel
                : null,
            channelDirectory: quickChannelDirectory,
            requestChannelById: _owners.library.channels.length > 1
                ? requestChannelById
                : null,
          ),
        ),
      );
      // Stop prefetch when player exits
      await stopPrefetch();
    } on NativePlayerSettingsUnavailable catch (error) {
      showNativeSettingsFailure(error);
    } finally {
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
          _owners.session.status = '';
        });
        debugPrint('MagicTV: Watch flow finished.');
      }
    }
  }

  Future<void> watchWithTorbox(
    List<String> keywords,
    void Function(String message) log,
  ) async {
    final integrationEnabled =
        await TorboxStorage.getTorboxIntegrationEnabled();
    if (!integrationEnabled) {
      closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _owners.session.status =
            'Enable Torbox in Settings to use this provider.';
        _owners.session.isBusy = false;
      });
      showSnack(
        'Enable Torbox in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await TorboxStorage.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _owners.session.status =
            'Add your Torbox API key in Settings to use this provider.';
        _owners.session.isBusy = false;
      });
      showSnack(
        'Please add your Torbox API key in Settings first!',
        color: Colors.red,
      );
      return;
    }

    log('🌐 Torbox: searching for cached torrents...');
    final Map<String, Torrent> dedup = <String, Torrent>{};
    final engineStates = await tvEngineSearchStates();
    final maxResultsOverrides = quickPlayMaxResultsOverrides();

    try {
      final futures = keywords
          .map(
            (kw) => TorrentService.searchAllEngines(
              kw,
              engineStates: engineStates,
              maxResultsOverrides: maxResultsOverrides,
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
        if (_owners.settings.quickAvoidNsfw ||
            _owners.settings.viewerForcesNsfw) {
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
          final normalizedHash = normalizeInfohash(torrent.infohash);
          if (normalizedHash.isEmpty) continue;
          if (!dedup.containsKey(normalizedHash)) {
            dedup[normalizedHash] = torrent;
            added++;
          }
        }
        if (added > 0) {
          final combined = applyQualityFilterToTorrents(dedup.values.toList());
          combined.shuffle(Random());
          _owners.session.queue
            ..clear()
            ..addAll(combined);
          _owners.session.lastQueueSize = _owners.session.queue.length;
          _owners.session.lastSearchAt = DateTime.now();
          if (mounted) {
            setState(() {
              _owners.session.status = 'Checking Torbox cache...';
            });
          }
        }
      }

      final combinedList = applyQualityFilterToTorrents(
        dedup.values.toList(),
        // Search is complete here — an empty match means this search really
        // has nothing at the requested quality, so degrade rather than fail.
        allowFallback: true,
      );
      if (combinedList.isEmpty) {
        closeProgressDialog();
        if (mounted) {
          setState(() {
            _owners.session.status =
                'No results found. Try different keywords.';
          });
          showSnack(
            'No results found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      combinedList.shuffle(Random());
      if (mounted) {
        setState(() {
          _owners.session.status = 'Checking Torbox cache...';
        });
      }

      int candidateCursor = 0;

      Future<bool> populateQueue() async {
        while (true) {
          if (candidateCursor >= combinedList.length) {
            return false;
          }
          final TorboxCacheWindowResult window = await fetchTorboxCacheWindow(
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
          _owners.session.queue
            ..clear()
            ..addAll(window.cachedTorrents);
          _owners.session.lastQueueSize = _owners.session.queue.length;
          _owners.session.lastSearchAt = DateTime.now();
          if (mounted) {
            setState(() {
              _owners.session.status = _owners.session.queue.isEmpty
                  ? ''
                  : 'Queue has ${_owners.session.queue.length} remaining';
            });
          }
          log(
            '✅ Found ${_owners.session.queue.length} cached Torbox torrent(s)',
          );
          return true;
        }
      }

      bool seeded;
      try {
        seeded = await populateQueue();
      } catch (e) {
        log('❌ Torbox cache check failed: $e');
        closeProgressDialog();
        if (mounted) {
          setState(() {
            _owners.session.status = 'Torbox cache check failed. Try again.';
          });
          showSnack(
            'Torbox cache check failed: ${formatTorboxError(e)}',
            color: Colors.red,
          );
        }
        return;
      }

      if (!seeded) {
        closeProgressDialog();
        if (mounted) {
          setState(() {
            _owners.session.status =
                'Torbox has no cached results for these keywords.';
          });
          showSnack(
            'Torbox has no cached results for these keywords.',
            color: Colors.orange,
          );
        }
        return;
      }

      Future<Map<String, String>?> requestTorboxNext() async {
        if (_owners.session.watchCancelled) {
          return null;
        }
        while (!_owners.session.watchCancelled) {
          if (_owners.session.queue.isEmpty) {
            bool replenished;
            try {
              replenished = await populateQueue();
            } catch (e) {
              log('❌ Torbox cache check failed: $e');
              closeProgressDialog();
              if (mounted && !_owners.session.watchCancelled) {
                setState(() {
                  _owners.session.status =
                      'Torbox cache check failed. Try again.';
                });
                showSnack(
                  'Torbox cache check failed: ${formatTorboxError(e)}',
                  color: Colors.red,
                );
              }
              return null;
            }
            if (!replenished) {
              break;
            }
          }
          if (_owners.session.queue.isEmpty) {
            break;
          }
          final item = _owners.session.queue.removeAt(0);
          if (_owners.session.watchCancelled) {
            break;
          }
          if (item is Map &&
              item['type'] == DebrifyTvConstants.torboxFileEntryType) {
            final resolved = await resolveTorboxQueuedFile(
              entry: item as Map<String, dynamic>,
              apiKey: apiKey,
              log: log,
            );
            if (_owners.session.watchCancelled) {
              return null;
            }
            if (resolved != null) {
              if (mounted && !_owners.session.watchCancelled) {
                setState(() {
                  _owners.session.status = _owners.session.queue.isEmpty
                      ? ''
                      : 'Queue has ${_owners.session.queue.length} remaining';
                });
              }
              if (_owners.session.watchCancelled) {
                return null;
              }
              return resolved;
            }
            continue;
          }

          if (item is Torrent) {
            final result = await prepareTorboxTorrent(
              candidate: item,
              apiKey: apiKey,
              log: log,
            );
            if (_owners.session.watchCancelled) {
              return null;
            }
            if (result != null) {
              if (result.hasMore && !_owners.session.watchCancelled) {
                combinedList.add(item);
              }
              if (mounted && !_owners.session.watchCancelled) {
                setState(() {
                  _owners.session.status = _owners.session.queue.isEmpty
                      ? ''
                      : 'Queue has ${_owners.session.queue.length} remaining';
                });
              }
              if (_owners.session.watchCancelled) {
                return null;
              }
              return {'url': result.streamUrl, 'title': result.title};
            }
          }
        }
        if (mounted && !_owners.session.watchCancelled) {
          setState(() {
            _owners.session.status = 'No more cached Torbox streams available.';
          });
        }
        return null;
      }

      final first = await requestTorboxNext();
      if (_owners.session.watchCancelled) {
        return;
      }
      if (first == null) {
        closeProgressDialog();
        if (mounted && !_owners.session.watchCancelled) {
          setState(() {
            _owners.session.status =
                'No playable Torbox streams found. Try different keywords.';
          });
          showSnack(
            'No playable Torbox streams found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      closeProgressDialog();
      if (!mounted) return;

      if (await handOffToExternalPlayer(
        first['url'] ?? '',
        first['title'] ?? 'Debrify TV',
      )) {
        return;
      }

      final launchedOnTv = await launchTorboxOnAndroidTv(
        firstStream: first,
        requestNext: requestTorboxNext,
        showChannelNameOverride: _owners.settings.quickShowChannelName,
        channelName: null,
        channelId: null,
        channelNumber: null,
        channelDirectory: null,
      );
      if (_owners.session.watchCancelled) {
        return;
      }
      if (launchedOnTv) {
        return;
      }

      if (!_owners.session.watchCancelled) {
        // Hide auto-launch overlay before launching player
        MainPageBridge.notifyPlayerLaunching();

        await Navigator.of(context).push(
          videoPlayerRoute(
            builder: (_) => VideoPlayerScreen(
              videoUrl: first['url'] ?? '',
              title: first['title'] ?? 'Debrify TV',
              startFromRandom: _owners.settings.startRandom,
              randomStartMaxPercent: _owners.settings.randomStartPercent,
              hideSeekbar: _owners.settings.hideSeekbar,
              showChannelName: _owners.settings.showChannelName,
              channelName: null,
              channelNumber: null,
              showVideoTitle: _owners.settings.showVideoTitle,
              hideOptions: _owners.settings.hideOptions,
              requestMagicNext: requestTorboxNext,
              requestNextChannel:
                  _owners.library.channels.length > 1 &&
                      (_owners.settings.quickProvider ==
                              DebrifyTvConstants.providerRealDebrid ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerTorbox ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerPikPak)
                  ? requestNextChannel
                  : null,
            ),
          ),
        );
      }

      if (mounted && !_owners.session.watchCancelled) {
        setState(() {
          _owners.session.status = _owners.session.queue.isEmpty
              ? ''
              : 'Queue has ${_owners.session.queue.length} remaining';
        });
      }
    } on NativePlayerSettingsUnavailable catch (error) {
      showNativeSettingsFailure(error);
    } finally {
      closeProgressDialog();
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
        });
      }
    }
  }

  Future<void> watchWithPikPak(
    List<String> keywords,
    void Function(String message) log,
  ) async {
    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    if (!pikpakAvailable) {
      closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _owners.session.status = 'Please login to PikPak in Settings first!';
        _owners.session.isBusy = false;
      });
      showSnack(
        'Please login to PikPak in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    log('🌐 PikPak: searching for torrents...');
    final Map<String, Torrent> dedup = <String, Torrent>{};
    final engineStates = await tvEngineSearchStates();
    final maxResultsOverrides = quickPlayMaxResultsOverrides();

    try {
      final futures = keywords
          .map(
            (kw) => TorrentService.searchAllEngines(
              kw,
              engineStates: engineStates,
              maxResultsOverrides: maxResultsOverrides,
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
        if (_owners.settings.quickAvoidNsfw ||
            _owners.settings.viewerForcesNsfw) {
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
          final normalizedHash = normalizeInfohash(torrent.infohash);
          if (normalizedHash.isEmpty) continue;
          if (!dedup.containsKey(normalizedHash)) {
            dedup[normalizedHash] = torrent;
            added++;
          }
        }
        if (added > 0) {
          final combined = applyQualityFilterToTorrents(dedup.values.toList());
          combined.shuffle(Random());
          _owners.session.queue
            ..clear()
            ..addAll(combined);
          _owners.session.lastQueueSize = _owners.session.queue.length;
          _owners.session.lastSearchAt = DateTime.now();
          if (mounted) {
            setState(() {
              _owners.session.status = 'Preparing PikPak stream...';
            });
          }
        }
      }

      final combinedList = applyQualityFilterToTorrents(
        dedup.values.toList(),
        // Search is complete here — an empty match means this search really
        // has nothing at the requested quality, so degrade rather than fail.
        allowFallback: true,
      );
      if (combinedList.isEmpty) {
        closeProgressDialog();
        if (mounted) {
          setState(() {
            _owners.session.status =
                'No results found. Try different keywords.';
          });
          showSnack(
            'No results found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      combinedList.shuffle(Random());
      _owners.session.queue
        ..clear()
        ..addAll(combinedList);
      _owners.session.lastQueueSize = _owners.session.queue.length;
      _owners.session.lastSearchAt = DateTime.now();

      if (mounted) {
        setState(() {
          _owners.session.status = 'Preparing PikPak stream...';
        });
      }

      Future<Map<String, String>?> requestPikPakNext() async {
        if (_owners.session.watchCancelled) {
          return null;
        }
        while (_owners.session.queue.isNotEmpty &&
            !_owners.session.watchCancelled) {
          final item = _owners.session.queue.removeAt(0);
          if (_owners.session.watchCancelled) {
            break;
          }
          if (item is! Torrent) {
            continue;
          }

          log('Trying torrent: ${item.name}');
          final prepared = await preparePikPakTorrent(
            candidate: item,
            log: (msg) => debugPrint('DebrifyTV/PikPak: $msg'),
          );

          if (_owners.session.watchCancelled) {
            return null;
          }

          if (prepared == null) {
            log('Torrent not ready, trying next...');
            continue;
          }

          // Add back to queue if there are more files in this torrent
          if (prepared.hasMore) {
            _owners.session.queue.add(item);
            log(
              'Multi-file torrent: added back to queue (${_owners.session.queue.length} remaining)',
            );
          }

          if (mounted && !_owners.session.watchCancelled) {
            setState(() {
              _owners.session.status = _owners.session.queue.isEmpty
                  ? ''
                  : 'Queue has ${_owners.session.queue.length} remaining';
            });
          }

          return {
            'url': prepared.streamUrl,
            'title': prepared.title,
            'provider': 'pikpak',
            'pikpakFileId': '',
          };
        }
        if (mounted && !_owners.session.watchCancelled) {
          setState(() {
            _owners.session.status = 'No more PikPak streams available.';
          });
        }
        return null;
      }

      final first = await requestPikPakNext();
      if (_owners.session.watchCancelled) {
        return;
      }
      if (first == null) {
        closeProgressDialog();
        if (mounted && !_owners.session.watchCancelled) {
          setState(() {
            _owners.session.status =
                'No playable PikPak streams found. Try different keywords.';
          });
          MainPageBridge.notifyAutoLaunchFailed('No PikPak streams available');
          showSnack(
            'No playable PikPak streams found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      closeProgressDialog();
      if (!mounted) return;

      if (await handOffToExternalPlayer(
        first['url'] ?? '',
        first['title'] ?? 'Debrify TV',
      )) {
        return;
      }

      // Try Android TV native player first
      final launchedOnTv = await launchPikPakOnAndroidTv(
        firstStream: first,
        requestNext: requestPikPakNext,
        showChannelNameOverride: _owners.settings.quickShowChannelName,
        channelName: null,
        channelId: null,
        channelNumber: null,
        channelDirectory: null,
      );
      if (_owners.session.watchCancelled) {
        return;
      }
      if (launchedOnTv) {
        return;
      }

      if (!_owners.session.watchCancelled) {
        // Hide auto-launch overlay before launching player
        MainPageBridge.notifyPlayerLaunching();

        await Navigator.of(context).push(
          videoPlayerRoute(
            builder: (_) => VideoPlayerScreen(
              videoUrl: first['url'] ?? '',
              title: first['title'] ?? 'Debrify TV',
              startFromRandom: _owners.settings.quickStartRandom,
              randomStartMaxPercent: _owners.settings.quickRandomStartPercent,
              hideSeekbar: _owners.settings.quickHideSeekbar,
              showChannelName: _owners.settings.quickShowChannelName,
              channelName: null,
              channelNumber: null,
              showVideoTitle: _owners.settings.quickShowVideoTitle,
              hideOptions: _owners.settings.quickHideOptions,
              requestMagicNext: requestPikPakNext,
              requestNextChannel:
                  _owners.library.channels.length > 1 &&
                      (_owners.settings.quickProvider ==
                              DebrifyTvConstants.providerRealDebrid ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerTorbox ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerPikPak)
                  ? requestNextChannel
                  : null,
            ),
          ),
        );
      }

      if (mounted && !_owners.session.watchCancelled) {
        setState(() {
          _owners.session.status = _owners.session.queue.isEmpty
              ? ''
              : 'Queue has ${_owners.session.queue.length} remaining';
        });
      }
    } on NativePlayerSettingsUnavailable catch (error) {
      showNativeSettingsFailure(error);
    } finally {
      closeProgressDialog();
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
        });
      }
    }
  }

  Future<void> watchWithCachedTorrents(
    List<Torrent> cachedTorrents, {
    required bool applyNsfwFilter,
    String? channelName,
    String? channelId,
    int? channelNumber,
  }) async {
    if (cachedTorrents.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No cached torrents');
      showSnack(
        'Cached channel has no torrents yet. Please wait a moment.',
        color: Colors.orange,
      );
      return;
    }

    final List<Map<String, dynamic>>? channelDirectory =
        _owners.library.channels.isNotEmpty
        ? androidTvChannelMetadata(
            activeChannelId:
                channelId ?? _owners.library.currentWatchingChannelId,
          )
        : null;

    _owners.session.launchedPlayer = false;
    await stopPrefetch();
    _owners.prefetch.prefetchStopRequested = false;
    _owners.session.originalMaxCap = null;
    _owners.session.seenRestrictedLinks.clear();
    _owners.session.seenLinkWithTorrentId.clear();

    final apiKey = await RealDebridStorage.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      MainPageBridge.notifyAutoLaunchFailed('No Real Debrid API key');
      showSnack(
        'Please add your Real Debrid API key in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    showCachedPlaybackDialog();

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

    // Filter out RD-blocked torrents
    if (_owners.settings.rdSkipBlockedTorrents) {
      final beforeCount = torrentsToUse.length;
      torrentsToUse = torrentsToUse
          .where((t) => !isRdBlockedTorrent(t.name))
          .toList();
      if (beforeCount != torrentsToUse.length) {
        debugPrint(
          'DebrifyTV: RD-blocked filter on cached: $beforeCount → ${torrentsToUse.length} torrents',
        );
      }
    }

    _owners.session.queue
      ..clear()
      ..addAll(List<Torrent>.from(torrentsToUse)..shuffle(Random()));
    _owners.session.lastQueueSize = _owners.session.queue.length;
    _owners.session.lastSearchAt = DateTime.now();

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
        'DebrifyTV: Cached requestMagicNext() queueSize=${_owners.session.queue.length}',
      );
      while (_owners.session.queue.isNotEmpty) {
        final item = _owners.session.queue.removeAt(0);
        if (item is Map && item['type'] == 'rd_restricted') {
          final String link = item['restrictedLink'] as String? ?? '';
          final String rdTid = item['torrentId'] as String? ?? '';
          debugPrint('DebrifyTV: Cached path trying RD link: torrentId=$rdTid');
          if (link.isEmpty) continue;
          try {
            final started = DateTime.now();
            final unrestrict = await DebridService.unrestrictLink(apiKey, link);
            if (!rdLinkPassesSizeRules(unrestrict)) continue;
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
                .where(
                  (link) => !_owners.session.seenRestrictedLinks.contains(link),
                )
                .toList();
            if (newLinks.isEmpty) {
              continue;
            }

            newLinks.shuffle(Random());
            // Walk THIS torrent's own links until one is playable. Bailing
            // after a single reject and re-queuing the torrent would pay
            // another add+info round trip just to reach a sibling file, so a
            // pack full of samples could burn one RD add per sample and play
            // nothing. Unrestrict calls are the cheap half — spend those.
            while (newLinks.isNotEmpty) {
              final selectedLink = newLinks.removeAt(0);
              _owners.session.seenRestrictedLinks.add(selectedLink);
              _owners.session.seenLinkWithTorrentId.add(
                '$torrentId|$selectedLink',
              );

              final unrestrict = await DebridService.unrestrictLink(
                apiKey,
                selectedLink,
              );
              if (!rdLinkPassesSizeRules(unrestrict)) continue;
              final videoUrl = unrestrict['download'] as String?;
              if (videoUrl == null || videoUrl.isEmpty) continue;

              debugPrint(
                'DebrifyTV: Cached success: unrestricted in ${elapsed}s',
              );
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
              firstTitle = chosenTitle;

              if (newLinks.isNotEmpty) {
                _owners.session.queue.add(item);
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
      _owners.session.status = 'Finding a playable stream...';
      _owners.session.isBusy = true;
    });

    try {
      final first = await requestMagicNext();
      if (first == null) {
        closeProgressDialog();
        if (!mounted) return;
        setState(() {
          _owners.session.isBusy = false;
          _owners.session.status =
              'No cached torrents played successfully. Try refreshing the channel.';
        });
        MainPageBridge.notifyAutoLaunchFailed('No cached streams available');
        showSnack(
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
      _owners.prefetch.activeApiKey = apiKey;
      _owners.prefetch.activeProvider = DebrifyTvConstants.providerRealDebrid;
      unawaited(startPrefetch());
      closeProgressDialog();

      if (await handOffToExternalPlayer(firstUrl, firstTitle)) {
        return;
      }

      // Try to launch on Android TV first (for cached flow)
      final launchedOnTv = await launchRealDebridOnAndroidTv(
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
        videoPlayerRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: firstUrl,
            title: firstTitle,
            startFromRandom: _owners.settings.startRandom,
            randomStartMaxPercent: _owners.settings.randomStartPercent,
            hideSeekbar: _owners.settings.hideSeekbar,
            showChannelName: _owners.settings.showChannelName,
            channelName: channelName,
            channelNumber: channelNumber,
            showVideoTitle: _owners.settings.showVideoTitle,
            hideOptions: _owners.settings.hideOptions,
            requestMagicNext: requestMagicNext,
            requestNextChannel:
                _owners.library.channels.length > 1 &&
                    (_owners.settings.provider ==
                            DebrifyTvConstants.providerRealDebrid ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerTorbox ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerPikPak ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerPremiumize)
                ? requestNextChannel
                : null,
            channelDirectory: channelDirectory,
            requestChannelById: _owners.library.channels.length > 1
                ? requestChannelById
                : null,
          ),
        ),
      );
      await stopPrefetch();
    } on NativePlayerSettingsUnavailable catch (error) {
      showNativeSettingsFailure(error);
    } finally {
      closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _owners.session.isBusy = false;
        _owners.session.status = '';
      });
      debugPrint('DebrifyTV: Cached watch flow finished.');
    }
  }

  /// AllDebrid channel playback. Mirrors the Real-Debrid cached flow
  /// (sequential add-and-probe, no cache-check API) but resolves each candidate
  /// through AllDebrid's `ready`-flag add (no polling) and lazily unlocks links
  /// on demand. The background prefetcher keeps upcoming items prepared.
  Future<void> watchAllDebridWithCachedTorrents(
    List<Torrent> cachedTorrents, {
    required bool applyNsfwFilter,
    String? channelName,
    String? channelId,
    int? channelNumber,
  }) async {
    if (cachedTorrents.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No cached torrents');
      showSnack(
        'Cached channel has no torrents yet. Please wait a moment.',
        color: Colors.orange,
      );
      return;
    }

    final List<Map<String, dynamic>>? channelDirectory =
        _owners.library.channels.isNotEmpty
        ? androidTvChannelMetadata(
            activeChannelId:
                channelId ?? _owners.library.currentWatchingChannelId,
          )
        : null;

    _owners.session.launchedPlayer = false;
    await stopPrefetch();
    _owners.prefetch.prefetchStopRequested = false;
    _owners.session.originalMaxCap = null;
    _owners.session.seenRestrictedLinks.clear();
    _owners.session.seenLinkWithTorrentId.clear();

    final apiKey = await AllDebridStorage.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      MainPageBridge.notifyAutoLaunchFailed('No AllDebrid API key');
      showSnack(
        'Please add your AllDebrid API key in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    showCachedPlaybackDialog();

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

    _owners.session.queue
      ..clear()
      ..addAll(List<Torrent>.from(torrentsToUse)..shuffle(Random()));
    _owners.session.lastQueueSize = _owners.session.queue.length;
    _owners.session.lastSearchAt = DateTime.now();

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
        'DebrifyTV/AD: requestMagicNext() queueSize=${_owners.session.queue.length}',
      );
      while (_owners.session.queue.isNotEmpty) {
        final item = _owners.session.queue.removeAt(0);
        if (item is Map && item['type'] == 'ad_locked') {
          final String link = item['allDebridLink'] as String? ?? '';
          if (link.isEmpty) continue;
          try {
            final videoUrl = await AllDebridService.unlockLink(apiKey, link);
            if (videoUrl.isNotEmpty) {
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final display = (item['displayName'] as String?)?.trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (display ?? 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('DebrifyTV/AD: Cached unlock failed: $e');
            continue;
          }
        }

        if (item is Torrent) {
          debugPrint(
            'DebrifyTV/AD: Cached trying torrent name="${item.name}" hash=${item.infohash}',
          );
          final prepared = await resolveAllDebridLinks(item, apiKey);
          if (prepared == null || prepared.lockedLinks.isEmpty) {
            continue;
          }
          final links = List<String>.from(prepared.lockedLinks);
          final String headLink = links.removeAt(0);
          // AllDebrid returns every file at once: enqueue the remaining video
          // files (still locked) so siblings aren't lost if the head fails.
          for (final link in links) {
            _owners.session.queue.add({
              'type': 'ad_locked',
              'allDebridLink': link,
              'magnetId': prepared.magnetId,
              'displayName': item.name,
            });
          }
          try {
            final videoUrl = await AllDebridService.unlockLink(
              apiKey,
              headLink,
            );
            if (videoUrl.isNotEmpty) {
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('DebrifyTV/AD: Cached add/unlock failed: $e');
            continue;
          }
        }
      }
      debugPrint('DebrifyTV/AD: Cached queue exhausted.');
      return null;
    }

    setState(() {
      _owners.session.status = 'Finding a playable stream...';
      _owners.session.isBusy = true;
    });

    try {
      final first = await requestMagicNext();
      if (first == null) {
        closeProgressDialog();
        if (!mounted) return;
        setState(() {
          _owners.session.isBusy = false;
          _owners.session.status =
              'No cached torrents played successfully. Try refreshing the channel.';
        });
        MainPageBridge.notifyAutoLaunchFailed('No cached streams available');
        showSnack(
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
      _owners.prefetch.activeApiKey = apiKey;
      _owners.prefetch.activeProvider = DebrifyTvConstants.providerAllDebrid;
      unawaited(startPrefetch());
      closeProgressDialog();

      if (await handOffToExternalPlayer(firstUrl, firstTitle)) {
        return;
      }

      // Try to launch on Android TV first (reuses the generic direct-URL
      // launcher; AllDebrid streams are ready URLs just like Real-Debrid's).
      final launchedOnTv = await launchRealDebridOnAndroidTv(
        firstStream: first,
        requestNext: requestMagicNext,
        channelName: channelName,
        channelId: channelId,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
      );

      if (launchedOnTv) {
        debugPrint(
          'DebrifyTV: Cached flow - AllDebrid playback started on Android TV',
        );
        return;
      }

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      // Fall back to Flutter video player
      await Navigator.of(context).push(
        videoPlayerRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: firstUrl,
            title: firstTitle,
            startFromRandom: _owners.settings.startRandom,
            randomStartMaxPercent: _owners.settings.randomStartPercent,
            hideSeekbar: _owners.settings.hideSeekbar,
            showChannelName: _owners.settings.showChannelName,
            channelName: channelName,
            channelNumber: channelNumber,
            showVideoTitle: _owners.settings.showVideoTitle,
            hideOptions: _owners.settings.hideOptions,
            requestMagicNext: requestMagicNext,
            requestNextChannel:
                _owners.library.channels.length > 1 &&
                    (_owners.settings.provider ==
                            DebrifyTvConstants.providerRealDebrid ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerTorbox ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerPikPak ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerPremiumize ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerAllDebrid)
                ? requestNextChannel
                : null,
            channelDirectory: channelDirectory,
            requestChannelById: _owners.library.channels.length > 1
                ? requestChannelById
                : null,
          ),
        ),
      );
      await stopPrefetch();
    } on NativePlayerSettingsUnavailable catch (error) {
      showNativeSettingsFailure(error);
    } finally {
      closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _owners.session.isBusy = false;
        _owners.session.status = '';
      });
      debugPrint('DebrifyTV: AllDebrid cached watch flow finished.');
    }
  }

  void showNativeSettingsFailure(NativePlayerSettingsUnavailable error) {
    unawaited(stopPrefetch());
    MainPageBridge.notifyAutoLaunchFailed(error.message.toString());
    if (mounted) showSnack(error.message.toString(), color: Colors.orange);
  }

  Future<bool> launchTorboxOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) async {
    if (!_owners.settings.isAndroidTv) {
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
        requestChannelSwitch: _owners.library.channels.length > 1
            ? requestNextChannel
            : null,
        requestChannelById: _owners.library.channels.length > 1
            ? requestChannelById
            : null,
        onFinished: () async {
          AndroidTvPlayerBridge.clearTorboxProvider();
          if (!mounted) {
            return;
          }
          setState(() {
            _owners.session.status = _owners.session.queue.isEmpty
                ? ''
                : 'Queue has ${_owners.session.queue.length} remaining';
          });
        },
        startFromRandom: _owners.settings.startRandom,
        randomStartMaxPercent: _owners.settings.randomStartPercent,
        hideSeekbar: _owners.settings.hideSeekbar,
        hideOptions: _owners.settings.hideOptions,
        showVideoTitle: _owners.settings.showVideoTitle,
        showChannelName:
            showChannelNameOverride ?? _owners.settings.showChannelName,
        channelName: channelName,
        channels: channelDirectory,
        currentChannelId: channelId ?? _owners.library.currentWatchingChannelId,
        currentChannelNumber: channelNumber,
      );
      if (launched) {
        if (mounted) {
          setState(() {
            _owners.session.status = 'Playing via Android TV';
          });
        }
        return true;
      }
    } catch (e) {
      debugPrint('DebrifyTV: Android TV bridge failed: $e');
      if (e is NativePlayerSettingsUnavailable) rethrow;
    }

    AndroidTvPlayerBridge.clearTorboxProvider();
    return false;
  }

  /// Handle channel switching on Android TV - cycles to next channel with looping
  Future<Map<String, dynamic>?> requestNextChannel() async {
    debugPrint('DebrifyTV: _requestNextChannel() called');

    if (_owners.library.channels.isEmpty) {
      debugPrint('DebrifyTV: No channels available');
      return null;
    }

    int currentIndex = -1;
    if (_owners.library.currentWatchingChannelId != null) {
      currentIndex = _owners.library.channels.indexWhere(
        (c) => c.id == _owners.library.currentWatchingChannelId,
      );
    }

    final int nextIndex = (currentIndex + 1) % _owners.library.channels.length;
    final DebrifyTvChannel targetChannel = _owners.library.channels[nextIndex];

    debugPrint(
      'DebrifyTV: Switching from channel ${currentIndex + 1} to ${nextIndex + 1} (${targetChannel.name})',
    );

    return switchToChannel(
      targetChannel,
      fallbackIndex: nextIndex,
      reason: 'next',
    );
  }

  Future<Map<String, dynamic>?> requestChannelById(String channelId) async {
    debugPrint('DebrifyTV: _requestChannelById($channelId) called');

    if (_owners.library.channels.isEmpty) {
      debugPrint('DebrifyTV: No channels available for direct selection');
      return null;
    }

    DebrifyTvChannel? targetChannel;
    int discoveredIndex = -1;
    for (var i = 0; i < _owners.library.channels.length; i++) {
      final channel = _owners.library.channels[i];
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

    if (_owners.library.currentWatchingChannelId == targetChannel.id) {
      debugPrint(
        'DebrifyTV: Selected channel is already active; refreshing playback',
      );
    } else {
      debugPrint(
        'DebrifyTV: Switching directly to channel ${targetChannel.name}',
      );
    }

    return switchToChannel(
      targetChannel,
      fallbackIndex: discoveredIndex >= 0 ? discoveredIndex : null,
      reason: 'direct',
    );
  }

  Future<Map<String, dynamic>?> switchToChannel(
    DebrifyTvChannel targetChannel, {
    int? fallbackIndex,
    String reason = 'direct',
  }) async {
    debugPrint(
      'DebrifyTV: _switchToChannel(${targetChannel.name}) reason=$reason',
    );

    final int computedIndex =
        fallbackIndex ??
        _owners.library.channels.indexWhere(
          (channel) => channel.id == targetChannel.id,
        );
    final int targetChannelNumber = targetChannel.channelNumber > 0
        ? targetChannel.channelNumber
        : (computedIndex >= 0 ? computedIndex + 1 : 0);

    final cacheEntry = await ensureCacheEntry(targetChannel.id);
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
    await stopPrefetch();
    debugPrint('DebrifyTV: Prefetcher stopped. Waiting for RD cooldown...');
    await Future.delayed(const Duration(seconds: 5));
    debugPrint('DebrifyTV: Cooldown complete. Proceeding with channel switch.');

    final previousChannelId = _owners.library.currentWatchingChannelId;
    if (previousChannelId != null) {
      _owners.library.channelCache.remove(previousChannelId);
      debugPrint(
        'DebrifyTV: Evicted cache entry for previous channel $previousChannelId',
      );
    }

    _owners.session.seenRestrictedLinks.clear();
    _owners.session.seenLinkWithTorrentId.clear();
    // New channel, new filter verdict — let it warn again if this one has
    // nothing at the requested quality/size.
    _owners.session.qualityFallbackNotified = false;
    _owners.session.rdSizeRejections = 0;
    _owners.session.sizeFilterRelaxed = false;
    debugPrint('DebrifyTV: Cleared prefetch state');

    final keywords = await getChannelKeywords(targetChannel.id);
    if (keywords.isEmpty) {
      debugPrint('DebrifyTV: Channel "${targetChannel.name}" has no keywords');
      if (_owners.settings.provider == DebrifyTvConstants.providerRealDebrid ||
          _owners.settings.provider == DebrifyTvConstants.providerAllDebrid) {
        unawaited(startPrefetch());
      }
      return null;
    }

    final normalizedKeywords = this.normalizedKeywords(keywords);
    final playbackSelection = selectTorrentsForPlayback(
      cacheEntry,
      normalizedKeywords,
    );

    if (playbackSelection.isEmpty) {
      debugPrint('DebrifyTV: No torrents matched in selected channel');
      if (_owners.settings.provider == DebrifyTvConstants.providerRealDebrid ||
          _owners.settings.provider == DebrifyTvConstants.providerAllDebrid) {
        unawaited(startPrefetch());
      }
      return null;
    }

    final List<Torrent> allTorrents = playbackSelection
        .map((cached) => cached.toTorrent())
        .toList();
    if (allTorrents.isEmpty) {
      debugPrint('DebrifyTV: No playable torrents resolved for channel');
      if (_owners.settings.provider == DebrifyTvConstants.providerRealDebrid ||
          _owners.settings.provider == DebrifyTvConstants.providerAllDebrid) {
        unawaited(startPrefetch());
      }
      return null;
    }

    List<Torrent> filteredTorrents = allTorrents;
    if (_owners.settings.provider == DebrifyTvConstants.providerTorbox) {
      final apiKey = await TorboxStorage.getTorboxApiKey();
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
          final TorboxCacheWindowResult window = await fetchTorboxCacheWindow(
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
      if (_owners.settings.provider == DebrifyTvConstants.providerRealDebrid) {
        debugPrint('DebrifyTV: Selected channel uses Real-Debrid provider');
        final apiKey = await RealDebridStorage.getApiKey();
        if (apiKey == null || apiKey.isEmpty) {
          debugPrint('DebrifyTV: ❌ No Real-Debrid API key configured');
          return null;
        }

        if (_owners.settings.rdSkipBlockedTorrents) {
          filteredTorrents = filteredTorrents
              .where((t) => !isRdBlockedTorrent(t.name))
              .toList();
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
              .where(
                (link) => !_owners.session.seenRestrictedLinks.contains(link),
              )
              .toList();
          if (newLinks.isEmpty) {
            newLinks = List<String>.from(rdLinks);
          }
          newLinks.shuffle(Random());
          // Exhaust THIS candidate's links before moving on. Advancing to the
          // next candidate costs a whole add+info round trip, so a sample as
          // the first pick must not throw away a torrent that has a real
          // episode sitting right behind it.
          String? videoUrl;
          for (final selectedLink in newLinks) {
            _owners.session.seenRestrictedLinks.add(selectedLink);
            if (torrentId.isNotEmpty) {
              _owners.session.seenLinkWithTorrentId.add(
                '$torrentId|$selectedLink',
              );
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

            if (!rdLinkPassesSizeRules(unrestrict)) continue;

            final String? resolved = unrestrict['download'] as String?;
            if (resolved == null || resolved.isEmpty) {
              debugPrint(
                'DebrifyTV: Real-Debrid unrestrict returned empty URL for candidate ${candidate.infohash}',
              );
              continue;
            }
            videoUrl = resolved;
            break;
          }

          if (videoUrl == null) continue;

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
              _owners.library.currentWatchingChannelId = targetChannel.id;
              _owners.session.queue
                ..clear()
                ..addAll(remaining);
            });
            _owners.library.keywordsController.text = keywords.join(', ');
          }

          _owners.prefetch.activeApiKey = apiKey;
          _owners.prefetch.activeProvider =
              DebrifyTvConstants.providerRealDebrid;
          unawaited(startPrefetch());
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

      if (_owners.settings.provider == DebrifyTvConstants.providerAllDebrid) {
        debugPrint('DebrifyTV: Selected channel uses AllDebrid provider');
        final apiKey = await AllDebridStorage.getAllDebridApiKey();
        if (apiKey == null || apiKey.isEmpty) {
          debugPrint('DebrifyTV: ❌ No AllDebrid API key configured');
          return null;
        }

        for (var index = 0; index < filteredTorrents.length; index++) {
          final candidate = filteredTorrents[index];

          final prepared = await resolveAllDebridLinks(candidate, apiKey);
          if (prepared == null || prepared.lockedLinks.isEmpty) {
            // Not cached/ready or no usable video; try the next candidate.
            continue;
          }

          final links = List<String>.from(prepared.lockedLinks);
          final String headLink = links.removeAt(0);

          String videoUrl;
          try {
            videoUrl = await AllDebridService.unlockLink(apiKey, headLink);
          } catch (error) {
            debugPrint(
              'DebrifyTV: AllDebrid unlock failed for candidate ${candidate.infohash}: $error',
            );
            continue;
          }
          if (videoUrl.isEmpty) {
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
              _owners.library.currentWatchingChannelId = targetChannel.id;
              _owners.session.queue
                ..clear()
                // Remaining video files of this torrent first (already
                // resolved, still locked), then the other candidates.
                ..addAll(
                  links.map(
                    (link) => {
                      'type': 'ad_locked',
                      'allDebridLink': link,
                      'magnetId': prepared.magnetId,
                      'displayName': candidate.name,
                    },
                  ),
                )
                ..addAll(remaining);
            });
            _owners.library.keywordsController.text = keywords.join(', ');
          }

          _owners.prefetch.activeApiKey = apiKey;
          _owners.prefetch.activeProvider =
              DebrifyTvConstants.providerAllDebrid;
          unawaited(startPrefetch());
          debugPrint('DebrifyTV: Started AllDebrid prefetcher for new channel');
          debugPrint('DebrifyTV: Successfully got stream from channel: $title');

          return {
            'channelId': targetChannel.id,
            'channelName': targetChannel.name,
            'channelNumber': targetChannelNumber,
            'firstUrl': videoUrl,
            'firstTitle': title,
          };
        }

        debugPrint('DebrifyTV: All AllDebrid candidates failed for channel');
        return null;
      }

      if (_owners.settings.provider == DebrifyTvConstants.providerTorbox) {
        final apiKey = await TorboxStorage.getTorboxApiKey();
        if (apiKey == null || apiKey.isEmpty) {
          debugPrint('DebrifyTV: ❌ No Torbox API key configured');
          return null;
        }

        for (var index = 0; index < filteredTorrents.length; index++) {
          final candidate = filteredTorrents[index];

          final prepared = await prepareTorboxTorrent(
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
              _owners.library.currentWatchingChannelId = targetChannel.id;
              _owners.session.queue
                ..clear()
                ..addAll(remaining);
              if (prepared.hasMore) {
                _owners.session.queue.add(candidate);
              }
            });
            _owners.library.keywordsController.text = keywords.join(', ');
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

      if (_owners.settings.provider == DebrifyTvConstants.providerPikPak) {
        final pikpakAvailable = await PikPakTvService.instance.isAvailable();
        if (!pikpakAvailable) {
          debugPrint('DebrifyTV: PikPak not authenticated');
          return null;
        }

        for (var index = 0; index < filteredTorrents.length; index++) {
          final candidate = filteredTorrents[index];

          final prepared = await preparePikPakTorrent(
            candidate: candidate,
            log: (message) => debugPrint('DebrifyTV/PikPak: $message'),
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
              _owners.library.currentWatchingChannelId = targetChannel.id;
              _owners.session.queue
                ..clear()
                ..addAll(remaining);
              // Add back to queue if there are more files in this torrent
              if (prepared.hasMore) {
                _owners.session.queue.add(candidate);
              }
            });
            _owners.library.keywordsController.text = keywords.join(', ');
          }

          debugPrint(
            'DebrifyTV: PikPak channel switch ready with stream ${prepared.title}',
          );
          return {
            'channelId': targetChannel.id,
            'channelName': targetChannel.name,
            'channelNumber': targetChannelNumber,
            'firstUrl': prepared.streamUrl,
            'firstTitle': prepared.title,
          };
        }

        debugPrint('DebrifyTV: All PikPak candidates failed for channel');
        return null;
      }

      debugPrint(
        'DebrifyTV: Unsupported provider for channel switching: ${_owners.settings.provider}',
      );
      return null;
    } catch (e) {
      debugPrint('DebrifyTV: Error getting stream from channel: $e');
    }

    debugPrint('DebrifyTV: Channel switch failed');
    if (_owners.settings.provider == DebrifyTvConstants.providerRealDebrid ||
        _owners.settings.provider == DebrifyTvConstants.providerAllDebrid) {
      unawaited(startPrefetch());
      debugPrint('DebrifyTV: Restarted prefetcher for current channel');
    }
    return null;
  }

  int resolveChannelNumber(DebrifyTvChannel channel) {
    if (channel.channelNumber > 0) {
      return channel.channelNumber;
    }
    final int index = _owners.library.channels.indexWhere(
      (element) => element.id == channel.id,
    );
    if (index >= 0) {
      return index + 1;
    }
    final int fallback = _owners.library.channels.indexOf(channel);
    return fallback >= 0 ? fallback + 1 : 0;
  }

  List<Map<String, dynamic>> androidTvChannelMetadata({
    String? activeChannelId,
  }) {
    if (_owners.library.channels.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final String? highlightId =
        activeChannelId ?? _owners.library.currentWatchingChannelId;
    final List<Map<String, dynamic>> payload = <Map<String, dynamic>>[];
    for (var i = 0; i < _owners.library.channels.length; i++) {
      final channel = _owners.library.channels[i];
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

  Future<bool> launchRealDebridOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) async {
    debugPrint('DebrifyTV: _launchRealDebridOnAndroidTv() called');
    debugPrint('DebrifyTV: _isAndroidTv=${_owners.settings.isAndroidTv}');

    if (!_owners.settings.isAndroidTv) {
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
          _owners.library.currentWatchingChannelId != null &&
          _owners.library.channels.length > 1 &&
          (_owners.settings.provider == DebrifyTvConstants.providerRealDebrid ||
              _owners.settings.provider ==
                  DebrifyTvConstants.providerAllDebrid);

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      final launched = await AndroidTvPlayerBridge.launchRealDebridPlayback(
        initialUrl: initialUrl,
        title: title.isEmpty ? 'Debrify TV' : title,
        channelName: channelName,
        requestNext: requestNext,
        requestChannelSwitch: canSwitchChannels ? requestNextChannel : null,
        requestChannelById: canSwitchChannels ? requestChannelById : null,
        onFinished: () async {
          debugPrint('DebrifyTV: Android TV playback finished callback');

          // Stop prefetcher when exiting player
          await stopPrefetch();
          debugPrint('DebrifyTV: Stopped prefetcher on player exit');

          AndroidTvPlayerBridge.clearStreamProvider();
          _owners.library.currentWatchingChannelId =
              null; // Clear channel tracking
          if (!mounted) return;
          setState(() {
            _owners.session.status = _owners.session.queue.isEmpty
                ? ''
                : 'Queue has ${_owners.session.queue.length} remaining';
          });
        },
        startFromRandom: _owners.settings.startRandom,
        randomStartMaxPercent: _owners.settings.randomStartPercent,
        hideSeekbar: _owners.settings.hideSeekbar,
        hideOptions: _owners.settings.hideOptions,
        showVideoTitle: _owners.settings.showVideoTitle,
        showChannelName:
            showChannelNameOverride ?? _owners.settings.showChannelName,
        channels: channelDirectory,
        currentChannelId: channelId ?? _owners.library.currentWatchingChannelId,
        currentChannelNumber: channelNumber,
      );

      debugPrint(
        'DebrifyTV: AndroidTvPlayerBridge.launchRealDebridPlayback() returned: $launched',
      );

      if (launched) {
        if (mounted) {
          setState(() {
            _owners.session.status = 'Playing via Android TV';
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
      if (e is NativePlayerSettingsUnavailable) rethrow;
    }

    AndroidTvPlayerBridge.clearStreamProvider();
    debugPrint('DebrifyTV: Falling back to Flutter player');
    return false;
  }

  Future<void> watchTorboxWithCachedTorrents(
    List<Torrent> cachedTorrents, {
    String? channelName,
    String? channelId,
    int? channelNumber,
  }) async {
    if (cachedTorrents.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No cached torrents');
      showSnack(
        'Cached channel has no torrents yet. Please wait a moment.',
        color: Colors.orange,
      );
      return;
    }

    final List<Map<String, dynamic>>? channelDirectory =
        _owners.library.channels.isNotEmpty
        ? androidTvChannelMetadata(
            activeChannelId:
                channelId ?? _owners.library.currentWatchingChannelId,
          )
        : null;

    void log(String message) {
      debugPrint('DebrifyTV: $message');
    }

    final integrationEnabled =
        await TorboxStorage.getTorboxIntegrationEnabled();
    if (!integrationEnabled) {
      showSnack(
        'Enable Torbox in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await TorboxStorage.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No Torbox API key');
      showSnack(
        'Please add your Torbox API key in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    showCachedPlaybackDialog();

    final List<Torrent> candidatePool = List<Torrent>.from(cachedTorrents);
    candidatePool.shuffle(Random());

    if (mounted) {
      setState(() {
        _owners.session.status = 'Checking Torbox cache...';
        _owners.session.isBusy = true;
      });
    }

    int candidateCursor = 0;

    Future<bool> populateQueue() async {
      while (true) {
        if (candidateCursor >= candidatePool.length) {
          return false;
        }
        final TorboxCacheWindowResult window = await fetchTorboxCacheWindow(
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
        _owners.session.queue
          ..clear()
          ..addAll(window.cachedTorrents);
        _owners.session.lastQueueSize = _owners.session.queue.length;
        _owners.session.lastSearchAt = DateTime.now();
        if (mounted) {
          setState(() {
            _owners.session.status = _owners.session.queue.isEmpty
                ? ''
                : 'Queue has ${_owners.session.queue.length} remaining';
          });
        }
        log(
          '✅ Cached Torbox batch ready with ${_owners.session.queue.length} item(s)',
        );
        return true;
      }
    }

    bool seeded;
    try {
      seeded = await populateQueue();
    } catch (e) {
      closeProgressDialog();
      showSnack(
        'Torbox cache check failed: ${formatTorboxError(e)}',
        color: Colors.orange,
      );
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
        });
      }
      return;
    }

    if (!seeded) {
      closeProgressDialog();
      showSnack(
        'Cached torrents are no longer available on Torbox. Please refresh the channel.',
        color: Colors.orange,
      );
      if (mounted) {
        setState(() {
          _owners.session.isBusy = false;
        });
      }
      return;
    }

    Future<Map<String, String>?> requestTorboxNext() async {
      while (true) {
        if (_owners.session.queue.isEmpty) {
          bool replenished;
          try {
            replenished = await populateQueue();
          } catch (e) {
            closeProgressDialog();
            showSnack(
              'Torbox cache check failed: ${formatTorboxError(e)}',
              color: Colors.orange,
            );
            if (mounted) {
              setState(() {
                _owners.session.isBusy = false;
              });
            }
            return null;
          }
          if (!replenished) {
            break;
          }
        }
        if (_owners.session.queue.isEmpty) {
          break;
        }

        final next = _owners.session.queue.removeAt(0);
        if (next is Map &&
            next['type'] == DebrifyTvConstants.torboxFileEntryType) {
          final resolved = await resolveTorboxQueuedFile(
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

        final prepared = await prepareTorboxTorrent(
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
        closeProgressDialog();
        if (!mounted) return;
        setState(() {
          _owners.session.status =
              'No playable Torbox streams found. Try refreshing.';
          _owners.session.isBusy = false;
        });
        MainPageBridge.notifyAutoLaunchFailed(
          'No cached Torbox streams available',
        );
        showSnack(
          'No cached Torbox streams are playable. Try refreshing the channel.',
          color: Colors.orange,
        );
        return;
      }

      if (!mounted) return;
      closeProgressDialog();

      if (await handOffToExternalPlayer(
        first['url'] ?? '',
        first['title'] ?? 'Debrify TV',
      )) {
        return;
      }

      final launchedOnTv = await launchTorboxOnAndroidTv(
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
        videoPlayerRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: first['url'] ?? '',
            title: first['title'] ?? 'Debrify TV',
            startFromRandom: _owners.settings.startRandom,
            randomStartMaxPercent: _owners.settings.randomStartPercent,
            hideSeekbar: _owners.settings.hideSeekbar,
            showChannelName: _owners.settings.showChannelName,
            channelName: channelName,
            channelNumber: channelNumber,
            showVideoTitle: _owners.settings.showVideoTitle,
            hideOptions: _owners.settings.hideOptions,
            requestMagicNext: requestTorboxNext,
            requestNextChannel:
                _owners.library.channels.length > 1 &&
                    (_owners.settings.provider ==
                            DebrifyTvConstants.providerRealDebrid ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerTorbox ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerPikPak ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerPremiumize)
                ? requestNextChannel
                : null,
            channelDirectory: channelDirectory,
            requestChannelById: _owners.library.channels.length > 1
                ? requestChannelById
                : null,
          ),
        ),
      );
      if (mounted) {
        setState(() {
          _owners.session.status = _owners.session.queue.isEmpty
              ? ''
              : 'Queue has ${_owners.session.queue.length} remaining';
        });
      }
    } on NativePlayerSettingsUnavailable catch (error) {
      showNativeSettingsFailure(error);
    } finally {
      closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _owners.session.isBusy = false;
      });
    }
  }

  Future<void> watchPikPakWithCachedTorrents(
    List<Torrent> cachedTorrents, {
    String? channelName,
    String? channelId,
    int? channelNumber,
  }) async {
    if (cachedTorrents.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No cached torrents');
      showSnack(
        'Cached channel has no torrents yet. Please wait a moment.',
        color: Colors.orange,
      );
      return;
    }

    final List<Map<String, dynamic>>? channelDirectory =
        _owners.library.channels.isNotEmpty
        ? androidTvChannelMetadata(
            activeChannelId:
                channelId ?? _owners.library.currentWatchingChannelId,
          )
        : null;

    void log(String message) {
      debugPrint('DebrifyTV/PikPak: $message');
    }

    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    if (!pikpakAvailable) {
      showSnack(
        'Please login to PikPak in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    showCachedPlaybackDialog();

    _owners.session.pikpakCandidatePool = List<Torrent>.from(cachedTorrents);
    _owners.session.pikpakCandidatePool!.shuffle(Random());

    if (mounted) {
      setState(() {
        _owners.session.status = 'Preparing PikPak stream...';
        _owners.session.isBusy = true;
        _owners.session.queue
          ..clear()
          ..addAll(_owners.session.pikpakCandidatePool!);
      });
    }

    Future<Map<String, String>?> requestPikPakNext() async {
      if (_owners.session.watchCancelled) return null;

      while (_owners.session.queue.isNotEmpty &&
          !_owners.session.watchCancelled) {
        final next = _owners.session.queue.removeAt(0);
        if (_owners.session.watchCancelled) break;

        if (next is! Torrent) {
          continue;
        }

        final prepared = await preparePikPakTorrent(candidate: next, log: log);

        if (_owners.session.watchCancelled) return null;

        if (prepared == null) {
          continue;
        }

        if (prepared.hasMore) {
          _owners.session.queue.add(next);
        }

        return {
          'url': prepared.streamUrl,
          'title': prepared.title,
          'provider': 'pikpak',
        };
      }
      return null;
    }

    try {
      final first = await requestPikPakNext();
      if (first == null) {
        closeProgressDialog();
        if (!mounted) return;
        setState(() {
          _owners.session.status =
              'No playable PikPak streams found. Try refreshing.';
          _owners.session.isBusy = false;
        });
        MainPageBridge.notifyAutoLaunchFailed('No PikPak streams available');
        showSnack(
          'No PikPak streams are playable. Try refreshing the channel.',
          color: Colors.orange,
        );
        return;
      }

      if (!mounted) return;
      closeProgressDialog();

      if (await handOffToExternalPlayer(
        first['url'] ?? '',
        first['title'] ?? 'Debrify TV',
      )) {
        return;
      }

      // Try Android TV native player first
      final launchedOnTv = await launchPikPakOnAndroidTv(
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
        videoPlayerRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: first['url'] ?? '',
            title: first['title'] ?? 'Debrify TV',
            startFromRandom: _owners.settings.startRandom,
            randomStartMaxPercent: _owners.settings.randomStartPercent,
            hideSeekbar: _owners.settings.hideSeekbar,
            showChannelName: _owners.settings.showChannelName,
            channelName: channelName,
            channelNumber: channelNumber,
            showVideoTitle: _owners.settings.showVideoTitle,
            hideOptions: _owners.settings.hideOptions,
            requestMagicNext: requestPikPakNext,
            requestNextChannel:
                _owners.library.channels.length > 1 &&
                    (_owners.settings.provider ==
                            DebrifyTvConstants.providerRealDebrid ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerTorbox ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerPikPak ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerPremiumize)
                ? requestNextChannel
                : null,
            channelDirectory: channelDirectory,
            requestChannelById: _owners.library.channels.length > 1
                ? requestChannelById
                : null,
          ),
        ),
      );
      if (mounted) {
        setState(() {
          _owners.session.status = _owners.session.queue.isEmpty
              ? ''
              : 'Queue has ${_owners.session.queue.length} remaining';
        });
      }
    } on NativePlayerSettingsUnavailable catch (error) {
      showNativeSettingsFailure(error);
    } finally {
      closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _owners.session.isBusy = false;
      });
    }
  }

  Future<bool> launchPikPakOnAndroidTv({
    required Map<String, String> firstStream,
    required Future<Map<String, String>?> Function() requestNext,
    String? channelName,
    bool? showChannelNameOverride,
    String? channelId,
    int? channelNumber,
    List<Map<String, dynamic>>? channelDirectory,
  }) async {
    if (!_owners.settings.isAndroidTv) {
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
        requestChannelSwitch: _owners.library.channels.length > 1
            ? requestNextChannel
            : null,
        requestChannelById: _owners.library.channels.length > 1
            ? requestChannelById
            : null,
        onFinished: () async {
          AndroidTvPlayerBridge.clearTorboxProvider();
          if (!mounted) {
            return;
          }
          setState(() {
            _owners.session.status = _owners.session.queue.isEmpty
                ? ''
                : 'Queue has ${_owners.session.queue.length} remaining';
          });
        },
        startFromRandom: _owners.settings.startRandom,
        randomStartMaxPercent: _owners.settings.randomStartPercent,
        hideSeekbar: _owners.settings.hideSeekbar,
        hideOptions: _owners.settings.hideOptions,
        showVideoTitle: _owners.settings.showVideoTitle,
        showChannelName:
            showChannelNameOverride ?? _owners.settings.showChannelName,
        channelName: channelName,
        channels: channelDirectory,
        currentChannelId: channelId ?? _owners.library.currentWatchingChannelId,
        currentChannelNumber: channelNumber,
      );
      if (launched) {
        if (mounted) {
          setState(() {
            _owners.session.status = 'Playing via Android TV';
          });
        }
        return true;
      }
    } catch (e) {
      debugPrint('DebrifyTV: Android TV bridge failed for PikPak: $e');
      if (e is NativePlayerSettingsUnavailable) rethrow;
    }

    AndroidTvPlayerBridge.clearTorboxProvider();
    return false;
  }

  void showChannelCreationDialog(String channelName, {int? countdownSeconds}) {
    if (_owners.progress.progressOpen || !mounted) {
      return;
    }
    _owners.progress.progress.value = [];
    _owners.progress.progressOpen = true;
    Future.microtask(() {
      if (!mounted || !_owners.progress.progressOpen) {
        return;
      }
      // showGeneralDialog skips InheritedTheme capture; snapshot this frozen
      // screen's themes so the dialog stays legacy under any app theme.
      final capturedThemes = captureAppThemes(context);
      showGeneralDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (ctx, _, __) {
          return capturedThemes.wrap(
            ChannelCreationDialog(
              channelName: channelName,
              countdownSeconds: countdownSeconds,
              onReady: (dialogCtx) {
                _owners.progress.progressSheetContext = dialogCtx;
              },
            ),
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

  void showCachedPlaybackDialog() {
    debugPrint(
      '[MagicTV] _showCachedPlaybackDialog called, _progressOpen=${_owners.progress.progressOpen}, mounted=$mounted, _watchCancelled=${_owners.session.watchCancelled}',
    );
    if (_owners.progress.progressOpen || !mounted) {
      return;
    }

    // Reset cancellation flag for new playback session.
    // This must happen before the auto-launch check so that playback can proceed
    // even when the dialog is skipped (auto-launch has its own overlay UI).
    _owners.session.watchCancelled = false;
    debugPrint(
      '[MagicTV] _showCachedPlaybackDialog: Reset _watchCancelled to false',
    );

    _owners.progress.progress.value = [];
    _owners.progress.progressOpen = true;
    Future.microtask(() {
      if (!mounted || !_owners.progress.progressOpen) {
        return;
      }
      // Same snapshot rule as the channel-creation dialog above.
      final capturedThemes = captureAppThemes(context);
      showGeneralDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (ctx, _, __) {
          // Use pageBuilder context directly - simpler and avoids race conditions
          _owners.progress.progressSheetContext = ctx;
          return capturedThemes.wrap(
            CachedLoadingDialog(
              onCancel: () {
                debugPrint('[MagicTV] onCancel callback triggered');
                cancelActiveWatch(dialogContext: ctx);
              },
            ),
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
    if (_owners.session.isBusy) return;
    final apiKey = await RealDebridStorage.getApiKey();
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
      _owners.session.isBusy = true;
      _owners.session.status = 'Finding a playable stream...';
    });

    try {
      while (_owners.session.queue.isNotEmpty) {
        final next = _owners.session.queue.removeAt(0);
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
              _owners.session.status = 'Playing: ${next.name}';
            });

            if (await handOffToExternalPlayer(videoUrl, next.name)) {
              break;
            }

            // Hide auto-launch overlay before launching player
            MainPageBridge.notifyPlayerLaunching();

            await Navigator.of(context).push(
              videoPlayerRoute(
                builder: (_) => VideoPlayerScreen(
                  videoUrl: videoUrl,
                  title: next.name,
                  startFromRandom: _owners.settings.quickStartRandom,
                  randomStartMaxPercent:
                      _owners.settings.quickRandomStartPercent,
                  hideSeekbar: _owners.settings.quickHideSeekbar,
                  showChannelName: _owners.settings.quickShowChannelName,
                  channelName: null,
                  channelNumber: null,
                  showVideoTitle: _owners.settings.quickShowVideoTitle,
                  hideOptions: _owners.settings.quickHideOptions,
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

      if (_owners.session.queue.isEmpty) {
        // Close popup and show user-friendly message
        if (_owners.progress.progressOpen &&
            _owners.progress.progressSheetContext != null) {
          Navigator.of(_owners.progress.progressSheetContext!).pop();
          _owners.progress.progressOpen = false;
          _owners.progress.progressSheetContext = null;
        }

        if (mounted) {
          setState(() {
            _owners.session.isBusy = false;
            _owners.session.status =
                'No playable torrents found. Try different keywords.';
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
          _owners.session.status =
              'Queue has ${_owners.session.queue.length} remaining';
        });
      }
    } finally {
      setState(() {
        _owners.session.isBusy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (_owners.library.debrifyTvStyle == 'spotlight') {
      return SpotlightLayout(
        view: _sections.legacy.buildSpotlightView(),
        bottomInset: bottomInset,
        entryFocusNode: _owners.focus.quickPlayFocusNode,
      );
    }
    // The historical layout, byte-identical under `grid` — the branch calls
    // it unchanged, never a re-implementation.
    return _sections.legacy.buildTvGridLayout(bottomInset);
  }

  /// The Spotlight layout's window onto this state. Paint only: every
  /// callback is an existing method, every playback path is shared verbatim.
  DebrifyTvView buildSpotlightView() {
    return DebrifyTvView(
      channels: _owners.library.channels,
      favoriteIds: _owners.library.favoriteChannelIds,
      railHealth: _owners.stage.spotlightRailHealth,
      stats: _owners.stage.spotlightFocusedId == null
          ? null
          : _owners.stage.spotlightStats[_owners.stage.spotlightFocusedId],
      busy: _owners.session.isBusy,
      onQuickPlay: showQuickPlayDialog,
      onAdd: handleAddChannel,
      onImport: handleImportChannels,
      onExport: handleExportChannels,
      onDeleteAll: handleDeleteAllChannels,
      onSettings: showGlobalSettingsDialog,
      onWatch: watchChannel,
      onEdit: handleEditChannel,
      onShare: handleShareChannelAsMagnet,
      onDelete: handleDeleteChannel,
      onToggleFavorite: toggleChannelFavorite,
      onChannelFocused: _onSpotlightChannelFocused,
      onWatchOne: (channel, torrent) =>
          watchChannel(channel, leadWith: torrent),
    );
  }

  Future<void> loadSpotlightRailHealth() async {
    final health = await DebrifyTvCacheService.loadRailHealth();
    if (!mounted) return;
    setState(() => _owners.stage.spotlightRailHealth = health);
  }

  /// Focus moved to a channel row. The stage's numbers need a per-row name
  /// classify over the pool, so: debounced (a DPAD glide crosses many rows),
  /// computed only for the channel that focus RESTS on, and memoised — a
  /// pool does not change while you are looking at it.
  void _onSpotlightChannelFocused(DebrifyTvChannel channel) {
    // Cancel FIRST, unconditionally: a memo hit must still kill a pending
    // timer for the previous channel, or gliding B→A (A memoised) classifies
    // B off-focus.
    _owners.stage.spotlightStatsDebounce?.cancel();
    _owners.stage.spotlightFocusedId = channel.id;
    // Rebuild NOW either way. On a miss the view's stats go null and the
    // stage draws placeholders — never another channel's numbers, which a
    // plate press would turn into another channel's torrent.
    setState(() {});
    if (_owners.stage.spotlightStats.containsKey(channel.id)) return;
    _owners.stage.spotlightStatsDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _computeSpotlightStats(channel),
    );
  }

  /// Wipe every memoised stage snapshot and recompute the focused channel's.
  /// For when the numbers' INPUTS change — the quality filter — rather than
  /// one channel's pool.
  void invalidateSpotlightStats() {
    if (_owners.library.debrifyTvStyle != 'spotlight') return;
    _owners.stage.spotlightStats.clear();
    refreshSpotlightStatsIfFocused(_owners.stage.spotlightFocusedId);
  }

  /// A channel's pool (or the filter over it) changed; if it is the one the
  /// stage is showing, schedule fresh numbers — memo removal alone leaves
  /// the stage on its placeholder forever, since only a focus MOVE computes.
  void refreshSpotlightStatsIfFocused(String? channelId) {
    if (_owners.library.debrifyTvStyle != 'spotlight' || channelId == null)
      return;
    if (_owners.stage.spotlightFocusedId != channelId) return;
    final channel = _owners.library.channels.firstWhereOrNull(
      (c) => c.id == channelId,
    );
    if (channel != null) _onSpotlightChannelFocused(channel);
  }

  Future<void> _computeSpotlightStats(DebrifyTvChannel channel) async {
    if (!mounted || _owners.stage.spotlightStats.containsKey(channel.id))
      return;
    final entry = await ensureCacheEntry(channel.id);
    // Focus may have moved during the read; bail rather than classify an
    // off-focus pool. The entry stays in _channelCache, so a return visit
    // pays only the classify.
    if (!mounted || _owners.stage.spotlightFocusedId != channel.id) return;
    final torrents = entry?.torrents ?? const <CachedTorrent>[];

    // ONE pass classifies every name: the quality count and the mix buckets
    // share it. Quality only — size is a per-file rule the pool rows cannot
    // answer, and counting it here would promise what playback can't keep.
    final hasQuality = _owners.settings.tvFilters.hasQuality;
    int uhd = 0, fhd = 0, rest = 0, atQuality = 0;
    for (final t in torrents) {
      switch (qualityTierForName(t.name)) {
        case QualityTier.ultraHd:
          uhd++;
        case QualityTier.fullHd:
          fhd++;
        case QualityTier.hd:
        case QualityTier.sd:
          rest++;
      }
      if (!hasQuality ||
          _owners.settings.tvFilters.qualityMatchesName(t.name)) {
        atQuality++;
      }
    }

    final keywordYield = <String, int>{
      for (final kw in entry?.normalizedKeywords ?? const <String>[])
        kw: entry?.keywordStats[kw]?.totalFetched ?? 0,
    };
    final dead = [
      for (final e in keywordYield.entries)
        if (e.value == 0) e.key,
    ];

    final sample = [...torrents]..shuffle(Random());

    final stats = DebrifyTvChannelStats(
      channelId: channel.id,
      pooled: torrents.length,
      atYourQuality: atQuality,
      qualityMix: [uhd, fhd, rest],
      deadKeywords: dead,
      keywordYield: keywordYield,
      fetchedAt: (entry?.fetchedAt ?? 0) > 0
          ? DateTime.fromMillisecondsSinceEpoch(entry!.fetchedAt)
          : null,
      status: entry?.status ?? DebrifyTvCacheStatus.warming,
      sample: sample.take(4).toList(),
    );
    setState(() {
      _owners.stage.spotlightStats[channel.id] = stats;
    });
  }

  void _toggleChannelSearchBar() {
    setState(() {
      _owners.focus.showSearchBar = !_owners.focus.showSearchBar;
      if (_owners.focus.showSearchBar) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _owners.focus.channelSearchFocusNode.requestFocus();
          }
        });
      } else {
        _owners.focus.channelSearchController.clear();
        _owners.focus.channelSearchTerm = '';
      }
    });
  }

  void clearChannelSearchAndRefocus() {
    _owners.focus.channelSearchController.clear();
    setState(() {
      _owners.focus.channelSearchTerm = '';
    });
    _owners.focus.channelSearchFocusNode.requestFocus();
  }

  void focusBelowChannelSearch() {
    final fieldContext = _owners.focus.channelSearchFocusNode.context;
    if (fieldContext != null) {
      FocusScope.of(fieldContext).nextFocus();
    }
  }

  void _handleTopMenuAction(DebrifyTvTopMenuAction action) {
    switch (action) {
      case DebrifyTvTopMenuAction.import:
        handleImportChannels();
        break;
      case DebrifyTvTopMenuAction.export:
        handleExportChannels();
        break;
      case DebrifyTvTopMenuAction.add:
        handleAddChannel();
        break;
      case DebrifyTvTopMenuAction.deleteAll:
        handleDeleteAllChannels();
        break;
      case DebrifyTvTopMenuAction.settings:
        showGlobalSettingsDialog();
        break;
    }
  }

  Widget _buildTopActionButton({
    required FocusNode focusNode,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required Color activeColor,

    /// Defaults to the surface's resting control fill (`controlBg`). Nullable
    /// rather than a const default because a token is not a constant.
    Color? inactiveColor,
    bool isActive = false,
    FocusNode? leftFocusNode,
    FocusNode? rightFocusNode,
    bool leftToSidebar = false,
    bool upToSearch = false,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.arrowLeft) {
          if (leftToSidebar) {
            MainPageBridge.focusTvSidebar?.call();
          } else {
            leftFocusNode?.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          rightFocusNode?.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          if (upToSearch && _owners.focus.showSearchBar) {
            _owners.focus.channelSearchFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          onPressed?.call();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final app = AppThemeScope.of(context);
          final tv = app.debrifyTv;
          final disabled = onPressed == null;
          final focused = focusNode.hasFocus;
          final highlighted = !disabled && (focused || isActive);

          return Tooltip(
            message: tooltip,
            child: GestureDetector(
              onTap: onPressed,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  // LEFT LITERAL: the disabled greys. No role holds
                  // `Colors.grey` / grey-at-0.3, and a disabled tone is not
                  // one of this surface's fills.
                  color: disabled
                      ? Colors.grey.withValues(alpha: 0.3)
                      : (focused
                            ? activeColor
                            : (inactiveColor ?? tv.controlBg)),
                  borderRadius: app.shape.br(20),
                  border: focused && !disabled
                      ? Border.all(
                          color: tv.focusRing.withValues(alpha: 0.6),
                          width: 2,
                        )
                      : null,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: disabled
                      ? Colors.grey
                      : (highlighted
                            ? app.core.tx
                            : app.core.tx.withValues(alpha: 0.5)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopMenuButton() {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final itemStyle = ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? tv.textFaint
            : states.contains(WidgetState.focused)
            ? app.inkOn(app.core.tx)
            : tv.textDim,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? app.core.tx
            : Colors.transparent,
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: app.shape.br(12)),
      ),
    );
    return Focus(
      focusNode: _owners.focus.channelMenuFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (_owners.focus.channelMenuController.isOpen) {
          if (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            _owners.focus.channelMenuController.close();
            _owners.focus.channelMenuFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        if (key == LogicalKeyboardKey.arrowLeft) {
          _owners.focus.channelSearchButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          if (_owners.focus.showSearchBar) {
            _owners.focus.channelSearchFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          _owners.focus.channelMenuController.open();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: _owners.focus.channelMenuFocusNode,
        builder: (context, _) => MenuAnchor(
          controller: _owners.focus.channelMenuController,
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(tv.noticeBg),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(18),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: app.shape.br(18),
                side: BorderSide(color: tv.hairline),
              ),
            ),
          ),
          menuChildren: [
            MenuItemButton(
              autofocus: true,
              style: itemStyle,
              leadingIcon: const Icon(Icons.cloud_download_rounded),
              onPressed: _owners.session.isBusy
                  ? null
                  : () => _handleTopMenuAction(DebrifyTvTopMenuAction.import),
              child: const Text('Import'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.folder_zip_rounded),
              onPressed:
                  _owners.session.isBusy || _owners.library.channels.isEmpty
                  ? null
                  : () => _handleTopMenuAction(DebrifyTvTopMenuAction.export),
              child: const Text('Export Channels'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.add_rounded),
              onPressed: _owners.session.isBusy
                  ? null
                  : () => _handleTopMenuAction(DebrifyTvTopMenuAction.add),
              child: const Text('Add Channel'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.delete_outline_rounded),
              onPressed:
                  _owners.session.isBusy || _owners.library.channels.isEmpty
                  ? null
                  : () =>
                        _handleTopMenuAction(DebrifyTvTopMenuAction.deleteAll),
              child: const Text('Delete All'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.settings_rounded),
              onPressed: () =>
                  _handleTopMenuAction(DebrifyTvTopMenuAction.settings),
              child: const Text('Settings'),
            ),
          ],
          builder: (context, controller, child) {
            final focused = _owners.focus.channelMenuFocusNode.hasFocus;

            return Tooltip(
              message: 'Options',
              child: GestureDetector(
                onTap: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: focused ? tv.fillStrong : tv.controlBg,
                    borderRadius: app.shape.br(20),
                    border: focused
                        ? Border.all(
                            color: tv.focusRing.withValues(alpha: 0.6),
                            width: 2,
                          )
                        : null,
                  ),
                  child: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: focused
                        ? app.core.tx
                        : app.core.tx.withValues(alpha: 0.5),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget buildTopActions() {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTopActionButton(
          focusNode: _owners.focus.quickPlayFocusNode,
          icon: Icons.play_arrow_rounded,
          tooltip: 'Play',
          onPressed: _owners.session.isBusy ? null : showQuickPlayDialog,
          activeColor: tv.fillStrong,
          leftToSidebar: true,
          rightFocusNode: _owners.focus.channelSearchButtonFocusNode,
        ),
        const SizedBox(width: 10),
        _buildTopActionButton(
          focusNode: _owners.focus.channelSearchButtonFocusNode,
          icon: Icons.search_rounded,
          tooltip: _owners.focus.showSearchBar
              ? 'Close search'
              : 'Search channels',
          onPressed: _toggleChannelSearchBar,
          activeColor: tv.fillStrong,
          isActive:
              _owners.focus.showSearchBar ||
              _owners.focus.channelSearchTerm.isNotEmpty,
          leftFocusNode: _owners.focus.quickPlayFocusNode,
          rightFocusNode: _owners.focus.channelMenuFocusNode,
          upToSearch: true,
        ),
        const SizedBox(width: 10),
        _buildTopMenuButton(),
      ],
    );
  }

  // Grid Layout for all devices (responsive)
  Widget buildTvGridLayout(double bottomInset) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final searchTerm = _owners.focus.channelSearchTerm.trim().toLowerCase();
    final filteredChannels = searchTerm.isEmpty
        ? _owners.library.channels
        : _owners.library.channels
              .where(
                (channel) => channel.name.toLowerCase().contains(searchTerm),
              )
              .toList();

    final screenWidth = MediaQuery.of(context).size.width;
    // Responsive padding: smaller on mobile, larger on TV/tablet
    final horizontalPadding = screenWidth < 600 ? 16.0 : 40.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        24,
        horizontalPadding,
        24 + bottomInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Centered top controls: Play, Search, and overflow.
          buildTopActions(),
          // Search field for TV (only show when toggled)
          if (_owners.focus.showSearchBar) ...[
            const SizedBox(height: 16),
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: handleChannelSearchBarBack,
              child: TvTextField(
                focusNode: _owners.focus.channelSearchFocusNode,
                controller: _owners.focus.channelSearchController,
                style: TextStyle(color: app.core.tx),
                // Shared TV shell/keyboard chrome — settings.accent, with the
                // keyboard's own panel ground and ink.
                accent: app.settings.accent,
                keyboardGround: app.youtube.keyboardPanel,
                keyboardInk: app.core.tx,
                keyboardInkOnAccent: app.inkOn(app.settings.accent),
                onLeftArrow: () => MainPageBridge.focusTvSidebar?.call(),
                onRightArrow: () {
                  if (_owners.focus.channelSearchController.text.isNotEmpty) {
                    _owners.focus.channelSearchClearFocusNode.requestFocus();
                  }
                },
                onUpArrow: () =>
                    _owners.focus.channelSearchButtonFocusNode.requestFocus(),
                onSubmitted: (_) => focusBelowChannelSearch(),
                onDownArrow: focusBelowChannelSearch,
                decoration: InputDecoration(
                  hintText: 'Search channels...',
                  hintStyle: TextStyle(
                    color: app.core.tx.withValues(alpha: 0.3),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: app.core.tx.withValues(alpha: 0.35),
                  ),
                  suffixIcon: _owners.focus.channelSearchTerm.isNotEmpty
                      ? Focus(
                          focusNode: _owners.focus.channelSearchClearFocusNode,
                          skipTraversal: true,
                          onKeyEvent: (node, event) {
                            if (event is! KeyDownEvent) {
                              return KeyEventResult.ignored;
                            }
                            final key = event.logicalKey;
                            if (key == LogicalKeyboardKey.arrowLeft) {
                              _owners.focus.channelSearchFocusNode
                                  .requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowRight) {
                              _owners.focus.channelMenuFocusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowUp) {
                              _owners.focus.channelSearchButtonFocusNode
                                  .requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (isActivateKey(key) ||
                                key == LogicalKeyboardKey.space) {
                              clearChannelSearchAndRefocus();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: Builder(
                            builder: (context) {
                              final ink = AppThemeScope.of(context).core.tx;
                              final focused = Focus.of(context).hasFocus;
                              return Container(
                                decoration: focused
                                    ? BoxDecoration(
                                        borderRadius: app.shape.br(20),
                                        border: Border.all(
                                          color: ink.withValues(alpha: 0.3),
                                          width: 1.5,
                                        ),
                                      )
                                    : null,
                                child: IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: focused
                                        ? ink
                                        : ink.withValues(alpha: 0.5),
                                  ),
                                  onPressed: clearChannelSearchAndRefocus,
                                ),
                              );
                            },
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: app.shape.br(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: app.shape.br(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: app.shape.br(14),
                    borderSide: BorderSide(
                      // The search field's focused border is `fillStrong` by
                      // design — see the token's own doc.
                      color: tv.fillStrong,
                      width: 1,
                    ),
                  ),
                  filled: true,
                  fillColor: app.core.tx.withValues(alpha: 0.07),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  setState(() {
                    _owners.focus.channelSearchTerm = value;
                  });
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Favorite channels section (only shows if there are favorites)
          buildFavoriteChannelsSection(),
          // "All" section header (only show when there are favorites to distinguish)
          if (_owners.library.favoriteChannelIds.isNotEmpty &&
              filteredChannels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.grid_view_rounded,
                    size: 18,
                    color: app.core.tx.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'All Channels',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: app.core.tx.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          // Channel grid (responsive)
          Expanded(
            child: filteredChannels.isEmpty
                ? _buildTvEmptyState()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Responsive grid: 2 cols on mobile, 3 on tablet, 4 on TV/desktop
                      final width = constraints.maxWidth;
                      int crossAxisCount;
                      double spacing;
                      double childAspectRatio;

                      if (width < 500) {
                        crossAxisCount = 2;
                        spacing = 12;
                        childAspectRatio = 1.4;
                      } else if (width < 800) {
                        crossAxisCount = 3;
                        spacing = 16;
                        childAspectRatio = 1.45;
                      } else {
                        crossAxisCount = 4;
                        spacing = 24;
                        childAspectRatio = 1.5;
                      }

                      return GridView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: childAspectRatio,
                        ),
                        itemCount:
                            filteredChannels.length +
                            1, // +1 for "Add Channel" card
                        itemBuilder: (context, index) {
                          if (index == filteredChannels.length) {
                            // "Add Channel" card at the end
                            return KeyedSubtree(
                              key: const ValueKey('add_channel_card'),
                              child: buildTvAddChannelCard(),
                            );
                          }
                          final channel = filteredChannels[index];
                          return KeyedSubtree(
                            key: ValueKey('channel_${channel.id}'),
                            child: buildTvChannelCard(channel),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // TV Empty State
  Widget _buildTvEmptyState() {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.tv_rounded, size: 120, color: app.core.tx.withAlpha(51)),
          const SizedBox(height: 24),
          Text(
            'No channels yet',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: tv.textDim,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Import channels or create your first channel to get started',
            style: TextStyle(fontSize: 16, color: tv.textFaint),
          ),
          const SizedBox(height: 32),
          TvFocusableButton(
            onPressed: handleAddChannel,
            icon: Icons.add_rounded,
            label: 'Add Channel',
            backgroundColor: tv.accent,
            width: 200,
          ),
        ],
      ),
    );
  }

  // Favorite Channels Section (horizontal row)
  Widget buildFavoriteChannelsSection() {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    // Get favorite channels from the channels list
    final favoriteChannels = _owners.library.channels
        .where(
          (channel) => _owners.library.favoriteChannelIds.contains(channel.id),
        )
        .toList();

    // Don't show if no favorites
    if (favoriteChannels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.star_rounded,
                size: 18,
                color: tv.favorite.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Text(
                'Favorites',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: app.core.tx.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Horizontal scrolling favorites
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: favoriteChannels.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final channel = favoriteChannels[index];
              return _buildFavoriteChannelCard(channel);
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // Favorite Channel Card (compact horizontal card)
  Widget _buildFavoriteChannelCard(DebrifyTvChannel channel) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return SizedBox(
      width: 160,
      height: 100,
      child: TvFocusableCard(
        onPressed: () => watchChannel(channel),
        onLongPress: () => showTvChannelOptionsMenu(channel),
        child: Stack(
          children: [
            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Channel number badge (smaller)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tv.accent,
                      borderRadius: app.shape.br(6),
                    ),
                    child: Text(
                      'CH ${channel.channelNumber > 0 ? channel.channelNumber : _owners.library.channels.indexOf(channel) + 1}',
                      style: TextStyle(
                        color: app.inkOn(tv.accent),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Channel name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      channel.name.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: app.core.tx,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Star indicator
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                Icons.star_rounded,
                size: 14,
                color: tv.favorite,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // TV Channel Card (Grid item)
  Widget buildTvChannelCard(DebrifyTvChannel channel) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final isFavorited = _owners.library.favoriteChannelIds.contains(channel.id);

    return TvFocusableCard(
      onPressed: () {
        watchChannel(channel);
      },
      onLongPress: () {
        showTvChannelOptionsMenu(channel);
      },
      showLongPressHint:
          _owners.settings.isAndroidTv, // Only show hint on Android TV
      child: Stack(
        children: [
          // Favorite star indicator (top-left)
          if (isFavorited)
            Positioned(
              top: 6,
              left: 6,
              child: Icon(
                Icons.star_rounded,
                size: 20,
                color: tv.favorite,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          // Main card content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Channel number badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tv.accent,
                    borderRadius: app.shape.br(8),
                  ),
                  child: Text(
                    'CH ${channel.channelNumber > 0 ? channel.channelNumber : _owners.library.channels.indexOf(channel) + 1}',
                    style: TextStyle(
                      color: app.inkOn(tv.accent),
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: app.core.tx,
                      height: 1.2,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 3-dot menu for non-Android TV devices
          if (!_owners.settings.isAndroidTv)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: app.shape.br(6),
                ),
                child: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    // Sits on the black plate above, so it takes glass ink.
                    color: app.onGlass.withValues(alpha: 0.9),
                    size: 16,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'Options',
                  color: tv.noticeBg,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: app.shape.br(18),
                    side: BorderSide(color: tv.hairline),
                  ),
                  onSelected: (value) {
                    if (value == 'favorite') {
                      toggleChannelFavorite(channel);
                    } else if (value == 'edit') {
                      handleEditChannel(channel);
                    } else if (value == 'share') {
                      handleShareChannelAsMagnet(channel);
                    } else if (value == 'delete') {
                      handleDeleteChannel(channel);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'favorite',
                      child: Row(
                        children: [
                          Icon(
                            isFavorited
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 18,
                            color: tv.favorite,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isFavorited
                                ? 'Remove Favorite'
                                : 'Add to Favorites',
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Share Channel'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // TV Channel Options Menu (Edit/Delete)
  Future<void> showTvChannelOptionsMenu(DebrifyTvChannel channel) async {
    final isFavorited = _owners.library.favoriteChannelIds.contains(channel.id);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return DebrifyTvSpotlightDialog(
          eyebrow:
              'Channel actions · ${channel.channelNumber.toString().padLeft(2, '0')}',
          title: channel.name,
          subtitle: 'Manage this channel without leaving the current view.',
          icon: Icons.tune_rounded,
          maxWidth: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DebrifyTvDialogOptionCard(
                autofocus: true,
                icon: isFavorited
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                title: isFavorited ? 'Remove pin' : 'Pin channel',
                subtitle: isFavorited
                    ? 'Return this channel to the main list.'
                    : 'Keep this channel at the top of the rail.',
                tag: isFavorited ? 'Pinned' : 'Pin',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  toggleChannelFavorite(channel);
                },
              ),
              const SizedBox(height: 10),
              DebrifyTvDialogOptionCard(
                icon: Icons.edit_rounded,
                title: 'Edit channel',
                subtitle: 'Change its name, keywords, or content filter.',
                tag: 'Edit',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  handleEditChannel(channel);
                },
              ),
              const SizedBox(height: 10),
              DebrifyTvDialogOptionCard(
                icon: Icons.share_rounded,
                title: 'Share channel',
                subtitle: 'Create a portable Debrify link for this pool.',
                tag: 'Link',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  handleShareChannelAsMagnet(channel);
                },
              ),
              const SizedBox(height: 10),
              DebrifyTvDialogOptionCard(
                icon: Icons.delete_outline_rounded,
                title: 'Delete channel',
                subtitle: 'Remove this channel and its cached title pool.',
                tag: 'Careful',
                danger: true,
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  handleDeleteChannel(channel);
                },
              ),
            ],
          ),
          actions: [
            DebrifyTvDialogButton(
              label: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  // TV "Add Channel" Card
  Widget buildTvAddChannelCard() {
    final tv = AppThemeScope.of(context).debrifyTv;
    return TvFocusableCard(
      onPressed: handleAddChannel,
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
                color: tv.fillWeak,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_rounded, size: 32, color: tv.textDim),
            ),
            const SizedBox(height: 12),
            Text(
              'Add Channel',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: tv.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSettingsCard({
    required DebrifyTvSettingsScope scope,
    required bool includeNsfwToggle,
    required String title,
    StateSetter? dialogSetState,
  }) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final bool isQuickScope = scope == DebrifyTvSettingsScope.quickPlay;

    final bool startRandom = isQuickScope
        ? _owners.settings.quickStartRandom
        : _owners.settings.startRandom;
    void setStartRandom(bool value) {
      setState(() {
        if (isQuickScope) {
          _owners.settings.quickStartRandom = value;
        } else {
          _owners.settings.startRandom = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvStorage.saveDebrifyTvStartRandom(value));
      }
    }

    final int randomStartPercent = isQuickScope
        ? _owners.settings.quickRandomStartPercent
        : _owners.settings.randomStartPercent;
    void setRandomStartPercent(int value) {
      setState(() {
        if (isQuickScope) {
          _owners.settings.quickRandomStartPercent = value;
        } else {
          _owners.settings.randomStartPercent = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvStorage.saveDebrifyTvRandomStartPercent(value));
      }
    }

    final bool showChannelName = isQuickScope
        ? _owners.settings.quickShowChannelName
        : _owners.settings.showChannelName;
    void setShowChannelName(bool value) {
      setState(() {
        if (isQuickScope) {
          _owners.settings.quickShowChannelName = value;
        } else {
          _owners.settings.showChannelName = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvStorage.saveDebrifyTvShowChannelName(value));
      }
    }

    final bool showVideoTitle = isQuickScope
        ? _owners.settings.quickShowVideoTitle
        : _owners.settings.showVideoTitle;
    void setShowVideoTitle(bool value) {
      setState(() {
        if (isQuickScope) {
          _owners.settings.quickShowVideoTitle = value;
        } else {
          _owners.settings.showVideoTitle = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvStorage.saveDebrifyTvShowVideoTitle(value));
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
          color: tv.fillWeak.withValues(alpha: .55),
          borderRadius: app.shape.br(20),
          border: Border.all(color: tv.hairline, width: 1),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: tv.textFaint,
                    fontFamily: 'JetBrainsMono',
                    fontSize: 9,
                    letterSpacing: 1.6,
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
            providerChoiceChips(scope, dialogSetState: dialogSetState),
            const SizedBox(height: 16),
            SwitchRow(
              title: 'Start from random timestamp',
              subtitle: 'Each Debrify TV video starts at a random point',
              value: startRandom,
              onChanged: (v) => setStartRandom(v),
            ),
            if (startRandom) ...[
              const SizedBox(height: 8),
              RandomStartSlider(
                value: randomStartPercent,
                isAndroidTv: _owners.settings.isAndroidTv,
                onChanged: (next) => setRandomStartPercent(next),
                onChangeEnd: isQuickScope
                    ? null
                    : (next) =>
                          DebrifyTvStorage.saveDebrifyTvRandomStartPercent(
                            next,
                          ),
              ),
            ],
            // Removed Hide all options and Hide back button settings
            // These are now hardcoded to false (visible by default)
            if (includeNsfwToggle && isQuickScope) ...[
              const SizedBox(height: 8),
              SwitchRow(
                title: 'Avoid NSFW content',
                subtitle: _owners.settings.viewerForcesNsfw
                    ? 'Always on for this profile'
                    : 'Filter adult/inappropriate torrents • Best effort, not 100% accurate',
                value:
                    _owners.settings.viewerForcesNsfw ||
                    _owners.settings.quickAvoidNsfw,
                onChanged: (v) {
                  // Role-locked: a child session cannot loosen it.
                  if (_owners.settings.viewerForcesNsfw) return;
                  setState(() {
                    _owners.settings.quickAvoidNsfw = v;
                  });
                  dialogSetState?.call(() {});
                },
              ),
            ],
            const SizedBox(height: 16),
            // Kept LAST (above Reset) on purpose: these are ~14 focusable
            // chips, and placing them higher would push every existing switch
            // that many extra D-pad presses away on TV.
            tvFilterChips(dialogSetState: dialogSetState),
            const SizedBox(height: 16),
            DebrifyTvDialogButton(
              expand: true,
              icon: Icons.restore_rounded,
              label: 'Reset to defaults',
              onPressed: () async {
                final defaultProvider = determineDefaultProvider(
                  null,
                  _owners.settings.rdAvailable,
                  _owners.settings.torboxAvailable,
                  _owners.settings.pikpakAvailable,
                  _owners.settings.premiumizeAvailable,
                  _owners.settings.allDebridAvailable,
                );

                setState(() {
                  if (isQuickScope) {
                    _owners.settings.quickStartRandom = true;
                    _owners.settings.quickRandomStartPercent =
                        randomStartPercentDefault;
                    _owners.settings.quickHideSeekbar = true;
                    _owners.settings.quickShowChannelName = true;
                    _owners.settings.quickShowVideoTitle = true;
                    _owners.settings.quickHideOptions =
                        false; // Hardcoded to false
                    _owners.settings.quickHideBackButton =
                        false; // Hardcoded to false
                    _owners.settings.quickAvoidNsfw = true;
                    _owners.settings.quickProvider = defaultProvider;
                  } else {
                    _owners.settings.startRandom = true;
                    _owners.settings.randomStartPercent =
                        randomStartPercentDefault;
                    _owners.settings.hideSeekbar = true;
                    _owners.settings.showChannelName = true;
                    _owners.settings.showVideoTitle = true;
                    _owners.settings.hideOptions = false; // Hardcoded to false
                    _owners.settings.hideBackButton =
                        false; // Hardcoded to false
                    _owners.settings.provider = defaultProvider;
                  }
                  // Playback filters are shared by both scopes, so reset
                  // them from either one.
                  _owners.settings.tvFilters = const DebrifyTvFilters.empty();
                });
                invalidateSpotlightStats();
                dialogSetState?.call(() {});

                await DebrifyTvStorage.setDebrifyTvFilterQualities(const []);
                await DebrifyTvStorage.setDebrifyTvFilterSizes(const []);

                if (!isQuickScope) {
                  await DebrifyTvStorage.saveDebrifyTvStartRandom(true);
                  await DebrifyTvStorage.saveDebrifyTvHideSeekbar(true);
                  await DebrifyTvStorage.saveDebrifyTvShowChannelName(true);
                  await DebrifyTvStorage.saveDebrifyTvShowVideoTitle(true);
                  // No longer saving hideOptions and hideBackButton - they're hardcoded to false
                  await DebrifyTvStorage.saveDebrifyTvProvider(defaultProvider);
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
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showQuickPlayDialog() async {
    if (_owners.session.isBusy) {
      return;
    }

    bool avoidNsfw = _owners.settings.quickAvoidNsfw;
    String? error;
    // Create a separate controller for Quick Play to avoid sharing state with edit dialog
    final TextEditingController controller = TextEditingController();
    final FocusNode keywordFocusNode = FocusNode(
      debugLabel: 'QuickPlayKeywordsField',
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final app = AppThemeScope.of(context);
            return DebrifyTvSpotlightDialog(
              eyebrow: 'Quick play · no channel needed',
              title: 'Play anything',
              subtitle:
                  'Enter up to ${_owners.settings.quickPlayMaxKeywords} search terms. Nothing is saved when playback ends.',
              icon: Icons.play_arrow_rounded,
              maxWidth: 680,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TvTextField(
                    controller: controller,
                    autofocus: true,
                    focusNode: keywordFocusNode,
                    textInputAction: TextInputAction.search,
                    // Shared TV shell/keyboard chrome — settings.accent,
                    // with the keyboard's own panel ground and ink.
                    accent: app.settings.accent,
                    keyboardGround: app.youtube.keyboardPanel,
                    keyboardInk: app.core.tx,
                    keyboardInkOnAccent: app.inkOn(app.settings.accent),
                    decoration: const InputDecoration(
                      labelText: 'Keywords',
                      hintText: 'Comma separated keywords',
                    ),
                    onDownArrow: () {
                      final ctx = keywordFocusNode.context;
                      if (ctx != null) {
                        FocusScope.of(ctx).nextFocus();
                      }
                    },
                    onUpArrow: () {
                      final ctx = keywordFocusNode.context;
                      if (ctx != null) {
                        FocusScope.of(ctx).previousFocus();
                      }
                    },
                    onChanged: (_) {
                      if (error != null) {
                        setDialogState(() => error = null);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchRow(
                    title: 'Avoid NSFW content',
                    subtitle: _owners.settings.viewerForcesNsfw
                        ? 'Always on for this profile'
                        : 'Best-effort filter while searching',
                    value: _owners.settings.viewerForcesNsfw || avoidNsfw,
                    onChanged: (value) {
                      // Role-locked: a child session cannot loosen it.
                      if (_owners.settings.viewerForcesNsfw) return;
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
              actions: [
                DebrifyTvDialogButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                DebrifyTvDialogButton(
                  label: 'Play now',
                  icon: Icons.play_arrow_rounded,
                  tone: DebrifyTvDialogButtonTone.primary,
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
                        _owners.settings.quickStartRandom =
                            _owners.settings.startRandom;
                        _owners.settings.quickRandomStartPercent =
                            _owners.settings.randomStartPercent;
                        _owners.settings.quickHideSeekbar =
                            _owners.settings.hideSeekbar;
                        _owners.settings.quickShowChannelName =
                            _owners.settings.showChannelName;
                        _owners.settings.quickShowVideoTitle =
                            _owners.settings.showVideoTitle;
                        _owners.settings.quickHideOptions =
                            false; // Always false now
                        _owners.settings.quickHideBackButton =
                            false; // Always false now
                        _owners.settings.quickAvoidNsfw = avoidNsfw;
                        _owners.settings.quickProvider =
                            _owners.settings.provider;
                      });
                      // Copy keywords from Quick Play controller to main controller for _watch()
                      _owners.library.keywordsController.text = keywords;
                    }

                    Navigator.of(dialogContext).pop();
                    // Wait for frames to ensure UI has updated and touch events are processed
                    await Future.delayed(const Duration(milliseconds: 100));
                    await WidgetsBinding.instance.endOfFrame;
                    await WidgetsBinding.instance.endOfFrame;
                    if (mounted) {
                      await watch();
                    }
                  },
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

  Future<void> showGlobalSettingsDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return DebrifyTvSpotlightDialog(
              eyebrow: 'Debrify TV · applies to every channel',
              title: 'Channel playback',
              subtitle:
                  'Choose the provider, filters, and starting behavior used when a channel tunes.',
              icon: Icons.settings_rounded,
              maxWidth: 920,
              maxHeightFactor: .94,
              child: buildSettingsCard(
                scope: DebrifyTvSettingsScope.channels,
                includeNsfwToggle: false,
                title: 'Playback rules',
                dialogSetState: setDialogState,
              ),
              actions: [
                DebrifyTvDialogButton(
                  autofocus: true,
                  label: 'Done',
                  icon: Icons.check_rounded,
                  tone: DebrifyTvDialogButtonTone.primary,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<Map<String, String>?> resolveTorboxQueuedFile({
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

  Future<TorboxPreparedTorrent?> prepareTorboxTorrent({
    required Torrent candidate,
    required String apiKey,
    required void Function(String message) log,
  }) async {
    final infohash = normalizeInfohash(candidate.infohash);
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
          (entry) => !_owners.session.seenLinkWithTorrentId.contains(
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
      _owners.session.seenLinkWithTorrentId.add(
        '${currentTorrent.id}|${next.file.id}',
      );
      return TorboxPreparedTorrent(
        streamUrl: streamUrl,
        title: next.title,
        hasMore: filteredEntries.isNotEmpty,
      );
    } catch (e) {
      log('❌ Torbox requestdl failed: $e');
      return null;
    }
  }

  Future<PikPakPreparedTorrent?> preparePikPakTorrent({
    required Torrent candidate,
    required void Function(String message) log,
  }) async {
    final infohash = normalizeInfohash(candidate.infohash);
    if (infohash.isEmpty) {
      return null;
    }

    log('⏳ PikPak: preparing ${candidate.name}');

    final prepared = await PikPakTvService.instance.prepareTorrent(
      infohash: infohash,
      torrentName: candidate.name,
      onLog: log,
    );

    if (prepared == null) {
      log('⚠️ PikPak torrent not ready ${candidate.name}');
      return null;
    }

    // Check if this is a multi-file torrent
    final allVideoFiles = prepared['allVideoFiles'] as List<dynamic>?;

    if (allVideoFiles == null || allVideoFiles.isEmpty) {
      // Single file torrent - return directly
      log('🎬 PikPak: streaming ${prepared['title']}');
      return PikPakPreparedTorrent(
        streamUrl: prepared['url'] as String,
        title: prepared['title'] as String,
        hasMore: false,
      );
    }

    // Multi-file torrent - filter out seen files
    final pikpakFolderId = prepared['pikpakFolderId'] as String?;
    if (pikpakFolderId == null) {
      log('⚠️ PikPak multi-file torrent missing folder ID');
      return null;
    }

    // Filter unseen files. PikPak reports a per-file `size`, so the same
    // per-FILE size rules the other providers use apply here — including the
    // 50MB floor that keeps trailers and samples out of the rotation.
    List<dynamic> filterUnseen({required bool applySizeFilter}) {
      return allVideoFiles.where((file) {
        final fileId = file['id'] as String?;
        if (fileId == null || fileId.isEmpty) return false;
        final trackingKey = '$infohash|$fileId';
        if (_owners.session.seenLinkWithTorrentId.contains(trackingKey))
          return false;
        final size = (file['size'] as num?)?.toInt() ?? 0;
        if (size > 0 && size < DebrifyTvConstants.torboxMinVideoSizeBytes)
          return false;
        if (applySizeFilter &&
            !_owners.settings.tvFilters.sizeMatchesBytes(size))
          return false;
        return true;
      }).toList();
    }

    var unseenFiles = filterUnseen(applySizeFilter: true);
    if (unseenFiles.isEmpty && _owners.settings.tvFilters.hasSize) {
      // Nothing in this torrent matched — take it unfiltered rather than
      // discarding the torrent (see the Torbox builder).
      log('⚠️ PikPak: no file matched the size filter — using unfiltered');
      unseenFiles = filterUnseen(applySizeFilter: false);
    }

    if (unseenFiles.isEmpty) {
      log('⚠️ PikPak torrent has no unseen files ${candidate.name}');
      return null;
    }

    // Shuffle and select next file
    final random = Random();
    unseenFiles.shuffle(random);
    final selectedFile = unseenFiles.removeAt(0);
    final selectedFileId = selectedFile['id'] as String?;
    final selectedFileName = selectedFile['name'] as String?;

    if (selectedFileId == null ||
        selectedFileId.isEmpty ||
        selectedFileName == null ||
        selectedFileName.isEmpty) {
      log('⚠️ Selected file has invalid ID or name');
      return null;
    }

    log(
      '🎬 PikPak: selected $selectedFileName (${unseenFiles.length} unseen files)',
    );

    // Get streaming URL for selected file
    String streamUrl;
    try {
      final api = PikPakApiService.instance;
      final fullFileData = await api.getFileDetails(selectedFileId);
      final url = api.getStreamingUrl(fullFileData);
      if (url == null || url.isEmpty) {
        log('⚠️ No streaming URL for selected file');
        return null;
      }
      streamUrl = url;
    } catch (e) {
      log('❌ Failed to get streaming URL: $e');
      return null;
    }

    // Mark as seen
    _owners.session.seenLinkWithTorrentId.add('$infohash|$selectedFileId');

    return PikPakPreparedTorrent(
      streamUrl: streamUrl,
      title: selectedFileName,
      hasMore: unseenFiles.isNotEmpty,
    );
  }

  // ── Premiumize helpers ──────────────────────────────────────────────────────

  Future<TorboxCacheWindowResult> fetchPremiumizeCacheWindow({
    required List<Torrent> candidates,
    required int startIndex,
    required String apiKey,
  }) async {
    const int chunkSize = 100;
    const int maxCalls = 2;

    int cursor = startIndex;
    int calls = 0;
    final List<Torrent> hits = [];

    while (cursor < candidates.length && calls < maxCalls && hits.isEmpty) {
      final int end = min(cursor + chunkSize, candidates.length);
      final List<Torrent> chunk = candidates.sublist(cursor, end);
      cursor = end;

      final List<Torrent> validChunk = chunk
          .where((t) => normalizeInfohash(t.infohash).isNotEmpty)
          .toList();
      final List<String> hashes = validChunk
          .map((t) => normalizeInfohash(t.infohash))
          .toList();

      if (hashes.isEmpty) continue;

      calls++;
      final List<bool> cached = await PremiumizeService.checkCache(
        apiKey,
        hashes,
      );

      for (int i = 0; i < validChunk.length; i++) {
        if (i < cached.length && cached[i]) {
          hits.add(validChunk[i]);
        }
      }
    }

    return TorboxCacheWindowResult(
      cachedTorrents: hits,
      nextCursor: cursor,
      exhausted: cursor >= candidates.length,
    );
  }

  Future<PremiumizePreparedTorrent?> preparePremiumizeTorrent({
    required Torrent candidate,
    required String apiKey,
    required void Function(String message) log,
  }) async {
    final infohash = normalizeInfohash(candidate.infohash);
    if (infohash.isEmpty) return null;

    log('⏳ Premiumize: preparing ${candidate.name}');

    final magnet = 'magnet:?xt=urn:btih:${candidate.infohash}';
    List<PremiumizeFile> files;
    try {
      files = await PremiumizeService.directDownload(apiKey, magnet);
    } catch (e) {
      log('❌ Premiumize directdl failed: $e');
      return null;
    }

    if (files.isEmpty) {
      log('⚠️ Premiumize: no files for ${candidate.name}');
      return null;
    }

    final playableEntries = _buildPremiumizePlayableEntries(
      files,
      candidate.name,
    );
    if (playableEntries.isEmpty) {
      log('⚠️ Premiumize: no playable files for ${candidate.name}');
      return null;
    }

    final filteredEntries = playableEntries
        .where(
          (e) => !_owners.session.seenLinkWithTorrentId.contains(
            '$infohash|${e.file.path}',
          ),
        )
        .toList();
    if (filteredEntries.isEmpty) {
      log('⚠️ Premiumize: no unseen playable files for ${candidate.name}');
      return null;
    }

    filteredEntries.shuffle(Random());
    final next = filteredEntries.removeAt(0);
    final streamUrl = next.file.streamLink ?? next.file.link;
    _owners.session.seenLinkWithTorrentId.add('$infohash|${next.file.path}');
    log('🎬 Premiumize: streaming ${next.title}');
    return PremiumizePreparedTorrent(
      streamUrl: streamUrl,
      title: next.title,
      hasMore: filteredEntries.isNotEmpty,
    );
  }

  List<PremiumizePlayableEntry> _buildPremiumizePlayableEntries(
    List<PremiumizeFile> files,
    String fallbackTitle, {
    bool applySizeFilter = true,
  }) {
    final seriesCandidates = <PremiumizePlayableEntry>[];
    final otherCandidates = <PremiumizePlayableEntry>[];

    for (final file in files) {
      if (!_premiumizeFileLooksLikeVideo(file)) continue;
      if (file.size < DebrifyTvConstants.torboxMinVideoSizeBytes) continue;
      // Per-FILE size filter (see the Torbox builder for the rationale).
      if (applySizeFilter &&
          !_owners.settings.tvFilters.sizeMatchesBytes(file.size))
        continue;

      final displayName = file.fileName.isNotEmpty
          ? file.fileName
          : fallbackTitle;
      final info = SeriesParser.parseFilenameConservative(displayName);
      final title = info.isSeries
          ? formatTorboxSeriesTitle(info, fallbackTitle)
          : (displayName.isNotEmpty ? displayName : fallbackTitle);
      final entry = PremiumizePlayableEntry(
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

    final entries = <PremiumizePlayableEntry>[
      ...seriesCandidates,
      ...otherCandidates,
    ];
    entries.shuffle(Random());
    if (entries.isEmpty &&
        applySizeFilter &&
        _owners.settings.tvFilters.hasSize) {
      debugPrint(
        'DebrifyTV/Premiumize: no file matched the size filter in '
        '"$fallbackTitle" — using it unfiltered.',
      );
      return _buildPremiumizePlayableEntries(
        files,
        fallbackTitle,
        applySizeFilter: false,
      );
    }
    return entries;
  }

  bool _premiumizeFileLooksLikeVideo(PremiumizeFile file) {
    final name = file.fileName;
    if (name.isEmpty) return false;
    return FileUtils.isVideoFile(name);
  }

  Future<void> watchPremiumizeWithCachedTorrents(
    List<Torrent> cachedTorrents, {
    String? channelName,
    String? channelId,
    int? channelNumber,
  }) async {
    if (cachedTorrents.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No cached torrents');
      showSnack(
        'Cached channel has no torrents yet. Please wait a moment.',
        color: Colors.orange,
      );
      return;
    }

    final List<Map<String, dynamic>>? channelDirectory =
        _owners.library.channels.isNotEmpty
        ? androidTvChannelMetadata(
            activeChannelId:
                channelId ?? _owners.library.currentWatchingChannelId,
          )
        : null;

    void log(String message) => debugPrint('DebrifyTV/PM: $message');

    final integrationEnabled =
        await PremiumizeStorage.getPremiumizeIntegrationEnabled();
    if (!integrationEnabled) {
      showSnack(
        'Enable Premiumize in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await PremiumizeStorage.getPremiumizeApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No Premiumize API key');
      showSnack(
        'Please add your Premiumize API key in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    showCachedPlaybackDialog();

    final List<Torrent> candidatePool = List<Torrent>.from(cachedTorrents);
    candidatePool.shuffle(Random());

    if (mounted) {
      setState(() {
        _owners.session.status = 'Checking Premiumize cache...';
        _owners.session.isBusy = true;
      });
    }

    int candidateCursor = 0;

    Future<bool> populateQueue() async {
      while (true) {
        if (candidateCursor >= candidatePool.length) return false;
        final TorboxCacheWindowResult window = await fetchPremiumizeCacheWindow(
          candidates: candidatePool,
          startIndex: candidateCursor,
          apiKey: apiKey,
        );
        candidateCursor = window.nextCursor;
        if (window.cachedTorrents.isEmpty) {
          if (window.exhausted) return false;
          continue;
        }
        _owners.session.queue
          ..clear()
          ..addAll(window.cachedTorrents);
        _owners.session.lastQueueSize = _owners.session.queue.length;
        _owners.session.lastSearchAt = DateTime.now();
        if (mounted) {
          setState(() {
            _owners.session.status = _owners.session.queue.isEmpty
                ? ''
                : 'Queue has ${_owners.session.queue.length} remaining';
          });
        }
        log(
          '✅ Cached Premiumize batch ready with ${_owners.session.queue.length} item(s)',
        );
        return true;
      }
    }

    bool seeded;
    try {
      seeded = await populateQueue();
    } catch (e) {
      closeProgressDialog();
      showSnack('Premiumize cache check failed: $e', color: Colors.orange);
      if (mounted) setState(() => _owners.session.isBusy = false);
      return;
    }

    if (!seeded) {
      closeProgressDialog();
      showSnack(
        'No cached torrents found on Premiumize. Please refresh the channel.',
        color: Colors.orange,
      );
      if (mounted) setState(() => _owners.session.isBusy = false);
      return;
    }

    Future<Map<String, String>?> requestPremiumizeNext() async {
      while (true) {
        if (_owners.session.queue.isEmpty) {
          bool replenished;
          try {
            replenished = await populateQueue();
          } catch (e) {
            closeProgressDialog();
            showSnack(
              'Premiumize cache check failed: $e',
              color: Colors.orange,
            );
            if (mounted) setState(() => _owners.session.isBusy = false);
            return null;
          }
          if (!replenished) break;
        }
        if (_owners.session.queue.isEmpty) break;

        final next = _owners.session.queue.removeAt(0);
        if (next is! Torrent) continue;

        final prepared = await preparePremiumizeTorrent(
          candidate: next,
          apiKey: apiKey,
          log: log,
        );
        if (prepared == null) continue;
        if (prepared.hasMore) candidatePool.add(next);
        return {'url': prepared.streamUrl, 'title': prepared.title};
      }
      return null;
    }

    try {
      final first = await requestPremiumizeNext();
      if (first == null) {
        closeProgressDialog();
        if (!mounted) return;
        setState(() {
          _owners.session.status =
              'No playable Premiumize streams found. Try refreshing.';
          _owners.session.isBusy = false;
        });
        MainPageBridge.notifyAutoLaunchFailed(
          'No cached Premiumize streams available',
        );
        showSnack(
          'No cached Premiumize streams are playable. Try refreshing the channel.',
          color: Colors.orange,
        );
        return;
      }

      if (!mounted) return;
      closeProgressDialog();

      if (await handOffToExternalPlayer(
        first['url'] ?? '',
        first['title'] ?? 'Debrify TV',
      )) {
        return;
      }

      final launchedOnTv = await launchPikPakOnAndroidTv(
        firstStream: first,
        requestNext: requestPremiumizeNext,
        channelName: channelName,
        channelId: channelId,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
      );
      if (launchedOnTv) return;

      MainPageBridge.notifyPlayerLaunching();

      await Navigator.of(context).push(
        videoPlayerRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: first['url'] ?? '',
            title: first['title'] ?? 'Debrify TV',
            startFromRandom: _owners.settings.startRandom,
            randomStartMaxPercent: _owners.settings.randomStartPercent,
            hideSeekbar: _owners.settings.hideSeekbar,
            showChannelName: _owners.settings.showChannelName,
            channelName: channelName,
            channelNumber: channelNumber,
            showVideoTitle: _owners.settings.showVideoTitle,
            hideOptions: _owners.settings.hideOptions,
            requestMagicNext: requestPremiumizeNext,
            requestNextChannel:
                _owners.library.channels.length > 1 &&
                    (_owners.settings.provider ==
                            DebrifyTvConstants.providerRealDebrid ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerTorbox ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerPikPak ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerPremiumize)
                ? requestNextChannel
                : null,
            channelDirectory: channelDirectory,
            requestChannelById: _owners.library.channels.length > 1
                ? requestChannelById
                : null,
          ),
        ),
      );
      if (mounted) {
        setState(() {
          _owners.session.status = _owners.session.queue.isEmpty
              ? ''
              : 'Queue has ${_owners.session.queue.length} remaining';
        });
      }
    } on NativePlayerSettingsUnavailable catch (error) {
      showNativeSettingsFailure(error);
    } finally {
      closeProgressDialog();
      if (!mounted) return;
      setState(() => _owners.session.isBusy = false);
    }
  }

  Future<void> watchWithPremiumize(
    List<String> keywords,
    void Function(String message) log,
  ) async {
    final integrationEnabled =
        await PremiumizeStorage.getPremiumizeIntegrationEnabled();
    if (!integrationEnabled) {
      closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _owners.session.status =
            'Enable Premiumize in Settings to use this provider.';
        _owners.session.isBusy = false;
      });
      showSnack(
        'Enable Premiumize in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await PremiumizeStorage.getPremiumizeApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _owners.session.status =
            'Add your Premiumize API key in Settings to use this provider.';
        _owners.session.isBusy = false;
      });
      showSnack(
        'Please add your Premiumize API key in Settings first!',
        color: Colors.red,
      );
      return;
    }

    log('🌐 Premiumize: searching for cached torrents...');
    final Map<String, Torrent> dedup = {};
    final engineStates = await tvEngineSearchStates();
    final maxResultsOverrides = quickPlayMaxResultsOverrides();

    try {
      final futures = keywords
          .map(
            (kw) => TorrentService.searchAllEngines(
              kw,
              engineStates: engineStates,
              maxResultsOverrides: maxResultsOverrides,
            ),
          )
          .toList();

      await for (final result in Stream.fromFutures(futures)) {
        final torrents =
            (result['torrents'] as List<Torrent>? ?? const <Torrent>[]);

        List<Torrent> torrentsToProcess = torrents;
        if (_owners.settings.quickAvoidNsfw ||
            _owners.settings.viewerForcesNsfw) {
          torrentsToProcess = torrents.where((t) {
            return !NsfwFilter.shouldFilter(t.category, t.name);
          }).toList();
        }

        for (final torrent in torrentsToProcess) {
          final normalizedHash = normalizeInfohash(torrent.infohash);
          if (normalizedHash.isEmpty) continue;
          dedup.putIfAbsent(normalizedHash, () => torrent);
        }

        if (dedup.isNotEmpty && mounted) {
          setState(
            () => _owners.session.status = 'Checking Premiumize cache...',
          );
        }
      }

      final combinedList = applyQualityFilterToTorrents(
        dedup.values.toList(),
        // Search is complete here — an empty match means this search really
        // has nothing at the requested quality, so degrade rather than fail.
        allowFallback: true,
      );
      if (combinedList.isEmpty) {
        closeProgressDialog();
        if (mounted) {
          setState(
            () => _owners.session.status =
                'No results found. Try different keywords.',
          );
          showSnack(
            'No results found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      combinedList.shuffle(Random());
      if (mounted)
        setState(() => _owners.session.status = 'Checking Premiumize cache...');

      int candidateCursor = 0;

      Future<bool> populateQueue() async {
        while (true) {
          if (candidateCursor >= combinedList.length) return false;
          final window = await fetchPremiumizeCacheWindow(
            candidates: combinedList,
            startIndex: candidateCursor,
            apiKey: apiKey,
          );
          candidateCursor = window.nextCursor;
          if (window.cachedTorrents.isEmpty) {
            if (window.exhausted) return false;
            continue;
          }
          _owners.session.queue
            ..clear()
            ..addAll(window.cachedTorrents);
          _owners.session.lastQueueSize = _owners.session.queue.length;
          _owners.session.lastSearchAt = DateTime.now();
          if (mounted) {
            setState(() {
              _owners.session.status = _owners.session.queue.isEmpty
                  ? ''
                  : 'Queue has ${_owners.session.queue.length} remaining';
            });
          }
          log(
            '✅ Found ${_owners.session.queue.length} cached Premiumize torrent(s)',
          );
          return true;
        }
      }

      bool seeded;
      try {
        seeded = await populateQueue();
      } catch (e) {
        log('❌ Premiumize cache check failed: $e');
        closeProgressDialog();
        if (mounted) {
          setState(
            () => _owners.session.status =
                'Premiumize cache check failed. Try again.',
          );
          showSnack('Premiumize cache check failed: $e', color: Colors.red);
        }
        return;
      }

      if (!seeded) {
        closeProgressDialog();
        if (mounted) {
          setState(
            () => _owners.session.status =
                'Premiumize has no cached results for these keywords.',
          );
          showSnack(
            'Premiumize has no cached results for these keywords.',
            color: Colors.orange,
          );
        }
        return;
      }

      Future<Map<String, String>?> requestPremiumizeNext() async {
        if (_owners.session.watchCancelled) return null;
        while (!_owners.session.watchCancelled) {
          if (_owners.session.queue.isEmpty) {
            bool replenished;
            try {
              replenished = await populateQueue();
            } catch (e) {
              log('❌ Premiumize cache check failed: $e');
              closeProgressDialog();
              if (mounted && !_owners.session.watchCancelled) {
                setState(
                  () => _owners.session.status =
                      'Premiumize cache check failed. Try again.',
                );
                showSnack(
                  'Premiumize cache check failed: $e',
                  color: Colors.red,
                );
              }
              return null;
            }
            if (!replenished) break;
          }
          if (_owners.session.queue.isEmpty) break;

          final item = _owners.session.queue.removeAt(0);
          if (_owners.session.watchCancelled) break;
          if (item is! Torrent) continue;

          final result = await preparePremiumizeTorrent(
            candidate: item,
            apiKey: apiKey,
            log: log,
          );
          if (_owners.session.watchCancelled) return null;
          if (result != null) {
            if (result.hasMore && !_owners.session.watchCancelled)
              combinedList.add(item);
            if (mounted && !_owners.session.watchCancelled) {
              setState(() {
                _owners.session.status = _owners.session.queue.isEmpty
                    ? ''
                    : 'Queue has ${_owners.session.queue.length} remaining';
              });
            }
            if (_owners.session.watchCancelled) return null;
            return {'url': result.streamUrl, 'title': result.title};
          }
        }
        if (mounted && !_owners.session.watchCancelled) {
          setState(
            () => _owners.session.status = 'No more cached Premiumize streams.',
          );
        }
        return null;
      }

      final first = await requestPremiumizeNext();
      if (_owners.session.watchCancelled) return;
      if (first == null) {
        closeProgressDialog();
        if (mounted && !_owners.session.watchCancelled) {
          setState(() {
            _owners.session.status =
                'No playable Premiumize streams found. Try different keywords.';
          });
          showSnack(
            'No playable Premiumize streams found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      closeProgressDialog();
      if (!mounted) return;

      if (await handOffToExternalPlayer(
        first['url'] ?? '',
        first['title'] ?? 'Debrify TV',
      )) {
        return;
      }

      final launchedOnTv = await launchPikPakOnAndroidTv(
        firstStream: first,
        requestNext: requestPremiumizeNext,
        showChannelNameOverride: _owners.settings.quickShowChannelName,
        channelName: null,
        channelId: null,
        channelNumber: null,
        channelDirectory: null,
      );
      if (_owners.session.watchCancelled) return;
      if (launchedOnTv) return;

      if (!_owners.session.watchCancelled) {
        MainPageBridge.notifyPlayerLaunching();
        await Navigator.of(context).push(
          videoPlayerRoute(
            builder: (_) => VideoPlayerScreen(
              videoUrl: first['url'] ?? '',
              title: first['title'] ?? 'Debrify TV',
              startFromRandom: _owners.settings.startRandom,
              randomStartMaxPercent: _owners.settings.randomStartPercent,
              hideSeekbar: _owners.settings.hideSeekbar,
              showChannelName: _owners.settings.showChannelName,
              channelName: null,
              channelNumber: null,
              showVideoTitle: _owners.settings.showVideoTitle,
              hideOptions: _owners.settings.hideOptions,
              requestMagicNext: requestPremiumizeNext,
              requestNextChannel:
                  _owners.library.channels.length > 1 &&
                      (_owners.settings.quickProvider ==
                              DebrifyTvConstants.providerRealDebrid ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerTorbox ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerPikPak ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerPremiumize)
                  ? requestNextChannel
                  : null,
            ),
          ),
        );
      }

      if (mounted && !_owners.session.watchCancelled) {
        setState(() {
          _owners.session.status = _owners.session.queue.isEmpty
              ? ''
              : 'Queue has ${_owners.session.queue.length} remaining';
        });
      }
    } on NativePlayerSettingsUnavailable catch (error) {
      showNativeSettingsFailure(error);
    } finally {
      closeProgressDialog();
      if (mounted) setState(() => _owners.session.isBusy = false);
    }
  }

  /// AllDebrid Quick Play. Self-contained like [_watchWithPremiumize] for the
  /// search phase, but follows Real-Debrid's resolve model (sequential
  /// add-and-probe + background prefetcher) since AllDebrid has no cache-check
  /// API. Each candidate is added trusting the `ready` flag (no polling) and
  /// links are unlocked lazily on demand.
  Future<void> watchWithAllDebrid(
    List<String> keywords,
    void Function(String message) log,
  ) async {
    final integrationEnabled =
        await AllDebridStorage.getAllDebridIntegrationEnabled();
    if (!integrationEnabled) {
      closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _owners.session.status =
            'Enable AllDebrid in Settings to use this provider.';
        _owners.session.isBusy = false;
      });
      showSnack(
        'Enable AllDebrid in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await AllDebridStorage.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _owners.session.status =
            'Add your AllDebrid API key in Settings to use this provider.';
        _owners.session.isBusy = false;
      });
      showSnack(
        'Please add your AllDebrid API key in Settings first!',
        color: Colors.red,
      );
      return;
    }

    log('🌐 AllDebrid: searching for torrents...');
    final Map<String, Torrent> dedup = {};
    final engineStates = await tvEngineSearchStates();
    final maxResultsOverrides = quickPlayMaxResultsOverrides();

    try {
      final futures = keywords
          .map(
            (kw) => TorrentService.searchAllEngines(
              kw,
              engineStates: engineStates,
              maxResultsOverrides: maxResultsOverrides,
            ),
          )
          .toList();

      await for (final result in Stream.fromFutures(futures)) {
        if (_owners.session.watchCancelled) return;
        final torrents =
            (result['torrents'] as List<Torrent>? ?? const <Torrent>[]);

        List<Torrent> torrentsToProcess = torrents;
        if (_owners.settings.quickAvoidNsfw ||
            _owners.settings.viewerForcesNsfw) {
          torrentsToProcess = torrents.where((t) {
            return !NsfwFilter.shouldFilter(t.category, t.name);
          }).toList();
        }

        for (final torrent in torrentsToProcess) {
          final normalizedHash = normalizeInfohash(torrent.infohash);
          if (normalizedHash.isEmpty) continue;
          dedup.putIfAbsent(normalizedHash, () => torrent);
        }

        if (dedup.isNotEmpty && mounted) {
          setState(
            () => _owners.session.status = 'Finding a playable stream...',
          );
        }
      }

      final combinedList = applyQualityFilterToTorrents(
        dedup.values.toList(),
        // Search is complete here — an empty match means this search really
        // has nothing at the requested quality, so degrade rather than fail.
        allowFallback: true,
      );
      if (combinedList.isEmpty) {
        closeProgressDialog();
        if (mounted) {
          setState(
            () => _owners.session.status =
                'No results found. Try different keywords.',
          );
          showSnack(
            'No results found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      combinedList.shuffle(Random());

      // Seed the queue with raw torrents — sequential add-and-probe, no cache
      // check (mirrors Real-Debrid). The prefetcher prepares the rest.
      _owners.session.queue
        ..clear()
        ..addAll(combinedList);
      _owners.session.lastQueueSize = _owners.session.queue.length;
      _owners.session.lastSearchAt = DateTime.now();
      _owners.session.seenRestrictedLinks.clear();
      _owners.session.seenLinkWithTorrentId.clear();

      String _inferTitleFromUrl(String url) {
        final uri = Uri.tryParse(url);
        final last = (uri != null && uri.pathSegments.isNotEmpty)
            ? uri.pathSegments.last
            : url;
        return Uri.decodeComponent(last);
      }

      String firstTitle = 'Debrify TV';

      Future<Map<String, String>?> requestMagicNext() async {
        if (_owners.session.watchCancelled) return null;
        debugPrint(
          'MagicTV/AD: requestMagicNext() queueSize=${_owners.session.queue.length}',
        );
        while (_owners.session.queue.isNotEmpty &&
            !_owners.session.watchCancelled) {
          final item = _owners.session.queue.removeAt(0);
          if (item is Map && item['type'] == 'ad_locked') {
            final String link = item['allDebridLink'] as String? ?? '';
            if (link.isEmpty) continue;
            try {
              final videoUrl = await AllDebridService.unlockLink(apiKey, link);
              if (_owners.session.watchCancelled) return null;
              if (videoUrl.isNotEmpty) {
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final display = (item['displayName'] as String?)?.trim();
                final chosenTitle = inferred.isNotEmpty
                    ? inferred
                    : (display ?? 'Debrify TV');
                firstTitle = chosenTitle;
                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint('MagicTV/AD: unlock failed: $e');
              continue;
            }
          }

          if (item is Torrent) {
            final prepared = await resolveAllDebridLinks(item, apiKey);
            if (_owners.session.watchCancelled) return null;
            if (prepared == null || prepared.lockedLinks.isEmpty) {
              continue;
            }
            final links = List<String>.from(prepared.lockedLinks);
            final String headLink = links.removeAt(0);
            for (final link in links) {
              _owners.session.queue.add({
                'type': 'ad_locked',
                'allDebridLink': link,
                'magnetId': prepared.magnetId,
                'displayName': item.name,
              });
            }
            try {
              final videoUrl = await AllDebridService.unlockLink(
                apiKey,
                headLink,
              );
              if (_owners.session.watchCancelled) return null;
              if (videoUrl.isNotEmpty) {
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final chosenTitle = inferred.isNotEmpty
                    ? inferred
                    : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
                firstTitle = chosenTitle;
                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint('MagicTV/AD: add/unlock failed: $e');
              continue;
            }
          }
        }
        debugPrint('MagicTV/AD: requestMagicNext() queue exhausted.');
        return null;
      }

      final first = await requestMagicNext();
      if (_owners.session.watchCancelled) return;
      if (first == null) {
        closeProgressDialog();
        if (mounted && !_owners.session.watchCancelled) {
          setState(() {
            _owners.session.status =
                'No playable AllDebrid streams found. Try different keywords.';
          });
          showSnack(
            'No playable AllDebrid streams found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      firstTitle = (first['title'] ?? firstTitle).trim().isNotEmpty
          ? (first['title'] ?? firstTitle)
          : firstTitle;

      closeProgressDialog();
      if (!mounted) return;

      _owners.prefetch.activeApiKey = apiKey;
      _owners.prefetch.activeProvider = DebrifyTvConstants.providerAllDebrid;
      unawaited(startPrefetch());

      if (await handOffToExternalPlayer(first['url'] ?? '', firstTitle)) {
        return;
      }

      final launchedOnTv = await launchRealDebridOnAndroidTv(
        firstStream: first,
        requestNext: requestMagicNext,
        showChannelNameOverride: _owners.settings.quickShowChannelName,
        channelId: null,
        channelNumber: null,
        channelDirectory: null,
      );
      if (_owners.session.watchCancelled) return;
      if (launchedOnTv) return;

      if (!_owners.session.watchCancelled) {
        MainPageBridge.notifyPlayerLaunching();
        await Navigator.of(context).push(
          videoPlayerRoute(
            builder: (_) => VideoPlayerScreen(
              videoUrl: first['url'] ?? '',
              title: firstTitle,
              startFromRandom: _owners.settings.quickStartRandom,
              randomStartMaxPercent: _owners.settings.quickRandomStartPercent,
              hideSeekbar: _owners.settings.quickHideSeekbar,
              showChannelName: _owners.settings.quickShowChannelName,
              channelName: null,
              channelNumber: null,
              showVideoTitle: _owners.settings.quickShowVideoTitle,
              hideOptions: _owners.settings.quickHideOptions,
              requestMagicNext: requestMagicNext,
              requestNextChannel:
                  _owners.library.channels.length > 1 &&
                      (_owners.settings.quickProvider ==
                              DebrifyTvConstants.providerRealDebrid ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerTorbox ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerPikPak ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerPremiumize ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerAllDebrid)
                  ? requestNextChannel
                  : null,
            ),
          ),
        );
        await stopPrefetch();
      }

      if (mounted && !_owners.session.watchCancelled) {
        setState(() {
          _owners.session.status = _owners.session.queue.isEmpty
              ? ''
              : 'Queue has ${_owners.session.queue.length} remaining';
        });
      }
    } on NativePlayerSettingsUnavailable catch (error) {
      showNativeSettingsFailure(error);
    } finally {
      closeProgressDialog();
      if (mounted) setState(() => _owners.session.isBusy = false);
    }
  }

  List<TorboxPlayableEntry> _buildTorboxPlayableEntries(
    TorboxTorrent torrent,
    String fallbackTitle, {
    bool applySizeFilter = true,
  }) {
    final entries = <TorboxPlayableEntry>[];
    final seriesCandidates = <TorboxPlayableEntry>[];
    final otherCandidates = <TorboxPlayableEntry>[];

    for (final file in torrent.files) {
      if (!_torboxFileLooksLikeVideo(file)) continue;
      if (file.size < DebrifyTvConstants.torboxMinVideoSizeBytes) continue;
      // Per-FILE size filter: a pack's files are individual episodes, so this
      // compares against the number the user actually meant.
      if (applySizeFilter &&
          !_owners.settings.tvFilters.sizeMatchesBytes(file.size))
        continue;

      final displayName = _torboxDisplayName(file);
      final info = SeriesParser.parseFilenameConservative(displayName);
      final title = info.isSeries
          ? formatTorboxSeriesTitle(info, fallbackTitle)
          : (displayName.isNotEmpty ? displayName : fallbackTitle);
      final entry = TorboxPlayableEntry(file: file, title: title, info: info);

      if (info.isSeries && info.season != null && info.episode != null) {
        seriesCandidates.add(entry);
      } else {
        otherCandidates.add(entry);
      }
    }

    // Sort series candidates by season and episode
    seriesCandidates.sort((a, b) {
      final seasonCompare = (a.info.season ?? 0).compareTo(b.info.season ?? 0);
      if (seasonCompare != 0) return seasonCompare;
      return (a.info.episode ?? 0).compareTo(b.info.episode ?? 0);
    });

    // Sort other candidates alphabetically
    otherCandidates.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );

    entries
      ..addAll(seriesCandidates)
      ..addAll(otherCandidates);
    entries.shuffle(Random());
    // Nothing in THIS torrent matched the size filter — take it unfiltered
    // rather than discarding the torrent, so a strict filter narrows what
    // plays instead of walking the whole queue and playing nothing.
    if (entries.isEmpty &&
        applySizeFilter &&
        _owners.settings.tvFilters.hasSize) {
      debugPrint(
        'DebrifyTV/Torbox: no file matched the size filter in '
        '"$fallbackTitle" — using it unfiltered.',
      );
      return _buildTorboxPlayableEntries(
        torrent,
        fallbackTitle,
        applySizeFilter: false,
      );
    }
    return entries;
  }

  String formatTorboxSeriesTitle(SeriesInfo info, String fallback) {
    final season = info.season?.toString().padLeft(2, '0');
    final episode = info.episode?.toString().padLeft(2, '0');
    final descriptor = info.episodeTitle?.trim().isNotEmpty == true
        ? info.episodeTitle!.trim()
        : (info.title?.trim().isNotEmpty == true
              ? info.title!.trim()
              : fallback);
    if (season != null && episode != null) {
      return 'S${season}E$episode · $descriptor';
    }
    return fallback;
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

  String normalizeInfohash(String hash) {
    return hash.trim().toLowerCase();
  }

  void showSnack(String message, {Color color = Colors.blueGrey}) {
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

  String formatTorboxError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  String formatImportError(Object error) {
    if (error is FormatException) {
      return error.message;
    }
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  // ===================== External player hand-off =====================

  /// Hands one resolved stream to the user's external player when that is
  /// their default, after warning them what external playback costs here.
  ///
  /// Returns true when the caller must abandon its own launch — either the
  /// stream is now playing in another app, or the user backed out of the
  /// warning. False means "carry on unchanged": the in-app player is the
  /// default, or the external launch failed and the built-in player is the
  /// fallback (same policy as [VideoPlayerLauncher.push]).
  ///
  /// Channel rotation dies with the hand-off — nothing outside Debrify can
  /// call back into `requestMagicNext` — so on any outcome that ends the flow
  /// this also stops the prefetcher that exists purely to feed it. A failed
  /// launch leaves the prefetcher running, because the in-app player that
  /// picks the flow back up still wants it.
  Future<bool> handOffToExternalPlayer(String url, String title) async {
    if (url.isEmpty || !mounted) return false;
    if (!await VideoPlayerLauncher.isExternalPlayerDefault()) return false;
    if (!mounted) return false;

    closeProgressDialog();
    // The home-screen auto-launch overlay draws above routes, so drop it
    // before the notice or the notice appears underneath it. Only the overlay
    // — firing notifyPlayerLaunching here would stop other screens' trailers
    // for a launch the user may still decline.
    MainPageBridge.hideAutoLaunchOverlay?.call();
    if (!mounted) return false;

    // Backing out must not silently fall through to the in-app player — that
    // is the very thing the user chose against — so a decline reports
    // "handled" too and every caller stops. Deliberately without touching
    // _watchCancelled: that flag is only reset by the quick-play and cached-
    // dialog entry points, so setting it here would leave channel plays
    // stuck-cancelled on the next attempt.
    if (!await ExternalPlayerNoticeDialog.confirm(context)) {
      await stopPrefetch();
      return true;
    }
    if (!mounted) return true;

    final launched = await VideoPlayerLauncher.launchExternalIfConfigured(
      context,
      videoUrl: url,
      title: title.trim().isEmpty ? 'Debrify TV' : title.trim(),
    );
    if (launched) {
      _owners.session.launchedPlayer = true;
      await stopPrefetch();
      return true;
    }
    return false;
  }

  // ===================== Prefetcher =====================

  Future<void> startPrefetch() async {
    if (_owners.prefetch.prefetchRunning ||
        _owners.prefetch.activeApiKey == null ||
        _owners.prefetch.activeApiKey!.isEmpty) {
      return;
    }

    final startEpoch = _owners.prefetch.prefetchEpoch;
    final enabled = await _owners.settings.settingsManager
        .getGlobalBackgroundPrefetchEnabled();

    // Re-check mutable state after the preference read. Multiple playback
    // paths can request a start at nearly the same time, and playback may
    // have stopped while this method was awaiting SharedPreferences.
    if (!mounted ||
        startEpoch != _owners.prefetch.prefetchEpoch ||
        _owners.prefetch.prefetchRunning ||
        _owners.prefetch.activeApiKey == null ||
        _owners.prefetch.activeApiKey!.isEmpty) {
      return;
    }
    if (!enabled) {
      debugPrint('MagicTV: Background torrent prefetch is disabled.');
      return;
    }

    _owners.prefetch.prefetchRunning = true;
    _owners.prefetch.prefetchStopRequested = false;
    debugPrint('MagicTV: Prefetch started.');
    _owners.prefetch.prefetchTask = _runPrefetchLoop();
  }

  Future<void> stopPrefetch() async {
    _owners.prefetch.prefetchEpoch++;
    if (!_owners.prefetch.prefetchRunning) return;
    _owners.prefetch.prefetchStopRequested = true;
    try {
      await _owners.prefetch.prefetchTask;
    } catch (_) {}
    _owners.prefetch.prefetchRunning = false;
    _owners.prefetch.prefetchTask = null;
    _owners.prefetch.inflightInfohashes.clear();
    debugPrint('MagicTV: Prefetch stopped.');
  }

  Future<void> _runPrefetchLoop() async {
    while (mounted && !_owners.prefetch.prefetchStopRequested) {
      try {
        final prepared = _countPreparedInLookahead();
        if (prepared >= DebrifyTvConstants.minPrepared) {
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
    final end =
        _owners.session.queue.length < DebrifyTvConstants.lookaheadWindow
        ? _owners.session.queue.length
        : DebrifyTvConstants.lookaheadWindow;
    int count = 0;
    for (int i = 0; i < end; i++) {
      final item = _owners.session.queue[i];
      if (item is Map &&
          (item['type'] == 'rd_restricted' || item['type'] == 'ad_locked')) {
        count++;
      }
    }
    return count;
  }

  int _findUnpreparedTorrentIndexInLookahead() {
    final end =
        _owners.session.queue.length < DebrifyTvConstants.lookaheadWindow
        ? _owners.session.queue.length
        : DebrifyTvConstants.lookaheadWindow;
    for (int i = 0; i < end; i++) {
      final item = _owners.session.queue[i];
      if (item is Torrent &&
          !_owners.prefetch.inflightInfohashes.contains(item.infohash)) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _prefetchOneAtIndex(int idx) async {
    if (_owners.prefetch.activeApiKey == null ||
        _owners.prefetch.activeApiKey!.isEmpty)
      return;
    if (idx < 0 || idx >= _owners.session.queue.length) return;
    final item = _owners.session.queue[idx];
    if (item is! Torrent) return;
    if (_owners.prefetch.activeProvider ==
        DebrifyTvConstants.providerAllDebrid) {
      await _prefetchOneAllDebrid(idx, item);
      return;
    }
    final infohash = item.infohash;
    _owners.prefetch.inflightInfohashes.add(infohash);
    debugPrint('MagicTV: Prefetching torrent at idx=$idx name="${item.name}"');
    try {
      final magnetLink = 'magnet:?xt=urn:btih:$infohash';
      final result = await DebridService.addTorrentToDebridPreferVideos(
        _owners.prefetch.activeApiKey!,
        magnetLink,
      );
      final String torrentId = result['torrentId'] as String? ?? '';
      final List<dynamic> rdLinks =
          (result['links'] as List<dynamic>? ?? const []);

      if (rdLinks.isEmpty) {
        // Nothing ready; move to tail to retry later
        if (idx < _owners.session.queue.length &&
            identical(_owners.session.queue[idx], item)) {
          _owners.session.queue.removeAt(idx);
          _owners.session.queue.add(item);
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
            (link) =>
                link.isNotEmpty &&
                !_owners.session.seenRestrictedLinks.contains(link),
          )
          .toList();
      if (headLinkCandidates.isEmpty) {
        if (idx < _owners.session.queue.length &&
            identical(_owners.session.queue[idx], item)) {
          _owners.session.queue.removeAt(idx);
          _owners.session.queue.add(item);
        }
        return;
      }

      headLinkCandidates.shuffle(Random());
      final headLink = headLinkCandidates.removeAt(0);
      _owners.session.seenRestrictedLinks.add(headLink);
      _owners.session.seenLinkWithTorrentId.add('$torrentId|$headLink');

      if (idx < _owners.session.queue.length &&
          identical(_owners.session.queue[idx], item)) {
        _owners.session.queue[idx] = {
          'type': 'rd_restricted',
          'restrictedLink': headLink,
          'torrentId': torrentId,
          'displayName': item.name,
        };
      }

      if (headLinkCandidates.isNotEmpty) {
        _owners.session.queue.add(item);
      }
    } catch (e) {
      // On failure, move to tail for retry later
      if (idx < _owners.session.queue.length &&
          identical(_owners.session.queue[idx], item)) {
        _owners.session.queue.removeAt(idx);
        _owners.session.queue.add(item);
      }
      debugPrint('MagicTV: Prefetch failed for $infohash: $e (moved to tail)');
    } finally {
      _owners.prefetch.inflightInfohashes.remove(infohash);
    }
  }

  /// Adds [candidate] to AllDebrid (trusting the upload `ready` flag — no
  /// polling) and returns its fresh (unseen) locked video-file links, marking
  /// them seen. Returns null when the torrent is not cached/ready (the magnet
  /// is deleted in that case) or has no usable video files. Each returned link
  /// is still locked and must be unlocked via [AllDebridService.unlockLink]
  /// before playback — the lazy model mirrors Real-Debrid's restricted links.
  Future<DebrifyTvAllDebridPrepared?> resolveAllDebridLinks(
    Torrent candidate,
    String apiKey,
  ) async {
    final magnetLink = 'magnet:?xt=urn:btih:${candidate.infohash}';
    AllDebridAddResult result;
    try {
      result = await AllDebridService.addMagnetAndResolveFiles(
        apiKey,
        magnetLink,
      );
    } on AllDebridTorrentNotReadyException catch (e) {
      // Not cached/ready — don't leave it downloading on the account.
      await AllDebridService.deleteMagnet(e.apiKey, e.magnetId);
      return null;
    }
    // AllDebrid returns a real per-file byte count, so the per-FILE size rules
    // apply before the files are reduced to bare links (after that reduction
    // the size is gone). The 50MB floor keeps trailers/samples out, matching
    // Torbox and Premiumize.
    List<String> collectLinks({required bool applySizeFilter}) {
      return result.files
          .where((f) {
            if (!FileUtils.isVideoFile(f.fileName)) return false;
            if (f.size > 0 &&
                f.size < DebrifyTvConstants.torboxMinVideoSizeBytes)
              return false;
            if (applySizeFilter &&
                !_owners.settings.tvFilters.sizeMatchesBytes(f.size)) {
              return false;
            }
            return true;
          })
          .map((f) => f.link)
          .where(
            (link) =>
                link.isNotEmpty &&
                !_owners.session.seenRestrictedLinks.contains(link),
          )
          .toList();
    }

    var freshLinks = collectLinks(applySizeFilter: true);
    if (freshLinks.isEmpty && _owners.settings.tvFilters.hasSize) {
      // Nothing matched in this torrent — take it unfiltered rather than
      // discarding the torrent (see the Torbox builder).
      debugPrint(
        'DebrifyTV/AD: no file matched the size filter in "${result.name}" — '
        'using it unfiltered.',
      );
      freshLinks = collectLinks(applySizeFilter: false);
    }
    if (freshLinks.isEmpty) return null;
    for (final link in freshLinks) {
      _owners.session.seenRestrictedLinks.add(link);
    }
    return DebrifyTvAllDebridPrepared(
      magnetId: result.magnetId,
      name: result.name,
      lockedLinks: freshLinks,
    );
  }

  /// AllDebrid analog of the Real-Debrid prefetch path. Converts the [item]
  /// queue slot into a prepared `ad_locked` entry (a still-locked link), and
  /// since AllDebrid returns every file at once, enqueues the remaining video
  /// files immediately rather than re-adding the torrent.
  Future<void> _prefetchOneAllDebrid(int idx, Torrent item) async {
    final infohash = item.infohash;
    _owners.prefetch.inflightInfohashes.add(infohash);
    debugPrint(
      'MagicTV: Prefetching AllDebrid torrent at idx=$idx name="${item.name}"',
    );
    try {
      final prepared = await resolveAllDebridLinks(
        item,
        _owners.prefetch.activeApiKey!,
      );
      if (prepared == null || prepared.lockedLinks.isEmpty) {
        // Not ready / no usable video; move to tail to retry later.
        if (idx < _owners.session.queue.length &&
            identical(_owners.session.queue[idx], item)) {
          _owners.session.queue.removeAt(idx);
          _owners.session.queue.add(item);
        }
        debugPrint(
          'MagicTV: AllDebrid prefetch: not ready/no links; moved to tail idx=$idx',
        );
        return;
      }

      final links = List<String>.from(prepared.lockedLinks);
      final headLink = links.removeAt(0);
      Map<String, dynamic> lockedEntry(String link) => {
        'type': 'ad_locked',
        'allDebridLink': link,
        'magnetId': prepared.magnetId,
        'displayName': item.name,
      };

      if (idx < _owners.session.queue.length &&
          identical(_owners.session.queue[idx], item)) {
        _owners.session.queue[idx] = lockedEntry(headLink);
      } else {
        // Slot shifted out from under us; don't lose the resolved head link.
        _owners.session.queue.add(lockedEntry(headLink));
      }
      for (final link in links) {
        _owners.session.queue.add(lockedEntry(link));
      }
    } catch (e) {
      if (idx < _owners.session.queue.length &&
          identical(_owners.session.queue[idx], item)) {
        _owners.session.queue.removeAt(idx);
        _owners.session.queue.add(item);
      }
      debugPrint(
        'MagicTV: AllDebrid prefetch failed for $infohash: $e (moved to tail)',
      );
    } finally {
      _owners.prefetch.inflightInfohashes.remove(infohash);
    }
  }
}

import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/android_tv_player_bridge.dart';
import '../services/main_page_bridge.dart';
import 'debrify_tv/layouts/spotlight_layout.dart';

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
    ),
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('magic_tv');
    _owners.focus.channelSearchFocusNode = FocusNode(
      debugLabel: 'DebrifyTVChannelSearch',
    );
    _sections.settings.loadSettings();
    _sections.library
        .loadChannels(); // also warms the Spotlight rail health, once per reload
    _sections.library.loadFavoriteChannels();

    // Register watch channel handler for external calls (e.g., from home screen)
    MainPageBridge.watchDebrifyTvChannel = _sections.library.watchChannelById;
    MainPageBridge.registerDebrifyTvLibraryListener(
      _sections.library.handleSyncedDebrifyTvLibraryChanged,
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
      _sections.library.checkPendingAutoPlay();
    });
  }

  @override
  void dispose() {
    _owners.stage.spotlightStatsDebounce?.cancel();
    // Clear watch channel handler
    MainPageBridge.watchDebrifyTvChannel = null;
    MainPageBridge.unregisterDebrifyTvLibraryListener(
      _sections.library.handleSyncedDebrifyTvLibraryChanged,
    );
    if (_owners.focus.tvContentFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(
        3,
        _owners.focus.tvContentFocusHandler!,
      );
    }
    // Ensure prefetch loop is stopped if this screen is disposed mid-run
    _owners.prefetch.prefetchStopRequested = true;
    _sections.prefetch.stopPrefetch();
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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (_owners.library.debrifyTvStyle == 'spotlight') {
      return SpotlightLayout(
        view: _sections.stage.buildSpotlightView(),
        bottomInset: bottomInset,
        entryFocusNode: _owners.focus.quickPlayFocusNode,
      );
    }
    // The historical layout, byte-identical under `grid` — the branch calls
    // it unchanged, never a re-implementation.
    return _sections.grid.buildTvGridLayout(bottomInset);
  }
}

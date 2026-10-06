import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:flutter/material.dart';

/// Main Stremio TV screen — a TV guide powered by Stremio addon catalogs.
///
/// Each addon catalog becomes a "channel" with a deterministic "now playing"
/// item that rotates on a configurable schedule.
class StremioTvScreen extends StatefulWidget {
  /// The resolved native Android-TV flag, threaded down from the app shell
  /// (see main.dart `_buildPage`). Prefer this over a width heuristic: on a TV
  /// the logical canvas sits right at the old `width >= 900` threshold, so
  /// screens that guessed from width flipped to the non-navigable phone layout.
  final bool isTelevision;

  const StremioTvScreen({super.key, this.isTelevision = false});

  @override
  State<StremioTvScreen> createState() => _StremioTvScreenState();
}

class _StremioTvScreenState extends State<StremioTvScreen> {
  final StremioTvOwners _owners = StremioTvOwners();
  StremioTvSections? _composition;
  StremioTvSections get _sections => _composition ??= StremioTvSections(
    StremioTvDependencies(
      owners: _owners,
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      isTelevision: () => widget.isTelevision,
    ),
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('stremio_tv');
    _sections.settings.loadSettings().then(
      (_) => _sections.library.discoverAndLoad(),
    );
    MdblistService.instance.isAuthenticated().then((v) {
      if (mounted && v != _owners.settings.mdblistConnected) {
        setState(() => _owners.settings.mdblistConnected = v);
      }
    });

    // Search DPAD exits live on the TvTextField (onUp/Down/Left/RightArrow).
    _owners.focus.searchController.addListener(() {
      final q = _owners.focus.searchController.text.toLowerCase().trim();
      if (q != _owners.focus.searchQuery) {
        setState(() => _owners.focus.searchQuery = q);
      }
    });

    // Register TV sidebar focus handler (tab index 9 = Stremio TV)
    _owners.focus.tvContentFocusHandler = () {
      _owners.focus.searchBtnFocusNode.requestFocus();
    };
    MainPageBridge.registerTvContentFocusHandler(
      9,
      _owners.focus.tvContentFocusHandler!,
    );

    // Register the auto-play bridge
    MainPageBridge.watchStremioTvChannel = (channelId) async {
      if (mounted) {
        _sections.actions.playChannelById(channelId);
      }
    };

    // Check for pending auto-play
    final pending = MainPageBridge.getAndClearStremioTvChannelToAutoPlay();
    if (pending != null) {
      _owners.playback.pendingChannelId = pending;
    }

    // No periodic screen-level refresh: the tuner runs its own 15s tick
    // (gated on the Auto-refresh setting, passed below) for progress bars
    // and slot rollovers, so a 30s whole-screen setState here was pure
    // rebuild churn on top of it.
  }

  @override
  void dispose() {
    _owners.library.contentRevision.dispose();
    _owners.focus.searchBtnFocusNode.dispose();
    _owners.focus.providerFocusNode.dispose();
    _owners.focus.menuFocusNode.dispose();
    _owners.focus.submenuFocusNode.dispose();
    _owners.focus.searchController.dispose();
    _owners.focus.searchFocusNode.dispose();
    for (final node in _owners.focus.rowFocusNodes) {
      node.dispose();
    }
    // Only clear if we're the active handler
    if (MainPageBridge.watchStremioTvChannel != null) {
      MainPageBridge.watchStremioTvChannel = null;
    }
    if (_owners.focus.tvContentFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(
        9,
        _owners.focus.tvContentFocusHandler!,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _sections.layout.build(context);
}

import 'package:flutter/material.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/android_native_downloader.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/engine/remote_engine_manager.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/stremio_marketplace_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/see_all/see_all_theme.dart';
import 'package:debrify/features/addon_hub/models/addon_hub_kinds.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_composition.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_list.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_market_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_sections.dart';

/// A single, Stremio-themed home for addons: one list with a source + type
/// filter, a search box, an "Add addon" URL flow, and a 1-click Discover
/// marketplace — styled with the same purple Discover kit (see_all_theme +
/// StremioDropdown) as the catalog browser.
class AddonHubScreen extends StatefulWidget {
  const AddonHubScreen({super.key});

  @override
  State<AddonHubScreen> createState() => _AddonHubScreenState();
}

class _AddonHubScreenState extends State<AddonHubScreen> {
  static const int _tabIndex = 7; // Addons slot in the main nav.
  final _installedOwner = AddonHubInstalledState();
  final _marketOwner = AddonHubMarketState();
  final h = AddonHubNavigationState();
  final _e = AddonHubEngineState();
  AddonHubEngineList get _el => _sections.engineList;
  AddonHubSections? _sectionCache;
  AddonHubSections get _sections => _sectionCache ??= createAddonHubSections(
    (
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      emptyState: _emptyState,
    ),
    (
      installedState: _installedOwner,
      marketState: _marketOwner,
      navigationState: h,
      engineState: _e,
    ),
  );

  VoidCallback? _tvFocusHandler;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('addon_hub');
    _installedOwner.stremio.addAddonsChangedListener(
      _sections.loading.onAddonsChanged,
    );
    LocalEngineStorage.changes.addListener(
      _sections.engineLoading.onEnginesChanged,
    );
    h.searchController.addListener(() {
      final q = h.searchController.text.trim();
      if (q != h.search) setState(() => h.search = q);
    });

    _tvFocusHandler = () => h.kindFocus.requestFocus();
    MainPageBridge.registerTvContentFocusHandler(_tabIndex, _tvFocusHandler!);

    AndroidNativeDownloader.isTelevision().then((tv) {
      if (mounted) setState(() => h.isTv = tv);
    });

    _sections.loading.loadDebridState();
    _sections.loading.loadInstalled();
  }

  @override
  void dispose() {
    _installedOwner.stremio.removeAddonsChangedListener(
      _sections.loading.onAddonsChanged,
    );
    LocalEngineStorage.changes.removeListener(
      _sections.engineLoading.onEnginesChanged,
    );
    if (_tvFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(
        _tabIndex,
        _tvFocusHandler!,
      );
    }
    h.searchController.dispose();
    h.kindFocus.dispose();
    h.sourceFocus.dispose();
    h.typeFocus.dispose();
    h.addFocus.dispose();
    h.moreFocus.dispose();
    h.searchFocus.dispose();
    h.searchBtnFocus.dispose();
    h.metadataFocus.dispose();
    h.firstRowFocus.dispose();
    h.marketNav.dispose();
    _e.remoteEngines.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Scaffold(
      backgroundColor: app.seeAll.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.75),
            radius: 1.35,
            colors: [
              Color(0xFF241E44),
              Color(0xFF161327),
              Color(0xFF0F0D1D),
              kSeeAllBg,
            ],
            stops: [0.0, 0.38, 0.68, 1.0],
          ),
        ),
        child: SafeArea(
          // Own scope: directional focus search never leaves the hub (the TV
          // sidebar is reached only via _onPageKey's explicit LEFT exit, and it
          // can still focus back INTO the hub via requestFocus).
          child: FocusScope(
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _sections.navigation.onPageKey,
              child: FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    _sections.filterBar.buildFilterBar(),
                    Expanded(child: _buildBody()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 14, 24, 8),
      child: Text(
        'Addons',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (h.kind == AddonHubKind.engines) return _el.buildEngineList();
    switch (h.source) {
      case AddonHubSource.installed:
        return _sections.installedList.buildInstalledList();
      case AddonHubSource.official:
      case AddonHubSource.community:
        return _sections.marketList.buildMarketList();
    }
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Colors.white.withValues(alpha: 0.25)),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
            if (action != null) ...[const SizedBox(height: 18), action],
          ],
        ),
      ),
    );
  }
}

@visibleForTesting
Map<String, Object?> addonHubTestAccess(State state) {
  final s = state as _AddonHubScreenState;
  return {
    'searchController': s.h.searchController,
    'kindFocus': s.h.kindFocus,
    'sourceFocus': s.h.sourceFocus,
    'typeFocus': s.h.typeFocus,
    'addFocus': s.h.addFocus,
    'moreFocus': s.h.moreFocus,
    'searchFocus': s.h.searchFocus,
    'searchBtnFocus': s.h.searchBtnFocus,
    'metadataFocus': s.h.metadataFocus,
    'firstRowFocus': s.h.firstRowFocus,
    'tvFocusHandler': s._tvFocusHandler,
    'isTv': s.h.isTv,
    'kind': s.h.kind,
    'source': s.h.source,
    'typeFilter': s.h.typeFilter,
    'search': s.h.search,
    'searchOpen': s.h.searchOpen,
    'installed': List<StremioAddon>.of(s._installedOwner.installed),
    'installedLoading': s._installedOwner.installedLoading,
    'metadataProviderPreference': s._installedOwner.metadataProviderPreference,
    'market': List<MarketplaceAddon>.of(s._marketOwner.market),
    'marketLoading': s._marketOwner.marketLoading,
    'marketError': s._marketOwner.marketError,
    'marketLoadedFor': s._marketOwner.marketLoadedFor,
    'hasDebrid': s._installedOwner.hasDebrid,
    'importedEngines': List<ImportedEngineMetadata>.of(s._e.importedEngines),
    'availableEngines': List<RemoteEngineInfo>.of(s._e.availableEngines),
    'knownRemoteEngines': List<RemoteEngineInfo>.of(s._e.knownRemoteEngines),
    'enginesLoading': s._e.enginesLoading,
    'enginesError': s._e.enginesError,
    'enginesLoadedOnce': s._e.enginesLoadedOnce,
    'installedLoadRevision': s._installedOwner.installedLoadRevision,
    'engineLoadRevision': s._e.engineLoadRevision,
    'blockingProgressUp': s._e.blockingProgressUp,
    'marketNodes': <FocusNode>[
      for (var i = 0; s.h.marketNav.nodeAt(i) != null; i++)
        s.h.marketNav.nodeAt(i)!,
    ],
    'marketIdenticalTo': (Object list) =>
        identical(s._marketOwner.market, list),
    'onAddonsChanged': s._sections.loading.onAddonsChanged,
    'onEnginesChanged': s._sections.engineLoading.onEnginesChanged,
    'loadInstalled': s._sections.loading.loadInstalled,
    'loadMarket': s._sections.loading.loadMarket,
    'loadEngines': s._sections.engineLoading.loadEngines,
    'focusFirstRow': s._sections.navigation.focusFirstRow,
    'setMetadataProvider': s._sections.installedList.setMetadataProvider,
    'toggleAddon': s._sections.management.toggleAddon,
    'setTv': (bool tv) {
      s.h.isTv = tv;
      (s.context as Element).markNeedsBuild();
    },
  };
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/android_native_downloader.dart';
import 'package:debrify/services/engine/local_engine_storage.dart';
import 'package:debrify/services/engine/remote_engine_manager.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/stremio_marketplace_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/see_all/see_all_theme.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:debrify/features/addon_hub/models/addon_hub_kinds.dart';
import 'package:debrify/features/addon_hub/presentation/addon_hub_action_button.dart';
import 'package:debrify/features/addon_hub/presentation/addon_hub_addon_info.dart';
import 'package:debrify/features/addon_hub/presentation/addon_hub_focus_card.dart';
import 'package:debrify/features/addon_hub/presentation/addon_hub_installed_row.dart';
import 'package:debrify/features/addon_hub/presentation/addon_hub_row_nav.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_composition.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_engine_loading.dart';
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
  AddonHubEngineLoading get _l => _sections.engineLoading;
  AddonHubSections? _sectionCache;
  AddonHubSections get _sections => _sectionCache ??= createAddonHubSections(
    (context: () => context, mounted: () => mounted, setState: setState),
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
    LocalEngineStorage.changes.addListener(_l.onEnginesChanged);
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
    LocalEngineStorage.changes.removeListener(_l.onEnginesChanged);
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

  /// Move focus from the filter bar down to the first row of whatever list is
  /// showing (market rows use their own nav pool; installed/engines use the
  /// single first-card node).
  void _focusFirstRow() {
    final isMarket =
        h.kind == AddonHubKind.addons &&
        (h.source == AddonHubSource.official ||
            h.source == AddonHubSource.community);
    if (isMarket) {
      h.marketNav.focus(0);
    } else if (h.kind == AddonHubKind.addons &&
        h.source == AddonHubSource.installed &&
        h.metadataFocus.context != null) {
      h.metadataFocus.requestFocus();
    } else if (h.firstRowFocus.context != null) {
      h.firstRowFocus.requestFocus();
    }
  }

  void _toggleSearch() {
    setState(() => h.searchOpen = !h.searchOpen);
    if (h.searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) h.searchFocus.requestFocus();
      });
    } else {
      h.searchController.clear();
      // Hand focus back to the search button so the remote isn't stranded on a
      // widget that just left the tree.
      h.searchBtnFocus.requestFocus();
    }
  }

  void _selectKind(AddonHubKind kind) {
    if (kind == h.kind) return;
    setState(() => h.kind = kind);
    if (kind == AddonHubKind.engines && !_e.enginesLoadedOnce) _l.loadEngines();
  }

  void _selectSource(AddonHubSource source) {
    if (source == h.source) return;
    setState(() => h.source = source);
    if (source != AddonHubSource.installed &&
        _marketOwner.marketLoadedFor != source) {
      _sections.loading.loadMarket(source);
    }
  }

  bool _isInstalled(MarketplaceAddon m) {
    // Match by manifest id OR transport URL. Note: a configurable addon installed
    // via the Configure→paste flow has a different (configured) URL than its
    // marketplace [config] transportUrl, so it's recognised only by id — fine for
    // addons that keep their id after configuration (the common case).
    for (final a in _installedOwner.installed) {
      if (a.id == m.id || a.manifestUrl == m.transportUrl) return true;
    }
    return false;
  }

  bool _matchesFilters({required List<String> types, required String name}) {
    if (h.typeFilter.isNotEmpty && !types.contains(h.typeFilter)) return false;
    if (h.search.isNotEmpty &&
        !name.toLowerCase().contains(h.search.toLowerCase())) {
      return false;
    }
    return true;
  }

  // ── Build ────────────────────────────────────────────────────────────────
  /// Page-level DPAD policy. On TV the sidebar shares the screen's focus scope,
  /// so default geometric traversal can "escape" sideways/down into it (focusing
  /// a rail icon pops the sidebar open). The [FocusScope] in [build] contains all
  /// directional moves to this page; this handler then implements the ONE
  /// deliberate exit: a LEFT press that can't move anywhere inside the hub goes
  /// to the sidebar.
  KeyEventResult _onPageKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    // Let the search field keep left/right for caret movement.
    if (h.searchFocus.hasFocus) return KeyEventResult.ignored;
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    // Move within the hub ONLY when there's a focusable genuinely to the left
    // in the same horizontal band (e.g. Configure → Install). We can't lean on
    // focusInDirection's return value here: it's greedy and, from a card's
    // leftmost button (Install), jumps diagonally up to the filter bar and
    // reports moved=true — which would swallow the deliberate LEFT exit to the
    // sidebar. So gate on a real in-band left neighbour instead.
    if (_hasLeftNeighbour(primary)) {
      primary.focusInDirection(TraversalDirection.left);
      return KeyEventResult.handled;
    }
    if (MainPageBridge.focusTvSidebar != null) {
      MainPageBridge.focusTvSidebar!();
    }
    return KeyEventResult.handled;
  }

  /// True if any focusable in this scope sits to the LEFT of [primary] while
  /// vertically overlapping its row band — i.e. a real left move exists and
  /// LEFT should stay inside the hub rather than exit to the sidebar.
  bool _hasLeftNeighbour(FocusNode primary) {
    final rect = primary.rect;
    final scope = primary.enclosingScope;
    if (scope == null) return false;
    for (final n in scope.traversalDescendants) {
      if (n == primary) continue;
      final r = n.rect;
      final overlapsVertically = r.top < rect.bottom && r.bottom > rect.top;
      if (overlapsVertically && r.center.dx < rect.center.dx - 1) return true;
    }
    return false;
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
              onKeyEvent: _onPageKey,
              child: FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    _buildFilterBar(),
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

  Widget _buildFilterBar() {
    final isAddon = h.kind == AddonHubKind.addons;
    return LayoutBuilder(
      builder: (context, c) {
        // Phone-width: the labelled dropdowns + buttons wrap into four ragged
        // rows that eat half the screen. Compose a compact three-row bar
        // instead (labels dropped — the values are self-explanatory) and keep
        // the free-flowing Wrap for wide layouts.
        final narrow = c.maxWidth < 480;

        final manageDd = StremioDropdown<AddonHubKind>(
          // Stremio addons and torrent engines are separate features — the
          // first dropdown picks which one is being managed.
          label: narrow ? null : 'Manage',
          value: h.kind,
          focusNode: h.kindFocus,
          isTelevision: h.isTv,
          options: const [
            StremioDropdownOption(AddonHubKind.addons, 'Stremio Addons'),
            StremioDropdownOption(AddonHubKind.engines, 'Torrent Engines'),
          ],
          onSelected: _selectKind,
        );
        final sourceDd = StremioDropdown<AddonHubSource>(
          label: narrow ? null : 'Source',
          value: h.source,
          focusNode: h.sourceFocus,
          isTelevision: h.isTv,
          options: const [
            StremioDropdownOption(AddonHubSource.installed, 'Installed'),
            StremioDropdownOption(AddonHubSource.official, 'Official'),
            StremioDropdownOption(AddonHubSource.community, 'Community'),
          ],
          onSelected: _selectSource,
        );
        final typeDd = StremioDropdown<String>(
          label: narrow ? null : 'Type',
          value: h.typeFilter,
          focusNode: h.typeFocus,
          isTelevision: h.isTv,
          options: const [
            StremioDropdownOption('', 'All'),
            StremioDropdownOption('movie', 'Movies'),
            StremioDropdownOption('series', 'Series'),
            StremioDropdownOption('channel', 'Channels'),
            StremioDropdownOption('tv', 'TV'),
            StremioDropdownOption('anime', 'Anime'),
          ],
          onSelected: (v) => setState(() => h.typeFilter = v),
        );
        final searchBtn = AddonHubHubActionButton(
          focusNode: h.searchBtnFocus,
          icon: Icons.search_rounded,
          onTap: _toggleSearch,
        );
        final addBtn = AddonHubHubActionButton(
          focusNode: h.addFocus,
          icon: Icons.add_rounded,
          label: 'Add addon',
          primary: true,
          expand: narrow,
          onTap: _sections.installActions.addByUrl,
        );
        final moreBtn = AddonHubHubActionButton(
          focusNode: h.moreFocus,
          icon: Icons.more_horiz_rounded,
          onTap: _sections.menus.showActionsMenu,
        );
        final importBtn = AddonHubHubActionButton(
          icon: Icons.file_upload_outlined,
          label: 'Import YAML',
          primary: true,
          expand: narrow,
          onTap: _sections.engineActions.importEngineFromFile,
        );
        final refreshBtn = AddonHubHubActionButton(
          icon: Icons.refresh_rounded,
          onTap: _l.loadEngines,
        );

        final Widget controls;
        if (narrow) {
          controls = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Row 1: what's being managed + overflow / refresh.
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: manageDd,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (isAddon) moreBtn else refreshBtn,
                ],
              ),
              const SizedBox(height: 10),
              if (isAddon) ...[
                // Row 2: the filters + search toggle.
                Row(
                  children: [
                    sourceDd,
                    const SizedBox(width: 10),
                    typeDd,
                    const Spacer(),
                    searchBtn,
                  ],
                ),
                const SizedBox(height: 10),
                // Row 3: the primary action gets the full width.
                addBtn,
              ] else
                importBtn,
            ],
          );
        } else {
          controls = Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              manageDd,
              if (isAddon) ...[
                sourceDd,
                typeDd,
                searchBtn,
                addBtn,
                moreBtn,
              ] else ...[
                importBtn,
                refreshBtn,
              ],
            ],
          );
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
            narrow ? 16 : 24,
            6,
            narrow ? 16 : 24,
            12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // DOWN from any filter-bar control goes deterministically to the
              // search field (when open) or the first list row — geometric
              // traversal's direction-history would otherwise return to whatever
              // row the user last came from.
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                    return KeyEventResult.ignored;
                  }
                  if (event.logicalKey != LogicalKeyboardKey.arrowDown) {
                    return KeyEventResult.ignored;
                  }
                  if (h.searchOpen || h.search.isNotEmpty) {
                    h.searchFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                  _focusFirstRow();
                  return KeyEventResult.handled;
                },
                child: controls,
              ),
              if (isAddon && (h.searchOpen || h.search.isNotEmpty)) ...[
                const SizedBox(height: 10),
                _buildSearchField(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    // DPAD exits are routed by TvTextField itself: down to the first list row,
    // up to the search button.
    final app = AppThemeScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: app.seeAll.panel,
        borderRadius: app.shape.br(11),
        border: Border.all(color: app.seeAll.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 18,
            color: app.fade(app.core.tx, 0.5),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TvTextField(
              controller: h.searchController,
              focusNode: h.searchFocus,
              style: const TextStyle(fontSize: 13),
              cursorColor: app.seeAll.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search addons',
                hintStyle: TextStyle(color: app.fade(app.core.tx, 0.35)),
              ),
              onSubmitted: (_) => _focusFirstRow(),
              onDownArrow: _focusFirstRow,
              onUpArrow: () => h.searchBtnFocus.requestFocus(),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() {
              h.searchController.clear();
              h.searchOpen = false;
            }),
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: app.fade(app.core.tx, 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (h.kind == AddonHubKind.engines) return _buildEngineList();
    switch (h.source) {
      case AddonHubSource.installed:
        return _buildInstalledList();
      case AddonHubSource.official:
      case AddonHubSource.community:
        return _buildMarketList();
    }
  }

  Widget _buildInstalledList() {
    if (_installedOwner.installedLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kSeeAllAccent, strokeWidth: 2),
      );
    }
    final items = _installedOwner.installed
        .where((a) => _matchesFilters(types: a.types, name: a.displayName))
        .toList();
    return Column(
      children: [
        _buildMetadataProviderSetting(),
        Expanded(
          child: items.isEmpty
              ? _emptyState(
                  icon: Icons.extension_outlined,
                  title: _installedOwner.installed.isEmpty
                      ? 'No addons yet'
                      : 'No matches',
                  subtitle: _installedOwner.installed.isEmpty
                      ? 'Add a manifest URL, or install one from Discover.'
                      : 'Try a different type or search.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
                  // DPAD can only move to rows that are BUILT — pre-build far
                  // past the viewport so focus never hits an unbuilt-row wall.
                  scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (_, i) => AddonHubInstalledRow(
                    addon: items[i],
                    focusNode: i == 0 ? h.firstRowFocus : null,
                    warnDebrid:
                        !_installedOwner.hasDebrid &&
                        items[i].resources.contains('stream'),
                    onTap: () => _sections.menus.showOptions(items[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMetadataProviderSetting() {
    final app = AppThemeScope.of(context);
    final providers = _installedOwner.installed
        .where(
          (a) =>
              a.enabled && a.resources.contains('meta') && a.baseUrl.isNotEmpty,
        )
        .toList();
    providers.sort((a, b) {
      final aCinemeta = StremioService.isCinemetaAddon(a);
      final bCinemeta = StremioService.isCinemetaAddon(b);
      if (aCinemeta == bCinemeta) return 0;
      return aCinemeta ? -1 : 1;
    });

    final providerValues = providers
        .map(StremioService.metadataProviderValue)
        .toSet();
    String value;
    if (_installedOwner.metadataProviderPreference ==
        StremioService.automaticMetadataProvider) {
      value = StremioService.automaticMetadataProvider;
    } else if (_installedOwner.metadataProviderPreference != null &&
        providerValues.contains(_installedOwner.metadataProviderPreference)) {
      value = _installedOwner.metadataProviderPreference!;
    } else {
      final cinemeta = providers.where(StremioService.isCinemetaAddon);
      value = cinemeta.isNotEmpty
          ? StremioService.metadataProviderValue(cinemeta.first)
          : StremioService.automaticMetadataProvider;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 4, 24, 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: app.seeAll.panel,
        borderRadius: app.shape.br(13),
        border: Border.all(color: app.seeAll.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Row(
            children: [
              Icon(
                Icons.badge_outlined,
                size: 20,
                color: app.fade(app.seeAll.accent2, 0.9),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Metadata provider',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Used to enrich details from Trakt, Simkl and MDBList.',
                      style: TextStyle(
                        fontSize: 12,
                        color: app.fade(app.core.tx, 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final picker = StremioDropdown<String>(
            value: value,
            focusNode: h.metadataFocus,
            isTelevision: h.isTv,
            onUpArrowPressed: () => h.typeFocus.requestFocus(),
            onDownArrowPressed: () {
              if (h.firstRowFocus.context != null) {
                h.firstRowFocus.requestFocus();
              }
            },
            options: [
              for (final addon in providers)
                StremioDropdownOption(
                  StremioService.metadataProviderValue(addon),
                  StremioService.isCinemetaAddon(addon)
                      ? '${addon.displayName} · Recommended'
                      : addon.displayName,
                ),
              const StremioDropdownOption(
                StremioService.automaticMetadataProvider,
                'Automatic',
              ),
            ],
            onSelected: _sections.installedList.setMetadataProvider,
          );
          if (constraints.maxWidth < 500) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: picker),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 14),
              picker,
            ],
          );
        },
      ),
    );
  }

  Widget _buildMarketList() {
    // Compatibility note pinned above BOTH marketplaces (Official/Community):
    // the catalogs list every Stremio addon, but only these four capability
    // families do anything in Debrify.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
          child: _marketCompatNote(),
        ),
        Expanded(child: _buildMarketListBody()),
        // Attribution required by the stremio-addons.net API terms — shown only
        // on the Community list AND only when that source actually served the
        // data (not the legacy fallback, which would be a misattribution).
        if (h.source == AddonHubSource.community &&
            _marketOwner.marketplace.communityFromNet)
          _communityAttribution(),
      ],
    );
  }

  /// Visible credit link back to stremio-addons.net, required by their API's
  /// attribution terms when we display community-directory data.
  Widget _communityAttribution() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: GestureDetector(
        onTap: () async {
          final uri = Uri.parse('https://stremio-addons.net');
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {
            /* no browser — the label still credits the source */
          }
        },
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Community addons from '),
              TextSpan(
                text: 'stremio-addons.net',
                style: TextStyle(
                  color: kSeeAllAccent,
                  decoration: TextDecoration.underline,
                  decorationColor: kSeeAllAccent.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }

  /// Slim accent-tinted banner: which addon capabilities Debrify supports.
  Widget _marketCompatNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: kSeeAllAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kSeeAllAccent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: kSeeAllAccent.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Works with Debrify: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const TextSpan(
                    text:
                        'catalog, HTTP stream, torrent-scraping and '
                        'subtitle addons. Other types install but add '
                        'nothing here.',
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketListBody() {
    if (_marketOwner.marketLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kSeeAllAccent, strokeWidth: 2),
      );
    }
    if (_marketOwner.marketError != null) {
      return _emptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn\'t load addons',
        subtitle: _marketOwner.marketError!,
        action: AddonHubHubActionButton(
          icon: Icons.refresh_rounded,
          label: 'Retry',
          primary: true,
          onTap: () => _sections.loading.loadMarket(h.source, force: true),
        ),
      );
    }
    final items = _marketOwner.market
        .where((m) => _matchesFilters(types: m.types, name: m.name))
        .toList();
    if (items.isEmpty) {
      return _emptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        subtitle: 'Try a different type or search.',
      );
    }
    // Assign each FOCUSABLE row (installed rows have no button) a nav index so
    // vertical DPAD can hop row-to-row deterministically.
    final navIndexOf = <int, int>{};
    var focusable = 0;
    for (var i = 0; i < items.length; i++) {
      if (!_isInstalled(items[i])) navIndexOf[i] = focusable++;
    }
    h.marketNav.ensure(focusable);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      // See installed list — keep DPAD off the unbuilt wall.
      scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        final m = items[i];
        final navIndex = navIndexOf[i];
        return _MarketRow(
          addon: m,
          installed: _isInstalled(m),
          nav: h.marketNav,
          navIndex: navIndex,
          navCount: focusable,
          warnDebrid:
              !_installedOwner.hasDebrid && m.resources.contains('stream'),
          onInstall: () =>
              _sections.installActions.installFromMarket(m, navIndex),
          onConfigure: () => _sections.installActions.configureInBrowser(m),
        );
      },
    );
  }

  Widget _buildEngineList() {
    if (_e.enginesLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kSeeAllAccent, strokeWidth: 2),
      );
    }
    if (_e.enginesError != null) {
      return _emptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn\'t load engines',
        subtitle: _e.enginesError!,
        action: AddonHubHubActionButton(
          icon: Icons.refresh_rounded,
          label: 'Retry',
          primary: true,
          onTap: _l.loadEngines,
        ),
      );
    }
    if (_e.importedEngines.isEmpty && _e.availableEngines.isEmpty) {
      return _emptyState(
        icon: Icons.travel_explore_rounded,
        title: 'No engines available',
        subtitle: 'Import an engine YAML, or check back after a refresh.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
      children: [
        if (_e.importedEngines.isNotEmpty) ...[
          _engineSectionHeader('Imported', _e.importedEngines.length),
          for (var i = 0; i < _e.importedEngines.length; i++) ...[
            _EngineRow(
              icon: _iconForEngine(_e.importedEngines[i].icon),
              title: _e.importedEngines[i].displayName,
              subtitle:
                  'Imported ${_relativeDate(_e.importedEngines[i].importedAt)}',
              actionLabel: 'Remove',
              danger: true,
              focusNode: i == 0 ? h.firstRowFocus : null,
              onTap: () =>
                  _sections.engineActions.deleteEngine(_e.importedEngines[i]),
            ),
            const SizedBox(height: 14),
          ],
        ],
        if (_e.availableEngines.isNotEmpty) ...[
          _engineSectionHeader(
            'Available to install',
            _e.availableEngines.length,
          ),
          for (var i = 0; i < _e.availableEngines.length; i++) ...[
            _EngineRow(
              icon: _iconForEngine(_e.availableEngines[i].icon),
              title: _e.availableEngines[i].displayName,
              subtitle: _e.availableEngines[i].description,
              actionLabel: 'Install',
              primary: true,
              focusNode: (_e.importedEngines.isEmpty && i == 0)
                  ? h.firstRowFocus
                  : null,
              onTap: () =>
                  _sections.engineActions.installEngine(_e.availableEngines[i]),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ],
    );
  }

  Widget _engineSectionHeader(String label, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 0, 12),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: kSeeAllAccent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: kSeeAllAccent2,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForEngine(String? name) {
    switch (name) {
      case 'sailing':
        return Icons.sailing_rounded;
      case 'storage':
      case 'database':
        return Icons.storage_rounded;
      case 'movie':
      case 'movie_creation':
        return Icons.movie_rounded;
      case 'tv':
        return Icons.tv_rounded;
      case 'cloud':
        return Icons.cloud_rounded;
      case 'search':
        return Icons.search_rounded;
      case 'public':
        return Icons.public_rounded;
      default:
        return Icons.extension_rounded;
    }
  }

  String _relativeDate(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays >= 1) return '${diff.inDays}d ago';
    if (diff.inHours >= 1) return '${diff.inHours}h ago';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
    return 'just now';
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

class _MarketRow extends StatelessWidget {
  final MarketplaceAddon addon;
  final bool installed;
  final VoidCallback onInstall;
  final VoidCallback onConfigure;

  /// Row-to-row DPAD navigation. [navIndex] is this row's slot in [nav] (null
  /// for installed rows, which aren't focusable); [navCount] is the total.
  final AddonHubRowNav nav;
  final int? navIndex;
  final int navCount;
  final bool warnDebrid;

  const _MarketRow({
    required this.addon,
    required this.installed,
    required this.onInstall,
    required this.onConfigure,
    required this.nav,
    required this.navIndex,
    required this.navCount,
    this.warnDebrid = false,
  });

  /// DOWN → next row's first button (always handled, so it never escapes the
  /// list sideways). UP → previous row's first button, or fall through to the
  /// filter bar when already at the top.
  bool _onDown() {
    nav.focus((navIndex ?? 0) + 1);
    return true;
  }

  bool _onUp() {
    final i = navIndex ?? 0;
    if (i == 0) return false; // let default traversal reach the filter bar
    nav.focus(i - 1);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Same responsive split as the installed card: below the breakpoint,
        // logo + title share a header row, the info flows full-width, and the
        // Install/Configure buttons drop to their own row (where they get room
        // instead of squeezing the info column).
        final narrow = c.maxWidth < 480;
        final meta = AddonHubAddonMeta(
          types: addon.types,
          resources: addon.resources,
          description: addon.description,
          warnDebrid: warnDebrid,
        );
        return Container(
          decoration: addonHubCardDecoration(false),
          padding: EdgeInsets.symmetric(
            horizontal: narrow ? 16 : 22,
            vertical: narrow ? 16 : 20,
          ),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        addonHubLogo(addon.logo, size: 44),
                        const SizedBox(width: 14),
                        Expanded(
                          child: AddonHubAddonTitleLine(
                            name: addon.name,
                            version: addon.version,
                            stacked: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    meta,
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _buildActions(),
                    ),
                  ],
                )
              : Row(
                  children: [
                    addonHubLogo(addon.logo),
                    const SizedBox(width: 20),
                    Expanded(
                      child: AddonHubAddonInfo(
                        name: addon.name,
                        version: addon.version,
                        types: addon.types,
                        resources: addon.resources,
                        description: addon.description,
                        warnDebrid: warnDebrid,
                      ),
                    ),
                    const SizedBox(width: 16),
                    _buildActions(),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildActions() {
    if (installed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: kSeeAllAccent2.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 6),
          Text(
            'Installed',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    // configurationRequired: config is mandatory, so there's no plain Install.
    // configurable (optional): offer both Install and Configure.
    // The row's FIRST button carries this row's nav node so DOWN/UP land on it.
    final primaryNode = navIndex != null ? nav.nodeAt(navIndex!) : null;
    final buttons = <Widget>[];
    if (!addon.configurationRequired) {
      buttons.add(
        _MarketButton(
          label: 'Install',
          primary: true,
          focusNode: primaryNode,
          onArrowDown: _onDown,
          onArrowUp: _onUp,
          onTap: onInstall,
        ),
      );
    }
    if (addon.configurationRequired || addon.configurable) {
      buttons.add(
        _MarketButton(
          label: 'Configure',
          focusNode: buttons.isEmpty ? primaryNode : null,
          onArrowDown: _onDown,
          onArrowUp: _onUp,
          onTap: onConfigure,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          buttons[i],
        ],
      ],
    );
  }
}

/// A stadium Install/Configure button matching the Stremio addons screen:
/// primary = solid accent fill, secondary = quiet outline. Constant 2px border
/// so focus never changes the button's size (no reflow shake).
class _MarketButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final FocusNode? focusNode;

  /// Return true if the arrow was consumed (focus moved / deliberately held).
  final bool Function()? onArrowUp;
  final bool Function()? onArrowDown;

  const _MarketButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.focusNode,
    this.onArrowUp,
    this.onArrowDown,
  });

  @override
  State<_MarketButton> createState() => _MarketButtonState();
}

class _MarketButtonState extends State<_MarketButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final Color fill;
    final Color borderColor;
    // The label/ring sit ON the accent fill when primary; the quiet variant sits
    // on the (untokenised) card, so its whites stay literal.
    final Color ink;
    if (widget.primary) {
      fill = _focused ? app.seeAll.accent2 : app.seeAll.accent;
      ink = app.inkOn(app.seeAll.accent);
      borderColor = _focused ? ink : Colors.transparent;
    } else {
      fill = _focused
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.transparent;
      borderColor = _focused
          ? Colors.white
          : Colors.white.withValues(alpha: 0.22);
      ink = Colors.white;
    }
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) addonHubCenterInScrollable(context);
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (isActivateKey(event.logicalKey)) {
          if (event is KeyDownEvent) widget.onTap();
          return KeyEventResult.handled;
        }
        // Vertical DPAD hops rows (Install↔Install, or Install→Configure-only) —
        // horizontal is left to default traversal (Install ↔ Configure in-row).
        if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
            widget.onArrowDown != null) {
          return widget.onArrowDown!()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
            widget.onArrowUp != null) {
          return widget.onArrowUp!()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: app.shape.br(24),
              border: Border.all(width: 2, color: borderColor),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A themed torrent-engine row (imported or available). Whole card is the tap
/// target — matching the classic engine screen — with a trailing action pill.
class _EngineRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String actionLabel;
  final bool primary;
  final bool danger;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  const _EngineRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    this.primary = false,
    this.danger = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return AddonHubFocusCard(
      onTap: onTap,
      focusNode: focusNode,
      builder: (focused) => Container(
        decoration: addonHubCardDecoration(focused),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: kSeeAllAccent2, size: 30),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            _EngineActionPill(
              label: actionLabel,
              primary: primary,
              danger: danger,
            ),
          ],
        ),
      ),
    );
  }
}

/// A non-focusable label pill inside an engine row (the whole row is the button;
/// this just states the action). Install = accent, Remove = danger outline.
class _EngineActionPill extends StatelessWidget {
  final String label;
  final bool primary;
  final bool danger;
  const _EngineActionPill({
    required this.label,
    this.primary = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final Color fill;
    final Color border;
    final Color text;
    if (danger) {
      fill = Colors.transparent;
      border = const Color(0xFFEF4444).withValues(alpha: 0.5);
      text = const Color(0xFFEF4444);
    } else if (primary) {
      fill = app.seeAll.accent;
      border = Colors.transparent;
      text = app.inkOn(app.seeAll.accent);
    } else {
      fill = Colors.transparent;
      border = Colors.white.withValues(alpha: 0.22);
      text = Colors.white;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: app.shape.br(24),
        border: Border.all(width: 2, color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 13,
          fontWeight: FontWeight.w700,
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
    'onEnginesChanged': s._l.onEnginesChanged,
    'loadInstalled': s._sections.loading.loadInstalled,
    'loadMarket': s._sections.loading.loadMarket,
    'loadEngines': s._l.loadEngines,
    'focusFirstRow': s._focusFirstRow,
    'setMetadataProvider': s._sections.installedList.setMetadataProvider,
    'toggleAddon': s._sections.management.toggleAddon,
    'setTv': (bool tv) {
      s.h.isTv = tv;
      (s.context as Element).markNeedsBuild();
    },
  };
}

import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import '../../theme/app_theme_scope.dart';
import 'widgets/settings_widgets.dart';

/// One selectable hero-source mode.
class SpotlightHeroSourceChoice {
  final HomeHeroSourceMode value;
  final String label;
  final String subtitle;
  const SpotlightHeroSourceChoice(this.value, this.label, this.subtitle);
}

const List<SpotlightHeroSourceChoice> kSpotlightHeroSourceChoices = [
  SpotlightHeroSourceChoice(
    HomeHeroSourceMode.auto,
    'First row',
    'The hero mirrors the top row of the board — the default',
  ),
  SpotlightHeroSourceChoice(
    HomeHeroSourceMode.random,
    'Surprise me',
    'Any installed catalog, re-rolled each time Home loads',
  ),
  SpotlightHeroSourceChoice(
    HomeHeroSourceMode.custom,
    'My picks',
    'Chosen catalogs below — more than one rotates each load',
  ),
];

/// Row caption for the current source (tile subtitle in Home Page Settings).
String spotlightHeroSourceLabel(HomeHeroSource source) =>
    switch (source.mode) {
      HomeHeroSourceMode.auto => 'First row',
      HomeHeroSourceMode.random => 'Surprise me',
      HomeHeroSourceMode.custom => source.ids.length == 1
          ? '1 catalog'
          : '${source.ids.length} catalogs, rotating',
    };

/// Spotlight "Hero Source" picker — which catalog feeds the hero reel.
///
/// Its own page (like Home Layout) rather than inline rows: the custom mode
/// unfolds into every installed catalog, which would swamp the Home settings
/// page. Applies live — every committed change fires
/// [MainPageBridge.notifyHomeSettingsChanged] and the board re-rolls its reel
/// without a restart. Only the Spotlight layout reads the pref; the page says
/// so rather than hiding itself, because the layout can change at any time.
class SpotlightHeroSourcePage extends StatefulWidget {
  /// The board's catalog addons (browsable catalogs are what's offered).
  final List<StremioAddon> addons;

  const SpotlightHeroSourcePage({super.key, required this.addons});

  @override
  State<SpotlightHeroSourcePage> createState() =>
      _SpotlightHeroSourcePageState();
}

class _SpotlightHeroSourcePageState extends State<SpotlightHeroSourcePage> {
  bool _loading = true;
  HomeHeroSourceMode _mode = HomeHeroSourceMode.random;

  /// Picked catalog leaves (`addonId:type:catalogId`), in pick order. Kept
  /// across mode flips — see [StorageService.getHomeHeroSource] — so trying
  /// "Surprise me" doesn't wipe a curated selection.
  final List<String> _ids = [];

  /// Non-focusable marker around the mode card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'spotlight-hero-source-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('spotlight_hero_source_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final source = await StorageService.getHomeHeroSource();
    if (!mounted) return;
    setState(() {
      _mode = source.mode;
      _ids
        ..clear()
        ..addAll(source.ids);
      _loading = false;
    });
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Don't yank focus if it already landed on a real node (only the
        // route's FocusScope holds focus while nothing is focused yet).
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        _firstCardMarker.traversalDescendants.firstOrNull?.requestFocus();
      });
    }
  }

  /// Persist the current selection and live-apply it to the board.
  Future<void> _save() async {
    await StorageService.setHomeHeroSource((
      mode: _mode,
      ids: List.of(_ids),
    ));
    // The board diffs the pref before doing anything, so this is cheap when
    // nothing effective changed (e.g. toggling picks while in auto mode).
    MainPageBridge.notifyHomeSettingsChanged();
  }

  Future<void> _selectMode(HomeHeroSourceMode value) async {
    if (value == _mode) return;
    setState(() => _mode = value);
    await _save();
  }

  Future<void> _toggleCatalog(String id, bool on) async {
    setState(() {
      if (on) {
        if (!_ids.contains(id)) _ids.add(id);
      } else {
        _ids.remove(id);
      }
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Hero Source',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final tree = [
      for (final a in widget.addons)
        (addon: a, catalogs: a.catalogs.where((c) => c.isBrowsable).toList()),
    ].where((e) => e.catalogs.isNotEmpty).toList();

    return SettingsPageScaffold(
      title: 'Hero Source',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.slideshow_rounded,
                  title: 'Hero Source',
                  subtitle:
                      'What the Spotlight layout\'s big hero reel is built '
                      'from',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in kSpotlightHeroSourceChoices)
                        _modeRow(choice),
                    ],
                  ),
                ),
                if (_mode == HomeHeroSourceMode.custom) ...[
                  const SizedBox(height: 20),
                  if (tree.isEmpty)
                    Text(
                      'No catalog add-ons installed — add one (e.g. '
                      'Cinemeta) from Addons first.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: t.dim,
                      ),
                    )
                  else ...[
                    if (_ids.isEmpty) ...[
                      Text(
                        'Pick at least one catalog — until then the hero '
                        'falls back to the first row.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    for (final entry in tree) ...[
                      SettingsSection(
                        title: entry.addon.name,
                        children: [
                          for (final c in entry.catalogs)
                            _catalogRow(entry.addon, c),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ],
                const SizedBox(height: 14),
                Text(
                  'Only the Spotlight home layout has this hero reel — '
                  'other layouts ignore this. A picked catalog that stops '
                  'answering is skipped, falling back to the first row.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: t.dim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Radio-style row — a plain [SettingsTile] (the DPAD-proven row) with a
  /// check on the active one, same grammar as the Home Layout picker.
  Widget _modeRow(SpotlightHeroSourceChoice choice) {
    final t = AppThemeScope.of(context).settings;
    final bool active = _mode == choice.value;
    return SettingsTile(
      icon: active
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_unchecked_rounded,
      title: choice.label,
      subtitle: choice.subtitle,
      trailing: active
          ? Icon(Icons.check_rounded, size: 20, color: t.accent2)
          : const SizedBox.shrink(),
      onTap: () => _selectMode(choice.value),
    );
  }

  Widget _catalogRow(StremioAddon addon, StremioAddonCatalog catalog) {
    final id = '${addon.id}:${catalog.type}:${catalog.id}';
    return SettingsToggleTile(
      icon: catalog.type == 'series'
          ? Icons.tv_rounded
          : Icons.movie_rounded,
      title: catalog.name,
      subtitle: catalog.type.toUpperCase(),
      value: _ids.contains(id),
      onChanged: (on) => _toggleCatalog(id, on),
    );
  }
}

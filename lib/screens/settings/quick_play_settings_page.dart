import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// Quick Play settings page for configuring torrent search quick play behavior.
class QuickPlaySettingsPage extends StatefulWidget {
  const QuickPlaySettingsPage({super.key});

  @override
  State<QuickPlaySettingsPage> createState() => _QuickPlaySettingsPageState();
}

class _QuickPlaySettingsPageState extends State<QuickPlaySettingsPage> {
  bool _loading = true;

  // Search timeout
  int _searchTimeout = 5;
  int _sourcesTimeout = 15;

  // Cache Fallback Settings
  bool _tryMultipleTorrents = false;
  int _maxRetries = 3;

  // Series auto-pin
  bool _autoBindSeriesPacks = false;

  // Default provider (to hide cache fallback for PikPak)
  String _defaultProvider = 'none';

  // Non-focusable marker around the first card; used on TV to hand entry
  // focus to its first focusable descendant (the timeout dropdown).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'quick-play-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('quick_play_settings');
    _loadSettings();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final searchTimeout = await StorageService.getQuickPlaySearchTimeout();
    final sourcesTimeout = await StorageService.getStremioSourcesTimeout();
    final tryMultipleTorrents =
        await StorageService.getQuickPlayTryMultipleTorrents();
    final maxRetries = await StorageService.getQuickPlayMaxRetries();
    final defaultProvider = await StorageService.getDefaultTorrentProvider();
    final autoBindSeriesPacks =
        await StorageService.getAutoBindSeriesPacksOnPlay();

    if (!mounted) return;

    setState(() {
      _searchTimeout = searchTimeout;
      _sourcesTimeout = sourcesTimeout;
      _tryMultipleTorrents = tryMultipleTorrents;
      _maxRetries = maxRetries;
      _defaultProvider = defaultProvider;
      _autoBindSeriesPacks = autoBindSeriesPacks;
      _loading = false;
    });
    // TV entry focus: land DPAD users on the first field instead of nothing.
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Don't yank focus if it already landed on a real node (only the
        // route's FocusScope holds focus while nothing is focused yet).
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        final target = _firstCardMarker.traversalDescendants.firstOrNull;
        target?.requestFocus();
      });
    }
  }

  Future<void> _setAutoBindSeriesPacks(bool enabled) async {
    setState(() => _autoBindSeriesPacks = enabled);
    await StorageService.setAutoBindSeriesPacksOnPlay(enabled);
  }

  Future<void> _setTryMultipleTorrents(bool tryMultiple) async {
    setState(() => _tryMultipleTorrents = tryMultiple);
    await StorageService.setQuickPlayTryMultipleTorrents(tryMultiple);
  }

  Future<void> _setMaxRetries(int maxRetries) async {
    setState(() => _maxRetries = maxRetries);
    await StorageService.setQuickPlayMaxRetries(maxRetries);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Quick Play Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Quick Play Settings',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: _buildSearchTimeoutSection(context),
                ),
                const SizedBox(height: 24),
                _buildSourcesTimeoutSection(context),
                const SizedBox(height: 24),
                // Series Auto-Pin + Cache Fallback both rely on cache-aware
                // pack probing, which PikPak can't do — hide for PikPak.
                if (_defaultProvider != 'pikpak') ...[
                  _buildSeriesAutoPinSection(context),
                  const SizedBox(height: 24),
                  _buildCacheFallbackSection(context),
                  const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return const SettingsPageHeader(
      icon: Icons.bolt_rounded,
      title: 'Quick Play Settings',
      subtitle: 'Configure quick play behavior for torrent search',
    );
  }

  Widget _buildSearchTimeoutSection(BuildContext context) {
    return _buildTimeoutCard(
      context: context,
      title: 'Quick Play Timeout',
      description:
          'Maximum time to wait for search results before starting playback with whatever is available.',
      options: const [5, 10, 15, 20, 30],
      value: _searchTimeout,
      onSelected: (selected) {
        setState(() => _searchTimeout = selected);
        StorageService.setQuickPlaySearchTimeout(selected);
      },
    );
  }

  Widget _buildSourcesTimeoutSection(BuildContext context) {
    return _buildTimeoutCard(
      context: context,
      title: 'Sources Timeout',
      description:
          'Maximum time to wait for each Stremio addon when listing sources for a title. Raise this if you use slow addons (e.g. addons that scrape on demand).',
      options: const [10, 15, 20, 30, 45, 60],
      value: _sourcesTimeout,
      onSelected: (selected) {
        setState(() => _sourcesTimeout = selected);
        StorageService.setStremioSourcesTimeout(selected);
      },
    );
  }

  Widget _buildTimeoutCard({
    required BuildContext context,
    required String title,
    required String description,
    required List<int> options,
    required int value,
    required ValueChanged<int> onSelected,
  }) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.timer_rounded,
                  color: t.accent2,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: app.core.tx,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: t.line),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
            ),
          ),
          // Dropdown instead of the old tap-row + SimpleDialog picker: the
          // closed field is one focusable node with the themed focus ring,
          // and the open menu's items take DPAD focus natively.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SettingsSelectDropdown(
              options: [
                for (final s in _withCurrent(options, value))
                  SettingsSelectOption('$s', '$s seconds'),
              ],
              value: '$value',
              onChanged: (v) {
                final parsed = int.tryParse(v);
                if (parsed != null) onSelected(parsed);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Discrete steps plus the stored value (if it isn't one of them), so a
  /// stale/custom pref doesn't silently change when the page opens.
  List<int> _withCurrent(List<int> options, int value) {
    if (options.contains(value)) return options;
    return [...options, value]..sort();
  }

  Widget _buildSeriesAutoPinSection(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.push_pin_rounded,
                  color: t.accent2,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Series Auto-Pin',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: app.core.tx,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: t.line),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'When you play a series with no pinned source, search for a '
              'complete-series pack first (then a season pack, then the single '
              'episode) and pin whatever plays — so later episodes start '
              'instantly from the pinned source.',
              style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
            ),
          ),
          _buildCheckboxTile(
            context,
            title: 'Prefer and pin series packs',
            subtitle: _autoBindSeriesPacks
                ? 'Packs are searched first and the playing source is pinned automatically'
                : 'Series plays search only the requested episode and pin nothing',
            value: _autoBindSeriesPacks,
            onChanged: _setAutoBindSeriesPacks,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildCacheFallbackSection(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.cached_rounded,
                  color: t.accent2,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Cache Fallback',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: app.core.tx,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: t.line),

          // Description
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Control what happens when a torrent is not cached on your debrid service.',
              style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
            ),
          ),

          // Try Multiple Torrents toggle
          _buildCheckboxTile(
            context,
            title: 'Try multiple torrents',
            subtitle: _tryMultipleTorrents
                ? 'If first torrent is not cached, try up to $_maxRetries torrents'
                : 'Stop immediately if first torrent is not cached',
            value: _tryMultipleTorrents,
            onChanged: _setTryMultipleTorrents,
          ),

          // Max retries (only visible when try multiple is enabled).
          // Dropdown instead of the old tap-row + SimpleDialog picker — see
          // the timeout cards for the DPAD rationale.
          if (_tryMultipleTorrents) ...[
            Divider(height: 1, color: t.line),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Max torrents to try',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: app.core.tx,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Higher values increase chance of finding cached content',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: t.dim,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SettingsSelectDropdown(
                    options: [
                      for (final n in _withCurrent(
                        List.generate(9, (i) => i + 2),
                        _maxRetries,
                      ))
                        SettingsSelectOption('$n', '$n torrents'),
                    ],
                    value: '$_maxRetries',
                    onChanged: (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null) _setMaxRetries(parsed);
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckboxTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return _FocusableCheckboxTile(
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Checkbox row with an unmistakable DPAD focus state (accent ring + lit
/// fill, like SettingsTile). One traversal stop: the row's InkWell owns
/// focus and activation; the Checkbox is excluded.
class _FocusableCheckboxTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool value;
  final Function(bool) onChanged;

  const _FocusableCheckboxTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_FocusableCheckboxTile> createState() => _FocusableCheckboxTileState();
}

class _FocusableCheckboxTileState extends State<_FocusableCheckboxTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final theme = Theme.of(context);
    // Snap, don't tween — per-keypress decoration lerps add cost on TV.
    return Container(
      decoration: BoxDecoration(
        color: _focused ? t.panel2 : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused ? t.accent : Colors.transparent,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => widget.onChanged(!widget.value),
        onFocusChange: (f) => setState(() => _focused = f),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ExcludeFocus(
                child: Checkbox(
                  value: widget.value,
                  onChanged: (v) => widget.onChanged(v ?? false),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: app.core.tx,
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: t.dim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../services/storage_service.dart';
import 'widgets/settings_widgets.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
                _buildSearchTimeoutSection(context),
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
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: kSettingsPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSettingsLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.timer_rounded,
                  color: kSettingsAccent2,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: kSettingsLine),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(color: kSettingsDim),
            ),
          ),
          InkWell(
            onTap: () async {
              final selected = await showDialog<int>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text(title),
                  children: options
                      .map(
                        (s) => SimpleDialogOption(
                          onPressed: () => Navigator.of(ctx).pop(s),
                          child: Row(
                            children: [
                              if (s == value)
                                const Icon(
                                  Icons.check,
                                  size: 18,
                                  color: kSettingsAccent2,
                                )
                              else
                                const SizedBox(width: 18),
                              const SizedBox(width: 12),
                              Text('$s seconds'),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
              if (selected != null) {
                onSelected(selected);
              }
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Timeout',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: kSettingsAccent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${value}s',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: kSettingsAccent2,
                      ),
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

  Widget _buildSeriesAutoPinSection(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: kSettingsPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSettingsLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.push_pin_rounded,
                  color: kSettingsAccent2,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Series Auto-Pin',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: kSettingsLine),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'When you play a series with no pinned source, search for a '
              'complete-series pack first (then a season pack, then the single '
              'episode) and pin whatever plays — so later episodes start '
              'instantly from the pinned source.',
              style: theme.textTheme.bodySmall?.copyWith(color: kSettingsDim),
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
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: kSettingsPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSettingsLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.cached_rounded,
                  color: kSettingsAccent2,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Cache Fallback',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: kSettingsLine),

          // Description
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Control what happens when a torrent is not cached on your debrid service.',
              style: theme.textTheme.bodySmall?.copyWith(color: kSettingsDim),
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

          // Max retries (only visible when try multiple is enabled)
          if (_tryMultipleTorrents) ...[
            Divider(height: 1, color: kSettingsLine),
            InkWell(
              onTap: () async {
                final selected = await showDialog<int>(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: const Text('Max torrents to try'),
                    children: List.generate(9, (i) => i + 2)
                        .map(
                          (n) => SimpleDialogOption(
                            onPressed: () => Navigator.of(ctx).pop(n),
                            child: Row(
                              children: [
                                if (n == _maxRetries)
                                  const Icon(
                                    Icons.check,
                                    size: 18,
                                    color: kSettingsAccent2,
                                  )
                                else
                                  const SizedBox(width: 18),
                                const SizedBox(width: 12),
                                Text('$n torrents'),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                );
                if (selected != null) {
                  _setMaxRetries(selected);
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Max torrents to try',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Higher values increase chance of finding cached content',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: kSettingsDim,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: kSettingsAccent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_maxRetries',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: kSettingsAccent2,
                        ),
                      ),
                    ),
                  ],
                ),
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
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: kSettingsDim,
                    ),
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

import 'package:flutter/material.dart';

import '../../services/storage_service.dart';

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
    final tryMultipleTorrents = await StorageService.getQuickPlayTryMultipleTorrents();
    final maxRetries = await StorageService.getQuickPlayMaxRetries();
    final defaultProvider = await StorageService.getDefaultTorrentProvider();

    if (!mounted) return;

    setState(() {
      _searchTimeout = searchTimeout;
      _sourcesTimeout = sourcesTimeout;
      _tryMultipleTorrents = tryMultipleTorrents;
      _maxRetries = maxRetries;
      _defaultProvider = defaultProvider;
      _loading = false;
    });
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
      return Scaffold(
        appBar: AppBar(
          title: const Text('Quick Play Settings'),
          backgroundColor: Theme.of(context).colorScheme.surface,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Play Settings'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: 24),
            _buildSearchTimeoutSection(context),
            const SizedBox(height: 24),
            _buildSourcesTimeoutSection(context),
            const SizedBox(height: 24),
            // Cache Fallback section (hide for PikPak - not supported)
            if (_defaultProvider != 'pikpak') ...[
              _buildCacheFallbackSection(context),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick Play Settings',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configure quick play behavior for torrent search',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimaryContainer
                            .withValues(alpha: 0.7),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
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
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
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
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          InkWell(
            onTap: () async {
              final selected = await showDialog<int>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text(title),
                  children: options.map((s) => SimpleDialogOption(
                    onPressed: () => Navigator.of(ctx).pop(s),
                    child: Row(
                      children: [
                        if (s == value)
                          Icon(Icons.check, size: 18, color: theme.colorScheme.primary)
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 12),
                        Text('${s} seconds'),
                      ],
                    ),
                  )).toList(),
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
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${value}s',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
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

  Widget _buildCacheFallbackSection(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
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
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Cache Fallback',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Description
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Control what happens when a torrent is not cached on your debrid service.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
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
            const Divider(height: 1),
            InkWell(
              onTap: () async {
                final selected = await showDialog<int>(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: const Text('Max torrents to try'),
                    children: List.generate(9, (i) => i + 2).map((n) => SimpleDialogOption(
                      onPressed: () => Navigator.of(ctx).pop(n),
                      child: Row(
                        children: [
                          if (n == _maxRetries)
                            Icon(Icons.check, size: 18, color: theme.colorScheme.primary)
                          else
                            const SizedBox(width: 18),
                          const SizedBox(width: 12),
                          Text('$n torrents'),
                        ],
                      ),
                    )).toList(),
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
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Higher values increase chance of finding cached content',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_maxRetries',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
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
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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

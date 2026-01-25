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
    final tryMultipleTorrents = await StorageService.getQuickPlayTryMultipleTorrents();
    final maxRetries = await StorageService.getQuickPlayMaxRetries();
    final defaultProvider = await StorageService.getDefaultTorrentProvider();

    if (!mounted) return;

    setState(() {
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

          // Max retries slider (only visible when try multiple is enabled)
          if (_tryMultipleTorrents) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Max torrents to try',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: theme.colorScheme.primary,
                      inactiveTrackColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                      thumbColor: theme.colorScheme.primary,
                      overlayColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                    ),
                    child: Slider(
                      value: _maxRetries.toDouble(),
                      min: 2,
                      max: 10,
                      divisions: 8,
                      label: '$_maxRetries',
                      onChanged: (value) => _setMaxRetries(value.round()),
                    ),
                  ),
                  Text(
                    'Higher values increase chance of finding cached content but may take longer',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
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

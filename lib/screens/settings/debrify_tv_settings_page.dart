import 'package:flutter/material.dart';
import 'widgets/dynamic_settings_builder.dart';
import '../../services/engine/settings_manager.dart';
import '../../services/engine/engine_registry.dart';

class DebrifyTvSettingsPage extends StatefulWidget {
  const DebrifyTvSettingsPage({super.key});

  @override
  State<DebrifyTvSettingsPage> createState() => _DebrifyTvSettingsPageState();
}

class _DebrifyTvSettingsPageState extends State<DebrifyTvSettingsPage> {
  final GlobalKey<DynamicTvSettingsBuilderState> _settingsKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debrify TV Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          _buildHeader(context),

          const SizedBox(height: 24),

          // Use DynamicTvSettingsBuilder
          DynamicTvSettingsBuilder(
            key: _settingsKey,
            onSettingsChanged: () {
              setState(() {}); // Refresh if needed
            },
          ),

          const SizedBox(height: 16),

          // Info section
          _buildInfoSection(context),

          const SizedBox(height: 16),

          // Reset button
          _buildResetButton(context),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.tv_rounded,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Debrify TV Configuration',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Configure search engines and result limits',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Performance Tips',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Higher limits = More results but slower\nLower limits = Faster but fewer results',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Each enabled engine will make API calls per keyword. Consider disabling engines you don\'t need for better performance.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResetButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showResetConfirmation(context),
        icon: const Icon(Icons.refresh),
        label: const Text('Reset to Defaults'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  void _showResetConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings'),
        content: const Text(
          'Are you sure you want to reset all Debrify TV settings to their default values?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resetToDefaults();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetToDefaults() async {
    final settings = SettingsManager();
    final registry = EngineRegistry.instance;

    // Reset global TV settings
    await settings.setGlobalKeywordThreshold(10);
    await settings.setGlobalBatchSize(4);
    await settings.setGlobalMinTorrentsPerKeyword(5);
    await settings.setGlobalAvoidNsfw(true);

    // Reset per-engine TV settings from their configs
    for (final config in registry.getAllConfigs().values) {
      if (config.tvMode != null) {
        await settings.setTvEnabled(
            config.metadata.id, config.tvMode!.enabledDefault);
        await settings.setTvSmallChannelMax(
            config.metadata.id, config.tvMode!.smallChannel.maxResults);
        await settings.setTvLargeChannelMax(
            config.metadata.id, config.tvMode!.largeChannel.maxResults);
        await settings.setTvQuickPlayMax(
            config.metadata.id, config.tvMode!.quickPlay.maxResults);
      }
    }

    // Reload the settings builder
    _settingsKey.currentState?.reload();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings reset to defaults')),
      );
    }
  }
}

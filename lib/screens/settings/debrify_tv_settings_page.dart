import 'package:flutter/material.dart';
import 'widgets/dynamic_settings_builder.dart';
import 'widgets/settings_widgets.dart';
import '../../services/engine/settings_manager.dart';
import '../../services/engine/engine_registry.dart';
import '../../services/engine/config_loader.dart';

class DebrifyTvSettingsPage extends StatefulWidget {
  const DebrifyTvSettingsPage({super.key});

  @override
  State<DebrifyTvSettingsPage> createState() => _DebrifyTvSettingsPageState();
}

class _DebrifyTvSettingsPageState extends State<DebrifyTvSettingsPage> {
  final GlobalKey<DynamicTvSettingsBuilderState> _settingsKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'Debrify TV Settings',
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: ListView(
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
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return const SettingsPageHeader(
      icon: Icons.tv_rounded,
      title: 'Debrify TV Configuration',
      subtitle: 'Configure search engines and result limits',
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSettingsPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSettingsLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 20, color: kSettingsAccent2),
              const SizedBox(width: 8),
              Text(
                'Performance Tips',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Higher limits = More results but slower\nLower limits = Faster but fewer results',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: kSettingsDim,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Each enabled engine will make API calls per keyword. Consider disabling engines you don\'t need for better performance.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: kSettingsDim),
          ),
        ],
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
    final configLoader = ConfigLoader();

    // Load defaults from _defaults.yaml
    final defaults = await configLoader.getDefaults();
    final tvDefaults = defaults.tvMode;

    // Reset global TV settings from YAML defaults
    await settings.setGlobalKeywordThreshold(tvDefaults.keywordThreshold);
    await settings.setGlobalBatchSize(tvDefaults.channelBatchSize);
    await settings.setGlobalMinTorrentsPerKeyword(
      tvDefaults.minTorrentsPerKeyword,
    );
    await settings.setGlobalMaxKeywords(tvDefaults.maxKeywords);
    await settings.setGlobalAvoidNsfw(tvDefaults.avoidNsfw);

    // Reset per-engine TV settings from their configs
    for (final config in registry.getAllConfigs().values) {
      if (config.tvMode != null) {
        await settings.setTvEnabled(
          config.metadata.id,
          config.tvMode!.enabledDefault,
        );
        await settings.setTvSmallChannelMax(
          config.metadata.id,
          config.tvMode!.smallChannel.maxResults,
        );
        await settings.setTvLargeChannelMax(
          config.metadata.id,
          config.tvMode!.largeChannel.maxResults,
        );
        await settings.setTvQuickPlayMax(
          config.metadata.id,
          config.tvMode!.quickPlay.maxResults,
        );
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

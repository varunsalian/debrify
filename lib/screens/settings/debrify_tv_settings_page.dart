import 'package:flutter/material.dart';
import 'widgets/dynamic_settings_builder.dart';
import 'widgets/settings_widgets.dart';
import '../../services/engine/settings_manager.dart';
import '../../services/engine/engine_registry.dart';
import '../../services/engine/config_loader.dart';
import '../../utils/platform_util.dart';

class DebrifyTvSettingsPage extends StatefulWidget {
  const DebrifyTvSettingsPage({super.key});

  @override
  State<DebrifyTvSettingsPage> createState() => _DebrifyTvSettingsPageState();
}

class _DebrifyTvSettingsPageState extends State<DebrifyTvSettingsPage> {
  final GlobalKey<DynamicTvSettingsBuilderState> _settingsKey = GlobalKey();

  /// Scope around the body only, so entry focus can never land on the
  /// AppBar back button (whose OK press would pop the page).
  final FocusScopeNode _bodyScope = FocusScopeNode(
    debugLabel: 'debrify-tv-settings-body',
  );

  @override
  void initState() {
    super.initState();
    // TV: land DPAD focus on the first body row. The builder's rows load
    // async, so retry a few frames until one becomes focusable.
    if (PlatformUtil.isAndroidTvCached) {
      _seedTvFocus();
    }
  }

  void _seedTvFocus([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _bodyScope.hasFocus) return;
      // Never steal focus: a freshly pushed route parks primary focus on a
      // FocusScopeNode; once the user has focused something real (e.g. the
      // AppBar back button) it's a regular FocusNode — stop retrying.
      final FocusNode? primary = FocusManager.instance.primaryFocus;
      if (primary != null && primary is! FocusScopeNode) return;
      // While the builder is still loading (spinner), the only focusable
      // descendant is the Reset button at the bottom — wait for the real
      // rows before seeding, so focus lands on the FIRST row at the top.
      final bool loaded = _settingsKey.currentState?.isLoaded ?? false;
      final List<FocusNode> rows = _bodyScope.traversalDescendants.toList();
      if (loaded && rows.length > 1) {
        final FocusNode first = rows.first;
        first.requestFocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = first.context;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.15,
              duration: const Duration(milliseconds: 180),
            );
          }
        });
      } else if (attempt < 600) {
        // ~10s of frames, so a cold engine-registry init can't outlast it.
        _seedTvFocus(attempt + 1);
      }
    });
  }

  @override
  void dispose() {
    _bodyScope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'Debrify TV Settings',
      body: FocusScope(
        node: _bodyScope,
        child: FocusTraversalGroup(
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
        // State-resolved accent border + lit fill so DPAD focus is
        // unmistakable on TV (default focus overlay is too faint).
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 16),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.focused) ? kSettingsPanel2 : null,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? const BorderSide(color: kSettingsAccent, width: 1.5)
                : BorderSide(
                    color: const Color(0xFFB4A0FF).withValues(alpha: 0.3),
                  ),
          ),
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
            // TV: land DPAD focus on the safe action when the dialog opens.
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? kSettingsPanel
                    : null,
              ),
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? const BorderSide(color: kSettingsAccent, width: 1.5)
                    : null,
              ),
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _resetToDefaults();
            },
            // Focused ring on the filled (accent) button reads as white.
            style: ButtonStyle(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? const BorderSide(color: Colors.white, width: 2)
                    : null,
              ),
            ),
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

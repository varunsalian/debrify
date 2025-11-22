import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/engine_config/engine_config.dart';
import '../../../services/engine/settings_manager.dart';
import '../../../services/engine/engine_registry.dart';

/// Builds settings UI dynamically from engine configurations
class DynamicSettingsBuilder extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const DynamicSettingsBuilder({super.key, this.onSettingsChanged});

  @override
  State<DynamicSettingsBuilder> createState() => _DynamicSettingsBuilderState();
}

class _DynamicSettingsBuilderState extends State<DynamicSettingsBuilder> {
  final SettingsManager _settings = SettingsManager();
  final Map<String, Map<String, dynamic>> _settingValues = {};
  bool _loading = true;
  List<EngineConfig> _engineConfigs = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      // Get all engine configs from registry
      final registry = EngineRegistry.instance;
      if (!registry.isInitialized) {
        await registry.initialize();
      }

      final configs = registry.getAllConfigs();
      _engineConfigs = configs.values.toList();

      // Load current setting values for each engine
      final prefs = await SharedPreferences.getInstance();
      for (final config in _engineConfigs) {
        final engineId = config.metadata.id;
        final settingsConfig = config.settings;

        if (settingsConfig.settings.isNotEmpty) {
          _settingValues[engineId] = await _loadEngineSettings(
            prefs,
            engineId,
            settingsConfig,
          );
        }
      }

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('DynamicSettingsBuilder: Error loading settings: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// Load all settings for an engine from SharedPreferences
  Future<Map<String, dynamic>> _loadEngineSettings(
    SharedPreferences prefs,
    String engineId,
    SettingsConfig config,
  ) async {
    final result = <String, dynamic>{};

    for (final entry in config.settings.entries) {
      final settingId = entry.key;
      final setting = entry.value;
      final storageKey = _settings.generateKey(engineId, settingId);

      if (setting.type == 'toggle') {
        result[settingId] = prefs.getBool(storageKey) ??
            (setting.defaultValue as bool? ?? false);
      } else if (setting.type == 'dropdown' || setting.type == 'slider') {
        result[settingId] = prefs.getInt(storageKey) ??
            (setting.defaultValue as int? ?? 50);
      } else {
        // Handle string or other types
        final stringValue = prefs.getString(storageKey);
        result[settingId] = stringValue ?? setting.defaultValue;
      }
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_engineConfigs.isEmpty) {
      return _buildNoEnginesMessage();
    }

    // Filter to only show engines with settings
    final enginesWithSettings = _engineConfigs
        .where((config) => config.settings.settings.isNotEmpty)
        .toList();

    if (enginesWithSettings.isEmpty) {
      return _buildNoEnginesMessage();
    }

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: enginesWithSettings
            .map((config) => _buildEngineCard(config))
            .toList(),
      ),
    );
  }

  Widget _buildNoEnginesMessage() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No Search Engines Configured',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Search engine configurations will appear here once loaded.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
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

  Widget _buildEngineCard(EngineConfig config) {
    final engineId = config.metadata.id;
    final displayName = config.metadata.displayName;
    final description = config.metadata.description;
    final iconName = config.metadata.icon;
    final settingsConfig = config.settings;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Engine header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getIconForEngine(iconName),
                    size: 22,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (description != null && description.isNotEmpty)
                        Text(
                          description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Settings list
            ...settingsConfig.settings.entries.map((entry) {
              final settingId = entry.key;
              final setting = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildSettingWidget(engineId, settingId, setting),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingWidget(
      String engineId, String settingId, SettingConfig setting) {
    switch (setting.type.toLowerCase()) {
      case 'toggle':
        return _buildToggleSetting(engineId, settingId, setting);
      case 'dropdown':
        return _buildDropdownSetting(engineId, settingId, setting);
      case 'slider':
        return _buildSliderSetting(engineId, settingId, setting);
      default:
        // Fallback to toggle for unknown types
        return _buildToggleSetting(engineId, settingId, setting);
    }
  }

  Widget _buildToggleSetting(
      String engineId, String settingId, SettingConfig setting) {
    final currentValue = _settingValues[engineId]?[settingId] as bool? ??
        (setting.defaultValue as bool? ?? false);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: currentValue
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
            : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: currentValue
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: currentValue
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                  : Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              _getIconForSetting(settingId),
              size: 18,
              color: currentValue
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  setting.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: currentValue
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  currentValue ? 'Enabled' : 'Disabled',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.7),
                      ),
                ),
              ],
            ),
          ),
          Switch(
            value: currentValue,
            onChanged: (value) async {
              await _settings.setValue<bool>(engineId, settingId, value);
              setState(() {
                _settingValues[engineId] ??= {};
                _settingValues[engineId]![settingId] = value;
              });
              widget.onSettingsChanged?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownSetting(
      String engineId, String settingId, SettingConfig setting) {
    final currentValue = _settingValues[engineId]?[settingId] as int? ??
        (setting.defaultValue as int? ?? 50);

    // Get options from setting config or use defaults
    final options = setting.options ?? [25, 50, 75, 100, 125, 150, 175, 200, 250, 300, 350, 400, 450, 500];

    // Ensure current value is in options, or find closest
    int validValue = currentValue;
    if (!options.contains(currentValue)) {
      validValue = options.reduce(
          (a, b) => (a - currentValue).abs() < (b - currentValue).abs() ? a : b);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  _getIconForSetting(settingId),
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      setting.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Select how many results to fetch',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: DropdownButtonFormField<int>(
              value: validValue,
              onChanged: (newValue) async {
                if (newValue != null) {
                  await _settings.setValue<int>(engineId, settingId, newValue);
                  setState(() {
                    _settingValues[engineId] ??= {};
                    _settingValues[engineId]![settingId] = newValue;
                  });
                  widget.onSettingsChanged?.call();
                }
              },
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: options.map((option) {
                return DropdownMenuItem<int>(
                  value: option,
                  child: Text(
                    '$option results',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              }).toList(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
              dropdownColor: Theme.of(context).colorScheme.surface,
              icon: Icon(
                Icons.arrow_drop_down,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderSetting(
      String engineId, String settingId, SettingConfig setting) {
    final currentValue = (_settingValues[engineId]?[settingId] as int? ??
            (setting.defaultValue as int? ?? 50))
        .toDouble();

    final min = (setting.min ?? 1).toDouble();
    final max = (setting.max ?? 500).toDouble();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  _getIconForSetting(settingId),
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  setting.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  currentValue.toInt().toString(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TvFriendlySlider(
            value: currentValue.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).toInt(),
            onChanged: (value) async {
              final intValue = value.toInt();
              await _settings.setValue<int>(engineId, settingId, intValue);
              setState(() {
                _settingValues[engineId] ??= {};
                _settingValues[engineId]![settingId] = intValue;
              });
              widget.onSettingsChanged?.call();
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                min.toInt().toString(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
              ),
              Text(
                max.toInt().toString(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Get appropriate icon based on engine icon name from config
  IconData _getIconForEngine(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'search':
      case 'search_rounded':
        return Icons.search_rounded;
      case 'movie':
      case 'movie_rounded':
      case 'movie_creation_rounded':
        return Icons.movie_creation_rounded;
      case 'sailing':
      case 'sailing_rounded':
        return Icons.sailing_rounded;
      case 'storage':
      case 'storage_rounded':
        return Icons.storage_rounded;
      case 'cloud':
      case 'cloud_rounded':
        return Icons.cloud_rounded;
      case 'download':
      case 'download_rounded':
        return Icons.download_rounded;
      case 'tv':
      case 'tv_rounded':
        return Icons.tv_rounded;
      default:
        return Icons.search_rounded;
    }
  }

  /// Get appropriate icon based on setting ID
  IconData _getIconForSetting(String settingId) {
    switch (settingId.toLowerCase()) {
      case 'enabled':
        return Icons.power_settings_new_rounded;
      case 'max_results':
        return Icons.format_list_numbered_rounded;
      case 'keyword_threshold':
        return Icons.tune_rounded;
      case 'batch_size':
        return Icons.batch_prediction_rounded;
      case 'min_torrents_per_keyword':
      case 'min_torrents':
        return Icons.filter_list_rounded;
      case 'avoid_nsfw':
        return Icons.shield_rounded;
      default:
        return Icons.settings_rounded;
    }
  }
}

// =============================================================================
// TV Mode Settings Builder
// =============================================================================

/// Builds TV mode settings UI dynamically from engine configurations
class DynamicTvSettingsBuilder extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const DynamicTvSettingsBuilder({super.key, this.onSettingsChanged});

  @override
  DynamicTvSettingsBuilderState createState() =>
      DynamicTvSettingsBuilderState();
}

class DynamicTvSettingsBuilderState extends State<DynamicTvSettingsBuilder> {
  final SettingsManager _settings = SettingsManager();
  bool _loading = true;
  List<EngineConfig> _tvEnabledEngines = [];

  // Global TV settings
  int _keywordThreshold = 5;
  int _batchSize = 3;
  int _minTorrentsPerKeyword = 10;
  int _maxKeywords = 5;
  bool _avoidNsfw = true;

  // Per-engine TV settings
  final Map<String, bool> _engineTvEnabled = {};
  final Map<String, int> _smallChannelMax = {};
  final Map<String, int> _largeChannelMax = {};
  final Map<String, int> _quickPlayMax = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// Public method to reload settings (called from parent widget)
  void reload() {
    setState(() {
      _loading = true;
    });
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      // Get engines with TV mode from registry
      final registry = EngineRegistry.instance;
      if (!registry.isInitialized) {
        await registry.initialize();
      }

      final configs = registry.getAllConfigs();
      _tvEnabledEngines = configs.values
          .where((config) => config.tvMode != null)
          .toList();

      // Load global TV settings
      _keywordThreshold = await _settings.getGlobalKeywordThreshold(5);
      _batchSize = await _settings.getGlobalBatchSize(3);
      _minTorrentsPerKeyword = await _settings.getGlobalMinTorrentsPerKeyword(10);
      _maxKeywords = await _settings.getGlobalMaxKeywords(5);
      _avoidNsfw = await _settings.getGlobalAvoidNsfw(true);

      // Load per-engine TV settings
      for (final config in _tvEnabledEngines) {
        final engineId = config.metadata.id;
        final tvMode = config.tvMode!;

        _engineTvEnabled[engineId] = await _settings.getTvEnabled(
          engineId,
          tvMode.enabledDefault,
        );
        _smallChannelMax[engineId] = await _settings.getTvSmallChannelMax(
          engineId,
          tvMode.smallChannel.maxResults,
        );
        _largeChannelMax[engineId] = await _settings.getTvLargeChannelMax(
          engineId,
          tvMode.largeChannel.maxResults,
        );
        _quickPlayMax[engineId] = await _settings.getTvQuickPlayMax(
          engineId,
          tvMode.quickPlay.maxResults,
        );
      }

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('DynamicTvSettingsBuilder: Error loading settings: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Global TV Settings Card
          _buildGlobalTvSettings(),

          const SizedBox(height: 24),

          // Per-engine TV settings
          if (_tvEnabledEngines.isNotEmpty) ...[
            Text(
              'Engine TV Mode Settings',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Configure TV mode limits for each search engine',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            ..._tvEnabledEngines
                .map((config) => _buildEngineTvCard(config)),
          ] else
            _buildNoTvEnginesMessage(),
        ],
      ),
    );
  }

  Widget _buildGlobalTvSettings() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.tv_rounded,
                    size: 22,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Global TV Mode Settings',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        'Settings that apply to all TV mode searches',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Keyword Threshold
            _buildGlobalSliderSetting(
              label: 'Keyword Threshold',
              subtitle: 'Below this: fetch more per keyword. Above: fetch less',
              value: _keywordThreshold,
              min: 1,
              max: 50,
              icon: Icons.tune_rounded,
              onChanged: (value) async {
                await _settings.setGlobalKeywordThreshold(value);
                setState(() {
                  _keywordThreshold = value;
                });
                widget.onSettingsChanged?.call();
              },
            ),

            const SizedBox(height: 12),

            // Batch Size
            _buildGlobalSliderSetting(
              label: 'Batch Size',
              subtitle: 'Number of keywords to process per batch',
              value: _batchSize,
              min: 1,
              max: 10,
              icon: Icons.batch_prediction_rounded,
              onChanged: (value) async {
                await _settings.setGlobalBatchSize(value);
                setState(() {
                  _batchSize = value;
                });
                widget.onSettingsChanged?.call();
              },
            ),

            const SizedBox(height: 12),

            // Min Torrents Per Keyword
            _buildGlobalSliderSetting(
              label: 'Min Torrents Per Keyword',
              subtitle: 'Skip keywords with fewer results than this',
              value: _minTorrentsPerKeyword,
              min: 1,
              max: 50,
              icon: Icons.filter_list_rounded,
              onChanged: (value) async {
                await _settings.setGlobalMinTorrentsPerKeyword(value);
                setState(() {
                  _minTorrentsPerKeyword = value;
                });
                widget.onSettingsChanged?.call();
              },
            ),

            const SizedBox(height: 12),

            // Max Keywords (Quick Play)
            _buildGlobalSliderSetting(
              label: 'Max Keywords (Quick Play)',
              subtitle: 'Maximum keywords allowed for quick play mode',
              value: _maxKeywords,
              min: 1,
              max: 20,
              icon: Icons.tag_rounded,
              onChanged: (value) async {
                await _settings.setGlobalMaxKeywords(value);
                setState(() {
                  _maxKeywords = value;
                });
                widget.onSettingsChanged?.call();
              },
            ),

            const SizedBox(height: 12),

            // Avoid NSFW
            _buildGlobalToggleSetting(
              label: 'Avoid NSFW Content',
              subtitle: 'Filter out adult content from results',
              value: _avoidNsfw,
              icon: Icons.shield_rounded,
              onChanged: (value) async {
                await _settings.setGlobalAvoidNsfw(value);
                setState(() {
                  _avoidNsfw = value;
                });
                widget.onSettingsChanged?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalSliderSetting({
    required String label,
    required String subtitle,
    required int value,
    required int min,
    required int max,
    required IconData icon,
    required Function(int) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  value.toString(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TvFriendlySlider(
            value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            onChanged: (newValue) {
              onChanged(newValue.toInt());
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                min.toString(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
              ),
              Text(
                max.toString(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalToggleSetting({
    required String label,
    required String subtitle,
    required bool value,
    required IconData icon,
    required Function(bool) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: value
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
            : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: value
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                  : Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: 18,
              color: value
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: value
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.7),
                      ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildEngineTvCard(EngineConfig config) {
    final engineId = config.metadata.id;
    final displayName = config.metadata.displayName;
    final iconName = config.metadata.icon;
    final tvMode = config.tvMode!;

    final isEnabled = _engineTvEnabled[engineId] ?? tvMode.enabledDefault;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Engine header with enabled toggle
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isEnabled
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                        : Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getIconForEngine(iconName),
                    size: 22,
                    color: isEnabled
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isEnabled
                                  ? null
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            ),
                      ),
                      Text(
                        isEnabled ? 'TV Mode Enabled' : 'TV Mode Disabled',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isEnabled,
                  onChanged: (value) async {
                    await _settings.setTvEnabled(engineId, value);
                    setState(() {
                      _engineTvEnabled[engineId] = value;
                    });
                    widget.onSettingsChanged?.call();
                  },
                ),
              ],
            ),

            // Limit settings (only shown when enabled)
            if (isEnabled) ...[
              const SizedBox(height: 16),

              // Small Channel Limit
              _buildEngineLimitSetting(
                engineId: engineId,
                label: 'Small Channel Limit',
                subtitle: 'Max results for small channel mode',
                settingKey: 'small_channel',
                currentValue: _smallChannelMax[engineId] ??
                    tvMode.smallChannel.maxResults,
                defaultValue: tvMode.smallChannel.maxResults,
                onChanged: (value) async {
                  await _settings.setTvSmallChannelMax(engineId, value);
                  setState(() {
                    _smallChannelMax[engineId] = value;
                  });
                  widget.onSettingsChanged?.call();
                },
              ),

              const SizedBox(height: 12),

              // Large Channel Limit
              _buildEngineLimitSetting(
                engineId: engineId,
                label: 'Large Channel Limit',
                subtitle: 'Max results for large channel mode',
                settingKey: 'large_channel',
                currentValue: _largeChannelMax[engineId] ??
                    tvMode.largeChannel.maxResults,
                defaultValue: tvMode.largeChannel.maxResults,
                onChanged: (value) async {
                  await _settings.setTvLargeChannelMax(engineId, value);
                  setState(() {
                    _largeChannelMax[engineId] = value;
                  });
                  widget.onSettingsChanged?.call();
                },
              ),

              const SizedBox(height: 12),

              // Quick Play Limit
              _buildEngineLimitSetting(
                engineId: engineId,
                label: 'Quick Play Limit',
                subtitle: 'Max results for quick play mode',
                settingKey: 'quick_play',
                currentValue:
                    _quickPlayMax[engineId] ?? tvMode.quickPlay.maxResults,
                defaultValue: tvMode.quickPlay.maxResults,
                onChanged: (value) async {
                  await _settings.setTvQuickPlayMax(engineId, value);
                  setState(() {
                    _quickPlayMax[engineId] = value;
                  });
                  widget.onSettingsChanged?.call();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEngineLimitSetting({
    required String engineId,
    required String label,
    required String subtitle,
    required String settingKey,
    required int currentValue,
    required int defaultValue,
    required Function(int) onChanged,
  }) {
    final options = [10, 25, 50, 75, 100, 150, 200, 250, 300, 400, 500];

    // Ensure current value is in options
    int validValue = currentValue;
    if (!options.contains(currentValue)) {
      validValue = options.reduce(
          (a, b) => (a - currentValue).abs() < (b - currentValue).abs() ? a : b);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: DropdownButtonFormField<int>(
              value: validValue,
              onChanged: (newValue) {
                if (newValue != null) {
                  onChanged(newValue);
                }
              },
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: options.map((option) {
                return DropdownMenuItem<int>(
                  value: option,
                  child: Text(
                    '$option results',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              }).toList(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
              dropdownColor: Theme.of(context).colorScheme.surface,
              icon: Icon(
                Icons.arrow_drop_down,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTvEnginesMessage() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No TV Mode Engines',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'No search engines with TV mode configuration found.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
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

  /// Get appropriate icon based on engine icon name from config
  IconData _getIconForEngine(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'search':
      case 'search_rounded':
        return Icons.search_rounded;
      case 'movie':
      case 'movie_rounded':
      case 'movie_creation_rounded':
        return Icons.movie_creation_rounded;
      case 'sailing':
      case 'sailing_rounded':
        return Icons.sailing_rounded;
      case 'storage':
      case 'storage_rounded':
        return Icons.storage_rounded;
      case 'cloud':
      case 'cloud_rounded':
        return Icons.cloud_rounded;
      case 'download':
      case 'download_rounded':
        return Icons.download_rounded;
      case 'tv':
      case 'tv_rounded':
        return Icons.tv_rounded;
      default:
        return Icons.search_rounded;
    }
  }
}

/// A TV-friendly slider that allows escaping with arrow keys
/// When at min value, up/left arrows navigate to previous focusable
/// When at max value, down/right arrows navigate to next focusable
class _TvFriendlySlider extends StatefulWidget {
  const _TvFriendlySlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  State<_TvFriendlySlider> createState() => _TvFriendlySliderState();
}

class _TvFriendlySliderState extends State<_TvFriendlySlider> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final step = (widget.max - widget.min) / widget.divisions;
    final isAtMin = widget.value <= widget.min;
    final isAtMax = widget.value >= widget.max;

    // Navigate up: allow if at min value
    if (key == LogicalKeyboardKey.arrowUp) {
      if (isAtMin) {
        final ctx = node.context;
        if (ctx != null) {
          FocusScope.of(ctx).focusInDirection(TraversalDirection.up);
          return KeyEventResult.handled;
        }
      }
    }

    // Navigate down: allow if at max value
    if (key == LogicalKeyboardKey.arrowDown) {
      if (isAtMax) {
        final ctx = node.context;
        if (ctx != null) {
          FocusScope.of(ctx).focusInDirection(TraversalDirection.down);
          return KeyEventResult.handled;
        }
      }
    }

    // Left arrow: decrease value or navigate if at min
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (isAtMin) {
        final ctx = node.context;
        if (ctx != null) {
          FocusScope.of(ctx).focusInDirection(TraversalDirection.up);
          return KeyEventResult.handled;
        }
      } else {
        widget.onChanged((widget.value - step).clamp(widget.min, widget.max));
        return KeyEventResult.handled;
      }
    }

    // Right arrow: increase value or navigate if at max
    if (key == LogicalKeyboardKey.arrowRight) {
      if (isAtMax) {
        final ctx = node.context;
        if (ctx != null) {
          FocusScope.of(ctx).focusInDirection(TraversalDirection.down);
          return KeyEventResult.handled;
        }
      } else {
        widget.onChanged((widget.value + step).clamp(widget.min, widget.max));
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: _isFocused
              ? Border.all(color: theme.colorScheme.primary, width: 2)
              : null,
          color: _isFocused
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : null,
        ),
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: widget.value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: widget.onChanged,
          ),
        ),
      ),
    );
  }
}

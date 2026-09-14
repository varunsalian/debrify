import 'package:flutter/material.dart';
import 'package:synchronized/synchronized.dart';
import '../../../services/engine/local_engine_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/engine_config/engine_config.dart';
import '../../../services/engine/settings_manager.dart';
import '../../../services/engine/engine_registry.dart';
import '../../../services/profiles/profile_preferences.dart';
import '../../../theme/app_theme_scope.dart';

/// Discrete choices replacing a former slider's min..max range. Small ranges
/// enumerate every value; large ones use a coarse ladder so the dropdown
/// stays short. The currently-stored [current] is always included so the
/// slider→dropdown swap can't silently change a saved setting.
List<int> _sliderStepOptions(int min, int max, int current) {
  final steps = <int>{};
  if (max - min <= 20) {
    for (int v = min; v <= max; v++) {
      steps.add(v);
    }
  } else {
    const ladder = [
      1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 75, //
      100, 150, 200, 250, 300, 350, 400, 450, 500,
    ];
    for (final v in ladder) {
      if (v >= min && v <= max) steps.add(v);
    }
    steps
      ..add(min)
      ..add(max);
  }
  steps.add(current);
  return steps.toList()..sort();
}

/// Shared numeric dropdown for the dynamic settings cards. Uses the themed
/// InputDecoration so DPAD focus paints the accent focusedBorder — the old
/// `InputBorder.none` idiom left focus invisible on TV.
Widget _stepDropdown(
  BuildContext context, {
  required int value,
  required List<int> options,
  required ValueChanged<int> onChanged,
  String Function(int value)? labelOf,
}) {
  final app = AppThemeScope.of(context);
  final t = app.settings;
  return DropdownButtonFormField<int>(
    value: value,
    isExpanded: true,
    decoration: const InputDecoration(),
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
    items: [
      for (final option in options)
        DropdownMenuItem<int>(
          value: option,
          child: Text(
            labelOf?.call(option) ?? '$option',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
    ],
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: app.core.tx),
    dropdownColor: t.panel2,
    borderRadius: app.shape.br(14),
    icon: Icon(Icons.arrow_drop_down, color: t.dim),
  );
}

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
    LocalEngineStorage.changes.addListener(_loadSettings);
    _loadSettings();
  }

  final _settingsLoadLock = Lock();

  @override
  void dispose() {
    LocalEngineStorage.changes.removeListener(_loadSettings);
    super.dispose();
  }

  Future<void> _loadSettings() =>
      _settingsLoadLock.synchronized(_loadSettingsNow);

  Future<void> _loadSettingsNow() async {
    if (!mounted) return;
    try {
      // Get all engine configs from registry
      final registry = EngineRegistry.instance;
      if (!registry.isInitialized) {
        await registry.initialize();
      }

      final configs = registry.getAllConfigs();
      _engineConfigs = configs.values.toList();

      // Load current setting values for each engine
      final prefs = await ProfilePreferences.instance();
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
        result[settingId] =
            prefs.getBool(storageKey) ??
            (setting.defaultValue as bool? ?? false);
      } else if (setting.type == 'dropdown' || setting.type == 'slider') {
        result[settingId] =
            prefs.getInt(storageKey) ?? (setting.defaultValue as int? ?? 50);
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
    final t = AppThemeScope.of(context).settings;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.panel2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: t.dim, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No Search Engines Configured',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: t.dim,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Search engine configurations will appear here once loaded.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: t.dim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEngineCard(EngineConfig config) {
    final t = AppThemeScope.of(context).settings;
    final engineId = config.metadata.id;
    final displayName = config.metadata.displayName;
    final description = config.metadata.description;
    final iconName = config.metadata.icon;
    final settingsConfig = config.settings;

    return Card(
      elevation: 0,
      color: t.panel,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: t.line),
      ),
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
                    color: t.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getIconForEngine(iconName),
                    size: 22,
                    color: t.accent2,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (description != null && description.isNotEmpty)
                        Text(
                          description,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: t.dim),
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
    String engineId,
    String settingId,
    SettingConfig setting,
  ) {
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
    String engineId,
    String settingId,
    SettingConfig setting,
  ) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final currentValue =
        _settingValues[engineId]?[settingId] as bool? ??
        (setting.defaultValue as bool? ?? false);

    // The Switch is the focusable; the ring goes on the row so DPAD focus is
    // unmissable on TV.
    return _FocusHighlight(
      builder: (context, focused) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: currentValue ? t.accent.withValues(alpha: 0.1) : t.panel2,
          borderRadius: app.shape.br(8),
          border: Border.all(
            color: focused
                ? t.accent
                : (currentValue ? t.accent.withValues(alpha: 0.3) : t.line),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: currentValue
                    ? t.accent.withValues(alpha: 0.2)
                    : app.fade(app.core.tx, 0.08),
                borderRadius: app.shape.br(6),
              ),
              child: Icon(
                _getIconForSetting(settingId),
                size: 18,
                color: currentValue ? t.accent2 : t.dim,
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
                      color: currentValue ? t.accent2 : t.dim,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    currentValue ? 'Enabled' : 'Disabled',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: t.dim),
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
      ),
    );
  }

  Widget _buildDropdownSetting(
    String engineId,
    String settingId,
    SettingConfig setting,
  ) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final currentValue =
        _settingValues[engineId]?[settingId] as int? ??
        (setting.defaultValue as int? ?? 50);

    // Get options from setting config or use defaults (a config-supplied
    // EMPTY list falls back too). The stored value is inserted if missing so
    // nothing silently changes.
    var options = setting.options ?? const <int>[];
    if (options.isEmpty) {
      options = [
        25,
        50,
        75,
        100,
        125,
        150,
        175,
        200,
        250,
        300,
        350,
        400,
        450,
        500,
      ];
    }
    if (!options.contains(currentValue)) {
      options = [...options, currentValue]..sort();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.panel2,
        borderRadius: app.shape.br(8),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: app.fade(app.core.tx, 0.08),
                  borderRadius: app.shape.br(6),
                ),
                child: Icon(
                  _getIconForSetting(settingId),
                  size: 18,
                  color: t.dim,
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
                        color: t.dim,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Select how many results to fetch',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: t.dim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _stepDropdown(
            context,
            value: currentValue,
            options: options,
            labelOf: (v) => '$v results',
            onChanged: (newValue) async {
              await _settings.setValue<int>(engineId, settingId, newValue);
              setState(() {
                _settingValues[engineId] ??= {};
                _settingValues[engineId]![settingId] = newValue;
              });
              widget.onSettingsChanged?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSliderSetting(
    String engineId,
    String settingId,
    SettingConfig setting,
  ) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final currentValue =
        _settingValues[engineId]?[settingId] as int? ??
        (setting.defaultValue as int? ?? 50);

    // Former slider — sliders trap DPAD focus on TV, so 'slider' settings
    // render as a discrete dropdown over the same min..max range.
    final min = setting.min ?? 1;
    final max = setting.max ?? 500;
    final options = _sliderStepOptions(min, max, currentValue);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.panel2,
        borderRadius: app.shape.br(8),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: app.fade(app.core.tx, 0.08),
                  borderRadius: app.shape.br(6),
                ),
                child: Icon(
                  _getIconForSetting(settingId),
                  size: 18,
                  color: t.dim,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  setting.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: t.dim,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _stepDropdown(
            context,
            value: currentValue,
            options: options,
            onChanged: (value) async {
              await _settings.setValue<int>(engineId, settingId, value);
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

  /// Whether the initial settings load has finished — the page's TV entry
  /// focus seeding waits on this (before load the only focusable descendant
  /// is the Reset button at the bottom).
  bool get isLoaded => !_loading;

  // Global TV settings
  int _keywordThreshold = 5;
  int _batchSize = 3;
  int _minTorrentsPerKeyword = 10;
  int _maxKeywords = 5;
  bool _avoidNsfw = true;
  bool _backgroundPrefetchEnabled = true;

  // Per-engine TV settings
  final Map<String, bool> _engineTvEnabled = {};
  final Map<String, int> _smallChannelMax = {};
  final Map<String, int> _largeChannelMax = {};
  final Map<String, int> _quickPlayMax = {};

  @override
  void initState() {
    super.initState();
    LocalEngineStorage.changes.addListener(_loadSettings);
    _loadSettings();
  }

  /// Public method to reload settings (called from parent widget)
  void reload() {
    setState(() {
      _loading = true;
    });
    _loadSettings();
  }

  final _settingsLoadLock = Lock();

  @override
  void dispose() {
    LocalEngineStorage.changes.removeListener(_loadSettings);
    super.dispose();
  }

  Future<void> _loadSettings() =>
      _settingsLoadLock.synchronized(_loadSettingsNow);

  Future<void> _loadSettingsNow() async {
    if (!mounted) return;
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
      _minTorrentsPerKeyword = await _settings.getGlobalMinTorrentsPerKeyword(
        10,
      );
      _maxKeywords = await _settings.getGlobalMaxKeywords(5);
      _avoidNsfw = await _settings.getGlobalAvoidNsfw(true);
      _backgroundPrefetchEnabled = await _settings
          .getGlobalBackgroundPrefetchEnabled();

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
    final t = AppThemeScope.of(context).settings;
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Configure TV mode limits for each search engine',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: t.dim),
            ),
            const SizedBox(height: 16),
            ..._tvEnabledEngines.map((config) => _buildEngineTvCard(config)),
          ] else
            _buildNoTvEnginesMessage(),
        ],
      ),
    );
  }

  Widget _buildGlobalTvSettings() {
    final t = AppThemeScope.of(context).settings;
    return Card(
      elevation: 0,
      color: t.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: t.line),
      ),
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
                    color: t.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.tv_rounded, size: 22, color: t.accent2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Global TV Mode Settings',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Settings that apply to all TV mode searches',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: t.dim),
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

            const SizedBox(height: 12),

            // Background torrent prefetch
            _buildGlobalToggleSetting(
              label: 'Prepare Torrents in Background',
              subtitle:
                  'Add upcoming Real-Debrid and AllDebrid torrents for faster playback',
              value: _backgroundPrefetchEnabled,
              icon: Icons.cloud_sync_rounded,
              onChanged: (value) async {
                await _settings.setGlobalBackgroundPrefetchEnabled(value);
                setState(() {
                  _backgroundPrefetchEnabled = value;
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
    final app = AppThemeScope.of(context);
    final t = app.settings;
    // Former slider — sliders trap DPAD focus on TV, so the global limits
    // render as discrete dropdowns over the same min..max range.
    final options = _sliderStepOptions(min, max, value);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.panel2,
        borderRadius: app.shape.br(8),
        border: Border.all(color: t.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: app.fade(app.core.tx, 0.08),
                  borderRadius: app.shape.br(6),
                ),
                child: Icon(icon, size: 18, color: t.dim),
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
                        color: t.dim,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: t.dim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _stepDropdown(
            context,
            value: value,
            options: options,
            onChanged: onChanged,
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
    final app = AppThemeScope.of(context);
    final t = app.settings;
    // The Switch is the focusable; the ring goes on the row so DPAD focus is
    // unmissable on TV.
    return _FocusHighlight(
      builder: (context, focused) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: value ? t.accent.withValues(alpha: 0.1) : t.panel2,
          borderRadius: app.shape.br(8),
          border: Border.all(
            color: focused
                ? t.accent
                : (value ? t.accent.withValues(alpha: 0.3) : t.line),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: value
                    ? t.accent.withValues(alpha: 0.2)
                    : app.fade(app.core.tx, 0.08),
                borderRadius: app.shape.br(6),
              ),
              child: Icon(icon, size: 18, color: value ? t.accent2 : t.dim),
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
                      color: value ? t.accent2 : t.dim,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: t.dim),
                  ),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineTvCard(EngineConfig config) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final engineId = config.metadata.id;
    final displayName = config.metadata.displayName;
    final iconName = config.metadata.icon;
    final tvMode = config.tvMode!;

    final isEnabled = _engineTvEnabled[engineId] ?? tvMode.enabledDefault;

    return Card(
      elevation: 0,
      color: t.panel,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: app.shape.br(16),
        side: BorderSide(color: t.line),
      ),
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
                        ? t.accent.withValues(alpha: 0.1)
                        : app.fade(app.core.tx, 0.06),
                    borderRadius: app.shape.br(10),
                  ),
                  child: Icon(
                    _getIconForEngine(iconName),
                    size: 22,
                    color: isEnabled ? t.accent2 : t.dim,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isEnabled ? null : t.dim,
                            ),
                      ),
                      Text(
                        isEnabled ? 'TV Mode Enabled' : 'TV Mode Disabled',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: t.dim),
                      ),
                    ],
                  ),
                ),
                // No row container here to light up, so the focus ring wraps
                // the Switch itself.
                _FocusHighlight(
                  builder: (context, focused) => Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: app.shape.br(20),
                      border: Border.all(
                        color: focused ? t.accent : Colors.transparent,
                      ),
                    ),
                    child: Switch(
                      value: isEnabled,
                      onChanged: (value) async {
                        await _settings.setTvEnabled(engineId, value);
                        setState(() {
                          _engineTvEnabled[engineId] = value;
                        });
                        widget.onSettingsChanged?.call();
                      },
                    ),
                  ),
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
                currentValue:
                    _smallChannelMax[engineId] ??
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
                currentValue:
                    _largeChannelMax[engineId] ??
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
    final t = AppThemeScope.of(context).settings;
    // The stored value is inserted if missing so nothing silently changes.
    var options = [10, 25, 50, 75, 100, 150, 200, 250, 300, 400, 500];
    if (!options.contains(currentValue)) {
      options = [...options, currentValue]..sort();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.panel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.line),
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
                        color: t.dim,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: t.dim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _stepDropdown(
            context,
            value: currentValue,
            options: options,
            labelOf: (v) => '$v results',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildNoTvEnginesMessage() {
    final t = AppThemeScope.of(context).settings;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.panel2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: t.dim, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No TV Mode Engines',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: t.dim,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'No search engines with TV mode configuration found.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: t.dim),
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

/// Paints the settings focus ring around [builder]'s output whenever a
/// descendant (e.g. a row's Switch) holds focus, so DPAD focus is visible on
/// TV. The wrapper node itself never takes focus. Snap decoration — no
/// tween — per the TV GPU rule.
class _FocusHighlight extends StatefulWidget {
  const _FocusHighlight({required this.builder});

  final Widget Function(BuildContext context, bool focused) builder;

  @override
  State<_FocusHighlight> createState() => _FocusHighlightState();
}

class _FocusHighlightState extends State<_FocusHighlight> {
  /// Live, never cached: Flutter does not guarantee the falling edge of
  /// `onFocusChange` — popping a route opened with OK restores focus to the
  /// modal scope rather than to a row, so rows that were focus-walked on the
  /// way in are never told they lost it and keep painting as focused. See the
  /// note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode => _ownFocusNode ??= FocusNode();
  bool get _focused => _focusNode.hasFocus;

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      // hasFocus includes descendants, so this fires when the child's
      // Switch/dropdown receives DPAD focus.
      focusNode: _focusNode,
      onFocusChange: (_) => setState(() {}),
      child: widget.builder(context, _focused),
    );
  }
}

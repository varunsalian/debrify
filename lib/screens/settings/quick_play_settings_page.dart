import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/storage_service.dart';
import '../../utils/deovr_utils.dart' as deovr;

/// Quick Play settings page for configuring torrent search quick play behavior.
class QuickPlaySettingsPage extends StatefulWidget {
  const QuickPlaySettingsPage({super.key});

  @override
  State<QuickPlaySettingsPage> createState() => _QuickPlaySettingsPageState();
}

class _QuickPlaySettingsPageState extends State<QuickPlaySettingsPage> {
  bool _loading = true;

  // VR Settings
  String _vrMode = 'disabled'; // disabled, auto, always
  String _vrDefaultScreenType = 'dome';
  String _vrDefaultStereoMode = 'sbs';
  bool _vrAutoDetectFormat = true;
  bool _vrShowDialog = true;

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
    final vrMode = await StorageService.getQuickPlayVrMode();
    final vrDefaultScreenType = await StorageService.getQuickPlayVrDefaultScreenType();
    final vrDefaultStereoMode = await StorageService.getQuickPlayVrDefaultStereoMode();
    final vrAutoDetectFormat = await StorageService.getQuickPlayVrAutoDetectFormat();
    final vrShowDialog = await StorageService.getQuickPlayVrShowDialog();
    final tryMultipleTorrents = await StorageService.getQuickPlayTryMultipleTorrents();
    final maxRetries = await StorageService.getQuickPlayMaxRetries();
    final defaultProvider = await StorageService.getDefaultTorrentProvider();

    if (!mounted) return;

    setState(() {
      _vrMode = vrMode;
      _vrDefaultScreenType = vrDefaultScreenType;
      _vrDefaultStereoMode = vrDefaultStereoMode;
      _vrAutoDetectFormat = vrAutoDetectFormat;
      _vrShowDialog = vrShowDialog;
      _tryMultipleTorrents = tryMultipleTorrents;
      _maxRetries = maxRetries;
      _defaultProvider = defaultProvider;
      _loading = false;
    });
  }

  Future<void> _setVrMode(String mode) async {
    setState(() => _vrMode = mode);
    await StorageService.setQuickPlayVrMode(mode);
  }

  Future<void> _setVrDefaultScreenType(String screenType) async {
    setState(() => _vrDefaultScreenType = screenType);
    await StorageService.setQuickPlayVrDefaultScreenType(screenType);
  }

  Future<void> _setVrDefaultStereoMode(String stereoMode) async {
    setState(() => _vrDefaultStereoMode = stereoMode);
    await StorageService.setQuickPlayVrDefaultStereoMode(stereoMode);
  }

  Future<void> _setVrAutoDetectFormat(bool autoDetect) async {
    setState(() => _vrAutoDetectFormat = autoDetect);
    await StorageService.setQuickPlayVrAutoDetectFormat(autoDetect);
  }

  Future<void> _setVrShowDialog(bool showDialog) async {
    setState(() => _vrShowDialog = showDialog);
    await StorageService.setQuickPlayVrShowDialog(showDialog);
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
            // VR Playback section (Android only)
            if (Platform.isAndroid) ...[
              _buildVrSection(context),
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

  Widget _buildVrSection(BuildContext context) {
    final theme = Theme.of(context);
    final isVrEnabled = _vrMode != 'disabled';

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
                  Icons.vrpano,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'VR Playback',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // VR Player Mode
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VR Player Mode',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose when to use DeoVR for playback',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 12),
                _buildVrModeOption(
                  context,
                  value: 'disabled',
                  title: 'Disabled',
                  subtitle: 'Always use regular player',
                  icon: Icons.tv,
                ),
                _buildVrModeOption(
                  context,
                  value: 'auto',
                  title: 'Auto-detect',
                  subtitle: 'Use DeoVR when VR content is detected',
                  icon: Icons.auto_awesome,
                  recommended: true,
                ),
                _buildVrModeOption(
                  context,
                  value: 'always',
                  title: 'Always use DeoVR',
                  subtitle: 'Force all Quick Play to open in DeoVR',
                  icon: Icons.vrpano,
                ),
              ],
            ),
          ),

          // VR Format Settings (only visible when VR is enabled)
          if (isVrEnabled) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Default VR Format',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Used when format cannot be detected from filename',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Screen Type dropdown
                  _buildDropdownSetting(
                    context,
                    label: 'Screen Type',
                    value: _vrDefaultScreenType,
                    items: deovr.screenTypeLabels,
                    onChanged: _setVrDefaultScreenType,
                  ),
                  const SizedBox(height: 12),

                  // Stereo Mode dropdown
                  _buildDropdownSetting(
                    context,
                    label: 'Stereo Mode',
                    value: _vrDefaultStereoMode,
                    items: deovr.stereoModeLabels,
                    onChanged: _setVrDefaultStereoMode,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Checkboxes
            _buildCheckboxTile(
              context,
              title: 'Auto-detect format from filename',
              subtitle: 'Parse filename for VR markers (180, 360, SBS, etc.)',
              value: _vrAutoDetectFormat,
              onChanged: _setVrAutoDetectFormat,
            ),
            _buildCheckboxTile(
              context,
              title: 'Show format selection dialog',
              subtitle: 'Confirm VR format before launching DeoVR',
              value: _vrShowDialog,
              onChanged: _setVrShowDialog,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVrModeOption(
    BuildContext context, {
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    bool recommended = false,
  }) {
    final theme = Theme.of(context);
    final isSelected = _vrMode == value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _setVrMode(value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Radio<String>(
                value: value,
                groupValue: _vrMode,
                onChanged: (v) => _setVrMode(v!),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Recommended',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
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
      ),
    );
  }

  Widget _buildDropdownSetting(
    BuildContext context, {
    required String label,
    required String value,
    required Map<String, String> items,
    required Function(String) onChanged,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                items: items.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            e.value,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ),
      ],
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

import 'package:flutter/material.dart';
import '../../models/debrify_tv_channel_record.dart';
import '../../models/stremio_tv/stremio_tv_channel.dart';
import '../../services/debrify_tv_repository.dart';
import '../../services/storage_service.dart';
import '../stremio_tv/stremio_tv_service.dart';

class StartupSettingsPage extends StatefulWidget {
  const StartupSettingsPage({super.key});

  @override
  State<StartupSettingsPage> createState() => _StartupSettingsPageState();
}

class _StartupSettingsPageState extends State<StartupSettingsPage> {
  bool _loading = true;
  bool _autoLaunchEnabled = false;
  String _startupMode =
      'channel'; // 'channel', 'stremio_tv', 'playlist', or 'continue_watching'
  String? _selectedChannelId; // "random" or actual channelId
  String? _selectedStremioTvChannelId; // "random" or actual channelId
  String? _selectedPlaylistItemId; // playlist item dedupe key
  String? _selectedContinueWatchingItemId; // continue watching imdbId
  List<DebrifyTvChannelRecord> _channels = [];
  List<StremioTvChannel> _stremioTvChannels = [];
  List<Map<String, dynamic>> _playlistItems = [];
  List<Map<String, dynamic>> _continueWatchingItems = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
    });

    try {
      // Fetch channels and playlist items
      final channels = await DebrifyTvRepository.instance.fetchAllChannels();
      final stremioTvChannels = await StremioTvService.instance
          .discoverChannels();
      final playlistItems = await StorageService.getPlaylistItemsRaw();
      final continueWatchingItems = _validContinueWatchingItems(
        await StorageService.getContinueWatchingItems(),
      );

      // Load settings
      final autoLaunchEnabled =
          await StorageService.getStartupAutoLaunchEnabled();
      final startupMode = await StorageService.getStartupMode();
      final selectedChannelId = await StorageService.getStartupChannelId();
      final selectedStremioTvChannelId =
          await StorageService.getStartupStremioTvChannelId();
      final selectedPlaylistItemId =
          await StorageService.getStartupPlaylistItemId();
      final selectedContinueWatchingItemId =
          await StorageService.getStartupContinueWatchingItemId();
      final availableModes = _availableModes(
        hasDebrifyChannels: channels.isNotEmpty,
        hasStremioTvChannels: stremioTvChannels.isNotEmpty,
        hasPlaylistItems: playlistItems.isNotEmpty,
        hasContinueWatchingItems: continueWatchingItems.isNotEmpty,
      );
      final resolvedMode = _resolveStartupMode(startupMode, availableModes);
      final resolvedChannelId = _resolveDebrifyChannelId(
        selectedChannelId,
        channels,
      );
      final resolvedStremioTvChannelId = _resolveStremioTvChannelId(
        selectedStremioTvChannelId,
        stremioTvChannels,
      );
      final resolvedPlaylistItemId = _resolvePlaylistItemId(
        selectedPlaylistItemId,
        playlistItems,
      );
      final resolvedContinueWatchingItemId = _resolveContinueWatchingItemId(
        selectedContinueWatchingItemId,
        continueWatchingItems,
      );
      await _persistResolvedStartupSettings(
        savedMode: startupMode,
        resolvedMode: resolvedMode,
        hasDebrifyChannels: channels.isNotEmpty,
        hasStremioTvChannels: stremioTvChannels.isNotEmpty,
        hasPlaylistItems: playlistItems.isNotEmpty,
        hasContinueWatchingItems: continueWatchingItems.isNotEmpty,
        savedChannelId: selectedChannelId,
        resolvedChannelId: resolvedChannelId,
        savedPlaylistItemId: selectedPlaylistItemId,
        resolvedPlaylistItemId: resolvedPlaylistItemId,
        savedContinueWatchingItemId: selectedContinueWatchingItemId,
        resolvedContinueWatchingItemId: resolvedContinueWatchingItemId,
      );

      setState(() {
        _channels = channels;
        _stremioTvChannels = stremioTvChannels;
        _playlistItems = playlistItems;
        _continueWatchingItems = continueWatchingItems;
        _autoLaunchEnabled = autoLaunchEnabled;
        _startupMode = resolvedMode;
        _selectedChannelId = resolvedChannelId;
        _selectedStremioTvChannelId = resolvedStremioTvChannelId;
        _selectedPlaylistItemId = resolvedPlaylistItemId;
        _selectedContinueWatchingItemId = resolvedContinueWatchingItemId;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load settings: $e')));
      }
    }
  }

  Future<void> _toggleAutoLaunch(bool value) async {
    try {
      await StorageService.setStartupAutoLaunchEnabled(value);
      setState(() {
        _autoLaunchEnabled = value;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save setting: $e')));
      }
    }
  }

  Future<void> _selectChannel(String? channelId) async {
    try {
      await StorageService.setStartupChannelId(channelId);
      setState(() {
        _selectedChannelId = channelId ?? 'random';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save channel selection: $e')),
        );
      }
    }
  }

  Future<void> _selectStremioTvChannel(String? channelId) async {
    try {
      await StorageService.setStartupStremioTvChannelId(channelId);
      setState(() {
        _selectedStremioTvChannelId = channelId ?? 'random';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save Stremio TV selection: $e')),
        );
      }
    }
  }

  Future<void> _selectMode(String mode) async {
    try {
      if (mode == 'continue_watching' &&
          _selectedContinueWatchingItemId == null &&
          _continueWatchingItems.isNotEmpty) {
        _selectedContinueWatchingItemId =
            _continueWatchingItems.first['imdbId'] as String?;
        await StorageService.setStartupContinueWatchingItemId(
          _selectedContinueWatchingItemId,
        );
      }
      await StorageService.setStartupMode(mode);
      setState(() {
        _startupMode = mode;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save mode selection: $e')),
        );
      }
    }
  }

  Future<void> _selectPlaylistItem(String? itemId) async {
    try {
      await StorageService.setStartupPlaylistItemId(itemId);
      setState(() {
        _selectedPlaylistItemId = itemId;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save playlist selection: $e')),
        );
      }
    }
  }

  Future<void> _selectContinueWatchingItem(String? itemId) async {
    try {
      await StorageService.setStartupContinueWatchingItemId(itemId);
      setState(() {
        _selectedContinueWatchingItemId = itemId;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save Continue Watching selection: $e'),
          ),
        );
      }
    }
  }

  List<String> _availableModes({
    required bool hasDebrifyChannels,
    required bool hasStremioTvChannels,
    required bool hasPlaylistItems,
    required bool hasContinueWatchingItems,
  }) {
    final modes = <String>[];
    if (hasDebrifyChannels) modes.add('channel');
    if (hasStremioTvChannels) modes.add('stremio_tv');
    if (hasPlaylistItems) modes.add('playlist');
    if (hasContinueWatchingItems) modes.add('continue_watching');
    return modes;
  }

  String _resolveStartupMode(String savedMode, List<String> availableModes) {
    if (availableModes.isEmpty) return 'channel';
    if (availableModes.contains(savedMode)) return savedMode;
    return availableModes.first;
  }

  String _resolveDebrifyChannelId(
    String? channelId,
    List<DebrifyTvChannelRecord> channels,
  ) {
    if (channelId == null || channelId.isEmpty || channelId == 'random') {
      return 'random';
    }
    final exists = channels.any((channel) => channel.channelId == channelId);
    return exists ? channelId : 'random';
  }

  String _resolveStremioTvChannelId(
    String? channelId,
    List<StremioTvChannel> channels,
  ) {
    if (channelId == null || channelId.isEmpty || channelId == 'random') {
      return 'random';
    }
    final exists = channels.any((channel) => channel.id == channelId);
    return exists ? channelId : 'random';
  }

  String? _resolvePlaylistItemId(
    String? itemId,
    List<Map<String, dynamic>> playlistItems,
  ) {
    if (itemId == null || itemId.isEmpty) return null;
    final exists = playlistItems.any(
      (item) => StorageService.computePlaylistDedupeKey(item) == itemId,
    );
    return exists ? itemId : null;
  }

  List<Map<String, dynamic>> _validContinueWatchingItems(
    List<Map<String, dynamic>> items,
  ) {
    return items
        .where((item) => (item['imdbId'] as String?)?.isNotEmpty == true)
        .toList();
  }

  String? _resolveContinueWatchingItemId(
    String? itemId,
    List<Map<String, dynamic>> continueWatchingItems,
  ) {
    if (continueWatchingItems.isEmpty) return null;
    if (itemId == null || itemId.isEmpty) {
      return continueWatchingItems.first['imdbId'] as String?;
    }
    final exists = continueWatchingItems.any(
      (item) => item['imdbId'] == itemId,
    );
    return exists ? itemId : continueWatchingItems.first['imdbId'] as String?;
  }

  Future<void> _persistResolvedStartupSettings({
    required String savedMode,
    required String resolvedMode,
    required bool hasDebrifyChannels,
    required bool hasStremioTvChannels,
    required bool hasPlaylistItems,
    required bool hasContinueWatchingItems,
    required String? savedChannelId,
    required String resolvedChannelId,
    required String? savedPlaylistItemId,
    required String? resolvedPlaylistItemId,
    required String? savedContinueWatchingItemId,
    required String? resolvedContinueWatchingItemId,
  }) async {
    final writes = <Future<void>>[];

    if (_shouldPersistResolvedMode(
      savedMode: savedMode,
      resolvedMode: resolvedMode,
      hasDebrifyChannels: hasDebrifyChannels,
      hasStremioTvChannels: hasStremioTvChannels,
      hasPlaylistItems: hasPlaylistItems,
      hasContinueWatchingItems: hasContinueWatchingItems,
    )) {
      writes.add(StorageService.setStartupMode(resolvedMode));
    }

    if (savedChannelId != null &&
        savedChannelId != 'random' &&
        resolvedChannelId == 'random') {
      writes.add(StorageService.setStartupChannelId(null));
    }

    if (savedPlaylistItemId != null && resolvedPlaylistItemId == null) {
      writes.add(StorageService.setStartupPlaylistItemId(null));
    }

    if (savedContinueWatchingItemId != resolvedContinueWatchingItemId) {
      writes.add(
        StorageService.setStartupContinueWatchingItemId(
          resolvedContinueWatchingItemId,
        ),
      );
    }

    if (writes.isNotEmpty) {
      await Future.wait(writes);
    }
  }

  bool _shouldPersistResolvedMode({
    required String savedMode,
    required String resolvedMode,
    required bool hasDebrifyChannels,
    required bool hasStremioTvChannels,
    required bool hasPlaylistItems,
    required bool hasContinueWatchingItems,
  }) {
    if (savedMode == resolvedMode) return false;

    switch (savedMode) {
      case 'channel':
        return !hasDebrifyChannels;
      case 'playlist':
        return !hasPlaylistItems;
      case 'continue_watching':
        return !hasContinueWatchingItems;
      case 'stremio_tv':
        return !hasStremioTvChannels &&
            _modeHasAvailableContent(
              resolvedMode,
              hasDebrifyChannels: hasDebrifyChannels,
              hasStremioTvChannels: hasStremioTvChannels,
              hasPlaylistItems: hasPlaylistItems,
              hasContinueWatchingItems: hasContinueWatchingItems,
            );
      default:
        return true;
    }
  }

  bool _modeHasAvailableContent(
    String mode, {
    required bool hasDebrifyChannels,
    required bool hasStremioTvChannels,
    required bool hasPlaylistItems,
    required bool hasContinueWatchingItems,
  }) {
    switch (mode) {
      case 'channel':
        return hasDebrifyChannels;
      case 'stremio_tv':
        return hasStremioTvChannels;
      case 'playlist':
        return hasPlaylistItems;
      case 'continue_watching':
        return hasContinueWatchingItems;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Startup Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final hasChannels = _channels.isNotEmpty;
    final hasStremioTvChannels = _stremioTvChannels.isNotEmpty;
    final hasPlaylistItems = _playlistItems.isNotEmpty;
    final hasContinueWatchingItems = _continueWatchingItems.isNotEmpty;
    final hasAnyContent =
        hasChannels ||
        hasStremioTvChannels ||
        hasPlaylistItems ||
        hasContinueWatchingItems;

    return Scaffold(
      appBar: AppBar(title: const Text('Startup Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(
                      Icons.rocket_launch_rounded,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Auto-Launch on Startup',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Automatically start playing selected content when the app launches',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Main settings card
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: Icon(
                      Icons.play_circle_rounded,
                      color: hasAnyContent
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                    ),
                    title: const Text('START ON LAUNCH'),
                    subtitle: Text(
                      hasAnyContent
                          ? 'Auto-play when app launches'
                          : 'Create channels, add playlist items, or watch something to enable',
                      style: TextStyle(
                        color: hasAnyContent
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.error,
                      ),
                    ),
                    value: _autoLaunchEnabled,
                    onChanged: hasAnyContent
                        ? (value) => _toggleAutoLaunch(value)
                        : null,
                  ),

                  // Mode and content selection (shown when toggle is ON)
                  if (_autoLaunchEnabled && hasAnyContent) ...[
                    const Divider(height: 1),

                    // Mode selector (Channel vs Playlist)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _startupMode,
                        decoration: InputDecoration(
                          labelText: 'Launch mode',
                          prefixIcon: Icon(
                            _startupMode == 'channel'
                                ? Icons.tv_rounded
                                : _startupMode == 'stremio_tv'
                                ? Icons.live_tv_rounded
                                : _startupMode == 'continue_watching'
                                ? Icons.play_circle_fill_rounded
                                : Icons.playlist_play_rounded,
                            color: theme.colorScheme.primary,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceVariant
                              .withOpacity(0.3),
                        ),
                        items: [
                          if (hasChannels)
                            const DropdownMenuItem<String>(
                              value: 'channel',
                              child: Text('Debrify TV Channel'),
                            ),
                          if (hasStremioTvChannels)
                            const DropdownMenuItem<String>(
                              value: 'stremio_tv',
                              child: Text('Stremio TV Channel'),
                            ),
                          if (hasPlaylistItems)
                            const DropdownMenuItem<String>(
                              value: 'playlist',
                              child: Text('Playlist Item'),
                            ),
                          if (hasContinueWatchingItems)
                            const DropdownMenuItem<String>(
                              value: 'continue_watching',
                              child: Text('Continue Watching Item'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) _selectMode(value);
                        },
                      ),
                    ),

                    // Channel selection (shown when mode is 'channel')
                    if (_startupMode == 'channel' && hasChannels)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _selectedChannelId,
                          decoration: InputDecoration(
                            labelText: 'Select channel',
                            prefixIcon: Icon(
                              _selectedChannelId == 'random'
                                  ? Icons.shuffle_rounded
                                  : Icons.tv_rounded,
                              color: theme.colorScheme.primary,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceVariant
                                .withOpacity(0.3),
                          ),
                          items: [
                            // Random option first
                            const DropdownMenuItem<String>(
                              value: 'random',
                              child: Text('Random Channel'),
                            ),
                            // Then all channels
                            ..._channels.map((channel) {
                              return DropdownMenuItem<String>(
                                value: channel.channelId,
                                child: Text(
                                  channel.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                          ],
                          onChanged: (value) => _selectChannel(value),
                        ),
                      ),

                    if (_startupMode == 'stremio_tv' && hasStremioTvChannels)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _selectedStremioTvChannelId,
                          decoration: InputDecoration(
                            labelText: 'Select Stremio TV channel',
                            prefixIcon: Icon(
                              _selectedStremioTvChannelId == 'random'
                                  ? Icons.shuffle_rounded
                                  : Icons.live_tv_rounded,
                              color: theme.colorScheme.primary,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceVariant
                                .withOpacity(0.3),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: 'random',
                              child: Text('Random Stremio TV Channel'),
                            ),
                            ..._stremioTvChannels.map((channel) {
                              return DropdownMenuItem<String>(
                                value: channel.id,
                                child: Text(
                                  channel.displayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                          ],
                          onChanged: (value) => _selectStremioTvChannel(value),
                        ),
                      ),

                    // Playlist item selection (shown when mode is 'playlist')
                    if (_startupMode == 'playlist' && hasPlaylistItems)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _selectedPlaylistItemId,
                          decoration: InputDecoration(
                            labelText: 'Select playlist item',
                            prefixIcon: Icon(
                              Icons.playlist_play_rounded,
                              color: theme.colorScheme.primary,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceVariant
                                .withOpacity(0.3),
                          ),
                          items: _playlistItems.map((item) {
                            final dedupeKey =
                                StorageService.computePlaylistDedupeKey(item);
                            final title =
                                (item['title'] as String?) ?? 'Unknown';
                            return DropdownMenuItem<String>(
                              value: dedupeKey,
                              child: Text(
                                title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (value) => _selectPlaylistItem(value),
                        ),
                      ),

                    if (_startupMode == 'continue_watching' &&
                        hasContinueWatchingItems)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _selectedContinueWatchingItemId,
                          decoration: InputDecoration(
                            labelText: 'Select Continue Watching item',
                            prefixIcon: Icon(
                              Icons.play_circle_fill_rounded,
                              color: theme.colorScheme.primary,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceVariant
                                .withOpacity(0.3),
                          ),
                          items: _continueWatchingItems.map((item) {
                            final imdbId = item['imdbId'] as String;
                            final title =
                                (item['title'] as String?) ?? 'Unknown';
                            return DropdownMenuItem<String>(
                              value: imdbId,
                              child: Text(
                                title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (value) =>
                              _selectContinueWatchingItem(value),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Info card
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _startupMode == 'channel'
                            ? 'When enabled, the app will automatically navigate to Debrify TV and start playing your selected channel on startup. This skips the normal home screen.'
                            : _startupMode == 'stremio_tv'
                            ? 'When enabled, the app will automatically navigate to Stremio TV and start playing your selected channel on startup. This skips the normal home screen.'
                            : _startupMode == 'continue_watching'
                            ? 'When enabled, the app will automatically quick play your selected Continue Watching item on startup. This skips the normal home screen.'
                            : 'When enabled, the app will automatically start playing your selected playlist item on startup. This skips the normal home screen.',
                        style: theme.textTheme.bodyMedium?.copyWith(
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
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../models/debrify_tv_channel_record.dart';
import '../../services/debrify_tv_repository.dart';
import '../../services/storage_service.dart';

class StartupSettingsPage extends StatefulWidget {
  const StartupSettingsPage({super.key});

  @override
  State<StartupSettingsPage> createState() => _StartupSettingsPageState();
}

class _StartupSettingsPageState extends State<StartupSettingsPage> {
  bool _loading = true;
  bool _autoLaunchEnabled = false;
  String _startupMode = 'channel'; // 'channel' or 'playlist'
  String? _selectedChannelId; // "random" or actual channelId
  String? _selectedPlaylistItemId; // playlist item dedupe key
  List<DebrifyTvChannelRecord> _channels = [];
  List<Map<String, dynamic>> _playlistItems = [];

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
      final playlistItems = await StorageService.getPlaylistItemsRaw();

      // Load settings
      final autoLaunchEnabled = await StorageService.getStartupAutoLaunchEnabled();
      final startupMode = await StorageService.getStartupMode();
      final selectedChannelId = await StorageService.getStartupChannelId();
      final selectedPlaylistItemId = await StorageService.getStartupPlaylistItemId();

      setState(() {
        _channels = channels;
        _playlistItems = playlistItems;
        _autoLaunchEnabled = autoLaunchEnabled;
        _startupMode = startupMode;
        _selectedChannelId = selectedChannelId ?? 'random';
        _selectedPlaylistItemId = selectedPlaylistItemId;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load settings: $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setting: $e')),
        );
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

  Future<void> _selectMode(String mode) async {
    try {
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Startup Settings'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final theme = Theme.of(context);
    final hasChannels = _channels.isNotEmpty;
    final hasPlaylistItems = _playlistItems.isNotEmpty;
    final hasAnyContent = hasChannels || hasPlaylistItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Startup Settings'),
      ),
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
                            'Automatically start playing a channel or playlist item when the app launches',
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
                          : 'Create channels or add playlist items to enable',
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
                                : Icons.playlist_play_rounded,
                            color: theme.colorScheme.primary,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                        ),
                        items: [
                          if (hasChannels)
                            const DropdownMenuItem<String>(
                              value: 'channel',
                              child: Text('Debrify TV Channel'),
                            ),
                          if (hasPlaylistItems)
                            const DropdownMenuItem<String>(
                              value: 'playlist',
                              child: Text('Playlist Item'),
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
                            fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
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
                            fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                          ),
                          items: _playlistItems.map((item) {
                            final dedupeKey = StorageService.computePlaylistDedupeKey(item);
                            final title = (item['title'] as String?) ?? 'Unknown';
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

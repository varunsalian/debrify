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
  String? _selectedChannelId; // "random" or actual channelId
  List<DebrifyTvChannelRecord> _channels = [];

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
      // Fetch channels
      final channels = await DebrifyTvRepository.instance.fetchAllChannels();

      // Load settings
      final autoLaunchEnabled = await StorageService.getStartupAutoLaunchEnabled();
      final selectedChannelId = await StorageService.getStartupChannelId();

      setState(() {
        _channels = channels;
        _autoLaunchEnabled = autoLaunchEnabled;
        _selectedChannelId = selectedChannelId ?? 'random';
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
                            'Auto-Launch Debrify TV',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Automatically start playing a channel when the app launches',
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
                      color: hasChannels
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                    ),
                    title: const Text('START DEBRIFY TV ON STARTUP'),
                    subtitle: Text(
                      hasChannels
                          ? 'Auto-play when app launches'
                          : 'Create channels in Debrify TV to enable',
                      style: TextStyle(
                        color: hasChannels
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.error,
                      ),
                    ),
                    value: _autoLaunchEnabled,
                    onChanged: hasChannels
                        ? (value) => _toggleAutoLaunch(value)
                        : null,
                  ),

                  // Channel selection (shown when toggle is ON)
                  if (_autoLaunchEnabled && hasChannels) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedChannelId,
                        decoration: InputDecoration(
                          labelText: 'Channel to launch on startup',
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
                        'When enabled, the app will automatically navigate to Debrify TV and start playing your selected channel on startup. This skips the normal home screen.',
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

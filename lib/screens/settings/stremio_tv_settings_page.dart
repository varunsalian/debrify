import 'package:flutter/material.dart';
import '../../services/storage_service.dart';

class StremioTvSettingsPage extends StatefulWidget {
  const StremioTvSettingsPage({super.key});

  @override
  State<StremioTvSettingsPage> createState() => _StremioTvSettingsPageState();
}

class _StremioTvSettingsPageState extends State<StremioTvSettingsPage> {
  bool _loading = true;
  int _rotationMinutes = 90;
  int _seriesRotationMinutes = 45;
  bool _autoRefresh = true;
  String _preferredQuality = 'auto';
  String _debridProvider = 'auto';
  int _maxStartPercent = -1; // -1 = no limit, 0 = beginning, 10/20/30/50 = cap
  bool _hideNowPlaying = false;
  List<MapEntry<String, String>> _availableProviders = [];
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);

    try {
      final rotationMinutes = await StorageService.getStremioTvRotationMinutes();
      final seriesRotationMinutes = await StorageService.getStremioTvSeriesRotationMinutes();
      final autoRefresh = await StorageService.getStremioTvAutoRefresh();
      final preferredQuality = await StorageService.getStremioTvPreferredQuality();
      final debridProvider = await StorageService.getStremioTvDebridProvider();
      final maxStartPercent = await StorageService.getStremioTvMaxStartPercent();
      final hideNowPlaying = await StorageService.getStremioTvHideNowPlaying();

      // Detect which providers are configured
      final providers = <MapEntry<String, String>>[];
      final rdKey = await StorageService.getApiKey();
      if (rdKey != null && rdKey.isNotEmpty) {
        providers.add(const MapEntry('realdebrid', 'Real-Debrid'));
      }
      final tbKey = await StorageService.getTorboxApiKey();
      if (tbKey != null && tbKey.isNotEmpty) {
        providers.add(const MapEntry('torbox', 'TorBox'));
      }
      final pikpakEnabled = await StorageService.getPikPakEnabled();
      if (pikpakEnabled) {
        providers.add(const MapEntry('pikpak', 'PikPak'));
      }

      setState(() {
        _rotationMinutes = rotationMinutes;
        _seriesRotationMinutes = seriesRotationMinutes;
        _autoRefresh = autoRefresh;
        _preferredQuality = preferredQuality;
        _debridProvider = debridProvider;
        _maxStartPercent = maxStartPercent;
        _hideNowPlaying = hideNowPlaying;
        _availableProviders = providers;
        // Reset to auto if saved provider is no longer configured
        if (_debridProvider != 'auto' &&
            !providers.any((p) => p.key == _debridProvider)) {
          _debridProvider = 'auto';
          StorageService.setStremioTvDebridProvider('auto');
        }
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load settings: $e')),
        );
      }
    }
  }

  Future<void> _setRotationMinutes(int value) async {
    try {
      await StorageService.setStremioTvRotationMinutes(value);
      setState(() => _rotationMinutes = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setting: $e')),
        );
      }
    }
  }

  Future<void> _setSeriesRotationMinutes(int value) async {
    try {
      await StorageService.setStremioTvSeriesRotationMinutes(value);
      setState(() => _seriesRotationMinutes = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setting: $e')),
        );
      }
    }
  }

  Future<void> _setAutoRefresh(bool value) async {
    try {
      await StorageService.setStremioTvAutoRefresh(value);
      setState(() => _autoRefresh = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setting: $e')),
        );
      }
    }
  }

  Future<void> _setPreferredQuality(String value) async {
    try {
      await StorageService.setStremioTvPreferredQuality(value);
      setState(() => _preferredQuality = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setting: $e')),
        );
      }
    }
  }

  Future<void> _setMaxStartPercent(int value) async {
    try {
      await StorageService.setStremioTvMaxStartPercent(value);
      setState(() => _maxStartPercent = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setting: $e')),
        );
      }
    }
  }

  Future<void> _setHideNowPlaying(bool value) async {
    try {
      await StorageService.setStremioTvHideNowPlaying(value);
      setState(() => _hideNowPlaying = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setting: $e')),
        );
      }
    }
  }

  Future<void> _setDebridProvider(String value) async {
    try {
      await StorageService.setStremioTvDebridProvider(value);
      setState(() => _debridProvider = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setting: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Stremio TV Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.smart_display_rounded,
                            size: 32,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Stremio TV',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Configure how Stremio addon catalogs are displayed as TV channels.',
                                  style: theme.textTheme.bodySmall?.copyWith(
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
                  // Settings card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Channel Settings',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Rotation interval dropdown
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Rotation Interval',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    Text(
                                      'How often the "now playing" item changes',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              DropdownButton<int>(
                                value: _rotationMinutes,
                                items: const [
                                  DropdownMenuItem(
                                    value: 30,
                                    child: Text('30 min'),
                                  ),
                                  DropdownMenuItem(
                                    value: 60,
                                    child: Text('1 hour'),
                                  ),
                                  DropdownMenuItem(
                                    value: 90,
                                    child: Text('1.5 hours'),
                                  ),
                                  DropdownMenuItem(
                                    value: 120,
                                    child: Text('2 hours'),
                                  ),
                                  DropdownMenuItem(
                                    value: 180,
                                    child: Text('3 hours'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    _setRotationMinutes(value);
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Series rotation interval dropdown
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Series Rotation Interval',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    Text(
                                      'How often the episode changes on series channels',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              DropdownButton<int>(
                                value: _seriesRotationMinutes,
                                items: const [
                                  DropdownMenuItem(
                                    value: 15,
                                    child: Text('15 min'),
                                  ),
                                  DropdownMenuItem(
                                    value: 30,
                                    child: Text('30 min'),
                                  ),
                                  DropdownMenuItem(
                                    value: 45,
                                    child: Text('45 min'),
                                  ),
                                  DropdownMenuItem(
                                    value: 60,
                                    child: Text('1 hour'),
                                  ),
                                  DropdownMenuItem(
                                    value: 90,
                                    child: Text('1.5 hours'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    _setSeriesRotationMinutes(value);
                                  }
                                },
                              ),
                            ],
                          ),
                          const Divider(height: 32),
                          // Auto-refresh toggle
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Auto-refresh'),
                            subtitle: const Text(
                              'Automatically refresh progress bars and detect rotation changes',
                            ),
                            value: _autoRefresh,
                            onChanged: _setAutoRefresh,
                          ),
                          const Divider(height: 32),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Hide Currently Playing'),
                            subtitle: const Text(
                              'Blur poster and hide details for a surprise when playing',
                            ),
                            value: _hideNowPlaying,
                            onChanged: _setHideNowPlaying,
                          ),
                          const Divider(height: 32),
                          // Preferred quality dropdown
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Preferred Quality',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    Text(
                                      'Prioritize streams matching this quality',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              DropdownButton<String>(
                                value: _preferredQuality,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'auto',
                                    child: Text('Auto'),
                                  ),
                                  DropdownMenuItem(
                                    value: '720p',
                                    child: Text('720p'),
                                  ),
                                  DropdownMenuItem(
                                    value: '1080p',
                                    child: Text('1080p'),
                                  ),
                                  DropdownMenuItem(
                                    value: '2160p',
                                    child: Text('4K'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    _setPreferredQuality(value);
                                  }
                                },
                              ),
                            ],
                          ),
                          const Divider(height: 32),
                          // Start position dropdown
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Start Position',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    Text(
                                      'Where to begin playback within the current slot',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              DropdownButton<int>(
                                value: _maxStartPercent,
                                items: const [
                                  DropdownMenuItem(
                                    value: 0,
                                    child: Text('Beginning'),
                                  ),
                                  DropdownMenuItem(
                                    value: 10,
                                    child: Text('Max 10%'),
                                  ),
                                  DropdownMenuItem(
                                    value: 20,
                                    child: Text('Max 20%'),
                                  ),
                                  DropdownMenuItem(
                                    value: 30,
                                    child: Text('Max 30%'),
                                  ),
                                  DropdownMenuItem(
                                    value: 50,
                                    child: Text('Max 50%'),
                                  ),
                                  DropdownMenuItem(
                                    value: -1,
                                    child: Text('Slot progress'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    _setMaxStartPercent(value);
                                  }
                                },
                              ),
                            ],
                          ),
                          if (_availableProviders.isNotEmpty) ...[
                            const Divider(height: 32),
                            // Debrid provider dropdown
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Debrid Provider',
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                      Text(
                                        'Which provider to use for torrent streams',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                DropdownButton<String>(
                                  value: _debridProvider,
                                  items: [
                                    DropdownMenuItem(
                                      value: 'auto',
                                      child: Text(
                                        'Auto (${_availableProviders.first.value})',
                                      ),
                                    ),
                                    ..._availableProviders
                                        .map((p) => DropdownMenuItem(
                                              value: p.key,
                                              child: Text(p.value),
                                            )),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      _setDebridProvider(value);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Info card
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Tips',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '- Each Stremio addon catalog becomes a TV channel\n'
                            '- The "now playing" item rotates deterministically based on time\n'
                            '- Start Position controls where playback begins within the slot\n'
                            '- Long press a channel to favorite/unfavorite it\n'
                            '- Favorites appear pinned at the top and on the home screen\n'
                            '- Install more catalog addons (like Cinemeta) for more channels\n'
                            '- Manage local catalogs from the 3-dot menu on the Stremio TV screen',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
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

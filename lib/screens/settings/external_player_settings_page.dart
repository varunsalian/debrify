import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/external_player.dart';
import '../../services/external_player_service.dart';
import '../../services/storage_service.dart';

class ExternalPlayerSettingsPage extends StatefulWidget {
  const ExternalPlayerSettingsPage({super.key});

  @override
  State<ExternalPlayerSettingsPage> createState() =>
      _ExternalPlayerSettingsPageState();
}

class _ExternalPlayerSettingsPageState
    extends State<ExternalPlayerSettingsPage> {
  bool _loading = true;
  ExternalPlayer _selectedPlayer = ExternalPlayer.systemDefault;
  Map<ExternalPlayer, bool> _installedPlayers = {};

  // Custom App state
  String? _customAppPath;
  String? _customAppName;

  // Custom Command state
  String? _customCommand;
  final TextEditingController _commandController = TextEditingController();
  String? _commandError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
    });

    try {
      // Load installed players
      final installed = await ExternalPlayerService.detectInstalledPlayers();

      // Load current settings
      final preferredKey = await StorageService.getPreferredExternalPlayer();
      final customAppPath = await StorageService.getCustomExternalPlayerPath();
      final customAppName = await StorageService.getCustomExternalPlayerName();
      final customCommand = await StorageService.getCustomExternalPlayerCommand();

      _commandController.text = customCommand ?? '';

      setState(() {
        _installedPlayers = installed;
        _selectedPlayer = ExternalPlayerExtension.fromStorageKey(preferredKey);
        _customAppPath = customAppPath;
        _customAppName = customAppName;
        _customCommand = customCommand;
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

  Future<void> _selectPlayer(ExternalPlayer player) async {
    try {
      await StorageService.setPreferredExternalPlayer(player.storageKey);
      setState(() {
        _selectedPlayer = player;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setting: $e')),
        );
      }
    }
  }

  Future<void> _browseForCustomApp() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['app'],
        dialogTitle: 'Select Video Player Application',
      );

      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        if (path != null) {
          // Extract app name from path
          final appName = path.split('/').last.replaceAll('.app', '');

          await StorageService.setCustomExternalPlayerPath(path);
          await StorageService.setCustomExternalPlayerName(appName);
          await StorageService.setPreferredExternalPlayer('custom_app');

          setState(() {
            _customAppPath = path;
            _customAppName = appName;
            _selectedPlayer = ExternalPlayer.customApp;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select application: $e')),
        );
      }
    }
  }

  Future<void> _clearCustomApp() async {
    try {
      await StorageService.setCustomExternalPlayerPath(null);
      await StorageService.setCustomExternalPlayerName(null);

      // If custom app was selected, switch to system default
      if (_selectedPlayer == ExternalPlayer.customApp) {
        await StorageService.setPreferredExternalPlayer('system_default');
        setState(() {
          _selectedPlayer = ExternalPlayer.systemDefault;
        });
      }

      setState(() {
        _customAppPath = null;
        _customAppName = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear custom app: $e')),
        );
      }
    }
  }

  Future<void> _saveCustomCommand() async {
    final command = _commandController.text.trim();

    // Validate command
    final validation = ExternalPlayerService.validateCustomCommand(command);
    if (!validation.isValid) {
      setState(() {
        _commandError = validation.errorMessage;
      });
      return;
    }

    try {
      await StorageService.setCustomExternalPlayerCommand(command);
      await StorageService.setPreferredExternalPlayer('custom_command');

      setState(() {
        _customCommand = command;
        _commandError = null;
        _selectedPlayer = ExternalPlayer.customCommand;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Custom command saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save command: $e')),
        );
      }
    }
  }

  Future<void> _clearCustomCommand() async {
    try {
      await StorageService.setCustomExternalPlayerCommand(null);

      // If custom command was selected, switch to system default
      if (_selectedPlayer == ExternalPlayer.customCommand) {
        await StorageService.setPreferredExternalPlayer('system_default');
        setState(() {
          _selectedPlayer = ExternalPlayer.systemDefault;
        });
      }

      _commandController.clear();
      setState(() {
        _customCommand = null;
        _commandError = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear command: $e')),
        );
      }
    }
  }

  Widget _buildPlayerTile(ExternalPlayer player) {
    final theme = Theme.of(context);
    final isInstalled = _installedPlayers[player] ?? false;
    final isCustomApp = player == ExternalPlayer.customApp;
    final isCustomCommand = player == ExternalPlayer.customCommand;
    final isSystemDefault = player == ExternalPlayer.systemDefault;

    // Determine if player can be selected
    bool canSelect;
    if (isSystemDefault) {
      canSelect = true;
    } else if (isCustomApp) {
      canSelect = _customAppPath != null;
    } else if (isCustomCommand) {
      canSelect = _customCommand != null && _customCommand!.isNotEmpty;
    } else {
      canSelect = isInstalled;
    }

    String subtitle;
    Color? subtitleColor;

    if (isSystemDefault) {
      subtitle = 'Uses system default video player';
    } else if (isCustomApp) {
      if (_customAppPath != null) {
        subtitle = _customAppName ?? _customAppPath!;
      } else {
        subtitle = 'No application selected';
        subtitleColor = theme.colorScheme.onSurfaceVariant;
      }
    } else if (isCustomCommand) {
      if (_customCommand != null && _customCommand!.isNotEmpty) {
        // Show truncated command
        final displayCmd = _customCommand!.length > 40
            ? '${_customCommand!.substring(0, 40)}...'
            : _customCommand!;
        subtitle = displayCmd;
      } else {
        subtitle = 'No command configured';
        subtitleColor = theme.colorScheme.onSurfaceVariant;
      }
    } else if (isInstalled) {
      subtitle = 'Installed';
      subtitleColor = Colors.green;
    } else {
      subtitle = 'Not found';
      subtitleColor = theme.colorScheme.error;
    }

    return RadioListTile<ExternalPlayer>(
      value: player,
      groupValue: canSelect ? _selectedPlayer : null,
      onChanged: canSelect
          ? (value) {
              if (value != null) {
                _selectPlayer(value);
              }
            }
          : null,
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          player.icon,
          color: canSelect
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
      title: Text(
        player.displayName,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: canSelect
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: subtitleColor ?? theme.colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('External Player'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.desktop_mac_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  'External player settings are only available on macOS',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('External Player'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('External Player'),
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
                      Icons.open_in_new_rounded,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'External Player',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Choose which video player to use when opening files externally',
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

            // Player selection card
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Preferred Player',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // System Default
                  _buildPlayerTile(ExternalPlayer.systemDefault),
                  const Divider(height: 1),
                  // VLC
                  _buildPlayerTile(ExternalPlayer.vlc),
                  const Divider(height: 1),
                  // IINA
                  _buildPlayerTile(ExternalPlayer.iina),
                  const Divider(height: 1),
                  // mpv
                  _buildPlayerTile(ExternalPlayer.mpv),
                  const Divider(height: 1),
                  // QuickTime
                  _buildPlayerTile(ExternalPlayer.quickTime),
                  const Divider(height: 1),
                  // Infuse
                  _buildPlayerTile(ExternalPlayer.infuse),
                  const Divider(height: 1),
                  // Custom App
                  _buildPlayerTile(ExternalPlayer.customApp),
                  const Divider(height: 1),
                  // Custom Command
                  _buildPlayerTile(ExternalPlayer.customCommand),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            // Custom App configuration (only shown when selected)
            if (_selectedPlayer == ExternalPlayer.customApp) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.folder_open_rounded,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Custom App',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select a .app to use as your video player',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_customAppPath != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.apps_rounded,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _customAppName ?? 'Custom App',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      _customAppPath!,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _browseForCustomApp,
                              icon: const Icon(Icons.folder_open_rounded),
                              label: Text(_customAppPath == null
                                  ? 'Browse'
                                  : 'Change'),
                            ),
                          ),
                          if (_customAppPath != null) ...[
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _clearCustomApp,
                              child: const Text('Clear'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // Custom Command configuration (only shown when selected)
            if (_selectedPlayer == ExternalPlayer.customCommand) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.code_rounded,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Custom Command',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Define a custom shell command to launch videos',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _commandController,
                        decoration: InputDecoration(
                          labelText: 'Command',
                          hintText: 'vlc --fullscreen {url}',
                          helperText: 'Use {url} for video URL, {title} for title',
                          helperMaxLines: 2,
                          errorText: _commandError,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.terminal_rounded),
                        ),
                        maxLines: 1,
                        onChanged: (_) {
                          // Clear error when typing
                          if (_commandError != null) {
                            setState(() {
                              _commandError = null;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _saveCustomCommand,
                              icon: const Icon(Icons.save_rounded),
                              label: const Text('Save Command'),
                            ),
                          ),
                          if (_customCommand != null &&
                              _customCommand!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _clearCustomCommand,
                              child: const Text('Clear'),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Examples
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Examples',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'vlc --fullscreen {url}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'mpv --fs --title="{title}" {url}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '/opt/homebrew/bin/mpv {url}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
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
            ],
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
                        'Players marked as "Not found" are not installed on your system. Install them via the App Store, Homebrew, or their official websites.',
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

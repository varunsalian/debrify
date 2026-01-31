import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/external_player_service.dart';
import '../../services/storage_service.dart';
import '../../services/android_native_downloader.dart';
import '../../utils/deovr_utils.dart' as deovr;
import '../video_player/services/subtitle_settings_service.dart';

class ExternalPlayerSettingsPage extends StatefulWidget {
  const ExternalPlayerSettingsPage({super.key});

  @override
  State<ExternalPlayerSettingsPage> createState() =>
      _ExternalPlayerSettingsPageState();
}

class _ExternalPlayerSettingsPageState
    extends State<ExternalPlayerSettingsPage> {
  bool _loading = true;

  // Default player mode: 'debrify', 'external', 'deovr'
  String _defaultPlayerMode = 'debrify';

  // macOS external player settings
  ExternalPlayer _selectedPlayer = ExternalPlayer.systemDefault;
  Map<ExternalPlayer, bool> _installedPlayers = {};
  String? _customAppPath;
  String? _customAppName;
  String? _customCommand;
  final TextEditingController _commandController = TextEditingController();
  final FocusNode _commandFocusNode = FocusNode();
  bool _commandFocused = false;
  String? _commandError;

  // iOS external player settings
  iOSExternalPlayer _selectedIOSPlayer = iOSExternalPlayer.vlc;
  Map<iOSExternalPlayer, bool> _installedIOSPlayers = {};
  String? _iosCustomScheme;
  final TextEditingController _iosSchemeController = TextEditingController();
  final FocusNode _iosSchemeFocusNode = FocusNode();
  bool _iosSchemeFocused = false;
  String? _iosSchemeError;

  // DeoVR settings (Android)
  String _vrDefaultScreenType = 'dome';
  String _vrDefaultStereoMode = 'sbs';
  bool _vrAutoDetectFormat = true;
  bool _vrShowDialog = true;

  // Debrify Player default settings
  bool _isAndroidTv = false;
  int _defaultAspectIndex = 2; // Fit Width (mobile) / Fill (TV)
  int _nightModeIndex = 2; // Medium
  int _subtitleSizeIndex = 2; // Medium
  int _subtitleStyleIndex = 1; // Outline
  int _subtitleColorIndex = 0; // White
  int _subtitleBgIndex = 0; // None

  // Debrify Player FocusNodes for DPAD navigation
  final FocusNode _aspectFocusNode = FocusNode();
  final FocusNode _subtitleSizeFocusNode = FocusNode();
  final FocusNode _subtitleStyleFocusNode = FocusNode();
  final FocusNode _subtitleColorFocusNode = FocusNode();
  final FocusNode _subtitleBgFocusNode = FocusNode();
  bool _aspectFocused = false;
  bool _subtitleSizeFocused = false;
  bool _subtitleStyleFocused = false;
  bool _subtitleColorFocused = false;
  bool _subtitleBgFocused = false;

  // DeoVR FocusNodes for DPAD navigation
  final FocusNode _screenTypeFocusNode = FocusNode();
  final FocusNode _stereoModeFocusNode = FocusNode();
  final FocusNode _autoDetectFocusNode = FocusNode();
  final FocusNode _showDialogFocusNode = FocusNode();
  bool _screenTypeFocused = false;
  bool _stereoModeFocused = false;
  bool _autoDetectFocused = false;
  bool _showDialogFocused = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _commandFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _commandFocused = _commandFocusNode.hasFocus;
      });
    });
    _iosSchemeFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _iosSchemeFocused = _iosSchemeFocusNode.hasFocus;
      });
    });
    _screenTypeFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _screenTypeFocused = _screenTypeFocusNode.hasFocus;
      });
    });
    _stereoModeFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _stereoModeFocused = _stereoModeFocusNode.hasFocus;
      });
    });
    _autoDetectFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _autoDetectFocused = _autoDetectFocusNode.hasFocus;
      });
    });
    _showDialogFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _showDialogFocused = _showDialogFocusNode.hasFocus;
      });
    });
    // Debrify Player focus listeners
    _aspectFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _aspectFocused = _aspectFocusNode.hasFocus;
      });
    });
    _subtitleSizeFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subtitleSizeFocused = _subtitleSizeFocusNode.hasFocus;
      });
    });
    _subtitleStyleFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subtitleStyleFocused = _subtitleStyleFocusNode.hasFocus;
      });
    });
    _subtitleColorFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subtitleColorFocused = _subtitleColorFocusNode.hasFocus;
      });
    });
    _subtitleBgFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subtitleBgFocused = _subtitleBgFocusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _commandController.dispose();
    _commandFocusNode.dispose();
    _iosSchemeController.dispose();
    _iosSchemeFocusNode.dispose();
    _screenTypeFocusNode.dispose();
    _stereoModeFocusNode.dispose();
    _autoDetectFocusNode.dispose();
    _showDialogFocusNode.dispose();
    // Debrify Player focus nodes
    _aspectFocusNode.dispose();
    _subtitleSizeFocusNode.dispose();
    _subtitleStyleFocusNode.dispose();
    _subtitleColorFocusNode.dispose();
    _subtitleBgFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
    });

    try {
      // Load default player mode
      final mode = await StorageService.getDefaultPlayerMode();

      // Load macOS-specific settings
      Map<ExternalPlayer, bool> installed = {};
      String preferredKey = 'system_default';
      String? customAppPath;
      String? customAppName;
      String? customCommand;

      if (Platform.isMacOS) {
        installed = await ExternalPlayerService.detectInstalledPlayers();
        preferredKey = await StorageService.getPreferredExternalPlayer();
        customAppPath = await StorageService.getCustomExternalPlayerPath();
        customAppName = await StorageService.getCustomExternalPlayerName();
        customCommand = await StorageService.getCustomExternalPlayerCommand();
        _commandController.text = customCommand ?? '';
      }

      // Load iOS-specific settings
      Map<iOSExternalPlayer, bool> installedIOS = {};
      String iosPreferredKey = 'vlc';
      String? iosCustomScheme;

      if (Platform.isIOS) {
        installedIOS = await ExternalPlayerService.detectInstalledIOSPlayers();
        iosPreferredKey = await StorageService.getPreferredIOSExternalPlayer();
        iosCustomScheme = await StorageService.getIOSCustomSchemeTemplate();
        _iosSchemeController.text = iosCustomScheme ?? '';
      }

      // Load DeoVR settings (Android)
      String vrScreenType = 'dome';
      String vrStereoMode = 'sbs';
      bool vrAutoDetect = true;
      bool vrShowDialog = true;

      if (Platform.isAndroid) {
        vrScreenType = await StorageService.getQuickPlayVrDefaultScreenType();
        vrStereoMode = await StorageService.getQuickPlayVrDefaultStereoMode();
        vrAutoDetect = await StorageService.getQuickPlayVrAutoDetectFormat();
        vrShowDialog = await StorageService.getQuickPlayVrShowDialog();
      }

      // Check if running on Android TV
      bool isAndroidTv = false;
      if (Platform.isAndroid) {
        try {
          isAndroidTv = await AndroidNativeDownloader.isTelevision();
        } catch (_) {
          isAndroidTv = false;
        }
      }

      // Load Debrify Player default settings (use platform-specific aspect setting)
      final defaultAspectIndex = isAndroidTv
          ? await StorageService.getPlayerDefaultAspectIndexTv()
          : await StorageService.getPlayerDefaultAspectIndex();
      final nightModeIndex = await StorageService.getPlayerNightModeIndex();

      // Load subtitle settings
      final subtitleSettings = await SubtitleSettingsService.instance.loadAll();

      setState(() {
        _defaultPlayerMode = mode;
        _installedPlayers = installed;
        _selectedPlayer = ExternalPlayerExtension.fromStorageKey(preferredKey);
        _customAppPath = customAppPath;
        _customAppName = customAppName;
        _customCommand = customCommand;
        // iOS settings
        _installedIOSPlayers = installedIOS;
        _selectedIOSPlayer = iOSExternalPlayerExtension.fromStorageKey(iosPreferredKey);
        _iosCustomScheme = iosCustomScheme;
        // Other settings
        _vrDefaultScreenType = vrScreenType;
        _vrDefaultStereoMode = vrStereoMode;
        _vrAutoDetectFormat = vrAutoDetect;
        _vrShowDialog = vrShowDialog;
        _isAndroidTv = isAndroidTv;
        _defaultAspectIndex = defaultAspectIndex;
        _nightModeIndex = nightModeIndex;
        _subtitleSizeIndex = subtitleSettings.sizeIndex;
        _subtitleStyleIndex = subtitleSettings.styleIndex;
        _subtitleColorIndex = subtitleSettings.colorIndex;
        _subtitleBgIndex = subtitleSettings.bgIndex;
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

  Future<void> _setDefaultPlayerMode(String mode) async {
    try {
      await StorageService.setDefaultPlayerMode(mode);
      setState(() {
        _defaultPlayerMode = mode;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setting: $e')),
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

  // iOS external player settings methods
  Future<void> _selectIOSPlayer(iOSExternalPlayer player) async {
    try {
      await StorageService.setPreferredIOSExternalPlayer(player.storageKey);
      setState(() {
        _selectedIOSPlayer = player;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save setting: $e')),
        );
      }
    }
  }

  Future<void> _saveIOSCustomScheme() async {
    final scheme = _iosSchemeController.text.trim();

    final validation = validateCustomScheme(scheme);
    if (!validation.isValid) {
      setState(() {
        _iosSchemeError = validation.errorMessage;
      });
      return;
    }

    try {
      await StorageService.setIOSCustomSchemeTemplate(scheme);
      await StorageService.setPreferredIOSExternalPlayer('custom_scheme');

      setState(() {
        _iosCustomScheme = scheme;
        _iosSchemeError = null;
        _selectedIOSPlayer = iOSExternalPlayer.customScheme;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Custom URL scheme saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save URL scheme: $e')),
        );
      }
    }
  }

  Future<void> _clearIOSCustomScheme() async {
    try {
      await StorageService.setIOSCustomSchemeTemplate(null);

      if (_selectedIOSPlayer == iOSExternalPlayer.customScheme) {
        await StorageService.setPreferredIOSExternalPlayer('vlc');
        setState(() {
          _selectedIOSPlayer = iOSExternalPlayer.vlc;
        });
      }

      _iosSchemeController.clear();
      setState(() {
        _iosCustomScheme = null;
        _iosSchemeError = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear URL scheme: $e')),
        );
      }
    }
  }

  // DeoVR settings setters
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

  // Debrify Player settings setters
  Future<void> _setDefaultAspectIndex(int index) async {
    setState(() => _defaultAspectIndex = index);
    // Use platform-specific storage key
    if (_isAndroidTv) {
      await StorageService.setPlayerDefaultAspectIndexTv(index);
    } else {
      await StorageService.setPlayerDefaultAspectIndex(index);
    }
  }

  Future<void> _setNightModeIndex(int index) async {
    setState(() => _nightModeIndex = index);
    await StorageService.setPlayerNightModeIndex(index);
  }

  Future<void> _setSubtitleSizeIndex(int index) async {
    setState(() => _subtitleSizeIndex = index);
    await SubtitleSettingsService.instance.setSizeIndex(index);
  }

  Future<void> _setSubtitleStyleIndex(int index) async {
    setState(() => _subtitleStyleIndex = index);
    await SubtitleSettingsService.instance.setStyleIndex(index);
  }

  Future<void> _setSubtitleColorIndex(int index) async {
    setState(() => _subtitleColorIndex = index);
    await SubtitleSettingsService.instance.setColorIndex(index);
  }

  Future<void> _setSubtitleBgIndex(int index) async {
    setState(() => _subtitleBgIndex = index);
    await SubtitleSettingsService.instance.setBgIndex(index);
  }

  // Aspect labels
  List<String> get _aspectLabels => _isAndroidTv
      ? ['Fit', 'Fill', 'Zoom']
      : ['Contain', 'Cover', 'Fit Width', 'Fit Height', '16:9', '4:3', '21:9', '1:1', '3:2', '5:4'];

  static const List<String> _nightModeLabels = [
    'Off', 'Low', 'Medium', 'High', 'Higher', 'Extreme', 'Max', 'Sleeping Baby'
  ];

  Widget _buildPlayerTile(ExternalPlayer player) {
    final theme = Theme.of(context);
    final isInstalled = _installedPlayers[player] ?? false;
    final isCustomApp = player == ExternalPlayer.customApp;
    final isCustomCommand = player == ExternalPlayer.customCommand;
    final isSystemDefault = player == ExternalPlayer.systemDefault;

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

  Widget _buildIOSPlayerTile(iOSExternalPlayer player) {
    final theme = Theme.of(context);
    final isInstalled = _installedIOSPlayers[player] ?? false;
    final isCustom = player == iOSExternalPlayer.customScheme;

    String subtitle;
    Color? subtitleColor;

    if (isCustom) {
      if (_iosCustomScheme != null && _iosCustomScheme!.isNotEmpty) {
        final displayScheme = _iosCustomScheme!.length > 40
            ? '${_iosCustomScheme!.substring(0, 40)}...'
            : _iosCustomScheme!;
        subtitle = displayScheme;
      } else {
        subtitle = 'No URL scheme configured';
        subtitleColor = theme.colorScheme.onSurfaceVariant;
      }
    } else {
      subtitle = player.description;
      if (isInstalled) {
        subtitleColor = Colors.green;
        subtitle = 'Likely installed • ${player.description}';
      }
    }

    return RadioListTile<iOSExternalPlayer>(
      value: player,
      groupValue: _selectedIOSPlayer,
      onChanged: (value) {
        if (value != null) {
          _selectIOSPlayer(value);
        }
      },
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          player.icon,
          color: theme.colorScheme.primary,
        ),
      ),
      title: Text(
        player.displayName,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.onSurface,
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

  Widget _buildPlayerModeOption(
    BuildContext context, {
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    bool recommended = false,
    bool disabled = false,
  }) {
    final theme = Theme.of(context);
    final isSelected = _defaultPlayerMode == value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: disabled ? null : () => _setDefaultPlayerMode(value),
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
                groupValue: _defaultPlayerMode,
                onChanged: disabled ? null : (v) => _setDefaultPlayerMode(v!),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? theme.colorScheme.primary
                    : disabled
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
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
                            color: disabled
                                ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                                : null,
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
                              'Default',
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
                        color: disabled
                            ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                            : theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
    FocusNode? focusNode,
    bool isFocused = false,
  }) {
    final theme = Theme.of(context);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          NextFocusIntent: CallbackAction<NextFocusIntent>(
            onInvoke: (intent) {
              FocusScope.of(context).nextFocus();
              return null;
            },
          ),
          PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
            onInvoke: (intent) {
              FocusScope.of(context).previousFocus();
              return null;
            },
          ),
        },
        child: Row(
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isFocused
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline.withValues(alpha: 0.3),
                    width: isFocused ? 2 : 1,
                  ),
                  boxShadow: isFocused
                      ? [
                          BoxShadow(
                            color: theme.colorScheme.primary.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: value,
                    focusNode: focusNode,
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
        ),
      ),
    );
  }

  Widget _buildCheckboxTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    FocusNode? focusNode,
    bool isFocused = false,
  }) {
    final theme = Theme.of(context);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          NextFocusIntent: CallbackAction<NextFocusIntent>(
            onInvoke: (intent) {
              FocusScope.of(context).nextFocus();
              return null;
            },
          ),
          PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
            onInvoke: (intent) {
              FocusScope.of(context).previousFocus();
              return null;
            },
          ),
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: isFocused
                ? Border.all(
                    color: theme.colorScheme.primary,
                    width: 2,
                  )
                : null,
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            focusNode: focusNode,
            onTap: () => onChanged(!value),
            borderRadius: BorderRadius.circular(8),
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
          ),
        ),
      ),
    );
  }

  Widget _buildSettingDropdown(
    BuildContext context, {
    required String label,
    required int value,
    required List<String> items,
    required Function(int) onChanged,
    FocusNode? focusNode,
    bool isFocused = false,
  }) {
    final theme = Theme.of(context);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          NextFocusIntent: CallbackAction<NextFocusIntent>(
            onInvoke: (intent) {
              FocusScope.of(context).nextFocus();
              return null;
            },
          ),
          PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
            onInvoke: (intent) {
              FocusScope.of(context).previousFocus();
              return null;
            },
          ),
        },
        child: Row(
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isFocused
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline.withValues(alpha: 0.3),
                    width: isFocused ? 2 : 1,
                  ),
                  boxShadow: isFocused
                      ? [
                          BoxShadow(
                            color: theme.colorScheme.primary.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: value.clamp(0, items.length - 1),
                    focusNode: focusNode,
                    isExpanded: true,
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    items: List.generate(items.length, (index) {
                      return DropdownMenuItem<int>(
                        value: index,
                        child: Text(items[index]),
                      );
                    }),
                    onChanged: (v) {
                      if (v != null) onChanged(v);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSupportedPlatform = Platform.isMacOS || Platform.isAndroid || Platform.isIOS;

    if (!isSupportedPlatform) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Player Settings'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.block_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  'Player settings are not available on this platform',
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
          title: const Text('Player Settings'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Player Settings'),
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
                            'Player Settings',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Choose which player to use for video playback',
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

            // Default Player Mode Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Default Player',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose which player to use when playing videos',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildPlayerModeOption(
                      context,
                      value: 'debrify',
                      title: 'Debrify Player',
                      subtitle: 'Use the built-in video player',
                      icon: Icons.play_circle_filled_rounded,
                      recommended: true,
                    ),
                    _buildPlayerModeOption(
                      context,
                      value: 'external',
                      title: 'External Player',
                      subtitle: Platform.isMacOS
                          ? 'Open videos in your preferred external player'
                          : 'Choose which app to use when opening videos',
                      icon: Icons.open_in_new_rounded,
                    ),
                    _buildPlayerModeOption(
                      context,
                      value: 'deovr',
                      title: 'DeoVR',
                      subtitle: 'Use this only on VR devices',
                      icon: Icons.vrpano,
                      disabled: !Platform.isAndroid,
                    ),
                  ],
                ),
              ),
            ),

            // Debrify Player settings (only when Debrify Player is selected)
            if (_defaultPlayerMode == 'debrify') ...[
              const SizedBox(height: 16),

              // Playback Defaults
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Playback Defaults',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Default settings when video playback starts',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Default Aspect
                      _buildSettingDropdown(
                        context,
                        label: 'Default Aspect',
                        value: _defaultAspectIndex,
                        items: _aspectLabels,
                        onChanged: (index) => _setDefaultAspectIndex(index),
                        focusNode: _aspectFocusNode,
                        isFocused: _aspectFocused,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Subtitle Appearance
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Subtitle Appearance',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Customize how subtitles look',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Size
                      _buildSettingDropdown(
                        context,
                        label: 'Size',
                        value: _subtitleSizeIndex,
                        items: SubtitleSize.options.map((o) => o.label).toList(),
                        onChanged: (index) => _setSubtitleSizeIndex(index),
                        focusNode: _subtitleSizeFocusNode,
                        isFocused: _subtitleSizeFocused,
                      ),
                      const SizedBox(height: 12),

                      // Style
                      _buildSettingDropdown(
                        context,
                        label: 'Style',
                        value: _subtitleStyleIndex,
                        items: SubtitleStyle.options.map((o) => o.label).toList(),
                        onChanged: (index) => _setSubtitleStyleIndex(index),
                        focusNode: _subtitleStyleFocusNode,
                        isFocused: _subtitleStyleFocused,
                      ),
                      const SizedBox(height: 12),

                      // Color
                      _buildSettingDropdown(
                        context,
                        label: 'Color',
                        value: _subtitleColorIndex,
                        items: SubtitleColor.options.map((o) => o.label).toList(),
                        onChanged: (index) => _setSubtitleColorIndex(index),
                        focusNode: _subtitleColorFocusNode,
                        isFocused: _subtitleColorFocused,
                      ),
                      const SizedBox(height: 12),

                      // Background
                      _buildSettingDropdown(
                        context,
                        label: 'Background',
                        value: _subtitleBgIndex,
                        items: SubtitleBackground.options.map((o) => o.label).toList(),
                        onChanged: (index) => _setSubtitleBgIndex(index),
                        focusNode: _subtitleBgFocusNode,
                        isFocused: _subtitleBgFocused,
                      ),

                      const SizedBox(height: 16),

                      // Preview
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            'Sample Subtitle',
                            style: TextStyle(
                              fontSize: SubtitleSize.options[_subtitleSizeIndex].sizePx * 0.4,
                              color: SubtitleColor.options[_subtitleColorIndex].color,
                              fontWeight: FontWeight.w600,
                              shadows: SubtitleStyle.options[_subtitleStyleIndex].shadows,
                              backgroundColor: SubtitleBackground.options[_subtitleBgIndex].color,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Night Mode (Android TV only)
              if (_isAndroidTv) ...[
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
                              Icons.nightlight_round,
                              color: theme.colorScheme.primary,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Night Mode',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Boosts quiet sounds for late-night viewing without disturbing others',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...List.generate(_nightModeLabels.length, (index) {
                          final isSelected = _nightModeIndex == index;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Focus(
                              onKeyEvent: (node, event) {
                                if (event is KeyDownEvent) {
                                  if (event.logicalKey == LogicalKeyboardKey.select ||
                                      event.logicalKey == LogicalKeyboardKey.enter ||
                                      event.logicalKey == LogicalKeyboardKey.gameButtonA) {
                                    _setNightModeIndex(index);
                                    return KeyEventResult.handled;
                                  }
                                }
                                return KeyEventResult.ignored;
                              },
                              child: Builder(
                                builder: (context) {
                                  final isFocused = Focus.of(context).hasFocus;
                                  return InkWell(
                                    onTap: () => _setNightModeIndex(index),
                                    borderRadius: BorderRadius.circular(8),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 160),
                                      curve: Curves.easeOutCubic,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isFocused
                                              ? theme.colorScheme.primary
                                              : isSelected
                                                  ? theme.colorScheme.primary
                                                  : theme.colorScheme.outline.withValues(alpha: 0.3),
                                          width: isFocused || isSelected ? 2 : 1,
                                        ),
                                        boxShadow: isFocused
                                            ? [
                                                BoxShadow(
                                                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: Row(
                                        children: [
                                          Radio<int>(
                                            value: index,
                                            groupValue: _nightModeIndex,
                                            onChanged: (v) => _setNightModeIndex(v!),
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            visualDensity: VisualDensity.compact,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _nightModeLabels[index],
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              fontWeight: isSelected || isFocused ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                          ),
                                          if (index == 2) ...[
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
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ],

            // Android External Player info
            if (Platform.isAndroid && _defaultPlayerMode == 'external') ...[
              const SizedBox(height: 16),
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
                          'When enabled, you will be able to choose which app to use when opening videos. Install VLC, MX Player, or other video player apps to see them in the chooser.',
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

            // iOS-specific player selection
            if (Platform.isIOS && _defaultPlayerMode == 'external') ...[
              const SizedBox(height: 16),
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Select the app to open videos with. Make sure the app is installed from the App Store.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildIOSPlayerTile(iOSExternalPlayer.vlc),
                    const Divider(height: 1),
                    _buildIOSPlayerTile(iOSExternalPlayer.infuse),
                    const Divider(height: 1),
                    _buildIOSPlayerTile(iOSExternalPlayer.outplayer),
                    const Divider(height: 1),
                    _buildIOSPlayerTile(iOSExternalPlayer.nplayer),
                    const Divider(height: 1),
                    _buildIOSPlayerTile(iOSExternalPlayer.playerXtreme),
                    const Divider(height: 1),
                    _buildIOSPlayerTile(iOSExternalPlayer.vimu),
                    const Divider(height: 1),
                    _buildIOSPlayerTile(iOSExternalPlayer.customScheme),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],

            // iOS Custom URL Scheme configuration
            if (Platform.isIOS && _defaultPlayerMode == 'external' && _selectedIOSPlayer == iOSExternalPlayer.customScheme) ...[
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
                            'Custom URL Scheme',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Define a custom URL scheme to launch videos',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _iosSchemeController,
                        focusNode: _iosSchemeFocusNode,
                        decoration: InputDecoration(
                          labelText: 'URL Scheme Template',
                          hintText: 'myplayer://play?url={url}',
                          helperText: 'Use {url} for the video URL',
                          helperMaxLines: 2,
                          errorText: _iosSchemeError,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.link_rounded),
                        ),
                        maxLines: 1,
                        onChanged: (_) {
                          if (_iosSchemeError != null) {
                            setState(() {
                              _iosSchemeError = null;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _saveIOSCustomScheme,
                              icon: const Icon(Icons.save_rounded),
                              label: const Text('Save'),
                            ),
                          ),
                          if (_iosCustomScheme != null && _iosCustomScheme!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _clearIOSCustomScheme,
                              child: const Text('Clear'),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
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
                              'vlc://{url}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'infuse://x-callback-url/play?url={url}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'customapp://stream?video={url}',
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

            // iOS external player info
            if (Platform.isIOS && _defaultPlayerMode == 'external') ...[
              const SizedBox(height: 16),
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
                          'Videos will open in the selected app using URL schemes. Make sure the player app is installed from the App Store.',
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

            // macOS-specific player selection
            if (Platform.isMacOS && _defaultPlayerMode == 'external') ...[
              const SizedBox(height: 16),
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
                    _buildPlayerTile(ExternalPlayer.systemDefault),
                    const Divider(height: 1),
                    _buildPlayerTile(ExternalPlayer.vlc),
                    const Divider(height: 1),
                    _buildPlayerTile(ExternalPlayer.iina),
                    const Divider(height: 1),
                    _buildPlayerTile(ExternalPlayer.mpv),
                    const Divider(height: 1),
                    _buildPlayerTile(ExternalPlayer.quickTime),
                    const Divider(height: 1),
                    _buildPlayerTile(ExternalPlayer.infuse),
                    const Divider(height: 1),
                    _buildPlayerTile(ExternalPlayer.customApp),
                    const Divider(height: 1),
                    _buildPlayerTile(ExternalPlayer.customCommand),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],

            // Custom App configuration (macOS only, when selected)
            if (Platform.isMacOS && _defaultPlayerMode == 'external' && _selectedPlayer == ExternalPlayer.customApp) ...[
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
                              label: Text(_customAppPath == null ? 'Browse' : 'Change'),
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

            // Custom Command configuration (macOS only, when selected)
            if (Platform.isMacOS && _defaultPlayerMode == 'external' && _selectedPlayer == ExternalPlayer.customCommand) ...[
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
                      Shortcuts(
                        shortcuts: const <ShortcutActivator, Intent>{
                          SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
                          SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
                        },
                        child: Actions(
                          actions: <Type, Action<Intent>>{
                            NextFocusIntent: CallbackAction<NextFocusIntent>(
                              onInvoke: (intent) {
                                FocusScope.of(context).nextFocus();
                                return null;
                              },
                            ),
                            PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
                              onInvoke: (intent) {
                                FocusScope.of(context).previousFocus();
                                return null;
                              },
                            ),
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOutCubic,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: _commandFocused
                                  ? Border.all(
                                      color: theme.colorScheme.primary,
                                      width: 1.8,
                                    )
                                  : null,
                              boxShadow: _commandFocused
                                  ? [
                                      BoxShadow(
                                        color: theme.colorScheme.primary.withValues(alpha: 0.25),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: TextField(
                              controller: _commandController,
                              focusNode: _commandFocusNode,
                              decoration: InputDecoration(
                                labelText: 'Command',
                                hintText: 'vlc --fullscreen {url}',
                                helperText: 'Use {url} for video URL, {title} for title',
                                helperMaxLines: 2,
                                errorText: _commandError,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                prefixIcon: const Icon(Icons.terminal_rounded),
                              ),
                              maxLines: 1,
                              onChanged: (_) {
                                if (_commandError != null) {
                                  setState(() {
                                    _commandError = null;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
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
                          if (_customCommand != null && _customCommand!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _clearCustomCommand,
                              child: const Text('Clear'),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
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

            // macOS external player info
            if (Platform.isMacOS && _defaultPlayerMode == 'external') ...[
              const SizedBox(height: 16),
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

            // DeoVR settings (Android only, when selected)
            if (Platform.isAndroid && _defaultPlayerMode == 'deovr') ...[
              const SizedBox(height: 16),
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                            'DeoVR Settings',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // VR Format Settings
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
                            focusNode: _screenTypeFocusNode,
                            isFocused: _screenTypeFocused,
                          ),
                          const SizedBox(height: 12),

                          // Stereo Mode dropdown
                          _buildDropdownSetting(
                            context,
                            label: 'Stereo Mode',
                            value: _vrDefaultStereoMode,
                            items: deovr.stereoModeLabels,
                            onChanged: _setVrDefaultStereoMode,
                            focusNode: _stereoModeFocusNode,
                            isFocused: _stereoModeFocused,
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
                      focusNode: _autoDetectFocusNode,
                      isFocused: _autoDetectFocused,
                    ),
                    _buildCheckboxTile(
                      context,
                      title: 'Show format selection dialog',
                      subtitle: 'Confirm VR format before launching DeoVR',
                      value: _vrShowDialog,
                      onChanged: _setVrShowDialog,
                      focusNode: _showDialogFocusNode,
                      isFocused: _showDialogFocused,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
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
                          'DeoVR must be installed on your device. All videos will open in DeoVR with the selected VR format settings.',
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
          ],
        ),
      ),
    );
  }
}

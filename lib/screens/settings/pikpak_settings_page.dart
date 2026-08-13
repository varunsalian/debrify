import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/storage_service.dart';
import '../../services/pikpak_api_service.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../utils/platform_util.dart';
import '../../widgets/pikpak_folder_picker_dialog.dart';
import '../../widgets/tv_text_field.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

class PikPakSettingsPage extends StatefulWidget {
  const PikPakSettingsPage({super.key});

  @override
  State<PikPakSettingsPage> createState() => _PikPakSettingsPageState();
}

class _PikPakSettingsPageState extends State<PikPakSettingsPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Focus nodes for TV/DPAD navigation
  final FocusNode _emailFocusNode = FocusNode(debugLabel: 'pikpak-email');
  final FocusNode _passwordFocusNode = FocusNode(debugLabel: 'pikpak-password');
  final FocusNode _loginButtonFocusNode = FocusNode(debugLabel: 'pikpak-login');
  final FocusNode _logoutButtonFocusNode = FocusNode(
    debugLabel: 'pikpak-logout',
  );
  final FocusNode _folderRestrictionSkipButtonFocusNode = FocusNode(
    debugLabel: 'folder-restriction-skip',
  );
  final FocusNode _folderRestrictionSelectButtonFocusNode = FocusNode(
    debugLabel: 'folder-restriction-select',
  );
  final FocusNode _resetDeviceIdButtonFocusNode = FocusNode(
    debugLabel: 'pikpak-reset-device-id',
  );
  final FocusNode _enableToggleFocusNode = FocusNode(
    debugLabel: 'pikpak-enable-toggle',
  );

  bool _pikpakEnabled = false;
  bool _showVideosOnly = true;
  bool _ignoreSmallVideos = true;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _loading = true;
  bool _hiddenFromNav = false;
  String? _restrictedFolderId;
  String? _restrictedFolderName;
  String _postTorrentAction = 'choose';

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('pikpak_settings');
    _loadSettings();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _loginButtonFocusNode.dispose();
    _logoutButtonFocusNode.dispose();
    _folderRestrictionSkipButtonFocusNode.dispose();
    _folderRestrictionSelectButtonFocusNode.dispose();
    _resetDeviceIdButtonFocusNode.dispose();
    _enableToggleFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final enabled = await StorageService.getPikPakEnabled();
    final showVideosOnly = await StorageService.getPikPakShowVideosOnly();
    final ignoreSmallVideos = await StorageService.getPikPakIgnoreSmallVideos();
    final isAuth = await PikPakApiService.instance.isAuthenticated();
    final restrictedId = await StorageService.getPikPakRestrictedFolderId();
    final restrictedName = await StorageService.getPikPakRestrictedFolderName();
    final hiddenFromNav = await StorageService.getPikPakHiddenFromNav();
    final postAction = await StorageService.getPikPakPostTorrentAction();

    if (!mounted) return;

    setState(() {
      _pikpakEnabled = enabled;
      _showVideosOnly = showVideosOnly;
      _ignoreSmallVideos = ignoreSmallVideos;
      // A connected shared account is usable without exposing its credential
      // fields to this screen. Replacement login always starts empty.
      _emailController.clear();
      _isConnected = isAuth;
      _restrictedFolderId = restrictedId;
      _restrictedFolderName = restrictedName;
      _hiddenFromNav = hiddenFromNav;
      _postTorrentAction = postAction;
      _loading = false;
    });

    // TV: land DPAD focus on the first interactive row so users aren't
    // stranded with nothing focused when the page opens.
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Only a bare FocusScopeNode as primary focus means DPAD is
        // stranded — don't steal focus the user already placed somewhere.
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        _enableToggleFocusNode.requestFocus();
      });
    }
  }

  Future<void> _login() async {
    final t = AppThemeScope.of(context).settings;
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnackBar('Please fill in both email and password');
      return;
    }

    setState(() {
      _isConnecting = true;
    });

    try {
      final success = await PikPakApiService.instance.login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      if (success) {
        setState(() {
          _isConnected = true;
          _pikpakEnabled = true;
        });
        await StorageService.setPikPakEnabled(true);
        AnalyticsService.integrationConnected('pikpak', {
          'surface': 'settings',
        });

        // Notify main page to update navigation immediately
        MainPageBridge.notifyIntegrationChanged();

        _showSnackBar('Connected successfully!', isError: false);

        // Clear password field for security
        _passwordController.clear();

        // Ask if user wants to set up folder restriction
        final shouldSetupRestriction = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.folder_special, color: t.warning),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Folder Restriction (Optional)')),
                ],
              ),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'For enhanced security, you can restrict PikPak access to a specific folder.',
                    style: TextStyle(fontSize: 14),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '• Full Access: Browse all files in your account',
                    style: TextStyle(fontSize: 13),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Restricted: Only access files in one folder',
                    style: TextStyle(fontSize: 13),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Note: You must logout and login again to change this later.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
              actions: [
                _FocusRing(
                  child: TextButton(
                    focusNode: _folderRestrictionSkipButtonFocusNode,
                    autofocus: true,
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Skip (Full Access)'),
                  ),
                ),
                _FocusRing(
                  child: FilledButton.icon(
                    focusNode: _folderRestrictionSelectButtonFocusNode,
                    onPressed: () => Navigator.pop(dialogContext, true),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Select Folder'),
                  ),
                ),
              ],
            );
          },
        );

        // If user wants to set restriction, show folder picker
        if (shouldSetupRestriction == true && mounted) {
          final folderResult = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (ctx) => const PikPakFolderPickerDialog(),
          );

          // Save folder restriction if selected
          if (folderResult != null) {
            final folderId = folderResult['folderId'] as String?;
            final folderName = folderResult['folderName'] as String?;
            await StorageService.setPikPakRestrictedFolder(
              folderId,
              folderName,
            );
            // Clear subfolder caches when restriction changes
            await StorageService.clearPikPakSubfolderCaches();
            setState(() {
              _restrictedFolderId = folderId;
              _restrictedFolderName = folderName;
            });
            _showSnackBar('Folder restriction applied', isError: false);
          }
        }

        // The login form unmounted on success, so when the last dialog pops
        // focus tries to restore to the dead Login node — reseed Logout.
        if (PlatformUtil.isTelevision && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _logoutButtonFocusNode.requestFocus();
          });
        }
      } else {
        _showSnackBar('Login failed. Please check your credentials.');
      }
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('Login failed. Please check your credentials and retry.');
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
        // On failure the (previously disabled) Login button re-enables but
        // focus was already dropped — reseed it so DPAD isn't stranded.
        if (PlatformUtil.isTelevision && !_isConnected) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loginButtonFocusNode.requestFocus();
          });
        }
      }
    }
  }

  Future<void> _logout() async {
    try {
      await PikPakApiService.instance.logout();

      // Clear folder restriction on logout
      await StorageService.clearPikPakRestrictedFolder();

      // Clear the hidden from nav flag on logout
      await StorageService.clearPikPakHiddenFromNav();

      if (!mounted) return;

      // Notify main page to update navigation
      MainPageBridge.notifyIntegrationChanged();

      _showSnackBar('Logged out successfully', isError: false);

      // Pop back to settings page with logout flag for TV navigation
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (!mounted) return;
      _showSnackBar(
        'This connection is shared. Revoke or transfer profile access before disconnecting.',
      );
    }
  }

  Future<void> _selectRestrictedFolder() async {
    if (!_isConnected) {
      _showSnackBar('Please login to PikPak first');
      return;
    }

    // Security: Require logout/login to change existing restriction
    if (_restrictedFolderId != null) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Security Restriction'),
          content: const Text(
            'To change the folder restriction, you must logout and login again. This is a security measure to prevent unauthorized changes.',
          ),
          actions: [
            _FocusRing(
              child: TextButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      );
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const PikPakFolderPickerDialog(),
    );

    if (result != null) {
      final folderId = result['folderId'] as String?;
      final folderName = result['folderName'] as String?;

      await StorageService.setPikPakRestrictedFolder(folderId, folderName);
      // Clear subfolder caches when restriction changes
      await StorageService.clearPikPakSubfolderCaches();
      setState(() {
        _restrictedFolderId = folderId;
        _restrictedFolderName = folderName;
      });
      _showSnackBar('Folder restriction applied', isError: false);
    }
  }

  Future<void> _clearRestrictedFolder() async {
    // Security: Require logout/login to remove restriction
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Security Restriction'),
        content: const Text(
          'To remove the folder restriction, you must logout and login again. This is a security measure to prevent unauthorized changes.',
        ),
        actions: [
          _FocusRing(
            child: TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _savePostAction(String action) async {
    setState(() => _postTorrentAction = action);
    await StorageService.savePikPakPostTorrentAction(action);
    _showSnackBar('Preference saved', isError: false);
  }

  Future<void> _toggleHideFromNav(bool value) async {
    final t = AppThemeScope.of(context).settings;
    if (value) {
      // Show confirmation dialog before enabling
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hide PikPak?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This will hide the PikPak tab from navigation.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: t.warning.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: t.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'To show PikPak again, you must logout and login. This is a security measure.',
                          style: TextStyle(fontSize: 13, color: t.warning),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            _FocusRing(
              child: TextButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ),
            _FocusRing(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Hide'),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }

      // Enable hiding
      await StorageService.setPikPakHiddenFromNav(true);
      setState(() {
        _hiddenFromNav = true;
      });
      MainPageBridge.notifyIntegrationChanged();
      _showSnackBar('PikPak hidden from navigation', isError: false);
    } else {
      // Try to disable - show dialog explaining logout requirement
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Security Restriction'),
          content: SingleChildScrollView(
            child: Text(
              'To show PikPak in navigation again, you must logout and login. This is a security measure to prevent unauthorized changes.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          actions: [
            _FocusRing(
              child: FilledButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      );
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    final t = AppThemeScope.of(context).settings;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? t.danger : t.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'PikPak Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'PikPak Settings',
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SettingsPageHeader(
              icon: Icons.cloud_rounded,
              title: 'PikPak Integration',
              subtitle:
                  'Send magnet links directly to your PikPak cloud storage.',
            ),
            const SizedBox(height: 24),

            // Enable/Disable Toggle
            Card(
              child: _FocusRing(
                child: SwitchListTile(
                  focusNode: _enableToggleFocusNode,
                  title: const Text(
                    'Enable PikPak Integration',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    _pikpakEnabled
                        ? 'PikPak button and tab are visible'
                        : 'PikPak button and tab are hidden',
                    style: const TextStyle(fontSize: 13),
                  ),
                  value: _pikpakEnabled,
                  onChanged: (value) async {
                    await StorageService.setPikPakEnabled(value);
                    setState(() {
                      _pikpakEnabled = value;
                    });

                    // Notify main page to update navigation immediately
                    MainPageBridge.notifyIntegrationChanged();

                    _showSnackBar(
                      value
                          ? 'PikPak integration enabled'
                          : 'PikPak integration disabled',
                      isError: false,
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),
            IgnorePointer(
              ignoring: !_pikpakEnabled,
              // IgnorePointer only blocks touch — DPAD could still focus and
              // activate the dimmed controls, so exclude them from focus too.
              child: ExcludeFocus(
                excluding: !_pikpakEnabled,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _pikpakEnabled ? 1.0 : 0.5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Hide from Navigation Toggle
                      Card(
                        child: Column(
                          children: [
                            _FocusRing(
                              child: SwitchListTile(
                                value: _hiddenFromNav,
                                onChanged: _isConnected
                                    ? _toggleHideFromNav
                                    : null,
                                title: const Text(
                                  'Hide from Navigation',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  !_isConnected
                                      ? 'Login to enable this option'
                                      : _hiddenFromNav
                                      ? 'PikPak is hidden from navigation'
                                      : 'Show/hide PikPak tab from navigation bar',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                secondary: Icon(
                                  _hiddenFromNav
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: _hiddenFromNav ? t.warning : null,
                                ),
                              ),
                            ),
                            if (_hiddenFromNav)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: SettingsInfoBanner(
                                  text:
                                      'To show PikPak in navigation again, please logout and login',
                                  tone: SettingsBannerTone.warning,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Show Videos Only Toggle
                      Card(
                        child: _FocusRing(
                          child: SwitchListTile(
                            title: const Text(
                              'Show Only Video Files',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              _showVideosOnly
                                  ? 'Only video files are shown in folders'
                                  : 'All file types are shown in folders',
                              style: const TextStyle(fontSize: 13),
                            ),
                            value: _showVideosOnly,
                            onChanged: (value) async {
                              await StorageService.setPikPakShowVideosOnly(
                                value,
                              );
                              setState(() {
                                _showVideosOnly = value;
                              });
                              _showSnackBar(
                                value
                                    ? 'Now showing only video files'
                                    : 'Now showing all file types',
                                isError: false,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Ignore Small Videos Toggle
                      Card(
                        child: _FocusRing(
                          child: SwitchListTile(
                            title: const Text(
                              'Ignore Videos Under 100MB',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              _ignoreSmallVideos
                                  ? 'Videos smaller than 100MB are hidden'
                                  : 'All video sizes are shown',
                              style: const TextStyle(fontSize: 13),
                            ),
                            value: _ignoreSmallVideos,
                            onChanged: (value) async {
                              await StorageService.setPikPakIgnoreSmallVideos(
                                value,
                              );
                              setState(() {
                                _ignoreSmallVideos = value;
                              });
                              _showSnackBar(
                                value
                                    ? 'Now hiding videos under 100MB'
                                    : 'Now showing all video sizes',
                                isError: false,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Post-Torrent Action
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.play_circle_outline,
                                    color: t.accent2,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Post-Torrent Action',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Choose what happens after adding a torrent to PikPak',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(color: t.dim),
                              ),
                              const SizedBox(height: 12),
                              SettingsSelectDropdown(
                                value: _postTorrentAction,
                                onChanged: _savePostAction,
                                options: const [
                                  SettingsSelectOption(
                                    'none',
                                    'None',
                                    'Do nothing - just add the torrent to PikPak',
                                  ),
                                  SettingsSelectOption(
                                    'choose',
                                    'Let me choose',
                                    'Show a quick Play/Download picker after adding a torrent',
                                  ),
                                  SettingsSelectOption(
                                    'open',
                                    'Open in PikPak',
                                    'View the torrent in PikPak tab',
                                  ),
                                  SettingsSelectOption(
                                    'play',
                                    'Play video',
                                    'Automatically open video player',
                                  ),
                                  SettingsSelectOption(
                                    'download',
                                    'Download to device',
                                    'If the torrent contains only video files, all videos will download immediately',
                                  ),
                                  SettingsSelectOption(
                                    'playlist',
                                    'Add to playlist',
                                    'Keep this torrent handy in your Debrify playlist',
                                  ),
                                  SettingsSelectOption(
                                    'channel',
                                    'Add to channel',
                                    'Cache this torrent in a Debrify TV channel',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Folder Restriction
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: Icon(
                                Icons.folder_special,
                                color: _restrictedFolderId != null
                                    ? t.warning
                                    : null,
                              ),
                              title: const Text(
                                'Restrict Access to Folder',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                _restrictedFolderId != null
                                    ? 'Restricted to: $_restrictedFolderName'
                                    : 'Full account access (all folders)',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            if (_restrictedFolderId != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SettingsInfoBanner(
                                      text:
                                          'To change or remove this restriction, please logout and login again',
                                      tone: SettingsBannerTone.warning,
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _FocusRing(
                                            child: OutlinedButton.icon(
                                              onPressed:
                                                  _selectRestrictedFolder,
                                              icon: const Icon(
                                                Icons.edit,
                                                size: 18,
                                              ),
                                              label: const Text('Change'),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _FocusRing(
                                          child: OutlinedButton.icon(
                                            onPressed: _clearRestrictedFolder,
                                            icon: const Icon(
                                              Icons.clear,
                                              size: 18,
                                            ),
                                            label: const Text('Remove'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: t.danger,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: _FocusRing(
                                    child: FilledButton.icon(
                                      onPressed: _selectRestrictedFolder,
                                      icon: const Icon(
                                        Icons.folder_open,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'Select Folder to Restrict',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Connection status
                      Card(
                        color: _isConnected
                            ? t.success.withValues(alpha: 0.15)
                            : t.panel,
                        child: ListTile(
                          leading: Icon(
                            _isConnected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: _isConnected ? t.success : t.dim,
                          ),
                          title: Text(
                            _isConnected ? 'Connected' : 'Not Connected',
                            style: TextStyle(
                              color: _isConnected ? t.success : app.core.tx,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            _isConnected
                                ? 'Connected account'
                                : 'Login with your PikPak account below',
                            style: TextStyle(color: t.dim),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      if (!_isConnected) ...[
                        const Text(
                          'PikPak Account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TvTextField(
                          controller: _emailController,
                          focusNode: _emailFocusNode,
                          labelText: 'Email',
                          hintText: 'your@email.com',
                          prefixIcon: const Icon(Icons.email),
                          keyboardType: TextInputType.emailAddress,
                          enabled: !_isConnecting,
                        ),
                        const SizedBox(height: 16),
                        TvTextField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          labelText: 'Password',
                          hintText: 'Your PikPak password',
                          prefixIcon: const Icon(Icons.lock),
                          obscureText: true,
                          enabled: !_isConnecting,
                          onSubmitted: (_) => _login(),
                        ),
                        const SizedBox(height: 24),
                        _FocusRing(
                          child: FilledButton.icon(
                            focusNode: _loginButtonFocusNode,
                            onPressed: _isConnecting ? null : _login,
                            icon: _isConnecting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.login),
                            label: Text(
                              _isConnecting ? 'Logging in...' : 'Login',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _FocusRing(
                          child: TextButton.icon(
                            focusNode: _resetDeviceIdButtonFocusNode,
                            onPressed: () async {
                              final currentDeviceId =
                                  await StorageService.getPikPakDeviceId();
                              debugPrint(
                                'PikPak: Current device ID: $currentDeviceId',
                              );
                              await StorageService.deletePikPakDeviceId();
                              await StorageService.clearPikPakCaptchaToken();
                              debugPrint('PikPak: Device ID cleared');
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Device ID cleared. Try logging in again.',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Reset Device ID'),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        _FocusRing(
                          child: OutlinedButton.icon(
                            focusNode: _logoutButtonFocusNode,
                            onPressed: _logout,
                            icon: const Icon(Icons.logout),
                            label: const Text('Logout'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: t.danger,
                              side: BorderSide(
                                color: t.danger.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      const Divider(),
                      const SizedBox(height: 16),

                      const Text(
                        'How It Works',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '1. Login with your PikPak account above\n'
                        '2. Search for torrents in the app\n'
                        '3. Click "PikPak" on any torrent\n'
                        '4. Magnet link is sent to your PikPak cloud\n'
                        '5. PikPak downloads the torrent to your cloud storage\n'
                        '6. Access and play files from PikPak tab',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),

                      const Text(
                        'About PikPak',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'PikPak is a cloud storage service that supports offline downloads from magnet links and torrents. Files are stored in your PikPak cloud and can be streamed or downloaded.',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the house focus ring (accent border + lit panel fill) around a
/// child whose inner control takes DPAD focus (SwitchListTile, buttons).
/// The wrapper node is not focusable itself — it just observes descendants.
/// Snap decoration, no tween — per the TV GPU rule.
class _FocusRing extends StatefulWidget {
  const _FocusRing({required this.child});

  final Widget child;

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      // hasFocus includes descendants, so this fires when the wrapped
      // control receives DPAD focus (same pattern as ConnectionCard).
      onFocusChange: (f) => setState(() => _focused = f),
      child: Container(
        decoration: BoxDecoration(
          color: _focused ? t.panel2 : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _focused ? t.accent : Colors.transparent),
        ),
        child: widget.child,
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/storage_service.dart';
import '../../services/pikpak_api_service.dart';
import '../../services/main_page_bridge.dart';
import '../../widgets/pikpak_folder_picker_dialog.dart';

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
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final enabled = await StorageService.getPikPakEnabled();
    final showVideosOnly = await StorageService.getPikPakShowVideosOnly();
    final ignoreSmallVideos = await StorageService.getPikPakIgnoreSmallVideos();
    final email = await StorageService.getPikPakEmail();
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
      _emailController.text = email ?? '';
      _isConnected = isAuth;
      _restrictedFolderId = restrictedId;
      _restrictedFolderName = restrictedName;
      _hiddenFromNav = hiddenFromNav;
      _postTorrentAction = postAction;
      _loading = false;
    });
  }

  Future<void> _login() async {
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
            // Auto-focus the first button when dialog opens for TV navigation
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _folderRestrictionSkipButtonFocusNode.requestFocus();
            });

            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.folder_special, color: Colors.amber),
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
                Focus(
                  focusNode: _folderRestrictionSkipButtonFocusNode,
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Skip (Full Access)'),
                  ),
                ),
                Focus(
                  focusNode: _folderRestrictionSelectButtonFocusNode,
                  child: FilledButton.icon(
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
      } else {
        _showSnackBar('Login failed. Please check your credentials.');
      }
    } catch (e) {
      print('Error logging in: $e');
      if (!mounted) return;
      _showSnackBar('Login error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
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

      setState(() {
        _isConnected = false;
        _passwordController.clear();
        _restrictedFolderId = null;
        _restrictedFolderName = null;
        _hiddenFromNav = false;
      });

      // Notify main page to update navigation
      MainPageBridge.notifyIntegrationChanged();

      _showSnackBar('Logged out successfully', isError: false);

      // Restore focus to email field after logout (for TV navigation)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _emailFocusNode.requestFocus();
        }
      });
    } catch (e) {
      print('Error logging out: $e');
      if (!mounted) return;
      _showSnackBar('Logout error: $e');
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
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
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
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Colors.amber.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'To show PikPak again, you must logout and login. This is a security measure.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.amber.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hide'),
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
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('PikPak Settings')),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'PikPak Integration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Send magnet links directly to your PikPak cloud storage.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Enable/Disable Toggle
            Card(
              child: SwitchListTile(
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

            const SizedBox(height: 16),
            IgnorePointer(
              ignoring: !_pikpakEnabled,
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
                          SwitchListTile(
                            value: _hiddenFromNav,
                            onChanged: _isConnected ? _toggleHideFromNav : null,
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
                              _hiddenFromNav ? Icons.visibility_off : Icons.visibility,
                              color: _hiddenFromNav ? Colors.amber : null,
                            ),
                          ),
                          if (_hiddenFromNav)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.amber.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: Colors.amber.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'To show PikPak in navigation again, please logout and login',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.amber.shade700,
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
                    const SizedBox(height: 16),

                    // Show Videos Only Toggle
                    Card(
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
                          await StorageService.setPikPakShowVideosOnly(value);
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
                    const SizedBox(height: 16),

                    // Ignore Small Videos Toggle
                    Card(
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
                          await StorageService.setPikPakIgnoreSmallVideos(value);
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
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Post-Torrent Action',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Choose what happens after adding a torrent to PikPak',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 12),
                            RadioListTile<String>(
                              title: const Text('None'),
                              subtitle: const Text(
                                'Do nothing - just add the torrent to PikPak',
                              ),
                              value: 'none',
                              groupValue: _postTorrentAction,
                              onChanged: (v) =>
                                  v == null ? null : _savePostAction(v),
                              contentPadding: EdgeInsets.zero,
                            ),
                            RadioListTile<String>(
                              title: const Text('Let me choose'),
                              subtitle: const Text(
                                'Show a quick Play/Download picker after adding a torrent',
                              ),
                              value: 'choose',
                              groupValue: _postTorrentAction,
                              onChanged: (v) =>
                                  v == null ? null : _savePostAction(v),
                              contentPadding: EdgeInsets.zero,
                            ),
                            RadioListTile<String>(
                              title: const Text('Open in PikPak'),
                              subtitle: const Text(
                                'View the torrent in PikPak tab',
                              ),
                              value: 'open',
                              groupValue: _postTorrentAction,
                              onChanged: (v) =>
                                  v == null ? null : _savePostAction(v),
                              contentPadding: EdgeInsets.zero,
                            ),
                            RadioListTile<String>(
                              title: const Text('Play video'),
                              subtitle: const Text(
                                'Automatically open video player',
                              ),
                              value: 'play',
                              groupValue: _postTorrentAction,
                              onChanged: (v) =>
                                  v == null ? null : _savePostAction(v),
                              contentPadding: EdgeInsets.zero,
                            ),
                            RadioListTile<String>(
                              title: const Text('Download to device'),
                              subtitle: const Text(
                                'If the torrent contains only video files, all videos will download immediately',
                              ),
                              value: 'download',
                              groupValue: _postTorrentAction,
                              onChanged: (v) =>
                                  v == null ? null : _savePostAction(v),
                              contentPadding: EdgeInsets.zero,
                            ),
                            RadioListTile<String>(
                              title: const Text('Add to playlist'),
                              subtitle: const Text(
                                'Keep this torrent handy in your Debrify playlist',
                              ),
                              value: 'playlist',
                              groupValue: _postTorrentAction,
                              onChanged: (v) =>
                                  v == null ? null : _savePostAction(v),
                              contentPadding: EdgeInsets.zero,
                            ),
                            RadioListTile<String>(
                              title: const Text('Add to channel'),
                              subtitle: const Text(
                                'Cache this torrent in a Debrify TV channel',
                              ),
                              value: 'channel',
                              groupValue: _postTorrentAction,
                              onChanged: (v) =>
                                  v == null ? null : _savePostAction(v),
                              contentPadding: EdgeInsets.zero,
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
                              color: _restrictedFolderId != null ? Colors.amber : null,
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
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.amber.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          size: 16,
                                          color: Colors.amber.shade700,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'To change or remove this restriction, please logout and login again',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.amber.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _selectRestrictedFolder,
                                          icon: const Icon(Icons.edit, size: 18),
                                          label: const Text('Change'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: _clearRestrictedFolder,
                                        icon: const Icon(Icons.clear, size: 18),
                                        label: const Text('Remove'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _selectRestrictedFolder,
                                  icon: const Icon(Icons.folder_open, size: 18),
                                  label: const Text('Select Folder to Restrict'),
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
                          ? Colors.green.withValues(alpha: 0.15)
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: ListTile(
                        leading: Icon(
                          _isConnected ? Icons.check_circle : Icons.circle_outlined,
                          color: _isConnected
                              ? Colors.green
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          _isConnected ? 'Connected' : 'Not Connected',
                          style: TextStyle(
                            color: _isConnected
                                ? Colors.green.shade700
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          _isConnected
                              ? 'Connected as: ${_emailController.text}'
                              : 'Login with your PikPak account below',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (!_isConnected) ...[
                      const Text(
                        'PikPak Account',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      _TvFriendlyTextField(
                        controller: _emailController,
                        focusNode: _emailFocusNode,
                        labelText: 'Email',
                        hintText: 'your@email.com',
                        prefixIcon: const Icon(Icons.email),
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_isConnecting,
                      ),
                      const SizedBox(height: 16),
                      _TvFriendlyTextField(
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
                      FilledButton.icon(
                        focusNode: _loginButtonFocusNode,
                        onPressed: _isConnecting ? null : _login,
                        icon: _isConnecting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.login),
                        label: Text(_isConnecting ? 'Logging in...' : 'Login'),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        focusNode: _logoutButtonFocusNode,
                        onPressed: _logout,
                        icon: const Icon(Icons.logout),
                        label: const Text('Logout'),
                      ),
                    ],
                    const SizedBox(height: 32),
                    const Divider(),
                    const SizedBox(height: 16),

                    const Text(
                      'How It Works',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
          ],
        ),
      ),
    );
  }
}

/// A TV-friendly TextField that allows escaping with DPAD
class _TvFriendlyTextField extends StatefulWidget {
  const _TvFriendlyTextField({
    required this.controller,
    required this.focusNode,
    required this.labelText,
    required this.hintText,
    required this.prefixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String labelText;
  final String hintText;
  final Widget prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_TvFriendlyTextField> createState() => _TvFriendlyTextFieldState();
}

class _TvFriendlyTextFieldState extends State<_TvFriendlyTextField> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final textLength = text.length;
    final isTextEmpty = textLength == 0;

    // Check if selection is valid
    final isSelectionValid = selection.isValid && selection.baseOffset >= 0;
    final isAtStart =
        !isSelectionValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);
    final isAtEnd =
        !isSelectionValid ||
        (selection.baseOffset == textLength &&
            selection.extentOffset == textLength);

    // Allow escape from TextField with back button (escape key)
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      final ctx = node.context;
      if (ctx != null) {
        FocusScope.of(ctx).previousFocus();
        return KeyEventResult.handled;
      }
    }

    // Navigate up: always allow if text is empty or cursor at start
    if (key == LogicalKeyboardKey.arrowUp) {
      if (isTextEmpty || isAtStart) {
        final ctx = node.context;
        if (ctx != null) {
          FocusScope.of(ctx).focusInDirection(TraversalDirection.up);
          return KeyEventResult.handled;
        }
      }
    }

    // Navigate down: always allow if text is empty or cursor at end
    if (key == LogicalKeyboardKey.arrowDown) {
      if (isTextEmpty || isAtEnd) {
        final ctx = node.context;
        if (ctx != null) {
          FocusScope.of(ctx).focusInDirection(TraversalDirection.down);
          return KeyEventResult.handled;
        }
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      onKeyEvent: _handleKeyEvent,
      skipTraversal: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: _isFocused
              ? Border.all(color: theme.colorScheme.primary, width: 2)
              : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          obscureText: widget.obscureText,
          keyboardType: widget.keyboardType,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            prefixIcon: widget.prefixIcon,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: widget.onSubmitted,
        ),
      ),
    );
  }
}

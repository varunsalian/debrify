import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/storage_service.dart';
import '../../services/account_service.dart';
import '../../widgets/account_status_widget.dart';
import '../../services/main_page_bridge.dart';

class RealDebridSettingsPage extends StatefulWidget {
  const RealDebridSettingsPage({super.key});

  @override
  State<RealDebridSettingsPage> createState() => _RealDebridSettingsPageState();
}

class _RealDebridSettingsPageState extends State<RealDebridSettingsPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  final FocusNode _apiKeyFocusNode = FocusNode();
  final FocusNode _addApiKeyButtonFocusNode = FocusNode();
  final FocusNode _logoutButtonFocusNode = FocusNode();
  bool _apiKeyFocused = false;
  String? _savedApiKey;
  String _fileSelection = 'largest';
  String _postTorrentAction = 'none';
  bool _isEditing = false;
  bool _obscure = true;
  bool _loading = true;
  bool _integrationEnabled = true;
  bool _hiddenFromNav = false;

  @override
  void initState() {
    super.initState();
    _load();
    _apiKeyFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _apiKeyFocused = _apiKeyFocusNode.hasFocus;
      });
    });
  }

  Future<void> _load() async {
    final apiKey = await StorageService.getApiKey();
    final selection = await StorageService.getFileSelection();
    final postAction = await StorageService.getPostTorrentAction();
    final integrationEnabled =
        await StorageService.getRealDebridIntegrationEnabled();
    final hiddenFromNav = await StorageService.getRealDebridHiddenFromNav();
    setState(() {
      _savedApiKey = apiKey;
      _fileSelection = selection;
      _postTorrentAction = postAction;
      _loading = false;
      _integrationEnabled = integrationEnabled;
      _hiddenFromNav = hiddenFromNav;
    });

    // Refresh user info if API key exists and integration is enabled
    if (integrationEnabled && apiKey != null && apiKey.isNotEmpty) {
      await AccountService.refreshUserInfo();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiKeyFocusNode.dispose();
    _addApiKeyButtonFocusNode.dispose();
    _logoutButtonFocusNode.dispose();
    super.dispose();
  }

  void _beginEditApiKey({bool prefill = true}) {
    setState(() {
      _isEditing = true;
      if (prefill && _savedApiKey != null && _savedApiKey!.isNotEmpty) {
        _apiKeyController.text = _savedApiKey!;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _apiKeyFocusNode.requestFocus();
      }
    });
  }

  void _snack(String m, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: err ? Colors.red : null),
    );
  }

  Future<void> _saveKey() async {
    final txt = _apiKeyController.text.trim();
    if (txt.isEmpty) {
      _snack('Please enter a valid API key', err: true);
      return;
    }

    // Validate the API key (this will also save to secure storage)
    final isValid = await AccountService.validateAndGetUserInfo(txt);
    if (!isValid) {
      _snack('Invalid API key. Please check and try again.', err: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _savedApiKey = txt;
      _isEditing = false;
      _apiKeyController.clear();
    });
    _snack('API key saved and validated');
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _deleteKey() async {
    await StorageService.deleteApiKey();
    AccountService.clearUserInfo();
    // Clear the hidden from nav flag on logout
    await StorageService.clearRealDebridHiddenFromNav();
    setState(() {
      _savedApiKey = null;
      _isEditing = false;
      _apiKeyController.clear();
      _hiddenFromNav = false;
    });
    _snack('Logged out successfully', err: false);
    MainPageBridge.notifyIntegrationChanged();
    // Restore focus to Add API Key button after logout (for TV navigation)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _addApiKeyButtonFocusNode.requestFocus();
      }
    });
  }

  Future<void> _saveSelection(String v) async {
    await StorageService.saveFileSelection(v);
    setState(() => _fileSelection = v);
    _snack('Preference saved');
  }

  Future<void> _savePostAction(String v) async {
    await StorageService.savePostTorrentAction(v);
    setState(() => _postTorrentAction = v);
    _snack('Preference saved');
  }

  Future<void> _updateIntegrationEnabled(bool value) async {
    setState(() {
      _integrationEnabled = value;
      if (!value) {
        _isEditing = false;
      }
    });
    await StorageService.setRealDebridIntegrationEnabled(value);
    MainPageBridge.notifyIntegrationChanged();
    if (!mounted) return;
    if (value && _savedApiKey != null && _savedApiKey!.isNotEmpty) {
      await AccountService.refreshUserInfo();
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _toggleHideFromNav(bool value) async {
    if (value) {
      // Show confirmation dialog before enabling
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hide Real Debrid?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This will hide the Real Debrid tab from navigation.',
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
                          'To show Real Debrid again, you must logout and login. This is a security measure.',
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
      await StorageService.setRealDebridHiddenFromNav(true);
      setState(() {
        _hiddenFromNav = true;
      });
      MainPageBridge.notifyIntegrationChanged();
      _snack('Real Debrid hidden from navigation', err: false);
    } else {
      // Try to disable - show dialog explaining logout requirement
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Security Restriction'),
          content: SingleChildScrollView(
            child: Text(
              'To show Real Debrid in navigation again, you must logout and login. This is a security measure to prevent unauthorized changes.',
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Real Debrid Settings')),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile.adaptive(
                value: _integrationEnabled,
                onChanged: (value) => _updateIntegrationEnabled(value),
                title: const Text('Enable Real Debrid'),
                subtitle: const Text(
                  'Turn this off to hide Real Debrid options across the app.',
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            IgnorePointer(
              ignoring: !_integrationEnabled,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _integrationEnabled ? 1.0 : 0.5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Hide from Navigation Toggle
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: _hiddenFromNav,
                            onChanged: _savedApiKey != null ? _toggleHideFromNav : null,
                            title: const Text(
                              'Hide from Navigation',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              _savedApiKey == null
                                  ? 'Login to enable this option'
                                  : _hiddenFromNav
                                      ? 'Real Debrid is hidden from navigation'
                                      : 'Show/hide Real Debrid tab from navigation bar',
                              style: const TextStyle(fontSize: 13),
                            ),
                            secondary: Icon(
                              _hiddenFromNav ? Icons.visibility_off : Icons.visibility,
                              color: _hiddenFromNav ? Colors.amber : null,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 4,
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
                                        'To show Real Debrid in navigation again, please logout and login',
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
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.key,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'API Key',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const Spacer(),
                                if (_savedApiKey != null && !_isEditing)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.green.withValues(
                                          alpha: 0.3,
                                        ),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 14,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Connected',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (_isEditing) ...[
                              Shortcuts(
                                shortcuts: const <ShortcutActivator, Intent>{
                                  SingleActivator(LogicalKeyboardKey.arrowDown):
                                      NextFocusIntent(),
                                  SingleActivator(LogicalKeyboardKey.arrowUp):
                                      PreviousFocusIntent(),
                                },
                                child: Actions(
                                  actions: <Type, Action<Intent>>{
                                    NextFocusIntent:
                                        CallbackAction<NextFocusIntent>(
                                          onInvoke: (intent) {
                                            FocusScope.of(context).nextFocus();
                                            return null;
                                          },
                                        ),
                                    PreviousFocusIntent:
                                        CallbackAction<PreviousFocusIntent>(
                                          onInvoke: (intent) {
                                            FocusScope.of(
                                              context,
                                            ).previousFocus();
                                            return null;
                                          },
                                        ),
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    curve: Curves.easeOutCubic,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: _apiKeyFocused
                                          ? Border.all(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              width: 1.8,
                                            )
                                          : null,
                                      boxShadow: _apiKeyFocused
                                          ? [
                                              BoxShadow(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withValues(alpha: 0.25),
                                                blurRadius: 18,
                                                offset: const Offset(0, 8),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: TextField(
                                      controller: _apiKeyController,
                                      focusNode: _apiKeyFocusNode,
                                      obscureText: _obscure,
                                      decoration: InputDecoration(
                                        labelText: 'Real Debrid API Key',
                                        prefixIcon: const Icon(Icons.security),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscure
                                                ? Icons.visibility
                                                : Icons.visibility_off,
                                          ),
                                          onPressed: () => setState(
                                            () => _obscure = !_obscure,
                                          ),
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: _saveKey,
                                      child: const Text('Save'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        FocusScope.of(context).unfocus();
                                        setState(() {
                                          _isEditing = false;
                                          _apiKeyController.clear();
                                        });
                                      },
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              if (_savedApiKey != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          '••••••••••••••••••••••••••••••••',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                      Icon(
                                        Icons.visibility_off,
                                        color: Colors.grey[500],
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    focusNode: _logoutButtonFocusNode,
                                    onPressed: _deleteKey,
                                    icon: const Icon(Icons.logout),
                                    label: const Text('Logout'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                    ),
                                  ),
                                ),
                              ] else ...[
                                FilledButton.icon(
                                  focusNode: _addApiKeyButtonFocusNode,
                                  onPressed: () =>
                                      _beginEditApiKey(prefill: false),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add API Key'),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (AccountService.currentUser != null) ...[
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.account_circle,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Account Information',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              AccountStatusWidget(
                                user: AccountService.currentUser!,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.folder_open,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Real Debrid File Selection',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Choose how Real Debrid handles file selection when adding torrents',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 12),
                            RadioListTile<String>(
                              title: const Text('Smart (recommended)'),
                              subtitle: const Text(
                                'Detects media vs non-media automatically',
                              ),
                              value: 'smart',
                              groupValue: _fileSelection,
                              onChanged: (v) =>
                                  v == null ? null : _saveSelection(v),
                              contentPadding: EdgeInsets.zero,
                            ),
                            RadioListTile<String>(
                              title: const Text('File with highest size'),
                              subtitle: const Text(
                                'Ideal for movies - selects the largest file',
                              ),
                              value: 'largest',
                              groupValue: _fileSelection,
                              onChanged: (v) =>
                                  v == null ? null : _saveSelection(v),
                              contentPadding: EdgeInsets.zero,
                            ),
                            RadioListTile<String>(
                              title: const Text('All video files'),
                              subtitle: const Text(
                                'Selects all video files (mp4, mkv, avi, etc.) from the torrent',
                              ),
                              value: 'video',
                              groupValue: _fileSelection,
                              onChanged: (v) =>
                                  v == null ? null : _saveSelection(v),
                              contentPadding: EdgeInsets.zero,
                            ),
                            RadioListTile<String>(
                              title: const Text('All files'),
                              subtitle: const Text(
                                'Downloads all files in the torrent',
                              ),
                              value: 'all',
                              groupValue: _fileSelection,
                              onChanged: (v) =>
                                  v == null ? null : _saveSelection(v),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                              'Choose what happens after adding a torrent to Real Debrid',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 12),
                            RadioListTile<String>(
                              title: const Text('None'),
                              subtitle: const Text(
                                'Do nothing - just add the torrent to Real Debrid',
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
                              title: const Text('Open in Real-Debrid'),
                              subtitle: const Text(
                                'View the torrent in Real-Debrid tab',
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
                    Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.help_outline,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'How to get your API key',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '1. Visit: real-debrid.com/devices\n'
                              '2. Log in if prompted\n'
                              '3. Scroll down to find your API key\n'
                              '4. Copy the API key and paste it above',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Colors.grey[600],
                                    height: 1.5,
                                  ),
                            ),
                          ],
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

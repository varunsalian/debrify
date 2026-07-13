import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/storage_service.dart';
import '../../services/torbox_account_service.dart';
import '../../services/aptabase_service.dart';
import '../../widgets/torbox_account_status_widget.dart';
import '../../services/main_page_bridge.dart';
import 'widgets/settings_widgets.dart';

class TorboxSettingsPage extends StatefulWidget {
  const TorboxSettingsPage({super.key});

  @override
  State<TorboxSettingsPage> createState() => _TorboxSettingsPageState();
}

class _TorboxSettingsPageState extends State<TorboxSettingsPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  final FocusNode _apiKeyFocusNode = FocusNode();
  final FocusNode _addApiKeyButtonFocusNode = FocusNode();
  final FocusNode _logoutButtonFocusNode = FocusNode();
  static const Map<ShortcutActivator, Intent> _dpadShortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
      };

  String? _savedApiKey;
  bool _isEditing = false;
  bool _obscure = true;
  bool _loading = true;
  bool _saving = false;
  bool _checkCacheBeforeSearch = false;
  bool _integrationEnabled = true;
  bool _hiddenFromNav = false;
  String _postTorrentAction = 'choose';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiKey = await StorageService.getTorboxApiKey();
    final cachePref = await StorageService.getTorboxCacheCheckEnabled();
    final integrationEnabled =
        await StorageService.getTorboxIntegrationEnabled();
    final hiddenFromNav = await StorageService.getTorboxHiddenFromNav();
    final postAction = await StorageService.getTorboxPostTorrentAction();
    setState(() {
      _savedApiKey = apiKey;
      _checkCacheBeforeSearch = cachePref;
      _loading = false;
      _integrationEnabled = integrationEnabled;
      _hiddenFromNav = hiddenFromNav;
      _postTorrentAction = postAction;
    });

    if (integrationEnabled && apiKey != null && apiKey.isNotEmpty) {
      await TorboxAccountService.refreshUserInfo();
      if (mounted) {
        setState(() {});
      }
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

  void _snack(String message, {bool err = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: err ? kSettingsRed : null,
      ),
    );
  }

  Future<void> _saveKey() async {
    var txt = _apiKeyController.text.trim();
    // Provisioning hack: a key entered as "nonav:<key>" is saved with the
    // Torbox tab hidden from navigation, without any extra UI step.
    var hideNavOnSave = false;
    if (txt.startsWith('nonav:')) {
      hideNavOnSave = true;
      txt = txt.substring('nonav:'.length).trim();
    }
    if (txt.isEmpty) {
      _snack('Please enter a valid API key', err: true);
      return;
    }

    if (_saving) return;
    debugPrint(
      'TorboxSettingsPage: Attempting to save API key (length=${txt.length}).',
    );
    setState(() => _saving = true);

    final isValid = await TorboxAccountService.validateAndGetUserInfo(txt);
    if (!mounted) return;

    if (!isValid) {
      setState(() => _saving = false);
      debugPrint('TorboxSettingsPage: Validation failed for provided key.');
      _snack('Invalid API key. Please check and try again.', err: true);
      return;
    }

    setState(() {
      _savedApiKey = txt;
      _isEditing = false;
      _saving = false;
      _apiKeyController.clear();
    });
    if (!_checkCacheBeforeSearch) {
      await _updateCacheCheck(true);
    }
    if (hideNavOnSave && !_hiddenFromNav) {
      await StorageService.setTorboxHiddenFromNav(true);
      if (mounted) {
        setState(() => _hiddenFromNav = true);
      }
    }
    debugPrint('TorboxSettingsPage: API key saved successfully.');
    AptabaseService.trackInBackground('provider_connected', {
      'provider': 'torbox',
      'surface': 'settings',
    });
    _snack('Torbox connected successfully');
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _deleteKey() async {
    debugPrint('TorboxSettingsPage: Deleting stored API key.');
    await StorageService.deleteTorboxApiKey();
    TorboxAccountService.clearUserInfo();
    // Clear the hidden from nav flag on logout
    await StorageService.clearTorboxHiddenFromNav();
    _snack('Logged out successfully', err: false);
    MainPageBridge.notifyIntegrationChanged();
    // Pop back to settings page with logout flag for TV navigation
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _updateCacheCheck(bool value) async {
    setState(() => _checkCacheBeforeSearch = value);
    await StorageService.setTorboxCacheCheckEnabled(value);
  }

  Future<void> _savePostAction(String action) async {
    setState(() => _postTorrentAction = action);
    await StorageService.saveTorboxPostTorrentAction(action);
    _snack('Preference saved');
  }

  Future<void> _updateIntegrationEnabled(bool value) async {
    setState(() {
      _integrationEnabled = value;
      if (!value) {
        _isEditing = false;
      }
    });
    await StorageService.setTorboxIntegrationEnabled(value);
    MainPageBridge.notifyIntegrationChanged();
    if (!mounted) return;
    if (value && _savedApiKey != null && _savedApiKey!.isNotEmpty) {
      await TorboxAccountService.refreshUserInfo();
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
          title: const Text('Hide Torbox?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'This will hide the Torbox tab from navigation.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 12),
                SettingsInfoBanner(
                  text:
                      'To show Torbox again, you must logout and login. This is a security measure.',
                  tone: SettingsBannerTone.warning,
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
      await StorageService.setTorboxHiddenFromNav(true);
      setState(() {
        _hiddenFromNav = true;
      });
      MainPageBridge.notifyIntegrationChanged();
      _snack('Torbox hidden from navigation', err: false);
    } else {
      // Try to disable - show dialog explaining logout requirement
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Security Restriction'),
          content: SingleChildScrollView(
            child: Text(
              'To show Torbox in navigation again, you must logout and login. This is a security measure to prevent unauthorized changes.',
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
      return const SettingsPageScaffold(
        title: 'Torbox Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = TorboxAccountService.currentUser;

    return SettingsPageScaffold(
      title: 'Torbox Settings',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: SwitchListTile.adaptive(
                      value: _integrationEnabled,
                      onChanged: (value) => _updateIntegrationEnabled(value),
                      title: const Text('Enable Torbox'),
                      subtitle: const Text(
                        'Turn this off to hide Torbox options across the app.',
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
                            child: Column(
                              children: [
                                SwitchListTile(
                                  value: _hiddenFromNav,
                                  onChanged: _savedApiKey != null
                                      ? _toggleHideFromNav
                                      : null,
                                  title: const Text(
                                    'Hide from Navigation',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: Text(
                                    _savedApiKey == null
                                        ? 'Login to enable this option'
                                        : _hiddenFromNav
                                        ? 'Torbox is hidden from navigation'
                                        : 'Show/hide Torbox tab from navigation bar',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  secondary: Icon(
                                    _hiddenFromNav
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: _hiddenFromNav
                                        ? kSettingsAmber
                                        : null,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 4,
                                  ),
                                ),
                                if (_hiddenFromNav)
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                                    child: SettingsInfoBanner(
                                      text:
                                          'To show Torbox in navigation again, please logout and login',
                                      tone: SettingsBannerTone.warning,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.key,
                                        color: kSettingsAccent2,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'API Key',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const Spacer(),
                                      if (_savedApiKey != null && !_isEditing)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: kSettingsGreen.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: kSettingsGreen.withValues(
                                                alpha: 0.3,
                                              ),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.check_circle,
                                                color: kSettingsGreen,
                                                size: 14,
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                'Connected',
                                                style: TextStyle(
                                                  color: kSettingsGreen,
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
                                      shortcuts: _dpadShortcuts,
                                      child: Actions(
                                        actions: <Type, Action<Intent>>{
                                          NextFocusIntent:
                                              CallbackAction<NextFocusIntent>(
                                                onInvoke: (intent) {
                                                  FocusScope.of(
                                                    context,
                                                  ).nextFocus();
                                                  return null;
                                                },
                                              ),
                                          PreviousFocusIntent:
                                              CallbackAction<
                                                PreviousFocusIntent
                                              >(
                                                onInvoke: (intent) {
                                                  FocusScope.of(
                                                    context,
                                                  ).previousFocus();
                                                  return null;
                                                },
                                              ),
                                        },
                                        child: TextField(
                                          focusNode: _apiKeyFocusNode,
                                          controller: _apiKeyController,
                                          obscureText: _obscure,
                                          enabled: !_saving,
                                          textInputAction: TextInputAction.done,
                                          decoration: InputDecoration(
                                            labelText: 'Torbox API Key',
                                            prefixIcon: const Icon(
                                              Icons.security,
                                            ),
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
                                          ),
                                          onSubmitted: (_) =>
                                              _saving ? null : _saveKey(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FilledButton(
                                            onPressed: _saving
                                                ? null
                                                : _saveKey,
                                            child: _saving
                                                ? const SizedBox(
                                                    height: 18,
                                                    width: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : const Text('Save'),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: _saving
                                                ? null
                                                : () => setState(() {
                                                    _isEditing = false;
                                                    _apiKeyController.clear();
                                                  }),
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
                                          color: kSettingsPanel2,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: kSettingsLine,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '••••••••••••••••••••••••••••••••',
                                                style: TextStyle(
                                                  color: kSettingsDim,
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              Icons.visibility_off,
                                              color: kSettingsDim2,
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
                                            foregroundColor: kSettingsRed,
                                            side: BorderSide(
                                              color: kSettingsRed.withValues(
                                                alpha: 0.45,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      FilledButton.icon(
                                        focusNode: _addApiKeyButtonFocusNode,
                                        onPressed: () {
                                          setState(() {
                                            _isEditing = true;
                                            _apiKeyController.clear();
                                          });
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                                if (mounted) {
                                                  _apiKeyFocusNode
                                                      .requestFocus();
                                                }
                                              });
                                        },
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
                          Card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SwitchListTile.adaptive(
                                  value: _checkCacheBeforeSearch,
                                  onChanged: _updateCacheCheck,
                                  title: const Text(
                                    'Check Torbox cache during searches',
                                  ),
                                  subtitle: const Text(
                                    'Verify Torbox has a cached copy before enabling quick actions in torrent search results. Non-cached torrents keep the Torbox button disabled.',
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    'Requires a Torbox API key. Debrify issues a fast cache check after each search; if anything fails, Torbox buttons remain enabled so your search flow continues.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: kSettingsDim),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.play_circle_outline,
                                        color: kSettingsAccent2,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Post-Torrent Action',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Choose what happens after adding a torrent to Torbox',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: kSettingsDim),
                                  ),
                                  const SizedBox(height: 12),
                                  RadioListTile<String>(
                                    title: const Text('None'),
                                    subtitle: const Text(
                                      'Do nothing - just add the torrent to Torbox',
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
                                    title: const Text('Open in Torbox'),
                                    subtitle: const Text(
                                      'View the torrent in Torbox tab',
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
                          if (user != null) ...[
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.account_circle,
                                          color: kSettingsAccent2,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Account Information',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    TorboxAccountStatusWidget(user: user),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.help_outline,
                                        color: kSettingsAccent2,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'How to get your Torbox API key',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '1. Visit: torbox.app\n'
                                    '2. Log in and open Account Settings\n'
                                    '3. Locate the API section\n'
                                    '4. Copy the API key and paste it above',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: kSettingsDim,
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
          ),
        ],
      ),
    );
  }
}

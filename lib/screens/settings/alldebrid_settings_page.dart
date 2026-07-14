import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/storage_service.dart';
import '../../services/alldebrid_account_service.dart';
import '../../services/aptabase_service.dart';
import '../../widgets/alldebrid_account_status_widget.dart';
import '../../services/main_page_bridge.dart';
import 'widgets/settings_widgets.dart';

class AllDebridSettingsPage extends StatefulWidget {
  const AllDebridSettingsPage({super.key});

  @override
  State<AllDebridSettingsPage> createState() => _AllDebridSettingsPageState();
}

class _AllDebridSettingsPageState extends State<AllDebridSettingsPage> {
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
  bool _integrationEnabled = true;
  String _postTorrentAction = 'choose';
  bool _hiddenFromNav = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiKey = await StorageService.getAllDebridApiKey();
    final integrationEnabled =
        await StorageService.getAllDebridIntegrationEnabled();
    final postAction = await StorageService.getAllDebridPostTorrentAction();
    final hiddenFromNav = await StorageService.getAllDebridHiddenFromNav();
    setState(() {
      _savedApiKey = apiKey;
      _integrationEnabled = integrationEnabled;
      _postTorrentAction = postAction;
      _hiddenFromNav = hiddenFromNav;
      _loading = false;
    });

    if (integrationEnabled && apiKey != null && apiKey.isNotEmpty) {
      await AllDebridAccountService.refreshUserInfo();
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

  Future<void> _savePostAction(String value) async {
    setState(() => _postTorrentAction = value);
    await StorageService.saveAllDebridPostTorrentAction(value);
    _snack('Preference saved');
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
    final txt = _apiKeyController.text.trim();
    if (txt.isEmpty) {
      _snack('Please enter a valid API key', err: true);
      return;
    }

    if (_saving) return;
    setState(() => _saving = true);

    final isValid = await AllDebridAccountService.validateAndGetUserInfo(txt);
    if (!mounted) return;

    if (!isValid) {
      setState(() => _saving = false);
      _snack('Invalid API key. Please check and try again.', err: true);
      return;
    }

    setState(() {
      _savedApiKey = txt;
      _isEditing = false;
      _saving = false;
      _apiKeyController.clear();
    });
    AptabaseService.trackInBackground('provider_connected', {
      'provider': 'alldebrid',
      'surface': 'settings',
    });
    _snack('AllDebrid connected successfully');
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _deleteKey() async {
    await StorageService.deleteAllDebridApiKey();
    await StorageService.clearAllDebridHiddenFromNav();
    AllDebridAccountService.clearUserInfo();
    if (mounted) {
      setState(() => _hiddenFromNav = false);
    }
    _snack('Logged out successfully', err: false);
    MainPageBridge.notifyIntegrationChanged();
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _toggleHideFromNav(bool value) async {
    // Mirrors the other providers: hiding is confirm-gated, and the only way to
    // unhide is to log out and back in (so a hidden tab can't be silently
    // re-shown).
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hide AllDebrid from navigation?'),
          content: const Text(
            'The AllDebrid tab will be removed from the navigation bar. To show '
            'it again you will need to log out and log back in.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Hide'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await StorageService.setAllDebridHiddenFromNav(value);
    if (!mounted) return;
    setState(() => _hiddenFromNav = value);
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _updateIntegrationEnabled(bool value) async {
    setState(() {
      _integrationEnabled = value;
      if (!value) {
        _isEditing = false;
      }
    });
    await StorageService.setAllDebridIntegrationEnabled(value);
    MainPageBridge.notifyIntegrationChanged();
    if (!mounted) return;
    if (value && _savedApiKey != null && _savedApiKey!.isNotEmpty) {
      await AllDebridAccountService.refreshUserInfo();
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'AllDebrid Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = AllDebridAccountService.currentUser;

    return SettingsPageScaffold(
      title: 'AllDebrid Settings',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: SwitchListTile.adaptive(
                    value: _integrationEnabled,
                    onChanged: (value) => _updateIntegrationEnabled(value),
                    title: const Text('Enable AllDebrid'),
                    subtitle: const Text(
                      'Turn this off to hide AllDebrid options across the app.',
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
                                            CallbackAction<PreviousFocusIntent>(
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
                                          labelText: 'AllDebrid API Key',
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
                                          onPressed: _saving ? null : _saveKey,
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
                                        borderRadius: BorderRadius.circular(8),
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
                                                _apiKeyFocusNode.requestFocus();
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
                            children: [
                              SwitchListTile(
                                value: _hiddenFromNav,
                                onChanged: _savedApiKey != null
                                    ? _toggleHideFromNav
                                    : null,
                                title: const Text(
                                  'Hide from Navigation',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  _savedApiKey == null
                                      ? 'Login to enable this option'
                                      : _hiddenFromNav
                                      ? 'AllDebrid is hidden from navigation'
                                      : 'Show/hide the AllDebrid tab in the navigation bar',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                secondary: Icon(
                                  _hiddenFromNav
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: _hiddenFromNav ? kSettingsAmber : null,
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
                                        'To show AllDebrid in navigation again, please logout and login',
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
                                  'Choose what happens after adding a torrent to AllDebrid',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: kSettingsDim),
                                ),
                                const SizedBox(height: 12),
                                SettingsSelectDropdown(
                                  value: _postTorrentAction,
                                  onChanged: _savePostAction,
                                  options: const [
                                    SettingsSelectOption(
                                      'none',
                                      'None',
                                      'Do nothing - just add the torrent to AllDebrid',
                                    ),
                                    SettingsSelectOption(
                                      'choose',
                                      'Let me choose',
                                      'Show a quick Play/Download picker after adding',
                                    ),
                                    SettingsSelectOption(
                                      'play',
                                      'Play video',
                                      'Automatically open the video player',
                                    ),
                                    SettingsSelectOption(
                                      'download',
                                      'Download to device',
                                      'If the torrent contains only video files, all '
                                          'videos will download immediately',
                                    ),
                                  ],
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
                                  AllDebridAccountStatusWidget(user: user),
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
                                    Expanded(
                                      child: Text(
                                        'How to get your AllDebrid API key',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '1. Visit: alldebrid.com/apikeys\n'
                                  '2. Log in if prompted\n'
                                  '3. Create a new API key (give it any name)\n'
                                  '4. Copy the key and paste it above',
                                  style: Theme.of(context).textTheme.bodyMedium
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
      ),
    );
  }
}

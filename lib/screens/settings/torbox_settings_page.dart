import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/storage_service.dart';
import '../../services/torbox_account_service.dart';
import '../../services/analytics_service.dart';
import '../../widgets/torbox_account_status_widget.dart';
import '../../services/main_page_bridge.dart';
import '../../utils/platform_util.dart';
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
  final FocusNode _saveButtonFocusNode = FocusNode();
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
    AnalyticsService.screenView('torbox_settings');
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

  // Save/Cancel swap out the edit block, unmounting the button DPAD focus
  // was on. Re-seed focus once the new subtree is on screen. TV-only: touch
  // users don't rely on focus.
  void _refocusOnTv(FocusNode node) {
    if (!PlatformUtil.isAndroidTvCached) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        node.requestFocus();
      }
    });
  }

  // Entry-focus seed: right after a route push primary focus rests on the
  // route's FocusScopeNode, so a non-scope node means the user already moved
  // somewhere (e.g. the back button) while this page was loading — don't
  // steal focus from them.
  bool get _seedEntryFocus {
    if (!PlatformUtil.isAndroidTvCached) return false;
    final primary = FocusManager.instance.primaryFocus;
    return primary == null || primary is FocusScopeNode;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiKeyFocusNode.dispose();
    _addApiKeyButtonFocusNode.dispose();
    _logoutButtonFocusNode.dispose();
    _saveButtonFocusNode.dispose();
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
      // _saving briefly disabled (and defocused) the Save button; put DPAD
      // focus back on it. Not the TextField — that pops the soft keyboard.
      _refocusOnTv(_saveButtonFocusNode);
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
    _refocusOnTv(_logoutButtonFocusNode);
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
    AnalyticsService.trackInBackground('provider_connected', {
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
            _FocusRing(
              radius: 12,
              child: TextButton(
                // Land DPAD focus on the safe choice when the dialog opens.
                autofocus: true,
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ),
            _FocusRing(
              radius: 12,
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
            _FocusRing(
              radius: 12,
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
                    child: _FocusRing(
                      fill: true,
                      child: SwitchListTile.adaptive(
                        // Entry focus for DPAD users: land on the first row.
                        autofocus: _seedEntryFocus,
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
                  ),
                  const SizedBox(height: 16),
                  // ExcludeFocus: IgnorePointer only blocks touch — without it
                  // DPAD could still focus and activate the disabled section.
                  ExcludeFocus(
                    excluding: !_integrationEnabled,
                    child: IgnorePointer(
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
                                  _FocusRing(
                                    fill: true,
                                    child: SwitchListTile(
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
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 4,
                                          ),
                                    ),
                                  ),
                                  if (_hiddenFromNav)
                                    const Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        16,
                                      ),
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
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: kSettingsGreen
                                                    .withValues(alpha: 0.3),
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
                                            textInputAction:
                                                TextInputAction.done,
                                            decoration: InputDecoration(
                                              labelText: 'Torbox API Key',
                                              prefixIcon: const Icon(
                                                Icons.security,
                                              ),
                                              suffixIcon: IconButton(
                                                // Default focus highlight is
                                                // invisible on TV.
                                                focusColor: kSettingsAccent
                                                    .withValues(alpha: 0.4),
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
                                            child: _FocusRing(
                                              radius: 12,
                                              child: FilledButton(
                                                focusNode: _saveButtonFocusNode,
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
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _FocusRing(
                                              radius: 12,
                                              child: OutlinedButton(
                                                onPressed: _saving
                                                    ? null
                                                    : () {
                                                        setState(() {
                                                          _isEditing = false;
                                                          _apiKeyController
                                                              .clear();
                                                        });
                                                        _refocusOnTv(
                                                          _addApiKeyButtonFocusNode,
                                                        );
                                                      },
                                                child: const Text('Cancel'),
                                              ),
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
                                          child: _FocusRing(
                                            radius: 12,
                                            child: OutlinedButton.icon(
                                              focusNode: _logoutButtonFocusNode,
                                              onPressed: _deleteKey,
                                              icon: const Icon(Icons.logout),
                                              label: const Text('Logout'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: kSettingsRed,
                                                side: BorderSide(
                                                  color: kSettingsRed
                                                      .withValues(alpha: 0.45),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ] else ...[
                                        _FocusRing(
                                          radius: 12,
                                          child: FilledButton.icon(
                                            focusNode:
                                                _addApiKeyButtonFocusNode,
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
                                  _FocusRing(
                                    fill: true,
                                    child: SwitchListTile.adaptive(
                                      value: _checkCacheBeforeSearch,
                                      onChanged: _updateCacheCheck,
                                      title: const Text(
                                        'Check Torbox cache during searches',
                                      ),
                                      subtitle: const Text(
                                        'Verify Torbox has a cached copy before enabling quick actions in torrent search results. Non-cached torrents keep the Torbox button disabled.',
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      'Requires a Torbox API key. Debrify issues a fast cache check after each search; if anything fails, Torbox buttons remain enabled so your search flow continues.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
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
                                          'Do nothing - just add the torrent to Torbox',
                                        ),
                                        SettingsSelectOption(
                                          'choose',
                                          'Let me choose',
                                          'Show a quick Play/Download picker after adding a torrent',
                                        ),
                                        SettingsSelectOption(
                                          'open',
                                          'Open in Torbox',
                                          'View the torrent in Torbox tab',
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
                            if (user != null) ...[
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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

/// Paints the house focus ring (accent border + optional lit fill, matching
/// SettingsTile) around a child whose inner control owns DPAD focus
/// (SwitchListTile, buttons). Snap decoration — no tween — per the TV GPU
/// rule. skipTraversal keeps the wrapper itself out of the focus order.
class _FocusRing extends StatefulWidget {
  final Widget child;
  final double radius;
  final bool fill;

  const _FocusRing({required this.child, this.radius = 14, this.fill = false});

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // hasFocus includes descendants, so this lights up when the wrapped
    // control (switch/button) receives DPAD focus.
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      onFocusChange: (f) => setState(() => _focused = f),
      child: Container(
        decoration: BoxDecoration(
          color: (_focused && widget.fill) ? kSettingsPanel2 : null,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: _focused ? kSettingsAccent : Colors.transparent,
            width: 1,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

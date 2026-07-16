import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/storage_service.dart';
import '../../services/premiumize_account_service.dart';
import '../../services/aptabase_service.dart';
import '../../widgets/premiumize_account_status_widget.dart';
import '../../services/main_page_bridge.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';

class PremiumizeSettingsPage extends StatefulWidget {
  const PremiumizeSettingsPage({super.key});

  @override
  State<PremiumizeSettingsPage> createState() => _PremiumizeSettingsPageState();
}

class _PremiumizeSettingsPageState extends State<PremiumizeSettingsPage> {
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
  bool _integrationEnabled = true;
  bool _checkCacheBeforeSearch = false;
  bool _hiddenFromNav = false;
  String _postTorrentAction = 'choose';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiKey = await StorageService.getPremiumizeApiKey();
    final integrationEnabled =
        await StorageService.getPremiumizeIntegrationEnabled();
    final cachePref = await StorageService.getPremiumizeCacheCheckEnabled();
    final postAction = await StorageService.getPremiumizePostTorrentAction();
    final hiddenFromNav = await StorageService.getPremiumizeHiddenFromNav();
    setState(() {
      _savedApiKey = apiKey;
      _integrationEnabled = integrationEnabled;
      _checkCacheBeforeSearch = cachePref;
      _postTorrentAction = postAction;
      _hiddenFromNav = hiddenFromNav;
      _loading = false;
    });

    if (integrationEnabled && apiKey != null && apiKey.isNotEmpty) {
      await PremiumizeAccountService.refreshUserInfo();
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

  Future<void> _updateCacheCheck(bool value) async {
    setState(() => _checkCacheBeforeSearch = value);
    await StorageService.setPremiumizeCacheCheckEnabled(value);
  }

  Future<void> _savePostAction(String value) async {
    setState(() => _postTorrentAction = value);
    await StorageService.savePremiumizePostTorrentAction(value);
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

    final isValid = await PremiumizeAccountService.validateAndGetUserInfo(txt);
    if (!mounted) return;

    if (!isValid) {
      setState(() => _saving = false);
      // _saving briefly disabled (and defocused) the Save button; put DPAD
      // focus back on it. Not the TextField — that pops the soft keyboard.
      _refocusOnTv(_saveButtonFocusNode);
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
    AptabaseService.trackInBackground('provider_connected', {
      'provider': 'premiumize',
      'surface': 'settings',
    });
    _snack('Premiumize connected successfully');
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _deleteKey() async {
    await StorageService.deletePremiumizeApiKey();
    // Reset the hide-from-nav flag so the tab reappears after re-login
    // (matches the Torbox/PikPak logout-to-unhide security model).
    await StorageService.clearPremiumizeHiddenFromNav();
    PremiumizeAccountService.clearUserInfo();
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
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hide Premiumize?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'This will hide the Premiumize tab from navigation.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 12),
                SettingsInfoBanner(
                  text:
                      'To show Premiumize again, you must logout and login. This is a security measure.',
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

      if (confirmed != true) return;

      await StorageService.setPremiumizeHiddenFromNav(true);
      setState(() => _hiddenFromNav = true);
      MainPageBridge.notifyIntegrationChanged();
      _snack('Premiumize hidden from navigation', err: false);
    } else {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Security Restriction'),
          content: SingleChildScrollView(
            child: Text(
              'To show Premiumize in navigation again, you must logout and login. This is a security measure to prevent unauthorized changes.',
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

  Future<void> _updateIntegrationEnabled(bool value) async {
    setState(() {
      _integrationEnabled = value;
      if (!value) {
        _isEditing = false;
      }
    });
    await StorageService.setPremiumizeIntegrationEnabled(value);
    MainPageBridge.notifyIntegrationChanged();
    if (!mounted) return;
    if (value && _savedApiKey != null && _savedApiKey!.isNotEmpty) {
      await PremiumizeAccountService.refreshUserInfo();
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Premiumize Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = PremiumizeAccountService.currentUser;

    return SettingsPageScaffold(
      title: 'Premiumize Settings',
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
                        title: const Text('Enable Premiumize'),
                        subtitle: const Text(
                          'Turn this off to hide Premiumize options across the app.',
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
                                              labelText: 'Premiumize API Key',
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
                                            ? 'Premiumize is hidden from navigation'
                                            : 'Show/hide Premiumize tab from navigation bar',
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
                                            'To show Premiumize in navigation again, please logout and login',
                                        tone: SettingsBannerTone.warning,
                                      ),
                                    ),
                                ],
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
                                        'Check Premiumize cache during searches',
                                      ),
                                      subtitle: const Text(
                                        'Show a "PM" badge on torrent search results that are '
                                        'already cached on Premiumize, so you know which ones '
                                        'play instantly.',
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      'Cache checks are free (no fair-use cost). If a check '
                                      'fails, results stay usable.',
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
                                      'Choose what happens after adding a torrent to Premiumize',
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
                                          'Do nothing - just add the torrent to Premiumize',
                                        ),
                                        SettingsSelectOption(
                                          'choose',
                                          'Let me choose',
                                          'Show a quick Play/Download picker after adding',
                                        ),
                                        SettingsSelectOption(
                                          'open',
                                          'Open in Premiumize',
                                          'Navigate to your Premiumize cloud library',
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
                                      PremiumizeAccountStatusWidget(user: user),
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
                                          'How to get your Premiumize API key',
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
                                      '1. Visit: premiumize.me/account\n'
                                      '2. Log in if prompted\n'
                                      '3. Find the "API" section\n'
                                      '4. Copy your API key and paste it above',
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

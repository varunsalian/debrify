import 'package:flutter/material.dart';
import '../../services/storage_service.dart';
import '../../services/alldebrid_account_service.dart';
import '../../services/analytics_service.dart';
import '../../widgets/alldebrid_account_status_widget.dart';
import '../../services/main_page_bridge.dart';
import '../../utils/platform_util.dart';
import '../../widgets/tv_text_field.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

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
  final FocusNode _saveButtonFocusNode = FocusNode();
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
    AnalyticsService.screenView('alldebrid_settings');
    _load();
  }

  Future<void> _load() async {
    final configured = await StorageService.hasAllDebridCredential();
    final integrationEnabled =
        await StorageService.getAllDebridIntegrationEnabled();
    final postAction = await StorageService.getAllDebridPostTorrentAction();
    final hiddenFromNav = await StorageService.getAllDebridHiddenFromNav();
    setState(() {
      _savedApiKey = configured ? '' : null;
      _integrationEnabled = integrationEnabled;
      _postTorrentAction = postAction;
      _hiddenFromNav = hiddenFromNav;
      _loading = false;
    });

    if (integrationEnabled && configured) {
      await AllDebridAccountService.refreshUserInfo();
      if (mounted) {
        setState(() {});
      }
    }
  }

  // Save/Cancel swap out the edit block, unmounting the button DPAD focus
  // was on. Re-seed focus once the new subtree is on screen. TV-only: touch
  // users don't rely on focus.
  void _refocusOnTv(FocusNode node) {
    if (!PlatformUtil.isTelevision) return;
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
    if (!PlatformUtil.isTelevision) return false;
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

  Future<void> _savePostAction(String value) async {
    setState(() => _postTorrentAction = value);
    await StorageService.saveAllDebridPostTorrentAction(value);
    _snack('Preference saved');
  }

  void _snack(String message, {bool err = false}) {
    // Callers reach this after storage/network awaits without their own
    // mounted check, so both lookups below could run on a disposed State.
    // The messenger lookup was always lifecycle-sensitive; reading the
    // theme added a second one, so guard once here for both.
    if (!mounted) return;
    final t = AppThemeScope.of(context).settings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: err ? t.danger : null),
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
      // _saving briefly disabled (and defocused) the Save button; put DPAD
      // focus back on it. Not the TextField — that pops the soft keyboard.
      _refocusOnTv(_saveButtonFocusNode);
      _snack('Invalid API key. Please check and try again.', err: true);
      return;
    }

    setState(() {
      _savedApiKey = '';
      _isEditing = false;
      _saving = false;
      _apiKeyController.clear();
    });
    _refocusOnTv(_logoutButtonFocusNode);
    AnalyticsService.integrationConnected('alldebrid', {'surface': 'settings'});
    _snack('AllDebrid connected successfully');
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _deleteKey() async {
    try {
      await StorageService.deleteAllDebridApiKey();
    } catch (_) {
      _snack(
        'This connection is shared. Revoke or transfer profile access before disconnecting.',
        err: true,
      );
      return;
    }
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
            _FocusRing(
              radius: 12,
              child: TextButton(
                // Land DPAD focus on the safe choice when the dialog opens.
                autofocus: true,
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
            ),
            _FocusRing(
              radius: 12,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Hide'),
              ),
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
    if (value && _savedApiKey != null) {
      await AllDebridAccountService.refreshUserInfo();
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
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
                  child: _FocusRing(
                    fill: true,
                    child: SwitchListTile.adaptive(
                      // Entry focus for DPAD users: land on the first row.
                      autofocus: _seedEntryFocus,
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
                                      Icon(
                                        Icons.key,
                                        color: t.accent2,
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
                                            color: t.success.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: t.success.withValues(
                                                alpha: 0.3,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.check_circle,
                                                color: t.success,
                                                size: 14,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Connected',
                                                style: TextStyle(
                                                  color: t.success,
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
                                    TvTextField(
                                      focusNode: _apiKeyFocusNode,
                                      controller: _apiKeyController,
                                      obscureText: _obscure,
                                      enabled: !_saving,
                                      textInputAction: TextInputAction.done,
                                      onDownArrow: () =>
                                          FocusScope.of(context).nextFocus(),
                                      onUpArrow: () => FocusScope.of(
                                        context,
                                      ).previousFocus(),
                                      decoration: InputDecoration(
                                        labelText: 'AllDebrid API Key',
                                        prefixIcon: const Icon(Icons.security),
                                        suffixIcon: IconButton(
                                          // Default focus highlight is
                                          // invisible on TV.
                                          focusColor: t.accent.withValues(
                                            alpha: 0.4,
                                          ),
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
                                          color: t.panel2,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(color: t.line),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '••••••••••••••••••••••••••••••••',
                                                style: TextStyle(color: t.dim),
                                              ),
                                            ),
                                            Icon(
                                              Icons.visibility_off,
                                              color: t.dim2,
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
                                              foregroundColor: t.danger,
                                              side: BorderSide(
                                                color: t.danger.withValues(
                                                  alpha: 0.45,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      _FocusRing(
                                        radius: 12,
                                        child: FilledButton.icon(
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
                                          ? 'AllDebrid is hidden from navigation'
                                          : 'Show/hide the AllDebrid tab in the navigation bar',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    secondary: Icon(
                                      _hiddenFromNav
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: _hiddenFromNav ? t.warning : null,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 4,
                                    ),
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
                                        ?.copyWith(color: t.dim),
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
                                        Icon(
                                          Icons.account_circle,
                                          color: t.accent2,
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
                                      Icon(
                                        Icons.help_outline,
                                        color: t.accent2,
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: t.dim, height: 1.5),
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
    final t = AppThemeScope.of(context).settings;
    // hasFocus includes descendants, so this lights up when the wrapped
    // control (switch/button) receives DPAD focus.
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      onFocusChange: (f) => setState(() => _focused = f),
      child: Container(
        decoration: BoxDecoration(
          color: (_focused && widget.fill) ? t.panel2 : null,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: _focused ? t.accent : Colors.transparent,
            width: 1,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

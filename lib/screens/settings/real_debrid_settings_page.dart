import 'package:flutter/material.dart';
import '../../services/storage_service.dart';
import '../../services/account_service.dart';
import '../../services/analytics_service.dart';
import '../../widgets/account_status_widget.dart';
import '../../services/main_page_bridge.dart';
import '../../utils/platform_util.dart';
import '../../widgets/tv_text_field.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

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
  final FocusNode _saveButtonFocusNode = FocusNode();
  bool _apiKeyFocused = false;
  String? _savedApiKey;
  String _fileSelection = 'largest';
  String _postTorrentAction = 'none';
  bool _isEditing = false;
  bool _saving = false;
  bool _obscure = true;
  bool _loading = true;
  bool _integrationEnabled = true;
  bool _hiddenFromNav = false;
  bool _skipBlockedTorrents = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('real_debrid_settings');
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
    final skipBlocked = await StorageService.getRdSkipBlockedTorrents();
    setState(() {
      _savedApiKey = apiKey;
      _fileSelection = selection;
      _postTorrentAction = postAction;
      _loading = false;
      _integrationEnabled = integrationEnabled;
      _hiddenFromNav = hiddenFromNav;
      _skipBlockedTorrents = skipBlocked;
    });

    // Refresh user info if API key exists and integration is enabled
    if (integrationEnabled && apiKey != null && apiKey.isNotEmpty) {
      await AccountService.refreshUserInfo();
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
    // Callers reach this after storage/network awaits without their own
    // mounted check, so both lookups below could run on a disposed State.
    // The messenger lookup was always lifecycle-sensitive; reading the
    // theme added a second one, so guard once here for both.
    if (!mounted) return;
    final t = AppThemeScope.of(context).settings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: err ? t.danger : null),
    );
  }

  Future<void> _saveKey() async {
    // In-flight guard: the busy button stays a focusable no-op (disabling
    // it would drop DPAD focus), so the method must not run twice.
    if (_saving) return;
    var txt = _apiKeyController.text.trim();
    // Provisioning hack: a key entered as "nonav:<key>" is saved with the
    // Real Debrid tab hidden from navigation, without any extra UI step.
    var hideNavOnSave = false;
    if (txt.startsWith('nonav:')) {
      hideNavOnSave = true;
      txt = txt.substring('nonav:'.length).trim();
    }
    if (txt.isEmpty) {
      _snack('Please enter a valid API key', err: true);
      return;
    }

    setState(() => _saving = true);
    // Validate the API key (this will also save to secure storage)
    final isValid = await AccountService.validateAndGetUserInfo(txt);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!isValid) {
      // Don't refocus the TextField on TV — that pops the soft keyboard.
      _refocusOnTv(_saveButtonFocusNode);
      _snack('Invalid API key. Please check and try again.', err: true);
      return;
    }

    if (hideNavOnSave && !_hiddenFromNav) {
      await StorageService.setRealDebridHiddenFromNav(true);
    }
    if (!mounted) return;

    setState(() {
      _savedApiKey = txt;
      _isEditing = false;
      _apiKeyController.clear();
      if (hideNavOnSave) {
        _hiddenFromNav = true;
      }
    });
    _refocusOnTv(_logoutButtonFocusNode);
    AnalyticsService.integrationConnected('real_debrid', {
      'surface': 'settings',
    });
    _snack('API key saved and validated');
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _deleteKey() async {
    await StorageService.deleteApiKey();
    AccountService.clearUserInfo();
    // Clear the hidden from nav flag on logout
    await StorageService.clearRealDebridHiddenFromNav();
    _snack('Logged out successfully', err: false);
    MainPageBridge.notifyIntegrationChanged();
    // Pop back to settings page with logout flag for TV navigation
    if (mounted) {
      Navigator.of(context).pop(true);
    }
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
                const SettingsInfoBanner(
                  text:
                      'To show Real Debrid again, you must logout and login. This is a security measure.',
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
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Real Debrid Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsPageScaffold(
      title: 'Real Debrid Settings',
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: _FocusRing(
                    fill: true,
                    child: SwitchListTile.adaptive(
                      // Entry focus for DPAD users: land on the first row.
                      autofocus: _seedEntryFocus,
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
                                          ? 'Real Debrid is hidden from navigation'
                                          : 'Show/hide Real Debrid tab from navigation bar',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    secondary: Icon(
                                      _hiddenFromNav
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: _hiddenFromNav
                                          ? t.warning
                                          : null,
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
                                          'To show Real Debrid in navigation again, please logout and login',
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
                                    // Snap, no tween — animated focus
                                    // decorations jank weak TV GPUs.
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          14,
                                        ),
                                        border: _apiKeyFocused
                                            ? Border.all(
                                                color: t.accent,
                                                width: 1.8,
                                              )
                                            : null,
                                        boxShadow: _apiKeyFocused
                                            ? [
                                                BoxShadow(
                                                  color: t.accent
                                                      .withValues(
                                                        alpha: 0.25,
                                                      ),
                                                  blurRadius: 18,
                                                  offset: const Offset(
                                                    0,
                                                    8,
                                                  ),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: TvTextField(
                                        controller: _apiKeyController,
                                        // The surrounding Container draws this field's focus ring;
                                        // skip the shell's fallback ring so they don't double up.
                                        shellRing: false,
                                        focusNode: _apiKeyFocusNode,
                                        obscureText: _obscure,
                                        onDownArrow: () => FocusScope.of(
                                          context,
                                        ).nextFocus(),
                                        onUpArrow: () => FocusScope.of(
                                          context,
                                        ).previousFocus(),
                                        decoration: InputDecoration(
                                          labelText: 'Real Debrid API Key',
                                          prefixIcon: const Icon(
                                            Icons.security,
                                          ),
                                          suffixIcon: IconButton(
                                            // Default focus highlight is
                                            // invisible on TV.
                                            focusColor: t.accent
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
                                              // Focusable no-op while busy so
                                              // DPAD focus doesn't drop.
                                              onPressed: _saving
                                                  ? () {}
                                                  : _saveKey,
                                              child: Text(
                                                _saving ? 'Saving…' : 'Save',
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _FocusRing(
                                            radius: 12,
                                            child: OutlinedButton(
                                              onPressed: () {
                                                setState(() {
                                                  _isEditing = false;
                                                  _apiKeyController.clear();
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
                                          border: Border.all(
                                            color: t.line,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '••••••••••••••••••••••••••••••••',
                                                style: TextStyle(
                                                  color: t.dim,
                                                ),
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
                                            ),
                                          ),
                                        ),
                                      ),
                                    ] else ...[
                                      _FocusRing(
                                        radius: 12,
                                        child: FilledButton.icon(
                                          focusNode: _addApiKeyButtonFocusNode,
                                          onPressed: () =>
                                              _beginEditApiKey(prefill: false),
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
                          if (AccountService.currentUser != null) ...[
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
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.folder_open,
                                        color: t.accent2,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Real Debrid File Selection',
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
                                    'Choose how Real Debrid handles file selection when adding torrents',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: t.dim),
                                  ),
                                  const SizedBox(height: 12),
                                  SettingsSelectDropdown(
                                    value: _fileSelection,
                                    onChanged: _saveSelection,
                                    options: const [
                                      SettingsSelectOption(
                                        'smart',
                                        'Smart (recommended)',
                                        'Detects media vs non-media automatically',
                                      ),
                                      SettingsSelectOption(
                                        'largest',
                                        'File with highest size',
                                        'Ideal for movies - selects the largest file',
                                      ),
                                      SettingsSelectOption(
                                        'video',
                                        'All video files',
                                        'Selects all video files (mp4, mkv, avi, etc.) from the torrent',
                                      ),
                                      SettingsSelectOption(
                                        'all',
                                        'All files',
                                        'Downloads all files in the torrent',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
                                    'Choose what happens after adding a torrent to Real Debrid',
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
                                        'Do nothing - just add the torrent to Real Debrid',
                                      ),
                                      SettingsSelectOption(
                                        'choose',
                                        'Let me choose',
                                        'Show a quick Play/Download picker after adding a torrent',
                                      ),
                                      SettingsSelectOption(
                                        'open',
                                        'Open in Real-Debrid',
                                        'View the torrent in Real-Debrid tab',
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
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.shield_outlined,
                                        color: t.accent2,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Content Filter Bypass',
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
                                    'Real-Debrid blocks torrents with certain filename patterns (WEB-DL, WEBRip, BDRip, HDRip, etc.). '
                                    'When enabled, Quick Play will skip torrents likely to be blocked, '
                                    'trying only ones that should work.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: t.dim),
                                  ),
                                  const SizedBox(height: 8),
                                  _FocusRing(
                                    fill: true,
                                    radius: 12,
                                    child: SwitchListTile(
                                      title: const Text(
                                        'Skip blocked torrents',
                                      ),
                                      subtitle: const Text(
                                        'Filter out WEB-DL, WEBRip, BDRip, HDRip, DVDRip and similar tags during Quick Play',
                                      ),
                                      value: _skipBlockedTorrents,
                                      onChanged: (v) async {
                                        setState(
                                          () => _skipBlockedTorrents = v,
                                        );
                                        await StorageService.setRdSkipBlockedTorrents(
                                          v,
                                        );
                                      },
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
                                        Icons.help_outline,
                                        color: t.accent2,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'How to get your API key',
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
                                    '1. Visit: real-debrid.com/devices\n'
                                    '2. Log in if prompted\n'
                                    '3. Scroll down to find your API key\n'
                                    '4. Copy the API key and paste it above',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: t.dim,
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

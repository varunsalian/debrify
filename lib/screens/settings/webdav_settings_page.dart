import 'package:flutter/material.dart';
import '../../utils/tv_reveal.dart';
import 'package:flutter/services.dart';

import '../../models/webdav_item.dart';
import '../../models/profiles/profile_policy.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/profiles/profile_async_authorization.dart';
import '../../services/storage_service.dart';
import '../../services/webdav_service.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/tv_text_field.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// House DPAD idiom: focus the node, then scroll it into view — plain
/// `requestFocus` from a key handler skips the traversal policy's
/// ensure-visible step, leaving the focused row off-screen.
void _focusAndReveal(FocusNode target) {
  target.requestFocus();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = target.context;
    if (ctx != null) {
      tvRevealMinimal(ctx);
    }
  });
}

class WebDavSettingsPage extends StatefulWidget {
  const WebDavSettingsPage({super.key, this.feature = ProfileFeature.cloud});

  final ProfileFeature feature;

  @override
  State<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends State<WebDavSettingsPage> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameFocusNode = FocusNode(debugLabel: 'webdav-name');
  final _urlFocusNode = FocusNode(debugLabel: 'webdav-url');
  final _usernameFocusNode = FocusNode(debugLabel: 'webdav-username');
  final _passwordFocusNode = FocusNode(debugLabel: 'webdav-password');
  final _passwordVisibilityFocusNode = FocusNode(
    debugLabel: 'webdav-password-visibility',
  );
  final _saveFocusNode = FocusNode(debugLabel: 'webdav-save');
  final _disconnectFocusNode = FocusNode(debugLabel: 'webdav-disconnect');

  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  bool _hiddenFromNav = false;
  bool _showVideosOnly = true;
  bool _obscure = true;
  List<WebDavConfig> _servers = [];
  String? _editingId;
  bool _editingReadOnly = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('webdav_settings');
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _nameFocusNode.dispose();
    _urlFocusNode.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _passwordVisibilityFocusNode.dispose();
    _saveFocusNode.dispose();
    _disconnectFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final servers = await StorageService.getWebDavServers(
      forSettings: true,
      feature: widget.feature,
    );
    final selected = await StorageService.getSelectedWebDavServer(
      forSettings: true,
      feature: widget.feature,
    );
    final enabled = await StorageService.getWebDavEnabled();
    final hidden = await StorageService.getWebDavHiddenFromNav();
    final showVideosOnly = await StorageService.getWebDavShowVideosOnly();
    if (!mounted) return;
    setState(() {
      _servers = servers;
      _editingId = selected?.id;
      _editingReadOnly = selected?.connectionReadOnly ?? false;
      _nameController.text = selected?.name ?? '';
      _urlController.text = selected?.baseUrl ?? '';
      _usernameController.text = selected?.username ?? '';
      _passwordController.text = selected?.password ?? '';
      _enabled = enabled;
      _hiddenFromNav = hidden;
      _showVideosOnly = showVideosOnly;
      _loading = false;
    });

    // TV: land DPAD focus somewhere when the page opens so users aren't
    // stranded. The Save button, not a TextField — autofocusing a field
    // would pop the soft keyboard.
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Bail if something already holds real focus (a scope node just
        // means nothing on the page grabbed it yet).
        final current = FocusManager.instance.primaryFocus;
        if (current != null && current is! FocusScopeNode) return;
        _saveFocusNode.requestFocus();
      });
    }
  }

  void _snack(String message, {bool error = false}) {
    final t = AppThemeScope.of(context).settings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? t.danger : null,
      ),
    );
  }

  Future<void> _save() async {
    if (_editingReadOnly) return;
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _snack('Enter your WebDAV server URL', error: true);
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    final config = WebDavConfig(
      id: _editingId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : (Uri.tryParse(url)?.host ?? 'WebDAV'),
      baseUrl: url,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    try {
      final authorization = await ProfileAsyncAuthorization.capture(
        widget.feature,
      );
      final WebDavConfig savedConfig;
      if (authorization == null) {
        await WebDavService.testConnection(config, feature: widget.feature);
        savedConfig = await StorageService.upsertWebDavServer(
          config,
          feature: widget.feature,
        );
      } else {
        await authorization.runIfCurrent(
          () => WebDavService.testConnection(config, feature: widget.feature),
        );
        // Revalidate after the network await and execute the write inside the
        // initiating profile scope. A profile switch/revocation cannot redirect
        // this credential into the newly visible profile.
        savedConfig = await authorization.runIfCurrent(
          () => StorageService.upsertWebDavServer(
            config,
            feature: widget.feature,
          ),
        );
      }
      final servers = await StorageService.getWebDavServers(
        forSettings: true,
        feature: widget.feature,
      );
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _editingId = savedConfig.id;
        _editingReadOnly = savedConfig.connectionReadOnly;
        _enabled = true;
        _saving = false;
      });
      MainPageBridge.notifyIntegrationChanged();
      _snack('WebDAV connected');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Could not connect to this WebDAV server', error: true);
    }
  }

  Future<void> _disconnect() async {
    if (_editingReadOnly) return;
    if (_editingId != null) {
      await StorageService.deleteWebDavServer(
        _editingId!,
        feature: widget.feature,
      );
    }
    final servers = await StorageService.getWebDavServers(
      forSettings: true,
      feature: widget.feature,
    );
    final selected = await StorageService.getSelectedWebDavServer(
      forSettings: true,
      feature: widget.feature,
    );
    if (!mounted) return;
    setState(() {
      _servers = servers;
      _enabled = servers.isNotEmpty;
      _hiddenFromNav = false;
      _editingId = selected?.id;
      _editingReadOnly = selected?.connectionReadOnly ?? false;
      _nameController.text = selected?.name ?? '';
      _urlController.text = selected?.baseUrl ?? '';
      _usernameController.text = selected?.username ?? '';
      _passwordController.text = selected?.password ?? '';
    });
    MainPageBridge.notifyIntegrationChanged();
    _snack('WebDAV server removed');
    // Removing the last server unmounts the focused Disconnect button
    // (_enabled goes false) — reseed DPAD focus on something that remains.
    if (PlatformUtil.isTelevision && servers.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusAndReveal(_saveFocusNode);
      });
    }
  }

  void _editServer(WebDavConfig server) {
    setState(() {
      _editingId = server.id;
      _editingReadOnly = server.connectionReadOnly;
      _nameController.text = server.name;
      _urlController.text = server.baseUrl;
      _usernameController.text = server.username;
      _passwordController.text = server.password;
    });
  }

  void _newServer() {
    setState(() {
      _editingId = null;
      _editingReadOnly = false;
      _nameController.clear();
      _urlController.clear();
      _usernameController.clear();
      _passwordController.clear();
    });
    // TV: don't focus the TextField directly (pops the soft keyboard) —
    // land on the Save button instead; it still reveals the cleared form.
    if (PlatformUtil.isTelevision) {
      _focusAndReveal(_saveFocusNode);
    } else {
      _focusAndReveal(_nameFocusNode);
    }
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    await StorageService.setWebDavEnabled(value);
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _setHidden(bool value) async {
    setState(() => _hiddenFromNav = value);
    await StorageService.setWebDavHiddenFromNav(value);
    MainPageBridge.notifyIntegrationChanged();
  }

  Future<void> _setShowVideosOnly(bool value) async {
    setState(() => _showVideosOnly = value);
    await StorageService.setWebDavShowVideosOnly(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'WebDAV',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsPageScaffold(
      title: 'WebDAV',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _section(
                  children: [
                    TvTextField(
                      controller: _nameController,
                      enabled: !_editingReadOnly,
                      focusNode: _nameFocusNode,
                      labelText: 'Server name',
                      hintText: 'Seedbox',
                      prefixIcon: const Icon(Icons.badge_rounded),
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _urlFocusNode.requestFocus(),
                      onDownArrow: () => _focusAndReveal(_urlFocusNode),
                    ),
                    const SizedBox(height: 12),
                    TvTextField(
                      controller: _urlController,
                      enabled: !_editingReadOnly,
                      focusNode: _urlFocusNode,
                      keyboardType: TextInputType.url,
                      labelText: 'Server URL',
                      hintText: 'https://example.com/remote.php/dav/files/me',
                      prefixIcon: const Icon(Icons.link_rounded),
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _usernameFocusNode.requestFocus(),
                      onUpArrow: () => _focusAndReveal(_nameFocusNode),
                      onDownArrow: () => _focusAndReveal(_usernameFocusNode),
                    ),
                    if (WebDavService.isInsecureUrl(_urlController.text)) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: t.warning,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Insecure HTTP — your WebDAV username, '
                                'password, and files travel without transport '
                                'encryption.',
                                style: TextStyle(
                                  color: t.warning,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TvTextField(
                      controller: _usernameController,
                      enabled: !_editingReadOnly,
                      focusNode: _usernameFocusNode,
                      labelText: 'Username',
                      hintText: 'Optional username',
                      prefixIcon: const Icon(Icons.person_rounded),
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                      onUpArrow: () => _focusAndReveal(_urlFocusNode),
                      onDownArrow: () => _focusAndReveal(_passwordFocusNode),
                    ),
                    const SizedBox(height: 12),
                    TvTextField(
                      controller: _passwordController,
                      enabled: !_editingReadOnly,
                      focusNode: _passwordFocusNode,
                      obscureText: _obscure,
                      labelText: 'Password or app token',
                      hintText: 'Optional password',
                      prefixIcon: const Icon(Icons.key_rounded),
                      suffixIcon: _PasswordVisibilityButton(
                        focusNode: _passwordVisibilityFocusNode,
                        passwordFocusNode: _passwordFocusNode,
                        saveFocusNode: _saveFocusNode,
                        obscure: _obscure,
                        onToggle: () => setState(() => _obscure = !_obscure),
                      ),
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _save(),
                      onUpArrow: () => _focusAndReveal(_usernameFocusNode),
                      onDownArrow: () => _focusAndReveal(_saveFocusNode),
                      onRightArrow: () =>
                          _focusAndReveal(_passwordVisibilityFocusNode),
                    ),
                    const SizedBox(height: 16),
                    CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                            _focusAndReveal(_passwordFocusNode),
                      },
                      child: _FocusRing(
                        child: FilledButton.icon(
                          focusNode: _saveFocusNode,
                          // Keep enabled with a no-op while saving: disabling
                          // the focused button drops DPAD focus mid-save.
                          onPressed: _editingReadOnly
                              ? null
                              : (_saving ? () {} : _save),
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_done_rounded),
                          label: Text(_saving ? 'Testing...' : 'Save and Test'),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_servers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _section(
                    children: [
                      for (final server in _servers)
                        _FocusRing(
                          child: ListTile(
                            // Static indicator, not a Radio: the row's onTap
                            // already selects, and a focusable Radio was an
                            // extra DPAD stop with no visible focus state.
                            leading: Icon(
                              server.id == _editingId
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: server.id == _editingId
                                  ? t.accent2
                                  : t.dim,
                            ),
                            title: Text(server.name),
                            subtitle: Text(
                              server.credentialsRedacted
                                  ? 'Shared connection • credentials hidden'
                                  : '${WebDavService.isInsecureConfig(server) ? 'Insecure HTTP • ' : ''}${server.baseUrl}',
                            ),
                            trailing: IconButton(
                              onPressed: server.connectionReadOnly
                                  ? null
                                  : () => _editServer(server),
                              icon: const Icon(Icons.edit_rounded),
                              // Visible DPAD focus for the bare icon action.
                              style: ButtonStyle(
                                backgroundColor:
                                    WidgetStateProperty.resolveWith(
                                      (states) =>
                                          states.contains(WidgetState.focused)
                                          ? t.accent.withValues(alpha: 0.35)
                                          : null,
                                    ),
                              ),
                            ),
                            onTap: () async {
                              await StorageService.setSelectedWebDavServerId(
                                server.id,
                              );
                              _editServer(server);
                              MainPageBridge.notifyIntegrationChanged();
                            },
                          ),
                        ),
                      const SizedBox(height: 8),
                      _FocusRing(
                        child: OutlinedButton.icon(
                          onPressed: _newServer,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add another server'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                _section(
                  children: [
                    _FocusRing(
                      child: SwitchListTile(
                        value: _enabled,
                        onChanged: _servers.isEmpty ? null : _setEnabled,
                        title: const Text('Enable WebDAV'),
                        subtitle: const Text('Show WebDAV features in the app'),
                      ),
                    ),
                    _FocusRing(
                      child: SwitchListTile(
                        value: _hiddenFromNav,
                        onChanged: _enabled ? _setHidden : null,
                        title: const Text('Hide from navigation'),
                        subtitle: const Text(
                          'Keep configured but remove the tab',
                        ),
                      ),
                    ),
                    _FocusRing(
                      child: SwitchListTile(
                        value: _showVideosOnly,
                        onChanged: _setShowVideosOnly,
                        title: const Text('Show videos only'),
                        subtitle: const Text(
                          'Hide non-video files while browsing',
                        ),
                      ),
                    ),
                  ],
                ),
                if (_enabled) ...[
                  const SizedBox(height: 16),
                  _FocusRing(
                    child: OutlinedButton.icon(
                      focusNode: _disconnectFocusNode,
                      onPressed: _editingReadOnly ? null : _disconnect,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: t.danger,
                        side: BorderSide(
                          color: t.danger.withValues(alpha: 0.5),
                        ),
                      ),
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(
                        _editingReadOnly
                            ? 'Shared connection managed by owner'
                            : 'Disconnect WebDAV',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section({required List<Widget> children}) {
    final t = AppThemeScope.of(context).settings;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
      child: Column(children: children),
    );
  }
}

/// Paints the house focus ring (accent border + lit panel fill) around a
/// child whose inner control takes DPAD focus (SwitchListTile, ListTile,
/// buttons). The wrapper node is not focusable itself — it just observes
/// descendants. Snap decoration, no tween — per the TV GPU rule.
class _FocusRing extends StatefulWidget {
  const _FocusRing({required this.child});

  final Widget child;

  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> {
  /// Live, never cached: Flutter does not guarantee the falling edge of
  /// `onFocusChange` — popping a route opened with OK restores focus to the
  /// modal scope rather than to a row, so rows that were focus-walked on the
  /// way in are never told they lost it and keep painting as focused. See the
  /// note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode => _ownFocusNode ??= FocusNode();
  bool get _focused => _focusNode.hasFocus;

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      // hasFocus includes descendants, so this fires when the wrapped
      // control receives DPAD focus (same pattern as ConnectionCard).
      focusNode: _focusNode,
      onFocusChange: (_) => setState(() {}),
      child: Container(
        decoration: BoxDecoration(
          color: _focused ? t.panel2 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _focused ? t.accent : Colors.transparent),
        ),
        child: widget.child,
      ),
    );
  }
}

class _PasswordVisibilityButton extends StatelessWidget {
  const _PasswordVisibilityButton({
    required this.focusNode,
    required this.passwordFocusNode,
    required this.saveFocusNode,
    required this.obscure,
    required this.onToggle,
  });

  final FocusNode focusNode;
  final FocusNode passwordFocusNode;
  final FocusNode saveFocusNode;
  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowLeft) {
          _focusAndReveal(passwordFocusNode);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _focusAndReveal(saveFocusNode);
          return KeyEventResult.handled;
        }
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          onToggle();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return IconButton(
            onPressed: onToggle,
            style: IconButton.styleFrom(
              backgroundColor: focused
                  ? t.accent.withValues(alpha: 0.16)
                  : null,
            ),
            icon: Icon(
              obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            ),
          );
        },
      ),
    );
  }
}

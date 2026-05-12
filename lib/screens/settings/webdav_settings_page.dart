import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/webdav_item.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../services/webdav_service.dart';

class WebDavSettingsPage extends StatefulWidget {
  const WebDavSettingsPage({super.key});

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

  @override
  void initState() {
    super.initState();
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
    final servers = await StorageService.getWebDavServers();
    final selected = await StorageService.getSelectedWebDavServer();
    final enabled = await StorageService.getWebDavEnabled();
    final hidden = await StorageService.getWebDavHiddenFromNav();
    final showVideosOnly = await StorageService.getWebDavShowVideosOnly();
    if (!mounted) return;
    setState(() {
      _servers = servers;
      _editingId = selected?.id;
      _nameController.text = selected?.name ?? '';
      _urlController.text = selected?.baseUrl ?? '';
      _usernameController.text = selected?.username ?? '';
      _passwordController.text = selected?.password ?? '';
      _enabled = enabled;
      _hiddenFromNav = hidden;
      _showVideosOnly = showVideosOnly;
      _loading = false;
    });
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }

  Future<void> _save() async {
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
      await WebDavService.testConnection(config);
      await StorageService.upsertWebDavServer(config);
      final servers = await StorageService.getWebDavServers();
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _editingId = config.id;
        _enabled = true;
        _saving = false;
      });
      MainPageBridge.notifyIntegrationChanged();
      _snack('WebDAV connected');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _disconnect() async {
    if (_editingId != null) {
      await StorageService.deleteWebDavServer(_editingId!);
    }
    final servers = await StorageService.getWebDavServers();
    final selected = await StorageService.getSelectedWebDavServer();
    if (!mounted) return;
    setState(() {
      _servers = servers;
      _enabled = servers.isNotEmpty;
      _hiddenFromNav = false;
      _editingId = selected?.id;
      _nameController.text = selected?.name ?? '';
      _urlController.text = selected?.baseUrl ?? '';
      _usernameController.text = selected?.username ?? '';
      _passwordController.text = selected?.password ?? '';
    });
    MainPageBridge.notifyIntegrationChanged();
    _snack('WebDAV server removed');
  }

  void _editServer(WebDavConfig server) {
    setState(() {
      _editingId = server.id;
      _nameController.text = server.name;
      _urlController.text = server.baseUrl;
      _usernameController.text = server.username;
      _passwordController.text = server.password;
    });
  }

  void _newServer() {
    setState(() {
      _editingId = null;
      _nameController.clear();
      _urlController.clear();
      _usernameController.clear();
      _passwordController.clear();
    });
    _nameFocusNode.requestFocus();
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
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _section(
              children: [
                _TvFriendlyTextField(
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  nextFocusNode: _urlFocusNode,
                  labelText: 'Server name',
                  hintText: 'Seedbox',
                  prefixIcon: const Icon(Icons.badge_rounded),
                ),
                const SizedBox(height: 12),
                _TvFriendlyTextField(
                  controller: _urlController,
                  focusNode: _urlFocusNode,
                  previousFocusNode: _nameFocusNode,
                  nextFocusNode: _usernameFocusNode,
                  keyboardType: TextInputType.url,
                  labelText: 'Server URL',
                  hintText: 'https://example.com/remote.php/dav/files/me',
                  prefixIcon: const Icon(Icons.link_rounded),
                ),
                const SizedBox(height: 12),
                _TvFriendlyTextField(
                  controller: _usernameController,
                  focusNode: _usernameFocusNode,
                  previousFocusNode: _urlFocusNode,
                  nextFocusNode: _passwordFocusNode,
                  labelText: 'Username',
                  hintText: 'Optional username',
                  prefixIcon: const Icon(Icons.person_rounded),
                ),
                const SizedBox(height: 12),
                _TvFriendlyTextField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  previousFocusNode: _usernameFocusNode,
                  nextFocusNode: _saveFocusNode,
                  rightFocusNode: _passwordVisibilityFocusNode,
                  obscureText: _obscure,
                  labelText: 'Password or app token',
                  hintText: 'Optional password',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffix: _PasswordVisibilityButton(
                    focusNode: _passwordVisibilityFocusNode,
                    passwordFocusNode: _passwordFocusNode,
                    saveFocusNode: _saveFocusNode,
                    obscure: _obscure,
                    onToggle: () => setState(() => _obscure = !_obscure),
                  ),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 16),
                CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                        _passwordFocusNode.requestFocus(),
                  },
                  child: FilledButton.icon(
                    focusNode: _saveFocusNode,
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_done_rounded),
                    label: Text(_saving ? 'Testing...' : 'Save and Test'),
                  ),
                ),
              ],
            ),
            if (_servers.isNotEmpty) ...[
              const SizedBox(height: 16),
              _section(
                children: [
                  for (final server in _servers)
                    ListTile(
                      leading: Radio<String>(
                        value: server.id,
                        groupValue: _editingId,
                        onChanged: (_) async {
                          await StorageService.setSelectedWebDavServerId(
                            server.id,
                          );
                          _editServer(server);
                          MainPageBridge.notifyIntegrationChanged();
                        },
                      ),
                      title: Text(server.name),
                      subtitle: Text(server.baseUrl),
                      trailing: IconButton(
                        onPressed: () => _editServer(server),
                        icon: const Icon(Icons.edit_rounded),
                      ),
                      onTap: () async {
                        await StorageService.setSelectedWebDavServerId(
                          server.id,
                        );
                        _editServer(server);
                        MainPageBridge.notifyIntegrationChanged();
                      },
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _newServer,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add another server'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _section(
              children: [
                SwitchListTile(
                  value: _enabled,
                  onChanged: _servers.isEmpty ? null : _setEnabled,
                  title: const Text('Enable WebDAV'),
                  subtitle: const Text('Show WebDAV features in the app'),
                ),
                SwitchListTile(
                  value: _hiddenFromNav,
                  onChanged: _enabled ? _setHidden : null,
                  title: const Text('Hide from navigation'),
                  subtitle: const Text('Keep configured but remove the tab'),
                ),
                SwitchListTile(
                  value: _showVideosOnly,
                  onChanged: _setShowVideosOnly,
                  title: const Text('Show videos only'),
                  subtitle: const Text('Hide non-video files while browsing'),
                ),
              ],
            ),
            if (_enabled) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                focusNode: _disconnectFocusNode,
                onPressed: _disconnect,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Disconnect WebDAV'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(children: children),
    );
  }
}

class _TvFriendlyTextField extends StatefulWidget {
  const _TvFriendlyTextField({
    required this.controller,
    required this.focusNode,
    required this.labelText,
    required this.hintText,
    required this.prefixIcon,
    this.previousFocusNode,
    this.nextFocusNode,
    this.rightFocusNode,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode? previousFocusNode;
  final FocusNode? nextFocusNode;
  final FocusNode? rightFocusNode;
  final String labelText;
  final String hintText;
  final Widget prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_TvFriendlyTextField> createState() => _TvFriendlyTextFieldState();
}

class _TvFriendlyTextFieldState extends State<_TvFriendlyTextField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TvFriendlyTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChange);
      widget.focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() {
      _focused = widget.focusNode.hasFocus;
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final textLength = widget.controller.text.length;
    final selection = widget.controller.selection;
    final isTextEmpty = textLength == 0;
    final isSelectionValid = selection.isValid && selection.baseOffset >= 0;
    final isAtStart =
        !isSelectionValid ||
        (selection.baseOffset == 0 && selection.extentOffset == 0);
    final isAtEnd =
        !isSelectionValid ||
        (selection.baseOffset == textLength &&
            selection.extentOffset == textLength);

    if (key == LogicalKeyboardKey.arrowUp &&
        (isTextEmpty || isAtStart) &&
        widget.previousFocusNode != null) {
      widget.previousFocusNode!.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown &&
        (isTextEmpty || isAtEnd) &&
        widget.nextFocusNode != null) {
      widget.nextFocusNode!.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight &&
        (isTextEmpty || isAtEnd) &&
        widget.rightFocusNode != null) {
      widget.rightFocusNode!.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack) {
      widget.previousFocusNode?.requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Focus(
      onKeyEvent: _handleKeyEvent,
      skipTraversal: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: _focused ? Border.all(color: primary, width: 2) : null,
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.18),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          keyboardType: widget.keyboardType,
          obscureText: widget.obscureText,
          textInputAction: widget.nextFocusNode == null
              ? TextInputAction.done
              : TextInputAction.next,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            prefixIcon: widget.prefixIcon,
            suffixIcon: widget.suffix,
          ),
          onSubmitted: (value) {
            if (widget.onSubmitted != null) {
              widget.onSubmitted!(value);
            } else {
              widget.nextFocusNode?.requestFocus();
            }
          },
        ),
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
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowLeft) {
          passwordFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          saveFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space) {
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
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.16)
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

import 'package:debrify/features/iptv_settings/models/iptv_settings_playlist_edit.dart';
import 'package:debrify/features/iptv_settings/presentation/iptv_settings_dialog_button_style.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';

/// Edit an existing playlist: rename, change the EPG URL, and — by type — the
/// source URL (M3U URL playlists) or server/username/password (Xtream logins).
///
/// TV DPAD: each field is a shell with no explicit arrow wiring, so vertical
/// moves fall through to the framework's directional traversal (the same way
/// the single-field dialogs walk field↔buttons). The name field seeds focus so
/// DOWN steps through the fields to the actions; OK on a field starts editing.
class IptvSettingsEditDialog extends StatefulWidget {
  const IptvSettingsEditDialog({
    required this.playlist,
    required this.existingNames,
    required this.existingUrls,
  });

  final IptvPlaylist playlist;
  final Set<String> existingNames;
  final Set<String> existingUrls;

  @override
  State<IptvSettingsEditDialog> createState() => _EditPlaylistDialogState();
}

class _EditPlaylistDialogState extends State<IptvSettingsEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _serverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _epgController;

  // One shell node per field so DPAD can be wired field-to-field explicitly —
  // this screen wires arrows rather than trusting directional traversal.
  final FocusNode _nameFocusNode = FocusNode(debugLabel: 'iptv-edit-name');
  final FocusNode _urlFocusNode = FocusNode(debugLabel: 'iptv-edit-url');
  final FocusNode _serverFocusNode = FocusNode(debugLabel: 'iptv-edit-server');
  final FocusNode _usernameFocusNode = FocusNode(
    debugLabel: 'iptv-edit-username',
  );
  final FocusNode _passwordFocusNode = FocusNode(
    debugLabel: 'iptv-edit-password',
  );
  final FocusNode _epgFocusNode = FocusNode(debugLabel: 'iptv-edit-epg');

  bool get _isXtream => widget.playlist.isXtreamCodes;
  bool get _isUrl =>
      !widget.playlist.isXtreamCodes && !widget.playlist.isLocalFile;

  @override
  void initState() {
    super.initState();
    final p = widget.playlist;
    _nameController = TextEditingController(text: p.name);
    _urlController = TextEditingController(text: p.url);
    _serverController = TextEditingController(text: p.serverUrl ?? '');
    _usernameController = TextEditingController(text: p.username ?? '');
    _passwordController = TextEditingController(text: p.password ?? '');
    _epgController = TextEditingController(text: p.epgUrl ?? '');
    for (final c in [
      _nameController,
      _urlController,
      _serverController,
      _usernameController,
      _passwordController,
    ]) {
      c.addListener(_revalidate);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _epgController.dispose();
    _nameFocusNode.dispose();
    _urlFocusNode.dispose();
    _serverFocusNode.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _epgFocusNode.dispose();
    super.dispose();
  }

  void _revalidate() => setState(() {});

  /// The blocking error for the current values, or null when saveable. Drives
  /// both the Save button's enabled state and the inline field errors.
  String? get _nameError {
    final name = _nameController.text.trim();
    if (name.isEmpty) return 'Please enter a name';
    // Keeping this playlist's own name is always fine, even if another
    // playlist already happens to share it (the add paths don't enforce
    // unique names) — only block CHANGING to a name that collides.
    if (name != widget.playlist.name.trim() &&
        widget.existingNames.contains(name)) {
      return 'A playlist with this name already exists';
    }
    return null;
  }

  String? get _urlError {
    if (!_isUrl) return null;
    final url = _urlController.text.trim();
    if (url.isEmpty) return 'Please enter a playlist URL';
    if (!IptvService.isValidPlaylistUrl(url)) {
      return 'Please enter a valid HTTP/HTTPS URL';
    }
    if (url != widget.playlist.url.trim() &&
        widget.existingUrls.contains(url)) {
      return 'This playlist URL already exists';
    }
    return null;
  }

  String? get _serverError {
    if (!_isXtream) return null;
    return _serverController.text.trim().isEmpty
        ? 'Please enter a server URL'
        : null;
  }

  String? get _usernameError {
    if (!_isXtream) return null;
    return _usernameController.text.trim().isEmpty
        ? 'Please enter a username'
        : null;
  }

  String? get _passwordError {
    if (!_isXtream) return null;
    return _passwordController.text.trim().isEmpty
        ? 'Please enter a password'
        : null;
  }

  bool get _canSave =>
      _nameError == null &&
      _urlError == null &&
      _serverError == null &&
      _usernameError == null &&
      _passwordError == null;

  void _submit() {
    if (!_canSave) {
      // IME "done" unfocused the field; park DPAD back on the name field so TV
      // users aren't stranded on the dialog scope with errors showing.
      _nameFocusNode.requestFocus();
      return;
    }
    Navigator.of(context).pop(
      IptvSettingsPlaylistEdit(
        name: _nameController.text.trim(),
        url: _urlController.text.trim(),
        serverUrl: _isXtream ? _serverController.text.trim() : null,
        username: _isXtream ? _usernameController.text.trim() : null,
        password: _isXtream ? _passwordController.text.trim() : null,
        epgUrl: _epgController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    // The field shells in the order they're shown, so each field's UP/DOWN can
    // point at its real neighbour regardless of type. First-field UP and
    // last-field DOWN stay null: those hops (field↔action-buttons) go through
    // the framework's directional traversal, exactly like the single-field
    // dialogs on this screen already do.
    final sequence = <FocusNode>[
      _nameFocusNode,
      if (_isUrl) _urlFocusNode,
      if (_isXtream) ...[
        _serverFocusNode,
        _usernameFocusNode,
        _passwordFocusNode,
      ],
      _epgFocusNode,
    ];
    VoidCallback? up(FocusNode n) {
      final i = sequence.indexOf(n);
      return i > 0 ? () => sequence[i - 1].requestFocus() : null;
    }

    VoidCallback? down(FocusNode n) {
      final i = sequence.indexOf(n);
      return i >= 0 && i < sequence.length - 1
          ? () => sequence[i + 1].requestFocus()
          : null;
    }

    final fields = <Widget>[
      TvTextField(
        controller: _nameController,
        focusNode: _nameFocusNode,
        labelText: 'Playlist Name',
        hintText: 'Enter a name for this playlist',
        errorText: _nameError,
        prefixIcon: const Icon(Icons.label_outline),
        // Off-TV only: on TV the action buttons seed DPAD focus (see the
        // Save/Cancel autofocus below), matching the import-name dialog — a
        // field autofocus in TV passthrough mode pops the broken system IME.
        autofocus: !PlatformUtil.isTelevision,
        textInputAction: TextInputAction.next,
        onUpArrow: up(_nameFocusNode),
        onDownArrow: down(_nameFocusNode),
      ),
      if (_isUrl) ...[
        const SizedBox(height: 12),
        TvTextField(
          controller: _urlController,
          focusNode: _urlFocusNode,
          labelText: 'Playlist URL',
          hintText: 'https://example.com/playlist.m3u',
          errorText: _urlError,
          prefixIcon: const Icon(Icons.link),
          textInputAction: TextInputAction.next,
          onUpArrow: up(_urlFocusNode),
          onDownArrow: down(_urlFocusNode),
        ),
      ],
      if (_isXtream) ...[
        const SizedBox(height: 12),
        TvTextField(
          controller: _serverController,
          focusNode: _serverFocusNode,
          labelText: 'Server URL',
          hintText: 'http://example.com:8080',
          errorText: _serverError,
          prefixIcon: const Icon(Icons.dns),
          textInputAction: TextInputAction.next,
          onUpArrow: up(_serverFocusNode),
          onDownArrow: down(_serverFocusNode),
        ),
        const SizedBox(height: 12),
        TvTextField(
          controller: _usernameController,
          focusNode: _usernameFocusNode,
          labelText: 'Username',
          hintText: 'your username',
          errorText: _usernameError,
          prefixIcon: const Icon(Icons.person),
          textInputAction: TextInputAction.next,
          onUpArrow: up(_usernameFocusNode),
          onDownArrow: down(_usernameFocusNode),
        ),
        const SizedBox(height: 12),
        TvTextField(
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          labelText: 'Password',
          hintText: 'your password',
          errorText: _passwordError,
          prefixIcon: const Icon(Icons.lock),
          obscureText: true,
          textInputAction: TextInputAction.next,
          onUpArrow: up(_passwordFocusNode),
          onDownArrow: down(_passwordFocusNode),
        ),
      ],
      const SizedBox(height: 12),
      TvTextField(
        controller: _epgController,
        focusNode: _epgFocusNode,
        labelText: 'EPG URL (XMLTV, optional)',
        hintText: 'https://example.com/guide.xml.gz',
        prefixIcon: const Icon(Icons.calendar_view_day_outlined),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onUpArrow: up(_epgFocusNode),
        onDownArrow: down(_epgFocusNode),
      ),
    ];

    return AlertDialog(
      title: const Text('Edit Playlist'),
      // No fixed width — let AlertDialog size to the screen (a hard width
      // overflows narrow phone dialogs). Scrollable so the taller Xtream form
      // (four fields + EPG) never overflows vertically on short screens.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isXtream)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Changing the server or credentials won\'t be re-checked '
                  'here — use Refresh afterwards to verify the login.',
                  style: TextStyle(fontSize: 12, color: t.dim),
                ),
              ),
            ...fields,
          ],
        ),
      ),
      actions: [
        TextButton(
          style: iptvSettingsDialogButtonFocusStyle,
          // TV: seed DPAD focus on Cancel only when Save opens disabled, so
          // focus is never stranded on the dialog scope.
          autofocus: PlatformUtil.isTelevision && !_canSave,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: iptvSettingsDialogButtonFocusStyle,
          autofocus: PlatformUtil.isTelevision && _canSave,
          onPressed: _canSave ? _submit : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

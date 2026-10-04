import 'package:debrify/features/iptv_settings/presentation/iptv_settings_dialog_button_style.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';

/// Dialog for entering playlist name when importing from file
class IptvSettingsPlaylistNameDialog extends StatefulWidget {
  const IptvSettingsPlaylistNameDialog({
    required this.defaultName,
    required this.channelCount,
    required this.existingNames,
  });

  final String defaultName;
  final int channelCount;
  final Set<String> existingNames;

  @override
  State<IptvSettingsPlaylistNameDialog> createState() =>
      _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<IptvSettingsPlaylistNameDialog> {
  late final TextEditingController _controller;
  final FocusNode _fieldFocusNode = FocusNode(
    debugLabel: 'iptv-import-name-field',
  );
  String? _errorText;
  // Whether the default name was valid on open — decides which action button
  // gets the TV autofocus (autofocus only counts on the first frame).
  late final bool _initialNameValid;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultName);
    _controller.addListener(_validateName);
    // Validate synchronously so the Import button's enabled state is right
    // before the first frame — a post-frame validate could disable an
    // already-autofocused Import, leaving nothing focused on TV.
    _errorText = _errorFor(_controller.text);
    _initialNameValid = _errorText == null;
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocusNode.dispose();
    super.dispose();
  }

  String? _errorFor(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return 'Please enter a name';
    if (widget.existingNames.contains(name)) {
      return 'A playlist with this name already exists';
    }
    return null;
  }

  void _validateName() {
    setState(() => _errorText = _errorFor(_controller.text));
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty || widget.existingNames.contains(name)) {
      _validateName();
      // IME "done" just unfocused the field; put DPAD back on it so TV
      // users aren't stranded on the dialog scope with an error showing.
      _fieldFocusNode.requestFocus();
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return AlertDialog(
      title: const Text('Name Your Playlist'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.success.withValues(alpha: 0.08),
              borderRadius: app.shape.br(8),
              border: Border.all(color: t.success.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: t.success, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${widget.channelCount} channels found',
                  style: TextStyle(fontSize: 14, color: app.core.tx),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Shared TV field idiom: on TV this is a non-editing shell (DPAD
          // landing never pops the keyboard; OK starts editing). Off-TV it
          // autofocuses with the keyboard ready, as before.
          TvTextField(
            controller: _controller,
            focusNode: _fieldFocusNode,
            labelText: 'Playlist Name',
            hintText: 'Enter a name for this playlist',
            errorText: _errorText,
            prefixIcon: const Icon(Icons.label_outline),
            // Off-TV only: on TV the dialog's action buttons seed DPAD focus
            // (below), matching the old clone which never autofocused on TV.
            autofocus: !PlatformUtil.isTelevision,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: iptvSettingsDialogButtonFocusStyle,
          // TV: when the default name is invalid Import opens disabled, so
          // seed DPAD focus here instead.
          autofocus: PlatformUtil.isTelevision && !_initialNameValid,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: iptvSettingsDialogButtonFocusStyle,
          autofocus: PlatformUtil.isTelevision && _initialNameValid,
          onPressed: _errorText == null ? _submit : null,
          child: const Text('Import'),
        ),
      ],
    );
  }
}

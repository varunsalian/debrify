import 'package:debrify/features/iptv_settings/presentation/iptv_settings_dialog_button_style.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Confirmation used when an Admin removes a source granted to other profiles.
/// Public so its remote-key contract can be covered without bootstrapping the
/// entire profile-backed settings page in a widget test.
class IptvSharedSourceDeleteDialog extends StatefulWidget {
  const IptvSharedSourceDeleteDialog({
    super.key,
    required this.playlistName,
    required this.borrowerCount,
  });

  final String playlistName;
  final int borrowerCount;

  @override
  State<IptvSharedSourceDeleteDialog> createState() =>
      _SharedIptvSourceDeleteDialogState();
}

class _SharedIptvSourceDeleteDialogState
    extends State<IptvSharedSourceDeleteDialog> {
  final FocusNode _cancelFocusNode = FocusNode(
    debugLabel: 'shared-iptv-delete-cancel',
  );
  final FocusNode _okFocusNode = FocusNode(debugLabel: 'shared-iptv-delete-ok');

  @override
  void dispose() {
    _cancelFocusNode.dispose();
    _okFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyRepeatEvent && isActivateOrSpaceKey(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _cancelFocusNode.requestFocus();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _okFocusNode.requestFocus();
        return KeyEventResult.handled;
    }
    if (!isActivateOrSpaceKey(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    Navigator.of(context).pop(_okFocusNode.hasFocus);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.borrowerCount == 1
        ? '1 other profile'
        : '${widget.borrowerCount} other profiles';
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _onKeyEvent,
      child: AlertDialog(
        title: const Text('Remove shared source?'),
        content: Text(
          '"${widget.playlistName}" is shared with $profiles. Removing it '
          'will also remove access to this source from those profiles.',
        ),
        actions: [
          TextButton(
            focusNode: _cancelFocusNode,
            autofocus: true,
            style: iptvSettingsDialogButtonFocusStyle,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            focusNode: _okFocusNode,
            style: iptvSettingsDialogButtonFocusStyle,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

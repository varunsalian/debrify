import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';

/// Snap accent border on DPAD focus for the dialog's action buttons — the
/// stock Material focus overlay is too faint to spot on TV.
/// TOP-LEVEL final, so it cannot read a BuildContext: this one keeps the
/// `kSettingsAccent` constant until it becomes a function of context.
final ButtonStyle iptvSettingsDialogButtonFocusStyle = ButtonStyle(
  side: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? const BorderSide(color: kSettingsAccent, width: 2)
        : null,
  ),
);

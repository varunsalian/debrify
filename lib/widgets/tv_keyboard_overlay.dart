import 'package:flutter/widgets.dart';

import 'tv_keyboard.dart';

/// The bottom-anchored Debrify keyboard a TV text field shows over the app.
///
/// A bare [OverlayEntry] inherits nothing local, and this keyboard opens from
/// INCLUDED and FROZEN surfaces alike, so the field passes its ambient
/// [themes] and the panel renders what its field renders (the legacy freeze
/// included when the field sits inside a LegacyThemeBoundary). They are
/// applied inside the [Positioned]: wrapping inserts plain widgets, and
/// [Positioned] must stay the overlay Stack's direct child.
///
/// The panel sits in the field's [TextFieldTapRegion]. On Android a mouse
/// press outside a text field unfocuses it, and an air mouse is a mouse: a
/// click on a key used to close the keyboard instead of typing the letter.
OverlayEntry tvKeyboardOverlayEntry({
  required CapturedThemes themes,
  required TvKeyboardController controller,
  required TextEditingController preview,
  required bool previewObscure,
  String? previewHint,
  Color? accent,
  Color? ground,
  Color? ink,
  Color? inkOnAccent,
}) => OverlayEntry(
  builder: (_) => Positioned(
    left: 0,
    right: 0,
    bottom: 16,
    child: themes.wrap(
      SafeArea(
        child: Center(
          child: TextFieldTapRegion(
            child: TvKeyboardPanel(
              controller: controller,
              // The bottom-anchored panel can cover the very field it edits;
              // the preview keeps what's typed in sight. Only this overlay
              // path passes it: the onboarding slot's field band is already
              // visible directly above its keyboard.
              previewController: preview,
              previewObscure: previewObscure,
              previewHint: previewHint,
              // The panel's own defaults are these same literals, so a token
              // left null lands on exactly what shipped either way.
              accent: accent,
              ground: ground,
              ink: ink,
              inkOnAccent: inkOnAccent,
            ),
          ),
        ),
      ),
    ),
  ),
);

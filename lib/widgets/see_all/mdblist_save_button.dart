import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme_scope.dart';
import '../../utils/tv_keys.dart';

/// The Discover filter bar's "Save" action for an MDBList list opened from
/// search. Saves the list into the user's own MDBList "My Lists" by CLONING it
/// (create a static list + copy its items) — MDBList has no API to link/like a
/// list, so a clone is the only way to make it appear in the user's lists.
///
/// Styled to sit beside [SeeAllRandomButton] — a boxed glass pill normally, a
/// bare quiet segment on the Discover TV stage — with the same constant-size
/// focus decoration so DPAD moves never reflow the row.
///
/// [busy] swaps the icon for a spinner while the save/remove request is in
/// flight (presses are ignored). [saved] is true once a clone exists.
class MdblistSaveButton extends StatefulWidget {
  final bool quiet;
  final bool saved;
  final bool busy;
  final FocusNode? focusNode;
  final VoidCallback onPressed;

  const MdblistSaveButton({
    super.key,
    required this.saved,
    required this.onPressed,
    this.quiet = false,
    this.busy = false,
    this.focusNode,
  });

  @override
  State<MdblistSaveButton> createState() => _MdblistSaveButtonState();
}

class _MdblistSaveButtonState extends State<MdblistSaveButton> {
  bool _focused = false;
  bool _hovered = false;

  void _activate() {
    if (!widget.busy) widget.onPressed();
  }

  Widget _leadingIcon(double size, Color color) {
    if (widget.busy) {
      return SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }
    return Icon(
      widget.saved
          ? Icons.bookmark_added_rounded
          : Icons.bookmark_add_outlined,
      size: size,
      color: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hovered;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        // Quiet segments live on a single never-wrapping line that scrolls
        // horizontally when too wide — keep the focused one in view.
        if (f && widget.quiet) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateOrSpaceKey(event.logicalKey)) {
          _activate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _activate,
          behavior: HitTestBehavior.opaque,
          child: widget.quiet ? _buildQuiet(active) : _buildBoxed(active),
        ),
      ),
    );
  }

  /// A saved bookmark reads in the accent; unsaved follows the same accent.
  Color get _iconColor => AppThemeScope.of(context).seeAll.accent2;

  /// Boxed pill matching StremioDropdown's non-quiet chip.
  Widget _buildBoxed(bool active) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
      decoration: BoxDecoration(
        color: app.seeAll.panel,
        borderRadius: app.shape.br(11),
        border: Border.all(
          width: 2,
          color: _focused
              ? app.seeAll.accent
              : (active ? app.seeAll.accentBorder : app.seeAll.line),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _leadingIcon(16, _iconColor),
          const SizedBox(width: 8),
          Text(
            widget.saved ? 'Saved' : 'Save',
            style: TextStyle(
              color: app.core.tx,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Quiet segment matching the Discover-TV styling — icon-only.
  Widget _buildQuiet(bool active) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _focused
            ? app.fade(app.seeAll.accent, 0.30)
            : Colors.transparent,
        borderRadius: app.shape.brPill,
        border: Border.all(
          width: 1.2,
          color: _focused
              ? app.fade(app.seeAll.accent2, 0.45)
              : (active ? app.seeAll.accentBorder : Colors.transparent),
        ),
      ),
      child: _leadingIcon(15, _focused ? app.core.tx : _iconColor),
    );
  }
}

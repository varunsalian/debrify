import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/tv_keys.dart';
import 'see_all_theme.dart';

/// The Discover filter bar's "♥ Like" action for an MDBList list opened from
/// search. Toggles the list's liked state on the user's MDBList account.
/// Styled to sit beside [SeeAllRandomButton] — a boxed glass pill normally, a
/// bare quiet segment on the Discover TV stage — with the same constant-size
/// focus decoration so DPAD moves never reflow the row.
///
/// [busy] swaps the heart for a spinner while the toggle request is in flight
/// (presses are ignored).
class MdblistLikeButton extends StatefulWidget {
  final bool quiet;
  final bool liked;
  final bool busy;
  final FocusNode? focusNode;
  final VoidCallback onPressed;

  const MdblistLikeButton({
    super.key,
    required this.liked,
    required this.onPressed,
    this.quiet = false,
    this.busy = false,
    this.focusNode,
  });

  @override
  State<MdblistLikeButton> createState() => _MdblistLikeButtonState();
}

class _MdblistLikeButtonState extends State<MdblistLikeButton> {
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
      widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
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

  /// A liked heart reads red in both variants; unliked follows the accent.
  Color get _heartColor =>
      widget.liked ? const Color(0xFFE0245E) : kSeeAllAccent2;

  /// Boxed pill matching StremioDropdown's non-quiet chip.
  Widget _buildBoxed(bool active) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
      decoration: BoxDecoration(
        color: kSeeAllPanel,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          width: 2,
          color: _focused
              ? kSeeAllAccent
              : (active ? kSeeAllAccentBorder : kSeeAllLine),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _leadingIcon(16, _heartColor),
          const SizedBox(width: 8),
          Text(
            widget.liked ? 'Liked' : 'Like',
            style: const TextStyle(
              color: Colors.white,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _focused
            ? kSeeAllAccent.withValues(alpha: 0.30)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          width: 1.2,
          color: _focused
              ? kSeeAllAccent2.withValues(alpha: 0.45)
              : (active ? kSeeAllAccentBorder : Colors.transparent),
        ),
      ),
      child: _leadingIcon(15, _focused ? Colors.white : _heartColor),
    );
  }
}

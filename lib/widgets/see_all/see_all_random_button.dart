import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/tv_keys.dart';
import 'see_all_theme.dart';

/// The Discover filter bar's "Random" action: picks a random item matching the
/// current Type/Catalog/Genre selection and Quick-Plays it. Styled to sit
/// beside [StremioDropdown] — a boxed glass pill normally, a bare quiet
/// segment on the Discover TV stage — with the same constant-size focus
/// decoration so DPAD moves never reflow the row.
///
/// [busy] swaps the die for a spinner while the host fetches the random page
/// (presses are ignored); [enabled] dims the chip when the grid has nothing to
/// draw from, but keeps it focusable so the DPAD walk has no dead spot.
class SeeAllRandomButton extends StatefulWidget {
  final bool quiet;
  final bool enabled;
  final bool busy;
  final FocusNode? focusNode;
  final VoidCallback onPressed;

  const SeeAllRandomButton({
    super.key,
    required this.onPressed,
    this.quiet = false,
    this.enabled = true,
    this.busy = false,
    this.focusNode,
  });

  @override
  State<SeeAllRandomButton> createState() => _SeeAllRandomButtonState();
}

class _SeeAllRandomButtonState extends State<SeeAllRandomButton> {
  bool _focused = false;
  bool _hovered = false;

  void _activate() {
    if (widget.enabled && !widget.busy) widget.onPressed();
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
    return Icon(Icons.casino_rounded, size: size, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hovered;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        // Quiet segments live on a single never-wrapping line that scrolls
        // horizontally when too wide — keep the focused one in view (no-op
        // while the line fits, or outside any scrollable).
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
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: _activate,
          behavior: HitTestBehavior.opaque,
          child: widget.quiet ? _buildQuiet(active) : _buildBoxed(active),
        ),
      ),
    );
  }

  /// Boxed pill matching StremioDropdown's non-quiet chip.
  Widget _buildBoxed(bool active) {
    final dim = widget.enabled ? 1.0 : 0.4;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
      decoration: BoxDecoration(
        color: kSeeAllPanel,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          width: 2,
          color: _focused
              ? kSeeAllAccent
              : (active && widget.enabled ? kSeeAllAccentBorder : kSeeAllLine),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _leadingIcon(16, kSeeAllAccent2.withValues(alpha: dim)),
          const SizedBox(width: 8),
          Text(
            'Random',
            style: TextStyle(
              color: Colors.white.withValues(alpha: dim),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Quiet segment matching StremioDropdown's Discover-TV styling — icon-only
  /// (the die reads on its own, and the single-row bar must stay tight).
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
              : (active && widget.enabled
                  ? kSeeAllAccentBorder
                  : Colors.transparent),
        ),
      ),
      child: _leadingIcon(
        15,
        !widget.enabled
            ? kSeeAllAccent2.withValues(alpha: 0.4)
            : _focused
                ? Colors.white
                : kSeeAllAccent2,
      ),
    );
  }
}

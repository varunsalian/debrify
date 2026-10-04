import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/see_all/see_all_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Rows ─────────────────────────────────────────────────────────────────────
/// Focus wrapper giving a card the purple DPAD ring + activate-key handling.
class AddonHubFocusCard extends StatefulWidget {
  final VoidCallback onTap;
  final Widget Function(bool focused) builder;
  final FocusNode? focusNode;
  const AddonHubFocusCard({
    required this.onTap,
    required this.builder,
    this.focusNode,
  });

  @override
  State<AddonHubFocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<AddonHubFocusCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) addonHubCenterInScrollable(context);
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateKey(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        // A small scale pop makes DPAD focus feel tactile. Compositor-only
        // transform on one layer — cheap even on weak TV GPUs.
        child: AnimatedScale(
          scale: _focused ? 1.008 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: widget.builder(_focused),
        ),
      ),
    );
  }
}

/// Flat, borderless Stremio-style card. The border slot is a CONSTANT 2px (a
/// changing width feeds into Container's layout padding and reflows the list —
/// the "shake"); unfocused it's transparent so the card reads clean and flat.
const Color addonHubCardBackground = Color(0xFF191B28);

BoxDecoration addonHubCardDecoration(bool focused) => BoxDecoration(
  color: addonHubCardBackground,
  borderRadius: BorderRadius.circular(12),
  border: Border.all(
    width: 2,
    color: focused ? kSeeAllAccent : Colors.transparent,
  ),
);

/// Scroll the focused row toward the vertical centre of its list. The framework
/// only nudges a newly-focused item to the nearest edge (so DPAD-down parks it
/// at the bottom); this keeps it centred instead. [ensureVisible] clamps to the
/// valid scroll range, so the first rows still rest at the top and the last at
/// the bottom — only the middle is actually centred.
void addonHubCenterInScrollable(BuildContext context) {
  final scrollable = Scrollable.maybeOf(context);
  if (scrollable == null) return;
  Scrollable.ensureVisible(
    context,
    alignment: 0.5,
    alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
  );
}

import 'package:flutter/material.dart';

import '../../../theme/app_theme_scope.dart';

/// Paints an accent ring around [child] while any descendant holds DPAD
/// focus; Material's own overlay is too subtle on TV. Non-focusable itself,
/// so it adds no traversal stop. Snaps rather than tweens (TV GPU rule).
///
/// Same behaviour as the private rings on the Trakt and Simkl settings
/// pages, which deliberately stay private to those pages.
class LedgerFocusRing extends StatefulWidget {
  const LedgerFocusRing({super.key, required this.child});

  final Widget child;

  @override
  State<LedgerFocusRing> createState() => _LedgerFocusRingState();
}

class _LedgerFocusRingState extends State<LedgerFocusRing> {
  // Read live, never cached: popping a route opened with OK restores focus to
  // the modal scope, so a falling-edge callback is not guaranteed.
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'ledger-focus-ring',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (_) => setState(() {}),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: _focusNode.hasFocus ? t.accent : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: widget.child,
      ),
    );
  }
}

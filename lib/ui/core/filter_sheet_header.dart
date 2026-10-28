import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/tv_keys.dart';

/// Shared torrent-filter header. Focus nodes are borrowed from the editor.
/// Read eligibility at interaction time as well as build time, as before.
class FilterSheetHeader extends StatelessWidget {
  const FilterSheetHeader({
    super.key,
    required this.clearFocus,
    required this.closeFocus,
    required this.canClear,
    required this.onClear,
    required this.onClose,
  });

  final FocusNode clearFocus;
  final FocusNode closeFocus;
  final ValueGetter<bool> canClear;
  final VoidCallback onClear;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      // Loose fit keeps main's intrinsic one-line width when the title fits;
      // a narrow or scaled window shrinks it instead of overflowing.
      const Flexible(
        child: Text(
          'Filter Results',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Focus(
            focusNode: clearFocus,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  (isActivateKey(event.logicalKey) ||
                      event.logicalKey == LogicalKeyboardKey.space)) {
                if (canClear()) {
                  onClear();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: TextButton(
              onPressed: canClear() ? onClear : null,
              child: const Text('Clear'),
            ),
          ),
          Focus(
            focusNode: closeFocus,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  (isActivateKey(event.logicalKey) ||
                      event.logicalKey == LogicalKeyboardKey.space)) {
                onClose();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
            ),
          ),
        ],
      ),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/tv_keys.dart';
import 'cloud_theme.dart';

/// One entry of a [CloudSegmentedTabs] control.
class CloudSegment<T> {
  final T value;
  final String label;
  final IconData icon;

  const CloudSegment(this.value, this.label, this.icon);
}

/// Pill segmented control matching the Search screen's Catalog/Keyword toggle:
/// accent-filled active segment, constant-width 2px white ring on DPAD focus
/// (so focus never shifts layout). Shared by the cloud screens' view
/// selectors (My Files / Transfers etc.).
class CloudSegmentedTabs<T> extends StatelessWidget {
  final List<CloudSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelected;

  const CloudSegmentedTabs({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: _segment(segments[i])),
          ],
        ],
      ),
    );
  }

  Widget _segment(CloudSegment<T> segment) {
    final isSelected = segment.value == selected;
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          onSelected(segment.value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () => onSelected(segment.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: isSelected ? CloudTheme.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: focused
                      ? Colors.white.withValues(alpha: 0.9)
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    segment.icon,
                    size: 17,
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      segment.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

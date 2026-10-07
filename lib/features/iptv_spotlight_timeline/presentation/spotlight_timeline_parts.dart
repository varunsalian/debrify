import 'package:flutter/material.dart';

class SpotlightTimelineRulerMark extends StatelessWidget {
  final DateTime time;
  final Color color;
  final Color lineColor;

  const SpotlightTimelineRulerMark({
    required this.time,
    required this.color,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final local = time.toLocal();
    final label =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return SizedBox(
      width: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: lineColor),
          ),
          Positioned(
            left: 7,
            top: 10,
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SpotlightTimelineGuideMessage extends StatelessWidget {
  final String label;
  final Color color;
  final Widget? leading;
  final VoidCallback? onTap;
  final String? hint;
  final bool focused;
  final Color? focusFill;
  final Color? focusInk;

  const SpotlightTimelineGuideMessage({
    super.key,
    required this.label,
    required this.color,
    this.leading,
    this.onTap,
    this.hint,
    this.focused = false,
    this.focusFill,
    this.focusInk,
  }) : assert(
         !focused || (focusFill != null && focusInk != null),
         'A focused guide message needs focus colors.',
       );

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: focused
          ? BoxDecoration(
              color: focusFill,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.28),
                  blurRadius: 16,
                  spreadRadius: -5,
                ),
              ],
            )
          : null,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: focused ? focusInk : color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(label: label, child: content);
    }
    return Semantics(
      excludeSemantics: true,
      button: true,
      focusable: true,
      focused: focused,
      selected: focused,
      label: label,
      hint: hint,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}

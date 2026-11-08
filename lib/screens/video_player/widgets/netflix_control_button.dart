import 'package:flutter/material.dart';

import '../../../services/player_controls_display_settings.dart';

// Netflix-style control button widget
class NetflixControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;
  final bool isCompact;

  const NetflixControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: PlayerControlsDisplaySettings.iconOnly,
    builder: (context, iconOnly, _) => iconOnly && label.isNotEmpty
        // Icon-only controls keep their name for pointers and long-press.
        ? Tooltip(message: label, child: _button(showLabel: false))
        : _button(showLabel: true),
  );

  Widget _button({required bool showLabel}) {
    return Container(
      margin: EdgeInsets.only(right: isCompact ? 8 : 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 8 : 12,
              vertical: isCompact ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: isPrimary
                  ? const Color(0xFFE50914).withValues(alpha: 0.9)
                  : Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isPrimary
                    ? const Color(0xFFE50914)
                    : Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: isCompact ? 16 : 18),
                if (showLabel && (!isCompact || label.isNotEmpty)) ...[
                  SizedBox(width: isCompact ? 4 : 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isCompact ? 10 : 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

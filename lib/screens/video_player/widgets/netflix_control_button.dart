import 'package:flutter/material.dart';

// Netflix-style control button widget
class NetflixControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;
  final bool isCompact;

  const NetflixControlButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
    this.isCompact = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
                  ? const Color(0xFFE50914).withOpacity(0.9)
                  : Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isPrimary
                    ? const Color(0xFFE50914)
                    : Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: isCompact ? 16 : 18),
                if (!isCompact || label.isNotEmpty) ...[
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

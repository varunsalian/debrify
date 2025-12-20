import 'package:flutter/material.dart';

class TitleBadge extends StatelessWidget {
  final String title;

  const TitleBadge({
    Key? key,
    required this.title,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 14, top: 8, bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        // Layered background for glassy blur effect
        boxShadow: [
          // Outer glow/shadow
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
        // Multiple gradients stacked to create frosted glass effect
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withOpacity(0.85), // Main frosted glass
            Colors.black.withOpacity(0.8),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Subtle left accent line with gradient
          Container(
            width: 1.5,
            height: 20,
            margin: const EdgeInsets.only(right: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF66FF00), // Neon green
                  Color(0xFF4CAF50), // Green
                  Color(0xFF00BCD4), // Cyan
                ],
              ),
              borderRadius: BorderRadius.all(Radius.circular(1)),
            ),
          ),
          // Play icon
          const Text(
            '▶',
            style: TextStyle(
              color: Color(0xFF66FF00),
              fontSize: 12,
              height: 1.0,
              shadows: [
                Shadow(
                  color: Color(0x40000000),
                  offset: Offset(0, 1),
                  blurRadius: 3,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Video title
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xE6FFFFFF), // 90% opacity white
                fontSize: 11,
                fontWeight: FontWeight.w400,
                height: 1.0,
                shadows: [
                  Shadow(
                    color: Color(0x40000000),
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

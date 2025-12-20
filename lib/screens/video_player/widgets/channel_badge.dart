import 'package:flutter/material.dart';

class ChannelBadge extends StatelessWidget {
  final String badgeText;

  const ChannelBadge({
    Key? key,
    required this.badgeText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Parse channel number and name from badgeText (format: "CH 05 • HBO MAX" or just "HBO MAX")
    String? channelNumber;
    String? channelName;

    if (badgeText.contains('•')) {
      final parts = badgeText.split('•');
      if (parts.length == 2) {
        // Remove "CH " prefix if exists and just keep the number
        final numberPart = parts[0].trim().replaceFirst('CH ', '');
        channelNumber = numberPart;
        channelName = parts[1].trim();
      }
    } else {
      // Just channel name, no number
      channelName = badgeText;
    }

    return Container(
      padding: const EdgeInsets.only(left: 14, right: 16, top: 10, bottom: 10),
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
            width: 2,
            height: 24,
            margin: const EdgeInsets.only(right: 12),
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
          // Channel number (if exists)
          if (channelNumber != null) ...[
            Text(
              channelNumber,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                shadows: [
                  Shadow(
                    color: Color(0x40000000),
                    offset: Offset(0, 1),
                    blurRadius: 3,
                  ),
                ],
              ),
            ),
            // Separator dot
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '•',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.53),
                  fontSize: 11,
                ),
              ),
            ),
          ],
          // Channel name
          if (channelName != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                channelName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xE6FFFFFF), // 90% opacity white
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
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

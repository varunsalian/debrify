import 'package:flutter/material.dart';
import '../models/hud_state.dart';

class AspectRatioHud extends StatelessWidget {
  final AspectRatioHudState hud;
  const AspectRatioHud({Key? key, required this.hud}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(hud.icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            hud.aspectRatio,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

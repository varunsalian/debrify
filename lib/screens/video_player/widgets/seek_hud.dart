import 'package:flutter/material.dart';
import '../models/hud_state.dart';

class SeekHud extends StatelessWidget {
  final SeekHudState hud;
  final String Function(Duration) format;
  const SeekHud({super.key, required this.hud, required this.format});
  @override
  Widget build(BuildContext context) {
    final delta = hud.target - hud.base;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hud.isForward
                ? Icons.fast_forward_rounded
                : Icons.fast_rewind_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            '${format(hud.target)}  (${delta.isNegative ? '-' : '+'}${format(delta)})',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

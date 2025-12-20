import 'package:flutter/material.dart';
import '../models/hud_state.dart';

class VerticalHud extends StatelessWidget {
  final VerticalHudState hud;
  const VerticalHud({Key? key, required this.hud}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final icon = hud.kind == VerticalKind.volume
        ? Icons.volume_up_rounded
        : Icons.brightness_6_rounded;
    final label = (hud.value * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            width: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: hud.value.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  hud.kind == VerticalKind.volume
                      ? Colors.lightBlueAccent
                      : Colors.amberAccent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('$label%', style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

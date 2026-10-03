import 'package:debrify/features/iptv/presentation/key_cap.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// Bottom-of-rail key hints: OK to watch fullscreen, hold OK to favourite (or
/// to pick a list, once the user has any), and — when the focused channel has
/// guide data — RIGHT for its schedule.
class IptvRailHints extends StatelessWidget {
  final bool showGuide;
  final bool hasLists;
  const IptvRailHints({
    super.key,
    this.showGuide = false,
    this.hasLists = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const KeyCap('OK'),
        const SizedBox(width: 6),
        _hint(context, 'Watch'),
        const SizedBox(width: 16),
        const KeyCap('HOLD OK'),
        const SizedBox(width: 6),
        _hint(context, hasLists ? 'Add to list' : 'Favorite'),
        if (showGuide) ...[
          const SizedBox(width: 16),
          const KeyCap('▶'),
          const SizedBox(width: 6),
          _hint(context, 'Guide'),
        ],
      ],
    );
  }

  Widget _hint(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      color: AppThemeScope.of(context).core.tx.withValues(alpha: 0.45),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
  );
}

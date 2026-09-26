import 'package:flutter/material.dart';

import '../../theme/app_theme_scope.dart';

/// The "See All ›" affordance in a rail header — a mouse/tap entry to the
/// full-screen See-All screen, shown on desktop only. Kept understated (quiet
/// grey that brightens on hover, no accent fill) so it doesn't compete with the
/// posters. TV rails are chrome-free and paginate on scroll instead.
class SeeAllLink extends StatefulWidget {
  final VoidCallback onTap;
  final bool compact;
  const SeeAllLink({super.key, required this.onTap, this.compact = false});

  @override
  State<SeeAllLink> createState() => _SeeAllLinkState();
}

class _SeeAllLinkState extends State<SeeAllLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final color = _hover ? app.core.tx : app.fade(app.core.tx, 0.5);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: _hover ? app.fade(app.core.tx, 0.08) : Colors.transparent,
            borderRadius: app.shape.br(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.compact ? 'All' : 'See All',
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 17, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

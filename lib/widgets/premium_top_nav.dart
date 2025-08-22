import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'premium_nav_bar.dart' show NavItem; // reuse NavItem type

class PremiumTopNav extends StatelessWidget implements PreferredSizeWidget {
  final int currentIndex;
  final List<NavItem> items;
  final ValueChanged<int> onTap;
  final List<int>? badges;
  final bool haptics;

  const PremiumTopNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.badges,
    this.haptics = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              _TopNavButton(
                selected: i == currentIndex,
                icon: items[i].icon,
                label: items[i].label,
                badge: (badges != null && i < badges!.length) ? badges![i] : null,
                onPressed: () {
                  if (haptics) HapticFeedback.selectionClick();
                  onTap(i);
                },
              ),
              if (i != items.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopNavButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final int? badge;
  final VoidCallback onPressed;

  const _TopNavButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 12 : 8,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: selected ? colorScheme.primary.withValues(alpha: 0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: selected ? Border.all(color: colorScheme.primary.withValues(alpha: 0.35)) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: selected ? colorScheme.primary : Colors.white70),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeOut,
                  child: selected
                      ? Padding(
                          key: const ValueKey('label'),
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('empty')),
                ),
              ],
            ),
          ),
        ),
        if ((badge ?? 0) > 0)
          Positioned(
            right: -4,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.tertiary,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.black.withValues(alpha: 0.2)),
              ),
              child: Text(
                badge! > 99 ? '99+' : '$badge',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
} 
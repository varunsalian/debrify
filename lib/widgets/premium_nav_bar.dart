import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PremiumNavBar extends StatelessWidget {
  final int currentIndex;
  final List<NavItem> items;
  final ValueChanged<int> onTap;
  final List<int>? badges; // counts per item
  final bool haptics;

  const PremiumNavBar({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.badges,
    this.haptics = true,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (int i = 0; i < items.length; i++)
                    _PremiumNavButton(
                      selected: i == currentIndex,
                      icon: items[i].icon,
                      label: items[i].label,
                      badge: (badges != null && i < badges!.length) ? badges![i] : null,
                      onPressed: () {
                        if (haptics) HapticFeedback.selectionClick();
                        onTap(i);
                      },
                    )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumNavButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final int? badge;
  final VoidCallback onPressed;

  const _PremiumNavButton({
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
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? colorScheme.primary.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: selected ? Border.all(color: colorScheme.primary.withValues(alpha: 0.35)) : null,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(icon, color: selected ? colorScheme.primary : Colors.white70, size: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: selected
                        ? Padding(
                            key: const ValueKey('label'),
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              label,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('empty')),
                  ),
                ],
              ),
            ),
          ),
        ),
        if ((badge ?? 0) > 0)
          Positioned(
            right: -2,
            top: -2,
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

class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

List<NavItem> buildDefaultNavItems(List<IconData> icons, List<String> labels) {
  assert(icons.length == labels.length);
  return [for (int i = 0; i < icons.length; i++) NavItem(icons[i], labels[i])];
} 
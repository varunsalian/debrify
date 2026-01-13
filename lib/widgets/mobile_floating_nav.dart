import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A floating action button menu for mobile navigation
/// Expands to show all navigation options in a speed-dial style
class MobileFloatingNav extends StatefulWidget {
  final int currentIndex;
  final List<MobileNavItem> items;
  final ValueChanged<int> onTap;

  const MobileFloatingNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  @override
  State<MobileFloatingNav> createState() => _MobileFloatingNavState();
}

class _MobileFloatingNavState extends State<MobileFloatingNav>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _rotateAnimation = Tween<double>(begin: 0, end: 0.125).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isExpanded = !_isExpanded;
    });
    if (_isExpanded) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  void _selectItem(int index) {
    HapticFeedback.selectionClick();
    _toggle();
    widget.onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentItem = widget.items[widget.currentIndex];

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // Backdrop when expanded
        if (_isExpanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggle,
              child: AnimatedBuilder(
                animation: _expandAnimation,
                builder: (context, child) {
                  return BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 5 * _expandAnimation.value,
                      sigmaY: 5 * _expandAnimation.value,
                    ),
                    child: Container(
                      color: Colors.black.withValues(
                        alpha: 0.5 * _expandAnimation.value,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        // Menu items (shown when expanded)
        Positioned(
          bottom: 80,
          right: 16,
          child: AnimatedBuilder(
            animation: _expandAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _expandAnimation.value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - _expandAnimation.value)),
                  child: IgnorePointer(
                    ignoring: !_isExpanded,
                    child: child,
                  ),
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < widget.items.length; i++) ...[
                  _MenuItemButton(
                    item: widget.items[i],
                    isSelected: i == widget.currentIndex,
                    onTap: () => _selectItem(i),
                    delay: i * 30,
                  ),
                  if (i < widget.items.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),

        // Main FAB button
        Positioned(
          bottom: 16,
          right: 16,
          child: GestureDetector(
            onTap: _toggle,
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colorScheme.primary,
                        colorScheme.primary.withValues(alpha: 0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: RotationTransition(
                    turns: _rotateAnimation,
                    child: Icon(
                      _isExpanded ? Icons.close_rounded : currentItem.icon,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuItemButton extends StatelessWidget {
  final MobileNavItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final int delay;

  const _MenuItemButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.2)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              size: 20,
              color: isSelected ? colorScheme.primary : Colors.white70,
            ),
            const SizedBox(width: 12),
            Text(
              item.label,
              style: TextStyle(
                color: isSelected ? colorScheme.primary : Colors.white,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Navigation item data
class MobileNavItem {
  final IconData icon;
  final String label;

  const MobileNavItem(this.icon, this.label);
}

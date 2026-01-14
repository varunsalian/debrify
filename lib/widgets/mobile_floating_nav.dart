import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A premium floating action button menu for mobile navigation
/// Features smooth animations, glassmorphism, and staggered reveals
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
    with TickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _mainController;
  late AnimationController _staggerController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateAnimation;
  late Animation<double> _blurAnimation;
  late List<Animation<double>> _itemAnimations;

  // Icon colors for each menu item
  static const List<List<Color>> _itemGradients = [
    [Color(0xFF6366F1), Color(0xFF8B5CF6)], // Torrent Search - Indigo/Purple
    [Color(0xFF10B981), Color(0xFF059669)], // Playlist - Emerald
    [Color(0xFF3B82F6), Color(0xFF1D4ED8)], // Downloads - Blue
    [Color(0xFFF59E0B), Color(0xFFD97706)], // Debrify TV - Amber
    [Color(0xFFEF4444), Color(0xFFDC2626)], // Real Debrid - Red
    [Color(0xFF8B5CF6), Color(0xFF7C3AED)], // Torbox - Purple
    [Color(0xFF6B7280), Color(0xFF4B5563)], // Settings - Gray
    [Color(0xFF06B6D4), Color(0xFF0891B2)], // PikPak - Cyan
  ];

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _mainController, curve: Curves.easeOutCubic),
    );

    _rotateAnimation = Tween<double>(begin: 0, end: 0.125).animate(
      CurvedAnimation(parent: _mainController, curve: Curves.easeOutBack),
    );

    _blurAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _mainController, curve: Curves.easeOut),
    );

    _buildItemAnimations();
  }

  void _buildItemAnimations() {
    final itemCount = widget.items.length;
    _itemAnimations = List.generate(itemCount, (index) {
      final startInterval = index / (itemCount + 1);
      final endInterval = (index + 1.5) / (itemCount + 1);
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(
            startInterval.clamp(0.0, 1.0),
            endInterval.clamp(0.0, 1.0),
            curve: Curves.easeOutBack,
          ),
        ),
      );
    });
  }

  @override
  void didUpdateWidget(MobileFloatingNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _buildItemAnimations();
    }
  }

  @override
  void dispose() {
    _mainController.dispose();
    _staggerController.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isExpanded = !_isExpanded;
    });
    if (_isExpanded) {
      _mainController.forward();
      _staggerController.forward();
    } else {
      _staggerController.reverse();
      _mainController.reverse();
    }
  }

  void _selectItem(int index) {
    HapticFeedback.selectionClick();
    _toggle();
    widget.onTap(index);
  }

  List<Color> _getGradientForIndex(int index) {
    if (index < _itemGradients.length) {
      return _itemGradients[index];
    }
    return _itemGradients[0];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentItem = widget.items[widget.currentIndex];
    final currentGradient = _getGradientForIndex(widget.currentIndex);

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // Backdrop with blur when expanded
        if (_isExpanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggle,
              child: AnimatedBuilder(
                animation: _blurAnimation,
                builder: (context, child) {
                  return BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 8 * _blurAnimation.value,
                      sigmaY: 8 * _blurAnimation.value,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.3 * _blurAnimation.value),
                            Colors.black.withValues(alpha: 0.6 * _blurAnimation.value),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        // Menu items
        Positioned(
          bottom: 76,
          right: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < widget.items.length; i++) ...[
                AnimatedBuilder(
                  animation: _itemAnimations[i],
                  builder: (context, child) {
                    final value = _itemAnimations[i].value;
                    return Transform.translate(
                      offset: Offset(50 * (1 - value), 0),
                      child: Transform.scale(
                        scale: 0.5 + (0.5 * value),
                        alignment: Alignment.centerRight,
                        child: Opacity(
                          opacity: value.clamp(0.0, 1.0),
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: IgnorePointer(
                    ignoring: !_isExpanded,
                    child: _PremiumMenuItem(
                      item: widget.items[i],
                      isSelected: i == widget.currentIndex,
                      gradient: _getGradientForIndex(i),
                      onTap: () => _selectItem(i),
                    ),
                  ),
                ),
                if (i < widget.items.length - 1) const SizedBox(height: 4),
              ],
            ],
          ),
        ),

        // Main FAB button
        Positioned(
          bottom: 16,
          right: 16,
          child: GestureDetector(
            onTap: _toggle,
            child: AnimatedBuilder(
              animation: _mainController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _isExpanded
                            ? [const Color(0xFF374151), const Color(0xFF1F2937)]
                            : currentGradient,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: (_isExpanded ? Colors.black : currentGradient[0])
                              .withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                          spreadRadius: 0,
                        ),
                        BoxShadow(
                          color: (_isExpanded ? Colors.black : currentGradient[1])
                              .withValues(alpha: 0.2),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Menu/close icon
                        RotationTransition(
                          turns: _rotateAnimation,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              _isExpanded ? Icons.close_rounded : Icons.menu_rounded,
                              key: ValueKey(_isExpanded),
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ],
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

class _PremiumMenuItem extends StatefulWidget {
  final MobileNavItem item;
  final bool isSelected;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _PremiumMenuItem({
    required this.item,
    required this.isSelected,
    required this.gradient,
    required this.onTap,
  });

  @override
  State<_PremiumMenuItem> createState() => _PremiumMenuItemState();
}

class _PremiumMenuItemState extends State<_PremiumMenuItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 150, // Fixed width for uniform appearance
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            // Glassmorphism effect
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isSelected
                  ? [
                      widget.gradient[0].withValues(alpha: 0.25),
                      widget.gradient[1].withValues(alpha: 0.15),
                    ]
                  : [
                      const Color(0xFF1E293B).withValues(alpha: 0.9),
                      const Color(0xFF0F172A).withValues(alpha: 0.95),
                    ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isSelected
                  ? widget.gradient[0].withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.isSelected
                    ? widget.gradient[0].withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.25),
                blurRadius: widget.isSelected ? 12 : 8,
                offset: const Offset(0, 2),
                spreadRadius: -2,
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon with gradient background
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.isSelected
                        ? widget.gradient
                        : [
                            widget.gradient[0].withValues(alpha: 0.2),
                            widget.gradient[1].withValues(alpha: 0.1),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: widget.isSelected
                      ? [
                          BoxShadow(
                            color: widget.gradient[0].withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  widget.item.icon,
                  size: 14,
                  color: widget.isSelected
                      ? Colors.white
                      : widget.gradient[0].withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(width: 10),
              // Label
              Expanded(
                child: Text(
                  widget.item.label,
                  style: TextStyle(
                    color: widget.isSelected ? Colors.white : Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (widget.isSelected)
                // Active indicator dot
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: widget.gradient,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.gradient[0].withValues(alpha: 0.5),
                        blurRadius: 4,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),
            ],
          ),
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

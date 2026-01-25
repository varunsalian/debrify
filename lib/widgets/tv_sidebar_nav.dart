import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/main_page_bridge.dart';

/// YouTube-style collapsible sidebar navigation for Android TV
/// Collapsed by default (icons only), expands when focused
class TvSidebarNav extends StatefulWidget {
  final int currentIndex;
  final List<TvNavItem> items;
  final ValueChanged<int> onTap;
  final VoidCallback? onFocusContent;

  const TvSidebarNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.onFocusContent,
  });

  @override
  State<TvSidebarNav> createState() => TvSidebarNavState();
}

class TvSidebarNavState extends State<TvSidebarNav>
    with SingleTickerProviderStateMixin {
  final List<FocusNode> _focusNodes = [];
  int _focusedIndex = 0;
  bool _isExpanded = false;
  bool _hasSidebarFocus = false;

  // Animation for expand/collapse
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  // Dimensions
  static const double _collapsedWidth = 72.0;
  static const double _expandedWidth = 240.0;

  // Delay for page transition before focusing content (ms)
  static const int _pageTransitionDelay = 400;

  @override
  void initState() {
    super.initState();
    _initFocusNodes();
    _focusedIndex = widget.currentIndex;

    _expandController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // NOTE: Removed auto-focus on first frame - sidebar should only open when user
    // explicitly navigates to it (DPAD left). Auto-focusing caused sidebar to
    // expand on app launch which is not desired behavior.
  }

  void _initFocusNodes() {
    for (final node in _focusNodes) {
      node.removeListener(() {});
      node.dispose();
    }
    _focusNodes.clear();

    for (int i = 0; i < widget.items.length; i++) {
      final node = FocusNode(debugLabel: 'tv-nav-item-$i');
      // FIX: Capture index by value using a local final variable
      final capturedIndex = i;
      node.addListener(() => _handleFocusChange(capturedIndex, node.hasFocus));
      _focusNodes.add(node);
    }
  }

  void _handleFocusChange(int index, bool hasFocus) {
    if (!mounted) return;

    if (hasFocus) {
      setState(() {
        _focusedIndex = index;
        _isExpanded = true;
        _hasSidebarFocus = true;
      });
      _expandController.forward();
    } else {
      // Check if ANY sidebar item still has focus
      final anySidebarFocused = _focusNodes.any((node) => node.hasFocus);
      if (!anySidebarFocused) {
        setState(() {
          _hasSidebarFocus = false;
          _isExpanded = false;
        });
        _expandController.reverse();
      }
    }
  }

  void _collapse() {
    setState(() {
      _isExpanded = false;
      _hasSidebarFocus = false;
    });
    _expandController.reverse();
  }

  /// Select a menu item and navigate to its content
  /// Consolidated method for both tap and key selection
  void _selectMenuItem(int index) {
    // Notify parent of selection
    widget.onTap(index);

    // Collapse sidebar
    _collapse();

    // Wait for page transition animation to complete before focusing content
    Future.delayed(const Duration(milliseconds: _pageTransitionDelay), () {
      if (mounted) {
        _focusContent();
      }
    });
  }

  /// Focus content using MainPageBridge, with fallback to callback
  void _focusContent() {
    // Try MainPageBridge first (screen-specific focus handler)
    if (!MainPageBridge.requestTvContentFocus()) {
      // Fallback to generic callback
      widget.onFocusContent?.call();
    }
  }

  /// Move focus from sidebar to content without changing the current tab
  void _moveToContent() {
    _collapse();

    // Small delay to ensure sidebar is collapsed and screen is ready
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _focusContent();
      }
    });
  }

  @override
  void didUpdateWidget(TvSidebarNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _initFocusNodes();
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _expandController.dispose();
    super.dispose();
  }

  /// Request focus on the sidebar (called from parent when DPAD left is pressed)
  void requestFocus() {
    if (_focusNodes.isNotEmpty) {
      final targetIndex = widget.currentIndex.clamp(0, _focusNodes.length - 1);
      _focusNodes[targetIndex].requestFocus();
    }
  }

  /// Check if sidebar currently has focus
  bool get hasFocus => _hasSidebarFocus;

  KeyEventResult _handleKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        if (index > 0) {
          _focusNodes[index - 1].requestFocus();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowDown:
        if (index < _focusNodes.length - 1) {
          _focusNodes[index + 1].requestFocus();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
        // Move focus to content area without changing tab
        _moveToContent();
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowLeft:
        // Already at left edge, do nothing
        return KeyEventResult.handled;

      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.gameButtonA:
        // Select this menu item and navigate to its content
        _selectMenuItem(index);
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        final width = _collapsedWidth +
            (_expandedWidth - _collapsedWidth) * _expandAnimation.value;

        return Container(
          width: width,
          decoration: BoxDecoration(
            // Gradient background - more visible when expanded
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color.lerp(
                  const Color(0xFF0F172A).withValues(alpha: 0.95),
                  const Color(0xFF0F172A),
                  _expandAnimation.value,
                )!,
                Color.lerp(
                  const Color(0xFF0F172A).withValues(alpha: 0.7),
                  const Color(0xFF0F172A).withValues(alpha: 0.95),
                  _expandAnimation.value,
                )!,
                Colors.transparent,
              ],
              stops: const [0.0, 0.85, 1.0],
            ),
            // Subtle right border when expanded
            border: Border(
              right: BorderSide(
                color: Colors.white.withValues(alpha: 0.05 * _expandAnimation.value),
                width: 1,
              ),
            ),
          ),
          child: child,
        );
      },
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App branding at top
              _buildBranding(),

              const SizedBox(height: 8),

              // Navigation items
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  itemCount: widget.items.length,
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    final isSelected = index == widget.currentIndex;
                    final isFocused = index == _focusedIndex && _hasSidebarFocus;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _TvNavItemWidget(
                        item: item,
                        isSelected: isSelected,
                        isFocused: isFocused,
                        isExpanded: _isExpanded,
                        expandAnimation: _expandAnimation,
                        focusNode: _focusNodes[index],
                        onTap: () => _selectMenuItem(index),
                        onKeyEvent: (event) => _handleKeyEvent(index, event),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBranding() {
    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            12 + (8 * _expandAnimation.value),
            8,
            12,
            16,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Debrify App Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 40,
                    height: 40,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              // App name (visible when expanded)
              ClipRect(
                child: SizedBox(
                  width: 140 * _expandAnimation.value,
                  child: Opacity(
                    opacity: _expandAnimation.value,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: Text(
                        'Debrify',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                        overflow: TextOverflow.clip,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TvNavItemWidget extends StatefulWidget {
  final TvNavItem item;
  final bool isSelected;
  final bool isFocused;
  final bool isExpanded;
  final Animation<double> expandAnimation;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final KeyEventResult Function(KeyEvent) onKeyEvent;

  const _TvNavItemWidget({
    required this.item,
    required this.isSelected,
    required this.isFocused,
    required this.isExpanded,
    required this.expandAnimation,
    required this.focusNode,
    required this.onTap,
    required this.onKeyEvent,
  });

  @override
  State<_TvNavItemWidget> createState() => _TvNavItemWidgetState();
}

class _TvNavItemWidgetState extends State<_TvNavItemWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _focusController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _focusController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _focusController, curve: Curves.easeOut),
    );
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _focusController, curve: Curves.easeOut),
    );

    if (widget.isFocused) {
      _focusController.forward();
    }
  }

  @override
  void didUpdateWidget(_TvNavItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFocused != oldWidget.isFocused) {
      if (widget.isFocused) {
        _focusController.forward();
      } else {
        _focusController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _focusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) => widget.onKeyEvent(event),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_focusController, widget.expandAnimation]),
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              alignment: Alignment.centerLeft,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  // Background color
                  color: widget.isFocused
                      ? const Color(0xFF6366F1).withValues(alpha: 0.25)
                      : widget.isSelected
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.transparent,
                  // Border for focused item
                  border: widget.isFocused
                      ? Border.all(
                          color: const Color(0xFF6366F1),
                          width: 2,
                        )
                      : null,
                  // Glow effect when focused
                  boxShadow: widget.isFocused
                      ? [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withValues(
                              alpha: 0.4 * _glowAnimation.value,
                            ),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // Icon container
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    widget.item.icon,
                    color: widget.isFocused
                        ? Colors.white
                        : widget.isSelected
                            ? const Color(0xFF6366F1)
                            : Colors.white.withValues(alpha: 0.6),
                    size: 22,
                  ),
                ),
                // Label (visible when expanded)
                AnimatedBuilder(
                  animation: widget.expandAnimation,
                  builder: (context, _) {
                    return ClipRect(
                      child: SizedBox(
                        width: 150 * widget.expandAnimation.value,
                        child: Opacity(
                          opacity: widget.expandAnimation.value,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text(
                              widget.item.label,
                              style: TextStyle(
                                color: widget.isFocused
                                    ? Colors.white
                                    : widget.isSelected
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.7),
                                fontSize: 15,
                                fontWeight: widget.isSelected || widget.isFocused
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Data class for TV navigation items
class TvNavItem {
  final IconData icon;
  final String label;

  const TvNavItem(this.icon, this.label);
}

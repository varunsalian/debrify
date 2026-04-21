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
  static const double _collapsedWidth = 48.0;
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
      // Auto-scroll to keep focused item visible (both up and down)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (index < _focusNodes.length) {
          final ctx = _focusNodes[index].context;
          if (ctx != null) {
            final scrollable = Scrollable.maybeOf(ctx);
            if (scrollable != null && scrollable.position.maxScrollExtent > 0) {
              Scrollable.ensureVisible(
                ctx,
                duration: Duration.zero,
                alignment: 0.3,
              );
            }
          }
        }
      });
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
        final width =
            _collapsedWidth +
            (_expandedWidth - _collapsedWidth) * _expandAnimation.value;

        return Container(
          width: width,
          decoration: BoxDecoration(
            color: const Color(0xFF0A0A14),
            border: Border(
              right: BorderSide(
                color: Colors.white.withValues(alpha: 0.06),
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

              // Divider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),

              const SizedBox(height: 8),

              // Navigation items
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  itemCount: widget.items.length,
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    final isSelected = index == widget.currentIndex;
                    final isFocused =
                        index == _focusedIndex && _hasSidebarFocus;

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
        final expanded = _expandAnimation.value;
        final bool showLabel = expanded > 0.08;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: SizedBox(
            height: 48,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: 32 + (expanded * 168),
                padding: EdgeInsets.symmetric(horizontal: expanded * 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: expanded <= 0.02
                      ? null
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(
                              alpha: 0.04 + (expanded * 0.03),
                            ),
                            const Color(
                              0xFF111827,
                            ).withValues(alpha: 0.68 + (expanded * 0.16)),
                          ],
                        ),
                  border: expanded <= 0.02
                      ? null
                      : Border.all(
                          color: Colors.white.withValues(
                            alpha: 0.06 + (expanded * 0.06),
                          ),
                        ),
                  boxShadow: expanded <= 0.02
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: 0.16 + (expanded * 0.08),
                            ),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                            spreadRadius: -8,
                          ),
                        ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: Image.asset(
                          'assets/app_icon.png',
                          width: 26,
                          height: 26,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    ClipRect(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        width: expanded * 96,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: showLabel ? expanded.clamp(0.0, 1.0) : 0.0,
                            child: const Padding(
                              padding: EdgeInsets.only(left: 10),
                              child: Text(
                                'Debrify',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                                overflow: TextOverflow.clip,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.03,
    ).animate(CurvedAnimation(parent: _focusController, curve: Curves.easeOut));
    _glowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _focusController, curve: Curves.easeOut));

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
          animation: Listenable.merge([
            _focusController,
            widget.expandAnimation,
          ]),
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              alignment: Alignment.centerLeft,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: widget.isFocused
                      ? Colors.white.withValues(alpha: 0.12)
                      : widget.isSelected
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.transparent,
                ),
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: widget.isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                // Selected indicator bar
                if (widget.isExpanded)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 3,
                    height: widget.isSelected ? 20 : 0,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: const Color(0xFF6366F1),
                    ),
                  ),
                // Icon
                Icon(
                  widget.item.icon,
                  color: widget.isFocused
                      ? Colors.white
                      : widget.isSelected
                      ? const Color(0xFF818CF8)
                      : Colors.white.withValues(alpha: 0.4),
                  size: 20,
                ),
                // Label (visible when expanded)
                AnimatedBuilder(
                  animation: widget.expandAnimation,
                  builder: (context, _) {
                    return ClipRect(
                      child: SizedBox(
                        width: 150 * widget.expandAnimation.value,
                        child: widget.expandAnimation.value < 0.1
                            ? const SizedBox.shrink()
                            : Opacity(
                                opacity: widget.expandAnimation.value,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          widget.item.label,
                                          style: TextStyle(
                                            color: widget.isFocused
                                                ? Colors.white
                                                : widget.isSelected
                                                ? Colors.white.withValues(
                                                    alpha: 0.95,
                                                  )
                                                : Colors.white.withValues(
                                                    alpha: 0.45,
                                                  ),
                                            fontSize: 14,
                                            fontWeight:
                                                widget.isSelected ||
                                                    widget.isFocused
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            letterSpacing: 0.1,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.clip,
                                          softWrap: false,
                                        ),
                                      ),
                                      if (widget.item.tag != null) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: Colors.amber.withValues(
                                                alpha: 0.4,
                                              ),
                                              width: 0.5,
                                            ),
                                          ),
                                          child: Text(
                                            widget.item.tag!,
                                            style: const TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.amber,
                                              letterSpacing: 0.5,
                                              height: 1.2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
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
  final String? tag;

  const TvNavItem(this.icon, this.label, {this.tag});
}

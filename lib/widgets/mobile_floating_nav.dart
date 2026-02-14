import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A premium glassmorphic floating action button menu for mobile navigation
/// Features frosted glass effect, smooth animations, and elegant reveals
class MobileFloatingNav extends StatefulWidget {
  final int currentIndex;
  final List<MobileNavItem> items;
  final ValueChanged<int> onTap;
  final VoidCallback? onRemoteControlTap;

  const MobileFloatingNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.onRemoteControlTap,
  });

  @override
  State<MobileFloatingNav> createState() => _MobileFloatingNavState();
}

class _MobileFloatingNavState extends State<MobileFloatingNav>
    with TickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _mainController;
  late AnimationController _menuController;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _backdropAnimation;
  late Animation<double> _menuSlideAnimation;
  late Animation<double> _menuFadeAnimation;
  late Animation<double> _pulseAnimation;

  // Icon colors for each menu item
  static const List<List<Color>> _itemGradients = [
    [Color(0xFF6366F1), Color(0xFF8B5CF6)], // Torrent Search - Indigo/Purple
    [Color(0xFF10B981), Color(0xFF059669)], // Playlist - Emerald
    [Color(0xFF3B82F6), Color(0xFF1D4ED8)], // Downloads - Blue
    [Color(0xFFF59E0B), Color(0xFFD97706)], // Debrify TV - Amber
    [Color(0xFFEF4444), Color(0xFFDC2626)], // Real Debrid - Red
    [Color(0xFF8B5CF6), Color(0xFF7C3AED)], // Torbox - Purple
    [Color(0xFF06B6D4), Color(0xFF0891B2)], // PikPak - Cyan
    [Color(0xFF14B8A6), Color(0xFF0D9488)], // Addons - Teal
    [Color(0xFF6B7280), Color(0xFF4B5563)], // Settings - Gray
  ];

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _menuController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _mainController, curve: Curves.easeOutCubic),
    );

    _backdropAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _mainController, curve: Curves.easeOut),
    );

    _menuSlideAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _menuController, curve: Curves.easeOutCubic),
    );

    _menuFadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _menuController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _mainController.dispose();
    _menuController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isExpanded = !_isExpanded;
    });
    if (_isExpanded) {
      _mainController.forward();
      _menuController.forward();
    } else {
      _menuController.reverse();
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final topPadding = MediaQuery.of(context).padding.top;
    final screenHeight = MediaQuery.of(context).size.height;
    // Calculate max menu height: screen - top safe area - bottom button area - some padding
    final maxMenuHeight = screenHeight - topPadding - 100 - bottomPadding - 40;

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // Backdrop with blur when expanded
        if (_isExpanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggle,
              child: AnimatedBuilder(
                animation: _backdropAnimation,
                builder: (context, child) {
                  return BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 12 * _backdropAnimation.value,
                      sigmaY: 12 * _backdropAnimation.value,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.2 * _backdropAnimation.value),
                            Colors.black.withValues(alpha: 0.5 * _backdropAnimation.value),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        // Glassmorphic menu panel
        Positioned(
          bottom: 80 + bottomPadding,
          right: 16,
          child: AnimatedBuilder(
            animation: Listenable.merge([_menuSlideAnimation, _menuFadeAnimation]),
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - _menuSlideAnimation.value)),
                child: Transform.scale(
                  scale: 0.9 + (0.1 * _menuSlideAnimation.value),
                  alignment: Alignment.bottomRight,
                  child: Opacity(
                    opacity: _menuFadeAnimation.value.clamp(0.0, 1.0),
                    child: child,
                  ),
                ),
              );
            },
            child: IgnorePointer(
              ignoring: !_isExpanded,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    width: 220,
                    constraints: BoxConstraints(maxHeight: maxMenuHeight),
                    decoration: BoxDecoration(
                      // Glassmorphic background
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.15),
                          Colors.white.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                          spreadRadius: -5,
                        ),
                      ],
                    ),
                    child: _ScrollableMenuContent(
                      items: widget.items,
                      currentIndex: widget.currentIndex,
                      getGradientForIndex: _getGradientForIndex,
                      onSelectItem: _selectItem,
                      onRemoteControlTap: widget.onRemoteControlTap != null
                          ? () {
                              _toggle();
                              widget.onRemoteControlTap!();
                            }
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Main FAB button - clean minimal design
        Positioned(
          bottom: 16 + bottomPadding,
          right: 16,
          child: GestureDetector(
            onTap: _toggle,
            child: AnimatedBuilder(
              animation: Listenable.merge([_mainController, _pulseAnimation]),
              builder: (context, child) {
                final pulseValue = _isExpanded ? 0.0 : _pulseAnimation.value;
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        // Subtle glow
                        BoxShadow(
                          color: _isExpanded
                              ? Colors.black.withValues(alpha: 0.2)
                              : const Color(0xFF8B5CF6).withValues(alpha: 0.4 + 0.15 * pulseValue),
                          blurRadius: 16 + 4 * pulseValue,
                          offset: const Offset(0, 6),
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: _isExpanded
                                  ? [
                                      Colors.white.withValues(alpha: 0.15),
                                      Colors.white.withValues(alpha: 0.08),
                                    ]
                                  : [
                                      const Color(0xFF8B5CF6),
                                      const Color(0xFF6366F1),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: _isExpanded ? 0.2 : 0.25),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Simple animated icon
                              _SimpleAnimatedIcon(
                                isExpanded: _isExpanded,
                                pulseValue: pulseValue,
                              ),
                              const SizedBox(width: 8),
                              // Text label
                              Text(
                                _isExpanded ? 'Close' : 'Menu',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

/// Scrollable menu content with scroll indicator
class _ScrollableMenuContent extends StatefulWidget {
  final List<MobileNavItem> items;
  final int currentIndex;
  final List<Color> Function(int) getGradientForIndex;
  final void Function(int) onSelectItem;
  final VoidCallback? onRemoteControlTap;

  const _ScrollableMenuContent({
    required this.items,
    required this.currentIndex,
    required this.getGradientForIndex,
    required this.onSelectItem,
    this.onRemoteControlTap,
  });

  @override
  State<_ScrollableMenuContent> createState() => _ScrollableMenuContentState();
}

class _ScrollableMenuContentState extends State<_ScrollableMenuContent> {
  final ScrollController _scrollController = ScrollController();
  bool _showBottomIndicator = false;
  bool _showTopIndicator = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateIndicators);
    // Check after first frame if content is scrollable
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateIndicators());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateIndicators);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateIndicators() {
    if (!mounted || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    final atTop = position.pixels <= 0;
    final atBottom = position.pixels >= position.maxScrollExtent;
    final isScrollable = position.maxScrollExtent > 0;

    setState(() {
      _showTopIndicator = isScrollable && !atTop;
      _showBottomIndicator = isScrollable && !atBottom;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < widget.items.length; i++) ...[
                  _GlassMenuItem(
                    item: widget.items[i],
                    isSelected: i == widget.currentIndex,
                    gradient: widget.getGradientForIndex(i),
                    onTap: () => widget.onSelectItem(i),
                  ),
                  if (i < widget.items.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Divider(
                        height: 1,
                        thickness: 0.5,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                ],
                // Remote Control action item (accent line style)
                if (widget.onRemoteControlTap != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  _RemoteControlMenuItem(
                    onTap: widget.onRemoteControlTap!,
                  ),
                ],
              ],
            ),
          ),
          // Top fade gradient
          if (_showTopIndicator)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF1a1a2e).withValues(alpha: 0.95),
                        Colors.transparent,
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          // Bottom fade gradient
          if (_showBottomIndicator)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        const Color(0xFF1a1a2e).withValues(alpha: 0.95),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Glassmorphic menu item with hover/tap states
class _GlassMenuItem extends StatefulWidget {
  final MobileNavItem item;
  final bool isSelected;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _GlassMenuItem({
    required this.item,
    required this.isSelected,
    required this.gradient,
    required this.onTap,
  });

  @override
  State<_GlassMenuItem> createState() => _GlassMenuItemState();
}

class _GlassMenuItemState extends State<_GlassMenuItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..scale(_isPressed ? 0.97 : 1.0),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          gradient: widget.isSelected || _isPressed
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.gradient[0].withValues(alpha: widget.isSelected ? 0.25 : 0.15),
                    widget.gradient[1].withValues(alpha: widget.isSelected ? 0.15 : 0.08),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(12),
          border: widget.isSelected
              ? Border.all(
                  color: widget.gradient[0].withValues(alpha: 0.4),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          children: [
            // Icon container with gradient
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 36,
              height: 36,
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
                borderRadius: BorderRadius.circular(10),
                boxShadow: widget.isSelected
                    ? [
                        BoxShadow(
                          color: widget.gradient[0].withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                          spreadRadius: -2,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                widget.item.icon,
                size: 18,
                color: widget.isSelected
                    ? Colors.white
                    : widget.gradient[0].withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 12),
            // Label
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.item.label,
                      style: TextStyle(
                        color: widget.isSelected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.85),
                        fontSize: 14,
                        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  if (widget.item.tag != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 0.5),
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
            // Selected indicator
            if (widget.isSelected)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: widget.gradient),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.gradient[0].withValues(alpha: 0.6),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Simple animated icon - 4 dots with subtle movement
class _SimpleAnimatedIcon extends StatelessWidget {
  final bool isExpanded;
  final double pulseValue;

  const _SimpleAnimatedIcon({
    required this.isExpanded,
    required this.pulseValue,
  });

  @override
  Widget build(BuildContext context) {
    if (isExpanded) {
      return const Icon(
        Icons.close_rounded,
        color: Colors.white,
        size: 18,
      );
    }

    // 2x2 grid of dots with subtle animation
    return SizedBox(
      width: 16,
      height: 16,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Dot(opacity: 0.9 + 0.1 * pulseValue),
              _Dot(opacity: 0.7 + 0.3 * (1 - pulseValue)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Dot(opacity: 0.7 + 0.3 * (1 - pulseValue)),
              _Dot(opacity: 0.9 + 0.1 * pulseValue),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final double opacity;

  const _Dot({required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}

/// Remote Control menu item - accent line style
class _RemoteControlMenuItem extends StatefulWidget {
  final VoidCallback onTap;

  const _RemoteControlMenuItem({required this.onTap});

  @override
  State<_RemoteControlMenuItem> createState() => _RemoteControlMenuItemState();
}

class _RemoteControlMenuItemState extends State<_RemoteControlMenuItem> {
  bool _isPressed = false;

  static const _accentColor = Color(0xFF06B6D4); // Cyan

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()..scale(_isPressed ? 0.98 : 1.0),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _isPressed ? _accentColor.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: _accentColor.withValues(alpha: _isPressed ? 1.0 : 0.6),
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.phonelink_rounded,
              size: 18,
              color: _accentColor.withValues(alpha: _isPressed ? 1.0 : 0.8),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Remote',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: _isPressed ? 1.0 : 0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Control your TV',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 12,
              color: _accentColor.withValues(alpha: 0.5),
            ),
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
  final String? tag;

  const MobileNavItem(this.icon, this.label, {this.tag});
}

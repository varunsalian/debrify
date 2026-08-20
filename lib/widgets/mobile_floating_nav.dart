import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_motion.dart';
import '../theme/app_surface.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_scope.dart';
import '../theme/widgets/glass_surface.dart';
import '../models/profiles/user_profile.dart';
import 'profiles/profile_avatar_view.dart';

/// A premium glassmorphic floating action button menu for mobile navigation
/// Features frosted glass effect, smooth animations, and elegant reveals
class MobileFloatingNav extends StatefulWidget {
  final int currentIndex;
  final List<MobileNavItem> items;
  final ValueChanged<int> onTap;
  final VoidCallback? onRemoteControlTap;
  final UserProfile? profile;
  final VoidCallback? onProfileTap;

  const MobileFloatingNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.onRemoteControlTap,
    this.profile,
    this.onProfileTap,
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

  // Held so didChangeDependencies can retarget their curve when the theme (or
  // the reduced-motion setting) changes; only the two that shipped the token
  // curve are kept — the rest stay as authored.
  late CurvedAnimation _scaleCurve;
  late CurvedAnimation _menuSlideCurve;

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

    // Deliberately NOT tokenised: this one repeats forever, and a repeating
    // controller cannot take the zero duration reduced motion resolves to.
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _scaleCurve = CurvedAnimation(
      parent: _mainController,
      curve: Curves.easeOutCubic,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(_scaleCurve);

    _backdropAnimation = Tween<double>(begin: 0, end: 1).animate(
      // Plain easeOut, which is neither token curve — left as shipped.
      CurvedAnimation(parent: _mainController, curve: Curves.easeOut),
    );

    _menuSlideCurve = CurvedAnimation(
      parent: _menuController,
      curve: Curves.easeOutCubic,
    );
    _menuSlideAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(_menuSlideCurve);

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The hook that may depend on inherited widgets AND re-runs when they
    // change, so a theme or accessibility switch retargets both live
    // controllers. Legacy resolves back to exactly what initState built.
    final motion = AppMotion.of(context);
    _mainController.duration = motion.scaled(const Duration(milliseconds: 250));
    _menuController.duration = motion.scaled(const Duration(milliseconds: 350));
    _scaleCurve.curve = motion.standard;
    _menuSlideCurve.curve = motion.standard;
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
    // Read ONCE: the FAB's AnimatedBuilder rides a repeating pulse controller,
    // so anything read inside it would be a per-frame scope walk.
    final app = AppThemeScope.of(context);
    // Hoisted with the theme read, above every builder callback below.
    final motion = AppMotion.of(context);
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
                // NOT a `GlassSurface`. Two reasons, and both are rules rather
                // than preferences. It is a SCRIM — a full-screen dim, which
                // is `LightTokens`' territory, not a pane. And its sigma is
                // animated, so wrapping it would put an inherited-theme lookup
                // inside an `AnimatedBuilder` callback, which the house rule
                // forbids: this builder runs on every frame of the reveal.
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
                            Colors.black.withValues(
                              alpha: 0.2 * _backdropAnimation.value,
                            ),
                            Colors.black.withValues(
                              alpha: 0.5 * _backdropAnimation.value,
                            ),
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
            animation: Listenable.merge([
              _menuSlideAnimation,
              _menuFadeAnimation,
            ]),
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
              child: GlassSurface(
                family: SurfaceFamily.dialog,
                borderRadius: app.shape.br(20),
                // STATED, not inherited. The theme's `glassSigma` only applies
                // under a look that asked for glass; Debrify Classic states no
                // surface opinion at all, and a site that omits its own sigma
                // gets none — which silently deleted this panel's shipped 24px
                // blur on every phone.
                sigma: 24,
                // The panel's veil is painted OVER its own drop shadow, and
                // that shadow falls inside the clip where the veil's 0.08 alpha
                // lets it darken the panel. Moving the fill up into
                // GlassSurface would put the shadow on top of it and change
                // what the panel weighs, so the whole stack stays in the child
                // and the widget is asked for the filter alone.
                tint: Colors.transparent,
                border: Colors.transparent,
                child: Container(
                  width: 220,
                  constraints: BoxConstraints(maxHeight: maxMenuHeight),
                  decoration: BoxDecoration(
                    color: app.fade(app.core.tx, 0.08),
                    borderRadius: app.shape.br(20),
                    border: Border.all(
                      color: app.fade(app.core.tx, 0.12),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
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
                    profile: widget.profile,
                    onProfileTap:
                        widget.profile != null && widget.onProfileTap != null
                        ? () {
                            _toggle();
                            widget.onProfileTap!();
                          }
                        : null,
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
                      borderRadius: app.shape.br(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: GlassSurface(
                      // A control rather than a pane, so it follows the family
                      // whose decoration it actually carries.
                      family: SurfaceFamily.card,
                      borderRadius: app.shape.br(20),
                      sigma: 16,
                      // The pill's fill and hairline TWEEN between the open and
                      // closed states (250ms at the shipped tempo); a tint
                      // handed to GlassSurface would swap instantly. The
                      // AnimatedContainer keeps them.
                      tint: Colors.transparent,
                      border: Colors.transparent,
                      child: AnimatedContainer(
                        duration: motion.scaled(
                          const Duration(milliseconds: 250),
                        ),
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: _isExpanded
                              ? app.fade(app.core.tx, 0.12)
                              : app.fade(app.core.tx, 0.1),
                          borderRadius: app.shape.br(22),
                          border: Border.all(
                            color: app.fade(
                              app.core.tx,
                              _isExpanded ? 0.25 : 0.15,
                            ),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Simple animated icon
                            _SimpleAnimatedIcon(
                              isExpanded: _isExpanded,
                              pulseValue: pulseValue,
                              app: app,
                            ),
                            const SizedBox(width: 8),
                            // Text label
                            Text(
                              _isExpanded ? 'Close' : 'Menu',
                              style: TextStyle(
                                color: app.fade(app.core.tx, 0.8),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
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
  final UserProfile? profile;
  final VoidCallback? onProfileTap;

  const _ScrollableMenuContent({
    required this.items,
    required this.currentIndex,
    required this.getGradientForIndex,
    required this.onSelectItem,
    this.onRemoteControlTap,
    this.profile,
    this.onProfileTap,
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
    final app = AppThemeScope.of(context);
    return ClipRRect(
      borderRadius: app.shape.br(20),
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
                  // Sections replace the per-item dividers: a header is
                  // drawn above the first item of each group, and no
                  // divider is inserted between items. Falls back to the
                  // old divided list when items carry no section.
                  if (widget.items[i].section != null &&
                      (i == 0 ||
                          widget.items[i - 1].section !=
                              widget.items[i].section))
                    _SectionLabel(widget.items[i].section!, first: i == 0),
                  _GlassMenuItem(
                    item: widget.items[i],
                    isSelected: i == widget.currentIndex,
                    gradient: widget.getGradientForIndex(i),
                    onTap: () => widget.onSelectItem(i),
                  ),
                  if (widget.items[i].section == null &&
                      i < widget.items.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Divider(
                        height: 1,
                        thickness: 0.5,
                        color: app.fade(app.core.tx, 0.08),
                      ),
                    ),
                ],
                // Remote Control action item (accent line style)
                if (widget.onRemoteControlTap != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: app.fade(app.core.tx, 0.1),
                    ),
                  ),
                  _RemoteControlMenuItem(onTap: widget.onRemoteControlTap!),
                ],
                if (widget.profile != null && widget.onProfileTap != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: app.fade(app.core.tx, 0.1),
                    ),
                  ),
                  _MobileProfileMenuItem(
                    profile: widget.profile!,
                    onTap: widget.onProfileTap!,
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
                      color: app.fade(app.core.tx, 0.6),
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
                      color: app.fade(app.core.tx, 0.6),
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

class _MobileProfileMenuItem extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onTap;

  const _MobileProfileMenuItem({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Material(
      key: const ValueKey('mobile-floating-profile'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: app.shape.br(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: ClipOval(
                  child: ProfileAvatarView(
                    profileId: profile.id,
                    avatarKey: profile.avatarKey,
                    role: profile.role,
                    name: profile.name,
                    animateWhenIdle: true,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: app.fade(app.core.tx, 0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      profile.isAdmin ? 'Admin' : 'Profile',
                      style: TextStyle(
                        color: app.fade(app.core.tx, 0.48),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: app.fade(app.core.tx, 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Group header inside the expanded menu. Matches the desktop / TV rail
/// label styling so all three nav surfaces read the same.
class _SectionLabel extends StatelessWidget {
  final String text;
  final bool first;
  const _SectionLabel(this.text, {this.first = false});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(14, first ? 6 : 16, 12, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: app.fade(app.core.tx, 0.38),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
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
    final app = AppThemeScope.of(context);
    final motion = AppMotion.of(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: motion.scaled(const Duration(milliseconds: 150)),
        curve: motion.standard,
        transform: Matrix4.identity()..scale(_isPressed ? 0.97 : 1.0),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          gradient: widget.isSelected || _isPressed
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.gradient[0].withValues(
                      alpha: widget.isSelected ? 0.25 : 0.15,
                    ),
                    widget.gradient[1].withValues(
                      alpha: widget.isSelected ? 0.15 : 0.08,
                    ),
                  ],
                )
              : null,
          borderRadius: app.shape.br(12),
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
              duration: motion.scaled(const Duration(milliseconds: 200)),
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
                borderRadius: app.shape.br(10),
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
                    ? app.core.tx
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
                            ? app.core.tx
                            : app.fade(app.core.tx, 0.85),
                        fontSize: 14,
                        fontWeight: widget.isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
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
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: app.shape.br(4),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.4),
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

  /// Passed down rather than read here: this widget rebuilds on every frame of
  /// the FAB's repeating pulse, so a scope lookup in its build would be one
  /// per frame. The host reads it once.
  final AppTheme app;

  const _SimpleAnimatedIcon({
    required this.isExpanded,
    required this.pulseValue,
    required this.app,
  });

  @override
  Widget build(BuildContext context) {
    if (isExpanded) {
      return Icon(Icons.close_rounded, color: app.core.tx, size: 18);
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
              _Dot(opacity: 0.9 + 0.1 * pulseValue, app: app),
              _Dot(opacity: 0.7 + 0.3 * (1 - pulseValue), app: app),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Dot(opacity: 0.7 + 0.3 * (1 - pulseValue), app: app),
              _Dot(opacity: 0.9 + 0.1 * pulseValue, app: app),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final double opacity;

  /// See [_SimpleAnimatedIcon.app] — per-frame widget, token passed in.
  final AppTheme app;

  const _Dot({required this.opacity, required this.app});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: app.fade(app.core.tx, opacity),
        borderRadius: app.shape.br(1.5),
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
    final app = AppThemeScope.of(context);
    final motion = AppMotion.of(context);
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: motion.scaled(const Duration(milliseconds: 150)),
        curve: motion.standard,
        transform: Matrix4.identity()..scale(_isPressed ? 0.98 : 1.0),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _isPressed
              ? _accentColor.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: app.shape.br(8),
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
                      color: app.fade(app.core.tx, _isPressed ? 1.0 : 0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Control your TV',
                    style: TextStyle(
                      color: app.fade(app.core.tx, 0.4),
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

  /// Group header this item sits under (e.g. "Main"). Consecutive items
  /// sharing a section render one header above the first of the group;
  /// when set, sections replace the per-item dividers.
  final String? section;

  const MobileNavItem(this.icon, this.label, {this.tag, this.section});
}

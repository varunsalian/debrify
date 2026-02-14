import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'premium_nav_bar.dart' show NavItem; // reuse NavItem type

class PremiumTopNav extends StatefulWidget implements PreferredSizeWidget {
  final int currentIndex;
  final List<NavItem> items;
  final ValueChanged<int> onTap;
  final List<int>? badges;
  final bool haptics;
  final bool enableAutofocus;

  const PremiumTopNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.badges,
    this.haptics = true,
    this.enableAutofocus = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  State<PremiumTopNav> createState() => _PremiumTopNavState();
}

class _PremiumTopNavState extends State<PremiumTopNav> {
  late final ScrollController _scrollController;
  bool _showLeftHint = false;
  bool _showRightHint = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_handleScroll);
    _scheduleIndicatorUpdate();
  }

  @override
  void didUpdateWidget(covariant PremiumTopNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleIndicatorUpdate();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() => _evaluateIndicators();

  void _scheduleIndicatorUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _evaluateIndicators();
    });
  }

  void _evaluateIndicators() {
    if (!_scrollController.hasClients) {
      _updateHintVisibility(false, false);
      return;
    }

    final position = _scrollController.position;

    if (!position.hasPixels || !position.hasContentDimensions) {
      _updateHintVisibility(false, false);
      return;
    }

    final maxExtent = position.maxScrollExtent;
    if (maxExtent <= 1) {
      _updateHintVisibility(false, false);
      return;
    }

    final offset = position.pixels;
    final showLeft = offset > 2;
    final showRight = offset < (maxExtent - 2);
    _updateHintVisibility(showLeft, showRight);
  }

  void _updateHintVisibility(bool showLeft, bool showRight) {
    if (showLeft == _showLeftHint && showRight == _showRightHint) return;
    setState(() {
      _showLeftHint = showLeft;
      _showRightHint = showRight;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final badges = widget.badges;
    final haptics = widget.haptics;
    final onTap = widget.onTap;

    // Show all labels on larger screens (tablets, desktops)
    final screenWidth = MediaQuery.sizeOf(context).width;
    final showAllLabels = screenWidth >= 800;

    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: widget.preferredSize.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: FocusTraversalGroup(
                        policy: OrderedTraversalPolicy(),
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: Row(
                              children: [
                                for (int i = 0; i < items.length; i++) ...[
                                  _TopNavButton(
                                    key: ValueKey<String>('top-nav-${items[i].label}'),
                                    selected: i == widget.currentIndex,
                                    showLabel: showAllLabels || i == widget.currentIndex,
                                    compact: showAllLabels,
                                    icon: items[i].icon,
                                    label: items[i].label,
                                    tag: items[i].tag,
                                    badge: (badges != null && i < badges.length)
                                        ? badges[i]
                                        : null,
                                    autofocus: widget.enableAutofocus && widget.currentIndex == i,
                                    onPressed: () {
                                      if (haptics) HapticFeedback.selectionClick();
                                      onTap(i);
                                    },
                                  ),
                                  if (i != items.length - 1) const SizedBox(width: 6),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _ScrollHintOverlay(isLeft: true, visible: _showLeftHint),
                  _ScrollHintOverlay(isLeft: false, visible: _showRightHint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollHintOverlay extends StatelessWidget {
  final bool isLeft;
  final bool visible;

  const _ScrollHintOverlay({required this.isLeft, required this.visible});

  @override
  Widget build(BuildContext context) {
    final surfaceColor =
        Theme.of(context).appBarTheme.backgroundColor ??
        Theme.of(context).colorScheme.surface;

    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
                end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
                colors: [
                  surfaceColor.withValues(alpha: 0.94),
                  surfaceColor.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: Align(
              alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  isLeft
                      ? Icons.arrow_back_ios_new_rounded
                      : Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopNavButton extends StatefulWidget {
  final bool selected;
  final bool showLabel;
  final bool compact;
  final IconData icon;
  final String label;
  final String? tag;
  final int? badge;
  final VoidCallback onPressed;
  final bool autofocus;

  const _TopNavButton({
    super.key,
    required this.selected,
    required this.showLabel,
    this.compact = false,
    required this.icon,
    required this.label,
    this.tag,
    required this.onPressed,
    this.badge,
    this.autofocus = false,
  });

  @override
  State<_TopNavButton> createState() => _TopNavButtonState();
}

class _TopNavButtonState extends State<_TopNavButton> {
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'top-nav-${widget.label}')
      ..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TopNavButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.label != oldWidget.label) {
      _focusNode.debugLabel = 'top-nav-${widget.label}';
    }
    if (widget.autofocus && !_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() {
      _focused = _focusNode.hasFocus;
    });
    if (_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.4,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  static const Map<ShortcutActivator, Intent> _shortcutOverrides = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool selected = widget.selected;
    final bool highlighted = _focused || selected;
    final bool compact = widget.compact;

    // Compact sizes for when all labels are shown
    final double iconSize = compact ? 16 : 18;
    final double fontSize = compact ? 11 : 13;
    final double hPadding = compact ? 10 : 12;
    final double vPadding = compact ? 6 : 8;
    final double labelPadding = compact ? 6 : 8;

    return FocusableActionDetector(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onShowFocusHighlight: (visible) {
        if (_focused != visible) {
          setState(() => _focused = visible);
        }
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            widget.onPressed();
            return null;
          },
        ),
      },
      shortcuts: _shortcutOverrides,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.2)
                  : (_focused ? Colors.white.withValues(alpha: 0.08) : Colors.transparent),
              border: Border.all(
                color: selected
                    ? colorScheme.primary.withValues(alpha: 0.5)
                    : (_focused ? Colors.white.withValues(alpha: 0.2) : Colors.transparent),
                width: 1.5,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onPressed,
                borderRadius: BorderRadius.circular(10),
                canRequestFocus: false,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.icon,
                      size: iconSize,
                      color: selected
                          ? colorScheme.primary
                          : (highlighted ? Colors.white : Colors.white60),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeOut,
                      child: widget.showLabel
                          ? Padding(
                              key: const ValueKey('label'),
                              padding: EdgeInsets.only(left: labelPadding),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                      color: selected
                                          ? Colors.white
                                          : (highlighted ? Colors.white : Colors.white60),
                                      fontSize: fontSize,
                                    ),
                                  ),
                                  if (widget.tag != null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 0.5),
                                      ),
                                      child: Text(
                                        widget.tag!,
                                        style: TextStyle(
                                          fontSize: fontSize - 3,
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
                            )
                          : const SizedBox.shrink(key: ValueKey('empty')),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if ((widget.badge ?? 0) > 0)
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
                  widget.badge! > 99 ? '99+' : '${widget.badge}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'premium_nav_bar.dart' show NavItem; // reuse NavItem type

class PremiumTopNav extends StatefulWidget implements PreferredSizeWidget {
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

    return SizedBox(
      height: widget.preferredSize.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    for (int i = 0; i < items.length; i++) ...[
                      _TopNavButton(
                        selected: i == widget.currentIndex,
                        icon: items[i].icon,
                        label: items[i].label,
                        badge: (badges != null && i < badges.length)
                            ? badges[i]
                            : null,
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
            ),
          ),
          _ScrollHintOverlay(isLeft: true, visible: _showLeftHint),
          _ScrollHintOverlay(isLeft: false, visible: _showRightHint),
        ],
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
                  surfaceColor.withOpacity(0.94),
                  surfaceColor.withOpacity(0.0),
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
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: selected
                  ? Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.35),
                    )
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? colorScheme.primary : Colors.white70,
                ),
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
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

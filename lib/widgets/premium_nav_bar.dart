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
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (int i = 0; i < items.length; i++)
                      _PremiumNavButton(
                        key: ValueKey<String>('bottom-nav-${items[i].label}'),
                        selected: i == currentIndex,
                        icon: items[i].icon,
                        label: items[i].label,
                        badge: (badges != null && i < badges!.length) ? badges![i] : null,
                        autofocus: i == currentIndex,
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
      ),
    );
  }
}

class _PremiumNavButton extends StatefulWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final int? badge;
  final VoidCallback onPressed;
  final bool autofocus;

  const _PremiumNavButton({
    super.key,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badge,
    this.autofocus = false,
  });

  @override
  State<_PremiumNavButton> createState() => _PremiumNavButtonState();
}

class _PremiumNavButtonState extends State<_PremiumNavButton> {
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'bottom-nav-${widget.label}')
      ..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _PremiumNavButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.label != oldWidget.label) {
      _focusNode.debugLabel = 'bottom-nav-${widget.label}';
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
    final bool showFocusBorder = _focused || selected;

    final backgroundColor = selected
        ? colorScheme.primary.withValues(alpha: 0.18)
        : (_focused
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.transparent);

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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: backgroundColor,
              border: showFocusBorder
                  ? Border.all(
                      color: selected
                          ? colorScheme.primary
                          : Colors.white.withValues(alpha: 0.65),
                      width: selected ? 2 : 1.6,
                    )
                  : Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: showFocusBorder
                  ? [
                      BoxShadow(
                        color: (selected
                                ? colorScheme.primary
                                : Colors.white)
                            .withValues(alpha: 0.24),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onPressed,
                borderRadius: BorderRadius.circular(12),
                canRequestFocus: false,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.icon,
                      color: selected
                          ? colorScheme.primary
                          : Colors.white70,
                      size: 20,
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: selected
                          ? Padding(
                              key: const ValueKey('label'),
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                widget.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
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
              right: -2,
              top: -2,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.tertiary,
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: Colors.black.withValues(alpha: 0.2)),
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

class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

List<NavItem> buildDefaultNavItems(List<IconData> icons, List<String> labels) {
  assert(icons.length == labels.length);
  return [for (int i = 0; i < icons.length; i++) NavItem(icons[i], labels[i])];
} 

import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Prime-style quick actions: a wrapped grid of uniform icon buttons with a
/// caption underneath. Everything is visible at once — no hidden scroll — so
/// users always see every action. Items are a fixed width so rows align.
class _QuickActions extends StatelessWidget {
  final List<TraktMenuOption> options;
  final bool tv;

  /// Phone (narrow layout): lay out as an even 3-column grid so narrow
  /// widths don't drop to an ugly 2-up. Wide/TV keeps the free wrap.
  final bool phone;
  final void Function(TraktItemMenuAction) onSelected;

  const _QuickActions({
    required this.options,
    required this.tv,
    required this.phone,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'QUICK ACTIONS',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
          ),
        ),
        const SizedBox(height: 16),
        if (phone) _grid() else _wrap(),
      ],
    );
  }

  Widget _wrap() => Wrap(
    spacing: 8,
    runSpacing: 18,
    children: [
      for (final o in options)
        _QuickAction(option: o, tv: tv, onTap: () => onSelected(o.action)),
    ],
  );

  Widget _grid() {
    const cols = 3;
    const gap = 8.0;
    final rows = <Widget>[];
    for (var i = 0; i < options.length; i += cols) {
      final cells = <Widget>[];
      for (var j = 0; j < cols; j++) {
        if (j > 0) cells.add(const SizedBox(width: gap));
        final idx = i + j;
        cells.add(
          Expanded(
            child: idx < options.length
                ? _QuickAction(
                    option: options[idx],
                    tv: tv,
                    expand: true,
                    onTap: () => onSelected(options[idx].action),
                  )
                : const SizedBox.shrink(),
          ),
        );
      }
      if (i > 0) rows.add(const SizedBox(height: 18));
      rows.add(
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}

class _QuickAction extends StatefulWidget {
  final TraktMenuOption option;
  final bool tv;

  /// Grid mode: fill the parent cell instead of a fixed 80px box.
  final bool expand;
  final VoidCallback onTap;

  const _QuickAction({
    required this.option,
    required this.tv,
    required this.onTap,
    this.expand = false,
  });

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _focused = false;
  bool _hovered = false;
  bool get _active => _focused || _hovered;

  @override
  Widget build(BuildContext context) {
    final o = widget.option;
    final t = DetailThemeScope.maybeOf(context);

    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (isActivateKey(event.logicalKey) ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            duration: widget.tv
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            scale: _active ? 1.06 : 1.0,
            child: SizedBox(
              width: widget.expand ? null : 80,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      AnimatedContainer(
                        duration: widget.tv
                            ? Duration.zero
                            : const Duration(milliseconds: 150),
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(
                            alpha: _active ? 0.16 : 0.07,
                          ),
                          border: Border.all(
                            color: _active
                                ? t.focus
                                : Colors.white.withValues(alpha: 0.12),
                            width: _active ? 1.6 : 1,
                          ),
                          boxShadow: _active
                              ? [
                                  BoxShadow(
                                    color: t.fade(t.focus, 0.32),
                                    blurRadius: 18,
                                    spreadRadius: 0.5,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          o.icon,
                          size: 24,
                          color: Colors.white.withValues(
                            alpha: _active ? 1.0 : 0.92,
                          ),
                        ),
                      ),
                      if (o.isTrakt)
                        Positioned(
                          top: -4,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFED1C24),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: const Color(0xFF050507),
                                width: 1.5,
                              ),
                            ),
                            child: const Text(
                              'TRAKT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 7,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    o.caption,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(
                        alpha: _active ? 1.0 : 0.62,
                      ),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef CatalogQuickActions = _QuickActions;

const catalogQuickActionsConstructor = _QuickActions.new;

typedef CatalogQuickAction = _QuickAction;

const catalogQuickActionConstructor = _QuickAction.new;

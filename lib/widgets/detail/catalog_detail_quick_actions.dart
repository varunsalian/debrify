/// The tracker quick-action sections on `CatalogItemDetailScreen` — Trakt's
/// icon grid, MDBList's chips and Simkl's parallel grid.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/mdblist/mdblist_menu_helpers.dart';
import '../../services/simkl/simkl_menu_helpers.dart';
import '../../utils/tv_keys.dart';
import '../trakt/trakt_menu_helpers.dart';
import 'theme/detail_theme.dart';

// ── Quick actions row ───────────────────────────────────────────────────────

/// Prime-style quick actions: a wrapped grid of uniform icon buttons with a
/// caption underneath. Everything is visible at once — no hidden scroll — so
/// users always see every action. Items are a fixed width so rows align.
class CatalogDetailQuickActions extends StatelessWidget {
  final List<TraktMenuOption> options;
  final bool tv;

  /// Phone (narrow layout): lay out as an even 3-column grid so narrow
  /// widths don't drop to an ugly 2-up. Wide/TV keeps the free wrap.
  final bool phone;
  final void Function(TraktItemMenuAction) onSelected;

  const CatalogDetailQuickActions({
    super.key,
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
        CatalogDetailQuickAction(
          option: o,
          tv: tv,
          onTap: () => onSelected(o.action),
        ),
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
                ? CatalogDetailQuickAction(
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

class CatalogDetailQuickAction extends StatefulWidget {
  final TraktMenuOption option;
  final bool tv;

  /// Grid mode: fill the parent cell instead of a fixed 80px box.
  final bool expand;
  final VoidCallback onTap;

  const CatalogDetailQuickAction({
    super.key,
    required this.option,
    required this.tv,
    required this.onTap,
    this.expand = false,
  });

  @override
  State<CatalogDetailQuickAction> createState() =>
      _CatalogDetailQuickActionState();
}

class _CatalogDetailQuickActionState extends State<CatalogDetailQuickAction> {
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

class CatalogDetailMdblistQuickActions extends StatelessWidget {
  const CatalogDetailMdblistQuickActions({
    super.key,
    required this.options,
    required this.onSelected,
  });
  final List<MdblistMenuOption> options;
  final void Function(MdblistItemMenuAction) onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'MDBLIST ACTIONS',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 2.2,
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in options)
            ActionChip(
              avatar: Icon(option.icon, size: 18, color: option.color),
              label: Text(option.caption),
              tooltip: option.label,
              onPressed: () => onSelected(option.action),
            ),
        ],
      ),
    ],
  );
}

/// Simkl's quick-actions section — duplicated from [CatalogDetailQuickActions] rather
/// than genericized, since sharing a widget across [TraktMenuOption] and
/// [SimklMenuOption] would mean a shared type between the two trackers,
/// which the rest of this integration deliberately avoids.
class CatalogDetailSimklQuickActions extends StatelessWidget {
  final List<SimklMenuOption> options;
  final bool tv;
  final bool phone;
  final void Function(SimklItemMenuAction) onSelected;

  const CatalogDetailSimklQuickActions({
    super.key,
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
          'SIMKL ACTIONS',
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
        CatalogDetailSimklQuickAction(
          option: o,
          tv: tv,
          onTap: () => onSelected(o.action),
        ),
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
                ? CatalogDetailSimklQuickAction(
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

class CatalogDetailSimklQuickAction extends StatefulWidget {
  final SimklMenuOption option;
  final bool tv;
  final bool expand;
  final VoidCallback onTap;

  const CatalogDetailSimklQuickAction({
    super.key,
    required this.option,
    required this.tv,
    required this.onTap,
    this.expand = false,
  });

  @override
  State<CatalogDetailSimklQuickAction> createState() =>
      _CatalogDetailSimklQuickActionState();
}

class _CatalogDetailSimklQuickActionState
    extends State<CatalogDetailSimklQuickAction> {
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
                      Positioned(
                        top: -4,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22D3EE),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: const Color(0xFF050507),
                              width: 1.5,
                            ),
                          ),
                          child: const Text(
                            'SIMKL',
                            style: TextStyle(
                              color: Colors.black,
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

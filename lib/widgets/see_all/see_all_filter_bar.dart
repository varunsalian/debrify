import 'package:flutter/material.dart';

import '../../theme/app_theme_scope.dart';

/// Lays out a See-All screen's filter dropdowns responsively.
///
/// On a wide canvas (and always on TV) it's the familiar wrap of dropdown chips.
/// On a narrow, non-TV canvas — where those chips wrap into several stacked rows
/// and shove the poster grid off-screen — the screen's own filters collapse into
/// a single "Filters" button that opens them in a bottom sheet. Any [leading]
/// control (the Discover Source selector) stays inline, since changing it swaps
/// the whole panel and shouldn't be buried in a sheet.
///
/// [quiet] opts out of that entirely: the whisper line is already the compact
/// form, so it renders inline at every width.
class SeeAllFilterBar extends StatefulWidget {
  final bool isTelevision;

  /// Always-visible leading control (the Discover Source dropdown), or null on
  /// the standalone See-All pages.
  final Widget? leading;

  /// Always-visible trailing control (the Discover Random button), or null.
  /// Like [leading] it stays inline when the chips collapse into the sheet —
  /// it's an action, not a filter, so it must not be buried there.
  final Widget? trailing;

  /// Builds the screen's own filter chips fresh on each call, so the open sheet
  /// reflects live filter changes (see [didUpdateWidget]).
  final List<Widget> Function() buildChips;

  /// Number of filters set to a non-default value, shown as a badge on the
  /// collapsed button. 0 hides the badge.
  final int activeCount;

  /// Quiet styling (Discover TV, and the IPTV two-pane guide column): the
  /// equal-width column row of boxed pills becomes a single left-packed line of
  /// bare text segments separated by dots, sitting directly on the glass stage.
  /// The chips themselves must be built quiet too (StremioDropdown.quiet).
  /// A quiet bar never collapses into the Filters button — see [build].
  final bool quiet;

  const SeeAllFilterBar({
    super.key,
    required this.isTelevision,
    required this.buildChips,
    this.leading,
    this.trailing,
    this.activeCount = 0,
    this.quiet = false,
  });

  @override
  State<SeeAllFilterBar> createState() => _SeeAllFilterBarState();
}

class _SeeAllFilterBarState extends State<SeeAllFilterBar> {
  /// Below this width the screen's filters collapse into the Filters button —
  /// roughly where the chip wrap would spill past two rows.
  static const double _narrowMax = 640;

  StateSetter? _sheetSetState;

  /// A context *inside* the open sheet route, used to dismiss it from outside
  /// (on a wide flip or on dispose). Non-null exactly while the sheet is open.
  BuildContext? _sheetContext;

  @override
  void didUpdateWidget(SeeAllFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A filter changed upstream (the parent screen rebuilt) — refresh the open
    // sheet so its chips show the new values. Deferred a frame: didUpdateWidget
    // runs during the parent's build, and the sheet lives in a separate route,
    // so poking its setState synchronously would be a "setState during build".
    if (_sheetSetState != null && (_sheetContext?.mounted ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sheetSetState != null && (_sheetContext?.mounted ?? false)) {
          _sheetSetState!(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    // The sheet route lives on the Navigator, not under this widget, so it
    // outlives us if the screen is torn down while it's open (e.g. the Discover
    // panel swaps sources). Dismiss it next frame so its chips can't fire
    // setState on the now-disposed screen. The closure captures the sheet's
    // context, not `this`.
    final ctx = _sheetContext;
    _sheetContext = null;
    _sheetSetState = null;
    if (ctx != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _popRoute(ctx));
    }
    super.dispose();
  }

  /// Pop the sheet [ctx] belongs to, but only if it's still the current route
  /// (don't clobber a menu opened on top of it, or an already-gone route).
  static void _popRoute(BuildContext ctx) {
    if (!ctx.mounted) return;
    final route = ModalRoute.of(ctx);
    if (route != null && route.isCurrent) Navigator.of(ctx).pop();
  }

  Future<void> _openSheet() async {
    final app = AppThemeScope.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: app.seeAll.panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (innerContext, setSheetState) {
            _sheetContext = innerContext;
            _sheetSetState = setSheetState;
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune_rounded,
                            size: 18, color: app.core.tx.withValues(alpha: 0xB3 / 0xFF)),
                        const SizedBox(width: 8),
                        const Text(
                          'Filters',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(innerContext).pop(),
                          icon: Icon(Icons.close_rounded,
                              color: app.core.tx.withValues(alpha: 0x8A / 0xFF)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: widget.buildChips(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    _sheetContext = null;
    _sheetSetState = null;
  }

  List<Widget> _items() => <Widget>[
    if (widget.leading != null) widget.leading!,
    ...widget.buildChips(),
    if (widget.trailing != null) widget.trailing!,
  ];

  @override
  Widget build(BuildContext context) {
    // Quiet: a left-packed text line, dot-separated — the grid owns the
    // canvas, the filters whisper above it. A single row of intrinsic units,
    // NOT a flex Row: Flexible caps every segment at an equal share even when
    // siblings leave slack, truncating "Continue Watching" beside a roomy
    // "All". Every value renders in full and the bar NEVER wraps — a rare
    // too-wide combo scrolls horizontally instead (on TV each segment pulls
    // itself into view on DPAD focus), so the filters can't fold onto a second
    // line and push the grid down.
    //
    // Checked before [isTelevision] because the line is already the compact
    // form: collapsing it into a Filters button costs a click to read what is
    // in plain sight, and off TV that only ever happened in a two-pane whose
    // guide column sits below _narrowMax while the window itself is wide. The
    // phone's IPTV filter bar stays inline at any width; this matches it.
    if (widget.quiet) {
      final app = AppThemeScope.of(context);
      final items = _items();
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Container(
                  width: 3,
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: app.fade(app.core.tx, 0.25),
                    shape: BoxShape.circle,
                  ),
                ),
              items[i],
            ],
          ],
        ),
      );
    }
    // TV: one row, equal-width columns (leading + each chip share the width
    // evenly). The dropdowns fill their column and pin the chevron right (see
    // StremioDropdown), so it reads as a deliberate bar instead of a ragged
    // 2-row wrap. No collapse on TV — sheets are a pointer-only affordance.
    if (widget.isTelevision) {
      final items = _items();
      return Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: items[i]),
          ],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            !widget.isTelevision && constraints.maxWidth < _narrowMax;
        // Keep the chips collapsed into the button while the sheet is open, even
        // if the canvas just went wide — rendering them inline now, while the
        // sheet still holds the same chips, would attach the screen's shared
        // FocusNodes to two live Focus widgets (a duplicate-FocusNode assertion).
        // So on a wide flip we dismiss the sheet and stay collapsed until it
        // fully drains (then _sheetContext clears and the inline chips return).
        final collapsed = narrow || _sheetContext != null;
        if (!narrow && _sheetContext != null) {
          final ctx = _sheetContext!;
          WidgetsBinding.instance.addPostFrameCallback((_) => _popRoute(ctx));
        }
        return Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.leading != null) widget.leading!,
            if (collapsed)
              _FiltersButton(count: widget.activeCount, onTap: _openSheet)
            else
              ...widget.buildChips(),
            if (widget.trailing != null) widget.trailing!,
          ],
        );
      },
    );
  }
}

/// The collapsed "Filters (n)" chip, styled to match [StremioDropdown].
class _FiltersButton extends StatefulWidget {
  final int count;
  final VoidCallback onTap;

  const _FiltersButton({required this.count, required this.onTap});

  @override
  State<_FiltersButton> createState() => _FiltersButtonState();
}

class _FiltersButtonState extends State<_FiltersButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          decoration: BoxDecoration(
            color: app.seeAll.panel,
            borderRadius: app.shape.br(11),
            border: Border.all(
              color: _hovered ? app.seeAll.accentBorder : app.seeAll.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_rounded, size: 16, color: app.core.tx.withValues(alpha: 0xB3 / 0xFF)),
              const SizedBox(width: 8),
              const Text(
                'Filters',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (widget.count > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: app.seeAll.accent,
                    borderRadius: app.shape.br(9),
                  ),
                  child: Text(
                    '${widget.count}',
                    // Ink chosen against the fill actually painted: this badge
                    // is a SOLID accent swatch, and half the themes' accents
                    // are light (Noir/Frost are literally #FFFFFF), where a
                    // hardcoded white count is invisible. Legacy's violet keeps
                    // white — it scores 4.36, above inkOn's threshold — so the
                    // shipped look is unchanged.
                    style: TextStyle(
                      color: app.inkOn(app.seeAll.accent),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

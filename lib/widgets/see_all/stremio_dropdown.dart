import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/tv_keys.dart';
import 'see_all_theme.dart';

/// One selectable option in a [StremioDropdown].
class StremioDropdownOption<T> {
  final T value;
  final String label;
  const StremioDropdownOption(this.value, this.label);
}

/// A dark-glass, Stremio-styled pill dropdown used for the See-All filter bars
/// (Type / Catalog / Genre / Category). Built on [showMenu] rather than
/// [PopupMenuButton] so it can carry its own [focusNode] and paint a DPAD focus
/// ring, and so a SELECT keypress opens the menu on TV.
///
/// [T] must be non-nullable: a null result from the menu means "dismissed", so
/// callers represent an "All" option with a sentinel value (e.g. the empty
/// string) rather than null.
class StremioDropdown<T extends Object> extends StatefulWidget {
  final String? label;
  final T value;
  final List<StremioDropdownOption<T>> options;
  final ValueChanged<T> onSelected;
  final bool isTelevision;
  final FocusNode? focusNode;

  /// TV navigation: called when DPAD-up is pressed on the pill (e.g. to return
  /// focus to a search field above the filter row). Null on screens that don't
  /// need it (the Discover filter bar).
  final VoidCallback? onUpArrowPressed;

  /// TV navigation: called when DPAD-down is pressed on the pill (e.g. to drop
  /// focus into the results list below). Null = default directional traversal.
  final VoidCallback? onDownArrowPressed;

  /// Quiet styling (Discover TV): the boxed glass pill becomes a bare
  /// value + chevron text segment on the stage — no panel, no border box. The
  /// DPAD focus state is a soft violet pill (constant-size decoration, so focus
  /// never reflows the row). The popup menu is unchanged.
  final bool quiet;

  /// Quiet mode only: render the value in the violet accent — marks the leading
  /// Source segment as the row's identity, per the Discover design.
  final bool quietAccent;

  const StremioDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    this.label,
    this.isTelevision = false,
    this.focusNode,
    this.onUpArrowPressed,
    this.onDownArrowPressed,
    this.quiet = false,
    this.quietAccent = false,
  });

  @override
  State<StremioDropdown<T>> createState() => _StremioDropdownState<T>();
}

class _StremioDropdownState<T extends Object> extends State<StremioDropdown<T>> {
  final GlobalKey _btnKey = GlobalKey();
  bool _focused = false;
  bool _hovered = false;

  String get _valueLabel {
    for (final o in widget.options) {
      if (o.value == widget.value) return o.label;
    }
    return widget.options.isNotEmpty ? widget.options.first.label : '';
  }

  /// Above this many options the showMenu popup is swapped for a lazy picker
  /// dialog. showMenu builds and lays out EVERY item synchronously — a visible
  /// freeze for a several-hundred-entry IPTV category list — and DPAD-stepping
  /// a popup that long is hopeless anyway. The dialog builds rows lazily,
  /// opens scrolled to the current value, and (off-TV) adds a filter field.
  static const int _lazyPickerThreshold = 30;

  Future<void> _open() async {
    if (widget.options.length > _lazyPickerThreshold) {
      final result = await showDialog<T>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.62),
        builder: (_) => _LazyPickerDialog<T>(
          title: widget.label ?? 'Select',
          options: widget.options,
          value: widget.value,
          isTelevision: widget.isTelevision,
        ),
      );
      if (result != null) widget.onSelected(result);
      return;
    }
    final btn = _btnKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (btn == null || overlay == null) return;
    final topLeft = btn.localToGlobal(Offset(0, btn.size.height + 6),
        ancestor: overlay);
    final bottomRight =
        btn.localToGlobal(btn.size.bottomRight(Offset.zero), ancestor: overlay);
    final pos = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );

    final result = await showMenu<T>(
      context: context,
      position: pos,
      color: kSeeAllPanel2,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: kSeeAllLine),
      ),
      constraints: const BoxConstraints(minWidth: 190, maxWidth: 320),
      items: [
        for (final o in widget.options)
          PopupMenuItem<T>(
            value: o.value,
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    o.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: o.value == widget.value
                          ? kSeeAllAccent2
                          : Colors.white,
                      fontSize: 13.5,
                      fontWeight: o.value == widget.value
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                ),
                if (o.value == widget.value)
                  const Icon(Icons.check_rounded,
                      size: 16, color: kSeeAllAccent2),
              ],
            ),
          ),
      ],
    );
    if (result != null) widget.onSelected(result);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (isActivateKey(event.logicalKey) ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _open();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        widget.onUpArrowPressed != null) {
      widget.onUpArrowPressed!();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        widget.onDownArrowPressed != null) {
      widget.onDownArrowPressed!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hovered;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        // Quiet segments live on a single never-wrapping line that scrolls
        // horizontally when too wide — keep the focused one in view (no-op
        // while the line fits, or outside any scrollable).
        if (f && widget.quiet) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
        }
      },
      onKeyEvent: _onKey,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _open,
          behavior: HitTestBehavior.opaque,
          // When a parent hands a TIGHT width (an equal-width filter column —
          // see SeeAllFilterBar's TV single row), fill it and pin the chevron to
          // the right edge, ellipsizing the value. Otherwise stay intrinsic (the
          // Wrap/Row usages everywhere else are unaffected — they pass loose or
          // unbounded width, so `hasTightWidth` is false).
          child: widget.quiet
              ? _buildQuiet(active)
              : LayoutBuilder(
            builder: (context, constraints) {
              final stretch = constraints.hasTightWidth;
              final valueText = Text(
                _valueLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              );
              return Container(
                key: _btnKey,
                padding: const EdgeInsets.fromLTRB(14, 9, 11, 9),
                decoration: BoxDecoration(
                  color: kSeeAllPanel,
                  borderRadius: BorderRadius.circular(11),
                  // Constant width: Container feeds the border's thickness into
                  // its layout padding, so a 1→2px focus ring RESIZES the pill
                  // and reflows the whole filter row (reads as the screen shaking
                  // on DPAD moves). Only the color may change on focus.
                  border: Border.all(
                    width: 2,
                    color: _focused
                        ? kSeeAllAccent
                        : (active ? kSeeAllAccentBorder : kSeeAllLine),
                  ),
                ),
                child: Row(
                  mainAxisSize:
                      stretch ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    if (widget.label != null) ...[
                      Text(
                        widget.label!.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (stretch)
                      Expanded(child: valueText)
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: valueText,
                      ),
                    const SizedBox(width: 8),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: Colors.white.withValues(alpha: 0.5)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// The quiet segment: value text + a small chevron sitting directly on the
  /// stage. Distinctive values (a source, catalog or type name) stand alone;
  /// generic ones ("All" / "Default") are rewritten to self-describe — "All
  /// types", "Any state" — so two Alls in one line stay tellable apart without
  /// small-caps label prefixes eating the row's width.
  String get _quietDisplay {
    final label = widget.label?.toLowerCase();
    if (_valueLabel == 'All') {
      switch (label) {
        case 'show':
        case 'type':
          return 'All types';
        case 'state':
          return 'Any state';
        case 'genre':
          return 'All genres';
        case 'category':
          return 'All categories';
      }
      return 'All';
    }
    if (_valueLabel == 'Default' && label == 'sort') return 'Default order';
    return _valueLabel;
  }

  Widget _buildQuiet(bool active) {
    return Container(
      key: _btnKey,
      padding: const EdgeInsets.fromLTRB(9, 6, 6, 6),
      decoration: BoxDecoration(
        color: _focused
            ? kSeeAllAccent.withValues(alpha: 0.30)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        // Constant thickness — only the color changes on focus, so the row
        // never reflows on DPAD moves (same rule as the boxed pill).
        border: Border.all(
          width: 1.2,
          color: _focused
              ? kSeeAllAccent2.withValues(alpha: 0.45)
              : (active ? kSeeAllAccentBorder : Colors.transparent),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hard cap (the quiet row is a Wrap of intrinsic units, so this is
          // the only guard against a pathologically long addon/list name).
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              _quietDisplay,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _focused
                    ? Colors.white
                    : widget.quietAccent
                        ? kSeeAllAccent2
                        : Colors.white.withValues(alpha: 0.78),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 3),
          Icon(Icons.keyboard_arrow_down_rounded,
              size: 15, color: Colors.white.withValues(alpha: 0.45)),
        ],
      ),
    );
  }
}

/// Lazy replacement for [showMenu] on huge option lists (see
/// [_StremioDropdownState._lazyPickerThreshold]): a fixed-extent
/// [ListView.builder] so only visible rows exist, opened scrolled to the
/// current value. DPAD rides stock vertical traversal between the lazily-built
/// rows (each keeps itself in view on focus); off-TV a filter field narrows
/// the list. Pops with the chosen value, or null on dismiss.
class _LazyPickerDialog<T extends Object> extends StatefulWidget {
  final String title;
  final List<StremioDropdownOption<T>> options;
  final T value;
  final bool isTelevision;

  const _LazyPickerDialog({
    required this.title,
    required this.options,
    required this.value,
    required this.isTelevision,
  });

  @override
  State<_LazyPickerDialog<T>> createState() => _LazyPickerDialogState<T>();
}

class _LazyPickerDialogState<T extends Object>
    extends State<_LazyPickerDialog<T>> {
  static const double _rowH = 44;

  late final ScrollController _scroll;
  late List<StremioDropdownOption<T>> _shown;
  late final int _initialIndex;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _shown = widget.options;
    final idx = widget.options.indexWhere((o) => o.value == widget.value);
    _initialIndex = idx < 0 ? 0 : idx;
    // Open with the current value near the top of the viewport (a few rows of
    // context above it). Overshoot is clamped by the scroll position on the
    // first layout.
    _scroll = ScrollController(
      initialScrollOffset: ((_initialIndex - 3).clamp(0, _initialIndex)) * _rowH,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onFilterChanged(String v) {
    final f = v.trim().toLowerCase();
    setState(() {
      _filter = f;
      _shown = f.isEmpty
          ? widget.options
          : [
              for (final o in widget.options)
                if (o.label.toLowerCase().contains(f)) o,
            ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxH =
        (MediaQuery.of(context).size.height * 0.72).clamp(260.0, 560.0);
    return Dialog(
      backgroundColor: kSeeAllPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kSeeAllLine),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 340, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: Row(
                children: [
                  Text(
                    widget.title.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_shown.length}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            // TV skips the filter field: it would drag the soft keyboard over
            // the dialog, and holding DPAD through the lazy list is fast.
            if (!widget.isTelevision)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: TextField(
                  autofocus: true,
                  onChanged: _onFilterChanged,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Filter…',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 13.5,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 18, color: Colors.white38),
                    filled: true,
                    fillColor: kSeeAllPanel2,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: kSeeAllLine),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: kSeeAllLine),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kSeeAllAccent),
                    ),
                  ),
                ),
              ),
            Flexible(
              child: ListView.builder(
                controller: _scroll,
                itemExtent: _rowH,
                itemCount: _shown.length,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                itemBuilder: (context, i) {
                  final o = _shown[i];
                  return _LazyPickerRow(
                    label: o.label,
                    selected: o.value == widget.value,
                    // Land DPAD focus on the current value when the dialog
                    // opens (its row is built — we scrolled to it). Filtering
                    // reshuffles indices, so only the pristine list anchors.
                    autofocus: widget.isTelevision &&
                        _filter.isEmpty &&
                        i == _initialIndex,
                    onPick: () => Navigator.of(context).pop(o.value),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LazyPickerRow extends StatefulWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onPick;

  const _LazyPickerRow({
    required this.label,
    required this.selected,
    required this.autofocus,
    required this.onPick,
  });

  @override
  State<_LazyPickerRow> createState() => _LazyPickerRowState();
}

class _LazyPickerRowState extends State<_LazyPickerRow> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          // Keep the focused row centered as DPAD walks the lazy viewport
          // (same recenter-on-focus grammar as the channel rows).
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space) {
          widget.onPick();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPick,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _focused
                  ? kSeeAllAccent.withValues(alpha: 0.26)
                  : _hovered
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.selected ? kSeeAllAccent2 : Colors.white,
                      fontSize: 13.5,
                      fontWeight:
                          widget.selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (widget.selected)
                  const Icon(Icons.check_rounded,
                      size: 16, color: kSeeAllAccent2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

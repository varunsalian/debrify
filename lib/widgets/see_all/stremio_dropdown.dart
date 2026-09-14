import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme_scope.dart';
import '../../utils/tv_keys.dart';
import '../tv_text_field.dart';

/// One row in a [StremioDropdown] — a selectable option, or a section header
/// when [isHeader] is set.
///
/// A header is never selectable, never matched against the dropdown's value,
/// and never counted as the fallback label; its [value] exists only because
/// the list is typed, so callers pass any unused sentinel.
class StremioDropdownOption<T> {
  final T value;
  final String label;
  final bool isHeader;

  /// Whether HOLDING OK (TV) or long-pressing this row runs the dropdown's
  /// [StremioDropdown.onOptionHold] instead of selecting it. Opt-in per
  /// option so a list can offer the gesture on its real entries without
  /// offering it on an "All"/sentinel row.
  final bool holdable;

  const StremioDropdownOption(
    this.value,
    this.label, {
    this.isHeader = false,
    this.holdable = false,
  });

  /// Section header. Give it a sentinel [value] no real option uses.
  const StremioDropdownOption.header(this.value, this.label)
    : isHeader = true,
      holdable = false;
}

/// Section label inside a dropdown list: an accent tick and an upper-case
/// caption.
///
/// Sized against the OPTIONS it labels rather than as fine print. A caption
/// lighter than its own group reads as an artifact floating between two rows;
/// this one is smaller than an option but heavier, which is what makes it
/// scan as a heading instead of a disabled entry.
class StremioDropdownSectionHeader extends StatelessWidget {
  final String label;
  const StremioDropdownSectionHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: app.fade(app.seeAll.accent2, 0.75),
            borderRadius: app.shape.br(2),
          ),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: app.fade(app.core.tx, 0.62),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }
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

  /// Secondary action for options marked [StremioDropdownOption.holdable]:
  /// fired when such a row is HELD (TV) or long-pressed (touch/desktop)
  /// instead of picked. The picker closes first, so a confirmation the
  /// callback opens lands over the page rather than over the option list.
  final ValueChanged<T>? onOptionHold;

  /// One-line hint drawn on a focused holdable row, e.g. "HOLD OK to hide" —
  /// the gesture is invisible otherwise.
  final String? holdHint;

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
    this.onOptionHold,
    this.holdHint,
  });

  @override
  State<StremioDropdown<T>> createState() => _StremioDropdownState<T>();
}

class _StremioDropdownState<T extends Object>
    extends State<StremioDropdown<T>> {
  final GlobalKey _btnKey = GlobalKey();
  bool _focused = false;
  bool _hovered = false;

  String get _valueLabel {
    for (final o in widget.options) {
      if (!o.isHeader && o.value == widget.value) return o.label;
    }
    // Headers are skipped in the fallback too, or a dropdown whose value has
    // gone missing would render a section title as its current selection.
    for (final o in widget.options) {
      if (!o.isHeader) return o.label;
    }
    return '';
  }

  /// Above this many options the showMenu popup is swapped for a lazy picker
  /// dialog. showMenu builds and lays out EVERY item synchronously — a visible
  /// freeze for a several-hundred-entry IPTV category list — and DPAD-stepping
  /// a popup that long is hopeless anyway. The dialog builds rows lazily,
  /// opens scrolled to the current value, and (off-TV) adds a filter field.
  static const int _lazyPickerThreshold = 30;

  /// A hold gesture forces the lazy picker regardless of length: the showMenu
  /// path's items own their own tap and key handling, so there is nowhere to
  /// hang a hold on them, and an option that offers the gesture in a long list
  /// but silently drops it in a short one is worse than not offering it.
  bool get _offersHold =>
      widget.onOptionHold != null && widget.options.any((o) => o.holdable);

  Future<void> _open() async {
    if (widget.options.length > _lazyPickerThreshold || _offersHold) {
      final result = await showDialog<_PickerChoice<T>>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.62),
        builder: (_) => _LazyPickerDialog<T>(
          title: widget.label ?? 'Select',
          options: widget.options,
          value: widget.value,
          isTelevision: widget.isTelevision,
          offersHold: _offersHold,
          holdHint: widget.holdHint,
        ),
      );
      if (result == null) return;
      if (result.held) {
        widget.onOptionHold?.call(result.value);
      } else {
        widget.onSelected(result.value);
      }
      return;
    }
    final btn = _btnKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (btn == null || overlay == null) return;
    final topLeft = btn.localToGlobal(
      Offset(0, btn.size.height + 6),
      ancestor: overlay,
    );
    final bottomRight = btn.localToGlobal(
      btn.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final pos = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );

    // Resolved once per open rather than per item: the items loop below would
    // otherwise rescan the whole option list for every row it builds.
    final hasSections = widget.options.any((o) => o.isHeader);
    final app = AppThemeScope.of(context);
    final result = await showMenu<T>(
      context: context,
      position: pos,
      color: app.seeAll.panel2,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: app.shape.br(14),
        side: BorderSide(color: app.seeAll.line),
      ),
      constraints: const BoxConstraints(minWidth: 190, maxWidth: 320),
      // Sectioned menus indent their options so each group reads as belonging
      // to the caption above it. Flat menus pass null and keep whatever
      // PopupMenuItem's own default is — hard-coding a number here silently
      // shifted every header-less dropdown in the app, because the Material 3
      // default is 12, not the 16 the Material 2 default used to be.
      items: [
        for (final (index, o) in widget.options.indexed)
          if (o.isHeader)
            // enabled:false keeps it out of the tap AND keyboard-traversal
            // paths, so DPAD steps between real options as if it weren't
            // there.
            PopupMenuItem<T>(
              enabled: false,
              height: 38,
              // Two pieces of geometry carry the hierarchy. The tick hangs in
              // the gutter so the caption itself starts LEFT of the options,
              // which indent beneath it. And the spare height sits above the
              // caption, not around it — air on both sides would make the
              // header look like it belongs to neither group. The first
              // header skips that gap; nothing precedes it to separate from.
              padding: EdgeInsets.only(
                left: 6,
                right: 16,
                top: index == 0 ? 0 : 12,
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: StremioDropdownSectionHeader(label: o.label),
              ),
            )
          else
            PopupMenuItem<T>(
              value: o.value,
              height: 44,
              padding: hasSections
                  ? const EdgeInsets.only(left: 32, right: 16)
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      o.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: o.value == widget.value
                            ? app.seeAll.accent2
                            : Theme.of(context).colorScheme.onSurface,
                        fontSize: 13.5,
                        fontWeight: o.value == widget.value
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (o.value == widget.value)
                    Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: app.seeAll.accent2,
                    ),
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
    final app = AppThemeScope.of(context);
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
          // Wrap/Row usages use loose sizing, with the value allowed to shrink
          // when a narrow sheet cannot fit the label and full value).
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
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                    return Container(
                      key: _btnKey,
                      padding: const EdgeInsets.fromLTRB(14, 9, 11, 9),
                      decoration: BoxDecoration(
                        color: app.seeAll.panel,
                        borderRadius: app.shape.br(11),
                        // Constant width: Container feeds the border's thickness into
                        // its layout padding, so a 1→2px focus ring RESIZES the pill
                        // and reflows the whole filter row (reads as the screen shaking
                        // on DPAD moves). Only the color may change on focus.
                        border: Border.all(
                          width: 2,
                          color: _focused
                              ? app.seeAll.accent
                              : (active
                                  ? app.seeAll.accentBorder
                                  : app.seeAll.line),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: stretch
                            ? MainAxisSize.max
                            : MainAxisSize.min,
                        children: [
                          if (widget.label != null) ...[
                            Text(
                              widget.label!.toUpperCase(),
                              style: TextStyle(
                                color: app.fade(app.core.tx, 0.42),
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
                            Flexible(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 200),
                                child: valueText,
                              ),
                            ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: app.fade(app.core.tx, 0.5),
                          ),
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
    final app = AppThemeScope.of(context);
    return Container(
      key: _btnKey,
      padding: const EdgeInsets.fromLTRB(9, 6, 6, 6),
      decoration: BoxDecoration(
        color: _focused
            ? app.fade(app.seeAll.accent, 0.30)
            : Colors.transparent,
        borderRadius: app.shape.brPill,
        // Constant thickness — only the color changes on focus, so the row
        // never reflows on DPAD moves (same rule as the boxed pill).
        border: Border.all(
          width: 1.2,
          color: _focused
              ? app.fade(app.seeAll.accent2, 0.45)
              : (active ? app.seeAll.accentBorder : Colors.transparent),
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
                    ? app.core.tx
                    : widget.quietAccent
                    ? app.seeAll.accent2
                    : app.fade(app.core.tx, 0.78),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 3),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 15,
            color: app.fade(app.core.tx, 0.45),
          ),
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
/// What the picker closed with: the option, and whether it was HELD (the
/// secondary action) rather than picked.
class _PickerChoice<T> {
  const _PickerChoice(this.value, {this.held = false});
  final T value;
  final bool held;
}

class _LazyPickerDialog<T extends Object> extends StatefulWidget {
  final String title;
  final List<StremioDropdownOption<T>> options;
  final T value;
  final bool isTelevision;

  /// Whether the host dropdown has a hold action to offer at all — rows still
  /// opt in individually via [StremioDropdownOption.holdable].
  final bool offersHold;
  final String? holdHint;

  const _LazyPickerDialog({
    required this.title,
    required this.options,
    required this.value,
    required this.isTelevision,
    this.offersHold = false,
    this.holdHint,
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

  /// Whether any row is a section heading — rows indent under headings.
  /// Cached: [itemBuilder] reads it per row, and this dialog exists for lists
  /// of several hundred entries, where a rescan per row is a real cost on the
  /// weak TV hardware it was written to protect. Safe to cache because a
  /// dialog's options never change once it is open.
  late final bool _hasSections = widget.options.any((o) => o.isHeader);
  String _filter = '';
  final TextEditingController _filterController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _shown = widget.options;
    final idx = widget.options.indexWhere(
      (o) => !o.isHeader && o.value == widget.value,
    );
    // A miss still has to anchor on a real row. Index 0 is a section heading
    // in a grouped list, and headings are not focusable — autofocusing one
    // would open the picker on TV with focus nowhere at all.
    final firstOption = widget.options.indexWhere((o) => !o.isHeader);
    _initialIndex = idx >= 0 ? idx : (firstOption < 0 ? 0 : firstOption);
    // Open with the current value near the top of the viewport (a few rows of
    // context above it). Overshoot is clamped by the scroll position on the
    // first layout.
    _scroll = ScrollController(
      initialScrollOffset:
          ((_initialIndex - 3).clamp(0, _initialIndex)) * _rowH,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _filterController.dispose();
    super.dispose();
  }

  void _onFilterChanged(String v) {
    final f = v.trim().toLowerCase();
    setState(() {
      _filter = f;
      // Headers are dropped entirely while filtering rather than matched:
      // a surviving header whose whole section was filtered out would label
      // the rows beneath it with the wrong section.
      _shown = f.isEmpty
          ? widget.options
          : [
              for (final o in widget.options)
                if (!o.isHeader && o.label.toLowerCase().contains(f)) o,
            ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final maxH = (MediaQuery.of(context).size.height * 0.72).clamp(
      260.0,
      560.0,
    );
    return Dialog(
      backgroundColor: app.seeAll.panel,
      shape: RoundedRectangleBorder(
        borderRadius: app.shape.br(16),
        side: BorderSide(color: app.seeAll.line),
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
                      color: app.fade(app.core.tx, 0.55),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    // Headings are not results — counting them would read
                    // "8" over a four-source list.
                    '${_shown.where((o) => !o.isHeader).length}',
                    style: TextStyle(
                      color: app.fade(app.core.tx, 0.35),
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
                child: TvTextField(
                  controller: _filterController,
                  autofocus: true,
                  onChanged: _onFilterChanged,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Filter…',
                    hintStyle: TextStyle(
                      color: app.fade(app.core.tx, 0.35),
                      fontSize: 13.5,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: app.core.tx.withValues(alpha: 0x62 / 0xFF),
                    ),
                    filled: true,
                    fillColor: app.seeAll.panel2,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: app.shape.br(10),
                      borderSide: BorderSide(color: app.seeAll.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: app.shape.br(10),
                      borderSide: BorderSide(color: app.seeAll.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: app.shape.br(10),
                      borderSide: BorderSide(color: app.seeAll.accent),
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
                  if (o.isHeader) {
                    // The list is fixed-extent for lazy-scroll performance, so
                    // the header sits in a full row slot; bottom-align it to
                    // read as a lead-in to the rows under it rather than a
                    // floating caption. Left of the rows, which indent under
                    // it — the tick hangs further left still.
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(2, 0, 8, 6),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: StremioDropdownSectionHeader(label: o.label),
                      ),
                    );
                  }
                  return _LazyPickerRow(
                    label: o.label,
                    selected: o.value == widget.value,
                    // Filtering strips the headings, so the indent that sat
                    // under them goes with it.
                    indented: _hasSections && _filter.isEmpty,
                    // Land DPAD focus on the current value when the dialog
                    // opens (its row is built — we scrolled to it). Filtering
                    // reshuffles indices, so only the pristine list anchors.
                    autofocus:
                        widget.isTelevision &&
                        _filter.isEmpty &&
                        i == _initialIndex,
                    onPick: () =>
                        Navigator.of(context).pop(_PickerChoice<T>(o.value)),
                    holdHint: widget.offersHold && o.holdable
                        ? widget.holdHint
                        : null,
                    onHold: widget.offersHold && o.holdable
                        ? () => Navigator.of(
                            context,
                          ).pop(_PickerChoice<T>(o.value, held: true))
                        : null,
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

  /// Sit under a section heading rather than at the list's own left edge.
  final bool indented;
  final VoidCallback onPick;

  /// Secondary action: hold OK (TV) or long-press. Null = plain row.
  final VoidCallback? onHold;

  /// Caption revealed on the focused row when [onHold] is wired.
  final String? holdHint;

  const _LazyPickerRow({
    required this.label,
    required this.selected,
    required this.autofocus,
    required this.onPick,
    this.indented = false,
    this.onHold,
    this.holdHint,
  });

  @override
  State<_LazyPickerRow> createState() => _LazyPickerRowState();
}

class _LazyPickerRowState extends State<_LazyPickerRow> {
  bool _focused = false;
  bool _hovered = false;

  /// The house hold length — the same 500ms the channel rows use for
  /// hold-OK, so one gesture is learned once.
  static const _holdDuration = Duration(milliseconds: 500);

  /// A Timer rather than an AnimationController: these rows are built lazily
  /// by the hundred on weak TV boxes, and a per-row ticker to drive a fill
  /// animation is not worth what it costs there.
  Timer? _holdTimer;

  /// Whether the key-up being handled belongs to a key-down THIS row saw.
  /// Holdable rows pick on key-UP (that is what tells a press from a hold),
  /// so a stray key-up arriving after focus moved must not select.
  bool _sawSelectDown = false;
  bool _holdFired = false;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _startHold() {
    _holdFired = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdDuration, () {
      _holdFired = true;
      _sawSelectDown = false;
      widget.onHold?.call();
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  KeyEventResult _handleSelectKey(KeyEvent event) {
    // No hold action → the original behaviour: pick on key-down.
    if (widget.onHold == null) {
      if (event is KeyDownEvent) {
        widget.onPick();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _sawSelectDown = true;
      _startHold();
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _cancelHold();
      final wasPress = _sawSelectDown && !_holdFired;
      _sawSelectDown = false;
      _holdFired = false;
      if (wasPress) widget.onPick();
      return KeyEventResult.handled;
    }
    // Swallow auto-repeat while the key is held down.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _focused = f);
        // Focus leaving mid-press abandons the hold: the key-up will land
        // somewhere else, and a timer that fires afterwards would act on a
        // row the user is no longer on.
        if (!f) {
          _cancelHold();
          _sawSelectDown = false;
        }
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
        if (isActivateKey(event.logicalKey) ||
            event.logicalKey == LogicalKeyboardKey.space) {
          return _handleSelectKey(event);
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPick,
          // Touch/desktop counterpart of TV's hold-OK. The row had no
          // long-press before, so this adds a gesture rather than
          // reinterpreting one.
          onLongPress: widget.onHold,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: EdgeInsets.only(
              left: widget.indented ? 22 : 12,
              right: 12,
            ),
            decoration: BoxDecoration(
              color: _focused
                  ? app.fade(app.seeAll.accent, 0.26)
                  : _hovered
                  ? app.fade(app.core.tx, 0.05)
                  : Colors.transparent,
              borderRadius: app.shape.br(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:
                          widget.selected ? app.seeAll.accent2 : app.core.tx,
                      fontSize: 13.5,
                      fontWeight: widget.selected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                ),
                // The hold gesture is invisible without a caption, so the
                // focused (or hovered) row spells it out. Only there: on
                // every row at once it would read as part of every label.
                if (widget.onHold != null &&
                    widget.holdHint != null &&
                    (_focused || _hovered))
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      widget.holdHint!,
                      style: TextStyle(
                        color: app.fade(app.core.tx, 0.45),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                if (widget.selected)
                  Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: app.seeAll.accent2,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

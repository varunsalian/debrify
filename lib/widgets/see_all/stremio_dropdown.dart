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

  const StremioDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    this.label,
    this.isTelevision = false,
    this.focusNode,
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

  Future<void> _open() async {
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
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hovered;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: _onKey,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _open,
          behavior: HitTestBehavior.opaque,
          child: Container(
            key: _btnKey,
            padding: const EdgeInsets.fromLTRB(14, 9, 11, 9),
            decoration: BoxDecoration(
              color: kSeeAllPanel,
              borderRadius: BorderRadius.circular(11),
              // Constant width: Container feeds the border's thickness into its
              // layout padding, so a 1→2px focus ring RESIZES the pill and
              // reflows the whole filter row (reads as the screen shaking on
              // DPAD moves). Only the color may change on focus.
              border: Border.all(
                width: 2,
                color: _focused
                    ? kSeeAllAccent
                    : (active ? kSeeAllAccentBorder : kSeeAllLine),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    _valueLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: Colors.white.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

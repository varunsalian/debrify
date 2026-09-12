import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/tv_keys.dart';
import '../styles/iptv_style.dart';

/// Xtream content switch for the Spotlight header.
///
/// Values intentionally match `IptvResultsView._selectedContentType` so the
/// parent can pass its existing state through without an adapter model.
class SpotlightContentTypeControl extends StatelessWidget {
  static const String live = 'live';
  static const String movies = 'vod';
  static const String series = 'series';

  final String value;
  final ValueChanged<String> onChanged;
  final FocusNode? firstItemFocusNode;

  const SpotlightContentTypeControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.firstItemFocusNode,
  }) : assert(
         value == live || value == movies || value == series,
         'Spotlight content type must be live, vod, or series.',
       );

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    return DecoratedBox(
      key: const ValueKey<String>('spotlight-content-type-control'),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CONTENT',
              style: TextStyle(
                color: t.fgDim,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 5),
            FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Row(
                children: [
                  _segment(live, 'Live TV', 0),
                  const SizedBox(width: 4),
                  _segment(movies, 'Movies', 1),
                  const SizedBox(width: 4),
                  _segment(series, 'Series', 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(String itemValue, String label, int order) {
    return Expanded(
      child: FocusTraversalOrder(
        order: NumericFocusOrder(order.toDouble()),
        child: _ContentTypeSegment(
          key: ValueKey<String>('spotlight-content-type-$itemValue'),
          label: label,
          selected: value == itemValue,
          focusNode: order == 0 ? firstItemFocusNode : null,
          onPressed: () => onChanged(itemValue),
        ),
      ),
    );
  }
}

class _ContentTypeSegment extends StatefulWidget {
  final String label;
  final bool selected;
  final FocusNode? focusNode;
  final VoidCallback onPressed;

  const _ContentTypeSegment({
    super.key,
    required this.label,
    required this.selected,
    required this.focusNode,
    required this.onPressed,
  });

  @override
  State<_ContentTypeSegment> createState() => _ContentTypeSegmentState();
}

class _ContentTypeSegmentState extends State<_ContentTypeSegment> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    return Semantics(
      button: true,
      selected: widget.selected,
      excludeSemantics: true,
      label: widget.label,
      onTap: widget.onPressed,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        onKeyEvent: (_, event) {
          if (isActivateOrSpaceKey(event.logicalKey)) {
            if (event is KeyDownEvent) widget.onPressed();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              key: ValueKey<String>(
                'spotlight-content-type-pill-${widget.label}',
              ),
              duration: const Duration(milliseconds: 120),
              height: 42,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: _focused
                    ? t.focusFill
                    : widget.selected
                    ? t.selectedTint
                    : _hovered
                    ? t.focusTint
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _focused
                      ? t.focusFill!
                      : widget.selected
                      ? t.accent.withValues(alpha: 0.55)
                      : Colors.transparent,
                ),
              ),
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _focused
                      ? t.focusInk
                      : widget.selected
                      ? t.fg
                      : t.fgDim,
                  fontSize: 11.5,
                  fontWeight: widget.selected
                      ? FontWeight.w700
                      : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

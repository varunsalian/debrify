import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/tv_keys.dart';
import '../styles/iptv_style.dart';
import 'iptv_spotlight_layout.dart';

/// Slot-based chrome for the Spotlight IPTV presentation.
///
/// This widget deliberately owns no IPTV data and no player state. The search
/// field remains the single instance owned by `BrowseScreen`; the rail,
/// category picker, hero, and content are supplied by `IptvResultsView`.
///
/// It also deliberately paints no page-wide background. The native preview
/// can require a clear compositing path through Flutter, so every Spotlight
/// surface paints only its own pane and [heroSlot] remains outside an opaque
/// ancestor introduced by this shell.
class SpotlightShell extends StatelessWidget {
  final IptvSpotlightLayoutMode mode;
  final Widget searchSlot;
  final Widget railSlot;
  final Widget categorySlot;
  final Widget? contentTypeSlot;
  final Widget heroSlot;
  final Widget contentSlot;

  /// Opens the compact source sheet. The sheet itself stays with the parent,
  /// which owns source selection and exact focus restoration.
  final VoidCallback onOpenSources;
  final String compactSourceLabel;
  final int? compactSourceCount;
  final FocusNode? compactSourceFocusNode;

  final double railWidth;
  final EdgeInsetsGeometry padding;

  const SpotlightShell({
    super.key,
    required this.mode,
    required this.searchSlot,
    required this.railSlot,
    required this.categorySlot,
    this.contentTypeSlot,
    required this.heroSlot,
    required this.contentSlot,
    required this.onOpenSources,
    this.compactSourceLabel = 'Sources',
    this.compactSourceCount,
    this.compactSourceFocusNode,
    this.railWidth = 236,
    this.padding = const EdgeInsets.all(12),
  }) : assert(
         mode != IptvSpotlightLayoutMode.classic,
         'Classic canvases must use the existing IPTV result view.',
       );

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: switch (mode) {
        IptvSpotlightLayoutMode.wide => _buildWide(),
        IptvSpotlightLayoutMode.compact => _buildCompact(),
        // The assertion above catches integration mistakes in debug. Keep the
        // release fallback inert so Spotlight never mounts a second search or
        // player subtree on a canvas intended for the classic view.
        IptvSpotlightLayoutMode.classic => const SizedBox.shrink(),
      },
    );
  }

  Widget _buildWide() {
    final t = IptvStyleTokens.spotlight;
    return Padding(
      key: const ValueKey<String>('spotlight-shell-wide'),
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: railWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _wideBrand(),
                  KeyedSubtree(
                    key: const ValueKey<String>('spotlight-search-slot'),
                    child: searchSlot,
                  ),
                  Expanded(
                    child: KeyedSubtree(
                      key: const ValueKey<String>('spotlight-rail-slot'),
                      child: railSlot,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 4,
                  child: KeyedSubtree(
                    key: const ValueKey<String>('spotlight-hero-slot'),
                    child: heroSlot,
                  ),
                ),
                const SizedBox(height: 8),
                _topControls(),
                const SizedBox(height: 8),
                Expanded(
                  flex: 6,
                  child: KeyedSubtree(
                    key: const ValueKey<String>('spotlight-content-slot'),
                    child: contentSlot,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact() {
    final t = IptvStyleTokens.spotlight;
    return Padding(
      key: const ValueKey<String>('spotlight-shell-compact'),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  _CompactSourceButton(
                    label: compactSourceLabel,
                    count: compactSourceCount,
                    focusNode: compactSourceFocusNode,
                    onPressed: onOpenSources,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: KeyedSubtree(
                      key: const ValueKey<String>('spotlight-search-slot'),
                      child: searchSlot,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 4,
            child: KeyedSubtree(
              key: const ValueKey<String>('spotlight-hero-slot'),
              child: heroSlot,
            ),
          ),
          const SizedBox(height: 8),
          _topControls(),
          const SizedBox(height: 8),
          Expanded(
            flex: 6,
            child: KeyedSubtree(
              key: const ValueKey<String>('spotlight-content-slot'),
              child: contentSlot,
            ),
          ),
        ],
      ),
    );
  }

  Widget _wideBrand() {
    final t = IptvStyleTokens.spotlight;
    return Padding(
      key: const ValueKey<String>('spotlight-wide-brand'),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 0),
      child: Row(
        children: [
          Icon(Icons.play_circle_fill_rounded, color: t.accent, size: 18),
          const SizedBox(width: 7),
          Text(
            'Debrify',
            style: TextStyle(
              color: t.fg,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          Container(
            width: 1,
            height: 13,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: t.hairline2,
          ),
          Flexible(
            child: Text(
              'LIVE TV',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.fgDim,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topControls() {
    final types = contentTypeSlot;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (types != null) ...[
          Flexible(
            child: KeyedSubtree(
              key: const ValueKey<String>('spotlight-content-type-slot'),
              child: types,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: KeyedSubtree(
            key: const ValueKey<String>('spotlight-category-slot'),
            child: categorySlot,
          ),
        ),
      ],
    );
  }
}

class _CompactSourceButton extends StatefulWidget {
  final String label;
  final int? count;
  final FocusNode? focusNode;
  final VoidCallback onPressed;

  const _CompactSourceButton({
    required this.label,
    required this.count,
    required this.focusNode,
    required this.onPressed,
  });

  @override
  State<_CompactSourceButton> createState() => _CompactSourceButtonState();
}

class _CompactSourceButtonState extends State<_CompactSourceButton> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    final inverse = _focused;
    final label = widget.count == null
        ? widget.label
        : '${widget.label} · ${_compactCount(widget.count!)}';

    return Semantics(
      button: true,
      excludeSemantics: true,
      label: 'Open sources',
      value: label,
      onTap: widget.onPressed,
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
            widget.onPressed();
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
              key: const ValueKey<String>('spotlight-source-trigger'),
              duration: const Duration(milliseconds: 120),
              height: 44,
              constraints: const BoxConstraints(minWidth: 132, maxWidth: 196),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: inverse
                    ? t.focusFill
                    : _hovered
                    ? t.focusTint
                    : t.selectedTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: inverse ? t.focusFill! : t.hairline2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.view_sidebar_rounded,
                    size: 18,
                    color: inverse ? t.focusInk : t.accent,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: inverse ? t.focusInk : t.fg,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 17,
                    color: inverse ? t.focusInk : t.fgDim,
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

String _compactCount(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) {
    final thousands = value / 1000;
    return '${thousands.toStringAsFixed(thousands >= 10 ? 0 : 1)}K';
  }
  final millions = value / 1000000;
  return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}M';
}

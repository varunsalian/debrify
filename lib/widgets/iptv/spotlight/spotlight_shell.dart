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
  final VoidCallback? onSourceDown;

  /// Keeps the expanded drawer and its toggle in the same focus scope.
  final Widget Function(Widget)? sourcesWrapper;
  final bool sourcesExpanded;
  final VoidCallback? onToggleSources;
  final VoidCallback? onCloseSources;
  final VoidCallback? onExitSourcesLeft;
  final VoidCallback? onOpenSearch;
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
    this.onSourceDown,
    this.sourcesWrapper,
    this.sourcesExpanded = false,
    this.onToggleSources,
    this.onCloseSources,
    this.onExitSourcesLeft,
    this.onOpenSearch,
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
    // The content always reserves only the icon rail. Expansion overlays its
    // left edge without resizing or reparenting the native preview surface.
    return Padding(
      key: const ValueKey<String>('spotlight-shell-wide'),
      padding: padding,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 76),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: KeyedSubtree(
                    key: const ValueKey<String>('spotlight-hero-slot'),
                    child: heroSlot,
                  ),
                ),
                const SizedBox(height: 8),
                _topControls(),
                const SizedBox(height: 8),
                Expanded(
                  flex: 5,
                  child: KeyedSubtree(
                    key: const ValueKey<String>('spotlight-content-slot'),
                    child: contentSlot,
                  ),
                ),
              ],
            ),
          ),
          if (sourcesExpanded)
            Positioned.fill(
              key: const ValueKey('spotlight-sources-dismiss-position'),
              child: GestureDetector(
                key: const ValueKey('spotlight-sources-dismiss'),
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: onCloseSources,
                child: const SizedBox.expand(),
              ),
            ),
          Positioned(
            // Keep this subtree when the sibling dismiss layer is inserted.
            // Both siblings are Positioned; without keys Flutter replaces the
            // rail with that layer and destroys its remembered focus nodes.
            key: const ValueKey('spotlight-sources-position'),
            left: 0,
            top: 0,
            bottom: 0,
            width: sourcesExpanded ? railWidth : 64,
            child: (sourcesWrapper ?? (child) => child)(
              DecoratedBox(
                key: const ValueKey('spotlight-sources-panel'),
                decoration: BoxDecoration(
                  color: t.panel,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: t.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (sourcesExpanded)
                      _wideBrand()
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 4),
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: t.accent,
                          size: 22,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Focus(
                        canRequestFocus: false,
                        onKeyEvent: (_, event) {
                          if (isActivateOrSpaceKey(event.logicalKey)) {
                            if (event is KeyDownEvent) {
                              (onToggleSources ?? onOpenSources)();
                            }
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowRight &&
                              (event is KeyDownEvent ||
                                  event is KeyRepeatEvent)) {
                            onCloseSources?.call();
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowLeft &&
                              (event is KeyDownEvent ||
                                  event is KeyRepeatEvent)) {
                            if (event is KeyDownEvent) {
                              onExitSourcesLeft?.call();
                            }
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: IconButton(
                          key: const ValueKey('spotlight-sources-toggle'),
                          tooltip: sourcesExpanded
                              ? 'Collapse sources'
                              : 'Expand sources',
                          constraints: const BoxConstraints(
                            minHeight: 44,
                            minWidth: 44,
                          ),
                          onPressed: onToggleSources ?? onOpenSources,
                          icon: Icon(
                            sourcesExpanded
                                ? Icons.chevron_left_rounded
                                : Icons.menu_rounded,
                          ),
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.focused)
                                  ? t.focusFill
                                  : Colors.transparent,
                            ),
                            foregroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.focused)
                                  ? t.focusInk
                                  : t.fg,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Keep one search field mounted at drawer width so its
                    // controller, keyboard and focus survive rail changes.
                    Offstage(
                      offstage: !sourcesExpanded,
                      child: ExcludeFocus(
                        excluding: !sourcesExpanded,
                        child: UnconstrainedBox(
                          constrainedAxis: Axis.vertical,
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: railWidth,
                            child: KeyedSubtree(
                              key: const ValueKey<String>(
                                'spotlight-search-slot',
                              ),
                              child: searchSlot,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!sourcesExpanded)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Focus(
                          canRequestFocus: false,
                          onKeyEvent: (_, event) {
                            if (isActivateOrSpaceKey(event.logicalKey)) {
                              if (event is KeyDownEvent) onOpenSearch?.call();
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowRight &&
                                (event is KeyDownEvent ||
                                    event is KeyRepeatEvent)) {
                              onCloseSources?.call();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: IconButton(
                            key: const ValueKey('spotlight-search-trigger'),
                            tooltip: 'Search channels',
                            onPressed: onOpenSearch,
                            icon: const Icon(Icons.search_rounded),
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.resolveWith(
                                (states) => states.contains(WidgetState.focused)
                                    ? t.focusFill
                                    : Colors.transparent,
                              ),
                              foregroundColor: WidgetStateProperty.resolveWith(
                                (states) => states.contains(WidgetState.focused)
                                    ? t.focusInk
                                    : t.fg,
                              ),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      key: const ValueKey('spotlight-rail-position'),
                      child: KeyedSubtree(
                        key: const ValueKey<String>('spotlight-rail-slot'),
                        child: railSlot,
                      ),
                    ),
                  ],
                ),
              ),
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
                    onDown: onSourceDown,
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
            flex: 5,
            child: KeyedSubtree(
              key: const ValueKey<String>('spotlight-hero-slot'),
              child: heroSlot,
            ),
          ),
          const SizedBox(height: 8),
          _topControls(),
          const SizedBox(height: 8),
          Expanded(
            flex: 5,
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (mode == IptvSpotlightLayoutMode.wide) ...[
          Flexible(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                compactSourceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: IptvStyleTokens.spotlight.fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (types != null) ...[
          Flexible(
            flex: 3,
            child: KeyedSubtree(
              key: const ValueKey<String>('spotlight-content-type-slot'),
              child: types,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          flex: 4,
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
  final VoidCallback? onDown;

  const _CompactSourceButton({
    required this.label,
    required this.count,
    required this.focusNode,
    required this.onPressed,
    this.onDown,
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
          if (isActivateOrSpaceKey(event.logicalKey)) {
            if (event is KeyDownEvent) widget.onPressed();
            return KeyEventResult.handled;
          }
          if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
              event.logicalKey == LogicalKeyboardKey.arrowDown &&
              widget.onDown != null) {
            widget.onDown!();
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

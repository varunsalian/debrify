import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/main_page_bridge.dart';

/// Cyan pole of the liquid-glass chromatic accents (edge rim + focus ring).
const _kRimCyan = Color(0xFF54D6FF);

/// "Liquid glass" collapsible sidebar for Android TV. At rest it's barely
/// there — a smoke gradient melting off the left edge, each tab icon in its
/// own glass puck (the current tab's puck lit purple). When focused it expands
/// into a translucent pane with a rounded right edge, a diagonal specular
/// streak and a purple→cyan chromatic rim; labels slide/fade in.
///
/// Performance: this is designed to be laid out as an OVERLAY (a Stack sibling
/// over the content, inset by [collapsedWidth]) — NOT a Row sibling. As a Row
/// sibling, animating the rail width re-lays-out the whole content board every
/// frame, which is the main source of TV sluggishness. As an overlay the board
/// never moves. Internally the per-item cost is kept tiny: items are stateless
/// (no per-item AnimationControllers / Transform.scale), the focus highlight is
/// a plain Container that snaps instantly on focus move (no per-move blur
/// tween — animated blur is what janks a weak TV GPU), and labels fade via a
/// single opacity driven by the shared expand animation.
class TvSidebarNav extends StatefulWidget {
  final int currentIndex;
  final List<TvNavItem> items;
  final ValueChanged<int> onTap;
  final VoidCallback? onFocusContent;

  /// Fired when the rail opens (true) / closes (false), so the host can dim
  /// the content behind the expanded overlay for depth.
  final ValueChanged<bool>? onExpandedChanged;

  const TvSidebarNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.onFocusContent,
    this.onExpandedChanged,
  });

  /// The width the collapsed rail occupies. The content should be inset by this
  /// so nothing hides behind the rail while it's collapsed.
  static const double collapsedWidth = 64.0;
  static const double expandedWidth = 232.0;

  @override
  State<TvSidebarNav> createState() => TvSidebarNavState();
}

class TvSidebarNavState extends State<TvSidebarNav>
    with SingleTickerProviderStateMixin {
  static const _accent = Color(0xFF7B5CFF); // kStremioAccent
  static const _accentSoft = Color(0xFFA78BFA);

  final List<FocusNode> _focusNodes = [];
  int _focusedIndex = 0;
  bool _hasSidebarFocus = false;

  late final AnimationController _expandController;
  late final Animation<double> _expand;

  static const int _pageTransitionDelay = 400;

  @override
  void initState() {
    super.initState();
    _initFocusNodes();
    _focusedIndex = widget.currentIndex;
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _expand = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  void _initFocusNodes() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
    for (int i = 0; i < widget.items.length; i++) {
      final capturedIndex = i;
      // skipTraversal: the rail must NEVER be reachable by Flutter's directional
      // focus search — otherwise a stray DPAD press at a content edge (e.g. DOWN
      // from a search bar while its results grid can't take focus) lands here and
      // pops the sidebar open. Entry is explicit only: requestFocus() below,
      // driven by MainPageBridge.focusTvSidebar (LEFT at the content's left
      // edge). Internal UP/DOWN navigation uses explicit requestFocus too, so
      // skipping traversal changes nothing inside the rail.
      final node = FocusNode(debugLabel: 'tv-nav-item-$i', skipTraversal: true);
      node.addListener(() => _handleFocusChange(capturedIndex, node.hasFocus));
      _focusNodes.add(node);
    }
  }

  void _handleFocusChange(int index, bool hasFocus) {
    if (!mounted) return;
    if (hasFocus) {
      final wasFocused = _hasSidebarFocus;
      setState(() {
        _focusedIndex = index;
        _hasSidebarFocus = true;
      });
      if (!wasFocused) widget.onExpandedChanged?.call(true);
      _expandController.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (index >= _focusNodes.length) return;
        final ctx = _focusNodes[index].context;
        if (ctx == null) return;
        final scrollable = Scrollable.maybeOf(ctx);
        if (scrollable != null && scrollable.position.maxScrollExtent > 0) {
          Scrollable.ensureVisible(ctx, duration: Duration.zero, alignment: 0.3);
        }
      });
    } else {
      // Only collapse once NO sidebar item holds focus.
      if (!_focusNodes.any((n) => n.hasFocus)) {
        setState(() => _hasSidebarFocus = false);
        widget.onExpandedChanged?.call(false);
        _expandController.reverse();
        _scrollToCurrent();
      }
    }
  }

  void _collapse() {
    if (!mounted) return;
    setState(() => _hasSidebarFocus = false);
    widget.onExpandedChanged?.call(false);
    _expandController.reverse();
    _scrollToCurrent();
  }

  /// Re-centre the collapsed rail on the current tab. On a short screen the
  /// item list overflows and scrolls while you navigate it; without this the
  /// resting rail would keep whatever offset you'd scrolled to instead of
  /// showing where you actually are. No-op when the list fits (no scroll).
  void _scrollToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final idx = widget.currentIndex.clamp(0, _focusNodes.length - 1);
      final ctx = _focusNodes[idx].context;
      if (ctx == null) return;
      final scrollable = Scrollable.maybeOf(ctx);
      if (scrollable == null || scrollable.position.maxScrollExtent <= 0) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _selectMenuItem(int index) {
    widget.onTap(index);
    _collapse();
    Future.delayed(const Duration(milliseconds: _pageTransitionDelay), () {
      if (mounted) _focusContent();
    });
  }

  void _focusContent() {
    if (!MainPageBridge.requestTvContentFocus()) {
      widget.onFocusContent?.call();
    }
  }

  void _moveToContent() {
    _collapse();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _focusContent();
    });
  }

  @override
  void didUpdateWidget(TvSidebarNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _initFocusNodes();
    }
    // Selecting a new tab collapses the rail — re-centre it on the new current
    // item (its index arrives here, one frame after the tap fires).
    if (oldWidget.currentIndex != widget.currentIndex && !_hasSidebarFocus) {
      _scrollToCurrent();
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _expandController.dispose();
    super.dispose();
  }

  /// Called from the parent when DPAD-left lands on the sidebar.
  void requestFocus() {
    if (_focusNodes.isEmpty) return;
    final targetIndex = widget.currentIndex.clamp(0, _focusNodes.length - 1);
    _focusNodes[targetIndex].requestFocus();
  }

  bool get hasFocus => _hasSidebarFocus;

  KeyEventResult _handleKeyEvent(int index, KeyEvent event) {
    // Repeats (held DPAD) must be handled here too: the rail's nodes skip
    // focus traversal, so a repeat that fell through would be resolved by
    // geometric search against CONTENT nodes and yank focus out of the rail.
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        if (index > 0) _focusNodes[index - 1].requestFocus();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        if (index < _focusNodes.length - 1) {
          _focusNodes[index + 1].requestFocus();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        // One exit per press: the 100ms collapse→focus handoff in
        // _moveToContent shouldn't be re-queued by key repeats.
        if (event is KeyDownEvent) _moveToContent();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        return KeyEventResult.handled;
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.gameButtonA:
        // Activate only on the initial press — a held SELECT must not
        // re-trigger tab switches — but still swallow the repeats.
        if (event is KeyDownEvent) _selectMenuItem(index);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only the width-bearing shell rebuilds each animation frame; the item list
    // is passed as `child` so it isn't rebuilt during the expand tween.
    return AnimatedBuilder(
      animation: _expand,
      builder: (context, child) {
        final t = _expand.value;
        final width = TvSidebarNav.collapsedWidth +
            (TvSidebarNav.expandedWidth - TvSidebarNav.collapsedWidth) * t;
        // While the Home hero's trailer plays, the shell publishes the focused
        // title's colour (MainPageBridge.tvHeroTint); the rail takes it on in
        // lock-step with the hero's left colour stage and the rows, so the whole
        // room shares the film's mood. Null (no trailer) → the normal purple.
        return ValueListenableBuilder<Color?>(
          valueListenable: MainPageBridge.tvHeroTint,
          child: child,
          builder: (context, heroTint, kid) {
            return TweenAnimationBuilder<Color?>(
              // Ease toward the tint, or toward TRANSPARENT when there's none
              // (its alpha eases to 0 so the rail melts back to purple). Must be
              // non-null — TweenAnimationBuilder asserts tween.end != null, and
              // tvHeroTint is null whenever no trailer plays.
              tween: ColorTween(end: heroTint ?? const Color(0x00000000)),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOut,
              child: kid,
              builder: (context, eased, inner) {
                // Blend the film's colour into the rail by [amt], scaled by the
                // eased alpha so it fades in and out. Low amounts keep the icons
                // and labels legible over the darkened, tinted rail.
                Color tinted(Color c, double amt) => eased == null
                    ? c
                    : Color.lerp(
                        c,
                        eased.withValues(alpha: 1.0),
                        amt * eased.a,
                      )!;
                // LIQUID GLASS shell. Collapsed: only a smoke gradient
                // melting off the left edge (the pucks per item carry the
                // rest). Expanded: a translucent pane — diagonal glass wash,
                // specular streak, purple→cyan rim — whose alphas all ride
                // [t]. The Home board lays blurred art behind the rail, so
                // translucency reads as glass for free (no BackdropFilter —
                // banned on TV). Everything here is plain gradients baked per
                // frame: no Opacity layers, same cost class as the old fill.
                final smoke = tinted(const Color(0xFF0A0816), 0.35);
                final paneMid = tinted(const Color(0xFF120D26), 0.40);
                final paneDeep = tinted(const Color(0xFF0A0816), 0.30);
                return Container(
                  width: width,
                  // antiAlias (not hardEdge): the open pane clips a 26px
                  // rounded corner, and a hard-edge clip draws that curve
                  // jagged on a TV panel.
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    // Rounded right edge grows in with the pane; at rest the
                    // smoke fades to nothing, so no corner is visible anyway.
                    borderRadius: BorderRadius.horizontal(
                      right: Radius.circular(26 * t),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        smoke.withValues(alpha: 0.46 * (1 - t)),
                        smoke.withValues(alpha: 0.0),
                      ],
                    ),
                    boxShadow: t > 0.02
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5 * t),
                              blurRadius: 36,
                              offset: const Offset(10, 0),
                            ),
                            BoxShadow(
                              color: tinted(_accent, 0.5)
                                  .withValues(alpha: 0.10 * t),
                              blurRadius: 40,
                              offset: const Offset(2, 0),
                            ),
                          ]
                        : null,
                  ),
                  // The glass layers are in the tree UNCONDITIONALLY (at rest
                  // their alphas are 0, painting nothing). Gating them on [t]
                  // would shift the menu's slot in this list the moment the
                  // expand starts, re-inflating the whole menu subtree — which
                  // resets the scroll position to the top and drops focus/
                  // label state mid-open.
                  child: Stack(
                    children: [
                      // The pane: brightest at the top-left corner — the "lit"
                      // edge of the glass.
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withValues(alpha: 0.10 * t),
                                paneMid.withValues(alpha: 0.36 * t),
                                paneDeep.withValues(alpha: 0.46 * t),
                              ],
                              stops: const [0.0, 0.40, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: inner ?? const SizedBox.shrink(),
                      ),
                      // Specular streak OVER the content — the gloss. Capped
                      // at 10% white so labels stay legible beneath it.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withValues(alpha: 0.0),
                                  Colors.white.withValues(alpha: 0.10 * t),
                                  Colors.white.withValues(alpha: 0.02 * t),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                                stops: const [0.30, 0.42, 0.55, 0.62],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Chromatic rim on the open edge — replaces the old
                      // hairline border.
                      Positioned(
                        right: 0,
                        top: 20,
                        bottom: 20,
                        width: 1.5,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  _accentSoft.withValues(alpha: 0.70 * t),
                                  _kRimCyan.withValues(alpha: 0.40 * t),
                                  _accentSoft.withValues(alpha: 0.15 * t),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBranding(),
              const SizedBox(height: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Centre the icon group when it fits; scroll if a tall menu
                    // ever overflows a short screen (keeps ensureVisible working).
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _buildNavItems(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The nav items as a vertically-centred group. Every tab icon shows on the
  /// resting rail (dimmed when idle, the current one in its accent pill); labels
  /// and section headers fade/slide in only when the rail opens. Centring keeps
  /// the rail balanced rather than top-clustered or a bottom-heavy wall.
  List<Widget> _buildNavItems() {
    final widgets = <Widget>[];
    for (int index = 0; index < widget.items.length; index++) {
      final item = widget.items[index];
      final startsSection = item.section != null &&
          (index == 0 || widget.items[index - 1].section != item.section);
      if (startsSection) {
        widgets.add(_SectionHeader(item.section!, _expand));
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _TvNavItemWidget(
            item: item,
            index: index,
            isSelected: index == widget.currentIndex,
            isFocused: index == _focusedIndex && _hasSidebarFocus,
            expand: _expand,
            accent: _accent,
            accentSoft: _accentSoft,
            focusNode: _focusNodes[index],
            onTap: () => _selectMenuItem(index),
            onKeyEvent: (e) => _handleKeyEvent(index, e),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildBranding() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            SizedBox(
              width: TvSidebarNav.collapsedWidth,
              child: Center(
                child: Image.asset(
                  'assets/app_icon.png',
                  width: 26,
                  height: 26,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Expanded(
              child: ClipRect(
                child: FadeTransition(
                  opacity: _expand,
                  child: const Text(
                    'Debrify',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single nav row, liquid-glass edition. Stateless: collapsed, the icon sits
/// in a 36px glass puck (the current tab's puck lit purple); expanded, the row
/// becomes a stadium pill — a purple→cyan gradient ring with a static glow
/// when focused, faint glass when selected. Both visuals bake the shared
/// expand value into their colors (AnimatedBuilder rebuilds, no Opacity
/// layers), and focus state still snaps instantly on focus move (no per-move
/// animation — animated blur janks a weak TV GPU). No per-item
/// AnimationController.
class _TvNavItemWidget extends StatelessWidget {
  final TvNavItem item;

  /// Position in the menu — drives the label's slide-in stagger on expand.
  final int index;
  final bool isSelected;
  final bool isFocused;
  final Animation<double> expand;
  final Color accent;
  final Color accentSoft;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final KeyEventResult Function(KeyEvent) onKeyEvent;

  const _TvNavItemWidget({
    required this.item,
    required this.index,
    required this.isSelected,
    required this.isFocused,
    required this.expand,
    required this.accent,
    required this.accentSoft,
    required this.focusNode,
    required this.onTap,
    required this.onKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = isFocused || isSelected;
    final Color iconColor = isFocused
        ? Colors.white
        : isSelected
        // Light lavender: legible both on the lit puck (collapsed) and the
        // faint glass pill (expanded).
        ? const Color(0xFFD8CDFF)
        : Colors.white.withValues(alpha: 0.42);
    final Color labelColor = isFocused
        ? Colors.white
        : isSelected
        ? Colors.white.withValues(alpha: 0.94)
        : Colors.white.withValues(alpha: 0.5);

    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) => onKeyEvent(event),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // Highlights snap instantly as focus moves between items (no per-move
        // animation — animated blur is what made item-to-item navigation
        // sluggish on the weak TV GPU); glows are static, painted when focus
        // lands. Only the puck↔pill cross-dissolve animates, riding the shared
        // 200ms expand with alphas baked into the colors.
        child: SizedBox(
          height: 42,
          child: Stack(
            children: [
              // COLLAPSED visual: the glass puck behind the icon. Alphas are
              // premultiplied by (1 - t) so it dissolves as the pane pours in.
              Positioned(
                left: 4, // (44-wide icon box − 36 puck) / 2
                top: 3,
                child: AnimatedBuilder(
                  animation: expand,
                  builder: (context, _) {
                    final k = 1.0 - expand.value;
                    if (k < 0.01) {
                      return const SizedBox(width: 36, height: 36);
                    }
                    return Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: isSelected
                              ? [
                                  accent.withValues(alpha: 0.34 * k),
                                  accent.withValues(alpha: 0.18 * k),
                                ]
                              : [
                                  Colors.white.withValues(alpha: 0.10 * k),
                                  Colors.white.withValues(alpha: 0.03 * k),
                                ],
                        ),
                        border: Border.all(
                          color: isSelected
                              ? accentSoft.withValues(alpha: 0.55 * k)
                              : Colors.white.withValues(alpha: 0.10 * k),
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.45 * k),
                                  blurRadius: 14,
                                  spreadRadius: -2,
                                ),
                              ]
                            : null,
                      ),
                    );
                  },
                ),
              ),
              // EXPANDED visual: the stadium pill behind the whole row —
              // liquid purple→cyan ring + glow for focus, faint glass for the
              // selected tab. Alphas ride t so the collapsed rail stays clean
              // (the pill would otherwise peek out from behind the puck).
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: expand,
                  builder: (context, _) {
                    final t = expand.value;
                    if (t < 0.01 || !active) return const SizedBox.shrink();
                    if (isFocused) {
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(21),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accentSoft.withValues(alpha: t),
                              _kRimCyan.withValues(alpha: t),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.45 * t),
                              blurRadius: 20,
                              spreadRadius: -3,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(1.4),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(
                                  0xFF241B4D,
                                ).withValues(alpha: 0.94 * t),
                                const Color(
                                  0xFF1A1338,
                                ).withValues(alpha: 0.94 * t),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(21),
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.08 * t),
                            Colors.white.withValues(alpha: 0.02 * t),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Row(
                children: [
                  SizedBox(
                    width: TvSidebarNav.collapsedWidth - 20, // rail - padding(2×10)
                    child: Center(
                      child: Icon(item.icon, color: iconColor, size: 20),
                    ),
                  ),
                  Expanded(
                    child: ClipRect(
                      child: _StaggeredLabel(
                        expand: expand,
                        index: index,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                item.label,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                  color: labelColor,
                                  fontSize: 13.5,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                            if (item.tag != null) ...[
                              const SizedBox(width: 7),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  item.tag!,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: accentSoft,
                                    letterSpacing: 0.4,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Leading tick — active-tab marker, expanded only (collapsed,
              // the lit puck marks the tab). Focused rows drop it: the
              // gradient ring is the marker there.
              if (isSelected && !isFocused)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: AnimatedBuilder(
                    animation: expand,
                    builder: (context, _) {
                      final t = expand.value;
                      if (t < 0.01) return const SizedBox.shrink();
                      return Center(
                        child: Container(
                          width: 3.5,
                          height: 15,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.75 * t),
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(4),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A nav label that rides the shared expand animation with a per-item stagger:
/// each row's text fades in while settling ~12px leftward into place (it
/// trails the expanding rail edge), offset a touch later the further down the
/// menu it sits — the open reads as a choreographed cascade instead of one
/// flat fade. Still zero per-item controllers; every label derives from the
/// single expand CurvedAnimation.
class _StaggeredLabel extends StatelessWidget {
  final Animation<double> expand;
  final int index;
  final Widget child;

  const _StaggeredLabel({
    required this.expand,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: expand,
      // Later rows start later; cap the offset so a long menu's tail doesn't
      // lag the 200ms expand.
      curve: Interval(
        (index * 0.055).clamp(0.0, 0.45),
        1.0,
        curve: Curves.easeOutCubic,
      ),
    );
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, inner) => Transform.translate(
          offset: Offset(12 * (1 - curved.value), 0),
          child: inner,
        ),
        child: child,
      ),
    );
  }
}

/// Group header / section gap. Fixed height so it reads as a constant gap
/// between icon groups on the collapsed rail; the label just fades in when the
/// rail opens (no height change, so the centred icon group doesn't drift).
class _SectionHeader extends StatelessWidget {
  final String text;
  final Animation<double> expand;
  const _SectionHeader(this.text, this.expand);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: FadeTransition(
        opacity: expand,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 12, 3),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              text.toUpperCase(),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Data class for TV navigation items.
class TvNavItem {
  final IconData icon;
  final String label;
  final String? tag;

  /// Group header this item sits under (e.g. "Main"). Consecutive items
  /// sharing a section render one header above the first of the group.
  final String? section;

  const TvNavItem(this.icon, this.label, {this.tag, this.section});
}

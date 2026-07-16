import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/main_page_bridge.dart';

/// Stremio-themed collapsible sidebar for Android TV. Collapsed to an icon rail
/// by default; expands (labels slide/fade in) when focused.
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
  static const _bg = Color(0xFF0D0B1A); // kStremioBg
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
        return Container(
          width: width,
          decoration: BoxDecoration(
            // Stremio look: a purple-tinted top blooming down into deep indigo-
            // black, richer as it expands so the overlay reads as a raised panel.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(const Color(0xFF1B1636), _bg, 0.15)!,
                Color.lerp(const Color(0xFF14112A), _bg, 0.5 - t * 0.2)!,
                _bg,
              ],
              stops: const [0.0, 0.42, 1.0],
            ),
            border: Border(
              right: BorderSide(
                // faint accent-tinted hairline, brightening as it opens
                color: _accent.withValues(alpha: 0.10 + t * 0.10),
                width: 1,
              ),
            ),
            boxShadow: t > 0.02
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5 * t),
                      blurRadius: 28,
                      offset: const Offset(8, 0),
                    ),
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.10 * t),
                      blurRadius: 40,
                      offset: const Offset(2, 0),
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.hardEdge,
          child: child,
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
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
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

/// A single nav row. Stateless: the focus "pill" is a plain Container that
/// snaps instantly on focus move (no per-move animation — animated blur janks a
/// weak TV GPU), with a static glow painted once when focus lands; the label
/// fades via the shared expand animation. No per-item AnimationController.
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
        ? accentSoft
        : Colors.white.withValues(alpha: 0.4);
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
        // Plain Container (not AnimatedContainer): the highlight snaps instantly
        // as focus moves between items — that feels responsive on a remote, and
        // it avoids re-animating the blur shadow every frame (animated blur is
        // what made item-to-item navigation sluggish on the weak TV GPU). The
        // glow below is now static: painted once when focus lands, not tweened.
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            // Focus = accent gradient pill with a soft glow; selected = a faint
            // glass tint; idle = nothing.
            gradient: isFocused
                ? LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      accent.withValues(alpha: 0.32),
                      accent.withValues(alpha: 0.08),
                    ],
                  )
                : isSelected
                ? LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.07),
                      Colors.white.withValues(alpha: 0.02),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(11),
            border: isFocused
                ? Border.all(color: accent.withValues(alpha: 0.6), width: 1.5)
                : null,
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.28),
                      blurRadius: 12,
                      spreadRadius: -3,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
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
              // Leading accent bar — the active-tab marker. Overlaid so the icon
              // stays centered; bright + glowing when focused, dimmer when the
              // current tab isn't focused.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: active ? 3.5 : 0,
                    height: isFocused ? 21 : (isSelected ? 15 : 0),
                    decoration: BoxDecoration(
                      color: isFocused ? accent : accent.withValues(alpha: 0.75),
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(4),
                      ),
                    ),
                  ),
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

import 'dart:async';
import 'dart:ui' as ui show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/main_page_bridge.dart';
import '../models/profiles/user_profile.dart';
import '../utils/platform_util.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_scope.dart';
import 'profiles/profile_avatar_view.dart';

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
  final UserProfile? profile;
  final VoidCallback? onProfileTap;

  /// Visual style: 'ghost' (no chrome, white coin — the default) | 'classic'
  /// (the original liquid glass) | 'island' (floating glass capsule) |
  /// 'marquee' (ghost at rest, big-type overlay when open) | 'badge'
  /// (labelled icons, white squircle active) | 'pill' (no rail at rest — a
  /// single capsule naming the current tab, and the menu arrives as a drawer
  /// over full-bleed content).
  ///
  /// Focus model, LEFT-only entry, key handling and expand mechanics are
  /// identical in every style. The first five change chrome ONLY; 'pill' also
  /// changes layout, which is why [contentInsetFor] exists.
  final String navStyle;

  const TvSidebarNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
    this.onFocusContent,
    this.onExpandedChanged,
    this.navStyle = 'ghost',
    this.profile,
    this.onProfileTap,
  });

  /// The width the collapsed rail occupies. The content is inset by this so
  /// nothing hides behind the rail while it's collapsed.
  static const double collapsedWidth = 64.0;
  static const double expandedWidth = 232.0;

  /// How far the CONTENT must be inset for [style].
  ///
  /// Every style used to share [collapsedWidth] precisely so switching one
  /// never re-flowed the content. 'pill' is the exception and the reason this
  /// is a function: it draws no rail at rest, so reserving a 64px gutter for a
  /// rail that is not there would waste the space the style exists to reclaim.
  ///
  /// Read this rather than the constant — a host that hardcodes 64 silently
  /// leaves a dead margin down the left of every screen under 'pill'.
  static double contentInsetFor(String style) =>
      style == 'pill' ? 0.0 : collapsedWidth;

  /// Handle for the 'pill' capsule.
  ///
  /// Needed because the shell keeps building its item list even at zero width,
  /// so the collapsed drawer's labels are in the tree alongside the capsule's
  /// — a bare `find.text('Home')` matches both and proves nothing.
  static const Key pillKey = ValueKey('tv-sidebar-pill');

  @override
  State<TvSidebarNav> createState() => TvSidebarNavState();
}

// Ticker*s*, plural: the expand tween and the 'pill' capsule's hold-fade run
// independently, so `SingleTickerProviderStateMixin` throws the moment the
// second controller is built.
class TvSidebarNavState extends State<TvSidebarNav>
    with TickerProviderStateMixin {
  final List<FocusNode> _focusNodes = [];
  int _focusedIndex = 0;
  bool _hasSidebarFocus = false;

  late final AnimationController _expandController;
  late final CurvedAnimation _expand;

  /// The theme's tempo, resolved once per dependency change and read from here
  /// everywhere else in this State. The rail's shell and item list re-inflate
  /// on every frame of the expand tween, so a scope lookup down there would be
  /// a per-frame inherited walk — same reason [build] hoists the theme.
  late AppMotion _motion;

  static const int _pageTransitionDelay = 400;

  /// How long the 'pill' capsule stays up after you arrive somewhere.
  ///
  /// The label answers "which tab am I on", and that is a question you have
  /// when you ARRIVE, not continuously — so it says its piece and leaves.
  /// Permanent would mean permanent collision: every page in this app owns its
  /// own top-left (YouTube's search field starts in the corner), and no amount
  /// of shrinking makes a fixed overlay stop landing on them.
  ///
  /// A second. Short on purpose: it is a confirmation, not a heading, and the
  /// LABEL sits on someone's content the whole time it is up.
  static const Duration _pillHold = Duration(milliseconds: 1000);

  /// How close to the left edge focus must be for the mark to brighten.
  ///
  /// Roughly one poster plus its gutter — the leftmost column, which is
  /// exactly where LEFT stops moving within the content and starts opening
  /// the menu. Content is full-bleed under this style, so this is measured
  /// from the screen edge.
  static const double _pillEdgeZone = 200;

  /// Reveals the LABEL — not the mark. The chevron and icon are permanent;
  /// only the name breathes in and out.
  AnimationController? _pillLabel;

  /// The left-edge brighten. Separate controller so the mark can light up
  /// while the label is collapsed, which is the common case.
  AnimationController? _pillGlow;
  final ValueNotifier<bool> _pillNearEdge = ValueNotifier<bool>(false);
  Timer? _pillTimer;

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
      // Not a token — the tokens name one deceleration curve, and this is the
      // close's ease-IN counterpart. Left as shipped.
      reverseCurve: Curves.easeInCubic,
    );
    // Closing the drawer is an arrival too — you have just chosen where to be,
    // so the label re-states it rather than leaving you to guess.
    _expandController.addStatusListener(_onExpandStatus);
    if (_ensurePillFade()) {
      _armPillHide();
      FocusManager.instance.addListener(_onFocusMovedForEdge);
    }
  }

  /// Brighten the mark when focus reaches the leftmost column.
  ///
  /// The "you can use me right now" signal: LEFT is only the menu gesture once
  /// focus has run out of content to move through, and this is the same
  /// moment. Runs on focus CHANGE, which is user-paced — one render-object
  /// lookup per keypress, not per frame.
  void _onFocusMovedForEdge() {
    if (_pillGlow == null) return;
    final ctx = FocusManager.instance.primaryFocus?.context;
    final ro = ctx?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return;
    final near = ro.localToGlobal(Offset.zero).dx < _pillEdgeZone;
    if (_pillNearEdge.value == near) return;
    _pillNearEdge.value = near;
    near ? _pillGlow!.forward() : _pillGlow!.reverse();
  }

  /// Build the capsule's fade controller if this style needs one.
  ///
  /// Lazy and idempotent: the other five styles never carry a ticker they
  /// cannot use, and switching INTO 'pill' at runtime builds it then. Returns
  /// whether a controller exists afterwards, so callers can decide what to do
  /// without re-testing the style.
  ///
  /// One constructor, one place — duplicating it across initState and
  /// didUpdateWidget is how the two quietly end up with different durations.
  bool _ensurePillFade() {
    if (widget.navStyle != 'pill') return false;
    _pillLabel ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 340),
      value: 1,
    );
    _pillGlow ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 320),
    );
    return true;
  }

  void _onExpandStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) _showPill();
  }

  /// Bring the capsule back and start its countdown. Cheap no-op under every
  /// other style, which never builds the controller.
  void _showPill() {
    final label = _pillLabel;
    if (label == null) return;
    label.forward();
    _armPillHide();
  }

  void _armPillHide() {
    _pillTimer?.cancel();
    _pillTimer = Timer(_pillHold, () {
      if (!mounted) return;
      // Never fade out from under an OPEN drawer: closing it re-shows the
      // label, and a timer that fired mid-open would cut that short.
      if (_expandController.value > 0) return;
      _pillLabel?.reverse();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The one hook that may depend on inherited widgets AND re-runs when they
    // change, so switching theme or turning "remove animations" on retargets
    // the live expand controller. Legacy resolves both back to what initState
    // built.
    _motion = AppMotion.of(context);
    _expandController.duration = _motion.scaled(
      const Duration(milliseconds: 200),
    );
    _expand.curve = _motion.standard;
  }

  void _initFocusNodes() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
    final count =
        widget.items.length +
        (widget.profile != null && widget.onProfileTap != null ? 1 : 0);
    for (int i = 0; i < count; i++) {
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
          Scrollable.ensureVisible(
            ctx,
            duration: Duration.zero,
            alignment: 0.3,
          );
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
      // `mounted` too, not just null: a style switch re-parents the item
      // subtree (pill wraps it in its panel), and this post-frame callback
      // can run while the OLD elements are deactivated but not yet nulled —
      // an ancestor walk from one of those asserts.
      if (ctx == null || !ctx.mounted) return;
      final scrollable = Scrollable.maybeOf(ctx);
      if (scrollable == null || scrollable.position.maxScrollExtent <= 0)
        return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: _motion.scaled(const Duration(milliseconds: 220)),
        curve: _motion.standard,
      );
    });
  }

  void _selectMenuItem(int index) {
    if (index == widget.items.length &&
        widget.profile != null &&
        widget.onProfileTap != null) {
      // A pushed route owns its own initial focus. The normal tab path's
      // delayed focus handoff would otherwise reach through the new Profiles
      // page and ask the old content tab to take focus back.
      _collapse();
      widget.onProfileTap!();
      return;
    }
    widget.onTap(index);
    _collapse();
    Future.delayed(const Duration(milliseconds: _pageTransitionDelay), () {
      // !_hasSidebarFocus: if the rail was re-entered during the delay
      // (BACK/Menu at root, or LEFT), stealing focus back to content would
      // slam the just-reopened rail shut.
      if (mounted && !_hasSidebarFocus) _focusContent();
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
      // Same re-entry guard as _selectMenuItem.
      if (mounted && !_hasSidebarFocus) _focusContent();
    });
  }

  @override
  void didUpdateWidget(TvSidebarNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldHasProfile =
        oldWidget.profile != null && oldWidget.onProfileTap != null;
    final hasProfile = widget.profile != null && widget.onProfileTap != null;
    if (oldWidget.items.length != widget.items.length ||
        oldHasProfile != hasProfile) {
      _initFocusNodes();
    }
    if (oldWidget.currentIndex != widget.currentIndex) {
      // Selecting a new tab collapses the rail — re-centre it on the new
      // current item (its index arrives here, one frame after the tap fires).
      if (!_hasSidebarFocus) _scrollToCurrent();
      // Arriving somewhere new is exactly when the 'pill' label earns its
      // place. No-op under every other style.
      _showPill();
    }
    if (oldWidget.navStyle != widget.navStyle) {
      // A live style change swaps the shell branch, which recreates the scroll
      // view at offset 0 — on a short panel that scrolls the SELECTED item
      // (Settings, where the picker lives) clean off-screen. Re-centre it.
      _scrollToCurrent();
      if (_ensurePillFade()) {
        // Switched INTO the style — announce where we are, same as a fresh
        // arrival. Remove-then-add so a second switch cannot double-register.
        FocusManager.instance.removeListener(_onFocusMovedForEdge);
        FocusManager.instance.addListener(_onFocusMovedForEdge);
        _showPill();
      } else {
        // Switched AWAY. The controllers are kept — `_ensurePillFade` uses
        // `??=`, so disposing them here would hand a switch back a dead one —
        // but everything that DRIVES them has to stop: nothing renders the
        // capsule now, so a running tween is a ticker per frame for a widget
        // that is not on screen, and the focus listener is a render-object
        // lookup per keypress for an answer nobody reads.
        _pillTimer?.cancel();
        _pillTimer = null;
        FocusManager.instance.removeListener(_onFocusMovedForEdge);
        _pillLabel?.stop();
        _pillGlow?.stop();
        _pillNearEdge.value = false;
        _pillGlow?.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _pillTimer?.cancel();
    FocusManager.instance.removeListener(_onFocusMovedForEdge);
    _pillLabel?.dispose();
    _pillGlow?.dispose();
    _pillNearEdge.dispose();
    _expandController.removeStatusListener(_onExpandStatus);
    for (final node in _focusNodes) {
      node.dispose();
    }
    _expandController.dispose();
    super.dispose();
  }

  /// Called from the parent when DPAD-left lands on the sidebar (and, at the
  /// true root, BACK/Menu — see _onRootPopInvoked in main.dart).
  void requestFocus() {
    if (_focusNodes.isEmpty) return;
    final targetIndex = widget.currentIndex.clamp(0, _focusNodes.length - 1);
    final node = _focusNodes[targetIndex];
    if (node.hasFocus) {
      // Re-entry during the collapse→content handoff: _collapse() has already
      // marked the rail closed while this node still holds real focus (the
      // handoff moves it out 100–400ms later — or never, when the content has
      // nothing focusable). requestFocus() on an already-focused node fires
      // no focus event, so the enter path must run by hand or the press that
      // got us here is silently swallowed.
      _handleFocusChange(targetIndex, true);
      return;
    }
    node.requestFocus();
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

  String get _style => widget.navStyle;

  /// Open width per style — marquee is a typographic overlay, island a
  /// compact capsule; the collapsed width never varies (content inset).
  double get _expandedW {
    switch (_style) {
      case 'ghost':
        return 250;
      case 'island':
        return 216;
      case 'marquee':
        return 320;
      case 'badge':
        return 240;
      default:
        return TvSidebarNav.expandedWidth;
    }
  }

  /// The shell's width at rest. Zero under 'pill' — the capsule is drawn as a
  /// separate overlay, so the shell itself must occupy nothing until it opens
  /// or it would reintroduce the gutter the style just removed.
  double get _collapsedW =>
      _style == 'pill' ? 0.0 : TvSidebarNav.collapsedWidth;

  @override
  Widget build(BuildContext context) {
    // Read ONCE here and captured by the builders below: the shell's builders
    // rerun every frame of the expand tween, so a scope lookup inside one
    // would be a per-frame inherited-widget walk.
    final app = AppThemeScope.of(context);
    // Only the width-bearing shell rebuilds each animation frame; the item list
    // is passed as `child` so it isn't rebuilt during the expand tween.
    final shell = AnimatedBuilder(
      animation: _expand,
      builder: (context, child) {
        final t = _expand.value;
        final width = _collapsedW + (_expandedW - _collapsedW) * t;
        // Non-classic styles skip the liquid-glass pane entirely: their shell
        // is either a plain scrim gradient (ghost/badge: quiet; marquee:
        // heavy, for the big type) or fully transparent (island — the capsule
        // around the item group is the chrome). Same width/expand mechanics.
        if (_style == 'pill') {
          // The Apple TV drawer, to the reference frame: a FLOATING frosted
          // panel with rounded corners and a margin on every side — not a
          // pane growing off the screen edge. Real BackdropFilter blur only
          // on tvOS (an A15 renders it for free; the Android boxes this rail
          // also serves raster at ~720p on GLES2-class GPUs where a per-frame
          // blur is exactly the jank the no-BackdropFilter rule exists for —
          // they get a higher-opacity fill that reads as the same glass over
          // dim content).
          // The item subtree must be MOUNTED at rest even though the shell
          // is zero-wide — its FocusNodes are the door LEFT walks through,
          // and returning a bare SizedBox here unmounted them: the sidebar
          // could never open because there was nothing to focus.
          if (t <= 0.01) return SizedBox(width: width, child: child);
          // The panel is laid out ONCE at its full expanded width and the
          // tween reveals it through an animating clip. Animating the panel's
          // own width re-laid-out and re-painted the whole rail subtree —
          // pucks, labels, glass, a 34px-blur shadow — on every frame, which
          // a Mali box renders at ~10fps whatever is behind it (measured
          // 2026-08-19; the content RepaintBoundary alone moved nothing).
          // Items sit behind their own boundary so per-frame paint is the
          // decoration and the clip, not the list.
          final panel = Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: PlatformUtil.isTvOS
                  ? Color.fromRGBO(38, 38, 42, 0.72 * t)
                  : Color.fromRGBO(32, 32, 36, 0.92 * t),
              borderRadius: app.shape.br(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.07 * t),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45 * t),
                  blurRadius: 34,
                  offset: const Offset(6, 10),
                ),
              ],
            ),
            child: RepaintBoundary(child: child),
          );
          return SizedBox(
            width: width,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: _expandedW,
                maxWidth: _expandedW,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 6, 14),
                  child: PlatformUtil.isTvOS
                      ? ClipRRect(
                          borderRadius: app.shape.br(18),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                            child: panel,
                          ),
                        )
                      : panel,
                ),
              ),
            ),
          );
        }
        if (_style != 'classic') {
          final bool marquee = _style == 'marquee';
          final bool island = _style == 'island';
          return Container(
            width: width,
            decoration: island
                ? null
                : BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: marquee
                          ? [
                              Color.lerp(
                                const Color(0x8C05040A),
                                const Color(0xF705040A),
                                t,
                              )!,
                              Color.lerp(
                                const Color(0x0005040A),
                                const Color(0xE005040A),
                                t,
                              )!,
                              const Color(0x0005040A),
                            ]
                          : [
                              Color.lerp(
                                const Color(0x8C05040A),
                                const Color(0xF005040A),
                                t,
                              )!,
                              Color.lerp(
                                const Color(0x0005040A),
                                const Color(0xB805040A),
                                t,
                              )!,
                              const Color(0x0005040A),
                            ],
                      stops: marquee
                          ? const [0.0, 0.62, 1.0]
                          : const [0.0, 0.55, 1.0],
                    ),
                  ),
            child: child,
          );
        }
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
              duration: _motion.scaled(const Duration(milliseconds: 650)),
              // Left as shipped: plain easeOut is neither of the two token
              // curves, so swapping it would change the legacy look.
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
                              color: tinted(
                                app.shell.navAccent,
                                0.5,
                              ).withValues(alpha: 0.10 * t),
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
                                app.fade(app.core.tx, 0.10 * t),
                                paneMid.withValues(alpha: 0.36 * t),
                                paneDeep.withValues(alpha: 0.46 * t),
                              ],
                              stops: const [0.0, 0.40, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(child: inner ?? const SizedBox.shrink()),
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
                                  app.fade(app.core.tx, 0.0),
                                  app.fade(app.core.tx, 0.10 * t),
                                  app.fade(app.core.tx, 0.02 * t),
                                  app.fade(app.core.tx, 0.0),
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
                              borderRadius: app.shape.br(2),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  app.shell.navFocus.withValues(
                                    alpha: 0.70 * t,
                                  ),
                                  _kRimCyan.withValues(alpha: 0.40 * t),
                                  app.shell.navFocus.withValues(
                                    alpha: 0.15 * t,
                                  ),
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
              // Island hides the branding row — the floating capsule is the
              // whole chrome, and a lone logo above it read as clutter.
              // Pill replaces it with the reference's header: avatar, name,
              // clock.
              if (_style == 'pill') ...[
                _buildPillHeader(app),
                const SizedBox(height: 10),
              ] else if (_style != 'island') ...[
                _buildBranding(),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Centre the icon group when it fits; scroll if a tall menu
                    // ever overflows a short screen (keeps ensureVisible working).
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Padding(
                          // Island runs tighter: the capsule's own padding +
                          // border eat into the 64px rail, and the row's 44px
                          // leading slot must still fit inside (10px outer
                          // padding would overflow every collapsed row).
                          padding: EdgeInsets.symmetric(
                            horizontal: _style == 'island' ? 6 : 10,
                            vertical: 8,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_style == 'island')
                                _IslandCapsule(
                                  expand: _expand,
                                  app: app,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: _buildNavItems(app),
                                  ),
                                )
                              else
                                ..._buildNavItems(app),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.profile != null && widget.onProfileTap != null)
                _buildProfileFooter(app),
            ],
          ),
        ),
      ),
    );

    // Every other style IS the rail; 'pill' is a capsule that names where you
    // are and gets out of the way. The shell above still renders the drawer
    // when it opens — this only adds what stands in for the rail at rest.
    if (_style != 'pill') return shell;
    final pad = MediaQuery.paddingOf(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        shell,
        // Hard into the corner: the safe-area inset and NOTHING else. The
        // capsule is transient, so a comfortable margin only buys it more
        // content to sit on; flush to the edge is where it overlaps least.
        //
        // The `pad` term stays because it is not decoration — the rail's items
        // sit inside a `SafeArea` further down, and this capsule is a sibling
        // of the shell, so without it a TV reporting overscan would clip the
        // capsule against the bezel entirely.
        //
        // Only `left`/`top` are set, which is deliberate: `RenderStack` leaves
        // a child constrained that way UNBOUNDED, so the capsule sizes to its
        // content and paints outside the zero-width shell (hence
        // `Clip.none`). Adding `right` or `width` would tighten it to a stack
        // that is 0px wide at rest and collapse the pill to nothing.
        //
        // `IgnorePointer` because the capsule is a LABEL — LEFT is the only
        // way in, and giving it its own focus would be a second entry point
        // the policy forbids.
        Positioned(
          left: pad.left,
          top: pad.top,
          child: IgnorePointer(
            child: KeyedSubtree(
              key: TvSidebarNav.pillKey,
              child: _buildPill(app),
            ),
          ),
        ),
      ],
    );
  }

  /// The 'pill' style's whole resting state: `‹` plus the current tab's icon,
  /// permanently — widening to name the tab for a second when you arrive.
  ///
  /// The split is the point. The chevron answers "is there a menu?", the icon
  /// answers "where am I?", and both are cheap enough to stay. Only the NAME
  /// is expensive — 150px of it, straight through whatever the page put in its
  /// corner — so only the name is transient.
  ///
  /// Alpha is BAKED into every colour rather than wrapped in an Opacity — a
  /// saveLayer per frame is the one thing a TV cursor cannot afford.
  ///
  Widget _buildPill(AppTheme app) {
    final label = _pillLabel;
    final glow = _pillGlow;
    return AnimatedBuilder(
      // Three drivers, merged so the mark can never be caught half-lit by one
      // while another moves: the drawer's expand, the label's reveal, and the
      // left-edge brighten.
      animation: Listenable.merge([
        _expand,
        if (label != null) label,
        if (glow != null) glow,
      ]),
      builder: (context, _) {
        // Gone by the halfway point of the open: past that the drawer covers
        // this spot, and two names for one tab read as a duplication bug.
        final a = (1.0 - _expand.value * 2).clamp(0.0, 1.0);
        if (a <= 0.01) return const SizedBox.shrink();

        final item = widget.items.isEmpty
            ? null
            : widget.items[widget.currentIndex.clamp(
                0,
                widget.items.length - 1,
              )];
        if (item == null) return const SizedBox.shrink();

        final reveal = label?.value ?? 1.0;
        final lit = glow?.value ?? 0.0;
        final ink = app.core.tx;

        // Transparent by design — no plate, no scrim. The mark is a glyph pair
        // sitting ON the page rather than a bar laid over it, which is what
        // lets it stay permanent without owning the corner. Only the icon gets
        // a container, and only enough of one to read as a control.
        double at(double rest, double near) => (rest + (near - rest) * lit) * a;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The affordance. Dim at rest, brighter the moment focus reaches
            // the column where LEFT would actually open the menu.
            Icon(
              Icons.chevron_left_rounded,
              size: 18,
              color: ink.withValues(alpha: at(0.34, 0.72)),
            ),
            const SizedBox(width: 3),
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ink.withValues(alpha: at(0.07, 0.13)),
                shape: BoxShape.circle,
                border: Border.all(
                  color: ink.withValues(alpha: at(0.08, 0.16)),
                ),
              ),
              child: Icon(
                item.icon,
                size: 16,
                color: ink.withValues(alpha: at(0.72, 0.98)),
              ),
            ),
            // The NAME breathes; the mark above does not. Built only while it
            // is actually revealing — a clipped-to-zero Text still lays out,
            // and it would still be found by anything looking for the label.
            if (reveal > 0.01)
              ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: reveal,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 4),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                        // Rides the reveal so it fades as it narrows, instead
                        // of a full-strength word being sliced in half.
                        color: ink.withValues(alpha: 0.92 * reveal * a),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The nav items as a vertically-centred group. Every tab icon shows on the
  /// resting rail (dimmed when idle, the current one in its accent pill); labels
  /// and section headers fade/slide in only when the rail opens. Centring keeps
  /// the rail balanced rather than top-clustered or a bottom-heavy wall.
  /// [app] is passed in, never read here: this runs inside the width-sensitive
  /// LayoutBuilder, which re-inflates on every frame of the expand tween.
  List<Widget> _buildNavItems(AppTheme app) {
    final widgets = <Widget>[];
    for (int index = 0; index < widget.items.length; index++) {
      final item = widget.items[index];
      final startsSection =
          item.section != null &&
          (index == 0 || widget.items[index - 1].section != item.section);
      // The reference drawer has no category headers — one flat list. Pill
      // follows it exactly; every other style keeps its sections.
      if (startsSection && _style != 'pill') {
        widgets.add(_SectionHeader(item.section!, _expand, app));
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _TvNavItemWidget(
            app: app,
            item: item,
            index: index,
            isSelected: index == widget.currentIndex,
            isFocused: index == _focusedIndex && _hasSidebarFocus,
            expand: _expand,
            accent: app.shell.navAccent,
            accentSoft: app.shell.navFocus,
            focusNode: _focusNodes[index],
            onTap: () => _selectMenuItem(index),
            onKeyEvent: (e) => _handleKeyEvent(index, e),
            labelCurve: _motion.standard,
            style: _style,
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildProfileFooter(AppTheme app) {
    final index = widget.items.length;
    return Padding(
      key: const ValueKey('tv-sidebar-profile'),
      padding: EdgeInsets.fromLTRB(
        _style == 'island' ? 6 : 10,
        4,
        _style == 'island' ? 6 : 10,
        2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeTransition(
            opacity: _expand,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Container(height: 1, color: app.fade(app.core.tx, 0.08)),
            ),
          ),
          _TvProfileItemWidget(
            app: app,
            profile: widget.profile!,
            isFocused: index == _focusedIndex && _hasSidebarFocus,
            expand: _expand,
            focusNode: _focusNodes[index],
            onTap: () => _selectMenuItem(index),
            onKeyEvent: (event) => _handleKeyEvent(index, event),
            style: _style,
          ),
        ],
      ),
    );
  }

  /// The reference drawer's header: avatar disc, name, clock — in place of
  /// the branding row, pill style only.
  Widget _buildPillHeader(AppTheme app) {
    return FadeTransition(
      opacity: _expand,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Image.asset('assets/app_icon.png', fit: BoxFit.contain),
              ),
            ),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Debrify',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                  color: Colors.white,
                ),
              ),
            ),
            _PillClock(),
          ],
        ),
      ),
    );
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

class _TvProfileItemWidget extends StatelessWidget {
  final AppTheme app;
  final UserProfile profile;
  final bool isFocused;
  final Animation<double> expand;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final KeyEventResult Function(KeyEvent) onKeyEvent;
  final String style;

  const _TvProfileItemWidget({
    required this.app,
    required this.profile,
    required this.isFocused,
    required this.expand,
    required this.focusNode,
    required this.onTap,
    required this.onKeyEvent,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (_, event) => onKeyEvent(event),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: expand,
          builder: (context, _) {
            final open = expand.value;
            final whiteFocus =
                isFocused && (style == 'badge' || style == 'pill');
            final collapsedSlot = style == 'island'
                ? TvSidebarNav.collapsedWidth - 12
                : TvSidebarNav.collapsedWidth - 20;
            return Container(
              height: style == 'badge' ? 52 : 46,
              decoration: BoxDecoration(
                color: whiteFocus
                    ? app.core.tx
                    : isFocused
                    ? app.shell.navFocus.withValues(alpha: 0.22)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: isFocused && !whiteFocus
                    ? Border.all(color: app.fade(app.core.tx, 0.55), width: 1.5)
                    : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: collapsedSlot,
                    child: Center(
                      child: Container(
                        width: 34,
                        height: 34,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: whiteFocus
                                ? app.shell.railInk.withValues(alpha: 0.15)
                                : app.fade(app.core.tx, isFocused ? 0.8 : 0.16),
                          ),
                        ),
                        child: ProfileAvatarView(
                          profileId: profile.id,
                          avatarKey: profile.avatarKey,
                          role: profile.role,
                          name: profile.name,
                          focused: isFocused,
                        ),
                      ),
                    ),
                  ),
                  if (open > 0.01)
                    Expanded(
                      child: ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: open,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      profile.name,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.clip,
                                      style: TextStyle(
                                        color: whiteFocus
                                            ? app.shell.railInk
                                            : app.core.tx,
                                        fontSize: style == 'marquee'
                                            ? 17
                                            : 13.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      profile.isAdmin ? 'Admin' : 'Profile',
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: whiteFocus
                                            ? app.shell.railInk.withValues(
                                                alpha: 0.62,
                                              )
                                            : app.fade(app.core.tx, 0.48),
                                        fontSize: 9.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: whiteFocus
                                    ? app.shell.railInk.withValues(alpha: 0.7)
                                    : app.fade(app.core.tx, 0.48),
                              ),
                              const SizedBox(width: 10),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
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
  /// Passed down, never looked up here — see [TvSidebarNavState._buildNavItems].
  final AppTheme app;

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

  /// The theme's standard curve for the label cascade. Passed down for the same
  /// reason [app] is — see [TvSidebarNavState._buildNavItems].
  final Curve labelCurve;

  /// Visual style (see [TvSidebarNav.navStyle]) — visuals only; the Focus /
  /// key wrapper is shared by every style.
  final String style;

  const _TvNavItemWidget({
    required this.app,
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
    required this.labelCurve,
    this.style = 'classic',
  });

  double get _rowH {
    switch (style) {
      case 'marquee':
        return 50;
      case 'badge':
        return 52;
      case 'pill':
        // The reference's roomy pitch — the drawer is a short flat list and
        // can afford it.
        return 46;
      default:
        return 42;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    switch (style) {
      case 'ghost':
        body = _ghostBody(marquee: false);
        break;
      case 'marquee':
        body = _ghostBody(marquee: true);
        break;
      case 'island':
        body = _islandBody();
        break;
      case 'badge':
        body = _badgeBody();
        break;
      case 'pill':
        body = _appleBody();
        break;
      default:
        body = _classicBody();
    }
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) => onKeyEvent(event),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(height: _rowH, child: body),
      ),
    );
  }

  /// GHOST (and MARQUEE, which is ghost-at-rest with big type when open):
  /// no chrome — the selected tab is a solid white coin, a focused row gets a
  /// white ring; open, labels ride the shared stagger (marquee: oversized).
  Widget _ghostBody({required bool marquee}) {
    return AnimatedBuilder(
      animation: expand,
      builder: (context, _) {
        final iconColor = isSelected
            ? app.shell.railInk
            : isFocused
            ? app.core.tx
            : app.fade(app.core.tx, 0.45);
        return Row(
          children: [
            SizedBox(
              width: TvSidebarNav.collapsedWidth - 20,
              child: Center(
                // Ring = FOCUS, coin = CURRENT TAB — independent, so the
                // common entry case (focus lands on the current tab) still
                // shows where focus is: a ring around the coin.
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: isFocused
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: app.fade(app.core.tx, 0.9),
                            width: 2,
                          ),
                        )
                      : null,
                  child: Center(
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: isSelected
                          ? BoxDecoration(
                              shape: BoxShape.circle,
                              color: app.core.tx,
                              boxShadow: [
                                BoxShadow(
                                  color: app.fade(app.core.tx, 0.30),
                                  blurRadius: 18,
                                ),
                              ],
                            )
                          : null,
                      child: Center(
                        child: Icon(item.icon, size: 19, color: iconColor),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ClipRect(
                child: _StaggeredLabel(
                  expand: expand,
                  index: index,
                  curve: labelCurve,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      color: isFocused
                          ? app.core.tx
                          : isSelected
                          ? app.fade(app.core.tx, 0.95)
                          : app.fade(app.core.tx, marquee ? 0.4 : 0.55),
                      fontSize: marquee ? (isFocused ? 23 : 18) : 14,
                      fontWeight: (isFocused || isSelected)
                          ? FontWeight.w800
                          : FontWeight.w600,
                      letterSpacing: marquee ? -0.3 : 0.1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// PILL: the Apple TV reference row, exactly. Focused — a full white
  /// stadium with black icon and label (their focus idiom does not lift or
  /// ring; it floods). Current-but-unfocused — a soft grey stadium. Idle —
  /// bare icon and label on the glass. No accents, no gradients, no glow:
  /// the reference's whole palette is white at three strengths.
  Widget _appleBody() {
    return AnimatedBuilder(
      animation: expand,
      builder: (context, _) {
        final ink = isFocused
            ? Colors.black
            : Colors.white.withValues(alpha: isSelected ? 0.95 : 0.80);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Container(
            decoration: BoxDecoration(
              color: isFocused
                  ? Colors.white
                  : isSelected
                  ? Colors.white.withValues(alpha: 0.14)
                  : null,
              borderRadius: app.shape.br(23),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(item.icon, size: 17, color: ink),
                const SizedBox(width: 11),
                Expanded(
                  child: ClipRect(
                    child: _StaggeredLabel(
                      expand: expand,
                      index: index,
                      curve: labelCurve,
                      child: Text(
                        item.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          color: ink,
                          fontSize: 14.5,
                          fontWeight: isFocused
                              ? FontWeight.w700
                              : FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// ISLAND: inside the floating capsule. Collapsed, the selected tab is a
  /// white coin; open, the focused row becomes a white pill (ink icon/text)
  /// and the selected row faint glass.
  Widget _islandBody() {
    return AnimatedBuilder(
      animation: expand,
      builder: (context, _) {
        final t = expand.value;
        final open = t > 0.5;
        final iconColor = open
            ? (isFocused
                  ? app.shell.railInk
                  : isSelected
                  ? app.fade(app.core.tx, 0.95)
                  : app.fade(app.core.tx, 0.5))
            : (isSelected ? app.shell.railInk : app.fade(app.core.tx, 0.5));
        return Stack(
          children: [
            // Collapsed coin (dissolves as the capsule opens).
            Positioned(
              left: 4,
              top: 3,
              child: Builder(
                builder: (_) {
                  final k = 1.0 - t;
                  if (k < 0.01 || !isSelected) {
                    return const SizedBox(width: 36, height: 36);
                  }
                  return Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: app.fade(app.core.tx, k),
                    ),
                  );
                },
              ),
            ),
            // Open pill.
            if (t > 0.01 && (isFocused || isSelected))
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    borderRadius: app.shape.br(14),
                    color: isFocused
                        ? app.fade(app.core.tx, t)
                        : app.fade(app.core.tx, 0.10 * t),
                  ),
                ),
              ),
            Row(
              children: [
                SizedBox(
                  width: TvSidebarNav.collapsedWidth - 20,
                  child: Center(
                    child: Icon(item.icon, size: 19, color: iconColor),
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    child: _StaggeredLabel(
                      expand: expand,
                      index: index,
                      curve: labelCurve,
                      child: Text(
                        item.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          color: isFocused
                              ? app.shell.railInk
                              : isSelected
                              ? app.fade(app.core.tx, 0.95)
                              : app.fade(app.core.tx, 0.55),
                          fontSize: 13,
                          fontWeight: (isFocused || isSelected)
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// BADGE: Google-TV grammar — every icon carries a tiny label beneath it at
  /// rest, the selected tab in a white squircle. Open, rows become pills: the
  /// selected one solid white (it "wears its name"), a focused row ringed.
  Widget _badgeBody() {
    return AnimatedBuilder(
      animation: expand,
      builder: (context, _) {
        final t = expand.value;
        final k = 1.0 - t;
        final open = t > 0.5;
        final iconColor = open
            ? (isSelected
                  ? app.shell.railInk
                  : isFocused
                  ? app.core.tx
                  : app.fade(app.core.tx, 0.5))
            : (isSelected ? app.shell.railInk : app.fade(app.core.tx, 0.48));
        return Stack(
          children: [
            // Collapsed: white squircle behind the selected icon.
            if (k > 0.01 && isSelected)
              Positioned(
                left: 3,
                top: 0,
                child: Container(
                  width: 38,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: app.shape.br(12),
                    color: app.fade(app.core.tx, k),
                  ),
                ),
              ),
            // Collapsed: tiny label under EVERY icon.
            if (k > 0.01)
              Positioned(
                left: 0,
                bottom: 2,
                width: TvSidebarNav.collapsedWidth - 20,
                child: Text(
                  item.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: app.fade(app.core.tx, (isSelected ? 0.95 : 0.5) * k),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            // Open: the row pill.
            if (t > 0.01 && (isFocused || isSelected))
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
                  decoration: BoxDecoration(
                    borderRadius: app.shape.br(16),
                    color: isSelected ? app.fade(app.core.tx, t) : null,
                    border: isFocused
                        ? Border.all(
                            color: app.fade(app.core.tx, 0.9 * t),
                            width: 1.6,
                          )
                        : null,
                  ),
                ),
              ),
            // Icon zone glides from the top 38px (label beneath, collapsed)
            // to the full row height (label beside, open) — no end-snap.
            Positioned(
              left: 0,
              top: 0,
              height: 38 + (_rowH - 38) * t,
              child: SizedBox(
                width: TvSidebarNav.collapsedWidth - 20,
                child: Center(
                  child: Icon(item.icon, size: 19, color: iconColor),
                ),
              ),
            ),
            Positioned(
              left: TvSidebarNav.collapsedWidth - 20,
              right: 0,
              top: 0,
              bottom: 0,
              child: ClipRect(
                child: _StaggeredLabel(
                  expand: expand,
                  index: index,
                  curve: labelCurve,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: isSelected
                            ? app.shell.railInk
                            : isFocused
                            ? app.core.tx
                            : app.fade(app.core.tx, 0.55),
                        fontSize: 13,
                        fontWeight: (isFocused || isSelected)
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// CLASSIC — the liquid-glass original, unchanged.
  Widget _classicBody() {
    final bool active = isFocused || isSelected;
    final Color iconColor = isFocused
        ? app.core.tx
        : isSelected
        // Light lavender: legible both on the lit puck (collapsed) and the
        // faint glass pill (expanded).
        ? const Color(0xFFD8CDFF)
        : app.fade(app.core.tx, 0.42);
    final Color labelColor = isFocused
        ? app.core.tx
        : isSelected
        ? app.fade(app.core.tx, 0.94)
        : app.fade(app.core.tx, 0.5);

    // Highlights snap instantly as focus moves between items (no per-move
    // animation — animated blur is what made item-to-item navigation
    // sluggish on the weak TV GPU); glows are static, painted when focus
    // lands. Only the puck↔pill cross-dissolve animates, riding the shared
    // 200ms expand with alphas baked into the colors.
    return Stack(
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
                            app.fade(app.core.tx, 0.10 * k),
                            app.fade(app.core.tx, 0.03 * k),
                          ],
                  ),
                  border: Border.all(
                    color: isSelected
                        ? accentSoft.withValues(alpha: 0.55 * k)
                        : app.fade(app.core.tx, 0.10 * k),
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
                    borderRadius: app.shape.br(21),
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
                      borderRadius: app.shape.br(20),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF241B4D).withValues(alpha: 0.94 * t),
                          const Color(0xFF1A1338).withValues(alpha: 0.94 * t),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return Container(
                decoration: BoxDecoration(
                  borderRadius: app.shape.br(21),
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      app.fade(app.core.tx, 0.08 * t),
                      app.fade(app.core.tx, 0.02 * t),
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
              child: Center(child: Icon(item.icon, color: iconColor, size: 20)),
            ),
            Expanded(
              child: ClipRect(
                child: _StaggeredLabel(
                  expand: expand,
                  index: index,
                  curve: labelCurve,
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
                            borderRadius: app.shape.br(5),
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
    );
  }
}

/// ISLAND's floating glass capsule around the item group: detached from the
/// edge, vertically centred (the host Column centres it), glass fill + faint
/// rim + drop shadow. Alphas ride the expand so the open pane reads slightly
/// denser. No BackdropFilter (banned on TV) — the ambient art behind the rail
/// already makes translucency read as glass.
class _IslandCapsule extends StatelessWidget {
  final Animation<double> expand;
  final Widget child;

  /// Passed down, never looked up here — see [TvSidebarNavState._buildNavItems].
  final AppTheme app;

  const _IslandCapsule({
    required this.expand,
    required this.child,
    required this.app,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: expand,
      child: child,
      builder: (context, kid) {
        final t = expand.value;
        return Container(
          clipBehavior: Clip.antiAlias,
          // 64 rail − 6×2 outer padding − 2×2 this padding − 1×2 border
          // = 46px inner: the 44px leading slot fits with a hair to spare.
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24 - 6 * t),
            color: Color.lerp(
              // Exact eighth-bit fractions — see tv_ambient_art_stage.
              app.fade(app.shell.ink, 0xA3 / 0xFF), // was 0xA30D0B1A
              app.fade(app.shell.ink, 0xC9 / 0xFF), // was 0xC90D0B1A
              t,
            ),
            border: Border.all(color: app.fade(app.core.tx, 0.09)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x8C000000),
                blurRadius: 22,
                offset: Offset(6, 8),
              ),
            ],
          ),
          child: kid,
        );
      },
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

  /// The theme's standard curve, passed down rather than looked up — see
  /// [TvSidebarNavState._buildNavItems].
  final Curve curve;

  final Widget child;

  const _StaggeredLabel({
    required this.expand,
    required this.index,
    required this.curve,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: expand,
      // Later rows start later; cap the offset so a long menu's tail doesn't
      // lag the 200ms expand.
      curve: Interval((index * 0.055).clamp(0.0, 0.45), 1.0, curve: curve),
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

  /// Passed down, never looked up here — see [TvSidebarNavState._buildNavItems].
  final AppTheme app;

  const _SectionHeader(this.text, this.expand, this.app);

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
                color: app.fade(app.core.tx, 0.4),
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

/// The header clock — the reference shows local time, live. One timer per
/// mounted drawer, aligned to the minute so it ticks exactly when the label
/// would change.
class _PillClock extends StatefulWidget {
  @override
  State<_PillClock> createState() => _PillClockState();
}

class _PillClockState extends State<_PillClock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  void _arm() {
    final now = DateTime.now();
    _tick = Timer(
      Duration(seconds: 60 - now.second, milliseconds: -now.millisecond),
      () {
        if (!mounted) return;
        setState(() {});
        _arm();
      },
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = TimeOfDay.now();
    return Text(
      MaterialLocalizations.of(context).formatTimeOfDay(now),
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.85),
      ),
    );
  }
}

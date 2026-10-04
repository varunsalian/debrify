import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_constants_state.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_metrics.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/utils/spotlight_interaction_policy.dart';
import 'package:debrify/widgets/home/midnight_rain_background.dart';
import 'package:debrify/widgets/home/moonlit_ocean_background.dart';
import 'package:debrify/widgets/home/snowy_mountain_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

// ── paint ──────────────────────────────────────────────────────────────

class SpotlightBoardRootLayout {
  final SpotlightBoardDependencies _deps;
  SpotlightBoardRootLayout(this._deps);
  SpotlightBoardWidgetView get view => _deps.view;
  SpotlightBoardOwners get _owners => _deps.owners;
  SpotlightBoardSections get _sections => _deps.sections;
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) => _sections.focus.onKey(e),
      // The FULL parallax (spring, velocity tilt, travelling glare) on
      // Android TV — the same opt-in the detail Showcase carries. The board
      // originally stayed on the lite body because a Mali box couldn't
      // afford it, but that budget was spent on oversized card textures:
      // with cards decoding at display size (2026-08-19) the box renders
      // the rich cursor smoothly, and only two cards ever animate per step.
      // The board's walk already notes travel direction for the lean.
      child: ParallaxRichScope(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final m = SpotlightBoardMetrics(
              constraints.maxWidth,
              dpad: view.dpad,
            );
            final large =
                view.largeScreenInteractions &&
                !view.dpad &&
                spotlightUsesRichCards(
                  viewport: MediaQuery.sizeOf(context),
                  platform: Theme.of(context).platform,
                  availableWidth: constraints.maxWidth,
                );
            final selectionViewport = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            if (_owners.selection.selectionViewport != selectionViewport) {
              _owners.selection.selectionViewport = selectionViewport;
              _owners.selection.scrollRowId = null;
              _sections.selection.queueScrollSelection();
            }
            if (large != _owners.selection.largeCardInteractions) {
              _owners.selection.largeCardInteractions = large;
              _owners.selection.scrollingSources.clear();
              _sections.selection.queueScrollSelection();
            }
            // The hero is measured against the board's real height, so it is
            // the same share of the screen on every panel.
            final viewport = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height;
            return _sections.rootLayout.board(
              m,
              viewport *
                  (m.compact
                      ? SpotlightBoardConstantsState.heroFractionCompact
                      : SpotlightBoardConstantsState.heroFraction),
            );
          },
        ),
      ),
    );
  }

  Widget board(SpotlightBoardMetrics m, double heroH) {
    _owners.scroll.lastMetrics = m;
    _owners.scroll.heroBandH = heroH;
    final app = AppThemeScope.of(_deps.context());
    final ground = view.groundOf(app);
    // One key per shelf, by rail IDENTITY (see [SpotlightShelf.id]).
    String shelfKey(int i) {
      final s = view.sections[i];
      return 'shelf-${s.id ?? 'pos-$i'}';
    }

    // BUILDER, not children — and no Column around the shelves. A Column is
    // one child, so it defeated the vertical list's laziness: all 11-13
    // shelves (and each one's first screenful of cards) built, decoded and
    // uploaded textures in the first frames of every mount — and the shell
    // remounts Home per tab switch, so every tab return paid the full-board
    // texture burst again (measured on the Mi Box: ~8s of 100-200ms raster
    // frames). Lazily built, only the on-screen shelves pay at mount and the
    // rest stream in with the scroll — texture uploads paced for free.
    //
    // cacheExtent is one TV viewport rather than the 250 default: DOWN moves
    // focus one row at a time via requestFocus, which needs the target
    // shelf's nodes ATTACHED — a viewport of lead keeps the next rows built
    // ahead of the cursor without resurrecting the build-everything burst.
    final list = ListView.builder(
      controller: _owners.scroll.scroll,
      padding: EdgeInsets.zero,
      cacheExtent: 600,
      itemCount: view.sections.length + 2,
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        if (key.value == 'spotlight-hero-band') return 0;
        if (key.value == 'spotlight-tail') return view.sections.length + 1;
        for (var i = 0; i < view.sections.length; i++) {
          if (shelfKey(i) == key.value) return i + 1;
        }
        return null;
      },
      itemBuilder: (context, index) {
        // Laid out 88 short so the first shelf sits over the hero's lower
        // edge; the band overflows to the hero's full height so its contents
        // lay out against the same geometry the pinned art is drawn in. On
        // wide this band carries only the hero's FOREGROUND (identity, dots,
        // pointer surface, focus node) — the picture itself is pinned behind
        // the list in the Stack below. Compact has no overlap and keeps art
        // and identity together in flow — the hero fades to ground and the
        // rows follow.
        //
        // The hero is drawn 88 SHORTER than its visual height rather than
        // the shelves being transformed up over it. A `Transform` moves
        // paint and hit-testing but leaves the ListView's extent alone, so
        // the overlap reappears as a phantom 88px gap at the bottom and
        // the page overscrolls past its own last shelf. Sizing the hero
        // box is the version the scroll extent agrees with.
        if (index == 0) {
          if (view.shelvesOnly) {
            return const SizedBox.shrink(key: ValueKey('spotlight-hero-band'));
          }
          return SizedBox(
            key: const ValueKey('spotlight-hero-band'),
            height:
                heroH *
                (1 -
                    (m.compact
                        ? 0
                        : SpotlightBoardConstantsState.shelfOverlapFraction)),
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: heroH,
              child: SizedBox(
                height: heroH,
                child: _sections.compactHero.hero(m, heroH),
              ),
            ),
          );
        }
        if (index == view.sections.length + 1) {
          return const SizedBox(key: ValueKey('spotlight-tail'), height: 24);
        }
        final i = index - 1;
        return KeyedSubtree(
          key: ValueKey(shelfKey(i)),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (_owners.selection.largeCardInteractions &&
                  notification.metrics.axis == Axis.horizontal &&
                  ((notification is UserScrollNotification &&
                          notification.direction != ScrollDirection.idle) ||
                      (notification is ScrollStartNotification &&
                          notification.dragDetails != null))) {
                _owners.selection.scrollRowId = view.sections[i].id ?? i;
              }
              if (notification is ScrollUpdateNotification &&
                  view.shelvesOnly &&
                  notification.metrics.axis == Axis.horizontal &&
                  notification.metrics.extentAfter < 400) {
                view.onLoadMoreRow?.call(i);
              }
              return false;
            },
            child: _sections.shelves.shelf(i, m),
          ),
        );
      },
    );
    // A board reload can SHRINK the list under a parked scroll. The framework
    // clamps the offset during layout WITHOUT notifying the controller, so
    // the veil and the scrolled-away trailer gate would keep acting on an
    // offset the list no longer has — a hero veiled opaque with nothing left
    // to scroll back from. Notify only the veil; extent estimates also change
    // as differently sized shelves enter the lazy viewport during a fling.
    // Depth 0 excludes the horizontal shelf lists.
    final content = NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        if (n.depth == 0) {
          // Always re-run the crossing detector — a clamped offset never
          // notifies the controller (cheap: no rebuild of its own).
          _sections.selection.onBoardScrolled();
          // The controller already drives normal scrolling. Metrics changes
          // cover silent layout corrections without rebuilding the shelves.
          if (!view.dpad &&
              _deps.mounted() &&
              n.metrics.maxScrollExtent != _owners.scroll.lastMaxExtent) {
            _owners.scroll.lastMaxExtent = n.metrics.maxScrollExtent;
            _owners.scroll.veilMetricsRevision.value++;
          }
        }
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _sections.selection.onCardScroll,
        child: list,
      ),
    );
    if (!view.paintBackground) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ground, view.groundLowOf(app)],
        ),
      ),
      // Wide pins the picture BEHIND the scroll view. A Scrollable claims
      // every pointer in its viewport, which is fine here because nothing in
      // the backdrop is interactive — the hero's tap/swipe surface and the
      // tappable dots ride in the list with the identity.
      child: (m.compact || view.shelvesOnly) && !view.animationsEnabled
          ? content
          : Stack(
              fit: StackFit.expand,
              children: [
                if (view.animationsEnabled)
                  Positioned.fill(
                    child: switch (view.animationStyle) {
                      'moonlit_ocean' => MoonlitOceanBackground(
                        lowPower: view.dpad,
                      ),
                      'midnight_rain' => MidnightRainBackground(
                        lowPower: view.dpad,
                      ),
                      _ => SnowyMountainBackground(lowPower: view.dpad),
                    },
                  ),
                if (!m.compact && !view.shelvesOnly)
                  // Its own layer: the backdrop is a full-screen image under
                  // two full-screen gradients — the most expensive paint on
                  // the page. Isolated, a board rebuild (row moves, the
                  // trailer's rolling flips) re-composites a cached texture
                  // instead of re-rasterising all three.
                  RepaintBoundary(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        height: heroH,
                        child: _sections.wideHero.heroBackdrop(heroH),
                      ),
                    ),
                  ),
                content,
                if (_owners.navigation.loadingMoreShelves)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 20,
                    child: IgnorePointer(
                      child: Center(
                        child: DecoratedBox(
                          key: const ValueKey('spotlight-loading-more-shelves'),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 9),
                                Text(
                                  'Loading more',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

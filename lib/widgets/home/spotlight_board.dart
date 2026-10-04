import 'dart:async';
import 'dart:math' show max;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_card.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_constants_state.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_logo_or_title.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_metrics.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_types.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_hero_open_pill.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_shelf_title_link.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/utils/spotlight_interaction_policy.dart';
import 'package:debrify/widgets/home/home_row_focus.dart';
import 'package:debrify/widgets/home/midnight_rain_background.dart';
import 'package:debrify/widgets/home/moonlit_ocean_background.dart';
import 'package:debrify/widgets/home/row_tag_pill.dart';
import 'package:debrify/widgets/home/snowy_mountain_background.dart';
import 'package:debrify/widgets/metadata_presentation_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

export 'package:debrify/features/spotlight_board/presentation/spotlight_board_types.dart'
    show SpotlightCard, SpotlightCardShape, SpotlightShelf;

/// **Spotlight** — the tvOS Home idiom.
///
/// The hero art is a **pinned full-screen backdrop** the shelves ride over —
/// the Apple TV app's grammar. Going DOWN does not scroll the picture away
/// (it used to be the first item of the scroll, which sent a hard band-edge
/// sliding up the screen — the one obviously-not-Apple frame this board
/// produced). Instead the shelves and the hero's identity translate up while
/// the art stays put, and a ground-coloured veil rises with the scroll so the
/// picture dims toward the page ground and the rows stay legible whatever the
/// theme. Only the PICTURE is pinned: identity, dots and the pointer surface
/// ride in the scroll, because text that slides away with the rows is the
/// reference behaviour.
///
/// Compact keeps the in-flow hero (the Apple *phone* measure): its art stops
/// at ~64% of the board and fades into the ground, so there is no band edge
/// to pin away and nothing under the fold to dim.
///
/// The hero is also **a focusable row**: LEFT/RIGHT page it, dots show
/// position, and it parks where you left it. That is the piece that changes
/// Home's focus topology rather than its paint — the other boards take their
/// identity from whatever is focused *below* them and have no cursor of their
/// own.
class SpotlightBoard extends StatefulWidget {
  /// The hero reel. Capped by the caller; parked position is restored by ITEM
  /// ID rather than index, because the rail list re-orders as tracker data
  /// arrives.
  final List<StremioMeta> hero;

  /// The shelves, in order.
  ///
  /// NOT `List<CatalogSection>` any more: Continue Watching and the favourites
  /// rails are neither that shape nor that card — they carry progress, a
  /// context menu, and entries that are not `StremioMeta` at all. A descriptor
  /// lets the host say "here is a row of things and what to do with them"
  /// without the board learning about six data sources.
  final List<SpotlightShelf> sections;

  /// The hero's own node. Registered with the host so sidebar re-entry and
  /// dead-focus reclaim can land on it.
  final FocusNode heroNode;

  /// Ask the host for another page of [row]'s items. Called when focus nears
  /// the end of a shelf — without it only each shelf's FIRST page is ever
  /// reachable, because this board owns its own scroll and the host's
  /// scroll-driven pagination never fires.
  final void Function(int row)? onLoadMoreRow;

  /// Ask the host for another batch of shelves, when DOWN runs out of them.
  ///
  /// Returns whether at least one shelf was appended. Spotlight awaits this
  /// result so the DOWN that started the fetch can finish its move instead of
  /// being swallowed at the old end of the board.
  final Future<bool> Function()? onLoadMoreShelves;

  /// The host has already reserved rows that can still arrive independently.
  /// Keep a DPAD-down pending if requesting another batch cannot start yet.
  final bool pendingShelves;

  /// The hero has been resting on [item] long enough to be worth a trailer.
  ///
  /// The board owns the CADENCE; the host owns the video. That split is why
  /// the two cannot fight: there is one timer, here, and the host is told when
  /// rather than deciding for itself.
  final void Function(StremioMeta item)? onDwell;

  /// Paints over the hero while a trailer is playing. Null when the host has
  /// no trailer to show, which is also what reduced motion and the
  /// `home_hero_trailer_enabled` pref produce.
  final Widget? trailer;

  /// Off when the user has disabled hero trailers, or under reduced motion.
  /// The reel still advances — the cadence is the layout, the video is not.
  final bool trailersEnabled;

  /// Tear the trailer down. Called on every exit from the rolling state —
  /// advancing, paging by hand, and losing focus — because a video that
  /// outlives the title it was resolved for is worse than no video.
  final VoidCallback? onTrailerStop;

  /// The addon behind the hero reel, which is the shelf it was taken from.
  final StremioAddon? heroAddon;

  /// Opens the hero. Separate from a shelf's own opener because the hero is
  /// its own row, not a member of one.
  final void Function(StremioMeta, StremioAddon) onHeroOpen;

  /// Published so the shell can light the room with the focused title's
  /// colour, exactly as the other stage layouts do.
  final void Function(String? art, Color? tint)? onAmbient;

  /// The INPUT axis, distinct from size: true on a television, where the
  /// remote drives everything and the cadence is armed by hero focus. False
  /// on phones, tablets and desktop — the hero advances on its own clock,
  /// pages on swipe and dot taps, and (under 600 wide) the whole board takes
  /// the compact presentation. Width never implies input: a narrow TV must
  /// stay a TV.
  final bool dpad;

  /// Home-card presentation preference. When false, cards keep their artwork,
  /// context metadata and playback state but omit title and rating text.
  final bool showCardTitlesAndRatings;
  final bool expandFocusedCard;
  final double cardTrailerVolume;
  final bool shelvesOnly;
  final bool paintBackground;
  final bool animationsEnabled;
  final String animationStyle;
  final bool forceCardParallax;
  final bool largeScreenInteractions;
  final VoidCallback? onExitTop;

  const SpotlightBoard({
    super.key,
    required this.hero,
    required this.sections,
    required this.heroNode,
    required this.onHeroOpen,
    required this.heroAddon,
    this.onLoadMoreRow,
    this.onLoadMoreShelves,
    this.pendingShelves = false,
    this.onDwell,
    this.onTrailerStop,
    this.trailer,
    this.trailersEnabled = true,
    this.onAmbient,
    this.dpad = true,
    this.showCardTitlesAndRatings = true,
    this.expandFocusedCard = false,
    this.cardTrailerVolume = 0,
    this.shelvesOnly = false,
    this.paintBackground = true,
    this.animationsEnabled = false,
    this.animationStyle = 'snowy_mountain',
    this.forceCardParallax = false,
    this.largeScreenInteractions = false,
    this.onExitTop,
  });

  /// The scrolled ground, taken from the THEME.
  ///
  /// It was `0xFF1B1C1C`/`0xFF1F1D1C` — measured off the reference screenshots
  /// at every gutter of a scrolled frame, and hardcoded so the Apple look was
  /// the Apple look whatever theme was selected.
  ///
  /// That stopped being defensible once tokens became editable: this was the
  /// one surface that ignored the Background setting, so changing it moved the
  /// whole app EXCEPT Home, with nothing on screen to explain why. The value
  /// moved into the Look — whose ground has since been re-chosen twice on
  /// real panels (true black, then the palette's Deep Navy; the story lives
  /// on `PremiumLooks.spotlight`) — and this getter simply follows whatever
  /// the active theme says.
  static Color groundOf(AppTheme app) => app.home.bg;

  /// The gradient's lower stop. The reference drifts a few levels lighter down
  /// the page; derived rather than fixed so it drifts from whatever the ground
  /// now is.
  ///
  /// **Flat on Android TV**, where the drift renders as banding rather than as
  /// a drift.
  ///
  /// It is about three 8-bit levels spread over the full screen height — which
  /// is the most fragile thing you can hand that pipeline. Those boxes raster
  /// at ~720p on GLES2-class hardware and let the TV's scaler upscale, and the
  /// Flutter surface is TRANSLUCENT so the underlay trailer can show through;
  /// three levels through a low-res upscale and a blend become wide contour
  /// bands. Apple TV has neither constraint and draws it as intended.
  ///
  /// Returning the ground itself rather than skipping the gradient keeps one
  /// code path: a two-stop gradient between identical colours IS a flat fill.
  /// The drift is below the threshold anyone notices when it works, so nothing
  /// is lost where it is dropped.
  static Color groundLowOf(AppTheme app) => PlatformUtil.isAndroidTvCached
      ? app.home.bg
      : Color.lerp(app.home.bg, app.core.tx, 0.015)!;

  /// Above this, the backdrop's left third is too busy for text and the
  /// identity stack flips to the right edge. Without it, text lands on a face
  /// roughly a third of the time — metahub backdrops are frame grabs, not
  /// editorial stills composed for a caption.
  static const double leftThirdBusy = 0.32;

  @override
  State<SpotlightBoard> createState() => SpotlightBoardState();
}

class SpotlightBoardState extends State<SpotlightBoard>
    with MetadataPresentationMixin<SpotlightBoard>
    implements SpotlightBoardWidgetView {
  @override
  bool get prioritizeMetadata => _sections.heroArt.prioritizeMetadata;

  @override
  StremioMeta? get originalMetadata => _sections.heroArt.originalMetadata;

  @override
  void onMetadataPresentationChanged() =>
      _sections.heroArt.onMetadataPresentationChanged();

  @override
  void onMetadataPolicyChanged() => _sections.heroArt.onMetadataPolicyChanged();

  @visibleForTesting
  ImageProvider heroWarmupProvider(String url) =>
      _sections.heroArt.heroWarmupProvider(url);

  /// The id of the slide currently SHOWING — the host's suppression snapshot
  /// reads this at content-playback launch, because its own bookkeeping only
  /// knows the last *dwelled* item and playback can start before any dwell.
  String? get currentHeroId => _sections.heroArt.currentHeroId;

  @override
  void initState() {
    super.initState();
    _owners.hero.heroId = widget.hero.isNotEmpty ? widget.hero.first.id : null;
    widget.heroNode.addListener(_sections.cadence.onHeroFocus);
    _owners.scroll.scroll.addListener(_sections.selection.onBoardScrolled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sections.ambient.probe();
      _sections.cadence.restartCadence();
      _sections.heroWarmup.preloadHeroes();
    });
  }

  @override
  void didUpdateWidget(SpotlightBoard old) {
    super.didUpdateWidget(old);
    _sections.movement.finishProgressiveDown();
    if (widget.dpad &&
        PlatformUtil.isAndroidTvCached &&
        _owners.scroll.lastMetrics != null) {
      for (final section in old.sections) {
        if (section.id == null || !section.nodes.any((node) => node.hasFocus))
          continue;
        preserveHomeInsertionAnchor(
          scroll: _owners.scroll.scroll,
          previous: [for (final s in old.sections) s.id ?? ''],
          next: [for (final s in widget.sections) s.id ?? ''],
          anchor: section.id!,
          extentOf: (id) => _shelfExtent(
            widget.sections.firstWhere((s) => s.id == id),
            _owners.scroll.lastMetrics!,
          ),
        );
        break;
      }
    }
    if (old.hero.length != widget.hero.length ||
        List.generate(
          widget.hero.length,
          (i) => i,
        ).any((i) => !identical(old.hero[i], widget.hero[i]))) {
      _sections.heroWarmup.preloadHeroes();
    }
    // The reel can change under us as sections load. Keep the parked item if
    // it is still present; otherwise fall back to the head rather than to a
    // stale index pointing at a different title.
    // The host can hand us a different node across a rebuild; without moving
    // the listener the old node keeps one forever and the new one has none.
    if (old.heroNode != widget.heroNode) {
      old.heroNode.removeListener(_sections.cadence.onHeroFocus);
      widget.heroNode.addListener(_sections.cadence.onHeroFocus);
    }
    // The trailer pref flipped: rebuild the cadence from scratch. Disable
    // must also clear a stale `_rolling` (or nothing ever re-arms — the
    // reconcile below skips while rolling), and enable must arm a clock that
    // has nothing else to wake it.
    if (old.trailersEnabled != widget.trailersEnabled) {
      _sections.cadence.restartCadence();
    }
    if (_owners.hero.heroId != null &&
        !widget.hero.any((m) => m.id == _owners.hero.heroId)) {
      // The title we were on is gone. Tear the trailer down FIRST: it was
      // resolved for that title, and leaving it rolling paints it over the new
      // head until the 20s cap expires.
      _sections.cadence.stopRolling();
      _owners.hero.heroId = widget.hero.isNotEmpty
          ? widget.hero.first.id
          : null;
      _sections.cadence.restartCadence();
    } else if (_owners.hero.cadence == null && !_owners.hero.rolling) {
      // Reconcile for BOTH inputs: the host often enables trailers (the
      // pref read lands) or grows the reel AFTER first build, with the
      // parked id intact — the branch above never runs then, and without
      // this the dwell clock would simply never start. _restartCadence
      // applies its own gates (focus on DPAD, pref, dwell callback), so an
      // uncalled-for restart is a no-op, not a stolen cadence.
      _sections.cadence.restartCadence();
    }
    // The cursor bookkeeping is positional, but tracker rows FRONT-INSERT:
    // after `rows=9to11` every `_col[i]` describes a different shelf than it
    // was recorded for, and a stale column pointing outside the target row's
    // built cells makes the next DOWN/UP focus a detached node — a silently
    // eaten keypress. Re-key both by shelf IDENTITY across the update.
    if (!identical(old.sections, widget.sections)) {
      int remap(int oldIndex) {
        if (oldIndex < 0 || oldIndex >= old.sections.length) return -1;
        final id = old.sections[oldIndex].id;
        if (id == null) return oldIndex;
        return widget.sections.indexWhere((s) => s.id == id);
      }

      final remappedCols = <int, int>{};
      for (final entry in _owners.navigation.col.entries) {
        final ni = remap(entry.key);
        if (ni >= 0) remappedCols[ni] = entry.value;
      }
      _owners.navigation.col
        ..clear()
        ..addAll(remappedCols);
      if (_owners.navigation.row >= 0) {
        final ni = remap(_owners.navigation.row);
        if (ni >= 0) _owners.navigation.row = ni;
      }
    }
    // A board reload can shrink or reorder the shelves under a parked cursor.
    // `_row` is positional, so without this the next arrow key indexes past
    // the end of `rowNodes` and throws.
    if (_owners.navigation.row >= widget.sections.length) {
      _owners.navigation.row = widget.sections.isEmpty
          ? -1
          : widget.sections.length - 1;
    }
    for (final row in _owners.navigation.col.keys.toList()) {
      if (row >= widget.sections.length) {
        _owners.navigation.col.remove(row);
        continue;
      }
      final len = widget.sections[row].nodes.length;
      if (len == 0) {
        _owners.navigation.col.remove(row);
      } else if ((_owners.navigation.col[row] ?? 0) >= len) {
        _owners.navigation.col[row] = len - 1;
      }
    }
    _sections.ambient.probe();
  }

  @override
  void dispose() {
    _sections.heroWarmup.cancelWarmups();
    _owners.scroll.veilMetricsRevision.dispose();
    widget.heroNode.removeListener(_sections.cadence.onHeroFocus);
    if (_owners.hero.rolling) widget.onTrailerStop?.call();
    _owners.hero.cadence?.cancel();
    _owners.scroll.scroll.dispose();
    super.dispose();
  }

  @visibleForTesting
  String? get heroAlignmentItemId => _sections.ambient.heroAlignmentItemId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!(ModalRoute.isCurrentOf(context) ?? true)) {
      _owners.navigation.pendingProgressiveDown = null;
    }
  }

  /// Enter a collection at its selected category, including off-screen rows.
  void focusShelf(int row) => _sections.focus.focusShelf(row);

  /// Initial entry and re-entry must only target mounted content. Shelves
  /// may arrive before the independently loaded hero, and late hero data
  /// must not move an already placed card cursor.
  FocusNode? focusTarget() => _sections.focus.focusTarget();

  // ── paint ──────────────────────────────────────────────────────────────
  @override
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
              dpad: widget.dpad,
            );
            final large =
                widget.largeScreenInteractions &&
                !widget.dpad &&
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
            return _board(
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

  Widget _board(SpotlightBoardMetrics m, double heroH) {
    _owners.scroll.lastMetrics = m;
    _owners.scroll.heroBandH = heroH;
    final app = AppThemeScope.of(context);
    final ground = SpotlightBoard.groundOf(app);
    // One key per shelf, by rail IDENTITY (see [SpotlightShelf.id]).
    String shelfKey(int i) {
      final s = widget.sections[i];
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
      itemCount: widget.sections.length + 2,
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        if (key.value == 'spotlight-hero-band') return 0;
        if (key.value == 'spotlight-tail') return widget.sections.length + 1;
        for (var i = 0; i < widget.sections.length; i++) {
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
          if (widget.shelvesOnly) {
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
              child: SizedBox(height: heroH, child: _hero(m, heroH)),
            ),
          );
        }
        if (index == widget.sections.length + 1) {
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
                _owners.selection.scrollRowId = widget.sections[i].id ?? i;
              }
              if (notification is ScrollUpdateNotification &&
                  widget.shelvesOnly &&
                  notification.metrics.axis == Axis.horizontal &&
                  notification.metrics.extentAfter < 400) {
                widget.onLoadMoreRow?.call(i);
              }
              return false;
            },
            child: _shelf(i, m),
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
          if (!widget.dpad &&
              mounted &&
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
    if (!widget.paintBackground) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ground, SpotlightBoard.groundLowOf(app)],
        ),
      ),
      // Wide pins the picture BEHIND the scroll view. A Scrollable claims
      // every pointer in its viewport, which is fine here because nothing in
      // the backdrop is interactive — the hero's tap/swipe surface and the
      // tappable dots ride in the list with the identity.
      child: (m.compact || widget.shelvesOnly) && !widget.animationsEnabled
          ? content
          : Stack(
              fit: StackFit.expand,
              children: [
                if (widget.animationsEnabled)
                  Positioned.fill(
                    child: switch (widget.animationStyle) {
                      'moonlit_ocean' => MoonlitOceanBackground(
                        lowPower: widget.dpad,
                      ),
                      'midnight_rain' => MidnightRainBackground(
                        lowPower: widget.dpad,
                      ),
                      _ => SnowyMountainBackground(lowPower: widget.dpad),
                    },
                  ),
                if (!m.compact && !widget.shelvesOnly)
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
                        child: _heroBackdrop(heroH),
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

  Widget _hero(SpotlightBoardMetrics m, double heroH) {
    if (m.compact) return _heroCompact(m);
    return _heroWide(m, heroH);
  }

  /// The phone hero — the Apple phone idiom, not the TV hero cropped.
  ///
  /// Centered identity stack over the art's lower third (logo → metadata →
  /// CTA → dots), a vertical scrim whose bottom stop is the page ground
  /// exactly (the seam rule), swipe paging, tappable dots. No description
  /// line and no side-flip heuristic: there is no "side" when the stack is
  /// centered.
  Widget _heroCompact(SpotlightBoardMetrics m) {
    final item = _sections.heroArt.heroItem;
    if (item == null) return const SizedBox.shrink();
    final url = _sections.heroArt.heroArt(item);
    final posterUrl = _sections.heroArt.heroPoster(item);
    final app = AppThemeScope.of(context);
    final ground = SpotlightBoard.groundOf(app);
    final rolling = _owners.hero.rolling;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 120) return;
        _sections.cadence.jumpTo(
          (_sections.heroArt.heroIndex +
                  (v < 0 ? 1 : -1) +
                  widget.hero.length) %
              widget.hero.length,
        );
      },
      onTap: () {
        final addon = widget.heroAddon;
        if (addon != null) _sections.heroArt.openHero();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null && url.isNotEmpty)
            CachedNetworkImage(
              imageUrl: url,
              key: ValueKey(url),
              fit: BoxFit.cover,
              cacheManager: DebrifyImageCache.manager,
              // Decode at the PANEL's resolution, not a guessed constant —
              // 900 was under a 1080-class phone's physical width (390 × 3),
              // so the one full-bleed image on the screen was the soft one.
              // Clamped: metahub art tops out around 1920.
              memCacheWidth: _sections.heroArt.heroDecodeWidth,
              fadeInDuration: _sections.heroArt.heroImageFadeIn,
              fadeOutDuration: _sections.heroArt.heroImageFadeOut,
              placeholder: (_, __) => ColoredBox(color: ground),
              // Same guess-404 fallback as the wide backdrop: derived
              // metahub art can miss, and the poster beats a blank hero.
              errorWidget: (_, __, ___) =>
                  (posterUrl != null &&
                      posterUrl.isNotEmpty &&
                      posterUrl != url)
                  ? CachedNetworkImage(
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                      cacheManager: DebrifyImageCache.manager,
                      memCacheWidth: 900,
                      placeholder: (_, __) => ColoredBox(color: ground),
                      errorWidget: (_, __, ___) => ColoredBox(color: ground),
                    )
                  : ColoredBox(color: ground),
            ),
          // The trailer, when the host supplies one. This was mounted only in
          // the WIDE hero — so the phone resolved a stream into a layer that
          // was never in the tree, which read as "trailers don't load".
          if (widget.trailer != null) Positioned.fill(child: widget.trailer!),
          // One vertical scrim doing both jobs: a light cap up top so the
          // status-bar clock stays readable over bright art, and a heavy bed
          // below for the identity — ending ON the ground so the hero meets
          // the rows without a seam. Thinned while the picture rolls, same
          // rule as everywhere else tonight: snapped, and the bottom stop is
          // still the ground exactly so the seam never opens.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: rolling
                      ? [
                          const Color(0x2E000000),
                          const Color(0x00000000),
                          const Color(0x00000000),
                          ground.withValues(alpha: 0.55),
                          ground,
                        ]
                      : [
                          const Color(0x6B000000),
                          const Color(0x00000000),
                          const Color(0x00000000),
                          ground.withValues(alpha: 0.78),
                          ground,
                        ],
                  stops: rolling
                      ? const [0, 0.18, 0.62, 0.88, 1]
                      : const [0, 0.24, 0.46, 0.8, 1],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 12,
            child: _identityCompact(item, m),
          ),
        ],
      ),
    );
  }

  Widget _identityCompact(StremioMeta item, SpotlightBoardMetrics m) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: SpotlightBoardLogoOrTitle(
            url: item.logo,
            name: item.name,
            align: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          [
            item.type == 'series' ? 'Series' : 'Film',
            ...(item.genres ?? const []).take(2),
          ].join(' · '),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: Colors.white.withValues(alpha: 0.86),
          ),
        ),
        const SizedBox(height: 12),
        // The CTA the mock promises. "Open" rather than "Play": it routes to
        // the detail page (the same thing OK does on TV) — a button that says
        // Play and then shows a detail page would be a lie.
        SpotlightHeroOpenPill(
          onTap: () {
            final addon = widget.heroAddon;
            if (addon != null) _sections.heroArt.openHero();
          },
        ),
        if (widget.hero.length > 1) ...[
          const SizedBox(height: 13),
          _dots(tappable: true),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  /// The TV hero's SCROLLING half: identity, dots, pointer surface, focus
  /// node. The picture it reads against is [_heroBackdrop], pinned behind the
  /// list — split so the text can ride away with the shelves while the art
  /// stays put.
  Widget _heroWide(SpotlightBoardMetrics m, double heroH) {
    final item = _sections.heroArt.heroItem;
    if (item == null) return const SizedBox.shrink();
    final wide = _heroForeground(m, item, heroH);
    if (widget.dpad) return wide;
    // Desktop and tablet drive the same wide layout by pointer/touch: swipe
    // pages the reel, a tap opens the showcased title — the exact gestures
    // the compact hero has. TV returns the bare stack above, untouched.
    // This surface must live HERE, in the list, not on the backdrop: the
    // Scrollable in front of the backdrop claims every pointer in its
    // viewport, so a tap layer down there would never hear anything.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 120 || widget.hero.length < 2) return;
        _sections.cadence.jumpTo(
          (_sections.heroArt.heroIndex +
                  (v < 0 ? 1 : -1) +
                  widget.hero.length) %
              widget.hero.length,
        );
      },
      onTap: () {
        final addon = widget.heroAddon;
        if (addon != null) _sections.heroArt.openHero();
      },
      child: wide,
    );
  }

  /// The pinned picture: art, trailer, scrims, and the scroll veil. Sits
  /// BEHIND the scroll view (see [_board]); everything here is
  /// non-interactive by construction.
  Widget _heroBackdrop(double heroH) {
    final backdrop = _heroBackdropContent(heroH);
    if (!widget.animationsEnabled) return backdrop;
    // Keep the title's artwork and trailer in the hero. Fade that entire
    // layer away on scroll to reveal the fixed mountain instead of painting
    // an opaque ground veil over it. The trailer host stays mounted.
    return AnimatedBuilder(
      animation: Listenable.merge([
        _owners.scroll.scroll,
        _owners.scroll.veilMetricsRevision,
      ]),
      // TV already snaps the hero visibility on row changes. Its existing
      // bottom scrim supplies the blend without an extra offscreen mask.
      child: widget.dpad
          ? backdrop
          : ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0, 0.7, 1],
              ).createShader(bounds),
              child: backdrop,
            ),
      builder: (context, child) {
        final off = _owners.scroll.scroll.hasClients
            ? _owners.scroll.scroll.offset
            : 0.0;
        final opacity = widget.dpad
            ? (_owners.navigation.row < 0 ? 1.0 : 0.0)
            : (1 - off / (heroH * 0.8)).clamp(0.0, 1.0);
        return Opacity(opacity: opacity, child: child);
      },
    );
  }

  Widget _heroBackdropContent(double heroH) {
    final item = _sections.heroArt.heroItem;
    if (item == null) return const SizedBox.shrink();
    final url = _sections.heroArt.heroArt(item);
    final posterUrl = _sections.heroArt.heroPoster(item);
    final flip = _sections.ambient.flip;
    // Both scrims below were tuned against a STILL, where they only have to
    // keep white text off busy artwork. Left at that strength over a moving
    // picture they are most of why the trailer reads dim: the identity scrim
    // blacks out the left two thirds, and the ground fade covers 260 of the
    // band's 540 across its full width.
    //
    // The page already has a name for this — theater, "veils thin to
    // near-clear" — but that flag is read only inside the Canvas branch and
    // never reaches this board, so Spotlight armed the timer and got none of
    // the lift. Driven off the board's own cadence flag instead, which is the
    // thing that actually knows a picture is rolling.
    //
    // Snapped, not tweened: animating a full-width gradient every frame is
    // exactly what the TV veil policy exists to avoid.
    final rolling = _owners.hero.rolling;
    final app = AppThemeScope.of(context);
    final ground = SpotlightBoard.groundOf(app);
    // The legibility bed under the hero's white identity — always dark, see the
    // gradient below.
    final bed = Color.lerp(ground, const Color(0xFF000000), 0.75)!;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (url != null && url.isNotEmpty)
          CachedNetworkImage(
            imageUrl: url,
            key: ValueKey(url),
            fit: BoxFit.cover,
            cacheManager: DebrifyImageCache.manager,
            // Decode at the PANEL's resolution off-TV, same as the compact
            // hero — 1400 flat was under a retina desktop's physical width,
            // so the one full-bleed image on the screen was the soft one.
            // TV keeps the 1400: its panels sit behind the box's own
            // upscaler and the decode budget there is the tighter constraint
            // (see TvHeroArtworkQuality).
            memCacheWidth: _sections.heroArt.heroDecodeWidth,
            fadeInDuration: _sections.heroArt.heroImageFadeIn,
            fadeOutDuration: _sections.heroArt.heroImageFadeOut,
            placeholder: (_, __) => ColoredBox(color: ground),
            // The derived metahub URL is a GUESS — when it 404s (no still
            // for that title), fall back to the poster rather than a flat
            // ground: a soft hero beats a blank one.
            errorWidget: (_, __, ___) =>
                (posterUrl != null && posterUrl.isNotEmpty && posterUrl != url)
                ? CachedNetworkImage(
                    imageUrl: posterUrl,
                    fit: BoxFit.cover,
                    cacheManager: DebrifyImageCache.manager,
                    memCacheWidth: 1400,
                    placeholder: (_, __) => ColoredBox(color: ground),
                    errorWidget: (_, __, ___) => ColoredBox(color: ground),
                  )
                : ColoredBox(color: ground),
          ),
        // Mounted whenever the HOST supplies one — never gated on this
        // board's own `_rolling`.
        //
        // Gating it here kept the layer alive after the host tore the trailer
        // down (`_clearHeroTrailer` on playback launch), so its media_kit
        // engine was still holding a VideoOutput when the player created its
        // own. Two VideoOutputs is SIGABRT on tvOS — the crash was at
        // `enableHardwareAcceleration`, in the second one's constructor.
        //
        // The host already owns this lifecycle for every other board; the
        // board's job is the cadence, and only the cadence.
        if (widget.trailer != null) Positioned.fill(child: widget.trailer!),
        // The identity scrim, on whichever side the text is. Pinned WITH the
        // art rather than scrolling with the text it serves: it covers that
        // side's full height, so the identity stays on scrimmed picture for
        // its whole upward travel — and a scrim that translated away with
        // the list would drag its visible edge up the artwork.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: flip
                    ? const Alignment(1, -0.2)
                    : const Alignment(-1, -0.2),
                end: flip ? const Alignment(-1, 0.2) : const Alignment(1, 0.2),
                colors: rolling
                    ? const [
                        Color(0x9E000000),
                        Color(0x66000000),
                        Color(0x1C000000),
                        Color(0x00000000),
                      ]
                    : const [
                        Color(0xE0000000),
                        Color(0xA8000000),
                        Color(0x2E000000),
                        Color(0x00000000),
                      ],
                stops: const [0, 0.26, 0.52, 0.68],
              ),
            ),
          ),
        ),
        // Fades into the SHELF GROUND, not into black — a scrim landing on a
        // colour the page never paints leaves a visible seam where the hero
        // ends.
        IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              // Pulled in tight while the picture rolls. The seam still has to
              // be sealed — the bottom stop is the ground colour exactly, so
              // the hero still meets the shelf without a visible edge — but
              // the long soft tail costs half the frame for no legibility.
              //
              // Deliberately absolute, unlike the hero's own height: this is a
              // blend DISTANCE, not a share of the layout, and a fade that
              // scaled with the panel would smear further on a large one for no
              // reason. The identity's `bottom` insets below are the same kind
              // of number.
              height: rolling ? 150 : 260,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    // TWO jobs, and only one of them follows the ground.
                    //
                    // The bottom stop is the page ground exactly, so the hero
                    // meets the shelf with no seam. Everything above it is a
                    // legibility bed for the hero's identity and dots, which
                    // are white because they sit on a photograph — so it stays
                    // DARK. Tinting the whole ramp with the ground put a white
                    // wash under white text the moment a pale background was
                    // chosen.
                    colors: [
                      ground,
                      bed.withValues(alpha: 0.92),
                      bed.withValues(alpha: 0.45),
                      bed.withValues(alpha: 0),
                    ],
                    stops: const [0.04, 0.22, 0.56, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
        // The veil — what going DOWN does to the picture now that it no
        // longer scrolls away. Ground-coloured for the same reason the fade
        // above ends on ground: the rows and their titles are inked for the
        // page ground, so the picture must dim TOWARD it — a black veil
        // would put theme-inked text on a surface the theme never chose.
        //
        // A solid fill whose alpha lives in the COLOUR — an Opacity widget
        // would add a compositing layer per change — inside its own
        // RepaintBoundary, so a veil change redraws one flat quad and never
        // dirties the layer holding the art and both gradients.
        //
        // TWO drivers, per input. TV snaps it off the CURSOR — hero clear,
        // first shelf 0.72, deeper opaque — because tracking the scroll
        // glide repaints every frame of every row move, which is exactly
        // what the TV veil policy exists to avoid (and what a MiBox-class
        // GPU renders as lag). Touch and desktop keep the continuous
        // scroll-driven ramp: free scrolling has no discrete states to snap
        // between, and those GPUs absorb the fill.
        if (!widget.animationsEnabled)
          RepaintBoundary(
            child: IgnorePointer(
              child: widget.dpad
                  ? _veil(
                      ground,
                      _owners.navigation.row < 0
                          ? 0.0
                          : (_owners.navigation.row == 0 ? 0.72 : 1.0),
                    )
                  : AnimatedBuilder(
                      animation: Listenable.merge([
                        _owners.scroll.scroll,
                        _owners.scroll.veilMetricsRevision,
                      ]),
                      builder: (context, _) {
                        final off = _owners.scroll.scroll.hasClients
                            ? _owners.scroll.scroll.offset
                            : 0.0;
                        final t = (off / (heroH * 0.8)).clamp(0.0, 1.0);
                        return _veil(ground, t);
                      },
                    ),
            ),
          ),
      ],
    );
  }

  /// One alpha-in-the-colour fill. Fully transparent paints nothing at all.
  static Widget _veil(Color ground, double t) => t <= 0
      ? const SizedBox.shrink()
      : ColoredBox(color: ground.withValues(alpha: t));

  Widget _heroForeground(
    SpotlightBoardMetrics m,
    StremioMeta item,
    double heroH,
  ) {
    final flip = _sections.ambient.flip;
    // TV keeps the shipped absolutes: on a ~960×540 canvas, 128 is the
    // proportional shelf overlap (88) plus 40 of clearance, and 92 is the
    // overlap plus 4. On touch the SAME structure is derived instead of
    // fixed, because the overlap is a FRACTION of the hero and the hero is a
    // full tablet viewport — at heroH≈1024 the overlap alone is ~167, so the
    // absolute 128 parked the identity UNDER the first shelf's header (the
    // observed collision), with the dots on the posters below it.
    final overlap = heroH * SpotlightBoardConstantsState.shelfOverlapFraction;
    final identityBottom = widget.dpad ? 128.0 : overlap + 40 * m.k;
    final dotsBottom = widget.dpad ? 92.0 : overlap + 4 * m.k;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: flip ? null : m.gutter,
          right: flip ? m.gutter : null,
          bottom: identityBottom,
          width: m.w * (820 / 1920),
          child: _identity(item, flip, m),
        ),
        if (widget.hero.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: dotsBottom,
            // Tappable wherever there is no remote — desktop and tablet run
            // this wide layout too. On TV the padding-free dots render
            // byte-identically to HEAD.
            child: _dots(tappable: !widget.dpad),
          ),
        // The hero's focusable surface. IgnorePointer-free and zero-sized in
        // paint terms: the hero shows focus through the page, not through a
        // ring on a full-screen box.
        // `skipTraversal`: the hero is reached ONLY by the explicit UP
        // handler. Left findable, a geometric LEFT/UP search from the first
        // shelves lands on it — which is why LEFT from row 1 and 2 went to the
        // hero instead of falling through to the sidebar. It sits at x=0, so
        // it is the nearest thing to the left of everything.
        Positioned(
          left: 0,
          top: 0,
          child: Focus(
            focusNode: widget.heroNode,
            skipTraversal: true,
            descendantsAreTraversable: false,
            child: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _identity(StremioMeta item, bool flip, SpotlightBoardMetrics m) {
    final cross = flip ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final align = flip ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment: cross,
      mainAxisSize: MainAxisSize.min,
      children: [
        SpotlightBoardLogoOrTitle(
          url: item.logo,
          name: item.name,
          align: align,
          scale: m.k,
        ),
        const SizedBox(height: 9),
        Text(
          [
            item.type == 'series' ? 'Series' : 'Film',
            ...(item.genres ?? const []).take(2),
          ].join(' · '),
          textAlign: align,
          style: TextStyle(
            fontSize: 10.5 * m.k,
            color: Colors.white.withValues(alpha: 0.86),
          ),
        ),
        if ((item.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            item.description!,
            maxLines: 2,
            textAlign: align,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5 * m.k,
              height: 1.42,
              color: Colors.white.withValues(alpha: 0.74),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dots({bool tappable = false}) => Row(
    // Keyed so the single-page guard is pinnable: the board grew other
    // AnimatedContainers (the off-parallax focus ring), so "no
    // AnimatedContainer anywhere" stopped meaning "no dots".
    key: const ValueKey('spotlight-hero-dots'),
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < widget.hero.length; i++)
        GestureDetector(
          // A 4px dot is not a tap target — the padding is.
          onTap: tappable ? () => _sections.cadence.jumpTo(i) : null,
          behavior: tappable ? HitTestBehavior.opaque : null,
          child: Padding(
            padding: tappable
                ? const EdgeInsets.symmetric(horizontal: 2, vertical: 8)
                : EdgeInsets.zero,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 2.25),
              width: i == _sections.heroArt.heroIndex ? 11 : 4,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: i == _sections.heroArt.heroIndex ? 0.95 : 0.34,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
    ],
  );

  /// The row heading. Off TV it takes the reference's measure — larger,
  /// brighter, bolder than the TV board's quiet labels (there the hero
  /// carries the weight) — and wears the inline chevron when the row has
  /// somewhere to go; DPAD keeps the heading bare of chrome, because a TV
  /// rail paginates as focus walks it — there is nothing to tap. The
  /// provenance pill is the one piece BOTH inputs wear: which addon fills a
  /// row is a fact on every device.
  TextStyle _shelfTitleStyle(SpotlightBoardMetrics m) {
    final fontSize = widget.dpad
        ? m.title
        : m.compact
        ? 22.0
        : (m.title < 24.0 ? 24.0 : m.title);
    return TextStyle(
      fontSize: fontSize,
      fontWeight: widget.dpad ? FontWeight.w600 : FontWeight.w700,
      letterSpacing: widget.dpad ? 0.0 : -0.2,
      // The one label on this board that sits on the PAGE rather than
      // on artwork, so it is the one that has to follow the ink. The
      // hero's text, the dots and the card captions all sit over a
      // photograph and stay white whatever the ground is.
      color: AppThemeScope.of(
        context,
      ).core.tx.withValues(alpha: widget.dpad ? 0.84 : 0.96),
    );
  }

  double _shelfExtent(SpotlightShelf section, SpotlightBoardMetrics m) {
    double textHeight(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    var header = 0.0;
    if (section.showHeader) {
      header = textHeight(section.title, _shelfTitleStyle(m));
      final tag = section.tag;
      if (tag != null && tag.isNotEmpty) {
        final size = widget.dpad ? m.title * .72 : 10.0;
        final tagHeight =
            textHeight(tag.toUpperCase(), RowTagPill.textStyle(size)) +
            size * .56 +
            2; // vertical padding and the two 1px borders
        if (tagHeight > header) header = tagHeight;
      }
    }
    final cardHeight = _shelfCardHeight(section, m);
    return (section.showHeader
            ? (widget.dpad ? 20 : 34)
            : (widget.dpad ? 8 : 14)) +
        header +
        m.liftUpFor(cardHeight) +
        cardHeight +
        m.liftDownFor(cardHeight) +
        (_shelfHasCaptions(section, m) ? m.captionBlock : 0);
  }

  Widget _shelfTitle(SpotlightShelf section, SpotlightBoardMetrics m) {
    final style = _shelfTitleStyle(m);
    final fontSize = style.fontSize!;
    final onSeeAll = section.onSeeAll;
    final Widget heading = (widget.dpad || onSeeAll == null)
        ? Text(
            section.title,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        : SpotlightShelfTitleLink(
            title: section.title,
            style: style,
            fontSize: fontSize,
            onTap: onSeeAll,
          );
    final tag = section.tag;
    if (tag == null || tag.isEmpty) return heading;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Only the HEADING flexes. Two Flexibles would split the row 50/50 as
        // max constraints and wrap a heading the pill never needed the room
        // of ("Featured Movies" broke onto two lines exactly that way). The
        // pill takes its intrinsic width under a hard cap instead, so a
        // long addon name ellipsizes inside the pill rather than squeezing
        // the words that matter.
        Flexible(child: heading),
        const SizedBox(width: 9),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: RowTagPill(tag, fontSize: widget.dpad ? m.title * 0.72 : 10),
        ),
      ],
    );
  }

  double _shelfCardHeight(SpotlightShelf section, SpotlightBoardMetrics m) {
    // Wide cards use their own rail width. Keeping the portrait card's
    // width makes a 16:9 tile too short to read, while keeping its height
    // makes it enormous and leaves only two titles on a TV row. The rule is
    // by ASPECT, so wide title cards and wide channel tiles share one rail;
    // shelves of portrait/square cards retain their native geometry.
    final uniformlyWide =
        section.items.isNotEmpty &&
        section.items.every((item) => item.shape.aspect > 1);
    return uniformlyWide
        ? m.wideCardW / SpotlightCardShape.wide.aspect
        : m.posterH;
  }

  bool _shelfHasCaptions(SpotlightShelf section, SpotlightBoardMetrics m) {
    // Caption-free rows off TV (see [SpotlightShelf.captions]); TV keeps its
    // overlay captions everywhere. Compact must also keep a caption whenever
    // a card carries metadata: otherwise portrait mode discards ratings and
    // Continue Watching's season/episode label while landscape shows both.
    final hasCardMetadata = section.items.any(
      (item) =>
          (item.subtitle ?? '').isNotEmpty ||
          (widget.showCardTitlesAndRatings && (item.rating ?? 0) > 0),
    );
    final hasVisibleCaptionContent =
        widget.showCardTitlesAndRatings || hasCardMetadata;
    return hasVisibleCaptionContent &&
        (widget.dpad || section.captions || (m.compact && hasCardMetadata));
  }

  Widget _shelf(int i, SpotlightBoardMetrics m) {
    final section = widget.sections[i];
    final nodes = section.nodes;
    final cardHeight = _shelfCardHeight(section, m);
    final captions = _shelfHasCaptions(section, m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (section.showHeader)
          Padding(
            // The gap under the title is `liftUp`, supplied by the row below —
            // reserved space that is empty at rest and consumed by the lift.
            // Off TV the rows breathe more — the reference's air is half of
            // what makes its rows read as considered rather than stacked.
            padding: EdgeInsets.fromLTRB(
              m.gutter,
              widget.dpad ? 20 : 34,
              m.gutter,
              0,
            ),
            child: _shelfTitle(section, m),
          )
        else
          SizedBox(height: widget.dpad ? 8 : 14),
        Padding(
          // The room the lift needs sits OUTSIDE the viewport, as padding.
          //
          // It used to be added to the viewport's own height instead, and that
          // was the bug behind cards reading far too tall: a horizontal
          // ListView constrains its children to the viewport height TIGHTLY,
          // so every card was stretched to `posterH * 1.10 + 24` while its
          // width was still computed from `posterH`. A 2:3 poster drew at
          // 0.53:1. No amount of re-deriving the ratio could have fixed it.
          padding: EdgeInsets.only(
            top: m.liftUpFor(cardHeight),
            bottom: m.liftDownFor(cardHeight),
          ),
          child: SizedBox(
            // The viewport IS the card now, so the tight cross-axis constraint
            // hands each card exactly the height it asked for. On compact the
            // caption strip below the art is part of the card, and the
            // viewport grows by exactly that strip — the art box itself stays
            // at [cardHeight], so the ratio guard still holds.
            height: cardHeight + (captions ? m.captionBlock : 0),
            child: ListView.separated(
              // Now that the board unbuilds far-off shelves, a rebuilt row
              // would otherwise come back rewound to column 0 — PageStorage
              // carries the offset across the unbuild (DPAD re-lands via
              // focus anyway; this is for touch scroll positions).
              key: PageStorageKey('spotlight-row-${section.id ?? i}'),
              // The lift paints into the padding above and below rather than
              // being sliced off at the viewport edge.
              clipBehavior: Clip.none,
              scrollDirection: Axis.horizontal,
              // Let the last card reach the reading cursor even on short rows.
              padding: EdgeInsets.only(
                left: m.gutter,
                right:
                    _owners.selection.largeCardInteractions &&
                        section.items.isNotEmpty
                    ? max(
                        m.gutter,
                        (_owners.selection.selectionViewport?.width ?? 0) -
                            m.gutter -
                            cardHeight * section.items.last.shape.aspect,
                      )
                    : m.gutter,
              ),
              itemCount: section.items.length,
              separatorBuilder: (_, __) => SizedBox(width: m.gap),
              itemBuilder: (context, c) => SpotlightBoardCard(
                rowId: section.id ?? i,
                largeInteractions: _owners.selection.largeCardInteractions,
                register: _sections.selection.registerCard,
                unregister: _sections.selection.unregisterCard,
                onInteraction: _sections.selection.interactWithCard,
                card: section.items[c],
                node: c < nodes.length ? nodes[c] : null,
                // Every shape shares the ROW's height and takes the width its
                // aspect implies, so a shelf that mixes posters and channel
                // tiles sits on one baseline instead of stepping up and down.
                height: cardHeight,
                expandedHeight: m.wideCardW / SpotlightCardShape.wide.aspect,
                caption: m.caption,
                radius: m.radius,
                captionBelow: m.compact && captions,
                captionBlock: captions ? m.captionBlock : 0,
                showCaption: captions && section.items[c].showCaption,
                showTitleAndRating: widget.showCardTitlesAndRatings,
                expandOnFocus:
                    (widget.dpad || _owners.selection.largeCardInteractions) &&
                    widget.expandFocusedCard,
                forceParallax:
                    widget.forceCardParallax ||
                    _owners.selection.largeCardInteractions,
                trailerEnabled: widget.trailersEnabled,
                trailerVolume: widget.cardTrailerVolume,
                onTrailerStart: widget.onTrailerStop,
                hoverable: !widget.dpad,
                dpad: widget.dpad,
                onDesktopPreviewActivityChanged:
                    _sections.cadence.onDesktopPreviewActivityChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  String get animationStyle => widget.animationStyle;
  @override
  bool get animationsEnabled => widget.animationsEnabled;
  @override
  double get cardTrailerVolume => widget.cardTrailerVolume;
  @override
  bool get dpad => widget.dpad;
  @override
  bool get expandFocusedCard => widget.expandFocusedCard;
  @override
  bool get forceCardParallax => widget.forceCardParallax;
  @override
  List<StremioMeta> get hero => widget.hero;
  @override
  StremioAddon? get heroAddon => widget.heroAddon;
  @override
  FocusNode get heroNode => widget.heroNode;
  @override
  bool get largeScreenInteractions => widget.largeScreenInteractions;
  @override
  void Function(String? art, Color? tint)? get onAmbient => widget.onAmbient;
  @override
  void Function(StremioMeta item)? get onDwell => widget.onDwell;
  @override
  VoidCallback? get onExitTop => widget.onExitTop;
  @override
  void Function(StremioMeta, StremioAddon) get onHeroOpen => widget.onHeroOpen;
  @override
  void Function(int row)? get onLoadMoreRow => widget.onLoadMoreRow;
  @override
  Future<bool> Function()? get onLoadMoreShelves => widget.onLoadMoreShelves;
  @override
  VoidCallback? get onTrailerStop => widget.onTrailerStop;
  @override
  bool get paintBackground => widget.paintBackground;
  @override
  bool get pendingShelves => widget.pendingShelves;
  @override
  List<SpotlightShelf> get sections => widget.sections;
  @override
  bool get shelvesOnly => widget.shelvesOnly;
  @override
  bool get showCardTitlesAndRatings => widget.showCardTitlesAndRatings;
  @override
  Widget? get trailer => widget.trailer;
  @override
  bool get trailersEnabled => widget.trailersEnabled;
  @override
  Color Function(AppTheme) get groundOf => SpotlightBoard.groundOf;
  @override
  Color Function(AppTheme) get groundLowOf => SpotlightBoard.groundLowOf;
  @override
  double get leftThirdBusy => SpotlightBoard.leftThirdBusy;
  final _owners = SpotlightBoardOwners();
  SpotlightBoardSections? _cachedSections;
  SpotlightBoardSections get _sections =>
      _cachedSections ??= createSpotlightBoardSections(
        view: this,
        owners: _owners,
        context: () => context,
        mounted: () => mounted,
        setState: setState,
        heroWarmupProvider: heroWarmupProvider,
        shelfExtent: _shelfExtent,
      );
}

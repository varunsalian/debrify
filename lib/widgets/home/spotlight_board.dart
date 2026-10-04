import 'dart:async';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_types.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/home/home_row_focus.dart';
import 'package:debrify/widgets/metadata_presentation_mixin.dart';
import 'package:flutter/material.dart';

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
          extentOf: (id) => _sections.shelves.shelfExtent(
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

  @override
  Widget build(BuildContext context) => _sections.rootLayout.build(context);
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
      );
}

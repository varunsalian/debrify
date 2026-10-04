import 'dart:async';
import 'dart:math' show max;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_card.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_constants_state.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_hero_state.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_logo_or_title.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_metrics.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_types.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_hero_open_pill.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_shelf_title_link.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:debrify/services/diagnostic_log.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/utils/artwork_url.dart';
import 'package:debrify/utils/dominant_color.dart';
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
import 'package:flutter/services.dart';

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
  void _registerCard(SpotlightBoardCardState card) {
    _owners.selection.visibleCards.add(card);
    if (_owners.selection.largeCardInteractions &&
        (_owners.selection.selectedCard == null ||
            _owners.selection.selectionFromScroll)) {
      _queueScrollSelection();
    }
  }

  void _unregisterCard(SpotlightBoardCardState card) {
    _owners.selection.visibleCards.remove(card);
    if (identical(_owners.selection.selectedCard, card)) {
      _owners.selection.selectedCard = null;
    }
    if (_owners.selection.largeCardInteractions &&
        _owners.selection.scrollingSources.isNotEmpty) {
      _queueScrollSelection();
    }
  }

  void _selectCard(SpotlightBoardCardState? card, {required bool scrolling}) {
    // Changing widths during a drag can collapse a short row's scroll extent
    // and cancel the gesture. Hold painted widths until scrolling settles.
    for (final visible in _owners.selection.visibleCards) {
      if (visible.mounted) visible.freezeScrollWidth(scrolling);
    }
    final previous = _owners.selection.selectedCard;
    _owners.selection.selectedCard = card;
    if (!identical(previous, card) && previous?.mounted == true) {
      previous!.setWideSelection(false, moving: false);
    }
    card?.setWideSelection(true, moving: scrolling);
  }

  void _interactWithCard(SpotlightBoardCardState card, bool active) {
    if (!_owners.selection.largeCardInteractions) return;
    // Hover can change as cards move beneath a stationary pointer.
    // Only scroll completion may release the moving state.
    if (_owners.selection.scrollingSources.isNotEmpty) {
      if (_pointerOwnsScrollSelection) _queueScrollSelection();
      return;
    }
    if (active) {
      _owners.selection.selectionFromScroll = false;
      _owners.selection.scrollInterruptedPreview = false;
      _selectCard(card, scrolling: false);
    } else if (!_owners.selection.selectionFromScroll &&
        identical(_owners.selection.selectedCard, card)) {
      // Hover and keyboard focus can overlap. Losing either one must not
      // hide the cursor while the other still owns this card.
      if (card.f || card.h) return;
      SpotlightBoardCardState? focused;
      for (final candidate in _owners.selection.visibleCards) {
        if (candidate.mounted && candidate.f) {
          focused = candidate;
          break;
        }
      }
      _selectCard(focused, scrolling: false);
    }
  }

  bool get _pointerOwnsScrollSelection => switch (Theme.of(context).platform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };

  bool _onCardScroll(ScrollNotification notification) {
    if (!_owners.selection.largeCardInteractions) return false;
    final userStarted =
        (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle) ||
        (notification is ScrollStartNotification &&
            notification.dragDetails != null);
    final source = notification.context;
    if (userStarted) {
      _owners.selection.selectionFromScroll = true;
      if (notification.metrics.axis == Axis.vertical) {
        _owners.selection.scrollRowId = null;
      }
      if (source != null) _owners.selection.scrollingSources.add(source);
      _owners.selection.scrollInterruptedPreview = true;
      _queueScrollSelection();
    }
    // Layout corrections and ensureVisible are not new user gestures.
    if (!_owners.selection.scrollingSources.contains(source)) return false;
    if (notification is ScrollEndNotification) {
      _owners.selection.scrollingSources.remove(source);
    }
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _queueScrollSelection();
    }
    return false;
  }

  /// Like the phone detail rail, scrolling supplies a visual reading cursor.
  /// Measure actual cards because Spotlight mixes shapes and expanded widths.
  /// Only one visible shelf/card owns it; cached offscreen cells never preview.
  void _queueScrollSelection() {
    if (_owners.selection.selectionQueued) return;
    _owners.selection.selectionQueued = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _owners.selection.selectionQueued = false;
      if (!mounted) return;
      _owners.selection.scrollingSources.removeWhere(
        (source) => !source.mounted,
      );
      if (!_owners.selection.visibleCards.any(
        (card) =>
            card.mounted && card.widget.rowId == _owners.selection.scrollRowId,
      )) {
        _owners.selection.scrollRowId = null;
      }
      if (!_owners.selection.largeCardInteractions) {
        _selectCard(null, scrolling: false);
        return;
      }

      if (_owners.selection.scrollInterruptedPreview) {
        _owners.selection.scrollInterruptedPreview = false;
        _owners.selection.selectedCard?.setWideSelection(true, moving: true);
      }
      // Desktop scrolling must not replace the pointer with the touch
      // reading cursor. MouseRegion also updates when content moves under
      // a stationary pointer; its callbacks queue another selection pass.
      if (_pointerOwnsScrollSelection) {
        SpotlightBoardCardState? hovered;
        SpotlightBoardCardState? focused;
        for (final card in _owners.selection.visibleCards) {
          if (!card.mounted || !card.widget.largeInteractions) continue;
          if (card.h) hovered = card;
          if (card.f) focused = card;
        }
        _owners.selection.selectionFromScroll = false;
        _selectCard(
          hovered ?? focused,
          scrolling: _owners.selection.scrollingSources.isNotEmpty,
        );
        if (_owners.selection.scrollingSources.isEmpty &&
            _owners.hero.desktopPreviewOwners.isEmpty)
          _restartCadence();
        return;
      }
      final render = context.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;
      final bounds = Offset.zero & render.size;
      final readingY = bounds.height * 0.6;
      final readingX = _owners.scroll.lastMetrics?.gutter ?? 24;
      SpotlightBoardCardState? nearest;
      double bestRow = double.infinity;
      double bestColumn = double.infinity;
      for (final card in _owners.selection.visibleCards) {
        if (!card.mounted || !card.widget.largeInteractions) continue;
        if (_owners.selection.selectionFromScroll &&
            _owners.selection.scrollRowId != null &&
            card.widget.rowId != _owners.selection.scrollRowId)
          continue;
        final box = card.context.findRenderObject();
        if (box is! RenderBox || !box.hasSize || !box.attached) continue;
        final rect =
            box.localToGlobal(Offset.zero, ancestor: render) & box.size;
        final visible = rect.intersect(bounds);
        if (visible.height < rect.height * 0.65 || visible.width < 24) continue;
        // Preserve explicit selection only while its card remains visible.
        if (!_owners.selection.selectionFromScroll &&
            identical(card, _owners.selection.selectedCard)) {
          return;
        }
        final row = (rect.center.dy - readingY).abs();
        final column = (rect.left - readingX).abs();
        if (row < bestRow - 4 ||
            ((row - bestRow).abs() <= 4 && column < bestColumn)) {
          nearest = card;
          bestRow = row;
          bestColumn = column;
        }
      }
      _selectCard(
        nearest,
        scrolling: _owners.selection.scrollingSources.isNotEmpty,
      );
      if (_owners.selection.scrollingSources.isEmpty &&
          _owners.hero.desktopPreviewOwners.isEmpty)
        _restartCadence();
    });
  }

  @override
  bool get prioritizeMetadata => true;

  @override
  StremioMeta? get originalMetadata =>
      widget.hero.isEmpty ? null : widget.hero[_heroIndex];

  @override
  void onMetadataPresentationChanged() => unawaited(_probe());

  @override
  void onMetadataPolicyChanged() {
    // A previous image's tint must not publish after the policy changes.
    _owners.hero.probeGen++;
    _preloadHeroes();
  }

  void _cancelWarmups() {
    for (final cancel in _owners.hero.cancelHeroWarmups.toList()) {
      cancel();
    }
  }

  int get _heroDecodeWidth => widget.dpad
      ? 1400
      : (MediaQuery.devicePixelRatioOf(context) *
                MediaQuery.sizeOf(context).width)
            .round()
            .clamp(720, 1920);

  Duration get _heroImageFadeIn =>
      (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
      ? Duration.zero
      : Duration(milliseconds: widget.dpad ? 180 : 420);

  Duration get _heroImageFadeOut =>
      widget.dpad || (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
      ? Duration.zero
      : const Duration(milliseconds: 1000);

  @visibleForTesting
  ImageProvider heroWarmupProvider(String url) => ResizeImage.resizeIfNeeded(
    _heroDecodeWidth,
    null,
    CachedNetworkImageProvider(url, cacheManager: DebrifyImageCache.manager),
  );

  Future<bool> _warmHeroImage(String url) {
    final result = Completer<bool>();
    final stream = heroWarmupProvider(
      url,
    ).resolve(createLocalImageConfiguration(context));
    Timer? timer;
    late ImageStreamListener listener;
    late VoidCallback cancel;
    void finish(bool success) {
      if (result.isCompleted) return;
      timer?.cancel();
      stream.removeListener(listener);
      _owners.hero.cancelHeroWarmups.remove(cancel);
      result.complete(success);
    }

    cancel = () => finish(false);
    listener = ImageStreamListener((image, _) {
      image.dispose();
      finish(true);
    }, onError: (_, _) => finish(false));
    _owners.hero.cancelHeroWarmups.add(cancel);
    timer = Timer(const Duration(seconds: 15), cancel);
    stream.addListener(listener);
    return result.future;
  }

  void _preloadHeroes() {
    _cancelWarmups();
    unawaited(
      preloadMetadata(widget.hero, (item, prefs) async {
        if (!mounted) return;
        final selected =
            prefs.provider(MetadataCategory.backgrounds) !=
            MetadataPreferences.current;
        final url =
            highQualityArtworkUrl(item.background) ??
            (!selected && (item.imdbId ?? item.id).startsWith('tt')
                ? 'https://images.metahub.space/background/large/${item.imdbId ?? item.id}/img'
                : !selected || prefs.fallback
                ? highQualityArtworkUrl(item.poster)
                : null);
        if (url == null || url.isEmpty) return;
        final timer = Stopwatch()..start();
        final failed = !await _warmHeroImage(url);
        DiagnosticLog.instance.recordEvent(
          source: 'metadata',
          event: 'hero_image_warm',
          fields: {'elapsed_ms': timer.elapsedMilliseconds, 'failed': failed},
        );
      }),
    );
  }

  /// Crossing detector for [_scrolledAway]: teardown on the way out,
  /// re-arm on the way back. Also called on metrics corrections (see
  /// [_board]) because a clamped offset never notifies the controller.
  void _onBoardScrolled() {
    if (!_owners.scroll.scroll.hasClients) return;
    if (!widget.dpad &&
        _owners.scroll.scroll.position.extentAfter <=
            SpotlightBoardConstantsState.touchLoadMoreThreshold) {
      unawaited(_loadMoreShelvesForTouch());
    }
    if (_owners.scroll.heroBandH <= 0) return;
    final away = _owners.scroll.scroll.offset > _owners.scroll.heroBandH * 0.35;
    if (away == _owners.constants.scrolledAway) return;
    _owners.constants.scrolledAway = away;
    if (away) {
      _owners.hero.cadence?.cancel();
      _owners.hero.cadence = null;
      _stopRolling();
    } else {
      // Applies its own gates (DPAD hero focus, pref, dwell callback), so
      // this is safe to fire from any scroll back to the top.
      _restartCadence();
    }
  }

  /// One funnel for leaving the rolling state, so no exit path can forget to
  /// tell the host to tear the video down.
  void _stopRolling() {
    if (!_owners.hero.rolling) return;
    if (mounted) setState(() => _owners.hero.rolling = false);
    widget.onTrailerStop?.call();
  }

  /// A desktop IPTV card is about to mount its own video decoder. The hero
  /// must yield its output lease before that mount; otherwise MediaKit queues
  /// the card behind an ambient trailer that loops indefinitely. Re-arm the
  /// hero only when the pointer has left every live card.
  void _onDesktopPreviewActivityChanged(Object owner, bool active) {
    if (widget.dpad) return;
    final hadPreview = _owners.hero.desktopPreviewOwners.isNotEmpty;
    if (active) {
      _owners.hero.desktopPreviewOwners.add(owner);
    } else {
      _owners.hero.desktopPreviewOwners.remove(owner);
    }
    final hasPreview = _owners.hero.desktopPreviewOwners.isNotEmpty;
    if (hadPreview == hasPreview) return;

    if (hasPreview) {
      _owners.hero.cadence?.cancel();
      _owners.hero.cadence = null;
      if (_owners.hero.rolling && mounted) {
        setState(() => _owners.hero.rolling = false);
      }
      // Also cancels a hero resolve that has not reached its first frame yet.
      widget.onTrailerStop?.call();
      return;
    }

    _restartCadence();
  }

  void _restartCadence() {
    if (_owners.selection.largeCardInteractions &&
        _owners.selection.scrollingSources.isNotEmpty) {
      return;
    }
    _owners.hero.cadence?.cancel();
    // Nulled, not just cancelled: didUpdateWidget's reconcile decides "is a
    // timer armed" by null-ness, and a cancelled-but-non-null handle reads
    // as armed.
    _owners.hero.cadence = null;
    if (!mounted) return;
    if (_owners.hero.dwelledHeroId != null &&
        _owners.hero.dwelledHeroId == _heroItem?.id) {
      return;
    }
    _owners.hero.rolling = false;
    // The active card owns the one available decoder. A rebuild caused by
    // loading more shelves or resolving hero art must not re-arm the hero
    // underneath it.
    if (_owners.hero.desktopPreviewOwners.isNotEmpty) return;
    // With no trailer to arm there is nothing to schedule. The reel itself
    // still moves only on input.
    if (!widget.trailersEnabled || widget.onDwell == null) return;
    // TV: frozen while focus is off the hero. `_row == -1` alone is NOT that
    // test: it stays -1 when focus goes to the sidebar, another tab, or a
    // pushed detail route — the node's own `hasFocus` is the real question.
    // Touch has no focus to gate on; visibility is checked at FIRE time.
    if (widget.dpad &&
        (_owners.navigation.row >= 0 || !widget.heroNode.hasFocus)) {
      return;
    }
    // Keep the handoff cancellable so a focus/route change in this event loop
    // can still stop the resolve, but add no user-visible dwell.
    _owners.hero.cadence = Timer(const Duration(seconds: 2), _onArtDone);
  }

  /// Dot tap / swipe target: show slide [i] and restart the clock.
  void _jumpTo(int i) {
    if (i < 0 || i >= widget.hero.length) return;
    if (widget.hero[i].id == _owners.hero.heroId) return;
    _stopRolling();
    _owners.hero.dwelledHeroId = null;
    setState(() => _owners.hero.heroId = widget.hero[i].id);
    refreshMetadataPresentation();
    _probe();
    _restartCadence();
  }

  void _onArtDone() {
    // The one-shot is consumed the moment this runs — null it, or the
    // reconcile in didUpdateWidget reads a dead handle as "armed" and a
    // disable→re-enable of trailers strands the cadence forever.
    _owners.hero.cadence = null;
    if (!mounted || _owners.navigation.row >= 0) return;
    // Scrolled off the hero (touch/wheel — a DPAD descent goes through
    // [_down] and cancels the clock itself): do not start a decoder behind
    // the veil. No re-arm — scrolling back under the threshold restarts the
    // cadence via [_onBoardScrolled].
    if (_owners.constants.scrolledAway) return;
    // Touch: a covered or backgrounded board must not spin up an engine for
    // a hero nobody can see. Poll gently until visible; this retry delay is
    // not part of the visible start cadence.
    if (!widget.dpad) {
      final route = ModalRoute.of(context);
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final visible =
          (route == null || route.isCurrent) &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed);
      if (!visible) {
        _owners.hero.cadence = Timer(
          SpotlightBoardHeroState.hiddenRetry,
          _onArtDone,
        );
        return;
      }
    }
    final item = _heroItem;
    if (item == null) {
      // didUpdateWidget re-arms when the first hero arrives; polling an empty
      // reel here would create a zero-delay loop.
      return;
    }
    if (widget.trailersEnabled && widget.onDwell != null) {
      _owners.hero.dwelledHeroId = item.id;
      // Once a trailer is rolling the reel stays put — the video loops until
      // the next deliberate move (swipe, dot tap, LEFT/RIGHT, DOWN).
      setState(() => _owners.hero.rolling = true);
      widget.onDwell!(item);
    }
    // Never an advance — see the cadence comment.
  }

  /// Best full-bleed art for [item]: its own backdrop, else a MetaHub 16:9
  /// still derived from its IMDb id — the same synchronous trick the other
  /// stage layouts use, because catalog and Continue Watching items carry a
  /// poster but rarely a backdrop — and the poster only as a last resort.
  ///
  /// This is intentionally the *large* MetaHub path. It feeds the single
  /// full-screen hero only; shelf cards keep their medium artwork and small
  /// decode budgets. The poster fallback is what blurry heroes are made of
  /// (~350px of 2:3 art cover-cropped over a full screen), so it is LAST, not
  /// second.
  String? _heroPoster(StremioMeta item) =>
      metadataArtworkPending(MetadataCategory.backgrounds)
      ? null
      : usesMetadataProvider(MetadataCategory.backgrounds) &&
            !metadataPreferences.fallback
      ? null
      : highQualityArtworkUrl(item.poster);

  String? _heroArt(StremioMeta item) {
    if (metadataArtworkPending(MetadataCategory.backgrounds)) return null;
    final b = item.background;
    if (b != null && b.isNotEmpty) return highQualityArtworkUrl(b);
    if (usesMetadataProvider(MetadataCategory.backgrounds))
      return _heroPoster(item);
    final tt = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    if (tt != null) {
      return 'https://images.metahub.space/background/large/$tt/img';
    }
    final p = item.poster;
    return (p != null && p.isNotEmpty) ? highQualityArtworkUrl(p) : null;
  }

  int get _heroIndex {
    if (widget.hero.isEmpty) return 0;
    final i = widget.hero.indexWhere((m) => m.id == _owners.hero.heroId);
    return i < 0 ? 0 : i;
  }

  StremioMeta? get _heroItem => heroPresentation;

  void _openHero() {
    final item = originalMetadata;
    final addon = widget.heroAddon;
    if (item != null && addon != null) widget.onHeroOpen(item, addon);
  }

  /// The id of the slide currently SHOWING — the host's suppression snapshot
  /// reads this at content-playback launch, because its own bookkeeping only
  /// knows the last *dwelled* item and playback can start before any dwell.
  String? get currentHeroId => _heroItem?.id;

  @override
  void initState() {
    super.initState();
    _owners.hero.heroId = widget.hero.isNotEmpty ? widget.hero.first.id : null;
    widget.heroNode.addListener(_onHeroFocus);
    _owners.scroll.scroll.addListener(_onBoardScrolled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _probe();
      _restartCadence();
      _preloadHeroes();
    });
  }

  @override
  void didUpdateWidget(SpotlightBoard old) {
    super.didUpdateWidget(old);
    _finishProgressiveDown();
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
      _preloadHeroes();
    }
    // The reel can change under us as sections load. Keep the parked item if
    // it is still present; otherwise fall back to the head rather than to a
    // stale index pointing at a different title.
    // The host can hand us a different node across a rebuild; without moving
    // the listener the old node keeps one forever and the new one has none.
    if (old.heroNode != widget.heroNode) {
      old.heroNode.removeListener(_onHeroFocus);
      widget.heroNode.addListener(_onHeroFocus);
    }
    // The trailer pref flipped: rebuild the cadence from scratch. Disable
    // must also clear a stale `_rolling` (or nothing ever re-arms — the
    // reconcile below skips while rolling), and enable must arm a clock that
    // has nothing else to wake it.
    if (old.trailersEnabled != widget.trailersEnabled) {
      _restartCadence();
    }
    if (_owners.hero.heroId != null &&
        !widget.hero.any((m) => m.id == _owners.hero.heroId)) {
      // The title we were on is gone. Tear the trailer down FIRST: it was
      // resolved for that title, and leaving it rolling paints it over the new
      // head until the 20s cap expires.
      _stopRolling();
      _owners.hero.heroId = widget.hero.isNotEmpty
          ? widget.hero.first.id
          : null;
      _restartCadence();
    } else if (_owners.hero.cadence == null && !_owners.hero.rolling) {
      // Reconcile for BOTH inputs: the host often enables trailers (the
      // pref read lands) or grows the reel AFTER first build, with the
      // parked id intact — the branch above never runs then, and without
      // this the dwell clock would simply never start. _restartCadence
      // applies its own gates (focus on DPAD, pref, dwell callback), so an
      // uncalled-for restart is a no-op, not a stolen cadence.
      _restartCadence();
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
    _probe();
  }

  /// Re-arms when the hero actually holds focus and stops the moment it does
  /// not — covering the sidebar, tab switches and pushed routes in one place.
  void _onHeroFocus() {
    if (!mounted) return;
    if (widget.heroNode.hasFocus) {
      _restartCadence();
    } else {
      _owners.hero.cadence?.cancel();
      _owners.hero.dwelledHeroId = null;
      _stopRolling();
    }
  }

  @override
  void dispose() {
    _cancelWarmups();
    _owners.scroll.veilMetricsRevision.dispose();
    widget.heroNode.removeListener(_onHeroFocus);
    if (_owners.hero.rolling) widget.onTrailerStop?.call();
    _owners.hero.cadence?.cancel();
    _owners.scroll.scroll.dispose();
    super.dispose();
  }

  void _emitAmbient(String? art, Color? tint) {
    final next = (art: art, tint: tint);
    final sink = widget.onAmbient;
    if (identical(sink, _owners.hero.lastAmbientSink) &&
        next == _owners.hero.lastAmbient) {
      return;
    }
    _owners.hero.lastAmbientSink = sink;
    _owners.hero.lastAmbient = next;
    sink?.call(art, tint);
  }

  Future<void> _probe() async {
    // The RESOLVED art, not the raw fields — tint and side-flip must be
    // measured on the image actually drawn.
    final gen = ++_owners.hero.probeGen;
    final item = _heroItem;
    final url = item == null ? null : _heroArt(item);
    if (url == null || url.isEmpty) {
      _emitAmbient(null, null);
      return;
    }

    // Publish FIRST from cache when we have it. Skipping the publish for a
    // cached URL meant paging A→B→A left B's art and tint on the shell —
    // the cache short-circuited the only code path that told anyone.
    if (_owners.hero.tints.containsKey(url)) {
      _emitAmbient(url, _owners.hero.tints[url]);
    } else {
      // Update the shell immediately; colour extraction may wait on a decode.
      _emitAmbient(url, null);
      final tint = await extractDominantColor(
        CachedNetworkImageProvider(
          url,
          cacheManager: DebrifyImageCache.manager,
        ),
      );
      if (!mounted || gen != _owners.hero.probeGen) return;
      setState(() => _remember(url, tint));
      _emitAmbient(url, tint);
    }
    unawaited(_warmNext());
  }

  /// Luminance of the extracted colour stands in for "is the left third busy":
  /// a bright dominant means a bright image, and a bright image is one whose
  /// text side cannot be trusted. A true left-third measurement would be
  /// better and is noted in the plan.
  void _remember(String url, Color? tint) {
    _owners.hero.leftThird[url] = tint == null ? 0.0 : tint.computeLuminance();
    _owners.hero.tints[url] = tint;
  }

  /// Resolve the NEXT slide's art while this one is still showing.
  ///
  /// Without this, freezing the side below would mean every slide's FIRST
  /// appearance used the default side, because the probe cannot possibly have
  /// finished by the time the slide is drawn. The cadence gives us seconds of
  /// lead time; one image is a cheap way to spend it.
  Future<void> _warmNext() async {
    if (widget.hero.length < 2) return;
    final next = widget.hero[(_heroIndex + 1) % widget.hero.length];
    final url = _heroArt(next);
    if (url == null || url.isEmpty || _owners.hero.tints.containsKey(url)) {
      return;
    }
    final tint = await extractDominantColor(
      CachedNetworkImageProvider(url, cacheManager: DebrifyImageCache.manager),
    );
    if (!mounted) return;
    setState(() => _remember(url, tint));
  }

  @visibleForTesting
  String? get heroAlignmentItemId => _owners.hero.flipFor;

  /// The side the identity sits on, FROZEN for as long as an item is showing.
  ///
  /// This used to read `_leftThird` directly on every build. That map is
  /// filled by an async probe, so a slide appeared with its logo on one side
  /// and then, a second or two later, jumped to the other as the probe landed
  /// — the one thing a title card must never do while someone is reading it.
  ///
  /// Memoised by item id rather than recomputed: a probe that resolves for the
  /// slide currently on screen updates the map for NEXT time, and moves
  /// nothing now. `_warmNext` is what keeps "next time" from being the common
  /// case.
  bool get _flip {
    final item = _heroItem;
    if (item == null) return false;
    // The missing URL is temporary during provider loading. Do not freeze
    // the default side before the resolved artwork's cached tint is usable.
    if (metadataArtworkPending(MetadataCategory.backgrounds)) return false;
    if (_owners.hero.flipFor != item.id) {
      _owners.hero.flipFor = item.id;
      final url = _heroArt(item);
      _owners.hero.flipValue =
          url != null &&
          (_owners.hero.leftThird[url] ?? 0) > SpotlightBoard.leftThirdBusy;
    }
    return _owners.hero.flipValue;
  }

  // ── movement ───────────────────────────────────────────────────────────
  void _go(FocusNode node, Offset dir) {
    ParallaxTravel.note(dir);
    node.requestFocus();
  }

  void _page(int delta) {
    if (widget.hero.length < 2) return;
    final n = widget.hero.length;
    final next = (_heroIndex + delta + n) % n;
    if (widget.hero[next].id == _owners.hero.heroId) return;
    _stopRolling();
    _owners.hero.dwelledHeroId = null;
    setState(() => _owners.hero.heroId = widget.hero[next].id);
    refreshMetadataPresentation();
    ParallaxTravel.note(Offset(delta.toDouble(), 0));
    _probe();
    _restartCadence();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!(ModalRoute.isCurrentOf(context) ?? true)) {
      _owners.navigation.pendingProgressiveDown = null;
    }
  }

  void _finishProgressiveDown() {
    if (_owners.navigation.pendingProgressiveDown == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = _owners.navigation.pendingProgressiveDown;
      if (!mounted || pending == null) return;
      if (!(ModalRoute.isCurrentOf(context) ?? true) ||
          !identical(FocusManager.instance.primaryFocus, pending.origin) ||
          DateTime.now().difference(pending.at) > const Duration(seconds: 3)) {
        _owners.navigation.pendingProgressiveDown = null;
        return;
      }
      final row = widget.sections.indexWhere(
        (s) => s.nodes.contains(pending.origin),
      );
      if (row < 0 || row + 1 >= widget.sections.length) {
        if (!widget.pendingShelves) {
          _owners.navigation.pendingProgressiveDown = null;
        }
        return;
      }
      _owners.navigation.pendingProgressiveDown = null;
      setState(() => _owners.navigation.row = row + 1);
      _focusRow(_owners.navigation.row, const Offset(0, 1));
    });
  }

  Future<void> _loadShelvesAndFinishDown() async {
    final load = widget.onLoadMoreShelves;
    if (load == null || _owners.navigation.loadingMoreShelves) return;

    final origin = FocusManager.instance.primaryFocus;
    final oldLength = widget.sections.length;
    setState(() => _owners.navigation.loadingMoreShelves = true);

    var appended = false;
    try {
      appended = await load();
    } catch (_) {
      // A catalog failure is recoverable: leave focus where it was so another
      // DOWN can retry, and always remove the loading acknowledgement below.
    }
    if (!mounted) return;
    setState(() => _owners.navigation.loadingMoreShelves = false);
    if (!appended) {
      if (widget.pendingShelves && origin != null) {
        _owners.navigation.pendingProgressiveDown = (
          origin: origin,
          at: DateTime.now(),
        );
        _finishProgressiveDown();
      }
      return;
    }

    // The host's setState that appended the shelves mounts their focus nodes
    // on the next frame. Complete the original DOWN only if the user is still
    // on the exact card that requested it; a slow addon must never pull focus
    // back after they moved sideways or opened the sidebar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.sections.length <= oldLength) return;
      // Inserting a leading shelf reuses the positional shelf elements and can
      // briefly detach [origin], leaving primaryFocus null. That is safe to
      // recover. A different focused node means the user deliberately moved;
      // a different route means they opened content while the addon loaded.
      final primary = FocusManager.instance.primaryFocus;
      if ((primary != null && !identical(primary, origin)) ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      // Continue Watching and favourites resolve independently and can insert
      // shelves at the front while the catalog request is in flight. Find the
      // origin by its stable FocusNode after the rebuild instead of assuming
      // the old list length is still the appended shelf's index.
      final currentRow = widget.sections.indexWhere(
        (section) => section.nodes.contains(origin),
      );
      if (currentRow < 0 || currentRow + 1 >= widget.sections.length) return;
      setState(() => _owners.navigation.row = currentRow + 1);
      _focusRow(_owners.navigation.row, const Offset(0, 1));
    });
  }

  /// Touch has no focused last shelf to retain while a batch loads. It still
  /// uses the same in-flight guard as DPAD, but deliberately leaves focus
  /// alone when the host appends the new shelves.
  Future<void> _loadMoreShelvesForTouch() async {
    final load = widget.onLoadMoreShelves;
    if (widget.dpad || load == null || _owners.navigation.loadingMoreShelves) {
      return;
    }

    setState(() => _owners.navigation.loadingMoreShelves = true);
    try {
      await load();
    } catch (_) {
      // A later scroll can retry a recoverable catalog failure.
    } finally {
      if (mounted) {
        setState(() => _owners.navigation.loadingMoreShelves = false);
      }
    }
  }

  void _down() {
    if (_owners.navigation.row < 0) {
      if (widget.sections.isEmpty) return;
      _stopRolling();
      setState(() => _owners.navigation.row = 0);
      _owners.hero.cadence?.cancel();
      _focusRow(0, const Offset(0, 1));
      return;
    }
    if (_owners.navigation.row + 1 >= widget.sections.length) {
      // Out of shelves: retain this DOWN while the next batch loads. When it
      // lands, focus advances into its first shelf without a second keypress.
      unawaited(_loadShelvesAndFinishDown());
      return;
    }
    setState(() => _owners.navigation.row = _owners.navigation.row + 1);
    _focusRow(_owners.navigation.row, const Offset(0, 1));
  }

  void _up() {
    if (_owners.navigation.row <= 0) {
      if (widget.shelvesOnly) {
        widget.onExitTop?.call();
        return;
      }
      // Local shelves can precede hero data. Do not leave a pending focus
      // request that steals the cursor when the hero eventually mounts.
      if (widget.hero.isEmpty || !(widget.heroNode.context?.mounted ?? false)) {
        return;
      }
      setState(() => _owners.navigation.row = -1);
      _restartCadence();
      _go(widget.heroNode, const Offset(0, -1));
      _owners.scroll.scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    setState(() => _owners.navigation.row = _owners.navigation.row - 1);
    _focusRow(_owners.navigation.row, const Offset(0, -1));
  }

  void _focusRow(int row, Offset dir, {bool retried = false}) {
    if (row < 0 || row >= widget.sections.length) return;
    final nodes = widget.sections[row].nodes;
    if (nodes.isEmpty) return;
    final col = (_owners.navigation.col[row] ?? 0).clamp(0, nodes.length - 1);
    bool attached(FocusNode n) => n.context?.mounted ?? false;
    final target = nodes[col];
    if (attached(target)) {
      _go(target, dir);
      return;
    }
    // The remembered column's CELL isn't built — the row is parked at a
    // different offset (its ListView only builds near its own scroll
    // position), or a stale column survived a shelf insert. Focusing a
    // detached node is a silent no-op, which read as "DOWN sometimes does
    // nothing". Land on the nearest BUILT cell instead; the remembered
    // column follows so the next vertical move starts from reality.
    FocusNode? nearest;
    var bestDistance = 1 << 30;
    for (var i = 0; i < nodes.length; i++) {
      final d = (i - col).abs();
      if (d < bestDistance && attached(nodes[i])) {
        bestDistance = d;
        nearest = nodes[i];
        _owners.navigation.col[row] = i;
      }
    }
    if (nearest != null) {
      _go(nearest, dir);
      return;
    }
    // The whole row is outside the lazy build window. Nudge the board's
    // scroll toward it so the builder mounts it, then finish the move next
    // frame — once only, so a row that stays unbuildable can't loop.
    if (retried || !_owners.scroll.scroll.hasClients) return;
    final position = _owners.scroll.scroll.position;
    final step = (dir.dy >= 0 ? 1.0 : -1.0) * 300.0;
    position.moveTo(
      (position.pixels + step).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusRow(row, dir, retried: true);
    });
  }

  /// Enter a collection at its selected category, including off-screen rows.
  void focusShelf(int row) {
    if (row < 0 || row >= widget.sections.length) return;
    final metrics = _owners.scroll.lastMetrics;
    if (metrics == null || !_owners.scroll.scroll.hasClients) return;
    setState(() => _owners.navigation.row = row);
    final offset = widget.sections
        .take(row)
        .fold<double>(0, (sum, shelf) => sum + _shelfExtent(shelf, metrics));
    // A lazy list's maximum is only an estimate until distant rows mount.
    // Let layout clamp this exact offset, rather than stopping at that estimate.
    _owners.scroll.scroll.jumpTo(offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusRow(row, const Offset(0, 1));
    });
  }

  /// Where the cursor ACTUALLY is in [nodes].
  ///
  /// `_col` is bookkeeping and can drift — a scroll-into-view, a rebuild, or
  /// anything that moves focus without going through `_walk` leaves it stale.
  /// A stale column is what made LEFT fall through while focus sat mid-row,
  /// handing the key to the shell's geometric search, which then jumped to
  /// whatever row happened to be nearest.
  int _liveCol(List<FocusNode> nodes) {
    final i = nodes.indexWhere((n) => n.hasFocus);
    if (i >= 0) return i;
    return (_owners.navigation.col[_owners.navigation.row] ?? 0).clamp(
      0,
      nodes.length - 1,
    );
  }

  /// The shelf that actually holds focus, or -1 for the hero.
  int _liveRow() {
    for (var i = 0; i < widget.sections.length; i++) {
      if (widget.sections[i].nodes.any((n) => n.hasFocus)) return i;
    }
    return -1;
  }

  void _walk(int delta) {
    if (_owners.navigation.row < 0 ||
        _owners.navigation.row >= widget.sections.length) {
      _page(delta);
      return;
    }
    final nodes = widget.sections[_owners.navigation.row].nodes;
    if (nodes.isEmpty) return;
    final at = _liveCol(nodes);
    final next = at + delta;
    if (widget.shelvesOnly && delta > 0 && next >= nodes.length) {
      widget.onLoadMoreRow?.call(_owners.navigation.row);
    }
    if (next < 0 || next >= nodes.length) return;
    // No setState: a horizontal step changes nothing this board PAINTS —
    // the cursor's visuals live inside each cell's own Focus widget, and
    // `_col` is read only by the focus-targeting helpers. Wrapped in
    // setState it rebuilt the hero stack and every shelf shell on every
    // LEFT/RIGHT of a held key — per-keypress cost a MiBox-class CPU
    // renders as visible lag.
    _owners.navigation.col[_owners.navigation.row] = next;
    _go(nodes[next], Offset(delta.toDouble(), 0));
    // Four from the end is roughly one screen of posters — enough lead time
    // for a page to land before the cursor reaches where it would have
    // stopped.
    if (next >= nodes.length - 4) {
      widget.onLoadMoreRow?.call(_owners.navigation.row);
    }
  }

  KeyEventResult _onKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Re-sync from reality before acting on it.
    final live = _liveRow();
    if (live != _owners.navigation.row) _owners.navigation.row = live;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _down();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _up();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _walk(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.gameButtonA:
        // The hero was focusable and inert: arrows paged it, but OK did
        // nothing at all, so the reel could be browsed and never opened.
        final item = _heroItem;
        final addon = widget.heroAddon;
        if (_owners.navigation.row < 0 && item != null && addon != null) {
          _openHero();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.arrowLeft:
        // Column 0 and LEFT again falls THROUGH, so the shell's sidebar
        // handler sees it. That is the one and only way in, per the LEFT-only
        // policy — nothing here calls focusTvSidebar.
        //
        // Tested against LIVE focus, not `_col`: falling through from the
        // middle of a row hands the key to a geometric search that lands in
        // another row, which is what made the sidebar hard to reach.
        if (_owners.navigation.row >= 0 &&
            _owners.navigation.row < widget.sections.length) {
          final nodes = widget.sections[_owners.navigation.row].nodes;
          if (nodes.isEmpty || _liveCol(nodes) == 0) {
            return KeyEventResult.ignored;
          }
        }
        // The hero obeys the same rule as a shelf: at the FIRST item there is
        // nothing to its left but the sidebar. It used to wrap round to the
        // last slide instead, which made the reel a loop with no exit — the
        // one gesture that opens the sidebar was the one gesture it ate.
        if (_owners.navigation.row < 0 &&
            (widget.hero.length < 2 || _heroIndex == 0)) {
          return KeyEventResult.ignored;
        }
        _walk(-1);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Initial entry and re-entry must only target mounted content. Shelves
  /// may arrive before the independently loaded hero, and late hero data
  /// must not move an already placed card cursor.
  FocusNode? focusTarget() {
    bool available(FocusNode node) =>
        (node.context?.mounted ?? false) && node.canRequestFocus;
    if (widget.heroNode.hasFocus && available(widget.heroNode)) {
      return widget.heroNode;
    }
    for (final section in widget.sections) {
      for (final node in section.nodes) {
        if (node.hasFocus && available(node)) return node;
      }
    }
    if (_owners.navigation.row >= 0 &&
        _owners.navigation.row < widget.sections.length) {
      final nodes = widget.sections[_owners.navigation.row].nodes;
      if (nodes.isNotEmpty) {
        final col = (_owners.navigation.col[_owners.navigation.row] ?? 0).clamp(
          0,
          nodes.length - 1,
        );
        if (available(nodes[col])) return nodes[col];
        for (final node in nodes) {
          if (available(node)) return node;
        }
      }
    }
    if (widget.hero.isNotEmpty && available(widget.heroNode)) {
      return widget.heroNode;
    }
    for (final section in widget.sections) {
      for (final node in section.nodes) {
        if (available(node)) return node;
      }
    }
    return null;
  }

  // ── paint ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) => _onKey(e),
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
              _queueScrollSelection();
            }
            if (large != _owners.selection.largeCardInteractions) {
              _owners.selection.largeCardInteractions = large;
              _owners.selection.scrollingSources.clear();
              _queueScrollSelection();
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
          _onBoardScrolled();
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
        onNotification: _onCardScroll,
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
    final item = _heroItem;
    if (item == null) return const SizedBox.shrink();
    final url = _heroArt(item);
    final posterUrl = _heroPoster(item);
    final app = AppThemeScope.of(context);
    final ground = SpotlightBoard.groundOf(app);
    final rolling = _owners.hero.rolling;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 120) return;
        _jumpTo(
          (_heroIndex + (v < 0 ? 1 : -1) + widget.hero.length) %
              widget.hero.length,
        );
      },
      onTap: () {
        final addon = widget.heroAddon;
        if (addon != null) _openHero();
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
              memCacheWidth: _heroDecodeWidth,
              fadeInDuration: _heroImageFadeIn,
              fadeOutDuration: _heroImageFadeOut,
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
            if (addon != null) _openHero();
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
    final item = _heroItem;
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
        _jumpTo(
          (_heroIndex + (v < 0 ? 1 : -1) + widget.hero.length) %
              widget.hero.length,
        );
      },
      onTap: () {
        final addon = widget.heroAddon;
        if (addon != null) _openHero();
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
    final item = _heroItem;
    if (item == null) return const SizedBox.shrink();
    final url = _heroArt(item);
    final posterUrl = _heroPoster(item);
    final flip = _flip;
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
            memCacheWidth: _heroDecodeWidth,
            fadeInDuration: _heroImageFadeIn,
            fadeOutDuration: _heroImageFadeOut,
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
    final flip = _flip;
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
          onTap: tappable ? () => _jumpTo(i) : null,
          behavior: tappable ? HitTestBehavior.opaque : null,
          child: Padding(
            padding: tappable
                ? const EdgeInsets.symmetric(horizontal: 2, vertical: 8)
                : EdgeInsets.zero,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 2.25),
              width: i == _heroIndex ? 11 : 4,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: i == _heroIndex ? 0.95 : 0.34,
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
                register: _registerCard,
                unregister: _unregisterCard,
                onInteraction: _interactWithCard,
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
                    _onDesktopPreviewActivityChanged,
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
}

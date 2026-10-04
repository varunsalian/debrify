import 'dart:async';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_card_layout.dart';
import 'package:debrify/features/spotlight_board/presentation/spotlight_board_types.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/metadata_presentation_mixin.dart';
import 'package:flutter/material.dart';

class SpotlightBoardCard extends StatefulWidget {
  final Object? rowId;
  final bool largeInteractions;
  final void Function(SpotlightBoardCardState)? register;
  final void Function(SpotlightBoardCardState)? unregister;
  final void Function(SpotlightBoardCardState, bool)? onInteraction;
  final SpotlightCard card;
  final FocusNode? node;

  /// The ROW's height. Width follows from the shape's aspect, so a shelf that
  /// mixes posters and channel tiles keeps one baseline.
  final double height;
  final double expandedHeight;
  final double caption;
  final double radius;

  /// Compact: the caption sits BELOW the art (small art can't afford an
  /// overlay eating its bottom quarter — the measured Apple phone idiom).
  /// Wide keeps the overlay-on-gradient the TV mock specifies.
  final bool captionBelow;
  final double captionBlock;

  /// False = no caption in EITHER position (and no caption gradient bed) —
  /// the caption-free catalog card off TV, where the art is the label. The
  /// progress bar is independent of this and always paints.
  final bool showCaption;

  /// False suppresses only title/rating text. Subtitles such as episode
  /// context remain available when a shelf has useful card metadata.
  final bool showTitleAndRating;
  final bool expandOnFocus;
  final bool forceParallax;
  final bool trailerEnabled;
  final double trailerVolume;
  final VoidCallback? onTrailerStart;

  /// Pointer hover lifts the card — desktop only. OFF on TV: an Apple TV
  /// trackpad delivers pointer events (see main.dart), and a hover lift
  /// independent of DPAD focus would put two cursors on a board that had
  /// exactly one at HEAD.
  final bool hoverable;

  /// Selects the input that owns an optional card preview: hover on a pointer
  /// board, focus on a DPAD board. This deliberately does not use `_f || _h`:
  /// a desktop card that retains keyboard focus while the pointer rests on a
  /// different card must not leave a second live stream decoding offscreen.
  final bool dpad;

  /// Announces a pointer-owned live preview before it mounts, so the board
  /// can release the hero trailer's single video-output lease first.
  final void Function(Object owner, bool active)?
  onDesktopPreviewActivityChanged;

  const SpotlightBoardCard({
    this.rowId,
    this.largeInteractions = false,
    this.register,
    this.unregister,
    this.onInteraction,
    required this.card,
    required this.node,
    required this.height,
    required this.expandedHeight,
    required this.caption,
    this.radius = 7,
    this.captionBelow = false,
    this.captionBlock = 0,
    this.showCaption = true,
    this.showTitleAndRating = true,
    this.expandOnFocus = false,
    this.forceParallax = false,
    this.trailerEnabled = false,
    this.trailerVolume = 0,
    this.onTrailerStart,
    this.hoverable = false,
    this.dpad = true,
    this.onDesktopPreviewActivityChanged,
  });

  @override
  State<SpotlightBoardCard> createState() => SpotlightBoardCardState();
}

class SpotlightBoardCardState extends State<SpotlightBoardCard>
    with MetadataPresentationMixin<SpotlightBoardCard> {
  SpotlightBoardCardLayout? _cachedLayout;
  SpotlightBoardCardLayout get _layout =>
      _cachedLayout ??= SpotlightBoardCardLayout(this, setState);
  double paintedGrowth = 1;

  double? scrollGrowth;

  void freezeScrollWidth(bool scrolling) {
    if (scrolling == (scrollGrowth != null)) return;
    setState(() => scrollGrowth = scrolling ? paintedGrowth : null);
  }

  bool wideSelected = false;

  bool moving = false;

  bool get activeCard => widget.largeInteractions ? wideSelected : f;

  bool? lastReducedMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (lastReducedMotion != null &&
        lastReducedMotion != reduced &&
        widget.largeInteractions) {
      trailerAttempted = false;
      armCardTrailer();
    }
    lastReducedMotion = reduced;
  }

  @override
  void initState() {
    super.initState();
    widget.register?.call(this);
  }

  void setWideSelection(bool selected, {required bool moving}) {
    if (wideSelected == selected && moving == moving) return;
    setState(() {
      wideSelected = selected;
      moving = moving;
    });
    armCardTrailer();
    loadFocusedDescription();
    reportDesktopPreviewActivity(cardPreviewActive);
  }

  @override
  StremioMeta? get originalMetadata => widget.card.metadata;

  bool f = false;

  Timer? trailerDwell;

  bool trailerRequested = false;

  bool trailerPlaying = false;

  bool trailerAttempted = false;

  bool hideTrailerText = false;

  Timer? trailerTextTimer;

  void armCardTrailer() {
    trailerDwell?.cancel();
    trailerTextTimer?.cancel();
    hideTrailerText = false;
    if (!activeCard || moving) trailerAttempted = false;
    trailerRequested = false;
    trailerPlaying = false;
    if (trailerAttempted ||
        !activeCard ||
        moving ||
        !canExpand ||
        !widget.trailerEnabled ||
        MediaQuery.disableAnimationsOf(context))
      return;
    trailerDwell = Timer(const Duration(seconds: 2), () {
      if (!mounted ||
          !activeCard ||
          moving ||
          !widget.trailerEnabled ||
          !canExpand ||
          ModalRoute.of(context)?.isCurrent == false ||
          !TickerMode.of(context) ||
          (WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed))
        return;
      widget.onTrailerStart?.call();
      trailerAttempted = true;
      setState(() => trailerRequested = true);
    });
  }

  Timer? descriptionTimer;

  String? resolvedDescription;

  Object? descriptionScope;

  int descriptionRequest = 0;

  void loadFocusedDescription() {
    descriptionTimer?.cancel();
    final request = ++descriptionRequest;
    final item = originalMetadata;
    if (!canExpand || !activeCard || moving || item == null) return;
    final scope = ProfileRuntime.scope.value;
    bool current() =>
        mounted &&
        activeCard &&
        canExpand &&
        request == descriptionRequest &&
        identical(originalMetadata, item) &&
        ProfileRuntime.scope.value == scope;
    descriptionTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final prefs = await MetadataPreferencesService.loadForBackground(
          isCurrent: current,
        );
        if (prefs == null || !current()) return;
        if (prefs.provider(MetadataCategory.information) !=
                MetadataPreferences.current &&
            !prefs.fallback)
          return;
        if ((heroPresentation?.description ?? '').trim().isNotEmpty) return;
        final imdb = item.effectiveImdbId;
        if (imdb == null) return;
        final details = await StremioService.instance.fetchMetaDetails(
          imdbId: imdb,
          type: item.type,
        );
        if (!current()) return;
        final description = details?.description?.trim();
        if (description == null || description.isEmpty) return;
        setState(() {
          resolvedDescription = description;
          descriptionScope = scope;
        });
      } catch (_) {
        // Optional metadata must never interrupt remote navigation.
      }
    });
  }

  /// DPAD centre is a key gesture, not a pointer long-press. Keep the short
  /// press for opening Details, but let a held press reach the card's options
  /// action (Continue Watching's preference-aware Play/Remove handler).
  late final TvHoldOk hold = TvHoldOk(
    onTap: () => widget.card.onOpen(),
    onHold: () => widget.card.onOptions?.call(),
  );

  /// Pointer hover — desktop's focus. Kept SEPARATE from [_f] and OR-ed at
  /// paint, so a pointer wandering off a card can never erase a real focus
  /// visual that a keyboard put there.
  bool h = false;

  final Object previewOwner = Object();

  bool previewActivityReported = false;

  bool get cardPreviewActive => widget.largeInteractions
      ? wideSelected && !moving
      : widget.dpad
      ? f
      : h || (widget.card.previewOnKeyboardFocus && f);

  void setHover(bool hovered) {
    if (h == hovered) return;
    setState(() => h = hovered);
    if (widget.largeInteractions) widget.onInteraction?.call(this, hovered);
    reportDesktopPreviewActivity(cardPreviewActive);
  }

  void reportDesktopPreviewActivity(bool active) {
    final report =
        active &&
        !widget.dpad &&
        (widget.card.previewBuilder != null ||
            widget.card.collectionVideoUrl != null ||
            (canExpand && widget.trailerEnabled));
    if (previewActivityReported == report) return;
    previewActivityReported = report;
    widget.onDesktopPreviewActivityChanged?.call(previewOwner, report);
  }

  @override
  void didUpdateWidget(SpotlightBoardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.metadata?.id != widget.card.metadata?.id ||
        oldWidget.card.metadata?.type != widget.card.metadata?.type) {
      trailerAttempted = false;
    }
    if (oldWidget.card.metadata?.id != widget.card.metadata?.id ||
        oldWidget.card.metadata?.type != widget.card.metadata?.type ||
        oldWidget.largeInteractions != widget.largeInteractions ||
        oldWidget.expandOnFocus != widget.expandOnFocus ||
        oldWidget.trailerEnabled != widget.trailerEnabled) {
      armCardTrailer();
    }
    if (!identical(oldWidget.card.metadata, widget.card.metadata) ||
        oldWidget.expandOnFocus != widget.expandOnFocus) {
      resolvedDescription = null;
      loadFocusedDescription();
    }
    final shouldReport =
        cardPreviewActive &&
        !widget.dpad &&
        (widget.card.previewBuilder != null ||
            widget.card.collectionVideoUrl != null ||
            (canExpand && widget.trailerEnabled));
    if (previewActivityReported && !shouldReport) {
      previewActivityReported = false;
      oldWidget.onDesktopPreviewActivityChanged?.call(previewOwner, false);
    } else if (!previewActivityReported && shouldReport) {
      previewActivityReported = true;
      widget.onDesktopPreviewActivityChanged?.call(previewOwner, true);
    }
  }

  @override
  void dispose() {
    widget.unregister?.call(this);
    trailerDwell?.cancel();
    trailerTextTimer?.cancel();
    descriptionTimer?.cancel();
    descriptionRequest++;
    hold.reset();
    if (previewActivityReported) {
      widget.onDesktopPreviewActivityChanged?.call(previewOwner, false);
    }
    super.dispose();
  }

  bool get canExpand =>
      widget.expandOnFocus &&
      (widget.dpad || widget.largeInteractions) &&
      (widget.card.metadata?.type == 'movie' ||
          widget.card.metadata?.type == 'series') &&
      !widget.captionBelow;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    // Focused title cards use the same landscape width and growth stages,
    // regardless of the resting poster preference.
    tween: Tween(
      end:
          scrollGrowth ??
          (canExpand && activeCard && !moving
              ? (widget.expandedHeight *
                        SpotlightCardShape.wide.aspect /
                        (widget.height * widget.card.shape.aspect)) *
                    (trailerPlaying ? 1.38 : 1.18)
              : 1.0),
    ),
    duration: scrollGrowth != null || MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : trailerPlaying
        ? const Duration(milliseconds: 700)
        : Duration(milliseconds: PlatformUtil.isAndroidTvCached ? 160 : 220),
    curve: Curves.easeOutCubic,
    builder: (context, growth, _) => _layout.buildCard(context, growth),
  );
}

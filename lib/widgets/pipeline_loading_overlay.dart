import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/play_loader_art.dart';
import '../theme/overlay_theme.dart';
import '../utils/platform_util.dart';

/// The real resolve stages a play flows through. The overlay shows the subset
/// relevant to the play (a bound-source play skips searching/cache; a provider
/// with no cache check skips [cacheCheck]).
enum PlayLoadStage { searching, cacheCheck, preparing, starting }

/// The two looks this loader wears — see `PlayLoaderStyleController` for the
/// stored preference and Settings → Appearance → Play Loader for the picker.
///
/// [show] defaults to [classic] deliberately: the widget keeps its shipped
/// behaviour for any caller that doesn't ask, and the play paths pass the
/// user's choice. The USER-facing default is Marquee, which lives in the pref.
enum PlayLoaderStyle { classic, marquee }

/// "The Pipeline" play loader — a cinematic overlay that ticks off each real
/// resolve stage (search → cache-check → prepare → start) instead of a frozen
/// spinner. Responsive: a poster-hero column on phones, a centered glass card
/// on desktop, and a full-bleed, D-pad-focusable layout on TV.
///
/// Handle-based like the poster overlay: [dismiss] pops exactly once, and
/// [setStage] advances the checklist live as the play flow progresses.

class PipelineLoadingOverlay {
  static const Color accent = Color(0xFF8B6BFF);

  final NavigatorState _nav;
  final ValueNotifier<_PlState> _state;
  final List<PlayLoadStage> _steps;
  RawDialogRoute<void>? _route;
  bool _dismissed = false;

  PipelineLoadingOverlay._(this._nav, this._state, this._steps);

  static PipelineLoadingOverlay show(
    BuildContext context, {
    String? posterUrl,
    required String title,
    String? subtitle,
    required String providerLabel,
    required String providerCode,
    required Color providerColor,
    bool bound = false,
    bool hasCacheCheck = false,
    Color? loaderGround,
    Color? loaderAccent,
    Color? loaderAccent2,
    Color? railFar,
    Color? ink,
    Color? inkOnFill,
    PlayLoaderStyle style = PlayLoaderStyle.classic,
    PlayLoaderArt? art,
    VoidCallback? onCancel,
  }) {
    final steps = <PlayLoadStage>[
      if (!bound) PlayLoadStage.searching,
      if (!bound && hasCacheCheck) PlayLoadStage.cacheCheck,
      PlayLoadStage.preparing,
      PlayLoadStage.starting,
    ];
    final state = ValueNotifier<_PlState>(_PlState(stage: steps.first));
    // Capture the ROOT navigator up front: it outlives the screen that started
    // the play, so dismiss() stays valid even if that screen is popped/replaced
    // while the loader is up.
    final nav = Navigator.of(context, rootNavigator: true);
    final handle = PipelineLoadingOverlay._(nav, state, steps);
    final tv = PlatformUtil.isTelevision;

    // RawDialogRoute skips InheritedTheme capture, and this loader is SHARED:
    // search_screen (themed) and Stremio TV (frozen) both launch it. Snapshot
    // the launcher's themes so it renders what its launcher renders — the
    // freeze included when launched from inside a LegacyThemeBoundary.
    final capturedThemes = captureAppThemes(context);

    // Pushed as an explicit route (not showGeneralDialog) so [dismiss] can
    // target THIS route: the play flow now keeps the loader up while the
    // player route/activity launches on top of it, and a blind pop() at that
    // point could pop the wrong screen.
    final route = RawDialogRoute<void>(
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => capturedThemes.wrap(PopScope(
        canPop: false,
        // Back cancels a cancelable play: dismiss immediately, THEN run the
        // caller's cancel — matching the Cancel button, so the overlay never
        // lingers (the flow's cancel-checks skip closeLoading assuming this).
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && onCancel != null) {
            handle.dismiss();
            onCancel();
          }
        },
        child: _PlContent(
          state: state,
          steps: steps,
          posterUrl: posterUrl,
          title: title,
          subtitle: subtitle,
          providerLabel: providerLabel,
          providerCode: providerCode,
          providerColor: providerColor,
          isTv: tv,
          loaderGround: loaderGround,
          loaderAccent: loaderAccent,
          loaderAccent2: loaderAccent2,
          railFar: railFar,
          ink: ink,
          inkOnFill: inkOnFill,
          style: style,
          art: art,
          onCancel: onCancel == null
              ? null
              : () {
                  handle.dismiss();
                  onCancel();
                },
        ),
      )),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    );
    handle._route = route;
    nav.push(route);
    return handle;
  }

  /// Advance the checklist. Counts are sticky — pass only what changed.
  ///
  /// Monotonic: a loading pipeline only moves forward. A stage this overlay
  /// doesn't display, or one earlier than the current, keeps the current stage
  /// (only its counts merge). This matters because the series pack-first phase
  /// can advance to "preparing" and then fall through to the episode search,
  /// which re-reports "searching" — without this the rail would rewind.
  void setStage(PlayLoadStage stage, {int? sourceCount, int? cachedCount}) {
    if (_dismissed) return;
    final s = _state.value;
    final curIdx = _steps.indexOf(s.stage);
    final newIdx = _steps.indexOf(stage);
    _state.value = _PlState(
      stage: newIdx > curIdx ? stage : s.stage,
      sourceCount: sourceCount ?? s.sourceCount,
      cachedCount: cachedCount ?? s.cachedCount,
      note: s.note,
    );
  }

  /// Free-text line under the checklist — quick-play's filter narration
  /// ("Matching your filters…", "No full filter match — trying without
  /// language…"). Unlike [setStage] it is NOT monotonic: it reflects the
  /// latest truth and may change repeatedly. Null hides the line.
  void setNote(String? note) {
    if (_dismissed) return;
    final s = _state.value;
    _state.value = _PlState(
      stage: s.stage,
      sourceCount: s.sourceCount,
      cachedCount: s.cachedCount,
      note: note,
    );
  }

  /// Idempotent, and safe at any point in the stack's life: pops normally
  /// when the loader is topmost, and removes its own route (never a blind
  /// pop) when something — e.g. the player route — was pushed on top of it.
  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    final route = _route;
    if (route == null || !_nav.mounted) return;
    if (route.isCurrent) {
      _nav.pop();
    } else if (route.isActive) {
      _nav.removeRoute(route);
    }
  }
}

class _PlState {
  final PlayLoadStage stage;
  final int? sourceCount;
  final int? cachedCount;
  final String? note;
  const _PlState({
    required this.stage,
    this.sourceCount,
    this.cachedCount,
    this.note,
  });
}

class _PlContent extends StatefulWidget {
  final ValueNotifier<_PlState> state;
  final List<PlayLoadStage> steps;
  final String? posterUrl;
  final String title;
  final String? subtitle;
  final String providerLabel;
  final String providerCode;
  final Color providerColor;
  final bool isTv;

  /// Caller-supplied palette, each defaulting to the literal it replaces.
  ///
  /// This overlay is pushed as a `RawDialogRoute`, so it deliberately does not
  /// resolve `AppThemeScope` itself — its launcher passes the tokens down and
  /// `captureAppThemes` carries the rest. Both launchers (Stremio TV and the
  /// Search/Home play path in `torrent_playback_service`) now pass real
  /// `stremioTv.loader*` tokens; omit them and it renders exactly as it
  /// shipped, which is what the overlay's own tests pump.
  final Color? loaderGround;
  final Color? loaderAccent;
  final Color? loaderAccent2;
  final Color? ink;
  final Color? inkOnFill;

  /// The progress rail's far gradient stop, paired with [loaderAccent].
  final Color? railFar;

  /// Which look to paint. [PlayLoaderStyle.marquee] uses [art] when it has a
  /// backdrop/logo and degrades to the poster when it doesn't.
  final PlayLoaderStyle style;
  final PlayLoaderArt? art;
  final VoidCallback? onCancel;

  const _PlContent({
    required this.state,
    required this.steps,
    required this.posterUrl,
    required this.title,
    required this.subtitle,
    required this.providerLabel,
    required this.providerCode,
    required this.providerColor,
    required this.isTv,
    required this.onCancel,
    this.style = PlayLoaderStyle.classic,
    this.art,
    this.loaderGround,
    this.loaderAccent,
    this.loaderAccent2,
    this.ink,
    this.inkOnFill,
    this.railFar,
  });

  @override
  State<_PlContent> createState() => _PlContentState();
}

class _PlContentState extends State<_PlContent> with TickerProviderStateMixin {
  late final AnimationController _kb;

  /// Drives the active segment's crawl on the Marquee rail. Separate from the
  /// Ken Burns controller because it runs even with no artwork at all.
  late final AnimationController _crawl;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _kb = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    _crawl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    // Only drive the Ken Burns controller when there's a backdrop to animate
    // (classic TV renders the static gradient backdrop — see _backdrop).
    final animatePlate = _marquee ? _hasPlate : (!widget.isTv && _hasPoster);
    if (!_reduceMotion && animatePlate && !_kb.isAnimating) {
      _kb.repeat(reverse: true);
    }
    if (_marquee && !_reduceMotion && !_crawl.isAnimating) {
      _crawl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _kb.dispose();
    _crawl.dispose();
    super.dispose();
  }

  bool get _hasPoster => widget.posterUrl != null && widget.posterUrl!.isNotEmpty;

  bool get _marquee => widget.style == PlayLoaderStyle.marquee;

  /// The Marquee plate: the backdrop when the caller had one, otherwise the
  /// poster (blurred, as the classic backdrop always was).
  String? get _plateUrl {
    final backdrop = widget.art?.backdropUrl;
    if (backdrop != null && backdrop.isNotEmpty) return backdrop;
    return _hasPoster ? widget.posterUrl : null;
  }

  bool get _hasPlate => _plateUrl != null;

  /// A poster stretched to fill a 16:9 plate is unreadable — blur it, which is
  /// also exactly what the classic backdrop did with the same image.
  bool get _plateIsPoster =>
      (widget.art?.backdropUrl == null || widget.art!.backdropUrl!.isEmpty);

  // The palette, resolved once: each falls back to the literal it replaced, so
  // a caller that passes nothing renders exactly as this overlay shipped.
  Color get _ground => widget.loaderGround ?? const Color(0xFF201636);
  Color get _accent => widget.loaderAccent ?? const Color(0xFF8B6BFF);
  Color get _accent2 => widget.loaderAccent2 ?? const Color(0xFFB9A6FF);
  Color get _ink => widget.ink ?? Colors.white;
  Color get _inkOnFill => widget.inkOnFill ?? const Color(0xFF0A0712);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final landscape = widget.isTv || size.width >= 880;
    // This surface stays a dark cinematic plate on every theme (its Material
    // ground, scrims and vignettes are all black at alpha), so its ink is
    // `onGlass` — page ink would go near-black on a paper theme and vanish.
    if (_marquee) return _marqueeBuild(size, landscape);
    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _backdrop(),
          _scrim(landscape),
          _TopRail(
            state: widget.state,
            steps: widget.steps,
            accent: _accent,
            railFar: widget.railFar ?? const Color(0xFFC4B2FF),
          ),
          SafeArea(
            child: landscape ? _landscape(size) : _portrait(),
          ),
        ],
      ),
    );
  }

  // ── Backdrop ────────────────────────────────────────────────────────────
  Widget _backdrop() {
    // TV: the blurred Ken-Burns poster is a per-frame full-screen 26px blur —
    // the single most expensive effect a weak TV GPU can be asked for. The
    // gradient (the no-poster look) is free; the foreground poster card still
    // carries the artwork.
    if (!_hasPoster || widget.isTv) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.3),
            radius: 1.1,
            colors: [
              _ground,
              // No token holds this near-black far stop; it stays a literal.
              const Color(0xFF08060D),
            ],
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _kb,
      builder: (_, __) {
        final t = _reduceMotion ? 0.5 : _kb.value;
        return Transform.scale(
          scale: 1.04 + 0.12 * t,
          child: Transform.translate(
            offset: Offset(-6 * t, -10 * t),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              child: Image.network(
                widget.posterUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _scrim(bool landscape) {
    if (landscape && widget.isTv) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xEB06040B), Color(0xB806040B), Color(0x3D06040B)],
            stops: [0, 0.42, 0.82],
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.5),
            Colors.black.withValues(alpha: 0.72),
            Colors.black.withValues(alpha: 0.92),
          ],
        ),
      ),
    );
  }

  // ── Marquee ─────────────────────────────────────────────────────────────
  /// Full-bleed plate, the title's logo art, and the resolve stages collapsed
  /// onto a segmented rail. Degrades all the way down: no backdrop → the
  /// blurred poster (what the classic backdrop always was), no artwork at all →
  /// the ground gradient, no logo art → the title set as type.
  Widget _marqueeBuild(Size size, bool landscape) {
    final scale = widget.isTv
        ? (size.width / 960).clamp(1.0, 1.55).toDouble()
        : 1.0;
    final body = _marqueeBody(size, landscape, scale);
    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _marqueePlate(),
          _marqueeScrim(landscape),
          SafeArea(
            child: landscape
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        // TV-safe margin on TV, a desktop gutter elsewhere.
                        horizontal: widget.isTv ? size.width * 0.06 : 44,
                        vertical: 24,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: (size.width * (widget.isTv ? 0.56 : 0.6))
                              .clamp(320.0, 760.0),
                        ),
                        child: body,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(26, 24, 26, 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Bottom-anchored, and scrollable when a short or
                        // split-screen phone can't fit the column — the
                        // checklist card's overflow lesson, kept.
                        Flexible(
                          child: SingleChildScrollView(
                            reverse: true,
                            child: body,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _marqueePlate() {
    final url = _plateUrl;
    final blur = _plateIsPoster;
    // No artwork, or a poster on TV: the blurred full-screen plate is the most
    // expensive effect a weak TV GPU can be asked for, and a poster stretched
    // to 16:9 needs that blur to be legible. Both fall back to the gradient.
    if (url == null || (blur && widget.isTv)) return _marqueeGround();

    Widget image = Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _marqueeGround(),
    );
    if (blur) {
      image = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: image,
      );
    }
    return AnimatedBuilder(
      animation: _kb,
      builder: (_, child) {
        final t = _reduceMotion ? 0.5 : _kb.value;
        return Transform.scale(
          scale: 1.03 + (blur ? 0.12 : 0.06) * t,
          child: Transform.translate(
            offset: Offset(-5 * t, -8 * t),
            child: child,
          ),
        );
      },
      child: image,
    );
  }

  Widget _marqueeGround() => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(0, -0.35),
        radius: 1.15,
        // No token holds this near-black far stop; it stays a literal, as in
        // the classic backdrop.
        colors: [_ground, const Color(0xFF08060D)],
      ),
    ),
  );

  /// Real key art is bright, and this plate carries every word of UI on it —
  /// so the scrim does real work rather than a token gradient.
  Widget _marqueeScrim(bool landscape) {
    if (landscape) {
      return Stack(
        fit: StackFit.expand,
        children: const [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xF505040B),
                  Color(0xEB05040B),
                  Color(0x7005040B),
                  Color(0x1405040B),
                ],
                stops: [0, 0.38, 0.66, 0.94],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xEB05040B), Color(0x5905040B), Color(0x0005040B)],
                stops: [0, 0.34, 0.62],
              ),
            ),
          ),
        ],
      );
    }
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x2E05040B),
            Color(0x8C05040B),
            Color(0xE605040B),
            Color(0xFF05040B),
          ],
          stops: [0, 0.34, 0.58, 0.88],
        ),
      ),
    );
  }

  Widget _marqueeBody(Size size, bool landscape, double scale) {
    final ink = _ink;
    final crawl = _reduceMotion
        ? const AlwaysStoppedAnimation<double>(0.55)
        : _crawl.view;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.subtitle != null) ...[
          Text(
            widget.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _accent2,
              fontSize: 12 * scale,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 10 * scale),
        ],
        _marqueeIdentity(landscape, scale),
        SizedBox(height: 12 * scale),
        _marqueeMeta(size, scale),
        SizedBox(height: 22 * scale),
        _StageRail(
          state: widget.state,
          steps: widget.steps,
          crawl: crawl,
          accent: _accent,
          accent2: _accent2,
          railFar: widget.railFar ?? const Color(0xFFC4B2FF),
          ink: ink,
          scale: scale,
        ),
        SizedBox(height: 14 * scale),
        _MarqueeStatus(
          state: widget.state,
          steps: widget.steps,
          accent2: _accent2,
          ink: ink,
          scale: scale,
        ),
        _NoteLine(
          state: widget.state,
          scale: scale,
          accent2: _accent2,
          ink: ink,
        ),
        SizedBox(height: 22 * scale),
        Row(
          children: [
            _providerChip(),
            const Spacer(),
            if (widget.onCancel != null)
              _CancelButton(
                onCancel: widget.onCancel!,
                isTv: widget.isTv,
                scale: scale,
                accent: _accent,
                ink: ink,
              ),
          ],
        ),
      ],
    );
  }

  /// Logo art when the title has it, the title as type when it doesn't — and
  /// the type again if the image fails, so a dead logo URL never leaves the
  /// plate untitled.
  Widget _marqueeIdentity(bool landscape, double scale) {
    final title = Text(
      widget.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: (landscape ? (widget.isTv ? 34 : 29) : 26) * scale,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1.03,
      ),
    );
    final logo = widget.art?.logoUrl;
    if (logo == null || logo.isEmpty) return title;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (landscape ? (widget.isTv ? 104 : 84) : 68) * scale,
          maxWidth: (landscape ? 460 : 300) * scale,
        ),
        // The logo REPLACES the title text, so it carries the title's
        // semantics — without this the only announced name on the plate would
        // be the provider chip.
        child: Image.network(
          logo,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          semanticLabel: widget.title,
          errorBuilder: (_, __, ___) => title,
        ),
      ),
    );
  }

  /// Rating · year · runtime · certificate · genres — whichever of them the
  /// play actually carried. Genres are the first thing dropped when the line
  /// would wrap on a phone.
  Widget _marqueeMeta(Size size, double scale) {
    final art = widget.art;
    final ink = _ink;
    final bits = <Widget>[];
    void text(String? value) {
      if (value == null || value.isEmpty) return;
      bits.add(
        Text(
          value,
          style: TextStyle(
            color: ink.withValues(alpha: 0.68),
            fontSize: 11.5 * scale,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    if (art?.ratingLabel != null) {
      bits.add(
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: 5 * scale,
            vertical: 1.5 * scale,
          ),
          decoration: BoxDecoration(
            // IMDb's brand yellow and its ink — fixed on every theme, like the
            // badge everywhere else in the app.
            color: const Color(0xFFF5C518),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'IMDb ${art!.ratingLabel}',
            style: TextStyle(
              color: const Color(0xFF0B0913),
              fontSize: 10 * scale,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
        ),
      );
    }
    text(art?.yearLabel);
    text(art?.runtimeLabel);
    text(art?.certificate);
    // A phone meta line fits four bits; genres are the fifth.
    if (size.width >= 430) text(art?.genreLabel);
    if (bits.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < bits.length; i++) {
      if (i > 0) {
        children.add(
          Container(
            width: 3 * scale,
            height: 3 * scale,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.32),
              shape: BoxShape.circle,
            ),
          ),
        );
      }
      children.add(bits[i]);
    }
    return Wrap(
      spacing: 8 * scale,
      runSpacing: 6 * scale,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  // ── Poster card ─────────────────────────────────────────────────────────
  Widget _posterCard(double width) {
    final loaderAccent = _accent;
    return Container(
      width: width,
      height: width * 1.5,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: loaderAccent.withValues(alpha: 0.32),
              blurRadius: 34,
              spreadRadius: 1),
          const BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 14)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _hasPoster
          ? Image.network(
              widget.posterUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _posterFallback(),
            )
          : _posterFallback(),
    );
  }

  Widget _posterFallback() {
    final ink = _ink;
    return ColoredBox(
      color: ink.withValues(alpha: 0.06),
      child: Center(
        child:
            Icon(Icons.movie_rounded, color: ink.withAlpha(0x3D), size: 34),
      ),
    );
  }

  // ── Layouts ─────────────────────────────────────────────────────────────
  Widget _portrait() {
    final ink = _ink;
    // Centered when it fits, scrollable when it doesn't (short / split-screen
    // phones), so the checklist + poster can never RenderFlex-overflow.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
          _posterCard(112),
          const SizedBox(height: 22),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (widget.subtitle != null) ...[
            const SizedBox(height: 5),
            Text(
              widget.subtitle!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink.withValues(alpha: 0.66), fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 26),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StepsList(
                  state: widget.state,
                  steps: widget.steps,
                  scale: 1,
                  accent: _accent,
                  ink: ink,
                  inkOnFill: _inkOnFill,
                ),
                _NoteLine(
                  state: widget.state,
                  scale: 1,
                  accent2: _accent2,
                  ink: ink,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _providerChip(),
                if (widget.onCancel != null) ...[
                  const SizedBox(height: 26),
                  _CancelButton(
                    onCancel: widget.onCancel!,
                    isTv: false,
                    scale: 1,
                    accent: _accent,
                    ink: ink,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _landscape(Size size) {
    final tv = widget.isTv;
    final scale = tv ? (size.width / 960).clamp(1.0, 1.7).toDouble() : 1.0;
    final posterW = tv ? 150.0 * scale : 130.0;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.subtitle != null)
          Text(
            widget.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _accent2,
              fontSize: 12.5 * scale,
              fontWeight: FontWeight.w700,
              letterSpacing: tv ? 1.2 : 0.2,
            ),
          ),
        SizedBox(height: 4 * scale),
        Text(
          widget.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: (tv ? 30 : 24) * scale,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.05,
          ),
        ),
        SizedBox(height: (tv ? 20 : 16) * scale),
        _StepsList(
          state: widget.state,
          steps: widget.steps,
          scale: tv ? 1.15 * scale : 1,
          accent: _accent,
          ink: _ink,
          inkOnFill: _inkOnFill,
        ),
        _NoteLine(
          state: widget.state,
          scale: tv ? 1.15 * scale : 1,
          accent2: _accent2,
          ink: _ink,
        ),
        SizedBox(height: (tv ? 22 : 16) * scale),
        Row(
          children: [
            _providerChip(),
            const Spacer(),
            if (widget.onCancel != null)
              _CancelButton(
                onCancel: widget.onCancel!,
                isTv: tv,
                scale: scale,
                accent: _accent,
                ink: _ink,
              ),
          ],
        ),
      ],
    );

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _posterCard(posterW),
        SizedBox(width: (tv ? 34 : 26) * scale),
        Flexible(child: body),
      ],
    );

    if (tv) {
      // Full-bleed, left-aligned inside a TV-safe margin.
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.06, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: size.width * 0.66),
            child: row,
          ),
        ),
      );
    }

    // Desktop — centered glass card.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 552),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            // The card's own two-stop plate: no token holds either literal, so
            // both stay pinned.
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xD1221A34), Color(0xCC0F0B19)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _ink.withValues(alpha: 0.12)),
            boxShadow: [
              const BoxShadow(color: Colors.black, blurRadius: 90, offset: Offset(0, 40), spreadRadius: -46),
              BoxShadow(color: _accent.withValues(alpha: 0.32), blurRadius: 70, offset: const Offset(0, 22), spreadRadius: -46),
            ],
          ),
          child: row,
        ),
      ),
    );
  }

  // ── Provider chip ───────────────────────────────────────────────────────
  Widget _providerChip() {
    final ink = _ink;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ink.withValues(alpha: 0.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 17,
            height: 17,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.providerColor,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              widget.providerCode,
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
                color: Color(0xFF06121F),
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            widget.providerLabel,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Thin top progress rail, driven by which stage is active.
class _TopRail extends StatelessWidget {
  final ValueNotifier<_PlState> state;
  final List<PlayLoadStage> steps;

  /// Both gradient stops. Previously pinned because the far stop had no token;
  /// it has one now (`stremioTv.loaderRailFar`), so the rail themes with the
  /// rest of the loader instead of running from a themed accent into a fixed
  /// violet.
  final Color accent;
  final Color railFar;
  const _TopRail({
    required this.state,
    required this.steps,
    required this.accent,
    required this.railFar,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 3,
        child: ValueListenableBuilder<_PlState>(
          valueListenable: state,
          builder: (context, st, _) {
            // Fraction from the active step's position within the SHOWN steps
            // (a subset in bound / no-cache-check modes), not the global enum.
            final n = steps.length;
            final idx = steps.indexOf(st.stage);
            final frac = n <= 0 ? 0.0 : ((idx < 0 ? n - 1 : idx) + 1) / n;
            return Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (0.08 + 0.9 * frac).clamp(0.08, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent, railFar],
                    ),
                    boxShadow: [
                      BoxShadow(color: accent, blurRadius: 10),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Marquee's stage rail: one segment per shown stage, done ones filled, the
/// active one crawling. Same monotonic stage source as the classic checklist —
/// only the shape differs.
class _StageRail extends StatelessWidget {
  final ValueNotifier<_PlState> state;
  final List<PlayLoadStage> steps;

  /// 0→1 crawl driver. A fixed [AlwaysStoppedAnimation] under reduced motion,
  /// so the active segment reads as in-progress without animating.
  final Animation<double> crawl;
  final Color accent;
  final Color accent2;
  final Color railFar;
  final Color ink;
  final double scale;

  const _StageRail({
    required this.state,
    required this.steps,
    required this.crawl,
    required this.accent,
    required this.accent2,
    required this.railFar,
    required this.ink,
    required this.scale,
  });

  /// Short forms — the full sentence lives in the status line below the rail.
  static String _short(PlayLoadStage s) {
    switch (s) {
      case PlayLoadStage.searching:
        return 'Search';
      case PlayLoadStage.cacheCheck:
        return 'Cache';
      case PlayLoadStage.preparing:
        return 'Prepare';
      case PlayLoadStage.starting:
        return 'Start';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_PlState>(
      valueListenable: state,
      builder: (context, st, _) {
        var active = steps.indexOf(st.stage);
        if (active < 0) active = 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < steps.length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: i == steps.length - 1 ? 0 : 8 * scale,
                      ),
                      child: Text(
                        _short(steps[i]).toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5 * scale,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: i == active
                              ? accent2
                              : ink.withValues(alpha: i < active ? 0.5 : 0.32),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 7 * scale),
            Row(
              children: [
                for (var i = 0; i < steps.length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: i == steps.length - 1 ? 0 : 8 * scale,
                      ),
                      child: _segment(i, active),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _segment(int i, int active) {
    final done = i < active;
    return SizedBox(
      height: 3 * scale,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ink.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(2),
        ),
        child: done
            ? _fill(1)
            : i == active
                ? AnimatedBuilder(
                    animation: crawl,
                    builder: (_, __) => _fill(0.22 + 0.6 * crawl.value),
                  )
                : const SizedBox.shrink(),
      ),
    );
  }

  Widget _fill(double factor) => Align(
    alignment: Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: factor.clamp(0.0, 1.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [accent, railFar]),
          borderRadius: BorderRadius.circular(2),
          boxShadow: [
            BoxShadow(color: accent.withValues(alpha: 0.55), blurRadius: 8),
          ],
        ),
      ),
    ),
  );
}

/// The one live sentence under Marquee's rail — the full stage label plus its
/// running count ("Searching sources · 148 found").
class _MarqueeStatus extends StatelessWidget {
  final ValueNotifier<_PlState> state;
  final List<PlayLoadStage> steps;
  final Color accent2;
  final Color ink;
  final double scale;

  const _MarqueeStatus({
    required this.state,
    required this.steps,
    required this.accent2,
    required this.ink,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_PlState>(
      valueListenable: state,
      builder: (context, st, _) {
        var active = steps.indexOf(st.stage);
        if (active < 0) active = 0;
        final stage = steps[active];
        // Counts are sticky, so the cache count keeps reading after its stage
        // ends — show the one that belongs to where we are now.
        final count = switch (stage) {
          PlayLoadStage.searching when st.sourceCount != null =>
            '${st.sourceCount} found',
          PlayLoadStage.cacheCheck when st.cachedCount != null =>
            '${st.cachedCount} ready',
          _ => null,
        };
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                _StepsList.labelFor(stage),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5 * scale,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
            if (count != null) ...[
              SizedBox(width: 9 * scale),
              Text(
                count,
                style: TextStyle(
                  fontSize: 11.5 * scale,
                  fontWeight: FontWeight.w600,
                  color: accent2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The staged checklist. Rebuilds only on stage change (ValueListenable).
class _StepsList extends StatelessWidget {
  final ValueNotifier<_PlState> state;
  final List<PlayLoadStage> steps;
  final double scale;

  /// Threaded down from [_PlContent] rather than read off `AppThemeScope`:
  /// the overlay's route skips ambient inheritance, so its launcher owns the
  /// palette. [inkOnFill] is the check glyph sitting ON the accent dot — a
  /// contrast-scored token, never page ink.
  final Color accent;
  final Color ink;
  final Color inkOnFill;

  const _StepsList({
    required this.state,
    required this.steps,
    required this.scale,
    required this.accent,
    required this.ink,
    required this.inkOnFill,
  });

  /// The one source of stage copy — Marquee's status line reads it too, so the
  /// two looks can never drift apart on wording.
  static String labelFor(PlayLoadStage s) {
    switch (s) {
      case PlayLoadStage.searching:
        return 'Searching sources';
      case PlayLoadStage.cacheCheck:
        return "Checking what's cached";
      case PlayLoadStage.preparing:
        return 'Preparing your stream';
      case PlayLoadStage.starting:
        return 'Starting playback';
    }
  }

  String? _count(PlayLoadStage s, _PlState st) {
    if (s == PlayLoadStage.searching && st.sourceCount != null) {
      return '${st.sourceCount} found';
    }
    if (s == PlayLoadStage.cacheCheck && st.cachedCount != null) {
      return '${st.cachedCount} ready';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_PlState>(
      valueListenable: state,
      builder: (context, st, _) {
        var active = steps.indexOf(st.stage);
        if (active < 0) active = 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++)
              _row(steps[i], i, active, st, i == steps.length - 1),
          ],
        );
      },
    );
  }

  Widget _row(PlayLoadStage s, int i, int active, _PlState st, bool last) {
    final done = i < active;
    final isActive = i == active;
    final labelColor = done
        ? ink.withValues(alpha: 0.85)
        : isActive
            ? ink
            : ink.withValues(alpha: 0.5);
    final count = _count(s, st);
    final iconSize = 22.0 * scale;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.5 * scale),
      child: Row(
        children: [
          SizedBox(
            width: iconSize,
            child: Column(
              children: [
                _icon(done, isActive, iconSize, i),
                if (!last)
                  Container(
                    margin: EdgeInsets.only(top: 3 * scale),
                    width: 2,
                    height: 8 * scale,
                    decoration: BoxDecoration(
                      color: done
                          ? accent.withValues(alpha: 0.6)
                          : ink.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 8 * scale),
              child: Text(
                labelFor(s),
                style: TextStyle(
                  color: labelColor,
                  fontSize: 14.5 * scale,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
          if (count != null)
            Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 8 * scale),
              child: Text(
                count,
                style: TextStyle(
                  color: ink.withValues(alpha: 0.5),
                  fontSize: 11.5 * scale,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _icon(bool done, bool active, double size, int i) {
    if (done) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        child: Icon(Icons.check_rounded, size: size * 0.62, color: inkOnFill),
      );
    }
    if (active) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accent, width: 2),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.16), blurRadius: 0, spreadRadius: 4)],
        ),
        child: SizedBox(
          width: size * 0.5,
          height: size * 0.5,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(accent),
          ),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ink.withValues(alpha: 0.18), width: 2),
      ),
      child: Text(
        '${i + 1}',
        style: TextStyle(
          color: ink.withValues(alpha: 0.42),
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Quiet one-liner under the checklist for quick-play's filter narration.
/// Hidden (zero-size) while the note is null, so plays without filters look
/// exactly as before.
class _NoteLine extends StatelessWidget {
  final ValueNotifier<_PlState> state;
  final double scale;

  /// Threaded down from [_PlContent] — see [_StepsList].
  final Color accent2;
  final Color ink;

  const _NoteLine({
    required this.state,
    required this.scale,
    required this.accent2,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_PlState>(
      valueListenable: state,
      builder: (context, st, _) {
        final note = st.note;
        if (note == null || note.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(top: 8 * scale),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.filter_alt_rounded,
                size: 13 * scale,
                color: accent2.withValues(alpha: 0.85),
              ),
              SizedBox(width: 6 * scale),
              Flexible(
                child: Text(
                  note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink.withValues(alpha: 0.62),
                    fontSize: 11.5 * scale,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Cancel affordance. On TV it's D-pad focusable with a bright focus ring and
/// autofocuses so the remote always has a target.
class _CancelButton extends StatefulWidget {
  final VoidCallback onCancel;
  final bool isTv;
  final double scale;

  /// Threaded down from [_PlContent] — see [_StepsList].
  final Color accent;
  final Color ink;

  const _CancelButton({
    required this.onCancel,
    required this.isTv,
    required this.scale,
    required this.accent,
    required this.ink,
  });

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton> {
  final _node = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(() {
      if (mounted) setState(() => _focused = _node.hasFocus);
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final ink = widget.ink;
    final tvFocused = widget.isTv && _focused;
    final s = widget.scale;
    return Focus(
      focusNode: _node,
      autofocus: widget.isTv,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onCancel,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.symmetric(horizontal: 18 * s, vertical: 8 * s),
          decoration: BoxDecoration(
            color: tvFocused ? ink : ink.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: tvFocused ? ink : ink.withValues(alpha: 0.22),
            ),
            boxShadow: tvFocused
                ? [
                    BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 0, spreadRadius: 3),
                    BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 8)),
                  ]
                : null,
          ),
          child: Text(
            'Cancel',
            style: TextStyle(
              // Ink on the focused pill, whose fill is [ink] — always a light
              // colour, since `onGlass` is scored against black on every
              // theme. No token holds this exact near-black, and `inkOn(ink)`
              // would resolve to the page ground (a different value), so it
              // stays pinned rather than shifting today's pixel.
              color: tvFocused
                  ? const Color(0xFF17131F)
                  : ink.withValues(alpha: 0.82),
              fontSize: 12.5 * s,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

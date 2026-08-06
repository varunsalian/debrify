import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/platform_util.dart';

/// The real resolve stages a play flows through. The overlay shows the subset
/// relevant to the play (a bound-source play skips searching/cache; a provider
/// with no cache check skips [cacheCheck]).
enum PlayLoadStage { searching, cacheCheck, preparing, starting }

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
    final tv = PlatformUtil.isAndroidTvCached;

    // Pushed as an explicit route (not showGeneralDialog) so [dismiss] can
    // target THIS route: the play flow now keeps the loader up while the
    // player route/activity launches on top of it, and a blind pop() at that
    // point could pop the wrong screen.
    final route = RawDialogRoute<void>(
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => PopScope(
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
          onCancel: onCancel == null
              ? null
              : () {
                  handle.dismiss();
                  onCancel();
                },
        ),
      ),
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
  });

  @override
  State<_PlContent> createState() => _PlContentState();
}

class _PlContentState extends State<_PlContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _kb;
  bool _reduceMotion = false;

  static const _accent = PipelineLoadingOverlay.accent;

  @override
  void initState() {
    super.initState();
    _kb = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    // Only drive the Ken Burns controller when there's a backdrop to animate
    // (TV renders the static gradient backdrop — see _backdrop).
    if (!_reduceMotion && !widget.isTv && _hasPoster && !_kb.isAnimating) {
      _kb.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _kb.dispose();
    super.dispose();
  }

  bool get _hasPoster => widget.posterUrl != null && widget.posterUrl!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final landscape = widget.isTv || size.width >= 880;
    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _backdrop(),
          _scrim(landscape),
          _TopRail(state: widget.state, steps: widget.steps),
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
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.3),
            radius: 1.1,
            colors: [Color(0xFF201636), Color(0xFF08060D)],
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

  // ── Poster card ─────────────────────────────────────────────────────────
  Widget _posterCard(double width) {
    return Container(
      width: width,
      height: width * 1.5,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: _accent.withValues(alpha: 0.32), blurRadius: 34, spreadRadius: 1),
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

  Widget _posterFallback() => ColoredBox(
        color: Colors.white.withValues(alpha: 0.06),
        child: const Center(
          child: Icon(Icons.movie_rounded, color: Colors.white24, size: 34),
        ),
      );

  // ── Layouts ─────────────────────────────────────────────────────────────
  Widget _portrait() {
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
              style: TextStyle(color: Colors.white.withValues(alpha: 0.66), fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 26),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StepsList(state: widget.state, steps: widget.steps, scale: 1),
                _NoteLine(state: widget.state, scale: 1),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _providerChip(),
                if (widget.onCancel != null) ...[
                  const SizedBox(height: 26),
                  _CancelButton(onCancel: widget.onCancel!, isTv: false, scale: 1),
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
              color: const Color(0xFFB9A6FF),
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
        _StepsList(state: widget.state, steps: widget.steps, scale: tv ? 1.15 * scale : 1),
        _NoteLine(state: widget.state, scale: tv ? 1.15 * scale : 1),
        SizedBox(height: (tv ? 22 : 16) * scale),
        Row(
          children: [
            _providerChip(),
            const Spacer(),
            if (widget.onCancel != null)
              _CancelButton(onCancel: widget.onCancel!, isTv: tv, scale: scale),
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
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xD1221A34), Color(0xCC0F0B19)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
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
  const _TopRail({required this.state, required this.steps});

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
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [PipelineLoadingOverlay.accent, Color(0xFFC4B2FF)],
                    ),
                    boxShadow: [
                      BoxShadow(color: PipelineLoadingOverlay.accent, blurRadius: 10),
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

/// The staged checklist. Rebuilds only on stage change (ValueListenable).
class _StepsList extends StatelessWidget {
  final ValueNotifier<_PlState> state;
  final List<PlayLoadStage> steps;
  final double scale;
  const _StepsList({required this.state, required this.steps, required this.scale});

  static const _accent = PipelineLoadingOverlay.accent;

  String _label(PlayLoadStage s) {
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
        ? Colors.white.withValues(alpha: 0.85)
        : isActive
            ? Colors.white
            : Colors.white.withValues(alpha: 0.5);
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
                      color: done ? _accent.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.15),
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
                _label(s),
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
                  color: Colors.white.withValues(alpha: 0.5),
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
        decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
        child: Icon(Icons.check_rounded, size: size * 0.62, color: const Color(0xFF0A0712)),
      );
    }
    if (active) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _accent, width: 2),
          boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.16), blurRadius: 0, spreadRadius: 4)],
        ),
        child: SizedBox(
          width: size * 0.5,
          height: size * 0.5,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(_accent),
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 2),
      ),
      child: Text(
        '${i + 1}',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.42),
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
  const _NoteLine({required this.state, required this.scale});

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
                color: const Color(0xFFB9A6FF).withValues(alpha: 0.85),
              ),
              SizedBox(width: 6 * scale),
              Flexible(
                child: Text(
                  note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
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
  const _CancelButton({required this.onCancel, required this.isTv, required this.scale});

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
            color: tvFocused ? Colors.white : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: tvFocused ? Colors.white : Colors.white.withValues(alpha: 0.22),
            ),
            boxShadow: tvFocused
                ? [
                    BoxShadow(color: PipelineLoadingOverlay.accent.withValues(alpha: 0.6), blurRadius: 0, spreadRadius: 3),
                    BoxShadow(color: PipelineLoadingOverlay.accent.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 8)),
                  ]
                : null,
          ),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: tvFocused ? const Color(0xFF17131F) : Colors.white.withValues(alpha: 0.82),
              fontSize: 12.5 * s,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

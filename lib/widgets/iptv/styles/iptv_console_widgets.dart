import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../../../services/iptv_epg_service.dart';
import 'iptv_style.dart';

/// Master Control's top status strip: source · counts · REC · SCHED · status
/// text · clock. Display-only — no focus nodes, pure state handed in by the
/// page. Owns exactly one 30 s timer for the clock; the same tick invokes
/// [onTick] so the page can reconcile Android recording state (its map only
/// refreshes on selected events otherwise and the count could sit stale).
class IptvConsoleStatusBar extends StatefulWidget {
  final IptvStyleTokens tokens;
  final String sourceName;
  final int channelCount;
  final int recCount;
  final int schedCount;

  /// The catalog chip's current message, or null when it is hidden. The chip
  /// system speaks for guide/maintenance/refresh alike, so the label is the
  /// neutral STATUS, not UPDATED.
  final String? statusText;

  /// Fired on the 30 s clock tick (never on build).
  final VoidCallback? onTick;

  const IptvConsoleStatusBar({
    super.key,
    required this.tokens,
    required this.sourceName,
    required this.channelCount,
    required this.recCount,
    required this.schedCount,
    this.statusText,
    this.onTick,
  });

  @override
  State<IptvConsoleStatusBar> createState() => _IptvConsoleStatusBarState();
}

class _IptvConsoleStatusBarState extends State<IptvConsoleStatusBar> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {});
      widget.onTick?.call();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String _fmtClock(BuildContext context) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(DateTime.now()),
        alwaysUse24HourFormat: true,
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final mono = t.monoFamily.isEmpty ? null : t.monoFamily;
    TextStyle label(Color color, {double size = 10}) => TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.6,
      fontFamily: mono,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              widget.sourceName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: label(t.fg, size: 11),
            ),
          ),
          const SizedBox(width: 10),
          Text('${_fmtCount(widget.channelCount)} CH', style: label(t.fgFaint)),
          const SizedBox(width: 22),
          Text('LIVE TV', style: label(t.fgDim)),
          if (widget.recCount > 0) ...[
            const SizedBox(width: 22),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.rec,
                boxShadow: [
                  BoxShadow(color: t.rec.withValues(alpha: 0.6), blurRadius: 8),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Text('REC ${widget.recCount}', style: label(t.rec)),
          ],
          const Spacer(),
          if (widget.schedCount > 0) ...[
            Text('SCHED ${widget.schedCount}', style: label(t.fgDim)),
            const SizedBox(width: 22),
          ],
          if (widget.statusText != null && widget.statusText!.isNotEmpty) ...[
            Flexible(
              child: Text(
                'STATUS · ${widget.statusText!.toUpperCase()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: label(t.fgDim),
              ),
            ),
            const SizedBox(width: 22),
          ],
          Text(_fmtClock(context), style: label(t.fg, size: 12)),
        ],
      ),
    );
  }

  String _fmtCount(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// Master Control's signature: the focused channel's −1 h → +5 h strip — hour
/// ruler, hairline programme cells (NOW amber-tinted, REPLAY tagged from
/// `hasArchive`), and an amber playhead pinned to the wall clock.
///
/// Display-only, no focus nodes. Data flow per the plan: `schedule(url)`
/// behind a 450 ms focus-settle debounce — it coalesces with the stage's own
/// schedule fetch through the service's in-flight map and LRU cache. Cells
/// live under their own RepaintBoundary and rebuild on channel/EPG change
/// AND at programme boundaries (one-shot timer, the stage's pattern); only
/// the playhead overlay ticks every 30 s. All timers cancel while hidden or
/// [suspended]. No per-programme REC tags in v1 (the page holds no
/// normalized schedule snapshot to tag from — see the plan).
class IptvConsoleTimeline extends StatefulWidget {
  final ValueListenable<IptvChannel?> channel;
  final IptvStyleTokens tokens;

  /// True while the full-day schedule pane covers the guide column.
  final bool suspended;

  const IptvConsoleTimeline({
    super.key,
    required this.channel,
    required this.tokens,
    this.suspended = false,
  });

  /// Total window width in hours (1 back, 5 forward).
  static const int windowHours = 6;

  @override
  State<IptvConsoleTimeline> createState() => _IptvConsoleTimelineState();
}

class _IptvConsoleTimelineState extends State<IptvConsoleTimeline> {
  List<EpgProgramme>? _schedule;
  String? _forUrl;
  Timer? _debounce;
  Timer? _boundary;
  Timer? _reanchor;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    widget.channel.addListener(_onChannelChanged);
    IptvEpgService.instance.contextVersion.addListener(_onEpgContextChanged);
    if (!widget.suspended) _sync();
  }

  @override
  void didUpdateWidget(IptvConsoleTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel != widget.channel) {
      oldWidget.channel.removeListener(_onChannelChanged);
      widget.channel.addListener(_onChannelChanged);
      // The new listenable's current value never fires a change — sync now.
      if (!widget.suspended) _sync();
    }
    if (oldWidget.suspended != widget.suspended) {
      if (widget.suspended) {
        _stopTimers();
      } else {
        _sync();
      }
    }
  }

  @override
  void dispose() {
    widget.channel.removeListener(_onChannelChanged);
    IptvEpgService.instance.contextVersion.removeListener(_onEpgContextChanged);
    _stopTimers();
    super.dispose();
  }

  void _stopTimers() {
    _debounce?.cancel();
    _debounce = null;
    _boundary?.cancel();
    _boundary = null;
    _reanchor?.cancel();
    _reanchor = null;
  }

  void _onChannelChanged() {
    if (mounted && !widget.suspended) _sync();
  }

  void _onEpgContextChanged() {
    if (mounted && !widget.suspended) _sync();
  }

  void _sync() {
    _debounce?.cancel();
    _boundary?.cancel();
    final ch = widget.channel.value;
    final urlChanged = _forUrl != ch?.url;
    _forUrl = ch?.url;
    final ticket = ++_ticket;
    if (ch == null || !IptvEpgService.isEpgCapable(ch)) {
      if (_schedule != null) setState(() => _schedule = null);
      return;
    }
    // A new subject must not keep painting the previous channel's cells for
    // the debounce+fetch window — clear immediately (zero-height, snap).
    if (urlChanged && _schedule != null) setState(() => _schedule = null);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final url = _forUrl;
      if (url == null || !mounted) return;
      try {
        final programmes = await IptvEpgService.instance.schedule(url);
        if (!mounted || ticket != _ticket || widget.suspended) return;
        setState(() => _schedule = programmes);
        _armBoundary();
        // Between boundaries the -1h..+5h framing would silently go stale
        // (the playhead stays truthful; the window just stops rolling) —
        // a slow re-anchor keeps the geometry honest without per-minute
        // rebuild cost.
        _reanchor ??= Timer.periodic(const Duration(minutes: 5), (_) {
          if (mounted && !widget.suspended) setState(() {});
        });
      } catch (_) {
        // A failed guide read just leaves the strip empty (zero height).
      }
    });
  }

  /// One-shot repaint at the next programme start/stop inside the window —
  /// the moment cell classification (past/NOW/upcoming) actually changes.
  void _armBoundary() {
    _boundary?.cancel();
    final schedule = _schedule;
    if (schedule == null || schedule.isEmpty || !mounted) return;
    final now = DateTime.now();
    DateTime? next;
    for (final p in schedule) {
      for (final t in [p.start, p.stop]) {
        if (t.isAfter(now) && (next == null || t.isBefore(next))) next = t;
      }
    }
    if (next == null) return;
    // A boundary past the window's forward edge (+5h) can't change what's
    // on screen — don't hold a wakeup for it.
    if (next.difference(now) > const Duration(hours: 5)) {
      return;
    }
    _boundary = Timer(next.difference(now) + const Duration(seconds: 1), () {
      if (!mounted || widget.suspended) return;
      setState(() {});
      _armBoundary();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final schedule = _schedule;
    final ch = widget.channel.value;
    if (ch == null || schedule == null || schedule.isEmpty) {
      // No guide: the strip takes no space at all — never a dead band.
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    // Anchored to the wall clock, not a floored hour — the window is always
    // exactly -1h..+5h and the playhead sits where the maths says it does.
    final windowStart = now.subtract(const Duration(hours: 1));
    final windowEnd = windowStart.add(
      const Duration(hours: IptvConsoleTimeline.windowHours),
    );
    final windowMs = windowEnd.difference(windowStart).inMilliseconds;
    // Whole-hour ruler marks inside the window, positioned fractionally.
    var rulerHour = DateTime(
      windowStart.year,
      windowStart.month,
      windowStart.day,
      windowStart.hour,
    );
    if (rulerHour.isBefore(windowStart)) {
      rulerHour = rulerHour.add(const Duration(hours: 1));
    }
    final rulerMarks = <DateTime>[];
    for (
      var m = rulerHour;
      !m.isAfter(windowEnd);
      m = m.add(const Duration(hours: 1))
    ) {
      rulerMarks.add(m);
    }

    final visible = [
      for (final p in schedule)
        if (p.stop.isAfter(windowStart) && p.start.isBefore(windowEnd)) p,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();

    double frac(DateTime time) =>
        (time.difference(windowStart).inMilliseconds / windowMs).clamp(
          0.0,
          1.0,
        );

    final mono = t.monoFamily.isEmpty ? null : t.monoFamily;
    return Container(
      height: 96,
      padding: const EdgeInsets.fromLTRB(14, 10, 24, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return Stack(
            children: [
              // Hour ruler + programme cells: static between boundary fires.
              RepaintBoundary(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 14,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final m in rulerMarks)
                            Positioned(
                              left: (w * frac(m)).clamp(0.0, w - 30),
                              top: 0,
                              child: Text(
                                '${m.hour.toString().padLeft(2, '0')}:00',
                                style: TextStyle(
                                  color: t.fgFaint,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: mono,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Stack(
                        children: [
                          for (final p in visible)
                            Positioned(
                              left: w * frac(p.start),
                              width: (w * (frac(p.stop) - frac(p.start))).clamp(
                                8.0,
                                w,
                              ),
                              top: 0,
                              bottom: 0,
                              child: _TimelineCell(
                                programme: p,
                                tokens: t,
                                isNow: p.airsAt(now),
                                isPast: !p.stop.isAfter(now),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // The playhead overlay owns its own 30 s tick — cells above
              // never repaint for it.
              _TimelinePlayhead(
                tokens: t,
                windowStart: windowStart,
                windowMs: windowMs,
                width: w,
                suspended: widget.suspended,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TimelineCell extends StatelessWidget {
  final EpgProgramme programme;
  final IptvStyleTokens tokens;
  final bool isNow;
  final bool isPast;

  const _TimelineCell({
    required this.programme,
    required this.tokens,
    required this.isNow,
    required this.isPast,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final mono = t.monoFamily.isEmpty ? null : t.monoFamily;
    // Past cells fade via pre-multiplied text colors, NOT an Opacity widget —
    // Opacity is a saveLayer, and the house TV rule bans those near the
    // underlay (and on anything that can appear dozens of times per frame).
    Color fade(Color c) => isPast ? c.withValues(alpha: c.a * 0.45) : c;
    return Container(
      margin: const EdgeInsets.only(right: 3, top: 2, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isNow ? t.accent.withValues(alpha: 0.45) : t.hairline2,
        ),
        color: isNow ? t.accent.withValues(alpha: 0.06) : Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${programme.start.hour.toString().padLeft(2, '0')}:'
                  '${programme.start.minute.toString().padLeft(2, '0')}',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: fade(t.fgFaint),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w500,
                    fontFamily: mono,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (programme.hasArchive && isPast)
                Flexible(
                  child: Text(
                    'REPLAY',
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: TextStyle(
                      color: fade(t.fgFaint),
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      fontFamily: mono,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            programme.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fade(isNow ? t.fg : t.fgMid),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              fontFamily: t.nameFamily.isEmpty ? null : t.nameFamily,
            ),
          ),
        ],
      ),
    );
  }
}

/// The amber wall-clock line. Its own widget so its 30 s tick repaints ONLY
/// this subtree, never the programme cells behind it.
class _TimelinePlayhead extends StatefulWidget {
  final IptvStyleTokens tokens;
  final DateTime windowStart;
  final int windowMs;
  final double width;
  final bool suspended;

  const _TimelinePlayhead({
    required this.tokens,
    required this.windowStart,
    required this.windowMs,
    required this.width,
    required this.suspended,
  });

  @override
  State<_TimelinePlayhead> createState() => _TimelinePlayheadState();
}

class _TimelinePlayheadState extends State<_TimelinePlayhead> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (!widget.suspended) _start();
  }

  @override
  void didUpdateWidget(_TimelinePlayhead oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.suspended != widget.suspended) {
      widget.suspended ? _stop() : _start();
    }
  }

  void _start() {
    _tick ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stop() {
    _tick?.cancel();
    _tick = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final now = DateTime.now();
    final frac =
        (now.difference(widget.windowStart).inMilliseconds / widget.windowMs)
            .clamp(0.0, 1.0);
    final mono = t.monoFamily.isEmpty ? null : t.monoFamily;
    return Positioned(
      left: (widget.width * frac - 0.75).clamp(0.0, widget.width - 1.5),
      top: 10,
      bottom: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}',
            style: TextStyle(
              color: t.accent,
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              fontFamily: mono,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Expanded(
            child: Container(
              width: 1.5,
              decoration: BoxDecoration(
                color: t.accent,
                boxShadow: [
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.5),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

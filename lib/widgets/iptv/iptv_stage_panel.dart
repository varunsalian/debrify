import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../../services/iptv_epg_service.dart';
import '../../utils/tv_keys.dart';
import '../browse/brand_accent.dart';

/// The Command Center stage's lower half: identity + now/next, an action row
/// (Watch · Record · ♥ · Guide), and a compact "Today on <channel>" schedule
/// whose FUTURE rows carry the inline REC affordance — "see what's on →
/// schedule it" without leaving the page.
///
/// Perf contract (TV): the schedule fetch is debounced 450ms behind focus
/// settling and served by IptvEpgService's 30-minute cache + in-flight
/// dedupe, so zapping focus down the list costs nothing; a stale ticket
/// guard drops answers for channels no longer focused. No animations — every
/// state change snaps (TV GPU rule) — and the whole panel sits behind one
/// RepaintBoundary owned by the caller.
class IptvStagePanel extends StatefulWidget {
  final IptvChannel channel;
  final bool isTelevision;
  final bool isFavorited;

  /// Recording affordances are platform-gated by the CALLER (engine on
  /// Android 10+, desktop capture elsewhere); false hides Record + REC rows.
  final bool canRecord;

  /// True when THIS channel is being captured right now (desktop). The
  /// Record button becomes Stop — without it a page-started desktop capture
  /// has no stop surface at all (no notifications there).
  final bool isRecordingThis;

  /// Bumped when guide context changes (an XMLTV guide finishing its async
  /// load). Re-arms the schedule fetch for a channel that was "no EPG" a
  /// moment ago — the url alone can't signal that.
  final int epgContextVersion;

  final VoidCallback onWatch;
  final VoidCallback? onRecordNow;
  final VoidCallback? onToggleFavorite;

  /// Null hides the Guide action — a channel with no EPG capability would
  /// only ever open a pane that says "No guide data".
  final VoidCallback? onOpenFullSchedule;

  /// Schedule a future programme; resolves to a user-facing result message.
  final Future<String?> Function(IptvChannel channel, EpgProgramme programme)?
      onScheduleProgramme;

  /// Play an archived programme (Xtream catchup) — the existing page path.
  final void Function(IptvChannel channel, EpgProgramme programme)?
      onPlayProgramme;

  /// LEFT anywhere in the panel returns focus to the guide — to the SAME row
  /// the stage was opened from (the caller knows it), so the preview never
  /// retunes on the way back. Geometric traversal would pick whichever row is
  /// nearest and reload the stream for it.
  final VoidCallback? onExitLeft;

  const IptvStagePanel({
    super.key,
    required this.channel,
    required this.isTelevision,
    required this.isFavorited,
    required this.canRecord,
    required this.onWatch,
    this.isRecordingThis = false,
    this.epgContextVersion = 0,
    this.onOpenFullSchedule,
    this.onRecordNow,
    this.onToggleFavorite,
    this.onScheduleProgramme,
    this.onPlayProgramme,
    this.onExitLeft,
  });

  @override
  State<IptvStagePanel> createState() => _IptvStagePanelState();
}

class _IptvStagePanelState extends State<IptvStagePanel> {
  List<EpgProgramme>? _schedule;
  bool _loading = false;
  Timer? _debounce;
  int _ticket = 0;

  /// Fires at the next programme boundary so NOW/REC tags (and the
  /// activation semantics behind them) track the wall clock while focus
  /// parks on one channel. One-shot, re-armed per fire — no periodic tick.
  Timer? _boundaryTimer;

  @override
  void initState() {
    super.initState();
    _armFetch();
  }

  @override
  void didUpdateWidget(covariant IptvStagePanel old) {
    super.didUpdateWidget(old);
    if (old.channel.url != widget.channel.url) {
      _schedule = null;
      _boundaryTimer?.cancel();
      _armFetch();
    } else if (old.epgContextVersion != widget.epgContextVersion) {
      // Guide context changed under the same channel (an XMLTV load landed):
      // a channel that probed "no EPG" seconds ago may have a schedule now.
      // Keep the old rows visible while the refetch runs — no flash.
      _armFetch();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _boundaryTimer?.cancel();
    super.dispose();
  }

  /// Arm a one-shot repaint for the next start/stop after now. A schedule
  /// has at most a couple of boundaries per hour, so this costs nothing —
  /// and without it a parked panel keeps yesterday's NOW forever.
  void _armBoundaryTimer() {
    _boundaryTimer?.cancel();
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
    _boundaryTimer = Timer(next.difference(now) + const Duration(seconds: 1),
        () {
      if (!mounted) return;
      setState(() {});
      _armBoundaryTimer();
    });
  }

  /// Focus-settle debounce: rapid DPAD travel re-arms the timer, so only the
  /// channel the user actually stops on pays for a fetch (and even that is
  /// usually a cache hit).
  void _armFetch() {
    _debounce?.cancel();
    final ticket = ++_ticket;
    if (!IptvEpgService.isEpgCapable(widget.channel)) {
      _loading = false;
      return;
    }
    _loading = true;
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final channel = widget.channel;
      final programmes = await IptvEpgService.instance.schedule(channel.url);
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _schedule = programmes;
        _loading = false;
      });
      _armBoundaryTimer();
    });
  }

  /// The visible window: one just-finished programme for catchup context,
  /// then NOW, then what fits. The full day lives behind the Guide action.
  List<EpgProgramme> _visibleWindow(List<EpgProgramme> all) {
    if (all.isEmpty) return const [];
    final now = DateTime.now();
    var nowIndex = all.indexWhere((p) => p.airsAt(now));
    if (nowIndex < 0) {
      nowIndex = all.indexWhere((p) => p.start.isAfter(now));
      if (nowIndex < 0) return all.length <= 6 ? all : all.sublist(all.length - 6);
    }
    final start = (nowIndex - 1).clamp(0, all.length);
    return all.sublist(start, (start + 6).clamp(0, all.length));
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final now = DateTime.now();
    final schedule = _schedule;
    final window = schedule == null ? const <EpgProgramme>[] : _visibleWindow(schedule);

    // Which rows are focusable determines the containment edges: the LAST
    // actionable row swallows DOWN; with none, the button strip does.
    var lastActionableIndex = -1;
    for (var i = 0; i < window.length; i++) {
      final p = window[i];
      final actionable = p.airsAt(now) ||
          (widget.onPlayProgramme != null &&
              !p.stop.isAfter(now) &&
              IptvEpgService.isCatchupAvailable(channel, p)) ||
          (widget.canRecord &&
              widget.onScheduleProgramme != null &&
              p.start.isAfter(now));
      if (actionable) lastActionableIndex = i;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: _StageActions(
            isTelevision: widget.isTelevision,
            isFavorited: widget.isFavorited,
            canRecord: widget.canRecord && widget.onRecordNow != null,
            isRecordingThis: widget.isRecordingThis,
            isSeries: channel.contentType == 'series',
            onWatch: widget.onWatch,
            onRecordNow: widget.onRecordNow,
            onToggleFavorite: widget.onToggleFavorite,
            onOpenFullSchedule: widget.onOpenFullSchedule,
            // Containment: nothing focusable sits above the strip, and with
            // no schedule rows below, nothing sits under it either — vertical
            // DPAD must never leak to the panes on the left.
            swallowDown: lastActionableIndex < 0,
            onExitLeft: widget.onExitLeft,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: !IptvEpgService.isEpgCapable(channel)
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'TODAY',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _loading && window.isEmpty
                            ? const SizedBox.shrink()
                            : window.isEmpty
                            ? Text(
                                'No guide data',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.30),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : ListView(
                                // The window is ≤6 fixed-height rows: cheap.
                                physics: const NeverScrollableScrollPhysics(),
                                padding: EdgeInsets.zero,
                                children: [
                                  for (var i = 0; i < window.length; i++)
                                    _StageScheduleRow(
                                      programme: window[i],
                                      isNow: window[i].airsAt(now),
                                      isPast: !window[i].stop.isAfter(now),
                                      isTelevision: widget.isTelevision,
                                      replayable: widget.onPlayProgramme !=
                                              null &&
                                          IptvEpgService.isCatchupAvailable(
                                            channel,
                                            window[i],
                                          ),
                                      recordable: widget.canRecord &&
                                          widget.onScheduleProgramme != null &&
                                          window[i].start.isAfter(now),
                                      isLastFocusable:
                                          i == lastActionableIndex,
                                      onExitLeft: widget.onExitLeft,
                                      onActivate: () =>
                                          _onRowActivate(window[i], now),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  void _onRowActivate(EpgProgramme p, DateTime now) {
    final channel = widget.channel;
    if (p.start.isAfter(now)) {
      final schedule = widget.onScheduleProgramme;
      if (schedule == null) return;
      unawaited(() async {
        final message = await schedule(channel, p);
        if (message == null || !mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }());
      return;
    }
    if (!p.stop.isAfter(now) &&
        IptvEpgService.isCatchupAvailable(channel, p)) {
      widget.onPlayProgramme?.call(channel, p);
      return;
    }
    // The NOW row: watching it is what the big button is for.
    widget.onWatch();
  }
}

// ── Actions row ─────────────────────────────────────────────────────────────

class _StageActions extends StatelessWidget {
  final bool isTelevision;
  final bool isFavorited;
  final bool canRecord;
  final bool isRecordingThis;
  final bool isSeries;
  final VoidCallback onWatch;
  final VoidCallback? onRecordNow;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onOpenFullSchedule;
  final bool swallowDown;
  final VoidCallback? onExitLeft;

  const _StageActions({
    required this.isTelevision,
    required this.isFavorited,
    required this.canRecord,
    required this.isRecordingThis,
    required this.isSeries,
    required this.onWatch,
    required this.onRecordNow,
    required this.onToggleFavorite,
    required this.onOpenFullSchedule,
    required this.swallowDown,
    required this.onExitLeft,
  });

  @override
  Widget build(BuildContext context) {
    // Content-sized buttons at one shared height, no stretching: an Expanded
    // Watch next to icon squares read lopsided.
    return Row(
      children: [
        _StageButton(
          label: isSeries ? 'Open' : 'Watch',
          icon: isSeries
              ? Icons.video_library_rounded
              : Icons.play_arrow_rounded,
          primary: true,
          onPressed: onWatch,
          swallowDown: swallowDown,
          onLeft: onExitLeft,
        ),
        if (canRecord && !isSeries) ...[
          const SizedBox(width: 7),
          _StageButton(
            label: isRecordingThis ? 'Stop' : 'Record',
            icon: isRecordingThis
                ? Icons.stop_rounded
                : Icons.fiber_manual_record_rounded,
            iconColor: const Color(0xFFF43F5E),
            emphasized: isRecordingThis,
            onPressed: onRecordNow!,
            swallowDown: swallowDown,
            onLeft: onExitLeft,
          ),
        ],
        if (onToggleFavorite != null) ...[
          const SizedBox(width: 7),
          _StageButton(
            icon: isFavorited ? Icons.star_rounded : Icons.star_border_rounded,
            iconColor:
                isFavorited ? const Color(0xFFF5C042) : Colors.white70,
            onPressed: onToggleFavorite!,
            swallowDown: swallowDown,
            onLeft: onExitLeft,
          ),
        ],
        if (onOpenFullSchedule != null) ...[
          const SizedBox(width: 7),
          _StageButton(
            icon: Icons.calendar_view_day_rounded,
            onPressed: onOpenFullSchedule!,
            swallowDown: swallowDown,
            onLeft: onExitLeft,
          ),
        ],
      ],
    );
  }
}

/// One focus-visible action. Custom rather than FilledButton so the TV focus
/// ring matches the house gold outline instead of Material's subtle overlay.
class _StageButton extends StatefulWidget {
  final String? label;
  final IconData icon;
  final Color? iconColor;
  final bool primary;

  /// Red-tinted resting state (the Stop-while-recording button) so an active
  /// capture is visible even when the button isn't focused.
  final bool emphasized;
  final VoidCallback onPressed;

  /// Containment: the strip is the panel's top edge (UP always swallowed);
  /// DOWN is swallowed too when no schedule rows sit below.
  final bool swallowDown;

  /// LEFT exits to the guide via the caller (never geometric traversal).
  final VoidCallback? onLeft;

  const _StageButton({
    this.label,
    required this.icon,
    this.iconColor,
    this.primary = false,
    this.emphasized = false,
    required this.onPressed,
    this.swallowDown = false,
    this.onLeft,
  });

  @override
  State<_StageButton> createState() => _StageButtonState();
}

class _StageButtonState extends State<_StageButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFF5C042);
    final body = Container(
      height: 38,
      padding: EdgeInsets.symmetric(horizontal: widget.label == null ? 10 : 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: widget.primary
            ? const LinearGradient(
                colors: [Color(0xFF4F74FF), Color(0xFF8A5CFF)],
              )
            : null,
        color: widget.primary
            ? null
            : widget.emphasized
            ? const Color(0xFFF43F5E).withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.06),
        border: Border.all(
          color: _focused
              ? gold
              : widget.emphasized
              ? const Color(0xFFF43F5E).withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: widget.primary ? 0.0 : 0.10),
          width: _focused ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.icon,
            size: 17,
            color: widget.iconColor ?? Colors.white,
          ),
          if (widget.label != null) ...[
            const SizedBox(width: 6),
            Text(
              widget.label!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (event is KeyDownEvent) widget.onLeft?.call();
          return widget.onLeft != null
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        // The strip is the panel's top edge — UP must never leak to the
        // guide/rail on the left. Same for DOWN when nothing sits below.
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          return KeyEventResult.handled;
        }
        if (widget.swallowDown &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: body,
      ),
    );
  }
}

// ── Schedule rows ───────────────────────────────────────────────────────────

class _StageScheduleRow extends StatefulWidget {
  final EpgProgramme programme;
  final bool isNow;
  final bool isPast;
  final bool isTelevision;
  final bool replayable;
  final bool recordable;

  /// The panel's bottom focus edge — DOWN is swallowed here so vertical DPAD
  /// can't leak into the guide/rail.
  final bool isLastFocusable;
  final VoidCallback? onExitLeft;
  final VoidCallback onActivate;

  const _StageScheduleRow({
    required this.programme,
    required this.isNow,
    required this.isPast,
    required this.isTelevision,
    required this.replayable,
    required this.recordable,
    required this.isLastFocusable,
    required this.onExitLeft,
    required this.onActivate,
  });

  @override
  State<_StageScheduleRow> createState() => _StageScheduleRowState();
}

class _StageScheduleRowState extends State<_StageScheduleRow> {
  bool _focused = false;

  String _clock(BuildContext context, DateTime t) => MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(t), alwaysUse24HourFormat: true);

  @override
  Widget build(BuildContext context) {
    final p = widget.programme;
    final actionable = widget.isNow || widget.replayable || widget.recordable;
    final titleAlpha = widget.isPast
        ? (widget.replayable ? 0.7 : 0.35)
        : (widget.isNow ? 1.0 : 0.82);

    final row = Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        color: _focused
            ? const Color(0xFF1A1F35)
            : widget.isNow
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.transparent,
        border: Border.all(
          color: _focused ? const Color(0xFFF5C042) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              _clock(context, p.start),
              style: TextStyle(
                color: widget.isNow
                    ? const Color(0xFFF5C042)
                    : Colors.white.withValues(alpha: widget.isPast ? 0.3 : 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              p.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: titleAlpha),
                fontSize: 12,
                fontWeight: widget.isNow ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (widget.isNow)
            const _Tag('NOW', Color(0xFF22C55E))
          else if (widget.replayable)
            _Tag('REPLAY', Colors.white.withValues(alpha: 0.55))
          else if (widget.recordable)
            const _Tag('REC', Color(0xFFF43F5E)),
        ],
      ),
    );

    if (!widget.isTelevision) {
      if (!actionable) return row;
      return GestureDetector(
        onTap: widget.onActivate,
        behavior: HitTestBehavior.opaque,
        child: row,
      );
    }
    if (!actionable) return row;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          widget.onActivate();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (event is KeyDownEvent) widget.onExitLeft?.call();
          return widget.onExitLeft != null
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        // Bottom edge of the panel: DOWN stops here instead of leaking into
        // whatever sits lower-left in the guide.
        if (widget.isLastFocusable &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: row,
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: color.withValues(alpha: 0.14),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Compact brand mark used by rail rows when a source has no artwork —
/// shared here so rail and stage agree on the monogram look.
class IptvMonogram extends StatelessWidget {
  final String name;
  final double size;
  const IptvMonogram({super.key, required this.name, this.size = 30});

  @override
  Widget build(BuildContext context) {
    final brand = brandAccentFor(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        color: Color.alphaBlend(
          brand.withValues(alpha: 0.22),
          const Color(0xFF141828),
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

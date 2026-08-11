import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../../services/iptv_epg_service.dart';
import 'styles/iptv_style.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/tv_keys.dart';

/// Formats a time as the device's clock format ("8:00 PM" / "20:00").
String _clock(BuildContext context, DateTime t) =>
    TimeOfDay.fromDateTime(t).format(context);

String _dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  final delta = d.difference(today).inDays;
  if (delta == 0) return 'Today';
  if (delta == 1) return 'Tomorrow';
  if (delta == -1) return 'Yesterday';
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
}

// ── Rail now/next card ──────────────────────────────────────────────────────

/// The TV preview rail's programme card: what's airing on the focused channel
/// right now (title, time range, progress, description) and what's up next.
///
/// Self-contained: give it the focused channel and it handles capability
/// checks, the fetch (debounced so arrowing down the guide doesn't fire a
/// request per row), caching via [IptvEpgService], and rolling itself over
/// when the current programme ends. Renders nothing for channels without
/// guide data — the rail simply looks like it did before EPG existed.
class IptvRailEpgCard extends StatefulWidget {
  final IptvChannel? channel;

  /// Compact "now" treatment for the TV focus-stage overlay. The standard
  /// desktop rail keeps its fuller now/next presentation.
  final bool stageOverlay;

  /// Tightens spacing and limits text to one line when the lower stage section
  /// is short. Programme descriptions remain visible.
  final bool dense;

  /// Styled-look tokens: swaps the card's gold (NOW tag, progress fill) for
  /// the style's accent. Null = the shipped paint, verbatim.
  final IptvStyleTokens? tokens;

  const IptvRailEpgCard({
    super.key,
    required this.channel,
    this.stageOverlay = false,
    this.dense = false,
    this.tokens,
  });

  @override
  State<IptvRailEpgCard> createState() => _IptvRailEpgCardState();
}

class _IptvRailEpgCardState extends State<IptvRailEpgCard> {
  EpgNowNext? _data;
  bool _loading = false;
  String? _forUrl;
  Timer? _fetchDebounce;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _sync();
    // An XMLTV guide finishing its (possibly minutes-long) first download
    // changes what this card can show for the already-focused channel.
    IptvEpgService.instance.contextVersion.addListener(_onEpgContextChanged);
    // Advance the progress bar and roll past programme boundaries. The
    // service cache is the staleness oracle — it invalidates itself when the
    // NOW programme ends, when the NEXT one starts (guide gaps), and when an
    // empty answer's retry window passes — so "peek came back null" is
    // exactly "time to re-ask". (XMLTV peeks are computed fresh every call
    // and are never null, so they roll by themselves via the reconcile.)
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final ch = widget.channel;
      if (ch == null || !IptvEpgService.isEpgCapable(ch)) return;
      final cached = IptvEpgService.instance.peekNowNext(ch.url);
      if (cached == null) {
        _fetch();
      } else if (!identical(cached, _data)) {
        setState(() => _data = cached);
      } else if (cached.now != null) {
        setState(() {}); // repaint the progress bar
      }
    });
  }

  void _onEpgContextChanged() {
    if (mounted) _sync();
  }

  @override
  void didUpdateWidget(IptvRailEpgCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel?.url != widget.channel?.url) _sync();
  }

  @override
  void dispose() {
    IptvEpgService.instance.contextVersion.removeListener(_onEpgContextChanged);
    _fetchDebounce?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  void _sync() {
    _fetchDebounce?.cancel();
    final ch = widget.channel;
    _forUrl = ch?.url;
    if (ch == null || !IptvEpgService.isEpgCapable(ch)) {
      setState(() {
        _data = null;
        _loading = false;
      });
      return;
    }
    // Paint straight from cache when we can; otherwise show the skeleton and
    // fetch once focus has rested a beat.
    final cached = IptvEpgService.instance.peekNowNext(ch.url);
    if (cached != null) {
      setState(() {
        _data = cached;
        _loading = false;
      });
      return;
    }
    setState(() {
      _data = null;
      _loading = true;
    });
    _fetchDebounce = Timer(const Duration(milliseconds: 250), _fetch);
  }

  Future<void> _fetch() async {
    final url = _forUrl;
    if (url == null) return;
    final result = await IptvEpgService.instance.nowNext(url);
    if (!mounted || url != _forUrl) return;
    setState(() {
      _data = result;
      _loading = false;
    });
  }

  /// This card's ink at a given emphasis.
  ///
  /// The `command` look has no style tokens and reads the app palette, exactly
  /// as it did before — passing `null` tokens returns the same
  /// `core.tx`-at-alpha literal every site used. Edition and Console DO own a
  /// foreground ramp (`fg` / `fgMid` / `fgDim` / `fgFaint`, the mocks'
  /// 100/80/55/35 steps), and the agreed rule is that palette follows the app
  /// theme while a style's own ramp and layout stay the style's. Reading
  /// `core.tx` unconditionally broke that half of it — this is the same
  /// `t == null ? … : t.fgN` shape `_EpgScheduleListState` already uses, just
  /// expressed once instead of eleven times.
  ///
  /// The alpha is the SELECTOR, not the value: each site keeps the alpha it
  /// always passed, and the bands map it onto the ramp step of the same
  /// MEANING. Deliberately semantic bands, not nearest-value ones — Console's
  /// ramp is 100/70/45/28, so a nearest-value rule would put the 0.58 body
  /// text on `fgMid` (a title tone) and the 0.40 metadata on `fgDim` (a body
  /// tone), flattening the hierarchy the alphas were chosen to express.
  /// primary ≥ 0.90 · secondary ≥ 0.65 · body ≥ 0.42 · metadata below.
  Color _ink(AppTheme app, double alpha) {
    final t = widget.tokens;
    if (t == null) return app.core.tx.withValues(alpha: alpha);
    if (alpha >= 0.90) return t.fg;
    if (alpha >= 0.65) return t.fgMid;
    if (alpha >= 0.42) return t.fgDim;
    return t.fgFaint;
  }

  @override
  Widget build(BuildContext context) {
    // The skeleton is a styled-card surface too — `surfaceTint` where the
    // style declares one, the app-ink veil otherwise.
    if (_loading) return _EpgSkeleton(tint: widget.tokens?.selectedTint);
    final app = AppThemeScope.of(context);
    final data = _data;
    if (data == null || data.isEmpty) return const SizedBox.shrink();

    final now = data.now;
    final next = data.next;
    final at = DateTime.now();

    if (widget.stageOverlay) {
      if (now == null) {
        if (next == null) return const SizedBox.shrink();
        return Row(
          children: [
            _EpgTag(
              'NEXT',
              dim: true,
              accent: widget.tokens?.accent,
              // The dim tone is part of the style's ramp too — passing only
              // the accent left REPLAY/NEXT on app ink under a styled panel.
              dimColor: widget.tokens?.fgFaint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                next.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ink(app, 0.78),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _clock(context, next.start),
              style: TextStyle(
                color: _ink(app, 0.48),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _EpgTag('NOW', accent: widget.tokens?.accent),
              const Spacer(),
              Text(
                '${_clock(context, now.start)} – ${_clock(context, now.stop)}',
                style: TextStyle(
                  color: _ink(app, 0.52),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SizedBox(height: widget.dense ? 3 : 7),
          Text(
            now.title,
            maxLines: widget.dense ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _ink(app, 1),
              fontSize: widget.dense ? 14 : 16,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          if (now.description.isNotEmpty) ...[
            SizedBox(height: widget.dense ? 3 : 6),
            if (widget.dense)
              _OverflowMarqueeText(
                text: now.description,
                style: TextStyle(
                  color: _ink(app, 0.58),
                  fontSize: 10.5,
                  height: 1.2,
                ),
              )
            else
              Text(
                now.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ink(app, 0.58),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
          ],
          SizedBox(height: widget.dense ? 5 : 9),
          _EpgProgressBar(
            progress: now.progressAt(at),
            accent: widget.tokens?.accent,
            // `_EpgScheduleList` already passes this; the rail card did not,
            // so a styled panel drew the style's fill on an app-ink track.
            track: widget.tokens?.hairline2,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (now != null) ...[
          Row(
            children: [
              _EpgTag('NOW', accent: widget.tokens?.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_clock(context, now.start)} – ${_clock(context, now.stop)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ink(app, 0.5),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            now.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _ink(app, 1),
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          _EpgProgressBar(
            progress: now.progressAt(at),
            accent: widget.tokens?.accent,
            // `_EpgScheduleList` already passes this; the rail card did not,
            // so a styled panel drew the style's fill on an app-ink track.
            track: widget.tokens?.hairline2,
          ),
          const SizedBox(height: 4),
          Text(
            _remainingLabel(now, at),
            style: TextStyle(
              color: _ink(app, 0.4),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (now.description.isNotEmpty) ...[
            const SizedBox(height: 7),
            Flexible(
              child: Text(
                now.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _ink(app, 0.55),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
        if (next != null) ...[
          if (now != null) const SizedBox(height: 10),
          Row(
            children: [
              _EpgTag(
              'NEXT',
              dim: true,
              accent: widget.tokens?.accent,
              // The dim tone is part of the style's ramp too — passing only
              // the accent left REPLAY/NEXT on app ink under a styled panel.
              dimColor: widget.tokens?.fgFaint,
            ),
              const SizedBox(width: 8),
              Text(
                _clock(context, next.start),
                style: TextStyle(
                  color: _ink(app, 0.45),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  next.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ink(app, 0.72),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static String _remainingLabel(EpgProgramme now, DateTime at) {
    final left = now.stop.difference(at).inMinutes;
    if (left <= 0) return 'ending now';
    if (left == 1) return '1 min left';
    if (left < 60) return '$left min left';
    final h = left ~/ 60, m = left % 60;
    return m == 0 ? '${h}h left' : '${h}h ${m}m left';
  }
}

/// A restrained one-line marquee for the compact TV stage. It stays still when
/// the full description fits, waits before moving, pauses at the end, then
/// resets to the beginning before repeating in the same direction.
class _OverflowMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _OverflowMarqueeText({required this.text, required this.style});

  @override
  State<_OverflowMarqueeText> createState() => _OverflowMarqueeTextState();
}

class _OverflowMarqueeTextState extends State<_OverflowMarqueeText> {
  static const _initialPause = Duration(milliseconds: 1400);
  static const _edgePause = Duration(milliseconds: 1100);
  static const _pixelsPerSecond = 34.0;

  final ScrollController _controller = ScrollController();
  Timer? _pause;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(_OverflowMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _restart();
    }
  }

  void _restart() {
    _generation++;
    _pause?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controller.hasClients) _controller.jumpTo(0);
      _schedule(_initialPause, _generation);
    });
  }

  void _schedule(Duration delay, int generation) {
    _pause?.cancel();
    _pause = Timer(delay, () => _scroll(generation));
  }

  Future<void> _scroll(int generation) async {
    if (!mounted ||
        generation != _generation ||
        !_controller.hasClients ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      return;
    }
    final max = _controller.position.maxScrollExtent;
    if (max <= 0.5) return;
    final distance = (_controller.offset - max).abs();
    final milliseconds = (distance / _pixelsPerSecond * 1000).round().clamp(
      700,
      14000,
    );
    try {
      await _controller.animateTo(
        max,
        duration: Duration(milliseconds: milliseconds),
        curve: Curves.linear,
      );
    } catch (_) {
      return;
    }
    if (!mounted || generation != _generation) return;
    _pause = Timer(_edgePause, () {
      if (!mounted || generation != _generation || !_controller.hasClients) {
        return;
      }
      _controller.jumpTo(0);
      _schedule(_initialPause, generation);
    });
  }

  @override
  void dispose() {
    _generation++;
    _pause?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(
          widget.text,
          maxLines: 1,
          softWrap: false,
          style: widget.style,
        ),
      ),
    );
  }
}

/// Static two-bar placeholder — no shimmer on purpose (TV perf playbook:
/// nothing animates unless it must).
class _EpgSkeleton extends StatelessWidget {
  /// The styled looks' own surface tint. Null keeps the app-ink veil, which is
  /// what `command` and every unstyled caller have always drawn.
  final Color? tint;

  const _EpgSkeleton({this.tint});

  @override
  Widget build(BuildContext context) {
    final veil = tint ?? AppThemeScope.of(context).core.tx.withValues(alpha: 0.07);
    Widget bar(double w) => Container(
      width: w,
      height: 10,
      decoration: BoxDecoration(
        color: veil,
        borderRadius: BorderRadius.circular(5),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [bar(90), const SizedBox(height: 9), bar(190)],
    );
  }
}

/// The schedule rows' record affordance: a red dot+label pill sized to read
/// as a button, brightening with the row's focus. Static styling only (TV).
class _EpgRecordChip extends StatelessWidget {
  final bool emphasized;

  /// Styled-look record color; null keeps the legacy pink family.
  final Color? rec;

  /// Styled-look emphasized-label color (the style's fg) — no literal white
  /// in styled paint.
  final Color? fgOn;

  /// Spotlight's white focus pill: translucent crimson washes out there, so
  /// the chip goes SOLID crimson with white ink.
  final bool solid;
  const _EpgRecordChip({
    required this.emphasized,
    this.rec,
    this.fgOn,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final base = rec ?? AppThemeScope.of(context).iptv.recordAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: solid
            ? base
            : base.withValues(alpha: emphasized ? 0.30 : 0.12),
        border: Border.all(
          color: solid
              ? base
              : base.withValues(alpha: emphasized ? 0.9 : 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: solid ? Colors.white : base,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'Record',
            style: TextStyle(
              color: solid
                  ? Colors.white
                  : rec == null
                  ? (emphasized
                        ? const Color(0xFFFFD9E0)
                        : const Color(0xFFFF8CA3))
                  : (emphasized ? (fgOn ?? base) : base),
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _EpgTag extends StatelessWidget {
  final String text;
  final bool dim;
  final Color? accent;

  /// Styled-look override for the dim tone (REPLAY); null keeps the legacy
  /// white 35%.
  final Color? dimColor;
  const _EpgTag(this.text, {this.dim = false, this.accent, this.dimColor});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final color = dim
        ? (dimColor ?? app.iptv.inkFaint)
        : (accent ?? app.home.focus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: app.shape.br(4),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _EpgProgressBar extends StatelessWidget {
  final double progress;
  final Color? accent;

  /// Styled-look override for the remaining-time track; null keeps the
  /// legacy white 12%.
  final Color? track;
  const _EpgProgressBar({required this.progress, this.accent, this.track});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return ClipRRect(
      borderRadius: app.shape.br(2),
      child: SizedBox(
        height: 3.5,
        child: Row(
          children: [
            Expanded(
              flex: (progress * 1000).round().clamp(0, 1000),
              child: ColoredBox(color: accent ?? app.home.focus),
            ),
            Expanded(
              flex: 1000 - (progress * 1000).round().clamp(0, 1000),
              child: ColoredBox(
                color: track ?? app.core.tx.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Schedule (TV pane + phone sheet) ────────────────────────────────────────

/// The per-channel schedule that swaps into the two-pane layout's right side
/// while the preview keeps playing. TV uses DPAD/BACK; large touch tablets get
/// an explicit back control and tappable replay rows.
class IptvSchedulePane extends StatelessWidget {
  final IptvChannel channel;
  final VoidCallback onClose;
  final bool isTelevision;

  /// Replay a finished programme from the panel archive (Xtream catchup).
  /// Rows only offer it when [IptvEpgService.isCatchupAvailable] says so.
  final void Function(EpgProgramme programme)? onPlayProgramme;

  /// Schedule a future programme for recording (see [EpgScheduleList]).
  final void Function(EpgProgramme programme)? onRecordProgramme;

  const IptvSchedulePane({
    super.key,
    required this.channel,
    required this.onClose,
    this.isTelevision = true,
    this.onPlayProgramme,
    this.onRecordProgramme,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onClose();
      },
      child: FocusScope(
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.goBack ||
                key == LogicalKeyboardKey.escape ||
                key == LogicalKeyboardKey.arrowLeft) {
              onClose();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (!isTelevision)
                      IconButton(
                        key: const ValueKey('iptv-schedule-back'),
                        tooltip: 'Back to channels',
                        onPressed: onClose,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: app.core.tx.withAlpha(0xB3),
                        ),
                      ),
                    Text(
                      'TV GUIDE',
                      style: TextStyle(
                        color: app.home.focus.withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        channel.numberedName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: app.core.tx,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (isTelevision) ...[
                      const SizedBox(width: 10),
                      Text(
                        'BACK to close',
                        style: TextStyle(
                          color: app.iptv.inkFaint,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: EpgScheduleList(
                    channel: channel,
                    isTelevision: isTelevision,
                    onPlayProgramme: onPlayProgramme,
                    onRecordProgramme: onRecordProgramme,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Phone/desktop: the same schedule as a modal bottom sheet. A replay tap
/// closes the sheet before [onPlayProgramme] runs, so the player doesn't
/// stack on top of it. Also the TV fallback when the two-pane layout (and
/// its in-place schedule pane) isn't active — pass [isTelevision] so the
/// rows keep their DPAD focus handling there.
Future<void> showIptvScheduleSheet(
  BuildContext context,
  IptvChannel channel, {
  void Function(EpgProgramme programme)? onPlayProgramme,
  void Function(EpgProgramme programme)? onRecordProgramme,
  bool isTelevision = false,
}) {
  // Read from the surface that opens the sheet, the way downloads_screen does:
  // a modal captures this subtree's inherited themes, freeze included.
  final app = AppThemeScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: app.iptv.modalBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) {
      final height = MediaQuery.of(sheetContext).size.height * 0.72;
      return SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: app.core.tx.withValues(alpha: 0.2),
                  borderRadius: app.shape.br(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_view_day_rounded,
                    size: 18,
                    color: app.home.focus.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      channel.numberedName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: app.core.tx,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: EpgScheduleList(
                channel: channel,
                isTelevision: isTelevision,
                onPlayProgramme: onPlayProgramme == null
                    ? null
                    : (programme) {
                        Navigator.of(sheetContext).pop();
                        onPlayProgramme(programme);
                      },
                // Scheduling shows its own confirm dialog and leaves the sheet
                // up — unlike replay, nothing is about to cover the screen.
                onRecordProgramme: onRecordProgramme,
              ),
            ),
          ],
        ),
      );
    },
  );
}

// ── Shared schedule list ────────────────────────────────────────────────────

sealed class _ScheduleItem {}

class _DayHeader extends _ScheduleItem {
  final String label;
  _DayHeader(this.label);
}

class _ProgrammeItem extends _ScheduleItem {
  final EpgProgramme programme;
  _ProgrammeItem(this.programme);
}

/// The day's programmes for one channel, grouped under Today/Tomorrow
/// headers, with the currently-airing entry highlighted and brought into
/// view. Owns its own fetch; loading and "no data" states stay inside it.
class EpgScheduleList extends StatefulWidget {
  final IptvChannel channel;
  final bool isTelevision;
  final void Function(EpgProgramme programme)? onPlayProgramme;

  /// Schedule a FUTURE programme for recording (the engine's alarm path).
  /// Null hides the affordance entirely — callers gate on the recording
  /// engine being on, Android 10+, and the channel being engine-recordable.
  final void Function(EpgProgramme programme)? onRecordProgramme;

  /// Styled-look tokens from the in-player guide (see
  /// `PlayerGuideStyle`). Null — the IPTV page's two call sites and the
  /// classic player look — keeps every legacy color literal below.
  final IptvStyleTokens? tokens;

  const EpgScheduleList({
    super.key,
    required this.channel,
    required this.isTelevision,
    this.onPlayProgramme,
    this.onRecordProgramme,
    this.tokens,
  });

  @override
  State<EpgScheduleList> createState() => _EpgScheduleListState();
}

class _EpgScheduleListState extends State<EpgScheduleList> {
  static const double _rowExtent = 54;
  static const double _headerExtent = 34;

  List<_ScheduleItem>? _items;
  int _nowIndex = -1;
  bool _loading = true;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final programmes = await IptvEpgService.instance.schedule(
      widget.channel.url,
    );
    if (!mounted) return;

    final now = DateTime.now();
    final items = <_ScheduleItem>[];
    var nowIndex = -1;
    DateTime? day;
    for (final p in programmes) {
      final d = DateTime(p.start.year, p.start.month, p.start.day);
      if (day == null || d != day) {
        day = d;
        items.add(_DayHeader(_dayLabel(d)));
      }
      if (nowIndex == -1 && p.airsAt(now)) nowIndex = items.length;
      items.add(_ProgrammeItem(p));
    }

    // Land on "now" by pre-positioning the scroll BEFORE the list's first
    // build, so the NOW row is in the initially-built viewport and its
    // autofocus applies in the very frame the loading anchor disposes. A
    // post-frame jump instead would leave one frame with nothing in the
    // pane focused — a BACK arriving in that gap (key auto-repeat) would
    // bypass the pane's close handler and hit the page.
    if (nowIndex > 0) {
      var offset = 0.0;
      for (var i = 0; i < nowIndex; i++) {
        offset += items[i] is _DayHeader ? _headerExtent : _rowExtent;
      }
      // No clients yet (the list only builds after setState below), so the
      // controller can be swapped for one with the right starting offset.
      // Overshoot is clamped by the scroll position on first layout.
      _scrollController.dispose();
      _scrollController = ScrollController(
        initialScrollOffset: (offset - 90).clamp(0.0, double.infinity),
      );
    }

    setState(() {
      _items = items;
      _nowIndex = nowIndex;
      _loading = false;
    });
  }

  /// On TV the loading/empty states must themselves hold focus: with no
  /// focusable descendant, DPAD focus would escape the pane and BACK (handled
  /// by the pane's ancestor Focus) could reach the page and close the whole
  /// tab instead of the schedule.
  Widget _focusAnchor(Widget child) {
    if (!widget.isTelevision) return child;
    return Focus(autofocus: true, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = widget.tokens;
    if (_loading) {
      return _focusAnchor(
        Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: t?.accent,
            ),
          ),
        ),
      );
    }
    final items = _items;
    if (items == null || items.isEmpty) {
      return _focusAnchor(
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.tv_off_rounded,
                size: 42,
                color: t == null
                    ? app.core.tx.withValues(alpha: 0.25)
                    : t.fgFaint,
              ),
              const SizedBox(height: 12),
              Text(
                'No guide data for this channel',
                style: TextStyle(
                  color: t == null
                      ? app.iptv.inkDim
                      : t.fgDim,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final now = DateTime.now();
    return FocusTraversalGroup(
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(
          bottom: 24,
          left: widget.isTelevision ? 0 : 8,
          right: widget.isTelevision ? 0 : 8,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          if (item is _DayHeader) {
            return SizedBox(
              height: _headerExtent,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 6),
                  child: Text(
                    item.label.toUpperCase(),
                    style: TextStyle(
                      color: t == null
                          ? app.core.tx.withValues(alpha: 0.4)
                          : t.fgDim,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
            );
          }
          final programme = (item as _ProgrammeItem).programme;
          final onPlay = widget.onPlayProgramme;
          final replayable =
              onPlay != null &&
              IptvEpgService.isCatchupAvailable(widget.channel, programme);
          final onRecord = widget.onRecordProgramme;
          // Now-airing counts: recording it captures the rest and stops at
          // its end (the schedule backend late-joins a past start).
          final recordable = onRecord != null && programme.stop.isAfter(now);
          return _ScheduleRow(
            programme: programme,
            isNow: index == _nowIndex,
            isPast: !programme.stop.isAfter(now),
            isTelevision: widget.isTelevision,
            autofocus:
                widget.isTelevision &&
                (index == _nowIndex || (_nowIndex == -1 && index == 1)),
            onPlay: replayable ? () => onPlay(programme) : null,
            onRecord: recordable ? () => onRecord(programme) : null,
            tokens: t,
          );
        },
      ),
    );
  }
}

class _ScheduleRow extends StatefulWidget {
  final EpgProgramme programme;
  final bool isNow;
  final bool isPast;
  final bool isTelevision;
  final bool autofocus;

  /// Non-null when this (finished) programme can be replayed from the panel
  /// archive — OK on TV / tap on touch plays it, and the row wears a REPLAY
  /// tag instead of fading out like ordinary past entries.
  final VoidCallback? onPlay;

  /// Non-null when this programme can be recorded — now-airing (records the
  /// rest, ending on time) or future. OK/tap opens the confirm flow, and the
  /// row wears a Record chip. Mutually exclusive with [onPlay] by
  /// construction (replay is past, record is now/future).
  final VoidCallback? onRecord;

  final IptvStyleTokens? tokens;

  const _ScheduleRow({
    required this.programme,
    required this.isNow,
    required this.isPast,
    required this.isTelevision,
    required this.autofocus,
    this.onPlay,
    this.onRecord,
    this.tokens,
  });

  @override
  State<_ScheduleRow> createState() => _ScheduleRowState();
}

class _ScheduleRowState extends State<_ScheduleRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final p = widget.programme;
    final replayable = widget.onPlay != null;
    // Replayable past programmes stay readable — they're actionable, not
    // history; ordinary past rows fade.
    final titleAlpha = widget.isPast
        ? (replayable ? 0.7 : 0.38)
        : (widget.isNow ? 1.0 : 0.85);

    final t = widget.tokens;
    // Spotlight inverse focus: solid white pill, dark ink (focusFill/focusInk
    // come as an asserted pair).
    final inverse = _focused && t?.focusFill != null;
    final ink = inverse ? t!.focusInk! : null;
    final row = Container(
      height: _EpgScheduleListState._rowExtent,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _focused
            ? (t == null ? app.iptv.rowFocusFill : (t.focusFill ?? t.focusTint))
            : (widget.isNow
                  ? (t == null
                        ? app.iptv.surfaceTint
                        : t.selectedTint)
                  : Colors.transparent),
        borderRadius: app.shape.br(10),
        border: Border.all(
          color: _focused && !inverse
              ? (t == null ? app.home.focus : t.accent)
              : Colors.transparent,
          width: 2,
        ),
        boxShadow: inverse
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              _clock(context, p.start),
              style: TextStyle(
                color: ink?.withValues(alpha: widget.isPast ? 0.45 : 0.6) ??
                    (widget.isNow
                        ? (t == null ? app.home.focus : t.accent)
                        : (t == null
                              ? app.core.tx.withValues(
                                  alpha: widget.isPast ? 0.3 : 0.5,
                                )
                              : (widget.isPast ? t.fgFaint : t.fgDim))),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: t != null && t.monoFamily.isNotEmpty
                    ? t.monoFamily
                    : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink?.withValues(alpha: titleAlpha) ??
                        (t == null
                            ? app.core.tx.withValues(alpha: titleAlpha)
                            : t.fg.withValues(alpha: titleAlpha)),
                    fontSize: 13.5,
                    fontWeight: widget.isNow
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                if (widget.isNow) ...[
                  const SizedBox(height: 5),
                  _EpgProgressBar(
                    progress: p.progressAt(DateTime.now()),
                    accent: ink ?? t?.accent,
                    track: inverse
                        ? ink!.withValues(alpha: 0.18)
                        : t?.hairline2,
                  ),
                ],
              ],
            ),
          ),
          if (widget.isNow)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _EpgTag('NOW', accent: ink ?? t?.accent),
            ),
          if (replayable)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _EpgTag(
                'REPLAY',
                dim: true,
                // Crimson at 9px sits just under contrast on the white
                // pill — deepen it there.
                dimColor: inverse ? const Color(0xFFB8202F) : t?.rec,
              ),
            ),
          // A chip that reads as the button it is (the dim "REC" text looked
          // like metadata). Sits beside NOW on the airing row: "record the
          // rest of this".
          if (widget.onRecord != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _EpgRecordChip(
                emphasized: _focused,
                rec: t?.rec,
                fgOn: t?.fg,
                solid: inverse,
              ),
            ),
        ],
      ),
    );

    if (!widget.isTelevision) {
      final onTap = widget.onPlay ?? widget.onRecord;
      if (onTap == null) return row;
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: row,
      );
    }

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: Duration.zero,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        // OK replays an archived programme, or schedules a future one for
        // recording; on inert rows it's swallowed so it can't fall through to
        // whatever sits behind the pane.
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          (widget.onPlay ?? widget.onRecord)?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: row,
    );
  }
}

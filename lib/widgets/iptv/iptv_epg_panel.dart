import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/iptv_playlist.dart';
import '../../services/iptv_epg_service.dart';
import '../home/home_theme.dart';
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

  const IptvRailEpgCard({
    super.key,
    required this.channel,
    this.stageOverlay = false,
    this.dense = false,
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _EpgSkeleton();
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
            const _EpgTag('NEXT', dim: true),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                next.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _clock(context, next.start),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.48),
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
              const _EpgTag('NOW'),
              const Spacer(),
              Text(
                '${_clock(context, now.start)} – ${_clock(context, now.stop)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.52),
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
              color: Colors.white,
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
                  color: Colors.white.withValues(alpha: 0.58),
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
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
          ],
          SizedBox(height: widget.dense ? 5 : 9),
          _EpgProgressBar(progress: now.progressAt(at)),
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
              const _EpgTag('NOW'),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_clock(context, now.start)} – ${_clock(context, now.stop)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          _EpgProgressBar(progress: now.progressAt(at)),
          const SizedBox(height: 4),
          Text(
            _remainingLabel(now, at),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
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
                  color: Colors.white.withValues(alpha: 0.55),
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
              const _EpgTag('NEXT', dim: true),
              const SizedBox(width: 8),
              Text(
                _clock(context, next.start),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
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
                    color: Colors.white.withValues(alpha: 0.72),
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
  const _EpgSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double w) => Container(
      width: w,
      height: 10,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
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

class _EpgTag extends StatelessWidget {
  final String text;
  final bool dim;
  const _EpgTag(this.text, {this.dim = false});

  @override
  Widget build(BuildContext context) {
    final color = dim
        ? Colors.white.withValues(alpha: 0.35)
        : HomeTheme.focusGold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
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
  const _EpgProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3.5,
        child: Row(
          children: [
            Expanded(
              flex: (progress * 1000).round().clamp(0, 1000),
              child: const ColoredBox(color: HomeTheme.focusGold),
            ),
            Expanded(
              flex: 1000 - (progress * 1000).round().clamp(0, 1000),
              child: ColoredBox(color: Colors.white.withValues(alpha: 0.12)),
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

  const IptvSchedulePane({
    super.key,
    required this.channel,
    required this.onClose,
    this.isTelevision = true,
    this.onPlayProgramme,
  });

  @override
  Widget build(BuildContext context) {
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
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    Text(
                      'TV GUIDE',
                      style: TextStyle(
                        color: HomeTheme.focusGold.withValues(alpha: 0.9),
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
                        style: const TextStyle(
                          color: Colors.white,
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
                          color: Colors.white.withValues(alpha: 0.35),
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
  bool isTelevision = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF14141D),
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
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
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
                    color: HomeTheme.focusGold.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      channel.numberedName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
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
  const EpgScheduleList({
    super.key,
    required this.channel,
    required this.isTelevision,
    this.onPlayProgramme,
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
    if (_loading) {
      return _focusAnchor(
        const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5),
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
                color: Colors.white.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 12),
              Text(
                'No guide data for this channel',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
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
                      color: Colors.white.withValues(alpha: 0.4),
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
          return _ScheduleRow(
            programme: programme,
            isNow: index == _nowIndex,
            isPast: !programme.stop.isAfter(now),
            isTelevision: widget.isTelevision,
            autofocus:
                widget.isTelevision &&
                (index == _nowIndex || (_nowIndex == -1 && index == 1)),
            onPlay: replayable ? () => onPlay(programme) : null,
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

  const _ScheduleRow({
    required this.programme,
    required this.isNow,
    required this.isPast,
    required this.isTelevision,
    required this.autofocus,
    this.onPlay,
  });

  @override
  State<_ScheduleRow> createState() => _ScheduleRowState();
}

class _ScheduleRowState extends State<_ScheduleRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.programme;
    final replayable = widget.onPlay != null;
    // Replayable past programmes stay readable — they're actionable, not
    // history; ordinary past rows fade.
    final titleAlpha = widget.isPast
        ? (replayable ? 0.7 : 0.38)
        : (widget.isNow ? 1.0 : 0.85);

    final row = Container(
      height: _EpgScheduleListState._rowExtent,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _focused
            ? const Color(0xFF141824)
            : (widget.isNow
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.transparent),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _focused ? HomeTheme.focusGold : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(
              _clock(context, p.start),
              style: TextStyle(
                color: widget.isNow
                    ? HomeTheme.focusGold
                    : Colors.white.withValues(alpha: widget.isPast ? 0.3 : 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w700,
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
                    color: Colors.white.withValues(alpha: titleAlpha),
                    fontSize: 13.5,
                    fontWeight: widget.isNow
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                if (widget.isNow) ...[
                  const SizedBox(height: 5),
                  _EpgProgressBar(progress: p.progressAt(DateTime.now())),
                ],
              ],
            ),
          ),
          if (widget.isNow)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: _EpgTag('NOW'),
            )
          else if (replayable)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: _EpgTag('REPLAY', dim: true),
            ),
        ],
      ),
    );

    if (!widget.isTelevision) {
      if (!replayable) return row;
      return GestureDetector(
        onTap: widget.onPlay,
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
        // OK replays an archived programme; on anything else it's swallowed
        // so it can't fall through to whatever sits behind the pane.
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          widget.onPlay?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: row,
    );
  }
}

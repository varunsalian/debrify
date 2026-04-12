import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stremio_addon.dart';
import '../models/trakt/trakt_calendar_entry.dart';
import '../services/trakt/trakt_calendar_service.dart';
import '../services/trakt/trakt_service.dart';
import '../widgets/trakt_calendar_day_sheet.dart';

/// Full-screen grid calendar of upcoming Trakt episodes.
///
/// Layout: AppBar + vertical list of month blocks. Each block is a 7-column
/// grid. Infinite scroll in both directions via lazy chunk fetching.
class TraktCalendarScreen extends StatefulWidget {
  const TraktCalendarScreen({super.key});

  @override
  State<TraktCalendarScreen> createState() => _TraktCalendarScreenState();
}

class _TraktCalendarScreenState extends State<TraktCalendarScreen> {
  bool _isAuth = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  final List<DateTime> _monthStarts = [];
  Map<DateTime, List<TraktCalendarEntry>> _byDay = const {};
  final ScrollController _scrollController = ScrollController();

  /// GlobalKeys for each month block, keyed by month start date. Used by
  /// [_jumpToToday] to scroll precisely to the current month via
  /// [Scrollable.ensureVisible] without relying on fixed-height estimates.
  final Map<DateTime, GlobalKey> _monthKeys = {};

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final isAuth = await TraktService.instance.isAuthenticated();
    if (!mounted) return;
    if (!isAuth) {
      setState(() {
        _isAuth = false;
        _isLoading = false;
      });
      return;
    }

    final now = DateTime.now();
    final prevMonthStart = DateTime(now.year, now.month - 1, 1);
    final thisMonthStart = DateTime(now.year, now.month, 1);
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);
    // Load 3 months (prev + current + next) so the total content height always
    // exceeds the phone viewport (~700px). With only 2 months the content can
    // fit on screen, leaving maxScrollExtent ≈ 0 and making touch scroll
    // impossible until a lazy-load completes.
    final rangeStart = prevMonthStart;
    final rangeEnd = DateTime(now.year, now.month + 2, 0);

    final grouped = await TraktCalendarService.instance.getRange(rangeStart, rangeEnd);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _byDay = grouped;
      _monthStarts
        ..clear()
        ..addAll([
          prevMonthStart,
          thisMonthStart,
          nextMonthStart,
        ]);
    });

    // Scroll to the current month so the user doesn't land on the previous
    // month (which is only loaded to ensure enough content for scrolling).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _monthKeys[thisMonthStart];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.0);
      }
    });
  }

  void _onDayTap(DateTime day, List<TraktCalendarEntry> entries) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TraktCalendarDaySheet(
        date: day,
        entries: entries,
        onEpisodeSelected: _handleEpisodeSelected,
      ),
    );
  }

  void _handleEpisodeSelected(StremioMeta meta) {
    Navigator.of(context).pop(meta);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            tooltip: 'Jump to today',
            icon: const Icon(Icons.today),
            onPressed: _isLoading ? null : _jumpToToday,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_isAuth) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Connect Trakt to see your calendar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_monthStarts.isEmpty) {
      return const Center(
        child: Text('Nothing airing.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _monthStarts.length,
      itemBuilder: (ctx, index) {
        final monthStart = _monthStarts[index];
        final key = _monthKeys.putIfAbsent(monthStart, () => GlobalKey());
        return _MonthBlock(
          key: key,
          monthStart: monthStart,
          byDay: _byDay,
          onDayTap: _onDayTap,
        );
      },
    );
  }

  void _jumpToToday() {
    final now = DateTime.now();
    final thisMonthStart = DateTime(now.year, now.month, 1);

    // Fast path: the current month is built in the viewport (or within the
    // cache extent) — let Flutter calculate the exact offset.
    final key = _monthKeys[thisMonthStart];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.0, // top-align the month header
      );
      return;
    }

    // Slow path: the current month isn't mounted (user scrolled far away).
    // Do a best-effort jump based on index, wait a frame for the ListView to
    // build the month, then call ensureVisible for pixel-perfect alignment.
    final idx = _monthStarts.indexWhere((m) => m == thisMonthStart);
    if (idx < 0) return;
    // 500 is a middle-ground estimate — month heights range roughly 350-900
    // depending on cell size and row count. The post-frame ensureVisible
    // corrects any error.
    _scrollController.jumpTo((idx * 500.0).clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx2 = _monthKeys[thisMonthStart]?.currentContext;
      if (ctx2 != null) {
        Scrollable.ensureVisible(
          ctx2,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: 0.0,
        );
      }
    });
  }

  void _onScroll() {
    if (_isLoadingMore || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final pos = _scrollController.position.pixels;

    // Use else-if so only ONE direction fires per scroll event. Without this,
    // both can start concurrently (both conditions are true when content fits
    // the viewport), racing on _monthStarts / setState and causing scroll jumps.
    if (pos < 600) {
      _prependPreviousMonth();
    } else if (pos > max - 600) {
      _appendNextMonth();
    }
  }

  Future<void> _appendNextMonth() async {
    if (_monthStarts.isEmpty) return;
    _isLoadingMore = true;
    final last = _monthStarts.last;
    final next = DateTime(last.year, last.month + 1, 1);
    final rangeEnd = DateTime(next.year, next.month + 1, 0);
    final grouped = await TraktCalendarService.instance.getRange(next, rangeEnd);
    if (!mounted) {
      _isLoadingMore = false;
      return;
    }
    setState(() {
      _monthStarts.add(next);
      _byDay = {..._byDay, ...grouped};
    });
    // Release the loading flag AFTER the new state has been laid out so the
    // scroll listener doesn't fire a cascading append while maxScrollExtent
    // is still being recalculated.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _isLoadingMore = false;
    });
  }

  Future<void> _prependPreviousMonth() async {
    if (_monthStarts.isEmpty) return;
    _isLoadingMore = true;
    final first = _monthStarts.first;
    final prev = DateTime(first.year, first.month - 1, 1);
    final rangeEnd = DateTime(prev.year, prev.month + 1, 0);
    final grouped = await TraktCalendarService.instance.getRange(prev, rangeEnd);
    if (!mounted) {
      _isLoadingMore = false;
      return;
    }
    final beforeMax = _scrollController.position.maxScrollExtent;
    final beforePos = _scrollController.position.pixels;
    setState(() {
      _monthStarts.insert(0, prev);
      _byDay = {..._byDay, ...grouped};
    });
    // CRITICAL: keep _isLoadingMore=true until AFTER the viewport jump so the
    // scroll listener doesn't see an intermediate state (new content, old
    // position still < 600) and fire another prepend. Without this guard,
    // prepend cascades and the view lands in an unexpected month.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        _isLoadingMore = false;
        return;
      }
      final afterMax = _scrollController.position.maxScrollExtent;
      final delta = afterMax - beforeMax;
      _scrollController.jumpTo(beforePos + delta);
      _isLoadingMore = false;
    });
  }
}

/// Renders one month header + 7-column day grid.
class _MonthBlock extends StatelessWidget {
  const _MonthBlock({
    super.key,
    required this.monthStart,
    required this.byDay,
    required this.onDayTap,
  });

  final DateTime monthStart;
  final Map<DateTime, List<TraktCalendarEntry>> byDay;
  final void Function(DateTime day, List<TraktCalendarEntry> entries) onDayTap;

  @override
  Widget build(BuildContext context) {
    final monthLabel = _formatMonth(monthStart);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              monthLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const _DowHeader(),
          const SizedBox(height: 4),
          _DayGrid(
            monthStart: monthStart,
            byDay: byDay,
            onDayTap: onDayTap,
          ),
        ],
      ),
    );
  }

  static String _formatMonth(DateTime m) {
    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return '${months[m.month - 1]} ${m.year}';
  }
}

class _DowHeader extends StatelessWidget {
  const _DowHeader();

  @override
  Widget build(BuildContext context) {
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.monthStart,
    required this.byDay,
    required this.onDayTap,
  });

  final DateTime monthStart;
  final Map<DateTime, List<TraktCalendarEntry>> byDay;
  final void Function(DateTime day, List<TraktCalendarEntry> entries) onDayTap;

  @override
  Widget build(BuildContext context) {
    final cells = _computeCells();
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cellSize = constraints.maxWidth / 7;
        return Column(
          children: [
            for (int rowStart = 0; rowStart < cells.length; rowStart += 7)
              Row(
                children: [
                  for (int i = 0; i < 7; i++)
                    SizedBox(
                      width: cellSize,
                      height: cellSize,
                      child: _DayCell(
                        cell: cells[rowStart + i],
                        cellWidth: cellSize,
                        onTap: onDayTap,
                        byDay: byDay,
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  /// Build cells covering the month, padded with prev/next month days.
  List<_Cell> _computeCells() {
    final firstOfMonth = monthStart;
    // Sunday is column 0 — Dart Monday=1, ... Sunday=7, so modulo 7 maps Sunday to 0
    final leadingBlank = firstOfMonth.weekday % 7;
    final daysInMonth = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 0).day;

    final cells = <_Cell>[];
    for (int i = leadingBlank; i > 0; i--) {
      final d = firstOfMonth.subtract(Duration(days: i));
      cells.add(_Cell(date: d, inMonth: false));
    }
    for (int day = 1; day <= daysInMonth; day++) {
      cells.add(_Cell(
        date: DateTime(firstOfMonth.year, firstOfMonth.month, day),
        inMonth: true,
      ));
    }
    while (cells.length % 7 != 0) {
      final last = cells.last.date;
      cells.add(_Cell(date: last.add(const Duration(days: 1)), inMonth: false));
    }
    return cells;
  }
}

class _Cell {
  final DateTime date;
  final bool inMonth;
  _Cell({required this.date, required this.inMonth});
}

class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.cell,
    required this.cellWidth,
    required this.onTap,
    required this.byDay,
  });

  final _Cell cell;
  final double cellWidth;
  final void Function(DateTime day, List<TraktCalendarEntry> entries) onTap;
  final Map<DateTime, List<TraktCalendarEntry>> byDay;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      debugLabel: 'day-${widget.cell.date}',
      skipTraversal: !widget.cell.inMonth,
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = widget.cell.date.year == now.year &&
        widget.cell.date.month == now.month &&
        widget.cell.date.day == now.day;
    final entries = widget.byDay[DateTime(
          widget.cell.date.year,
          widget.cell.date.month,
          widget.cell.date.day,
        )] ??
        const [];
    final hasEntries = entries.isNotEmpty && widget.cell.inMonth;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Opacity(
        opacity: widget.cell.inMonth ? 1.0 : 0.3,
        child: Focus(
          focusNode: _focusNode,
          canRequestFocus: hasEntries,
          onKeyEvent: (node, event) {
            if (!hasEntries) return KeyEventResult.ignored;
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.space ||
                key == LogicalKeyboardKey.gameButtonA) {
              widget.onTap(
                DateTime(
                  widget.cell.date.year,
                  widget.cell.date.month,
                  widget.cell.date.day,
                ),
                entries,
              );
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Builder(
            builder: (ctx) {
              final isFocused = Focus.of(ctx).hasFocus;
              return Material(
                color: isFocused
                    ? const Color(0xFF1E293B)
                    : const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: isFocused
                        ? const Color(0xFF60A5FA)
                        : (isToday
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF1E293B)),
                    width: (isFocused || isToday) ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: hasEntries
                      ? () => widget.onTap(
                            DateTime(
                              widget.cell.date.year,
                              widget.cell.date.month,
                              widget.cell.date.day,
                            ),
                            entries,
                          )
                      : null,
                  child: Padding(
                    padding: EdgeInsets.all(widget.cellWidth > 120 ? 8 : 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.cell.date.day}',
                          style: TextStyle(
                            color: isToday
                                ? const Color(0xFF60A5FA)
                                : Colors.white70,
                            fontSize: widget.cellWidth > 120 ? 15 : 11,
                            fontWeight: isToday
                                ? FontWeight.w700
                                : (widget.cellWidth > 120
                                    ? FontWeight.w600
                                    : FontWeight.w400),
                          ),
                        ),
                        SizedBox(height: widget.cellWidth > 120 ? 6 : 0),
                        if (entries.isNotEmpty)
                          Expanded(
                            child: _DayCellSummary(
                              entries: entries,
                              cellWidth: widget.cellWidth,
                            ),
                          )
                        else
                          const Spacer(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DayCellSummary extends StatelessWidget {
  const _DayCellSummary({required this.entries, required this.cellWidth});

  final List<TraktCalendarEntry> entries;
  final double cellWidth;

  @override
  Widget build(BuildContext context) {
    // Very narrow: dots + count indicator.
    if (cellWidth < 48) {
      return Align(
        alignment: Alignment.bottomLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: _colorForShow(entries.first.showTitle),
                shape: BoxShape.circle,
              ),
            ),
            if (entries.length > 1) ...[
              const SizedBox(width: 2),
              Text(
                '${entries.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 9),
              ),
            ],
          ],
        ),
      );
    }

    // Wide: rich chips with mini poster + bigger text.
    // Threshold is 120 (not higher) because Android TV at 1080p density 2.0
    // yields ~132px logical cells — needs to land in this tier, not bars.
    if (cellWidth > 120) {
      final visible = entries.take(2).toList();
      final overflow = entries.length > 2 ? entries.length - 2 : 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in visible)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _RichChip(entry: e, accent: _colorForShow(e.showTitle), cellWidth: cellWidth),
            ),
          if (overflow > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Text(
                '+$overflow more',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      );
    }

    // Medium (phones): colored bars at the bottom — one per episode, full
    // width, 3px tall. Same approach as Google Calendar's event indicators.
    // Text/images are unreadable at this cell size; color-coding is enough
    // to communicate "which shows, how many" at a glance.
    final maxBars = cellWidth > 80 ? 4 : 3;
    final visible = entries.take(maxBars).toList();
    final overflow = entries.length > maxBars ? entries.length - maxBars : 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in visible)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: _colorForShow(e.showTitle),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              '+$overflow',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 7,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  static Color _colorForShow(String title) {
    const palette = [
      Color(0xFF8B5CF6),
      Color(0xFF22C55E),
      Color(0xFFEF4444),
      Color(0xFFF59E0B),
      Color(0xFF3B82F6),
      Color(0xFFEC4899),
      Color(0xFF14B8A6),
      Color(0xFFF97316),
    ];
    int hash = 0;
    for (final c in title.codeUnits) {
      hash = (hash * 31 + c) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }
}

/// Rich chip for wide-screen day cells — mini poster + show name + episode label
/// on a show-colored accent background.
class _RichChip extends StatelessWidget {
  const _RichChip({
    required this.entry,
    required this.accent,
    required this.cellWidth,
  });

  final TraktCalendarEntry entry;
  final Color accent;
  final double cellWidth;

  @override
  Widget build(BuildContext context) {
    // Scale poster + text to the available cell space.
    // 140-200: compact rich. 200-280: medium. 280+: TV-scale.
    final double posterW;
    final double posterH;
    final double titleSize;
    final double epSize;
    final double iconSize;
    final double gap;
    final double padH;
    final double padV;
    final double radius;

    if (cellWidth > 250) {
      // TV / very wide — big and readable from across the room
      posterW = 48;
      posterH = 72;
      titleSize = 16;
      epSize = 13;
      iconSize = 22;
      gap = 12;
      padH = 10;
      padV = 8;
      radius = 10;
    } else if (cellWidth > 170) {
      // Desktop / large tablet
      posterW = 36;
      posterH = 54;
      titleSize = 14;
      epSize = 11;
      iconSize = 18;
      gap = 10;
      padH = 8;
      padV = 6;
      radius = 8;
    } else {
      // TV at high density / smaller wide screens (120-170)
      posterW = 26;
      posterH = 38;
      titleSize = 12;
      epSize = 10;
      iconSize = 14;
      gap = 8;
      padH = 6;
      padV = 4;
      radius = 6;
    }

    final placeholder = Container(
      width: posterW,
      height: posterH,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(radius * 0.5),
      ),
      child: Icon(Icons.tv_rounded, size: iconSize, color: Colors.white70),
    );

    return Container(
      padding: EdgeInsets.fromLTRB(padV, padV, padH, padV),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radius * 0.5),
            child: entry.posterUrl != null
                ? Image.network(
                    entry.posterUrl!,
                    width: posterW,
                    height: posterH,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => placeholder,
                  )
                : placeholder,
          ),
          SizedBox(width: gap),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.showTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: cellWidth > 200 ? 4 : 2),
                Text(
                  'S${entry.seasonNumber.toString().padLeft(2, '0')}E${entry.episodeNumber.toString().padLeft(2, '0')}',
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: epSize,
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

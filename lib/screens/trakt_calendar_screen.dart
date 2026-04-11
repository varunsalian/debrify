import 'package:flutter/material.dart';

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
    final thisMonthStart = DateTime(now.year, now.month, 1);
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);
    // Fetch current + next month upfront. Previous months are loaded lazily
    // via _prependPreviousMonth when the user scrolls near the top.
    final rangeStart = thisMonthStart;
    final rangeEnd = DateTime(now.year, now.month + 2, 0);

    final grouped = await TraktCalendarService.instance.getRange(rangeStart, rangeEnd);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _byDay = grouped;
      _monthStarts
        ..clear()
        ..addAll([
          thisMonthStart,
          nextMonthStart,
        ]);
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
      itemCount: _monthStarts.length,
      itemBuilder: (ctx, index) {
        final monthStart = _monthStarts[index];
        return _MonthBlock(
          monthStart: monthStart,
          byDay: _byDay,
          onDayTap: _onDayTap,
        );
      },
    );
  }

  void _jumpToToday() {
    final now = DateTime.now();
    final idx = _monthStarts.indexWhere(
      (m) => m.year == now.year && m.month == now.month,
    );
    if (idx >= 0) {
      _scrollController.animateTo(
        idx * 420.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _onScroll() {
    if (_isLoadingMore || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final pos = _scrollController.position.pixels;

    if (pos > max - 600) {
      _appendNextMonth();
    }
    if (pos < 600) {
      _prependPreviousMonth();
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
    _isLoadingMore = false;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final afterMax = _scrollController.position.maxScrollExtent;
      final delta = afterMax - beforeMax;
      _scrollController.jumpTo(beforePos + delta);
    });
    _isLoadingMore = false;
  }
}

/// Renders one month header + 7-column day grid.
class _MonthBlock extends StatelessWidget {
  const _MonthBlock({
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
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.cell.date.day}',
                          style: TextStyle(
                            color: isToday
                                ? const Color(0xFF60A5FA)
                                : Colors.white70,
                            fontSize: 11,
                            fontWeight: isToday
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                        const Spacer(),
                        if (entries.isNotEmpty)
                          _DayCellSummary(
                            entries: entries,
                            cellWidth: widget.cellWidth,
                          ),
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
    if (cellWidth < 48) {
      return Row(
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
      );
    }

    final maxName = cellWidth > 100 ? 16 : 8;
    final visible = entries.take(2).toList();
    final overflow = entries.length > 2 ? entries.length - 2 : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in visible)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: _colorForShow(e.showTitle),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                _truncate(e.showTitle, maxName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 9),
              ),
            ),
          ),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '+$overflow',
              style: const TextStyle(color: Colors.white54, fontSize: 9),
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

  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max - 1)}…';
  }
}

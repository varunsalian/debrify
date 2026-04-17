import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stremio_addon.dart';
import '../models/trakt/trakt_calendar_entry.dart';
import '../services/trakt/trakt_calendar_service.dart';
import '../services/trakt/trakt_service.dart';
import '../widgets/trakt_calendar_day_sheet.dart';

class TraktCalendarScreen extends StatefulWidget {
  const TraktCalendarScreen({super.key});

  @override
  State<TraktCalendarScreen> createState() => _TraktCalendarScreenState();
}

class _TraktCalendarScreenState extends State<TraktCalendarScreen> {
  static const Color _kNetflixRed = Color(0xFFE50914);

  final FocusNode _yearFocusNode = FocusNode(debugLabel: 'trakt-year-selector');
  final FocusNode _monthFocusNode = FocusNode(
    debugLabel: 'trakt-month-selector',
  );
  final Map<DateTime, FocusNode> _dayFocusNodes = <DateTime, FocusNode>{};
  final Map<DateTime, Map<DateTime, List<TraktCalendarEntry>>> _monthCache =
      <DateTime, Map<DateTime, List<TraktCalendarEntry>>>{};
  final Map<DateTime, Future<void>> _inFlightMonthLoads =
      <DateTime, Future<void>>{};

  late int _selectedYear;
  late int _selectedMonth;
  bool _isAuth = true;
  bool _isLoading = true;
  bool _isChangingMonth = false;
  int _latestMonthChangeRequestId = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _loadInitial();
  }

  @override
  void dispose() {
    _yearFocusNode.dispose();
    _monthFocusNode.dispose();
    for (final node in _dayFocusNodes.values) {
      node.dispose();
    }
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

    final currentMonth = _selectedMonthStart;
    await _ensureMonthLoaded(currentMonth);
    await _ensureMonthLoaded(
      DateTime(currentMonth.year, currentMonth.month + 1, 1),
    );

    if (!mounted) return;
    setState(() {
      _isAuth = true;
      _isLoading = false;
    });
  }

  DateTime get _selectedMonthStart =>
      DateTime(_selectedYear, _selectedMonth, 1);

  Future<void> _ensureMonthLoaded(DateTime monthStart) async {
    final normalized = _monthOnly(monthStart);
    if (_monthCache.containsKey(normalized)) return;
    final existing = _inFlightMonthLoads[normalized];
    if (existing != null) {
      await existing;
      return;
    }

    final future = () async {
      final monthEnd = DateTime(normalized.year, normalized.month + 1, 0);
      final grouped = await TraktCalendarService.instance.getRange(
        normalized,
        monthEnd,
      );
      if (!mounted) return;
      setState(() {
        _monthCache[normalized] = grouped;
      });
    }();

    _inFlightMonthLoads[normalized] = future;
    try {
      await future;
    } finally {
      _inFlightMonthLoads.remove(normalized);
    }
  }

  Future<void> _selectMonth({
    int? year,
    int? month,
    bool focusFirstDay = false,
  }) async {
    final nextYear = year ?? _selectedYear;
    final nextMonth = month ?? _selectedMonth;
    final nextStart = DateTime(nextYear, nextMonth, 1);
    if (_selectedYear == nextYear && _selectedMonth == nextMonth) return;
    final requestId = ++_latestMonthChangeRequestId;

    setState(() {
      _selectedYear = nextYear;
      _selectedMonth = nextMonth;
      _isChangingMonth = true;
    });

    await _ensureMonthLoaded(nextStart);

    if (!mounted) return;
    if (requestId != _latestMonthChangeRequestId) return;
    setState(() {
      _isChangingMonth = false;
    });

    if (focusFirstDay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusFirstVisibleDay();
      });
    }
  }

  void _focusFirstVisibleDay() {
    final days = _visibleDays;
    if (days.isEmpty) return;
    final node = _focusNodeForDay(days.first.day);
    if (node.canRequestFocus) {
      node.requestFocus();
    }
  }

  FocusNode _focusNodeForDay(DateTime day) {
    final normalized = _dateOnly(day);
    return _dayFocusNodes.putIfAbsent(
      normalized,
      () => FocusNode(debugLabel: 'trakt-day-$normalized'),
    );
  }

  List<_AiringDay> get _visibleDays {
    final grouped =
        _monthCache[_selectedMonthStart] ??
        const <DateTime, List<TraktCalendarEntry>>{};
    final days =
        grouped.entries
            .where((entry) => entry.value.isNotEmpty)
            .map(
              (entry) => _AiringDay(
                day: entry.key,
                entries: [...entry.value]
                  ..sort(
                    (a, b) => a.firstAiredLocal.compareTo(b.firstAiredLocal),
                  ),
              ),
            )
            .toList()
          ..sort((a, b) => a.day.compareTo(b.day));
    return days;
  }

  int get _episodeCount =>
      _visibleDays.fold<int>(0, (sum, item) => sum + item.entries.length);

  List<int> get _yearOptions {
    return List<int>.generate(51, (index) => _selectedYear - 25 + index);
  }

  void _openDaySheet(DateTime day, List<TraktCalendarEntry> entries) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0C1222),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFF060816),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Trakt Calendar'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF171B30), Color(0xFF0B1020), Color(0xFF060816)],
          ),
        ),
        child: SafeArea(top: false, child: _buildBody(isWide)),
      ),
    );
  }

  Widget _buildBody(bool isWide) {
    if (!_isAuth) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Connect Trakt to see your calendar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final days = _visibleDays;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 1040 : 1180),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isWide ? 28 : 16,
            10,
            isWide ? 28 : 16,
            isWide ? 28 : 18,
          ),
          child: Column(
            children: [
              _buildHeaderSurface(days, isWide),
              const SizedBox(height: 16),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  child: _isChangingMonth
                      ? const Center(
                          key: ValueKey('changing-month'),
                          child: CircularProgressIndicator(),
                        )
                      : days.isEmpty
                      ? _EmptyMonthState(
                          key: ValueKey('empty-$_selectedYear-$_selectedMonth'),
                          monthLabel: _monthName(_selectedMonth),
                          year: _selectedYear,
                        )
                      : _buildDayList(days, isWide),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSurface(List<_AiringDay> days, bool isWide) {
    final isCompact = MediaQuery.of(context).size.width < 560;
    final monthLabel = '${_monthName(_selectedMonth)} $_selectedYear';
    final summary = days.isEmpty
        ? 'No upcoming episodes found for this month.'
        : '${days.length} airing day${days.length == 1 ? '' : 's'} · $_episodeCount episode${_episodeCount == 1 ? '' : 's'}';

    return Container(
      padding: EdgeInsets.fromLTRB(
        isWide ? 22 : (isCompact ? 14 : 16),
        isWide ? 20 : (isCompact ? 14 : 16),
        isWide ? 22 : (isCompact ? 14 : 16),
        isWide ? 18 : (isCompact ? 14 : 16),
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF211017), Color(0xFF110A0F), Color(0xFF07090F)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: _kNetflixRed.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: _kNetflixRed.withValues(alpha: 0.14),
            ),
            child: Text(
              'YOUR TRAKT SCHEDULE',
              style: TextStyle(
                color: const Color(0xFFFFC4C8),
                fontSize: isCompact ? 10 : 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SizedBox(height: isCompact ? 10 : 12),
          Text(
            monthLabel,
            style: TextStyle(
              color: Colors.white,
              fontSize: isCompact ? 22 : 30,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          SizedBox(height: isCompact ? 6 : 8),
          if (!isCompact) ...[
            Text(
              'Pick a year and month, then browse only the days that actually have episodes airing. No grid, no jitter, just the schedule.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Text(
              'Only days with actual episodes are shown.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (isCompact)
            Row(
              children: [
                Expanded(
                  child: _SelectorField(
                    label: 'Year',
                    value: _selectedYear,
                    focusNode: _yearFocusNode,
                    dense: true,
                    items: [
                      for (final year in _yearOptions)
                        DropdownMenuItem<int>(
                          value: year,
                          child: Text('$year'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _selectMonth(year: value);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SelectorField(
                    label: 'Month',
                    value: _selectedMonth,
                    focusNode: _monthFocusNode,
                    dense: true,
                    items: [
                      for (int i = 1; i <= 12; i++)
                        DropdownMenuItem<int>(
                          value: i,
                          child: Text(_monthName(i)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _selectMonth(month: value, focusFirstDay: true);
                    },
                  ),
                ),
              ],
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: isWide ? 170 : 160,
                  child: _SelectorField(
                    label: 'Year',
                    value: _selectedYear,
                    focusNode: _yearFocusNode,
                    items: [
                      for (final year in _yearOptions)
                        DropdownMenuItem<int>(
                          value: year,
                          child: Text('$year'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _selectMonth(year: value);
                    },
                  ),
                ),
                SizedBox(
                  width: isWide ? 210 : 190,
                  child: _SelectorField(
                    label: 'Month',
                    value: _selectedMonth,
                    focusNode: _monthFocusNode,
                    items: [
                      for (int i = 1; i <= 12; i++)
                        DropdownMenuItem<int>(
                          value: i,
                          child: Text(_monthName(i)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      _selectMonth(month: value, focusFirstDay: true);
                    },
                  ),
                ),
              ],
            ),
          SizedBox(height: isCompact ? 10 : 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 12 : 14,
                  vertical: isCompact ? 8 : 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: _kNetflixRed.withValues(alpha: 0.14),
                  border: Border.all(
                    color: _kNetflixRed.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      size: isCompact ? 14 : 16,
                      color: const Color(0xFFFFB3B8),
                    ),
                    SizedBox(width: isCompact ? 6 : 8),
                    Text(
                      summary,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isCompact ? 11 : 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayList(List<_AiringDay> days, bool isWide) {
    return ListView.separated(
      key: ValueKey('list-$_selectedYear-$_selectedMonth'),
      padding: EdgeInsets.zero,
      itemCount: days.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final airingDay = days[index];
        return _AiringDayCard(
          day: airingDay.day,
          entries: airingDay.entries,
          isWide: isWide,
          focusNode: _focusNodeForDay(airingDay.day),
          onOpen: () => _openDaySheet(airingDay.day, airingDay.entries),
          onArrowUp: index == 0
              ? () => _monthFocusNode.requestFocus()
              : () => _focusNodeForDay(days[index - 1].day).requestFocus(),
          onArrowDown: index == days.length - 1
              ? null
              : () => _focusNodeForDay(days[index + 1].day).requestFocus(),
        );
      },
    );
  }

  static DateTime _monthOnly(DateTime value) =>
      DateTime(value.year, value.month, 1);

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }
}

class _SelectorField<T> extends StatelessWidget {
  const _SelectorField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.focusNode,
    this.dense = false,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final FocusNode focusNode;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      focusNode: focusNode,
      items: items,
      onChanged: onChanged,
      dropdownColor: const Color(0xFF12182B),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
        filled: true,
        fillColor: const Color(0xFF1A1720),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(
            color: _TraktCalendarScreenState._kNetflixRed,
            width: 2,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: dense ? 12 : 16,
        ),
      ),
      iconEnabledColor: Colors.white70,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      borderRadius: BorderRadius.circular(18),
    );
  }
}

class _AiringDay {
  const _AiringDay({required this.day, required this.entries});

  final DateTime day;
  final List<TraktCalendarEntry> entries;
}

class _AiringDayCard extends StatelessWidget {
  const _AiringDayCard({
    required this.day,
    required this.entries,
    required this.isWide,
    required this.focusNode,
    required this.onOpen,
    required this.onArrowUp,
    required this.onArrowDown,
  });

  final DateTime day;
  final List<TraktCalendarEntry> entries;
  final bool isWide;
  final FocusNode focusNode;
  final VoidCallback onOpen;
  final VoidCallback onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(entries.first.showTitle);
    return Focus(
      focusNode: focusNode,
      onFocusChange: (focused) {
        if (!focused) return;
        final ctx = focusNode.context;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.12,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          onArrowUp();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          onArrowDown?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.gameButtonA) {
          onOpen();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isFocused
                    ? const Color(0xFFE85A63)
                    : Colors.white.withValues(alpha: 0.06),
                width: isFocused ? 2 : 1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF141219).withValues(alpha: 0.98),
                  const Color(0xFF0A0B12).withValues(alpha: 0.98),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                ),
                if (isFocused)
                  BoxShadow(
                    color: const Color(0xFFE50914).withValues(alpha: 0.22),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: onOpen,
              child: Padding(
                padding: EdgeInsets.all(isWide ? 18 : 14),
                child: isWide
                    ? _buildWideLayout(accent)
                    : _buildCompactLayout(accent),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWideLayout(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DayHeaderStrip(
          posterUrl: entries.first.posterUrl,
          accent: accent,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _DateBadge(day: day, accent: accent),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            _formatHeadline(day),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _CountPill(count: entries.length, accent: accent),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entries.length == 1
                          ? 'One episode scheduled'
                          : '${entries.length} episodes scheduled',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              _PosterThumb(
                posterUrl: entries.first.posterUrl,
                width: 56,
                height: 82,
                radius: 16,
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.42),
                size: 28,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in entries.take(2))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _EpisodeRow(entry: entry),
          ),
        if (entries.length > 2)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '+${entries.length - 2} more episodes',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCompactLayout(Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DayHeaderStrip(
          posterUrl: entries.first.posterUrl,
          accent: accent,
          compact: true,
          child: Row(
            children: [
              _DateBadge(day: day, accent: accent, compact: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatHeadline(day),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _CountPill(count: entries.length, accent: accent),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _PosterThumb(
                posterUrl: entries.first.posterUrl,
                width: 44,
                height: 62,
                radius: 14,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final entry in entries.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _EpisodeRow(entry: entry),
          ),
        if (entries.length > 3)
          Text(
            '+${entries.length - 3} more episodes',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.58),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  static String _formatHeadline(DateTime day) {
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
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${weekdays[day.weekday - 1]}, ${months[day.month - 1]} ${day.day}';
  }

  static Color _accentFor(String title) {
    const palette = [
      Color(0xFFE50914),
      Color(0xFFF97316),
      Color(0xFFFB7185),
      Color(0xFFDC2626),
      Color(0xFFEF4444),
      Color(0xFFB91C1C),
    ];
    var hash = 0;
    for (final code in title.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({
    required this.day,
    required this.accent,
    this.compact = false,
  });

  final DateTime day;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const shortDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Container(
      width: compact ? 64 : 78,
      padding: EdgeInsets.symmetric(vertical: compact ? 10 : 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.22), const Color(0xFF191B23)],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${day.day}',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 24 : 30,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            shortDays[day.weekday - 1],
            style: TextStyle(
              color: accent,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.accent});

  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withValues(alpha: 0.16),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Text(
        '$count episode${count == 1 ? '' : 's'}',
        style: TextStyle(
          color: accent,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.entry});

  final TraktCalendarEntry entry;

  @override
  Widget build(BuildContext context) {
    final accent = _AiringDayCard._accentFor(entry.showTitle);
    final time = _formatTime(entry.firstAiredLocal);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF181922),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PosterThumb(
            posterUrl: entry.posterUrl,
            width: 38,
            height: 54,
            radius: 10,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.showTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'S${entry.seasonNumber.toString().padLeft(2, '0')}E${entry.episodeNumber.toString().padLeft(2, '0')} · $time'
                  '${entry.episodeTitle != null ? ' · ${entry.episodeTitle}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 28,
                  height: 3,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime local) {
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _PosterThumb extends StatelessWidget {
  const _PosterThumb({
    required this.posterUrl,
    required this.width,
    required this.height,
    required this.radius,
  });

  final String? posterUrl;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A1117), Color(0xFF181A24)],
        ),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.live_tv_rounded, color: Colors.white70, size: 18),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: posterUrl == null
          ? placeholder
          : Image.network(
              posterUrl!,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}

class _DayHeaderStrip extends StatelessWidget {
  const _DayHeaderStrip({
    required this.posterUrl,
    required this.accent,
    required this.child,
    this.compact = false,
  });

  final String? posterUrl;
  final Color accent;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          Positioned.fill(
            child: posterUrl == null
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent.withValues(alpha: 0.14),
                          const Color(0xFF12131A),
                        ],
                      ),
                    ),
                  )
                : Image.network(
                    posterUrl!,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (_, __, ___) => DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: 0.14),
                            const Color(0xFF12131A),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: compact ? 0.26 : 0.18),
                    const Color(0xFF10131C).withValues(alpha: 0.78),
                    const Color(0xFF10131C),
                  ],
                  stops: const [0.0, 0.52, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    const Color(0xFF11131B),
                    const Color(0xFF11131B).withValues(alpha: 0.82),
                    const Color(0xFF11131B).withValues(alpha: 0.48),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.0),
                    accent.withValues(alpha: 0.7),
                    accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(compact ? 10 : 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              borderRadius: BorderRadius.circular(22),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _EmptyMonthState extends StatelessWidget {
  const _EmptyMonthState({
    super.key,
    required this.monthLabel,
    required this.year,
  });

  final String monthLabel;
  final int year;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        color: const Color(0xFF0A0F1D).withValues(alpha: 0.96),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: Colors.white.withValues(alpha: 0.05),
            ),
            child: const Icon(
              Icons.event_busy_rounded,
              color: Colors.white70,
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Nothing airing in $monthLabel $year',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try another month or year. This screen only lists days that actually have episodes, so empty months stay clean.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.66),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

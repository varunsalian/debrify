import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/trakt/trakt_calendar_entry.dart';
import '../services/analytics_service.dart';
import '../services/android_native_downloader.dart';
import '../services/main_page_bridge.dart';
import '../services/simkl/simkl_calendar_service.dart';
import '../services/simkl/simkl_service.dart';
import '../services/trakt/trakt_calendar_service.dart';
import '../services/trakt/trakt_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_scope.dart';
import '../widgets/trakt_calendar_day_sheet.dart';
import '../utils/tv_keys.dart';

class TraktCalendarScreen extends StatefulWidget {
  const TraktCalendarScreen({super.key});

  @override
  State<TraktCalendarScreen> createState() => _TraktCalendarScreenState();
}

class _TraktCalendarScreenState extends State<TraktCalendarScreen> {
  final FocusNode _yearFocusNode = FocusNode(debugLabel: 'trakt-year-selector');
  final FocusNode _monthFocusNode = FocusNode(
    debugLabel: 'trakt-month-selector',
  );
  final FocusNode _sourceFocusNode = FocusNode(
    debugLabel: 'calendar-source-selector',
  );
  final Map<DateTime, FocusNode> _dayFocusNodes = <DateTime, FocusNode>{};
  final Map<DateTime, Map<DateTime, List<TraktCalendarEntry>>> _monthCache =
      <DateTime, Map<DateTime, List<TraktCalendarEntry>>>{};
  final Map<DateTime, Future<void>> _inFlightMonthLoads =
      <DateTime, Future<void>>{};

  // Calendar source: 'trakt' or 'simkl'. Both trackers can be connected at once,
  // in which case a Source dropdown swaps between them; a single-tracker user
  // sees no dropdown and their one calendar (identical to the pre-Simkl page).
  static const String _sourceTrakt = 'trakt';
  static const String _sourceSimkl = 'simkl';
  String _source = _sourceTrakt;
  bool _traktAuthed = false;
  bool _simklAuthed = false;
  // Bumped on every source switch; an in-flight month load carries the value it
  // started with and drops its result if the source changed underneath it.
  int _sourceGen = 0;

  late int _selectedYear;
  late int _selectedMonth;
  bool _isAuth = true;
  bool _isLoading = true;
  bool _isChangingMonth = false;
  bool _isTelevision = false;
  int _latestMonthChangeRequestId = 0;

  bool get _bothAuthed => _traktAuthed && _simklAuthed;
  String get _sourceName => _source == _sourceSimkl ? 'Simkl' : 'Trakt';

  // Remember the last-viewed month across this app session. Opening a title from
  // the calendar switches to the Home tab (which hosts the detail page), which
  // disposes+remounts this screen; without this, returning would snap back to
  // today instead of the month the user was browsing. Session-scoped (static) —
  // intentionally resets to the current month on a full app restart.
  static int? _lastViewedYear;
  static int? _lastViewedMonth;
  // Likewise remember the chosen source across the detail round-trip's
  // dispose+remount (both-authed users), so returning keeps the schedule they
  // were on instead of snapping back to the Trakt default.
  static String? _lastSource;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('trakt_calendar');
    final now = DateTime.now();
    _selectedYear = _lastViewedYear ?? now.year;
    _selectedMonth = _lastViewedMonth ?? now.month;
    _detectTelevision();
    _loadInitial();
  }

  @override
  void dispose() {
    _yearFocusNode.dispose();
    _monthFocusNode.dispose();
    _sourceFocusNode.dispose();
    for (final node in _dayFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _detectTelevision() async {
    final isTv = await AndroidNativeDownloader.isTelevision();
    if (mounted) setState(() => _isTelevision = isTv);
  }

  Future<void> _loadInitial() async {
    final results = await Future.wait([
      TraktService.instance.isAuthenticated(),
      SimklService.instance.isAuthenticated(),
    ]);
    if (!mounted) return;
    final traktAuthed = results[0];
    final simklAuthed = results[1];
    // Keep the source chosen earlier this session (across the detail round-trip)
    // IF it's still connected; otherwise default to Trakt when connected
    // (preserves the pre-Simkl behaviour), falling back to Simkl-only.
    final remembered = _lastSource;
    final source =
        (remembered == _sourceSimkl && simklAuthed) ||
                (remembered == _sourceTrakt && traktAuthed)
            ? remembered!
            : (traktAuthed ? _sourceTrakt : (simklAuthed ? _sourceSimkl : _sourceTrakt));
    final isAuth = source == _sourceSimkl ? simklAuthed : traktAuthed;

    setState(() {
      _traktAuthed = traktAuthed;
      _simklAuthed = simklAuthed;
      _source = source;
    });
    _lastSource = source;

    if (!isAuth) {
      setState(() {
        _isAuth = false;
        _isLoading = false;
      });
      return;
    }

    await _loadCurrentAndNextMonth();

    if (!mounted) return;
    setState(() {
      _isAuth = true;
      _isLoading = false;
    });
  }

  /// Preload the selected month and the next one (shared by initial load and
  /// source switching).
  Future<void> _loadCurrentAndNextMonth() async {
    final currentMonth = _selectedMonthStart;
    await _ensureMonthLoaded(currentMonth);
    await _ensureMonthLoaded(
      DateTime(currentMonth.year, currentMonth.month + 1, 1),
    );
  }

  /// Swap the calendar source (only reachable when both trackers are
  /// connected). Clears the per-month cache — it isn't keyed by source — and
  /// bumps [_sourceGen] so any in-flight load for the old source is dropped,
  /// then reloads the visible month for the new source.
  Future<void> _onSourceChanged(String? source) async {
    if (source == null || source == _source) return;
    setState(() {
      _source = source;
      _sourceGen++;
      _monthCache.clear();
      _inFlightMonthLoads.clear();
      _isChangingMonth = false;
      _isLoading = true;
    });
    _lastSource = source; // survive the detail round-trip's remount
    await _loadCurrentAndNextMonth();
    if (!mounted) return;
    setState(() => _isLoading = false);
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

    final gen = _sourceGen;
    final source = _source;
    final future = () async {
      final monthEnd = DateTime(normalized.year, normalized.month + 1, 0);
      final grouped = source == _sourceSimkl
          ? await SimklCalendarService.instance.getRange(normalized, monthEnd)
          : await TraktCalendarService.instance.getRange(normalized, monthEnd);
      if (!mounted) return;
      // The source was switched while this fetch was in flight — its result is
      // for the old tracker, so discard it (the new source reloads separately).
      if (gen != _sourceGen) return;
      setState(() {
        _monthCache[normalized] = grouped;
      });
    }();

    _inFlightMonthLoads[normalized] = future;
    try {
      await future;
    } finally {
      // Only clear OUR entry: a source switch may have cleared the map and
      // registered a newer future for this month, which we must not evict.
      if (identical(_inFlightMonthLoads[normalized], future)) {
        _inFlightMonthLoads.remove(normalized);
      }
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
    // Remember it for the round-trip through a title's detail page (see fields).
    _lastViewedYear = nextYear;
    _lastViewedMonth = nextMonth;

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
      backgroundColor: AppThemeScope.of(context).calendar.sheetBg,
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

  void _handleEpisodeSelected(TraktCalendarEntry entry) {
    // The day sheet already dismissed itself before calling this (see
    // TraktCalendarDaySheet) — do NOT pop again here, or we'd pop the MainPage
    // root (the calendar is a tab now, not a pushed route). Hand the title off
    // to the Home board, which owns the merged detail page and its Play/Sources
    // machinery (a separate tab can't push that flow itself): switchTab(15)
    // mounts Home, which opens the detail scrolled to this episode and returns
    // here (originTab) when it closes.
    final imdbId = entry.showImdbId;
    if (imdbId == null || imdbId.isEmpty) return;
    MainPageBridge.pendingCatalogDetailOpen = {
      'imdbId': imdbId,
      // Trakt's calendar is show-episodes only, so these are always series.
      'type': 'series',
      'title': entry.showTitle,
      'year': entry.showYear,
      'poster': entry.posterUrl,
      'season': entry.seasonNumber,
      'episode': entry.episodeNumber,
      'originTab': 19, // return to the Calendar tab when the detail closes
    };
    MainPageBridge.switchTab?.call(15);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: app.calendar.bg,
      appBar: _isTelevision
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: Text('$_sourceName Calendar'),
            ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF171B30),
              const Color(0xFF0B1020),
              app.calendar.bg,
            ],
          ),
        ),
        child: SafeArea(top: false, child: _buildBody(isWide, app)),
      ),
    );
  }

  Widget _buildBody(bool isWide, AppTheme app) {
    if (!_isAuth) {
      // Only reachable when neither tracker is connected (the default source is
      // whichever IS connected), so phrase it for both.
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Connect Trakt or Simkl to see your calendar.',
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

    if (_isTelevision) return _buildTvBody(days, isWide, app);

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
              _buildHeaderSurface(days, isWide, app),
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
                      : _buildDayList(days, isWide, app),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTvBody(List<_AiringDay> days, bool isWide, AppTheme app) {
    final dayListWidget = AnimatedSwitcher(
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
              compact: true,
            )
          : _buildDayList(days, isWide, app),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: _buildTvHeaderSurface(days, app),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(child: dayListWidget),
        ],
      ),
    );
  }

  /// The Trakt/Simkl source dropdown — only when BOTH trackers are connected
  /// (a single-tracker user has nothing to switch). Returns null otherwise so
  /// callers can conditionally omit it. Styled like the Year/Month selectors,
  /// so DPAD steps into/out of it identically.
  Widget? _buildSourceSelector({bool dense = false}) {
    if (!_bothAuthed) return null;
    return _SelectorField<String>(
      label: 'Source',
      value: _source,
      focusNode: _sourceFocusNode,
      dense: dense,
      items: const [
        DropdownMenuItem<String>(value: _sourceTrakt, child: Text('Trakt')),
        DropdownMenuItem<String>(value: _sourceSimkl, child: Text('Simkl')),
      ],
      onChanged: _onSourceChanged,
    );
  }

  Widget _buildTvHeaderSurface(List<_AiringDay> days, AppTheme app) {
    final monthLabel = '${_monthName(_selectedMonth)} $_selectedYear';
    final summary = days.isEmpty
        ? 'No episodes this month.'
        : '${days.length} airing day${days.length == 1 ? '' : 's'} · $_episodeCount episode${_episodeCount == 1 ? '' : 's'}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: app.shape.br(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF211017), Color(0xFF110A0F), Color(0xFF07090F)],
        ),
        border: Border.all(color: app.core.tx.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: app.fade(app.calendar.accent, 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: app.shape.brPill,
              color: app.fade(app.calendar.accent, 0.14),
            ),
            child: Text(
              'YOUR ${_sourceName.toUpperCase()} SCHEDULE',
              style: const TextStyle(
                color: Color(0xFFFFC4C8),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            monthLabel,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Browse only the days that have episodes airing.',
            style: TextStyle(
              color: app.core.tx.withValues(alpha: 0.68),
              fontSize: 11,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          if (_buildSourceSelector(dense: true) case final sourceField?) ...[
            sourceField,
            const SizedBox(height: 8),
          ],
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
              const SizedBox(width: 8),
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
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: app.shape.brPill,
              color: app.fade(app.calendar.accent, 0.14),
              border: Border.all(
                color: app.fade(app.calendar.accent, 0.22),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  size: 13,
                  color: Color(0xFFFFB3B8),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    summary,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSurface(List<_AiringDay> days, bool isWide, AppTheme app) {
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
        borderRadius: app.shape.br(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF211017), Color(0xFF110A0F), Color(0xFF07090F)],
        ),
        border: Border.all(color: app.core.tx.withValues(alpha: 0.07)),
        boxShadow: [
          BoxShadow(
            color: app.fade(app.calendar.accent, 0.12),
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
              borderRadius: app.shape.brPill,
              color: app.fade(app.calendar.accent, 0.14),
            ),
            child: Text(
              'YOUR ${_sourceName.toUpperCase()} SCHEDULE',
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
                color: app.core.tx.withValues(alpha: 0.72),
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Text(
              'Only days with actual episodes are shown.',
              style: TextStyle(
                color: app.core.tx.withValues(alpha: 0.68),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_buildSourceSelector(dense: isCompact) case final sourceField?) ...[
            sourceField,
            SizedBox(height: isCompact ? 10 : 12),
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
                  borderRadius: app.shape.brPill,
                  color: app.fade(app.calendar.accent, 0.14),
                  border: Border.all(
                    color: app.fade(app.calendar.accent, 0.22),
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

  Widget _buildDayList(List<_AiringDay> days, bool isWide, AppTheme app) {
    return ListView.separated(
      key: ValueKey('list-$_selectedYear-$_selectedMonth'),
      padding: EdgeInsets.zero,
      itemCount: days.length,
      separatorBuilder: (_, __) => SizedBox(height: _isTelevision ? 8 : 12),
      itemBuilder: (context, index) {
        final airingDay = days[index];
        return _AiringDayCard(
          // Captured from the enclosing build, never read per item: this list
          // scrolls a month of days on TV.
          app: app,
          day: airingDay.day,
          entries: airingDay.entries,
          isWide: isWide,
          isTelevision: _isTelevision,
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
    final app = AppThemeScope.of(context);
    return DropdownButtonFormField<T>(
      value: value,
      focusNode: focusNode,
      items: items,
      onChanged: onChanged,
      dropdownColor: const Color(0xFF12182B),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: app.core.tx.withValues(alpha: 0.72)),
        filled: true,
        fillColor: const Color(0xFF1A1720),
        border: OutlineInputBorder(
          borderRadius: app.shape.br(18),
          borderSide: BorderSide(color: app.core.tx.withValues(alpha: 0.07)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: app.shape.br(18),
          borderSide: BorderSide(color: app.core.tx.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(
            color: app.calendar.accent,
            width: 2,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: dense ? 12 : 16,
        ),
      ),
      iconEnabledColor: Colors.white70,
      // Explicit color: the dropdown renders its menu with this style,
      // outside the page's DefaultTextStyle. onSurface follows the
      // Appearance → Text Brightness preset.
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      borderRadius: app.shape.br(18),
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
    required this.app,
    required this.day,
    required this.entries,
    required this.isWide,
    required this.focusNode,
    required this.onOpen,
    required this.onArrowUp,
    required this.onArrowDown,
    this.isTelevision = false,
  });

  /// Handed down from the list's build — the card is created inside a
  /// `ListView.separated` itemBuilder, which must not read the scope itself.
  final AppTheme app;
  final DateTime day;
  final List<TraktCalendarEntry> entries;
  final bool isWide;
  final bool isTelevision;
  final FocusNode focusNode;
  final VoidCallback onOpen;
  final VoidCallback onArrowUp;
  final VoidCallback? onArrowDown;

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(
      entries.first.showTitle,
      app.calendar.accentPalette,
    );
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
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
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
              borderRadius: BorderRadius.circular(isTelevision ? 16 : 26),
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
                  app.fade(app.calendar.card, 0.98),
                  app.fade(app.calendar.card2, 0.98),
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
                    color: app.fade(app.calendar.accent, 0.22),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(isTelevision ? 16 : 26),
              onTap: onOpen,
              child: Padding(
                padding: EdgeInsets.all(isTelevision ? 10 : (isWide ? 18 : 14)),
                child: isTelevision
                    ? _buildTvLayout(accent)
                    : isWide
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
          app: app,
          posterUrl: entries.first.posterUrl,
          accent: accent,
          compact: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _DateBadge(
                day: day,
                accent: accent,
                badgeGround: app.calendar.badgeGround,
                compact: true,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatHeadline(day),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _CountPill(count: entries.length, accent: accent),
                        Text(
                          entries.length == 1
                              ? 'One episode scheduled'
                              : '${entries.length} episodes scheduled',
                          style: TextStyle(
                            // Inside _DayHeaderStrip, whose ground IS
                            // calendar.panel — so this ink may follow the
                            // theme. The rows below sit on hardcoded darks
                            // and deliberately do not.
                            color: app.fade(app.core.tx, 0.62),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in entries.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _EpisodeRow(
              entry: entry,
              app: app,
              palette: app.calendar.accentPalette,
              rowGround: app.calendar.row,
              rowLine: app.calendar.line,
              roomy: true,
            ),
          ),
        if (entries.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '+${entries.length - 3} more episodes',
              style: TextStyle(
                color: app.fade(app.core.tx, 0.58),
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
          app: app,
          posterUrl: entries.first.posterUrl,
          accent: accent,
          compact: true,
          child: Row(
            children: [
              _DateBadge(
                day: day,
                accent: accent,
                badgeGround: app.calendar.badgeGround,
                compact: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatHeadline(day),
                      style: const TextStyle(
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
            child: _EpisodeRow(
              entry: entry,
              app: app,
              palette: app.calendar.accentPalette,
              rowGround: app.calendar.row,
              rowLine: app.calendar.line,
            ),
          ),
        if (entries.length > 3)
          Text(
            '+${entries.length - 3} more episodes',
            style: TextStyle(
              color: app.fade(app.core.tx, 0.58),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  Widget _buildTvLayout(Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DateBadge(
          day: day,
          accent: accent,
          badgeGround: app.calendar.badgeGround,
          compact: true,
          tv: true,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatHeadline(day),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _CountPill(count: entries.length, accent: accent, compact: true),
                ],
              ),
              const SizedBox(height: 6),
              for (final entry in entries.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _EpisodeRow(
                    entry: entry,
                    app: app,
              palette: app.calendar.accentPalette,
              rowGround: app.calendar.row,
              rowLine: app.calendar.line,
                    compact: true,
                  ),
                ),
              if (entries.length > 3)
                Text(
                  '+${entries.length - 3} more',
                  style: TextStyle(
                    color: app.fade(app.core.tx, 0.58),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
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

  /// The per-title tone, hashed into [palette] (`calendar.accentPalette`).
  ///
  /// The palette arrives as an argument because a static cannot read the
  /// theme scope — and its ORDER is part of the contract: the hash indexes
  /// it, so reordering silently recolours every show.
  static Color _accentFor(String title, List<Color> palette) {
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
    required this.badgeGround,
    this.compact = false,
    this.tv = false,
  });

  final DateTime day;
  final Color accent;

  /// `calendar.badgeGround`, threaded like [accent] rather than read here —
  /// these badges are built per day inside the list.
  final Color badgeGround;
  final bool compact;
  final bool tv;

  @override
  Widget build(BuildContext context) {
    const shortDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final w = tv ? 48.0 : (compact ? 64.0 : 78.0);
    final vPad = tv ? 7.0 : (compact ? 10.0 : 12.0);
    final dayFontSize = tv ? 18.0 : (compact ? 24.0 : 30.0);
    final labelFontSize = tv ? 9.0 : (compact ? 11.0 : 12.0);
    return Container(
      width: w,
      padding: EdgeInsets.symmetric(vertical: vPad),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tv ? 12 : 20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.22), badgeGround],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: tv ? 8 : 16,
            offset: Offset(0, tv ? 4 : 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${day.day}',
            style: TextStyle(
              fontSize: dayFontSize,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            shortDays[day.weekday - 1],
            style: TextStyle(
              color: accent,
              fontSize: labelFontSize,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.accent, this.compact = false});

  final int count;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withValues(alpha: 0.16),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Text(
        '$count episode${count == 1 ? '' : 's'}',
        style: TextStyle(
          color: accent,
          fontSize: compact ? 10 : 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.entry,
    required this.app,
    required this.palette,
    required this.rowGround,
    required this.rowLine,
    this.roomy = false,
    this.compact = false,
  });

  final TraktCalendarEntry entry;

  /// Threaded, not read here — these rows are built inside the day list, and
  /// the row's INK has to move with [rowGround] for the same reason the
  /// palette does.
  final AppTheme app;

  /// `calendar.accentPalette`, handed down rather than read here — these rows
  /// are built inside the day list.
  final List<Color> palette;

  /// `calendar.row` / `calendar.line`. Threaded WITH the palette because the
  /// palette colours the text that sits on this ground: migrate one without
  /// the other and a light theme puts deep ink on a dark row.
  final Color rowGround;
  final Color rowLine;
  final bool roomy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = _AiringDayCard._accentFor(entry.showTitle, palette);
    final time = _formatTime(entry.firstAiredLocal);
    final code =
        'S${entry.seasonNumber.toString().padLeft(2, '0')}'
        'E${entry.episodeNumber.toString().padLeft(2, '0')}';
    final detail = entry.episodeTitle == null || entry.episodeTitle!.isEmpty
        ? code
        : '$code · ${entry.episodeTitle}';

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: app.shape.br(10),
          color: rowGround,
          border: Border.all(color: rowLine),
        ),
        child: Row(
          children: [
            _PosterThumb(posterUrl: entry.posterUrl, width: 28, height: 40, radius: 7),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.showTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: app.fade(app.core.tx, 0.68),
                      fontSize: 10,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: app.shape.brPill,
                color: accent.withValues(alpha: 0.14),
                border: Border.all(color: accent.withValues(alpha: 0.22)),
              ),
              child: Text(
                time,
                style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(roomy ? 12 : 10),
      decoration: BoxDecoration(
        borderRadius: app.shape.br(16),
        color: rowGround,
        border: Border.all(color: rowLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PosterThumb(
            posterUrl: entry.posterUrl,
            width: roomy ? 46 : 38,
            height: roomy ? 64 : 54,
            radius: roomy ? 12 : 10,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        entry.showTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: roomy ? 15 : 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: app.shape.brPill,
                        color: accent.withValues(alpha: 0.14),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Text(
                        time,
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  maxLines: roomy ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: app.fade(app.core.tx, 0.68),
                    fontSize: roomy ? 12.5 : 12,
                    height: 1.25,
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
    required this.app,
    required this.posterUrl,
    required this.accent,
    required this.child,
    this.compact = false,
  });

  /// Handed down from the card, which is itself built inside the day list.
  final AppTheme app;
  final String? posterUrl;
  final Color accent;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: app.shape.brImg(22),
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
                    app.calendar.panel,
                    app.fade(app.calendar.panel, 0.82),
                    app.fade(app.calendar.panel, 0.48),
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
              border: Border.all(color: app.core.tx.withValues(alpha: 0.04)),
              borderRadius: app.shape.br(22),
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
    this.compact = false,
  });

  final String monthLabel;
  final int year;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 18 : 28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        color: const Color(0xFF0A0F1D).withValues(alpha: 0.96),
      ),
      padding: EdgeInsets.all(compact ? 16 : 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Container(
            width: compact ? 48 : 68,
            height: compact ? 48 : 68,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 14 : 22),
              color: Colors.white.withValues(alpha: 0.05),
            ),
            child: Icon(
              Icons.event_busy_rounded,
              color: Colors.white70,
              size: compact ? 22 : 30,
            ),
          ),
          SizedBox(height: compact ? 12 : 18),
          Text(
            'Nothing airing in $monthLabel $year',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 16 : 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try another month or year.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.66),
              fontSize: compact ? 12 : 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

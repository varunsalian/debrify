import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/trakt/trakt_calendar_entry.dart';
import '../screens/trakt_calendar_screen.dart';
import '../services/trakt/trakt_calendar_service.dart';
import '../services/trakt/trakt_service.dart';
import 'home/home_theme.dart';
import 'home/home_section_reveal.dart';
import 'home_focus_controller.dart';
import 'home_trakt_now_playing_card.dart';
import '../utils/tv_keys.dart';

/// "Today" card at the top of Home showing upcoming Trakt episodes.
///
/// Three visible states:
/// - **Hidden**: Trakt not connected OR nothing airing in the next 7 days
/// - **Loading**: thin skeleton while first fetch is in flight
/// - **Hero**: full-bleed fanart card showing a featured episode (today's
///   first, or the next upcoming if today is empty) with a countdown pill,
///   a mini date tile, and a 7-day timeline strip for week-at-a-glance
///   multi-show awareness
class HomeTodayCalendarCard extends StatefulWidget {
  const HomeTodayCalendarCard({
    super.key,
    required this.focusController,
    required this.isTelevision,
    required this.onRequestFocusAbove,
    required this.onRequestFocusBelow,
    required this.onItemSelected,
    this.onInitialLoadStateChanged,
  });

  final HomeFocusController focusController;
  final bool isTelevision;
  final VoidCallback onRequestFocusAbove;
  final VoidCallback onRequestFocusBelow;
  final void Function(TraktCalendarEntry entry) onItemSelected;
  final ValueChanged<bool>? onInitialLoadStateChanged;

  @override
  State<HomeTodayCalendarCard> createState() => _HomeTodayCalendarCardState();
}

class _HomeTodayCalendarCardState extends State<HomeTodayCalendarCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _isAuth = false;
  bool _isLoading = true;
  bool _initialLoadSettled = false;
  Map<DateTime, List<TraktCalendarEntry>> _grouped = const {};
  final FocusNode _cardFocusNode = FocusNode(
    debugLabel: 'home-today-calendar-card',
  );

  void _onFocusChange(bool focused) {
    if (!focused || !widget.isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _cardFocusNode.context;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    HomeTraktNowPlayingCard.isScrobbleActive.addListener(_onScrobbleChange);
  }

  @override
  void dispose() {
    HomeTraktNowPlayingCard.isScrobbleActive.removeListener(_onScrobbleChange);
    _cardFocusNode.dispose();
    widget.focusController.unregisterSection(HomeSection.todayCalendar);
    super.dispose();
  }

  void _onScrobbleChange() {
    if (!mounted) return;
    final scrobbleActive = HomeTraktNowPlayingCard.isScrobbleActive.value;
    final visible = !scrobbleActive && _grouped.isNotEmpty;
    final hadFocus = _cardFocusNode.hasFocus;
    setState(() {}); // rebuild to hide/show based on scrobble state
    // Keep focus registration in sync so DPAD navigation skips the card when
    // it's hidden.
    widget.focusController.registerSection(
      HomeSection.todayCalendar,
      hasItems: visible,
      focusNodes: visible ? [_cardFocusNode] : const [],
    );
    if (hadFocus && !visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final next = widget.focusController.getNextSection(
          HomeSection.todayCalendar,
        );
        if (next != null) {
          widget.focusController.focusSection(next);
          return;
        }
        final previous = widget.focusController.getPreviousSection(
          HomeSection.todayCalendar,
        );
        if (previous != null) {
          widget.focusController.focusSection(previous);
        }
      });
    }
  }

  Future<void> _loadData() async {
    final isAuth = await TraktService.instance.isAuthenticated();
    if (!mounted) return;
    if (!isAuth) {
      setState(() {
        _isAuth = false;
        _isLoading = false;
        _grouped = const {};
      });
      widget.focusController.registerSection(
        HomeSection.todayCalendar,
        hasItems: false,
        focusNodes: const [],
      );
      _notifyInitialLoadFinished();
      return;
    }

    setState(() {
      _isAuth = true;
      _isLoading = true;
    });

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 7));
    try {
      final grouped = await TraktCalendarService.instance.getRange(start, end);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _grouped = grouped;
      });

      final scrobbleActive = HomeTraktNowPlayingCard.isScrobbleActive.value;
      final visible = !scrobbleActive && grouped.isNotEmpty;
      widget.focusController.registerSection(
        HomeSection.todayCalendar,
        hasItems: visible,
        focusNodes: visible ? [_cardFocusNode] : const [],
      );
      _notifyInitialLoadFinished();
    } catch (e) {
      debugPrint('HomeTodayCalendarCard: load error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _grouped = const {};
      });
      widget.focusController.registerSection(
        HomeSection.todayCalendar,
        hasItems: false,
        focusNodes: const [],
      );
      _notifyInitialLoadFinished();
    }
  }

  void _notifyInitialLoadFinished() {
    if (_initialLoadSettled) return;
    _initialLoadSettled = true;
    widget.onInitialLoadStateChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_isAuth) return const SizedBox.shrink();

    // Hide entirely when there's an active scrobble — the Now Playing card
    // below is the more urgent thing to see, and stacking two hero cards
    // clutters the top of Home.
    if (HomeTraktNowPlayingCard.isScrobbleActive.value) {
      return const SizedBox.shrink();
    }

    if (_isLoading) {
      return _buildSkeleton();
    }

    final now = DateTime.now();
    final todayBucket = DateTime(now.year, now.month, now.day);
    final todayEntries = _grouped[todayBucket] ?? const [];

    if (todayEntries.isNotEmpty) {
      return HomeSectionReveal(
        child: _buildHeroCard(
          isToday: true,
          featuredDay: todayBucket,
          dayEntries: todayEntries,
        ),
      );
    }

    // Nothing today — find the first non-empty day in the 7-day window
    final sortedKeys = _grouped.keys.toList()..sort();
    final nextKey = sortedKeys.firstWhere(
      (k) => k.isAfter(todayBucket),
      orElse: () => DateTime(0),
    );
    if (nextKey.year == 0) {
      return const SizedBox.shrink();
    }
    return HomeSectionReveal(
      child: _buildHeroCard(
        isToday: false,
        featuredDay: nextKey,
        dayEntries: _grouped[nextKey]!,
      ),
    );
  }

  // ─── Skeleton ───────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: 210,
        decoration: BoxDecoration(
          color: HomeTheme.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _skeletonBar(width: 96, height: 12),
              const SizedBox(height: 10),
              _skeletonBar(width: 200, height: 22),
              const SizedBox(height: 10),
              _skeletonBar(width: 140, height: 12),
              const SizedBox(height: 18),
              _skeletonBar(width: double.infinity, height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skeletonBar({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }

  // ─── Hero card ──────────────────────────────────────────────────────────

  /// Soft accent reserved for the focus ring only.
  static const Color _kFocusAccent = HomeTheme.accent;

  /// Breakpoint above which we render bigger type and a taller card.
  static const double _kWideBreakpoint = 720;

  /// Build the metahub fanart URL for a show. Returns null when imdbId missing.
  static String? _fanartUrlFor(TraktCalendarEntry e) {
    final imdb = e.showImdbId;
    if (imdb == null || !imdb.startsWith('tt')) return null;
    return 'https://images.metahub.space/background/medium/$imdb/img';
  }

  Widget _buildHeroCard({
    required bool isToday,
    required DateTime featuredDay,
    required List<TraktCalendarEntry> dayEntries,
  }) {
    final featured = dayEntries.first;
    final extraOnDay = dayEntries.length - 1;
    final badge = featured.isNewShow
        ? 'NEW SHOW'
        : featured.isSeasonPremiere
        ? 'SEASON PREMIERE'
        : null;
    final fanartUrl = _fanartUrlFor(featured);
    final showColor = _colorForShow(featured.showTitle);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Focus(
        focusNode: _cardFocusNode,
        onFocusChange: _onFocusChange,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (isActivateKey(key) ||
              key == LogicalKeyboardKey.space) {
            _openFullCalendar();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            widget.onRequestFocusAbove();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            widget.onRequestFocusBelow();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (ctx) {
            final hasFocus = Focus.of(ctx).hasFocus;
            return LayoutBuilder(
              builder: (_, constraints) {
                final w = constraints.maxWidth;
                final wide = w >= _kWideBreakpoint;
                // Card height scales with width on phones, capped on tablets
                // and TVs so it never becomes a billboard.
                final height = wide
                    ? 250.0
                    : (w * 0.62).clamp(196.0, 240.0);
                final pad = wide ? 18.0 : 14.0;
                final titleSize = wide ? 27.0 : 21.0;

                return Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: HomeTheme.cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: hasFocus
                          ? _kFocusAccent.withValues(alpha: 0.85)
                          : Colors.white.withValues(alpha: 0.06),
                      width: hasFocus ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 32,
                        offset: const Offset(0, 14),
                      ),
                      if (hasFocus)
                        BoxShadow(
                          color: _kFocusAccent.withValues(alpha: 0.35),
                          blurRadius: 28,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(19),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _openFullCalendar,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Full-bleed fanart (or a show-tinted gradient
                            // fallback when no artwork is available).
                            _background(
                              fanartUrl,
                              featured.posterUrl,
                              showColor,
                            ),
                            // Diagonal scrim — keeps the top-right of the
                            // image readable while anchoring text bottom-left.
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomLeft,
                                  end: Alignment.topRight,
                                  colors: [
                                    Color(0xF0000000),
                                    Color(0x8C000000),
                                    Color(0x1F000000),
                                  ],
                                  stops: [0.0, 0.55, 1.0],
                                ),
                              ),
                            ),
                            // Extra bottom darkening so the timeline + title
                            // stay crisp over busy artwork.
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Color(0xCC000000),
                                    Color(0x00000000),
                                  ],
                                  stops: [0.0, 0.6],
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(pad),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _dateTile(featuredDay),
                                      const Spacer(),
                                      _countdownPill(featured.firstAiredLocal),
                                    ],
                                  ),
                                  const Spacer(),
                                  Row(
                                    children: [
                                      Text(
                                        isToday ? 'AIRING TODAY' : 'UP NEXT',
                                        style: TextStyle(
                                          color: showColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.8,
                                        ),
                                      ),
                                      if (extraOnDay > 0)
                                        Text(
                                          '  ·  +$extraOnDay MORE',
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.45,
                                            ),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: wide ? 6 : 4),
                                  Text(
                                    featured.showTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: titleSize,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                      height: 1.05,
                                    ),
                                  ),
                                  SizedBox(height: wide ? 6 : 4),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'S${featured.seasonNumber.toString().padLeft(2, '0')}'
                                          'E${featured.episodeNumber.toString().padLeft(2, '0')}'
                                          ' · ${_formatTime(featured.firstAiredLocal)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.7,
                                            ),
                                            fontSize: wide ? 13 : 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      if (badge != null) ...[
                                        const SizedBox(width: 8),
                                        _pill(
                                          badge,
                                          accent: const Color(0xFFF59E0B),
                                          dense: true,
                                        ),
                                      ],
                                    ],
                                  ),
                                  SizedBox(height: wide ? 14 : 11),
                                  _buildWeekTimeline(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Full-bleed background image. Falls back to the show poster, and finally
  /// to a show-tinted gradient when no artwork resolves.
  Widget _background(String? fanartUrl, String? posterUrl, Color showColor) {
    final url = fanartUrl ?? posterUrl;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [showColor.withValues(alpha: 0.5), HomeTheme.cardBg],
        ),
      ),
    );
    if (url == null) return fallback;
    return Image.network(
      url,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  /// Compact stacked weekday + day-number tile.
  Widget _dateTile(DateTime day) {
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            weekdays[day.weekday - 1],
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '${day.day}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  /// Pill showing time-until-airing, e.g. "IN 4H 20M" / "TOMORROW".
  Widget _countdownPill(DateTime airTime) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 13,
            color: Colors.white.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 5),
          Text(
            _countdownLabel(airTime),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  String _countdownLabel(DateTime airTime) {
    final now = DateTime.now();
    final diff = airTime.difference(now);
    if (diff.isNegative) return 'AIRED';
    if (diff.inMinutes < 60) return 'IN ${diff.inMinutes}M';
    if (diff.inHours < 24) {
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      return m > 0 ? 'IN ${h}H ${m}M' : 'IN ${h}H';
    }
    final today = DateTime(now.year, now.month, now.day);
    final airDay = DateTime(airTime.year, airTime.month, airTime.day);
    final days = airDay.difference(today).inDays;
    if (days <= 1) return 'TOMORROW';
    return 'IN $days DAYS';
  }

  Widget _pill(
    String text, {
    required Color accent,
    bool muted = false,
    bool dense = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: muted
            ? Colors.white.withValues(alpha: 0.08)
            : accent.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(4),
        border: muted
            ? null
            : Border.all(color: accent.withValues(alpha: 0.45), width: 0.6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: muted ? Colors.white.withValues(alpha: 0.7) : accent,
          fontSize: dense ? 9 : 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  /// 7-day strip rendered as a segmented timeline: each day is a bar that
  /// fills with its show's color when something airs. Today's label is
  /// emphasized so the week reads at a glance.
  Widget _buildWeekTimeline() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Row(
      children: List.generate(7, (i) {
        final day = today.add(Duration(days: i));
        final dayKey = DateTime(day.year, day.month, day.day);
        final entries = _grouped[dayKey] ?? const <TraktCalendarEntry>[];
        final hasEpisodes = entries.isNotEmpty;
        final isTodayCol = i == 0;
        final barColor = hasEpisodes
            ? _colorForShow(entries.first.showTitle)
            : Colors.white.withValues(alpha: 0.12);

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 6 ? 0 : 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: hasEpisodes
                        ? [
                            BoxShadow(
                              color: barColor.withValues(alpha: 0.55),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  initials[day.weekday - 1],
                  style: TextStyle(
                    color: isTodayCol
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                    fontSize: 8.5,
                    fontWeight: isTodayCol
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  Future<void> _openFullCalendar() async {
    final result = await Navigator.of(context).push<TraktCalendarEntry?>(
      MaterialPageRoute(builder: (_) => const TraktCalendarScreen()),
    );
    if (!mounted) return;
    if (result != null) {
      widget.onItemSelected(result);
    }
  }

  String _formatTime(DateTime local) {
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Deterministic palette color based on show title — same color every render.
  static Color _colorForShow(String title) {
    const palette = [
      Color(0xFF8B5CF6), // purple
      Color(0xFF22C55E), // green
      Color(0xFFEF4444), // red
      Color(0xFFF59E0B), // amber
      Color(0xFF3B82F6), // blue
      Color(0xFFEC4899), // pink
      Color(0xFF14B8A6), // teal
      Color(0xFFF97316), // orange
    ];
    int hash = 0;
    for (final c in title.codeUnits) {
      hash = (hash * 31 + c) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }
}

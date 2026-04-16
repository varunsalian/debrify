import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stremio_addon.dart';
import '../models/trakt/trakt_calendar_entry.dart';
import '../screens/trakt_calendar_screen.dart';
import '../services/trakt/trakt_calendar_service.dart';
import '../services/trakt/trakt_service.dart';
import 'home_focus_controller.dart';
import 'home_trakt_now_playing_card.dart';

/// "Today" card at the top of Home showing upcoming Trakt episodes.
///
/// Three visible states:
/// - **Hidden**: Trakt not connected OR nothing airing in the next 7 days
/// - **Loading**: thin skeleton while first fetch is in flight
/// - **Hero**: rich card showing a featured episode (today's first, or the
///   next upcoming if today is empty) plus a 7-day dot strip at the bottom
///   for week-at-a-glance multi-show awareness
class HomeTodayCalendarCard extends StatefulWidget {
  const HomeTodayCalendarCard({
    super.key,
    required this.focusController,
    required this.isTelevision,
    required this.onRequestFocusAbove,
    required this.onRequestFocusBelow,
    required this.onItemSelected,
  });

  final HomeFocusController focusController;
  final bool isTelevision;
  final VoidCallback onRequestFocusAbove;
  final VoidCallback onRequestFocusBelow;
  final void Function(StremioMeta meta) onItemSelected;

  @override
  State<HomeTodayCalendarCard> createState() => _HomeTodayCalendarCardState();
}

class _HomeTodayCalendarCardState extends State<HomeTodayCalendarCard> {
  bool _isAuth = false;
  bool _isLoading = true;
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
    setState(() {}); // rebuild to hide/show based on scrobble state
    // Keep focus registration in sync so DPAD navigation skips the card when
    // it's hidden.
    final scrobbleActive = HomeTraktNowPlayingCard.isScrobbleActive.value;
    final visible = !scrobbleActive && _grouped.isNotEmpty;
    widget.focusController.registerSection(
      HomeSection.todayCalendar,
      hasItems: visible,
      focusNodes: visible ? [_cardFocusNode] : const [],
    );
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
      return;
    }

    setState(() {
      _isAuth = true;
      _isLoading = true;
    });

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 7));
    final grouped = await TraktCalendarService.instance.getRange(start, end);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _grouped = grouped;
    });

    widget.focusController.registerSection(
      HomeSection.todayCalendar,
      hasItems: grouped.isNotEmpty,
      focusNodes: grouped.isNotEmpty ? [_cardFocusNode] : const [],
    );
  }

  @override
  Widget build(BuildContext context) {
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
      return _buildHeroCard(
        isToday: true,
        featuredDay: todayBucket,
        dayEntries: todayEntries,
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
    return _buildHeroCard(
      isToday: false,
      featuredDay: nextKey,
      dayEntries: _grouped[nextKey]!,
    );
  }

  // ─── Skeleton ───────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: SizedBox(
          height: 108,
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  height: 78,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Color(0x22FFFFFF)),
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Color(0x11FFFFFF)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Hero card ──────────────────────────────────────────────────────────

  /// Netflix-style brand red.
  static const Color _kNetflixRed = Color(0xFFE50914);

  /// Deep near-black card background (matches Netflix UI).
  static const Color _kCardBg = Color(0xFF141414);

  /// Breakpoint above which we render bigger poster + bigger type.
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
    final label = isToday
        ? 'TONIGHT'
        : 'UPCOMING · ${_relativeDayLabel(featuredDay).toUpperCase()}';
    final time = _formatTime(featured.firstAiredLocal);
    final badge = featured.isNewShow
        ? 'NEW SHOW'
        : featured.isSeasonPremiere
        ? 'SEASON PREMIERE'
        : null;
    final fanartUrl = _fanartUrlFor(featured);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Focus(
        focusNode: _cardFocusNode,
        onFocusChange: _onFocusChange,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.gameButtonA) {
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
                final wide = constraints.maxWidth >= _kWideBreakpoint;
                return Container(
                  decoration: BoxDecoration(
                    color: _kCardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hasFocus
                          ? _kNetflixRed
                          : Colors.white.withValues(alpha: 0.06),
                      width: hasFocus ? 2 : 1,
                    ),
                    image: fanartUrl != null
                        ? DecorationImage(
                            image: NetworkImage(fanartUrl),
                            fit: BoxFit.cover,
                            alignment: Alignment.centerRight,
                            onError: (_, __) {},
                          )
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _openFullCalendar,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            // Single gradient: Netflix red tint on left,
                            // deep card-bg over the content area, fading to
                            // near-transparent on the right so the fanart
                            // shows through.
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color.alphaBlend(
                                  _kNetflixRed.withValues(alpha: 0.35),
                                  _kCardBg,
                                ),
                                _kCardBg.withValues(alpha: 0.92),
                                _kCardBg.withValues(alpha: 0.55),
                                _kCardBg.withValues(alpha: 0.08),
                              ],
                              stops: const [0.0, 0.3, 0.6, 1.0],
                            ),
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Left accent stripe (Netflix red)
                                Container(width: 4, color: _kNetflixRed),
                                const SizedBox(width: 12),
                                // Poster
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: wide ? 16 : 14,
                                  ),
                                  child: _poster(featured, big: wide),
                                ),
                                const SizedBox(width: 14),
                                // Featured text column. On wide screens it's
                                // capped so the rest of the row becomes reveal
                                // space for the fanart background. On narrow
                                // it flexes to fill available width.
                                if (wide)
                                  SizedBox(
                                    width: 320,
                                    child: _buildFeaturedColumn(
                                      label: label,
                                      extraOnDay: extraOnDay,
                                      featured: featured,
                                      time: time,
                                      badge: badge,
                                      wide: wide,
                                    ),
                                  )
                                else
                                  Expanded(
                                    child: _buildFeaturedColumn(
                                      label: label,
                                      extraOnDay: extraOnDay,
                                      featured: featured,
                                      time: time,
                                      badge: badge,
                                      wide: wide,
                                    ),
                                  ),
                                // Wide screens only: Spacer eats remaining
                                // horizontal space so fanart shows through.
                                if (wide) const Spacer(),
                                // Chevron on far right
                                Padding(
                                  padding: const EdgeInsets.only(
                                    right: 12,
                                    left: 6,
                                  ),
                                  child: Icon(
                                    Icons.chevron_right,
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
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

  Widget _buildFeaturedColumn({
    required String label,
    required int extraOnDay,
    required TraktCalendarEntry featured,
    required String time,
    required String? badge,
    required bool wide,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: wide ? 14 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Label row
          Row(
            children: [
              Flexible(child: _pill(label, accent: _kNetflixRed)),
              if (extraOnDay > 0) ...[
                const SizedBox(width: 6),
                _pill(
                  '+$extraOnDay MORE',
                  accent: Colors.white.withValues(alpha: 0.6),
                  muted: true,
                ),
              ],
            ],
          ),
          SizedBox(height: wide ? 8 : 6),
          // Show title
          Text(
            featured.showTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: wide ? 18 : 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          SizedBox(height: wide ? 4 : 2),
          // Episode line
          Row(
            children: [
              Flexible(
                child: Text(
                  'S${featured.seasonNumber.toString().padLeft(2, '0')}E${featured.episodeNumber.toString().padLeft(2, '0')} · $time',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: wide ? 13 : 12,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                _pill(badge, accent: const Color(0xFFF59E0B), dense: true),
              ],
            ],
          ),
          const Spacer(),
          // Week-at-a-glance dots
          _buildWeekDots(),
        ],
      ),
    );
  }

  Widget _poster(TraktCalendarEntry e, {bool big = false}) {
    final w = big ? 72.0 : 52.0;
    final h = big ? 108.0 : 78.0;
    final placeholder = Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.tv_rounded, size: big ? 28 : 20, color: Colors.white30),
    );
    if (e.posterUrl == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        e.posterUrl!,
        width: w,
        height: h,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }

  Widget _pill(
    String text, {
    required Color accent,
    bool muted = false,
    bool dense = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 5 : 6,
        vertical: dense ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: muted
            ? Colors.white.withValues(alpha: 0.08)
            : accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: muted ? Colors.white.withValues(alpha: 0.7) : accent,
          fontSize: dense ? 8 : 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildWeekDots() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(7, (i) {
        final day = today.add(Duration(days: i));
        final dayKey = DateTime(day.year, day.month, day.day);
        final entries = _grouped[dayKey] ?? const <TraktCalendarEntry>[];
        final hasEpisodes = entries.isNotEmpty;
        final isTodayDot = i == 0;

        return Padding(
          padding: const EdgeInsets.only(right: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                weekdayInitials[day.weekday - 1],
                style: TextStyle(
                  color: isTodayDot
                      ? Colors.white.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.35),
                  fontSize: 8,
                  fontWeight: isTodayDot ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: hasEpisodes
                      ? _colorForShow(entries.first.showTitle)
                      : Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: isTodayDot
                      ? Border.all(
                          color: Colors.white.withValues(alpha: 0.6),
                          width: 1,
                        )
                      : null,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────

  Future<void> _openFullCalendar() async {
    final result = await Navigator.of(context).push<StremioMeta?>(
      MaterialPageRoute(builder: (_) => const TraktCalendarScreen()),
    );
    if (!mounted) return;
    if (result != null) {
      widget.onItemSelected(result);
    }
  }

  String _relativeDayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = d.difference(today).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'tomorrow';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[d.weekday - 1];
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

// The sports board: hero, header, sport chips, day sections and live channels.
//
// Presentation layer. [SportsBoardView] owns exactly one board session —
// captured profile owner plus a private view identity — created once in
// [initState], so two routes showing the same league never share board state.
// It starts the first load after the first frame, watches
// [sportsBoardProvider] for that session, and derives the hero, the When
// counts, the sport chips and the day sections from the published state with
// the pure application functions. The chosen sport chip is local view state.
// Every action (When, Following, Scores, refresh, follow from the details
// panel) is handed to the controller; the league picker writes through its own
// notifier; every play intent leaves through [onPlay].
import 'dart:async';

import 'package:debrify/features/sports/application/sports_board_controller.dart';
import 'package:debrify/features/sports/application/sports_board_sections.dart';
import 'package:debrify/features/sports/application/sports_board_sports.dart';
import 'package:debrify/features/sports/application/sports_league_filter_notifier.dart';
import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/models/sports_league_filter.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sports_board_header.dart';
import 'sports_board_hero.dart';
import 'sports_board_rows.dart';
import 'sports_event_details.dart';
import 'sports_league_sheet.dart';
import 'sports_sport_chips.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;

/// At least this wide and the hero makes room for its preview panel.
const _heroWideMinWidth = 900.0;

/// The board's own copy of the empty-view sentence; the fixture rows are the
/// only thing on screen, and there is nothing to row.
const _noFixturesCopy = 'No fixtures in this view.';

class SportsBoardView extends ConsumerStatefulWidget {
  const SportsBoardView({super.key, required this.onPlay});

  /// Plays a channel the user picked — on the board or in the details panel.
  final void Function(SportsChannelRef channel) onPlay;

  @override
  ConsumerState<SportsBoardView> createState() => _SportsBoardViewState();
}

class _SportsBoardViewState extends ConsumerState<SportsBoardView>
    with WidgetsBindingObserver {
  /// Captured once: the profile session and view identity this board owns.
  late final SportsSession _session;

  /// The sport chip; null is All. Kept while the board is mounted and ignored
  /// (All shows) whenever the current view has no fixture of that sport.
  SportKind? _sport;

  @override
  void initState() {
    super.initState();
    _session = captureSportsSession();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(sportsBoardProvider(_session).notifier);
      // Timed refreshes wait while the player covers the board or the app
      // is in the background, so polling never competes with the stream.
      controller.canPoll = () =>
          mounted && _foreground && (ModalRoute.of(context)?.isCurrent ?? true);
      controller.refresh();
    });
  }

  bool _foreground = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  SportsBoardController get _controller =>
      ref.read(sportsBoardProvider(_session).notifier);

  void _openDetails(SportsEvent event) {
    final state = ref.read(sportsBoardProvider(_session));
    showSportsEventDetails(
      context,
      event: event,
      watch: state.watchFor(event),
      follows: state.follows,
      onPlay: widget.onPlay,
      onToggleTeam: (teamKey) => _controller.toggleTeam(teamKey),
      onToggleLeague: (leagueId) => _controller.toggleLeague(leagueId),
    );
  }

  /// The picker writes the league choices itself; a changed choice reloads
  /// the board once it closes, so newly enabled leagues are fetched.
  Future<void> _openLeagues() async {
    final before = ref.read(sportsLeagueFilterProvider).value;
    await showSportsLeagueSheet(context);
    if (!mounted) return;
    if (ref.read(sportsLeagueFilterProvider).value != before) {
      unawaited(_controller.refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sportsBoardProvider(_session));
    // Until the choices load (or when they cannot), every league shows.
    final leagues =
        ref.watch(sportsLeagueFilterProvider).value ??
        const SportsLeagueFilter();
    final events = _shownLeagues(state.events, leagues);
    final now = state.updatedAt ?? ref.watch(sportsClockProvider)();
    final hero = pickSportsHero(events, state.follows, now);
    final sections = buildSportsBoardSections(
      events: events,
      follows: state.follows,
      now: now,
      filter: state.filter,
      followingOnly: state.followingOnly,
    );
    final counts = sportsBoardFilterCounts(
      events: events,
      follows: state.follows,
      now: now,
      followingOnly: state.followingOnly,
    );
    final sports = sportsBoardSportCounts(sections);
    final sport = sports.any((entry) => entry.sport == _sport) ? _sport : null;
    final shown = sportsBoardSectionsForSport(sections, sport);
    // A touch device starts with nothing focused; a remote or a keyboard
    // needs a live target the moment the board appears.
    final focusOnMount = PlatformUtil.isTelevision || PlatformUtil.isDesktop;

    return ColoredBox(
      color: _tokens.bg,
      child: LayoutBuilder(
        builder: (context, constraints) => CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              sliver: SliverMainAxisGroup(
                slivers: [
                  if (hero != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 22),
                        child: SportsBoardHero(
                          event: hero,
                          watch: state.watchFor(hero),
                          hideScores: state.follows.hideScores,
                          wide: constraints.maxWidth >= _heroWideMinWidth,
                          onPlay: widget.onPlay,
                          onDetails: () => _openDetails(hero),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: SportsBoardHeader(
                      updatedAt: state.updatedAt,
                      filter: state.filter,
                      counts: counts,
                      followingOnly: state.followingOnly,
                      hideScores: state.follows.hideScores,
                      onSelectFilter: (filter) => _controller.setFilter(filter),
                      onToggleFollowing: () =>
                          _controller.setFollowingOnly(!state.followingOnly),
                      onToggleScores: () =>
                          _controller.setHideScores(!state.follows.hideScores),
                      onOpenLeagues: () => unawaited(_openLeagues()),
                      onRefresh: () => _controller.refresh(force: true),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 14)),
                  if (sections.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: SportsSportChips(
                        total: sportsBoardEventCount(sections),
                        sports: sports,
                        selected: sport,
                        onSelect: (picked) => setState(() => _sport = picked),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                  ..._body(state, shown, now, focusOnMount),
                  if (state.liveSportsListings.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: SportsBoardLiveChannelsRow(
                          listings: state.liveSportsListings,
                          now: now,
                          onPlay: widget.onPlay,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(
    SportsBoardState state,
    List<SportsBoardSection> sections,
    DateTime now,
    bool focusOnMount,
  ) {
    if (state.loading && state.events.isEmpty) {
      return const [SliverToBoxAdapter(child: SportsBoardSkeletonRows())];
    }
    if (state.error != null && state.events.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _SportsBoardError(
            message: state.error!,
            onRetry: () => _controller.refresh(force: true),
          ),
        ),
      ];
    }
    if (sections.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: sportsLabelText(_noFixturesCopy, _tokens.fgDim, size: 13.5),
          ),
        ),
      ];
    }
    return [
      for (final (index, section) in sections.indexed) ...[
        SportsBoardSectionSliver(
          key: ValueKey('sports-section-${section.id}'),
          section: section,
          hideScores: state.follows.hideScores,
          isFollowed: state.follows.followsEvent,
          watchFor: state.watchFor,
          onCardPressed: _openDetails,
          autofocusFirst: focusOnMount && index == 0,
          now: now,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
      ],
    ];
  }
}

/// Fixtures of leagues the picker leaves on; a league outside the catalog
/// has no switch and always shows.
List<SportsEvent> _shownLeagues(
  List<SportsEvent> events,
  SportsLeagueFilter filter,
) => [
  for (final event in events)
    if (_leagueShown(event.leagueId, filter)) event,
];

bool _leagueShown(String leagueId, SportsLeagueFilter filter) {
  final league = sportsLeagueById(leagueId);
  return league == null || filter.isEnabled(league);
}

/// Whole-board failure: the sentence the controller chose, plus a retry.
class _SportsBoardError extends StatelessWidget {
  const _SportsBoardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sportsLabelText(
          message,
          _tokens.fgMid,
          size: 13.5,
          height: 1.4,
          maxLines: 3,
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: 160,
          child: SportsFocusPill.row(
            key: const ValueKey('sports-retry'),
            label: 'Try again',
            onPressed: onRetry,
            builder: (_, ink, _) => Center(
              child: sportsLabelText('Try again', ink, weight: FontWeight.w700),
            ),
          ),
        ),
      ],
    ),
  );
}

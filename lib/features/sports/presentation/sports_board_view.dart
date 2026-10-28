// The sports board: hero, filters, fixture rows and live channels.
//
// Presentation layer. [SportsBoardView] owns exactly one board session —
// captured profile owner plus a private view identity — created once in
// [initState], so two routes showing the same league never share board state.
// It starts the first load after the first frame, watches
// [sportsBoardProvider] for that session, and derives the hero and the
// sections from the published state with the pure application functions.
// Every action (filter, score toggle, refresh, follow from the details panel)
// is delegated to the controller; every play intent leaves through [onPlay].
import 'package:debrify/features/sports/application/sports_board_controller.dart';
import 'package:debrify/features/sports/application/sports_board_sections.dart';
import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sports_board_rows.dart';
import 'sports_event_card.dart';
import 'sports_event_details.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;

/// At least this wide and the hero makes room for its preview panel.
const _heroWideMinWidth = 900.0;
const _heroPreviewFlex = 13;
const _heroInfoFlex = 10;

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

class _SportsBoardViewState extends ConsumerState<SportsBoardView> {
  /// Captured once: the profile session and view identity this board owns.
  late final SportsSession _session;

  @override
  void initState() {
    super.initState();
    _session = captureSportsSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(sportsBoardProvider(_session).notifier).refresh();
    });
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sportsBoardProvider(_session));
    final now = state.updatedAt ?? ref.watch(sportsClockProvider)();
    final hero = pickSportsHero(state.events, state.follows, now);
    final sections = buildSportsBoardSections(
      events: state.events,
      follows: state.follows,
      now: now,
      filter: state.filter,
    );
    final liveCount = state.events
        .where((event) => event.status == SportsEventStatus.live)
        .length;
    // A touch device starts with nothing focused; a remote or a keyboard
    // needs a live target the moment the board appears.
    final focusOnMount = PlatformUtil.isTelevision || PlatformUtil.isDesktop;

    return LayoutBuilder(
      builder: (context, constraints) => ColoredBox(
        color: _tokens.bg,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          children: [
            if (hero != null) ...[
              _SportsBoardHero(
                event: hero,
                watch: state.watchFor(hero),
                hideScores: state.follows.hideScores,
                wide: constraints.maxWidth >= _heroWideMinWidth,
                onPlay: widget.onPlay,
                onDetails: () => _openDetails(hero),
              ),
              const SizedBox(height: 22),
            ],
            SportsBoardControlsRow(
              filter: state.filter,
              liveCount: liveCount,
              hideScores: state.follows.hideScores,
              onSelectFilter: (filter) => _controller.setFilter(filter),
              onToggleScores: () =>
                  _controller.setHideScores(!state.follows.hideScores),
              onRefresh: () => _controller.refresh(force: true),
            ),
            const SizedBox(height: 18),
            if (state.loading && state.events.isEmpty)
              const SportsBoardSkeletonRows()
            else if (state.error != null && state.events.isEmpty)
              _SportsBoardError(
                message: state.error!,
                onRetry: () => _controller.refresh(force: true),
              )
            else if (sections.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: sportsLabelText(
                  _noFixturesCopy,
                  _tokens.fgDim,
                  size: 13.5,
                ),
              )
            else
              for (final (index, section) in sections.indexed) ...[
                SportsBoardSectionRow(
                  key: ValueKey('sports-section-${section.id}'),
                  section: section,
                  hideScores: state.follows.hideScores,
                  viewportWidth: constraints.maxWidth,
                  isFollowed: state.follows.followsEvent,
                  watchFor: state.watchFor,
                  onCardPressed: _openDetails,
                  autofocusFirst: focusOnMount && index == 0,
                ),
                const SizedBox(height: 18),
              ],
            if (state.liveSportsListings.isNotEmpty) ...[
              const SizedBox(height: 4),
              SportsBoardLiveChannelsRow(
                listings: state.liveSportsListings,
                now: now,
                onPlay: widget.onPlay,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The featured fixture: eyebrow, both teams at hero scale, live progress and
/// the two ways to act on it.
class _SportsBoardHero extends StatelessWidget {
  const _SportsBoardHero({
    required this.event,
    required this.watch,
    required this.hideScores,
    required this.wide,
    required this.onPlay,
    required this.onDetails,
  });

  final SportsEvent event;
  final SportsWatchOptions watch;
  final bool hideScores;

  /// Wide boards pair the info with a preview panel; narrow ones skip it.
  final bool wide;
  final void Function(SportsChannelRef channel) onPlay;
  final VoidCallback onDetails;

  SportsLeague? get _league => sportsLeagueById(event.leagueId);

  SportsWatchOption? get _firstGuide =>
      watch.guide.isEmpty ? null : watch.guide.first;

  /// Minutes of a live soccer clock over 90; anything unparseable hides the
  /// bar rather than guessing a position.
  double? get _progress {
    if (event.status != SportsEventStatus.live) return null;
    if (_league?.sport != SportKind.soccer) return null;
    final minutes = int.tryParse(
      RegExp(r'^(\d+)').firstMatch(event.clock?.trim() ?? '')?.group(1) ?? '',
    );
    if (minutes == null) return null;
    return (minutes / 90).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _tokens.panel,
      borderRadius: BorderRadius.circular(18),
    ),
    child: wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: _heroInfoFlex, child: _info()),
              const SizedBox(width: 16),
              Expanded(flex: _heroPreviewFlex, child: _preview()),
            ],
          )
        : _info(),
  );

  Widget _info() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      sportsLabelText(
        '${_league?.name ?? event.leagueId} · '
        '${sportsEventStatusText(event)}',
        _tokens.accent,
        size: 11,
        weight: FontWeight.w700,
        tracking: 0.8,
        ellipsize: true,
      ),
      const SizedBox(height: 14),
      if (event.isTeamEvent) _matchup() else _titleBlock(),
      if (_progress case final progress?) ...[
        const SizedBox(height: 12),
        _progressBar(progress),
      ],
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_firstGuide case final option?)
            SportsFocusPill.row(
              key: const ValueKey('sports-hero-play'),
              label: 'Watch on ${option.channel.name}',
              onPressed: () => onPlay(option.channel),
              builder: (_, ink, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded, size: 16, color: ink),
                  const SizedBox(width: 6),
                  Flexible(
                    child: sportsLabelText(
                      'Watch on '
                      '${sportsChannelDisplayName(option.channel.name)}',
                      ink,
                      weight: FontWeight.w700,
                      ellipsize: true,
                    ),
                  ),
                ],
              ),
            ),
          SportsFocusPill.row(
            key: const ValueKey('sports-hero-details'),
            label: 'Where to watch · ${watch.count}',
            onPressed: onDetails,
            builder: (_, ink, _) => sportsLabelText(
              'Where to watch · ${watch.count}',
              ink,
              weight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _matchup() => Row(
    children: [
      SportsTeamCrest(team: event.home!, size: 52),
      const SizedBox(width: 12),
      Expanded(
        child: sportsLabelText(
          event.home!.name,
          _tokens.fg,
          size: 16,
          weight: FontWeight.w700,
          ellipsize: true,
        ),
      ),
      const SizedBox(width: 12),
      _score(),
      const SizedBox(width: 12),
      Expanded(
        child: sportsLabelText(
          event.away!.name,
          _tokens.fg,
          size: 16,
          weight: FontWeight.w700,
          ellipsize: true,
        ),
      ),
      const SizedBox(width: 12),
      SportsTeamCrest(team: event.away!, size: 52),
    ],
  );

  Widget _score() {
    final home = event.homeScore;
    final away = event.awayScore;
    if (home == null || away == null) {
      return sportsLabelText(
        sportsMatchupConnector(_league?.sport),
        _tokens.fgFaint,
        size: 22,
        weight: FontWeight.w700,
      );
    }
    if (hideScores) {
      return sportsLabelText(
        hiddenScoresGlyph,
        _tokens.fgFaint,
        size: 22,
        tracking: 1,
      );
    }
    return sportsLabelText(
      '$home – $away',
      _tokens.fg,
      size: 30,
      weight: FontWeight.w700,
      tabular: true,
    );
  }

  Widget _titleBlock() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      sportsLabelText(
        event.displayTitle,
        _tokens.fg,
        size: 22,
        weight: FontWeight.w700,
        height: 1.2,
        maxLines: 2,
        ellipsize: true,
      ),
      if ((event.subtitle ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: sportsLabelText(
            event.subtitle!,
            _tokens.fgDim,
            size: 12.5,
            ellipsize: true,
          ),
        ),
    ],
  );

  Widget _progressBar(double progress) => ClipRRect(
    key: const ValueKey('sports-hero-progress'),
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(
      height: 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: _tokens.hairline2),
          FractionallySizedBox(
            widthFactor: progress,
            child: ColoredBox(color: _tokens.accent),
          ),
        ],
      ),
    ),
  );

  /// v1 has no live video here; the panel says which channel would carry it.
  Widget _preview() => AspectRatio(
    key: const ValueKey('sports-hero-preview'),
    aspectRatio: 16 / 9,
    child: Container(
      decoration: BoxDecoration(
        color: _tokens.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _tokens.hairline),
      ),
      alignment: Alignment.center,
      child: sportsLabelText(
        _firstGuide == null
            ? 'No channel in your guide'
            : sportsChannelDisplayName(_firstGuide!.channel.name),
        _tokens.fgFaint,
        size: 13,
        weight: FontWeight.w600,
        ellipsize: true,
      ),
    ),
  );
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

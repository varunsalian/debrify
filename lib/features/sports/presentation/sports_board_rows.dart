// The sports board's repeating rows: the filter controls, one fixture
// section, the live-channels strip and the loading skeletons.
//
// Presentation layer. Each row renders state handed to it and reports one
// intent upward — the board view owns the controller, the navigation and the
// play callback. Everything paints with the Spotlight tokens and every
// control is a [SportsFocusPill], so the D-pad contract is identical to the
// card and the details panel.
import 'package:debrify/features/sports/application/sports_board_sections.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'sports_event_card.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;

/// Height of a fixture row: the card's own content height plus room for its
/// focus scale and glow.
const sectionRowHeight = 158.0;

/// Below this board width a card takes 78 % of the visible width instead of
/// its fixed rail width, so a phone still shows "one card and a hint".
const _narrowBoardWidth = 640.0;
const _cardWidthFixed = 236.0;
const _channelTileWidth = 300.0;
const _channelTileHeight = 116.0;

final _boardTimeFormat = DateFormat('HH:mm');

/// The row heading every board section shares: uppercase 11 px title and,
/// when given, the number of fixtures in the row.
Widget sportsBoardSectionTitle(String title, {int? count}) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Row(
    children: [
      sportsLabelText(
        title.toUpperCase(),
        _tokens.fgDim,
        size: 11,
        weight: FontWeight.w700,
        tracking: 0.8,
      ),
      if (count != null) ...[
        const SizedBox(width: 6),
        sportsLabelText(
          '$count',
          _tokens.fgFaint,
          size: 11,
          weight: FontWeight.w700,
          tabular: true,
        ),
      ],
    ],
  ),
);

/// The board's filter segments plus the two board-wide actions.
class SportsBoardControlsRow extends StatelessWidget {
  const SportsBoardControlsRow({
    super.key,
    required this.filter,
    required this.liveCount,
    required this.hideScores,
    required this.onSelectFilter,
    required this.onToggleScores,
    required this.onRefresh,
  });

  final SportsBoardFilter filter;

  /// Shown inside the `Live` segment so the count follows the loaded board.
  final int liveCount;

  final bool hideScores;
  final void Function(SportsBoardFilter filter) onSelectFilter;
  final VoidCallback onToggleScores;
  final VoidCallback onRefresh;

  String _segmentLabel(SportsBoardFilter value) => switch (value) {
    SportsBoardFilter.live => 'Live $liveCount',
    SportsBoardFilter.today => 'Today',
    SportsBoardFilter.week => 'This week',
    SportsBoardFilter.following => 'Following',
  };

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final value in SportsBoardFilter.values)
        _segment(
          key: ValueKey('sports-filter-${value.name}'),
          label: _segmentLabel(value),
          selected: value == filter,
          onPressed: () => onSelectFilter(value),
        ),
      _segment(
        key: const ValueKey('sports-toggle-scores'),
        label: hideScores ? 'Scores hidden' : 'Scores shown',
        selected: hideScores,
        onPressed: onToggleScores,
      ),
      _segment(
        key: const ValueKey('sports-refresh'),
        label: 'Refresh',
        selected: false,
        onPressed: onRefresh,
      ),
    ],
  );

  Widget _segment({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) => SportsFocusPill.row(
    key: key,
    label: label,
    selected: selected,
    outlined: false,
    onPressed: onPressed,
    builder: (_, ink, _) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: sportsLabelText(
        label,
        ink,
        weight: FontWeight.w700,
        ellipsize: true,
      ),
    ),
  );
}

/// One titled section: heading plus a horizontal rail of fixture cards.
///
/// The rail is its own [FocusTraversalGroup] so left/right stays inside the
/// row while up/down crosses rows through the default directional policy.
class SportsBoardSectionRow extends StatelessWidget {
  const SportsBoardSectionRow({
    super.key,
    required this.section,
    required this.hideScores,
    required this.viewportWidth,
    required this.isFollowed,
    required this.watchFor,
    required this.onCardPressed,
    this.autofocusFirst = false,
  });

  final SportsBoardSection section;
  final bool hideScores;

  /// Board width, so the narrow rule can size a card as 78 % of it.
  final double viewportWidth;

  final bool Function(SportsEvent event) isFollowed;
  final SportsWatchOptions Function(SportsEvent event) watchFor;
  final void Function(SportsEvent event) onCardPressed;

  /// Only the first card of the first section may claim focus on mount.
  final bool autofocusFirst;

  double get _cardWidth => viewportWidth < _narrowBoardWidth
      ? viewportWidth * 0.78
      : _cardWidthFixed;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      sportsBoardSectionTitle(section.title, count: section.events.length),
      SizedBox(
        height: sectionRowHeight,
        child: FocusTraversalGroup(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: section.events.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, index) {
              final event = section.events[index];
              return SportsEventCard(
                key: ValueKey('sports-card-${event.leagueId}-${event.id}'),
                event: event,
                hideScores: hideScores,
                followed: isFollowed(event),
                watch: watchFor(event),
                onPressed: () => onCardPressed(event),
                autofocus: autofocusFirst && index == 0,
                width: _cardWidth,
              );
            },
          ),
        ),
      ),
    ],
  );
}

/// "Live sports channels": what is airing right now on the user's own guide.
class SportsBoardLiveChannelsRow extends StatelessWidget {
  const SportsBoardLiveChannelsRow({
    super.key,
    required this.listings,
    required this.now,
    required this.onPlay,
  });

  final List<SportsGuideListing> listings;

  /// Local "now", used for the time range and the NOW progress.
  final DateTime now;

  final void Function(SportsChannelRef channel) onPlay;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      sportsBoardSectionTitle('Live sports channels'),
      SizedBox(
        height: _channelTileHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: listings.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, index) => _tile(listings[index]),
        ),
      ),
    ],
  );

  Widget _tile(SportsGuideListing listing) {
    final channel = listing.channel;
    final range = _range(listing);
    return SizedBox(
      width: _channelTileWidth,
      child: SportsFocusPill.row(
        key: ValueKey('sports-live-channel-${channel.url}'),
        label: '${channel.name}, ${listing.title}, $range, now',
        height: _channelTileHeight,
        padding: const EdgeInsets.all(14),
        onPressed: () => onPlay(channel),
        builder: (_, ink, subtle) => Row(
          children: [
            SportsChannelLogo(name: channel.name, logoUrl: channel.logoUrl),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sportsLabelText(
                    sportsChannelDisplayName(channel.name),
                    ink,
                    size: 13.5,
                    weight: FontWeight.w700,
                    ellipsize: true,
                  ),
                  const SizedBox(height: 3),
                  sportsLabelText(
                    listing.title,
                    subtle,
                    size: 11.5,
                    ellipsize: true,
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      sportsLabelText(
                        'NOW',
                        _tokens.live,
                        size: 10,
                        weight: FontWeight.w700,
                        tracking: 0.6,
                      ),
                      const SizedBox(width: 6),
                      sportsLabelText(range, subtle, size: 11, tabular: true),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _nowProgress(listing),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nowProgress(SportsGuideListing listing) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(
      height: 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: _tokens.hairline2),
          FractionallySizedBox(
            widthFactor: _progressOf(listing),
            child: ColoredBox(color: _tokens.accent),
          ),
        ],
      ),
    ),
  );

  double _progressOf(SportsGuideListing listing) {
    final total = listing.stop.difference(listing.start);
    if (total <= Duration.zero) return 0;
    final done = now.toUtc().difference(listing.start);
    return (done.inSeconds / total.inSeconds).clamp(0.0, 1.0);
  }

  String _range(SportsGuideListing listing) =>
      '${_boardTimeFormat.format(listing.start.toLocal())}–'
      '${_boardTimeFormat.format(listing.stop.toLocal())}';
}

/// Three placeholder rows while the first refresh is in flight.
class SportsBoardSkeletonRows extends StatelessWidget {
  const SportsBoardSkeletonRows({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final row in const [0, 1, 2]) ...[
        _row(row),
        const SizedBox(height: 18),
      ],
    ],
  );

  Widget _row(int index) => Column(
    key: ValueKey('sports-board-skeleton-$index'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 96,
        height: 11,
        decoration: BoxDecoration(
          color: _tokens.hairline,
          borderRadius: BorderRadius.circular(5),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: sectionRowHeight,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          children: const [
            _SkeletonCard(),
            SizedBox(width: 12),
            _SkeletonCard(),
            SizedBox(width: 12),
            _SkeletonCard(),
          ],
        ),
      ),
    ],
  );
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) => Container(
    width: _cardWidthFixed,
    height: sectionRowHeight - 14,
    decoration: BoxDecoration(
      color: _tokens.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _tokens.hairline),
    ),
  );
}

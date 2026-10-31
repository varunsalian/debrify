// The sports board's repeating parts: a day section (heading plus a grid of
// fixture cards), the live-channels strip and the loading skeletons.
//
// Presentation layer. Each part renders state handed to it and reports one
// intent upward — the board view owns the controller, the navigation and the
// play callback. Everything paints with the Spotlight tokens and every
// control is a [SportsFocusPill], so the D-pad contract is identical to the
// card and the details panel.
import 'dart:math' as math;
import 'dart:ui' as ui show TextDirection;

import 'package:debrify/features/sports/application/sports_board_sections.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import 'sports_event_card.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;

/// Cards fill columns of at least this width, like CSS
/// `repeat(auto-fill, minmax(258px, 1fr))`, so a lone fixture takes one cell
/// instead of leaving a row of empty rail behind it.
const _cardMinWidth = 258.0;
const _gridGap = 12.0;
const _channelTileWidth = 300.0;
const _channelTileHeight = 116.0;

final _boardTimeFormat = DateFormat('HH:mm');

/// The heading every board section shares: an uppercase title, the number of
/// fixtures when given, and a hairline running to the edge. The live section
/// reads in the live red.
Widget sportsBoardSectionTitle(String title, {int? count, bool live = false}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          sportsLabelText(
            title.toUpperCase(),
            live ? _tokens.rec : _tokens.fgDim,
            size: 11.5,
            weight: FontWeight.w800,
            tracking: 1.4,
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            sportsLabelText(
              '$count',
              live ? _tokens.rec.withValues(alpha: 0.7) : _tokens.fgFaint,
              size: 11.5,
              weight: FontWeight.w700,
              tabular: true,
            ),
          ],
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: _tokens.hairline)),
        ],
      ),
    );

/// One titled section as slivers: its heading, then its cards in a grid.
///
/// Directional traversal moves across and down the grid geometrically; a
/// focused card scrolls itself into view, which builds the next grid row.
class SportsBoardSectionSliver extends StatelessWidget {
  const SportsBoardSectionSliver({
    super.key,
    required this.section,
    required this.hideScores,
    required this.isFollowed,
    required this.watchFor,
    required this.onCardPressed,
    this.autofocusFirst = false,
    this.checkingChannels = false,
    this.now,
  });

  final SportsBoardSection section;

  /// The board's "now", handed to every card's kick-off label.
  final DateTime? now;
  final bool hideScores;
  final bool Function(SportsEvent event) isFollowed;
  final SportsWatchOptions Function(SportsEvent event) watchFor;
  final void Function(SportsEvent event) onCardPressed;

  /// Only the first card of the first section may claim focus on mount.
  final bool autofocusFirst;

  /// The guide has not answered yet (see SportsEventCard.checking).
  final bool checkingChannels;

  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
    slivers: [
      SliverToBoxAdapter(
        child: sportsBoardSectionTitle(
          section.title,
          count: section.events.length,
          live: section.id == 'live',
        ),
      ),
      SliverGrid.builder(
        gridDelegate: SportsAutoFillGridDelegate(
          minTileWidth: _cardMinWidth,
          spacing: _gridGap,
          tileHeight: sportsEventCardHeight(context),
        ),
        itemCount: section.events.length,
        itemBuilder: (_, index) {
          final event = section.events[index];
          return SportsEventCard(
            key: ValueKey('sports-card-${event.leagueId}-${event.id}'),
            event: event,
            hideScores: hideScores,
            followed: isFollowed(event),
            watch: watchFor(event),
            checking: checkingChannels,
            onPressed: () => onCardPressed(event),
            autofocus: autofocusFirst && index == 0,
            now: now,
          );
        },
      ),
    ],
  );
}

/// As many equal columns of at least [minTileWidth] as fit, each
/// [tileHeight] tall.
class SportsAutoFillGridDelegate extends SliverGridDelegate {
  const SportsAutoFillGridDelegate({
    required this.minTileWidth,
    required this.spacing,
    required this.tileHeight,
  });

  final double minTileWidth;
  final double spacing;
  final double tileHeight;

  /// Columns that fit in [width].
  static int columnsFor(double width, double minTileWidth, double spacing) =>
      math.max(1, ((width + spacing) / (minTileWidth + spacing)).floor());

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width = constraints.crossAxisExtent;
    final columns = columnsFor(width, minTileWidth, spacing);
    final tileWidth = math.max(
      0.0,
      (width - spacing * (columns - 1)) / columns,
    );
    return SliverGridRegularTileLayout(
      crossAxisCount: columns,
      mainAxisStride: tileHeight + spacing,
      crossAxisStride: tileWidth + spacing,
      childMainAxisExtent: tileHeight,
      childCrossAxisExtent: tileWidth,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(SportsAutoFillGridDelegate oldDelegate) =>
      oldDelegate.minTileWidth != minTileWidth ||
      oldDelegate.spacing != spacing ||
      oldDelegate.tileHeight != tileHeight;
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

/// Three placeholder sections while the first refresh is in flight.
/// Three placeholder sections, in the board's own shapes (a sport chip row,
/// a heading, card plates with their header and footer bands), with a soft
/// sheen moving across so the wait reads as loading, not as a blank board.
class SportsBoardSkeletonRows extends StatefulWidget {
  const SportsBoardSkeletonRows({super.key});

  @override
  State<SportsBoardSkeletonRows> createState() =>
      _SportsBoardSkeletonRowsState();
}

class _SportsBoardSkeletonRowsState extends State<SportsBoardSkeletonRows>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = sportsEventCardHeight(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = SportsAutoFillGridDelegate.columnsFor(
          constraints.maxWidth,
          _cardMinWidth,
          _gridGap,
        );
        return AnimatedBuilder(
          animation: _sheen,
          builder: (context, child) => ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              // A narrow highlight sweeping left to right over the plates.
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.08),
                Colors.transparent,
              ],
              stops: const [0.35, 0.5, 0.65],
              transform: _SheenSlide(_sheen.value),
            ).createShader(bounds),
            child: child,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _chipRow(),
              const SizedBox(height: 16),
              for (final row in const [0, 1, 2]) ...[
                _row(row, math.min(columns, 3), height),
                const SizedBox(height: 18),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _plate(double width, double height, {double radius = 5}) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: _tokens.hairline,
      borderRadius: BorderRadius.circular(radius),
    ),
  );

  /// Clipped, not scrolled: a narrow board shows as many chips as fit.
  Widget _chipRow() => SizedBox(
    height: 32,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        maxWidth: double.infinity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final width in const [72.0, 104.0, 92.0, 128.0]) ...[
              _plate(width, 32, radius: 16),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _row(int index, int cards, double height) => Column(
    key: ValueKey('sports-board-skeleton-$index'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _plate(96, 11),
      const SizedBox(height: 10),
      Row(
        children: [
          for (var card = 0; card < cards; card++) ...[
            if (card > 0) const SizedBox(width: _gridGap),
            Expanded(child: _SkeletonCard(height: height)),
          ],
        ],
      ),
    ],
  );
}

/// Slides the sheen gradient across the full width over one cycle.
class _SheenSlide extends GradientTransform {
  const _SheenSlide(this.t);
  final double t;

  @override
  Matrix4? transform(Rect bounds, {ui.TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

/// A card-shaped plate with the header line, two side lines and the footer
/// band a real card has, so the layout does not jump when fixtures land.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
    decoration: BoxDecoration(
      color: _tokens.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _tokens.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [_line(118, 10), const Spacer(), _line(44, 10)]),
        const SizedBox(height: 18),
        _line(160, 13),
        const SizedBox(height: 12),
        _line(132, 13),
        const Spacer(),
        Container(
          padding: const EdgeInsets.only(top: 9),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: _tokens.hairline)),
          ),
          child: _line(150, 10),
        ),
      ],
    ),
  );

  Widget _line(double width, double height) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: _tokens.hairline,
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
}

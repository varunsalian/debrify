// The board's When switch: Live · Today · This week.
//
// Presentation layer. Equal-width segments on one track, a single indicator
// that slides to the selected segment, and each segment's fixture count
// inline. Every segment is a [SportsFocusPill], so the remote moves along it
// with left/right and Select picks; the indicator, not the pill tint, shows
// the selection.
import 'package:debrify/features/sports/application/sports_board_sections.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

import 'sports_event_card.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;
const _trackHeight = 44.0;
const _trackPadding = 3.0;
const _slide = Duration(milliseconds: 180);

const _segmentStyle = SportsFocusPillStyle(radius: 9, tintSelected: false);

/// What each segment says.
String sportsBoardFilterLabel(SportsBoardFilter filter) => switch (filter) {
  SportsBoardFilter.live => 'Live',
  SportsBoardFilter.today => 'Today',
  SportsBoardFilter.week => 'This week',
};

class SportsWhenSwitch extends StatelessWidget {
  const SportsWhenSwitch({
    super.key,
    required this.filter,
    required this.counts,
    required this.onSelect,
    this.expand = false,
  });

  final SportsBoardFilter filter;

  /// Fixtures each segment would show.
  final Map<SportsBoardFilter, int> counts;
  final void Function(SportsBoardFilter filter) onSelect;

  /// Fill the available width (narrow boards); otherwise every segment is as
  /// wide as the widest one needs.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    const values = SportsBoardFilter.values;
    final index = values.indexOf(filter);
    final slide = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _slide;
    final track = Container(
      height: _trackHeight,
      padding: const EdgeInsets.all(_trackPadding),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _tokens.hairline),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              key: const ValueKey('sports-when-indicator'),
              alignment: Alignment(-1 + 2 * index / (values.length - 1), 0),
              duration: slide,
              curve: Curves.easeOut,
              child: FractionallySizedBox(
                widthFactor: 1 / values.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: _tokens.hairline2),
                  ),
                ),
              ),
            ),
          ),
          FocusTraversalGroup(
            child: Row(
              children: [
                for (final value in values)
                  Expanded(child: _segment(value, value == filter)),
              ],
            ),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      label: 'When',
      child: expand ? track : IntrinsicWidth(child: track),
    );
  }

  Widget _segment(SportsBoardFilter value, bool selected) {
    final label = sportsBoardFilterLabel(value);
    final count = counts[value] ?? 0;
    return SportsFocusPill(
      key: ValueKey('sports-filter-${value.name}'),
      label: '$label, $count',
      style: _segmentStyle,
      selected: selected,
      height: _trackHeight - _trackPadding * 2,
      // A stretched (phone) switch gives each segment a third of the width;
      // tighter padding keeps "This week" whole.
      padding: EdgeInsets.symmetric(horizontal: expand ? 8 : 14),
      onPressed: () => onSelect(value),
      builder: (_, ink, subtle) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (value == SportsBoardFilter.live) ...[
            const SportsLiveDot(),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: sportsLabelText(
              label,
              selected ? ink : subtle,
              weight: FontWeight.w600,
              ellipsize: true,
            ),
          ),
          const SizedBox(width: 7),
          sportsLabelText(
            '$count',
            // A focused segment inverts its ink; keep the count on that ramp.
            selected || ink == _tokens.focusInk ? subtle : _tokens.fgFaint,
            size: 11,
            weight: FontWeight.w600,
            tabular: true,
          ),
        ],
      ),
    );
  }
}

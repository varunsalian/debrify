// The sport chips under the header: All plus one chip per sport in the
// current view, each with its fixture count.
//
// Presentation layer. The chips report the picked sport upward; the board
// view keeps the choice as local state and narrows its rows with it. Left and
// right stay inside the strip; up and down leave it through the board's
// directional traversal.
import 'package:debrify/features/sports/application/sports_board_sports.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

import 'sports_labels.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;
const _chipHeight = 40.0;

class SportsSportChips extends StatelessWidget {
  const SportsSportChips({
    super.key,
    required this.total,
    required this.sports,
    required this.selected,
    required this.onSelect,
  });

  /// Fixtures in the current view, for the All chip.
  final int total;

  final List<SportsBoardSportCount> sports;

  /// Null is All.
  final SportKind? selected;
  final void Function(SportKind? sport) onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _chipHeight + 4,
    child: FocusTraversalGroup(
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(vertical: 2),
        children: [
          _chip(
            key: const ValueKey('sports-chip-all'),
            name: 'All',
            count: total,
            isSelected: selected == null,
            onPressed: () => onSelect(null),
          ),
          for (final entry in sports) ...[
            const SizedBox(width: 8),
            _chip(
              key: ValueKey('sports-chip-${entry.sport.name}'),
              name: sportsKindName(entry.sport),
              icon: sportsKindIcon(entry.sport),
              count: entry.count,
              isSelected: selected == entry.sport,
              onPressed: () => onSelect(entry.sport),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _chip({
    required Key key,
    required String name,
    required int count,
    required bool isSelected,
    required VoidCallback onPressed,
    IconData? icon,
  }) {
    final ink = isSelected ? _tokens.focusInk! : _tokens.fgDim;
    final countInk = isSelected
        ? _tokens.focusInk!.withValues(alpha: 0.6)
        : _tokens.fgFaint;
    return SportsFocusPill(
      key: key,
      label: '$name, $count',
      selected: isSelected,
      height: _chipHeight,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      style: SportsFocusPillStyle(
        radius: _chipHeight / 2,
        outlined: true,
        restColor: isSelected ? _tokens.fg : Colors.transparent,
        focusedFill: isSelected ? _tokens.fg : _tokens.focusTint,
        focusedBorderColor: _tokens.accent,
        focusedBorderWidth: 2,
        scale: 1.05,
        invertInkOnFocus: false,
        tintSelected: false,
      ),
      onPressed: onPressed,
      builder: (_, _, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: ink),
            const SizedBox(width: 6),
          ],
          sportsLabelText(name, ink, size: 12.5, weight: FontWeight.w600),
          const SizedBox(width: 6),
          sportsLabelText(
            '$count',
            countInk,
            size: 10.5,
            weight: FontWeight.w600,
            tabular: true,
          ),
        ],
      ),
    );
  }
}

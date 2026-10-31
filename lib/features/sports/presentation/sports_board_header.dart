// The board's header row: title and last update, the When switch, the
// Following and Scores toggles, and the Sports & leagues and Refresh buttons.
//
// Presentation layer. The header renders the state handed to it and reports
// each intent upward; the board view owns the controller and the sheet. Wide
// boards fit everything on one row; narrower ones put the When switch on its
// own full-width line, and a phone wraps the tools under it.
import 'package:debrify/features/sports/application/sports_board_sections.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'sports_team_crest.dart';
import 'sports_when_switch.dart';

const _tokens = IptvStyleTokens.spotlight;
const _toolSize = 44.0;

/// At least this wide and the header is a single row.
const _singleRowMinWidth = 920.0;

/// At least this wide and the title shares its row with the tools.
const _titleWithToolsMinWidth = 520.0;

class SportsBoardHeader extends StatelessWidget {
  const SportsBoardHeader({
    super.key,
    required this.updatedAt,
    this.loading = false,
    required this.filter,
    required this.counts,
    required this.followingOnly,
    required this.hideScores,
    required this.onSelectFilter,
    required this.onToggleFollowing,
    required this.onToggleScores,
    required this.onOpenLeagues,
    required this.onRefresh,
  });

  /// When the fixtures on screen were loaded; null before the first load.
  final DateTime? updatedAt;

  /// Feeds are still answering: the title says so instead of "Updated".
  final bool loading;

  final SportsBoardFilter filter;
  final Map<SportsBoardFilter, int> counts;
  final bool followingOnly;
  final bool hideScores;
  final void Function(SportsBoardFilter filter) onSelectFilter;
  final VoidCallback onToggleFollowing;
  final VoidCallback onToggleScores;
  final VoidCallback onOpenLeagues;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (width >= _singleRowMinWidth) {
        return Row(
          children: [
            Expanded(child: _title()),
            _when(expand: false),
            const SizedBox(width: 14),
            _tools(),
          ],
        );
      }
      if (width >= _titleWithToolsMinWidth) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _title()),
                const SizedBox(width: 12),
                _tools(),
              ],
            ),
            const SizedBox(height: 12),
            _when(expand: true),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title(),
          const SizedBox(height: 12),
          _when(expand: true),
          const SizedBox(height: 12),
          _tools(),
        ],
      );
    },
  );

  Widget _title() => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Semantics(
        header: true,
        child: sportsLabelText(
          'Sports',
          _tokens.fg,
          size: 19,
          weight: FontWeight.w700,
          tracking: -0.2,
        ),
      ),
      if (loading) ...[
        const SizedBox(width: 10),
        Flexible(
          child: sportsLabelText(
            'Loading fixtures…',
            _tokens.fgFaint,
            size: 12,
            ellipsize: true,
          ),
        ),
      ] else if (updatedAt case final at?) ...[
        const SizedBox(width: 10),
        Flexible(
          child: sportsLabelText(
            'Updated ${DateFormat('HH:mm').format(at.toLocal())}',
            _tokens.fgFaint,
            size: 12,
            tabular: true,
            ellipsize: true,
          ),
        ),
      ],
    ],
  );

  Widget _when({required bool expand}) => SportsWhenSwitch(
    filter: filter,
    counts: counts,
    onSelect: onSelectFilter,
    expand: expand,
  );

  Widget _tools() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      SportsToolButton(
        key: const ValueKey('sports-toggle-following'),
        label: 'Following',
        icon: Icons.star_rounded,
        text: 'Following',
        toggled: followingOnly,
        onPressed: onToggleFollowing,
      ),
      SportsToolButton(
        key: const ValueKey('sports-toggle-scores'),
        label: hideScores ? 'Scores hidden' : 'Scores shown',
        icon: hideScores
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        text: 'Scores',
        toggled: !hideScores,
        onPressed: onToggleScores,
      ),
      SportsToolButton(
        key: const ValueKey('sports-open-leagues'),
        label: 'Sports & leagues',
        icon: Icons.tune_rounded,
        onPressed: onOpenLeagues,
      ),
      SportsToolButton(
        key: const ValueKey('sports-refresh'),
        label: 'Refresh',
        icon: Icons.refresh_rounded,
        onPressed: onRefresh,
      ),
    ],
  );
}

/// A header tool: an icon button, or an icon and a word; [toggled] makes it
/// an on/off control painted with the selected tint while on.
class SportsToolButton extends StatelessWidget {
  const SportsToolButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.text,
    this.toggled,
  });

  /// What a screen reader hears, and the tooltip of an icon-only button.
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final String? text;
  final bool? toggled;

  @override
  Widget build(BuildContext context) {
    final on = toggled ?? false;
    final pill = SportsFocusPill(
      label: label,
      style: const SportsFocusPillStyle(radius: 10, outlined: true),
      selected: on,
      toggled: toggled,
      height: _toolSize,
      padding: EdgeInsets.symmetric(horizontal: text == null ? 0 : 12),
      onPressed: onPressed,
      builder: (_, ink, subtle) {
        final color = on || ink == _tokens.focusInk ? ink : subtle;
        final glyph = Icon(icon, size: 17, color: color);
        if (text == null) return Center(child: glyph);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            glyph,
            const SizedBox(width: 7),
            sportsLabelText(text!, color, weight: FontWeight.w600),
          ],
        );
      },
    );
    if (text != null) return pill;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: SizedBox(width: _toolSize, child: pill),
    );
  }
}

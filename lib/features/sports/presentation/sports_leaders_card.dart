// Each side's top player per category: the home leader on the left, the away
// leader mirrored on the right, the category above them.
//
// Presentation layer. Headshots are decorative (the row's label names the
// player) and fall back to initials while missing, loading or failed.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

import 'sports_stats_frame.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;
const _headshot = 36.0;

class SportsLeadersCard extends StatelessWidget {
  const SportsLeadersCard({
    super.key,
    required this.title,
    required this.leaders,
    required this.homeName,
    required this.awayName,
    required this.colors,
    this.autofocus = false,
  });

  final String title;
  final List<SportsLeaderPair> leaders;
  final String homeName;
  final String awayName;
  final ({Color home, Color away}) colors;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => SportsStatsCard(
    title: title,
    children: [
      for (final (index, pair) in leaders.indexed)
        SportsStatsFocusRow(
          key: ValueKey('sports-leaders-${pair.category}'),
          autofocus: autofocus && index == 0,
          label: _label(pair),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: sportsLabelText(
                  pair.category,
                  _tokens.fgDim,
                  size: 11.5,
                  weight: FontWeight.w700,
                  tracking: 0.4,
                  ellipsize: true,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Leader(
                      leader: pair.home,
                      ring: colors.home,
                      mirrored: false,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Leader(
                      leader: pair.away,
                      ring: colors.away,
                      mirrored: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
    ],
  );

  String _label(SportsLeaderPair pair) {
    String side(String team, SportsLeader? leader) => leader == null
        ? '$team: none'
        : '$team: ${leader.name}, ${leader.summary}';
    return '${pair.category}. ${side(homeName, pair.home)}. '
        '${side(awayName, pair.away)}';
  }
}

class _Leader extends StatelessWidget {
  const _Leader({
    required this.leader,
    required this.ring,
    required this.mirrored,
  });

  final SportsLeader? leader;
  final Color ring;

  /// The away side reads from the outer edge inwards.
  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    final leader = this.leader;
    if (leader == null) {
      return Align(
        alignment: mirrored
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: sportsLabelText('—', _tokens.fgFaint),
      );
    }
    final align = mirrored ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final textAlign = mirrored ? TextAlign.end : TextAlign.start;
    final text = Expanded(
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(
            leader.shortName ?? leader.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: TextStyle(
              color: _tokens.fg,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            leader.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: textAlign,
            style: TextStyle(color: _tokens.fgDim, fontSize: 11.5, height: 1.3),
          ),
        ],
      ),
    );
    final face = _Headshot(leader: leader, ring: ring);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: mirrored
          ? [text, const SizedBox(width: 8), face]
          : [face, const SizedBox(width: 8), text],
    );
  }
}

class _Headshot extends StatelessWidget {
  const _Headshot({required this.leader, required this.ring});

  final SportsLeader leader;
  final Color ring;

  static String initials(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    return words.length == 1
        ? words.first[0].toUpperCase()
        : '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: sportsLabelText(
        initials(leader.name),
        _tokens.fgMid,
        size: 12,
        weight: FontWeight.w700,
      ),
    );
    final url = leader.headshotUrl;
    return ExcludeSemantics(
      child: Container(
        width: _headshot,
        height: _headshot,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _tokens.hairline,
          border: Border.all(color: ring, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: url == null
            ? fallback
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheHeight:
                    (_headshot * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

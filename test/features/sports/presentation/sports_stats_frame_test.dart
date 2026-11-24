// The two team colours the stats page draws with: readable on the dark
// panel, a side's own colour where possible, and never two look-alikes.
import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/features/sports/presentation/sports_stats_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SportsMatchSide _side(int? color, [int? alternate]) => SportsMatchSide(
  teamId: '$color',
  abbreviation: 'T',
  name: 'Team',
  color: color,
  alternateColor: alternate,
);

double _luminance(Color c) => c.computeLuminance();

void main() {
  test('a readable own colour is used as it is', () {
    final colors = sportsStatsColors(
      _side(0xFFF28800, 0xFFFFFFFF),
      _side(0xFF30D158),
    );
    expect(colors.home, const Color(0xFFF28800));
    expect(colors.away, const Color(0xFF30D158));
  });

  test('a near-black colour gives way to a readable alternate', () {
    // Houston: navy #021018 with a red alternate.
    final colors = sportsStatsColors(
      _side(0xFF021018, 0xFFEB0028),
      _side(0xFF30D158),
    );
    expect(colors.home.r, greaterThan(colors.home.b), reason: 'red, not grey');
    expect(_luminance(colors.home), greaterThanOrEqualTo(0.18));
  });

  test('a dark own colour is lightened rather than swapped on a tie', () {
    // Brighton: #0606fa, too dark as text on the panel.
    final colors = sportsStatsColors(
      _side(0xFFF28800),
      _side(0xFF0606FA, 0xFF005F60),
    );
    expect(_luminance(colors.away), greaterThanOrEqualTo(0.18));
    expect(colors.away.b, greaterThan(colors.away.g), reason: 'still blue');
  });

  test('two look-alike sides never share a colour', () {
    final colors = sportsStatsColors(_side(0xFF0A84FF), _side(0xFF0A84FF));
    expect(colors.away, isNot(colors.home));
  });

  test('sides without colours get the fallbacks', () {
    final colors = sportsStatsColors(_side(null), _side(null));
    expect(colors.home, sportsStatsHomeFallback);
    expect(colors.away, sportsStatsAwayFallback);
  });
}

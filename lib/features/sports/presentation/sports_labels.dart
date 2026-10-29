// What the board calls each sport and how the league picker describes each
// catalog league.
//
// Presentation layer: display copy only. The catalog itself carries no
// country, so the picker's second line lives here, keyed by league id.
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter/material.dart';

/// The sport's display name, e.g. `'Football'` for [SportKind.soccer].
String sportsKindName(SportKind sport) => switch (sport) {
  SportKind.soccer => 'Football',
  SportKind.basketball => 'Basketball',
  SportKind.americanFootball => 'American football',
  SportKind.hockey => 'Ice hockey',
  SportKind.baseball => 'Baseball',
  SportKind.motorsport => 'Motor racing',
  SportKind.cricket => 'Cricket',
  SportKind.tennis => 'Tennis',
  SportKind.combat => 'Fights',
  SportKind.golf => 'Golf',
  SportKind.rugby => 'Rugby',
};

/// The sport's icon on chips and in the picker.
IconData sportsKindIcon(SportKind sport) => switch (sport) {
  SportKind.soccer => Icons.sports_soccer,
  SportKind.basketball => Icons.sports_basketball,
  SportKind.americanFootball => Icons.sports_football,
  SportKind.hockey => Icons.sports_hockey,
  SportKind.baseball => Icons.sports_baseball,
  SportKind.motorsport => Icons.sports_motorsports,
  SportKind.cricket => Icons.sports_cricket,
  SportKind.tennis => Icons.sports_tennis,
  SportKind.combat => Icons.sports_mma,
  SportKind.golf => Icons.sports_golf,
  SportKind.rugby => Icons.sports_rugby,
};

/// The picker's second line for a league: its country or what it covers.
/// Null for a league without one.
String? sportsLeagueDescription(String leagueId) => _descriptions[leagueId];

const _descriptions = <String, String>{
  'ucl': 'UEFA',
  'epl': 'England',
  'nfl': 'USA',
  'nba': 'USA',
  'f1': 'World championship',
  'laliga': 'Spain',
  'uel': 'UEFA',
  'seriea': 'Italy',
  'bundesliga': 'Germany',
  'ligue1': 'France',
  'nhl': 'USA and Canada',
  'mlb': 'USA',
  'mls': 'USA and Canada',
  'intl-cricket': 'Tests, ODIs and T20Is',
  'ipl': 'India',
  'isl': 'India',
  'ranji': 'India',
  'atp': "Men's singles",
  'wta': "Women's singles",
  'ufc': 'Fight cards',
  'uecl': 'UEFA',
  'copa': 'Spain',
  'carabao': 'England',
  'facup': 'England',
  'bbl': 'Australia',
  'wbbl': 'Australia',
  'shield': 'Australia',
  'county': 'England',
  'nascar': 'USA',
  'indycar': 'USA',
  'pga': "Men's tour",
  'lpga': "Women's tour",
  'six-nations': 'Europe',
  'prem-rugby': 'England',
  'urc': 'Europe and South Africa',
  'top14': 'France',
  'efl': 'England',
  'eredivisie': 'Netherlands',
  'primeira': 'Portugal',
  'saudi': 'Saudi Arabia',
  'ligamx': 'Mexico',
  'brasileirao': 'Brazil',
  'spfl': 'Scotland',
  'uwcl': 'UEFA',
  'wnba': 'USA',
  'ncaam': 'NCAA',
  'ncaaf': 'NCAA',
};

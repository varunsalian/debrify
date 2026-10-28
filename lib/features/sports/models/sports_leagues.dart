// The curated league catalog for the sports board.
import 'sports_models.dart';

/// Exactly the supported leagues, in prominence order.
const List<SportsLeague> kSportsLeagues = [
  SportsLeague(
    id: 'ucl',
    name: 'Champions League',
    shortName: 'UCL',
    sport: SportKind.soccer,
    espnPath: 'soccer/uefa.champions',
    importance: 100,
  ),
  SportsLeague(
    id: 'epl',
    name: 'Premier League',
    shortName: 'EPL',
    sport: SportKind.soccer,
    espnPath: 'soccer/eng.1',
    importance: 95,
  ),
  SportsLeague(
    id: 'nfl',
    name: 'NFL',
    shortName: 'NFL',
    sport: SportKind.americanFootball,
    espnPath: 'football/nfl',
    importance: 90,
  ),
  SportsLeague(
    id: 'nba',
    name: 'NBA',
    shortName: 'NBA',
    sport: SportKind.basketball,
    espnPath: 'basketball/nba',
    importance: 88,
  ),
  SportsLeague(
    id: 'f1',
    name: 'Formula 1',
    shortName: 'F1',
    sport: SportKind.motorsport,
    importance: 85,
  ),
  SportsLeague(
    id: 'laliga',
    name: 'LaLiga',
    shortName: 'LaLiga',
    sport: SportKind.soccer,
    espnPath: 'soccer/esp.1',
    importance: 80,
  ),
  SportsLeague(
    id: 'uel',
    name: 'Europa League',
    shortName: 'UEL',
    sport: SportKind.soccer,
    espnPath: 'soccer/uefa.europa',
    importance: 75,
  ),
  SportsLeague(
    id: 'seriea',
    name: 'Serie A',
    shortName: 'Serie A',
    sport: SportKind.soccer,
    espnPath: 'soccer/ita.1',
    importance: 72,
  ),
  SportsLeague(
    id: 'bundesliga',
    name: 'Bundesliga',
    shortName: 'Bundesliga',
    sport: SportKind.soccer,
    espnPath: 'soccer/ger.1',
    importance: 70,
  ),
  SportsLeague(
    id: 'ligue1',
    name: 'Ligue 1',
    shortName: 'Ligue 1',
    sport: SportKind.soccer,
    espnPath: 'soccer/fra.1',
    importance: 65,
  ),
  SportsLeague(
    id: 'nhl',
    name: 'NHL',
    shortName: 'NHL',
    sport: SportKind.hockey,
    espnPath: 'hockey/nhl',
    importance: 60,
  ),
  SportsLeague(
    id: 'mlb',
    name: 'MLB',
    shortName: 'MLB',
    sport: SportKind.baseball,
    espnPath: 'baseball/mlb',
    importance: 55,
  ),
  SportsLeague(
    id: 'mls',
    name: 'MLS',
    shortName: 'MLS',
    sport: SportKind.soccer,
    espnPath: 'soccer/usa.1',
    importance: 50,
  ),
];

/// The league with [id], or null when unknown.
SportsLeague? sportsLeagueById(String id) {
  for (final league in kSportsLeagues) {
    if (league.id == id) return league;
  }
  return null;
}

/// Importance of the league with [id]; 0 when unknown.
int sportsLeagueImportance(String id) => sportsLeagueById(id)?.importance ?? 0;

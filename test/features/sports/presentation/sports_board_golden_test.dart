// Visual record of the redesigned Sports board (macOS goldens only): the
// week view with every card shape, the Sports & leagues sheet, and the board
// at phone width. Events are built in local time around a fixed 2030 board
// clock, so the day rows and kick-off labels never depend on the machine's
// zone or on the real date.
import 'dart:io';

import 'package:debrify/features/sports/data/sports_league_filter_store.dart';
import 'package:debrify/features/sports/models/sports_guide_contract.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sports_board_test_harness.dart';

/// Wednesday 6 March 2030, 20:41 local.
final _now = DateTime(2030, 3, 6, 20, 41);

DateTime _at(int day, int hour, [int minute = 0]) =>
    DateTime(2030, 3, day, hour, minute).toUtc();

SportsTeam _t(String id, String name, int color) => SportsTeam(
  id: id,
  name: name,
  shortName: name,
  abbreviation: id,
  color: color,
);

final _ucl = SportsEvent(
  id: 'ucl-1',
  leagueId: 'ucl',
  start: _at(6, 20),
  status: SportsEventStatus.live,
  clock: "41'",
  home: _t('RMA', 'Real Madrid', 0xFF1F2A44),
  away: _t('ARS', 'Arsenal', 0xFFEF0107),
  homeScore: 1,
  awayScore: 0,
);

final _cricket = SportsEvent(
  id: 'c-1',
  leagueId: 'intl-cricket',
  start: _at(4, 10),
  status: SportsEventStatus.live,
  clock: 'Day 3',
  home: _t('SA', 'South Africa', 0xFF007A4D),
  away: _t('AUS', 'Australia', 0xFFC6A100),
  homeScoreText: '329 & 0/0',
  awayScoreText: '330/4 (90 ov)',
  format: 'TEST',
  note: 'Australia lead by 1 run',
  group: 'Australia tour of South Africa',
);

final _tennis = SportsEvent(
  id: 't-1',
  leagueId: 'wta',
  start: _at(6, 18),
  status: SportsEventStatus.live,
  clock: 'Set 3',
  home: _t('Iatcenko', 'Polina Iatcenko', 0),
  away: _t('Shubladze', 'Alexandra Shubladze', 0),
  homeLines: const [6, 2, 4],
  awayLines: const [3, 6, 3],
  format: 'R16',
  group: 'Guangzhou Open',
);

final _golf = SportsEvent(
  id: 'g-1',
  leagueId: 'pga',
  start: _at(6, 13),
  status: SportsEventStatus.live,
  clock: 'Round 1',
  title: 'VidantaWorld Mexico Open',
  subtitle: 'Vidanta Vallarta',
  leaderName: 'Patton Kizzire',
  leaderScore: '-6',
);

final _serieATonight = SportsEvent(
  id: 'sa-1',
  leagueId: 'seriea',
  start: _at(6, 23),
  status: SportsEventStatus.scheduled,
  home: _t('FRO', 'Frosinone', 0xFFB8A000),
  away: _t('LEC', 'Lecce', 0xFFC8102E),
);

final _epl = SportsEvent(
  id: 'epl-1',
  leagueId: 'epl',
  start: _at(7, 18),
  status: SportsEventStatus.scheduled,
  home: _t('CHE', 'Chelsea', 0xFF034694),
  away: _t('MUN', 'Manchester United', 0xFFDA020E),
);

final _nba = SportsEvent(
  id: 'nba-1',
  leagueId: 'nba',
  start: _at(7, 5),
  status: SportsEventStatus.scheduled,
  home: _t('BOS', 'Boston Celtics', 0xFF007A33),
  away: _t('NYK', 'New York Knicks', 0xFF006BB6),
);

final _ufc = SportsEvent(
  id: 'ufc-1',
  leagueId: 'ufc',
  start: _at(8, 2, 30),
  status: SportsEventStatus.scheduled,
  title: 'UFC Fight Night: Moicano vs. Nolan',
  format: 'Lightweight',
  itemCount: 12,
  subtitle: 'UFC APEX, Las Vegas',
);

final _nascar = SportsEvent(
  id: 'nas-1',
  leagueId: 'nascar',
  start: _at(10, 0, 30),
  status: SportsEventStatus.scheduled,
  title: 'Xfinity 500',
  subtitle: 'Martinsville Speedway',
);

final _f1 = SportsEvent(
  id: 'f1-1',
  leagueId: 'f1',
  start: _at(10, 1, 30),
  status: SportsEventStatus.scheduled,
  title: 'Mexico City Grand Prix',
  subtitle: 'Autódromo Hermanos Rodríguez',
);

final _serieAResult = SportsEvent(
  id: 'sa-0',
  leagueId: 'seriea',
  start: _at(6, 15),
  status: SportsEventStatus.finished,
  home: _t('FIO', 'Fiorentina', 0xFF482E92),
  away: _t('ATA', 'Atalanta', 0xFF1E71B8),
  homeScore: 2,
  awayScore: 1,
);

final _nbaResult = SportsEvent(
  id: 'nba-0',
  leagueId: 'nba',
  start: _at(6, 3),
  status: SportsEventStatus.finished,
  home: _t('DEN', 'Denver Nuggets', 0xFF0E2240),
  away: _t('LAL', 'LA Lakers', 0xFF552583),
  homeScore: 118,
  awayScore: 121,
);

SportsGuideListing _listing(String channel, String title, SportsEvent event) =>
    SportsGuideListing(
      channel: SportsChannelRef(name: channel, url: 'http://test/$channel'),
      title: title,
      start: event.start,
      stop: event.start.add(const Duration(hours: 3)),
    );

SportsBoardHarness _harness() {
  final events = [
    _ucl,
    _cricket,
    _tennis,
    _golf,
    _serieATonight,
    _epl,
    _nba,
    _ufc,
    _nascar,
    _f1,
    _serieAResult,
    _nbaResult,
  ];
  final h = SportsBoardHarness(
    clock: _now,
    leagueIds: const [
      'ucl',
      'intl-cricket',
      'wta',
      'pga',
      'seriea',
      'epl',
      'nba',
      'ufc',
      'nascar',
      'f1',
    ],
    eventsByLeague: {
      for (final event in events)
        event.leagueId: [
          for (final e in events)
            if (e.leagueId == event.leagueId) e,
        ],
    },
    guide: SportsGuideSnapshot(
      listings: [
        _listing(
          'UK: Sky Sports Main Event FHD',
          'Champions League: Real Madrid v Arsenal',
          _ucl,
        ),
        _listing('TNT Sports 1 HD', 'Real Madrid v Arsenal', _ucl),
        _listing(
          'Sky Sport Calcio',
          'Serie A: Frosinone v Lecce',
          _serieATonight,
        ),
      ],
    ),
  );
  return h;
}

final _theme = ThemeData(brightness: Brightness.dark, fontFamily: 'Inter');

Future<void> _loadFonts(WidgetTester t) => t.runAsync(() async {
  for (final family in ['Inter', 'JetBrainsMono']) {
    await (FontLoader(
      family,
    )..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'))).load();
  }
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
});

Future<void> _mount(WidgetTester t, SportsBoardHarness h, Size size) async {
  await _loadFonts(t);
  await t.binding.setSurfaceSize(size);
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(h.app(theme: _theme));
  await t.pumpAndSettle();
}

Future<void> _expectGolden(String name) => expectLater(
  find.byKey(sportsBoardCaptureKey),
  matchesGoldenFile('../../../goldens/sports_board/macos/$name.png'),
);

void main() {
  // Goldens are recorded on macOS only; other hosts render fonts differently.
  final skip = !Platform.isMacOS;

  setUp(() => PlatformUtil.debugSetAndroidTvCached(true));
  tearDown(() => PlatformUtil.debugSetAndroidTvCached(null));

  testWidgets('week view with every card shape', skip: skip, (t) async {
    await _mount(t, _harness(), const Size(1280, 1720));
    await _expectGolden('week_mixed');
  });

  testWidgets('the Sports & leagues sheet', skip: skip, (t) async {
    final h = _harness();
    h.leaguePrefs.lists[SportsLeagueFilterStore.offKey] = ['ranji'];
    await _mount(t, h, const Size(1280, 800));
    await t.tap(find.byKey(const ValueKey('sports-open-leagues')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('sports-sheet-sport-cricket')));
    await t.pumpAndSettle();
    await _expectGolden('leagues_sheet');
  });

  testWidgets('phone width', skip: skip, (t) async {
    await _mount(t, _harness(), const Size(390, 1500));
    await _expectGolden('phone_week');
  });
}

import 'package:debrify/features/sports/application/sports_channel_matcher.dart';
import 'package:debrify/features/sports/application/sports_names.dart';
import 'package:debrify/features/sports/application/sports_stream_names.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _kickOff = DateTime.utc(2026, 10, 28, 20);

SportsTeam _team(String id, String name, {String? shortName}) => SportsTeam(
  id: id,
  name: name,
  shortName: shortName ?? name,
  abbreviation: id.toUpperCase(),
);

/// Arsenal v Bayern Munich, the fixture used by the spec example.
SportsEvent _matchEvent({
  DateTime? start,
  List<String> broadcasts = const [],
}) => SportsEvent(
  id: 'ucl-1',
  leagueId: 'ucl',
  start: start ?? _kickOff,
  status: SportsEventStatus.live,
  home: _team('ars', 'Arsenal'),
  away: _team('bay', 'Bayern Munich', shortName: 'Bayern'),
  broadcasts: broadcasts,
);

SportsEvent _raceEvent({
  String title = 'Mexico City Grand Prix',
  List<String> broadcasts = const [],
}) => SportsEvent(
  id: 'f1-2026-1',
  leagueId: 'f1',
  start: _kickOff,
  status: SportsEventStatus.scheduled,
  title: title,
  broadcasts: broadcasts,
);

SportsChannelRef _channel(String name) => SportsChannelRef(
  name: name,
  url: 'https://stream/${Uri.encodeComponent(name)}',
);

SportsGuideListing _listing(
  String channelName,
  String title, {
  DateTime? start,
  DateTime? stop,
}) => SportsGuideListing(
  channel: _channel(channelName),
  title: title,
  start: start ?? _kickOff.subtract(const Duration(minutes: 30)),
  stop: stop ?? _kickOff.add(const Duration(hours: 2, minutes: 15)),
);

/// The two listings of the spec example, on two copies of the same channel.
List<SportsGuideListing> _specListings() => [
  _listing(
    'UK: TNT Sports 1 HD',
    'Live UEFA Champions League: Arsenal v Bayern',
  ),
  _listing('TNT Sports 1 4K', 'Live UEFA Champions League: Arsenal v Bayern'),
];

void main() {
  group('sportsTitleNeedles', () {
    test('team events contribute both teams in home-then-away order', () {
      expect(sportsTitleNeedles(_matchEvent()), [
        'arsenal',
        'bayern munich',
        'bayern',
        'bayern munchen',
        'fc bayern',
      ]);
    });

    test('team needles are deduplicated', () {
      final event = SportsEvent(
        id: 'e',
        leagueId: 'mls',
        start: _kickOff,
        status: SportsEventStatus.scheduled,
        home: _team('a', 'FC Porto'),
        away: _team('b', 'FC Porto'),
      );
      expect(sportsTitleNeedles(event), ['fc porto', 'porto']);
    });

    test('a team with no usable variant contributes nothing', () {
      final event = SportsEvent(
        id: 'e',
        leagueId: 'mls',
        start: _kickOff,
        status: SportsEventStatus.scheduled,
        home: _team('a', 'FC'),
        away: _team('b', 'Arsenal'),
      );
      expect(sportsTitleNeedles(event), ['arsenal']);
    });

    test('non-team events use the title without "grand prix"', () {
      expect(sportsTitleNeedles(_raceEvent()), ['mexico city']);
      expect(sportsTitleNeedles(_raceEvent(title: 'São Paulo Grand Prix')), [
        'sao paulo',
      ]);
      expect(sportsTitleNeedles(_raceEvent(title: 'Formula 1 Grand Prix')), [
        'formula 1',
      ]);
    });

    test('non-team events with no usable title have no needles', () {
      expect(sportsTitleNeedles(_raceEvent(title: 'Grand Prix')), isEmpty);
      expect(sportsTitleNeedles(_raceEvent(title: '  — ')), isEmpty);
      expect(
        sportsTitleNeedles(
          SportsEvent(
            id: 'e',
            leagueId: 'f1',
            start: _kickOff,
            status: SportsEventStatus.scheduled,
          ),
        ),
        isEmpty,
      );
    });

    test('team events win over a title', () {
      final event = SportsEvent(
        id: 'e',
        leagueId: 'ucl',
        start: _kickOff,
        status: SportsEventStatus.scheduled,
        title: 'Mexico City Grand Prix',
        home: _team('a', 'Arsenal'),
        away: _team('b', 'Chelsea'),
      );
      expect(sportsTitleNeedles(event), ['arsenal', 'chelsea']);
    });
  });

  group('matchSportsEvent guide options', () {
    test('matches the spec example exactly', () {
      final result = matchSportsEvent(
        _matchEvent(),
        listings: _specListings(),
        channels: const [],
      );
      expect(result.guide, hasLength(1));
      final option = result.guide.single;
      expect(option.kind, SportsMatchKind.guide);
      expect(option.channel.name, 'TNT Sports 1 4K');
      expect(option.variants.map((c) => c.name), ['UK: TNT Sports 1 HD']);
      expect(
        option.listing?.title,
        'Live UEFA Champions League: Arsenal v Bayern',
      );
      expect(result.possible, isEmpty);
      expect(result.count, 1);
      expect(result.isEmpty, isFalse);
    });

    test('excludes a highlights listing outside the window', () {
      final result = matchSportsEvent(
        _matchEvent(),
        listings: [
          ..._specListings(),
          _listing(
            'TNT Sports 2',
            'Arsenal v Bayern: Highlights',
            start: _kickOff.add(const Duration(hours: 3)),
            stop: _kickOff.add(const Duration(hours: 3, minutes: 30)),
          ),
        ],
        channels: const [],
      );
      expect(result.guide, hasLength(1));
      expect(result.guide.single.channel.name, 'TNT Sports 1 4K');
    });

    test('no listings and no channels yields empty options', () {
      final result = matchSportsEvent(
        _matchEvent(),
        listings: const [],
        channels: const [],
      );
      expect(result, SportsWatchOptions.empty);
      expect(result.isEmpty, isTrue);
      expect(result.count, 0);
    });

    test('timing accepts a listing starting within two hours either side', () {
      List<SportsGuideListing> at(Duration offset) => [
        _listing(
          'TNT Sports 1',
          'Arsenal v Bayern Munich',
          start: _kickOff.add(offset),
          stop: _kickOff.add(offset + const Duration(minutes: 30)),
        ),
      ];
      expect(
        matchSportsEvent(
          _matchEvent(),
          listings: at(const Duration(hours: 2)),
          channels: const [],
        ).guide,
        hasLength(1),
      );
      expect(
        matchSportsEvent(
          _matchEvent(),
          listings: at(const Duration(hours: -2)),
          channels: const [],
        ).guide,
        hasLength(1),
      );
      expect(
        matchSportsEvent(
          _matchEvent(),
          listings: at(const Duration(hours: 2, minutes: 1)),
          channels: const [],
        ).guide,
        isEmpty,
      );
      expect(
        matchSportsEvent(
          _matchEvent(),
          listings: at(const Duration(hours: -2, minutes: -1)),
          channels: const [],
        ).guide,
        isEmpty,
      );
    });

    test('timing also accepts a listing covering kick-off', () {
      final result = matchSportsEvent(
        _matchEvent(),
        listings: [
          _listing(
            'TNT Sports 1',
            'Live UEFA Champions League build-up: Arsenal v Bayern Munich',
            start: _kickOff.subtract(const Duration(hours: 3)),
            stop: _kickOff.add(const Duration(minutes: 30)),
          ),
        ],
        channels: const [],
      );
      expect(result.guide, hasLength(1));
    });

    test('a listing ending exactly at kick-off does not cover it', () {
      final result = matchSportsEvent(
        _matchEvent(),
        listings: [
          _listing(
            'TNT Sports 1',
            'Arsenal v Bayern Munich',
            start: _kickOff.subtract(const Duration(hours: 3)),
            stop: _kickOff,
          ),
        ],
        channels: const [],
      );
      expect(result.guide, isEmpty);
    });

    test('rejects every recap word as a whole word', () {
      for (final word in kSportsNonLiveWords) {
        final result = matchSportsEvent(
          _matchEvent(),
          listings: [_listing('TNT Sports 1', 'Arsenal v Bayern Munich $word')],
          channels: const [],
        );
        expect(result.guide, isEmpty, reason: word);
      }
      // Other words are not on the list.
      expect(
        matchSportsEvent(
          _matchEvent(),
          listings: [
            _listing('TNT Sports 1', 'Arsenal v Bayern Munich highlight'),
          ],
          channels: const [],
        ).guide,
        hasLength(1),
      );
    });

    test('requires a variant of both teams', () {
      expect(
        matchSportsEvent(
          _matchEvent(),
          listings: [_listing('TNT Sports 1', 'Arsenal v Chelsea')],
          channels: const [],
        ).guide,
        isEmpty,
      );
      expect(
        matchSportsEvent(
          _matchEvent(),
          listings: [_listing('TNT Sports 1', 'Bayern Munich vs Dortmund')],
          channels: const [],
        ).guide,
        isEmpty,
      );
      expect(
        matchSportsEvent(
          _matchEvent(),
          listings: [_listing('TNT Sports 1', 'Man United v Bayern Munich')],
          channels: const [],
        ).guide,
        isEmpty,
      );
    });

    test('matches aliases and accents in the listing title', () {
      expect(
        matchSportsEvent(
          _matchEvent(),
          listings: [_listing('TNT Sports 1', 'Arsenal v Bayern München')],
          channels: const [],
        ).guide,
        hasLength(1),
      );
      final premier = SportsEvent(
        id: 'epl-1',
        leagueId: 'epl',
        start: _kickOff,
        status: SportsEventStatus.scheduled,
        home: _team('new', 'Newcastle United'),
        away: _team('lee', 'Leeds United'),
      );
      expect(
        matchSportsEvent(
          premier,
          listings: [_listing('Sky Sports Main Event', 'Newcastle vs Leeds')],
          channels: const [],
        ).guide,
        hasLength(1),
      );
      // Whole words only: `newcastle` inside another word is not a match.
      expect(
        matchSportsEvent(
          premier,
          listings: [
            _listing('Sky Sports Main Event', 'Newcastleupon vs Leeds'),
          ],
          channels: const [],
        ).guide,
        isEmpty,
      );
    });

    test('non-team events need the needle and a motor-sport phrase', () {
      expect(
        matchSportsEvent(
          _raceEvent(),
          listings: [_listing('Sky Sports F1', 'Formula 1: Mexico City GP')],
          channels: const [],
        ).guide,
        hasLength(1),
      );
      expect(
        matchSportsEvent(
          _raceEvent(),
          listings: [
            _listing('Sky Sports F1', 'Mexico City - Grand Prix review'),
          ],
          channels: const [],
        ).guide,
        isEmpty,
      );
      expect(
        matchSportsEvent(
          _raceEvent(),
          listings: [_listing('Sky Sports', 'Mexico City boxing undercard')],
          channels: const [],
        ).guide,
        isEmpty,
      );
      expect(
        matchSportsEvent(
          _raceEvent(),
          listings: [
            _listing('Sky Sports F1', 'Formula 1 practice highlights'),
          ],
          channels: const [],
        ).guide,
        isEmpty,
      );
      expect(
        matchSportsEvent(
          _raceEvent(title: 'Grand Prix'),
          listings: [_listing('Sky Sports F1', 'Formula 1 Mexico City')],
          channels: const [],
        ).guide,
        isEmpty,
      );
    });

    test('groups channel copies by base name, best quality wins', () {
      final result = matchSportsEvent(
        _matchEvent(),
        listings: [
          _listing('TNT Sports 1 HD', 'Arsenal v Bayern Munich'),
          _listing('UK: TNT Sports 1 SD', 'Arsenal v Bayern Munich'),
          _listing('TNT Sports 1 4K', 'Arsenal v Bayern Munich'),
        ],
        channels: const [],
      );
      expect(result.guide, hasLength(1));
      expect(result.guide.single.channel.name, 'TNT Sports 1 4K');
      expect(result.guide.single.variants.map((c) => c.name), [
        'TNT Sports 1 HD',
        'UK: TNT Sports 1 SD',
      ]);
      expect(result.guide.single.listing?.channel.name, 'TNT Sports 1 4K');
    });

    test('quality ties keep the first listing in input order', () {
      final result = matchSportsEvent(
        _matchEvent(),
        listings: [
          _listing('UK: TNT Sports 1 HD', 'Arsenal v Bayern Munich'),
          _listing('TNT Sports 1 HD', 'Arsenal v Bayern Munich'),
        ],
        channels: const [],
      );
      expect(result.guide.single.channel.name, 'UK: TNT Sports 1 HD');
      expect(result.guide.single.variants.map((c) => c.name), [
        'TNT Sports 1 HD',
      ]);
    });

    test('guide options sort by start distance, then channel name', () {
      final result = matchSportsEvent(
        _matchEvent(),
        listings: [
          _listing(
            'Ziggo Sport',
            'Arsenal v Bayern Munich',
            start: _kickOff.add(const Duration(minutes: 30)),
            stop: _kickOff.add(const Duration(hours: 2)),
          ),
          _listing(
            'Arena Play',
            'Arsenal v Bayern Munich',
            start: _kickOff.subtract(const Duration(minutes: 45)),
            stop: _kickOff.add(const Duration(hours: 2)),
          ),
          _listing(
            'Beta One',
            'Arsenal v Bayern Munich',
            start: _kickOff.subtract(const Duration(minutes: 45)),
            stop: _kickOff.add(const Duration(hours: 2)),
          ),
        ],
        channels: const [],
      );
      expect(result.guide.map((o) => o.channel.name), [
        'Ziggo Sport',
        'Arena Play',
        'Beta One',
      ]);
    });
  });

  group('matchSportsEvent possible options', () {
    test('matches broadcaster names and numbered siblings', () {
      final result = matchSportsEvent(
        _matchEvent(broadcasts: ['TNT Sports', 'Sky Sports Main Event']),
        listings: const [],
        channels: [
          _channel('TNT Sports 1'),
          _channel('TNT Sports 2'),
          _channel('TNT Sports Extra'),
          _channel('Sky Sports Main Event 4K'),
        ],
      );
      expect(result.possible.map((o) => o.channel.name), [
        'TNT Sports 1',
        'TNT Sports 2',
        'Sky Sports Main Event 4K',
      ]);
      for (final option in result.possible) {
        expect(option.kind, SportsMatchKind.broadcaster);
        expect(option.listing, isNull);
        expect(option.variants, isEmpty);
      }
      expect(result.count, 3);
    });

    test('multi-digit suffixes match while words do not', () {
      final result = matchSportsEvent(
        _matchEvent(broadcasts: ['TNT Sports']),
        listings: const [],
        channels: [
          _channel('TNT Sports 10'),
          _channel('TNT Sports Extra'),
          _channel('TNT Sports 1 HD'),
        ],
      );
      expect(result.possible.map((o) => o.channel.name), [
        'TNT Sports 10',
        'TNT Sports 1 HD',
      ]);
    });

    test('exact broadcaster names match ignoring region and quality', () {
      final result = matchSportsEvent(
        _matchEvent(broadcasts: ['Sky Sports Main Event FHD']),
        listings: const [],
        channels: [
          _channel('UK: Sky Sports Main Event'),
          _channel('Sky Sports Main Event 4K'),
        ],
      );
      expect(result.possible, hasLength(1));
      expect(result.possible.single.channel.name, 'Sky Sports Main Event 4K');
      expect(result.possible.single.variants.map((c) => c.name), [
        'UK: Sky Sports Main Event',
      ]);
    });

    test('skips channels that already have a guide option', () {
      final result = matchSportsEvent(
        _matchEvent(broadcasts: ['TNT Sports']),
        listings: [_listing('UK: TNT Sports 1 HD', 'Arsenal v Bayern Munich')],
        channels: [_channel('TNT Sports 1'), _channel('TNT Sports 2')],
      );
      expect(result.guide, hasLength(1));
      expect(result.possible.map((o) => o.channel.name), ['TNT Sports 2']);
    });

    test('a channel matched by two broadcasters is offered once', () {
      final result = matchSportsEvent(
        _matchEvent(broadcasts: ['TNT Sports', 'TNT Sports 1']),
        listings: const [],
        channels: [_channel('TNT Sports 1')],
      );
      expect(result.possible, hasLength(1));
      expect(result.possible.single.channel.name, 'TNT Sports 1');
    });

    test('ignores blank broadcaster names and empty inputs', () {
      final result = matchSportsEvent(
        _matchEvent(broadcasts: ['  — ', 'TNT Sports']),
        listings: const [],
        channels: [_channel('TNT Sports 1')],
      );
      expect(result.possible, hasLength(1));
      expect(
        matchSportsEvent(
          _matchEvent(),
          listings: const [],
          channels: [_channel('TNT Sports 1')],
        ).possible,
        isEmpty,
      );
      expect(
        matchSportsEvent(
          _matchEvent(broadcasts: ['TNT Sports']),
          listings: const [],
          channels: const [],
        ).possible,
        isEmpty,
      );
    });

    test('keeps broadcaster order then channel order and caps at eight', () {
      final channels = <SportsChannelRef>[
        for (var i = 1; i <= 6; i++) _channel('TNT Sports $i'),
        for (var i = 1; i <= 6; i++) _channel('Sky Sports $i'),
      ];
      final result = matchSportsEvent(
        _matchEvent(broadcasts: ['Sky Sports', 'TNT Sports']),
        listings: const [],
        channels: channels,
      );
      expect(result.possible, hasLength(8));
      expect(result.possible.map((o) => o.channel.name), [
        'Sky Sports 1',
        'Sky Sports 2',
        'Sky Sports 3',
        'Sky Sports 4',
        'Sky Sports 5',
        'Sky Sports 6',
        'TNT Sports 1',
        'TNT Sports 2',
      ]);
    });

    test('a non-team event can be matched by broadcaster too', () {
      final result = matchSportsEvent(
        _raceEvent(broadcasts: ['Sky Sports F1']),
        listings: const [],
        channels: [_channel('UK: Sky Sports F1 HD')],
      );
      expect(result.possible.single.channel.name, 'UK: Sky Sports F1 HD');
    });
  });

  group('new sports', () {
    SportsEvent titled(
      String leagueId,
      String title, {
      SportsEventStatus? status,
      DateTime? start,
    }) => SportsEvent(
      id: '$leagueId-1',
      leagueId: leagueId,
      start: start ?? _kickOff,
      status: status ?? SportsEventStatus.scheduled,
      title: title,
    );

    List<String> guideNames(
      SportsEvent event,
      List<SportsGuideListing> listings, {
      DateTime? now,
    }) => matchSportsEvent(
      event,
      listings: listings,
      channels: const [],
      now: now,
    ).guide.map((o) => o.channel.name).toList();

    test('a fight card matches a UFC listing naming either fighter', () {
      final card = titled('ufc', 'UFC Fight Night: Moicano vs. Nolan');
      expect(sportsTitleNeedles(card), ['moicano', 'nolan']);
      expect(
        guideNames(card, [
          _listing(
            'Sony Ten 2',
            'UFC Fight Night: Moicano v Nolan - Main Card',
          ),
          _listing('TNT Sports 1', 'UFC 312 Prelims: Nolan v Silva'),
          _listing('News 24', 'Moicano interview'),
        ]),
        ['Sony Ten 2', 'TNT Sports 1'],
      );
    });

    test('fighter needles skip suffixes, short names and vs-less titles', () {
      expect(
        sportsTitleNeedles(titled('ufc', 'UFC 320: Ankalaev vs. Pereira Jr.')),
        ['ankalaev', 'pereira'],
      );
      expect(
        sportsTitleNeedles(titled('ufc', 'UFC Fight Night: Lee vs. Ko')),
        isEmpty,
      );
      expect(sportsTitleNeedles(titled('ufc', 'UFC 310')), isEmpty);
    });

    test('a golf tournament matches without its sponsor name', () {
      final golf = titled('pga', 'VidantaWorld Mexico Open');
      expect(sportsTitleNeedles(golf), ['mexico open', 'pga tour golf']);
      expect(
        guideNames(golf, [
          _listing('Golf Channel', 'PGA Tour Golf: Mexico Open, Round 1'),
          _listing('Travel HD', 'Mexico Open Road Trip'),
        ]),
        ['Golf Channel'],
      );
    });

    test('live tour coverage counts for the tour\'s event of the week', () {
      final pga = titled('pga', 'VidantaWorld Mexico Open');
      final lpga = titled('lpga', 'Maybank Championship');
      final listings = [
        _listing('US: GOLF CHANNEL HD', 'Live: PGA Tour Golf'),
        _listing('Golf Replay', 'PGA Tour Golf'),
        _listing('Champions TV', 'Live: PGA Tour Champions Golf'),
        _listing('Golf Channel LPGA', 'Live: LPGA Tour Golf'),
      ];
      // Live only, and not the Champions tour.
      expect(guideNames(pga, listings), ['US: GOLF CHANNEL HD']);
      expect(guideNames(lpga, listings), ['Golf Channel LPGA']);
      // With two PGA events on (an opposite-field week), untitled tour
      // coverage could be either: only a title naming the event counts.
      final shared = matchSportsEvent(
        pga,
        listings: listings,
        channels: const [],
        now: _kickOff,
        tourCoverage: false,
      );
      expect(shared.guide, isEmpty);
    });

    test('a cricket listing by country codes names the game', () {
      final test = SportsEvent(
        id: 'rsa-aus',
        leagueId: 'intl-cricket',
        start: _kickOff,
        status: SportsEventStatus.live,
        home: _team('sa', 'South Africa', shortName: 'S Africa'),
        away: _team('aus', 'Australia'),
      );
      expect(sportsCodePairs(test), contains('rsa v aus'));
      expect(sportsTitleNeedles(test), contains('rsa v aus'));
      expect(
        guideNames(test, [
          _listing('SuperSport Cricket', "Int CRI '26: RSA v AUS 3rd Test D4"),
          _listing('SS Grandstand', "Int CRI HL '26: RSA v AUS 3rd Test D4"),
          _listing('Some Channel', 'Australia aus documentary'),
          // Same countries, other games: rugby, the women's side.
          _listing('SuperSport Rugby', 'Rugby Championship: RSA v AUS'),
          _listing('SS Rugby', 'Rugby Championship Test: RSA v AUS'),
          _listing('Fox Netball', 'Constellation Cup Test: AUS v RSA Netball'),
          _listing('SS Variety', "Int CRI W '26: RSA v AUS 1st T20"),
        ]),
        ['SuperSport Cricket'],
      );
      // Codes are a cricket thing only.
      expect(sportsCodePairs(_matchEvent()), isEmpty);
    });

    test('a NASCAR race matches by its venue', () {
      final race = titled('nascar', 'NASCAR Cup Series at Martinsville');
      expect(sportsTitleNeedles(race), ['martinsville']);
      expect(
        guideNames(race, [
          _listing('FS1', 'NASCAR Cup Series: Martinsville'),
          _listing('Local News', 'Martinsville weather'),
        ]),
        ['FS1'],
      );
    });

    test('a live multi-day match matches today\'s broadcast', () {
      final test = SportsEvent(
        id: 'test-1',
        leagueId: 'intl-cricket',
        start: _kickOff.subtract(const Duration(days: 2)),
        status: SportsEventStatus.live,
        home: _team('sa', 'South Africa'),
        away: _team('aus', 'Australia'),
      );
      final today = _listing(
        'SuperSport Cricket',
        'Live Cricket: South Africa v Australia, 3rd Test Day 3',
        start: _kickOff.subtract(const Duration(hours: 1)),
        stop: _kickOff.add(const Duration(hours: 7)),
      );
      expect(
        guideNames(test, [today]),
        isEmpty,
        reason: 'without now, day 3 is too far from the start',
      );
      expect(guideNames(test, [today], now: _kickOff), ['SuperSport Cricket']);
      final scheduled = SportsEvent(
        id: 'test-2',
        leagueId: 'intl-cricket',
        start: _kickOff.subtract(const Duration(days: 2)),
        status: SportsEventStatus.finished,
        home: _team('sa', 'South Africa'),
        away: _team('aus', 'Australia'),
      );
      expect(guideNames(scheduled, [today], now: _kickOff), isEmpty);
    });

    test(
      'at stumps, short news and highlights slots are not the broadcast',
      () {
        // Real Fox Sports News listings on day 3 of a Test (2026-10-30), when
        // play had stopped for the day and the board offered the next "Mini".
        final test = SportsEvent(
          id: 'test-1',
          leagueId: 'intl-cricket',
          start: _kickOff.subtract(const Duration(days: 3)),
          status: SportsEventStatus.live,
          home: _team('sa', 'South Africa'),
          away: _team('aus', 'Australia'),
        );
        final now = _kickOff;
        final mini = _listing(
          'Fox Sports News',
          'South Africa v Australia Mini - 3rd Test Day 3',
          start: now.add(const Duration(minutes: 25)),
          stop: now.add(const Duration(minutes: 45)),
        );
        final hourShow = _listing(
          'Fox Sports News',
          'South Africa v Australia - 3rd Test Day 2',
          start: now.subtract(const Duration(minutes: 30)),
          stop: now.add(const Duration(minutes: 30)),
        );
        final live = _listing(
          'SABC 3',
          'Cricket South Africa Vs Australia',
          start: now.add(const Duration(hours: 1)),
          stop: now.add(const Duration(hours: 3, minutes: 30)),
        );
        expect(guideNames(test, [mini, hourShow], now: now), isEmpty);
        expect(guideNames(test, [mini, hourShow, live], now: now), ['SABC 3']);
      },
    );

    test('a delayed single-day game still matches an hour-long slot', () {
      final late = SportsEvent(
        id: 't20-1',
        leagueId: 'intl-cricket',
        start: _kickOff,
        status: SportsEventStatus.live,
        home: _team('sa', 'South Africa'),
        away: _team('aus', 'Australia'),
      );
      // Rain: play started three hours late, in the guide's hourly slots.
      final now = _kickOff.add(const Duration(hours: 3, minutes: 10));
      final slot = _listing(
        'SuperSport Cricket',
        'Live Cricket: South Africa v Australia, 1st T20',
        start: _kickOff.add(const Duration(hours: 3)),
        stop: _kickOff.add(const Duration(hours: 4)),
      );
      expect(guideNames(late, [slot], now: now), ['SuperSport Cricket']);
    });

    test('"mini" highlights never match, even at kick-off', () {
      expect(
        guideNames(_matchEvent(), [
          _listing('Fox Sports News', 'Arsenal v Bayern Mini'),
        ]),
        isEmpty,
      );
    });
  });

  group('channels named for the match', () {
    SportsWatchOptions match({
      List<SportsGuideListing> listings = const [],
      List<SportsChannelRef> channels = const [],
      required List<SportsChannelRef> named,
      List<String> broadcasts = const [],
    }) => matchSportsEvent(
      _matchEvent(broadcasts: broadcasts),
      listings: listings,
      channels: channels,
      namedChannels: named,
      now: _kickOff,
    );

    test('an event stream naming both teams is a watch option', () {
      final options = match(
        named: [
          _channel('UEFA 03: Arsenal vs Bayern Munich FHD'),
          _channel('UEFA 03: Arsenal vs Bayern Munich HD'),
        ],
      );
      expect(options.guide, hasLength(1));
      final option = options.guide.single;
      expect(option.kind, SportsMatchKind.channelName);
      expect(option.listing, isNull);
      // Copies of one stream merge, the sharper one leading.
      expect(option.channel.name, 'UEFA 03: Arsenal vs Bayern Munich FHD');
      expect(
        option.variants.single.name,
        'UEFA 03: Arsenal vs Bayern Munich HD',
      );
    });

    test('guide listings come first, then named channels', () {
      final options = match(
        listings: _specListings(),
        named: [_channel('Events 1: Arsenal v Bayern')],
      );
      expect(options.guide.map((o) => o.kind), [
        SportsMatchKind.guide,
        SportsMatchKind.channelName,
      ]);
    });

    test('a club channel holding both names is not the derby', () {
      final derby = SportsEvent(
        id: 'sa-1',
        leagueId: 'ucl',
        start: _kickOff,
        status: SportsEventStatus.live,
        home: _team('int', 'Internazionale'),
        away: _team('mil', 'AC Milan'),
      );
      final options = matchSportsEvent(
        derby,
        listings: const [],
        channels: const [],
        namedChannels: [
          _channel('Inter Milan TV'),
          _channel('Serie A 01: Inter vs Milan'),
        ],
        now: _kickOff,
      );
      expect(options.guide.map((o) => o.channel.name), [
        'Serie A 01: Inter vs Milan',
      ]);
    });

    test('same-day streams lead, then undated, then a day off', () {
      final options = match(
        named: [
          _channel('NEXT | Arsenal vs Bayern | Tue 27 Oct 12:00'),
          _channel('UCL 02: Arsenal vs Bayern'),
          _channel('US (CBS 01) | Arsenal vs. Bayern (2026-10-28 19:55:00)'),
        ],
      );
      expect(options.guide.map((o) => o.channel.name), [
        'US (CBS 01) | Arsenal vs. Bayern (2026-10-28 19:55:00)',
        'UCL 02: Arsenal vs Bayern',
        'NEXT | Arsenal vs Bayern | Tue 27 Oct 12:00',
      ]);
    });

    test('a channel naming one team, or a recap, is not', () {
      final options = match(
        listings: _specListings(),
        named: [
          _channel('Arsenal TV'),
          _channel('Arsenal v Bayern Highlights'),
        ],
      );
      expect(
        options.guide.where((o) => o.kind == SportsMatchKind.channelName),
        isEmpty,
      );
    });

    test('a named channel is not offered again as a possible one', () {
      final options = match(
        named: [_channel('Arsenal v Bayern')],
        channels: [_channel('Arsenal v Bayern')],
        broadcasts: const ['Arsenal v Bayern'],
      );
      expect(options.guide, hasLength(1));
      expect(options.possible, isEmpty);
    });

    test('non-team events never match by channel name', () {
      final options = matchSportsEvent(
        _raceEvent(),
        listings: const [],
        channels: const [],
        namedChannels: [_channel('Mexico City Grand Prix 24/7')],
      );
      expect(options.isEmpty, isTrue);
    });
  });

  test('a short broadcaster name finds the channel under its full name', () {
    final golf = SportsEvent(
      id: 'pga-1',
      leagueId: 'pga',
      start: _kickOff,
      status: SportsEventStatus.live,
      title: 'VidantaWorld Mexico Open',
      broadcasts: const ['Golf Chnl'],
    );
    final options = matchSportsEvent(
      golf,
      listings: const [],
      channels: [_channel('US: GOLF CHANNEL HD'), _channel('Golf TV')],
      now: _kickOff,
    );
    expect(options.possible.map((o) => o.channel.name), [
      'US: GOLF CHANNEL HD',
    ]);
    expect(sportsBroadcasterNeedles('Golf Chnl'), [
      'golf chnl',
      'golf channel',
      'nbc golf',
    ]);
    expect(sportsBroadcasterNeedles('ESPN'), ['espn']);
  });

  group('tennis surnames', () {
    final match = SportsEvent(
      id: 'wta-1',
      leagueId: 'wta',
      start: _kickOff,
      status: SportsEventStatus.live,
      home: _team('ds', 'Diana Shnaider', shortName: 'D. Shnaider'),
      away: _team('mp', 'Mia Pohankova', shortName: 'M. Pohankova'),
    );

    test('a player is also known by surname', () {
      expect(sportsSideVariants(match, match.home!), contains('shnaider'));
      // Team sports keep their names as they are.
      final game = _matchEvent();
      expect(sportsSideVariants(game, game.home!), ['arsenal']);
    });

    test('guide titles and stream names by surname both match', () {
      final options = matchSportsEvent(
        match,
        listings: [
          _listing('Tennis Channel', 'WTA Tokyo: Shnaider v Pohankova'),
        ],
        channels: const [],
        namedChannels: [_channel('TENNIS 02: Shnaider vs Pohankova')],
        now: _kickOff,
      );
      expect(options.guide.map((o) => o.kind), [
        SportsMatchKind.guide,
        SportsMatchKind.channelName,
      ]);
    });
  });

  test(
    'sportsEventNeedles: both teams for a game, title needles otherwise',
    () {
      expect(sportsEventNeedles(_matchEvent()).sides, [
        ['arsenal'],
        ['bayern munich', 'bayern', 'bayern munchen', 'fc bayern'],
      ]);
      expect(sportsEventNeedles(_raceEvent()).sides, [
        ['mexico city'],
      ]);
    },
  );
}

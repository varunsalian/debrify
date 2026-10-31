// Channel names as event streams: which names are this game's stream.
import 'package:debrify/features/sports/application/sports_stream_names.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sportsChannelNamesMatch', () {
    const india = ['india'];
    const australia = ['australia'];
    bool names(String name) => sportsChannelNamesMatch(name, india, australia);

    test('an event stream names both sides around a separator', () {
      expect(names('CRICKET 05: India vs Australia'), isTrue);
      expect(names('IN | Australia v India FHD'), isTrue);
      expect(names('India x Australia'), isTrue);
      expect(names('India - Australia (1st ODI)'), isTrue);
      expect(names('Australia @ India'), isTrue);
    });

    test('another team of the same name is not this match', () {
      expect(names('CRICKET 05: India Women vs Australia Women'), isFalse);
      expect(names('India vs Australia Women'), isFalse);
      expect(names('India U19 vs Australia U19'), isFalse);
      expect(names('India A vs Australia A'), isFalse);
    });

    test('replays, loops and one-side names are not live streams', () {
      expect(names('India vs Australia Highlights'), isFalse);
      expect(names('India v Australia Classic'), isFalse);
      expect(names('India vs Australia 24/7'), isFalse);
      expect(names('India TV Australia'), isFalse);
      expect(names('Star Sports India'), isFalse);
    });

    test('a stream dated days away is another game', () {
      final around = DateTime.utc(2026, 10, 31, 12);
      bool dated(String name) =>
          sportsChannelNamesMatch(name, india, australia, around: around);
      expect(dated('India vs Australia (2026-10-31 22:30:00)'), isTrue);
      // A local date across midnight is still the same game.
      expect(dated('India v Australia (2026-11-01 01:50:50)'), isTrue);
      expect(dated('India vs Australia // UK Sun 18 May 1:30pm'), isFalse);
      expect(dated('India vs Australia | all | 29-10-2026 | 08:30'), isFalse);
      expect(dated('India vs Australia @ Oct 28 21:25'), isFalse);
      expect(dated('NFL | 02 - 1pm India at Australia'), isTrue);
      expect(sportsChannelNameDayGap('Fri 30 Oct 12:00 EDT', around), 1);
      expect(sportsChannelNameDayGap('No date here', around), isNull);
    });

    test('an ended stream, a press conference or another sport is not', () {
      expect(names('End | India vs Australia | all'), isFalse);
      expect(names('PERSCONFERENTIE | India - Australia'), isFalse);
      expect(names('Goal Rush: India v Australia'), isFalse);
      bool cricket(String name) => sportsChannelNamesMatch(
        name,
        india,
        australia,
        sport: SportKind.cricket,
      );
      expect(cricket('Volleyball: India vs Australia'), isFalse);
      expect(cricket('Soccer (W): India at Australia'), isFalse);
      expect(cricket('live: India vs Australia _ Cricket'), isTrue);
      // A provider's "SOCCER PPV" group label after the teams is fine.
      expect(cricket('Next | India vs Australia | US: SOCCER PPV 26'), isTrue);
    });

    test('a women\'s event keeps its own Women', () {
      const thunder = ['sydney thunder women'];
      const renegades = ['melbourne renegades women'];
      expect(
        sportsChannelNamesMatch(
          'live: Sydney Thunder vs Melbourne Renegades _ Women`s Cricket',
          thunder,
          renegades,
        ),
        isTrue,
      );
      expect(
        sportsChannelNamesMatch(
          'Frauen: Sydney Thunder vs Melbourne Renegades',
          thunder,
          renegades,
        ),
        isTrue,
      );
      // The men's stream says nothing about women: not the women's game.
      expect(
        sportsChannelNamesMatch(
          'CRICKET 01: Sydney Thunder vs Melbourne Renegades',
          thunder,
          renegades,
        ),
        isFalse,
      );
    });

    test('team names that start like a month are not dates', () {
      final around = DateTime.utc(2026, 10, 31, 12);
      expect(
        sportsChannelNameDayGap('Mainz vs Augsburg 15:30', around),
        isNull,
      );
      expect(
        sportsChannelNameDayGap('Braves vs Miami Marlins 19:05', around),
        isNull,
      );
      expect(sportsChannelNameDayGap('Marseille 2 Lens', around), isNull);
      expect(sportsChannelNameDayGap('Sat 31 October', around), 0);
      expect(sportsChannelNameDayGap('Sept 30 kick-off', around), 31);
    });

    test('a US-style date counts as well as a European one', () {
      final nov1 = DateTime.utc(2026, 11, 1, 12);
      expect(sportsChannelNameDayGap('Game | 11/01/2026 | 20:00', nov1), 0);
      expect(sportsChannelNameDayGap('Game | 01/11/2026 | 20:00', nov1), 0);
    });

    test('tennis names may carry country codes and seeds', () {
      bool tennis(String name) => sportsChannelNamesMatch(
        name,
        const ['jannik sinner', 'sinner'],
        const ['carlos alcaraz', 'alcaraz'],
        sport: SportKind.tennis,
      );
      expect(tennis('TENNIS 01: Sinner (ITA) vs Alcaraz (ESP)'), isTrue);
      expect(tennis('[1] Sinner vs [2] Alcaraz'), isTrue);
      expect(tennis('Sinner Alcaraz'), isFalse);
      // Only tennis gets the leeway.
      expect(
        sportsChannelNamesMatch(
          'Arsenal ENG vs Bayern',
          const ['arsenal'],
          const ['bayern'],
        ),
        isFalse,
      );
    });

    test('a kick-off time "a las" is not an A team', () {
      expect(
        sportsChannelNamesMatch(
          'LaLiga: Real Madrid vs Barcelona a las 21:00',
          const ['real madrid'],
          const ['barcelona'],
        ),
        isTrue,
      );
      expect(names('India vs Australia A'), isFalse);
    });

    test('one name cannot count for both sides', () {
      expect(
        sportsChannelNamesMatch(
          'Inter Milan TV',
          const ['internazionale', 'inter', 'inter milan'],
          const ['ac milan', 'milan'],
        ),
        isFalse,
      );
    });
  });
}

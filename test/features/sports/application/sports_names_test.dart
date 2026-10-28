import 'package:debrify/features/sports/application/sports_names.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

SportsTeam team({
  String id = '1',
  required String name,
  String? shortName,
  String abbreviation = 'ABC',
}) => SportsTeam(
  id: id,
  name: name,
  shortName: shortName ?? name,
  abbreviation: abbreviation,
);

void main() {
  group('normalizeSportsText', () {
    test('folds the documented examples', () {
      expect(normalizeSportsText('Bayern München'), 'bayern munchen');
      expect(
        normalizeSportsText('Brighton & Hove Albion'),
        'brighton hove albion',
      );
      expect(normalizeSportsText('  PSG–OM!! '), 'psg om');
    });

    test('lowercases and keeps digits', () {
      expect(normalizeSportsText('Tottenham HOTSPUR'), 'tottenham hotspur');
      expect(normalizeSportsText('Inter 2025'), 'inter 2025');
      expect(normalizeSportsText('NBA76ers'), 'nba76ers');
    });

    test('folds every documented accent to its ASCII form', () {
      expect(normalizeSportsText('á à â ä ã å ā'), 'a a a a a a a');
      expect(normalizeSportsText('é è ê ë ē'), 'e e e e e');
      expect(normalizeSportsText('í ì î ï'), 'i i i i');
      expect(normalizeSportsText('ó ò ô ö õ ø'), 'o o o o o o');
      expect(normalizeSportsText('ú ù û ü'), 'u u u u');
      expect(normalizeSportsText('ñ ç'), 'n c');
      expect(normalizeSportsText('ß'), 'ss');
      expect(normalizeSportsText('æ œ'), 'ae oe');
    });

    test('folds accents that arrive uppercase', () {
      expect(normalizeSportsText('MÜNCHEN'), 'munchen');
      expect(normalizeSportsText('COPENHAGUE Æ'), 'copenhague ae');
    });

    test('folds inside words', () {
      expect(normalizeSportsText('Straße'), 'strasse');
      expect(normalizeSportsText('Atlético'), 'atletico');
      expect(normalizeSportsText('Cæsar'), 'caesar');
      expect(normalizeSportsText('Mölde'), 'molde');
    });

    test('every other character becomes a single space', () {
      expect(normalizeSportsText('a,b.c/d_e+f'), 'a b c d e f');
      expect(normalizeSportsText('Live\tFootball\nNow'), 'live football now');
      expect(normalizeSportsText('Sky ᴴᴰ Sports'), 'sky sports');
    });

    test('characters without a fold are dropped like any other symbol', () {
      expect(normalizeSportsText('Wisła Kraków'), 'wis a krakow');
    });

    test('collapses runs of spaces and trims', () {
      expect(
        normalizeSportsText('   many    spaces   here   '),
        'many spaces here',
      );
      expect(normalizeSportsText('---***---'), '');
      expect(normalizeSportsText(''), '');
      expect(normalizeSportsText('!!!'), '');
    });
  });

  group('sportsTextContains', () {
    test('matches whole words only', () {
      expect(sportsTextContains('arsenal v bayern', 'arsenal'), isTrue);
      expect(sportsTextContains('tottenham hotspur', 'tottenham'), isTrue);
      expect(sportsTextContains('newcastle united', 'new'), isFalse);
      expect(sportsTextContains('man utd', 'united'), isFalse);
      expect(sportsTextContains('inter milan', 'inter'), isTrue);
      expect(sportsTextContains('printemps', 'temp'), isFalse);
    });

    test('matches multi-word needles as a phrase', () {
      expect(sportsTextContains('west ham united', 'west ham'), isTrue);
      expect(sportsTextContains('man utd', 'man city'), isFalse);
      expect(
        sportsTextContains('mexico city grand prix', 'mexico city'),
        isTrue,
      );
    });

    test('an empty needle never matches', () {
      expect(sportsTextContains('arsenal', ''), isFalse);
      expect(sportsTextContains('', ''), isFalse);
    });

    test('an empty haystack matches nothing but never throws', () {
      expect(sportsTextContains('', 'arsenal'), isFalse);
    });
  });

  group('teamNameVariants', () {
    test('follows the documented AFC Bournemouth example', () {
      expect(
        teamNameVariants(
          const SportsTeam(
            id: 'bournemouth',
            name: 'AFC Bournemouth',
            shortName: 'Bournemouth',
            abbreviation: 'BOU',
          ),
        ),
        ['afc bournemouth', 'bournemouth'],
      );
    });

    test('orders name, short name, aliases, then token-stripped name', () {
      expect(
        teamNameVariants(
          team(name: 'Manchester United', shortName: 'Man United'),
        ),
        ['manchester united', 'man united', 'man utd'],
      );
    });

    test('adds aliases in catalog order and keeps the first spelling', () {
      expect(
        teamNameVariants(team(name: 'Tottenham Hotspur', shortName: 'Spurs')),
        ['tottenham hotspur', 'spurs', 'tottenham'],
      );
      expect(
        teamNameVariants(team(name: 'Internazionale', shortName: 'Inter')),
        ['internazionale', 'inter', 'inter milan'],
      );
    });

    test('drops variants shorter than four characters', () {
      // `psg` and `bvb` are known aliases but too short to match a title.
      expect(
        teamNameVariants(team(name: 'Paris Saint-Germain', shortName: 'PSG')),
        ['paris saint germain', 'paris sg'],
      );
      expect(
        teamNameVariants(
          team(name: 'Borussia Dortmund', shortName: 'Dortmund'),
        ),
        ['borussia dortmund', 'dortmund'],
      );
    });

    test('removes generic club tokens as whole words', () {
      expect(
        teamNameVariants(team(name: 'FC Bayern München', shortName: 'Bayern')),
        ['fc bayern munchen', 'bayern', 'bayern munchen'],
      );
      expect(teamNameVariants(team(name: 'AC Milan', shortName: 'Milan')), [
        'ac milan',
        'milan',
      ]);
      expect(
        teamNameVariants(team(name: 'Sporting Club Braga', shortName: 'Braga')),
        ['sporting club braga', 'braga', 'sporting braga'],
      );
      // Tokens are only removed as whole words, never inside a word.
      expect(
        teamNameVariants(team(name: 'Ascension FC', shortName: 'Ascension')),
        ['ascension fc', 'ascension'],
      );
    });

    test('looks aliases up by normalized name', () {
      expect(
        teamNameVariants(team(name: 'Bayern Munich', shortName: 'Bayern')),
        ['bayern munich', 'bayern', 'bayern munchen', 'fc bayern'],
      );
      expect(
        teamNameVariants(team(name: 'Sporting CP', shortName: 'Sporting')),
        ['sporting cp', 'sporting', 'sporting lisbon'],
      );
    });

    test('returns a single variant for an unknown short team', () {
      expect(teamNameVariants(team(name: 'Real Betis', shortName: 'Betis')), [
        'real betis',
        'betis',
      ]);
      expect(teamNameVariants(team(name: 'FC Porto', shortName: 'Porto')), [
        'fc porto',
        'porto',
      ]);
    });

    test('never returns duplicates, an empty name or a too-short name', () {
      final variants = teamNameVariants(team(name: 'FC', shortName: ''));
      expect(variants, isEmpty);
      final single = teamNameVariants(
        team(name: 'Wolves', shortName: 'Wolves'),
      );
      expect(single, ['wolves']);
    });

    test('every variant is normalized and free of duplicates', () {
      final variants = teamNameVariants(
        team(name: 'Brighton & Hove Albion', shortName: 'Brighton'),
      );
      expect(variants, ['brighton hove albion', 'brighton']);
      expect(variants.toSet().length, variants.length);
      for (final variant in variants) {
        expect(variant, normalizeSportsText(variant));
        expect(variant.length, greaterThanOrEqualTo(4));
      }
    });
  });

  group('kSportsTeamAliases', () {
    test('keys and values are already normalized', () {
      kSportsTeamAliases.forEach((key, aliases) {
        expect(key, normalizeSportsText(key), reason: 'key $key');
        for (final alias in aliases) {
          expect(alias, normalizeSportsText(alias), reason: 'alias $alias');
        }
      });
    });

    test('holds the documented catalog', () {
      expect(kSportsTeamAliases.length, 19);
      expect(kSportsTeamAliases['manchester united'], [
        'man utd',
        'man united',
      ]);
      expect(kSportsTeamAliases['manchester city'], ['man city']);
      expect(kSportsTeamAliases['tottenham hotspur'], ['spurs', 'tottenham']);
      expect(kSportsTeamAliases['paris saint germain'], ['psg', 'paris sg']);
      expect(kSportsTeamAliases['bayern munich'], [
        'bayern',
        'bayern munchen',
        'fc bayern',
      ]);
      expect(kSportsTeamAliases['internazionale'], ['inter', 'inter milan']);
      expect(kSportsTeamAliases['ac milan'], ['milan']);
      expect(kSportsTeamAliases['atletico madrid'], ['atletico', 'atleti']);
      expect(kSportsTeamAliases['borussia dortmund'], ['dortmund', 'bvb']);
      expect(kSportsTeamAliases['wolverhampton wanderers'], ['wolves']);
      expect(kSportsTeamAliases['brighton hove albion'], ['brighton']);
      expect(kSportsTeamAliases['newcastle united'], ['newcastle']);
      expect(kSportsTeamAliases['west ham united'], ['west ham']);
      expect(kSportsTeamAliases['nottingham forest'], [
        'nottm forest',
        'forest',
      ]);
      expect(kSportsTeamAliases['afc bournemouth'], ['bournemouth']);
      expect(kSportsTeamAliases['leeds united'], ['leeds']);
      expect(kSportsTeamAliases['bayer leverkusen'], ['leverkusen']);
      expect(kSportsTeamAliases['real betis'], ['betis']);
      expect(kSportsTeamAliases['sporting cp'], [
        'sporting lisbon',
        'sporting',
      ]);
    });
  });

  group('channelBaseName', () {
    test('follows the documented examples', () {
      expect(
        channelBaseName('UK: Sky Sports Main Event FHD'),
        'sky sports main event',
      );
      expect(channelBaseName('|UK| TNT Sports 1 ᴴᴰ'), 'tnt sports 1');
      expect(channelBaseName('TNT Sports 1 4K'), 'tnt sports 1');
    });

    test('removes every leading region tag spelling', () {
      expect(channelBaseName('UK | Sky Sports Golf'), 'sky sports golf');
      expect(channelBaseName('[UK] Sky Sports Golf'), 'sky sports golf');
      expect(channelBaseName('(UK) Sky Sports Golf'), 'sky sports golf');
      expect(channelBaseName('┃UK┃ Sky Sports Golf'), 'sky sports golf');
      expect(channelBaseName('US - ESPN 2'), 'espn 2');
      expect(channelBaseName('  uk :  Sky Sports Golf'), 'sky sports golf');
      expect(channelBaseName('|USA| NBA TV'), 'nba tv');
    });

    test('leaves names that are not region tags alone', () {
      expect(channelBaseName('Sky Sports Main Event'), 'sky sports main event');
      expect(channelBaseName('UK'), 'uk');
      expect(channelBaseName('BBC One'), 'bbc one');
      expect(channelBaseName('ITV4'), 'itv4');
      expect(channelBaseName('ESPN 2'), 'espn 2');
      expect(channelBaseName('Sky Sports News UK'), 'sky sports news uk');
    });

    test(
      'a leading 3-letter word before a separator reads as a region tag',
      () {
        // Documented consequence of the region-tag pattern in the spec.
        expect(channelBaseName('Sky: Sports'), 'sports');
      },
    );

    test('drops quality tokens as whole words only', () {
      expect(channelBaseName('Sky Sports F1 HD Raw'), 'sky sports f1');
      expect(channelBaseName('Sky Sports F1 4K'), 'sky sports f1');
      expect(channelBaseName('Sky Sports F1 2160p 50fps'), 'sky sports f1');
      expect(channelBaseName('Sky Sports F1 HEVC'), 'sky sports f1');
      expect(channelBaseName('Sky Sports F1 H264'), 'sky sports f1');
      expect(channelBaseName('Sky Sports F1 Backup'), 'sky sports f1');
      expect(channelBaseName('Sky Sports 8k UHD'), 'sky sports');
      expect(channelBaseName('Hollywood TV HD'), 'hollywood tv');
      expect(channelBaseName('SkyHD'), 'skyhd');
    });

    test('collapses the gaps left by removed tokens and trims', () {
      expect(channelBaseName('UK: TNT Sports 1 HD'), 'tnt sports 1');
      expect(channelBaseName('HD TNT Sports 1'), 'tnt sports 1');
      expect(channelBaseName('   '), '');
      expect(channelBaseName('!!!'), '');
      expect(channelBaseName('4K'), '');
    });
  });

  group('channelQualityRank', () {
    test('ranks ultra HD, full HD and HD', () {
      expect(channelQualityRank('TNT Sports 1 4K'), 3);
      expect(channelQualityRank('TNT Sports 1 UHD'), 3);
      expect(channelQualityRank('TNT Sports 1 2160p'), 3);
      expect(channelQualityRank('TNT Sports 1 FHD'), 2);
      expect(channelQualityRank('TNT Sports 1 1080p'), 2);
      expect(channelQualityRank('UK: TNT Sports 1 HD'), 1);
      expect(channelQualityRank('TNT Sports 1 720p'), 1);
    });

    test('the best token wins', () {
      expect(channelQualityRank('TNT Sports 1 HD 4K'), 3);
      expect(channelQualityRank('TNT Sports 1 HD FHD'), 2);
    });

    test('returns 0 without a quality token', () {
      expect(channelQualityRank('TNT Sports 1'), 0);
      expect(channelQualityRank('TNT Sports 1 ᴴᴰ'), 0);
      expect(channelQualityRank('SkyHD'), 0);
      expect(channelQualityRank(''), 0);
    });
  });
}

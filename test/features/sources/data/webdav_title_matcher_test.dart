import 'package:debrify/features/sources/data/webdav_release_name.dart';
import 'package:debrify/features/sources/data/webdav_title_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

WebDavTitleMatcher movie(String title, [String? year]) => WebDavTitleMatcher(
  WebDavMatchTarget(title: title, year: year, isSeries: false),
);

WebDavTitleMatcher episode(
  String title,
  int season,
  int episode, [
  String? year,
]) => WebDavTitleMatcher(
  WebDavMatchTarget(
    title: title,
    year: year,
    isSeries: true,
    season: season,
    episode: episode,
  ),
);

void main() {
  group('release names', () {
    test('cut the title at the year, episode or a technical tag', () {
      final release = WebDavReleaseName.parse(
        'The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv',
        isFile: true,
      );
      expect(release.titleKey, 'the matrix');
      expect(release.year, 1999);

      final show = WebDavReleaseName.parse(
        'Breaking.Bad.S01E03.720p.mkv',
        isFile: true,
      );
      expect(show.titleKey, 'breaking bad');
      expect((show.season, show.episode), (1, 3));
    });

    test('a leading year is the title, and title words stay', () {
      expect(WebDavReleaseName.parse('1917 (2019)').titleKey, '1917');
      expect(WebDavReleaseName.parse('1917 (2019)').year, 2019);
      expect(
        WebDavReleaseName.parse('A Series of Unfortunate Events').titleKey,
        'a series of unfortunate events',
      );
      expect(
        WebDavReleaseName.parse('A Complete Unknown (2024)').titleKey,
        'a complete unknown',
      );
    });

    test('episode forms: SxxEyy, multi, 1x02, words, and bare numbers', () {
      final multi = WebDavReleaseName.parse('Show.S02E05E06.mkv', isFile: true);
      expect((multi.season, multi.episode, multi.episodeEnd), (2, 5, 6));
      expect(multi.coversEpisode(6), isTrue);
      expect(multi.coversEpisode(7), isFalse);

      final cross = WebDavReleaseName.parse('Show 3x07.mkv', isFile: true);
      expect((cross.season, cross.episode), (3, 7));

      final words = WebDavReleaseName.parse(
        'Show Season 2 Episode 4.mp4',
        isFile: true,
      );
      expect((words.season, words.episode), (2, 4));

      final bare = WebDavReleaseName.parse(
        '03 - Pilot.mkv',
        isFile: true,
        bareEpisodes: true,
      );
      expect((bare.season, bare.episode), (null, 3));
      // Outside a series folder a leading number is a title ("300").
      expect(
        WebDavReleaseName.parse('03 - Pilot.mkv', isFile: true).episode,
        isNull,
      );

      final dashed = WebDavReleaseName.parse(
        '[Group] Show - 05 (1080p).mkv',
        isFile: true,
        bareEpisodes: true,
      );
      expect(dashed.episode, 5);
      expect(dashed.titleKey, 'show');
    });

    test('a resolution or year is never read as an episode', () {
      expect(
        WebDavReleaseName.parse('1080p.mkv', isFile: true).episode,
        isNull,
      );
      expect(WebDavReleaseName.parse('2012.mkv', isFile: true).episode, isNull);
    });

    test('folding ignores apostrophes and spells & as and', () {
      expect(WebDavReleaseName.fold("Grey's Anatomy"), 'greys anatomy');
      expect(WebDavReleaseName.fold('Law & Order'), 'law and order');
    });
  });

  group('movies', () {
    test('a title folder opens; another year or a sequel does not', () {
      final dune = movie('Dune', '2021');
      expect(dune.libraryFolder('Dune (2021)').kind, WebDavFolderKind.title);
      expect(
        dune.libraryFolder('Dune.2021.2160p.WEB').kind,
        WebDavFolderKind.title,
      );
      expect(dune.libraryFolder('Dune (1984)').kind, WebDavFolderKind.skip);
      expect(
        dune.libraryFolder('Dune Part Two (2024)').kind,
        WebDavFolderKind.skip,
      );
    });

    test('library and index folders are browsed, others skipped', () {
      final dune = movie('Dune', '2021');
      expect(dune.libraryFolder('Movies').kind, WebDavFolderKind.browse);
      expect(dune.libraryFolder('__all__').kind, WebDavFolderKind.browse);
      expect(dune.libraryFolder('D').kind, WebDavFolderKind.browse);
      expect(dune.libraryFolder('A-F').kind, WebDavFolderKind.browse);
      expect(dune.libraryFolder('G-M').kind, WebDavFolderKind.skip);
      expect(dune.libraryFolder('Holiday Photos').kind, WebDavFolderKind.skip);
      final matrix = movie('The Matrix', '1999');
      expect(matrix.libraryFolder('M').kind, WebDavFolderKind.browse);
    });

    test('loose files must name the title; samples never match', () {
      final dune = movie('Dune', '2021');
      expect(
        dune.matchesFile('Dune.2021.1080p.mkv', insideTitle: false),
        isTrue,
      );
      expect(
        dune.matchesFile('Dune.1984.1080p.mkv', insideTitle: false),
        isFalse,
      );
      expect(dune.matchesFile('movie.mkv', insideTitle: true), isTrue);
      expect(dune.matchesFile('dune-sample.mkv', insideTitle: true), isFalse);
      expect(
        dune.matchesFile('trailer.mkv', insideTitle: true, sizeBytes: 9000000),
        isFalse,
      );
    });

    test('extras folders inside the title are skipped', () {
      final dune = movie('Dune', '2021');
      expect(dune.innerFolder('Featurettes').kind, WebDavFolderKind.skip);
      expect(dune.innerFolder('Disc 1').kind, WebDavFolderKind.title);
    });
  });

  group('series', () {
    test('show, region-free and season-pack folders match', () {
      final office = episode('The Office', 2, 3, '2005');
      expect(
        office.libraryFolder('The Office (2005)').kind,
        WebDavFolderKind.title,
      );
      expect(office.libraryFolder('Office').kind, WebDavFolderKind.title);
      expect(
        office.libraryFolder('The Office (US)').kind,
        WebDavFolderKind.title,
      );
      final pack = office.libraryFolder('The.Office.S02.1080p.WEB');
      expect((pack.kind, pack.season), (WebDavFolderKind.title, 2));
      expect(
        office.libraryFolder('The.Office.S03.1080p.WEB').kind,
        WebDavFolderKind.skip,
      );
      expect(
        office.libraryFolder('The.Office.S02E04.720p').kind,
        WebDavFolderKind.skip,
      );
    });

    test('season folders carry their number to bare episode files', () {
      final show = episode('Severance', 1, 3);
      final season = show.innerFolder('Season 01');
      expect((season.kind, season.season), (WebDavFolderKind.title, 1));
      expect(show.innerFolder('Season 2').kind, WebDavFolderKind.skip);
      expect(show.innerFolder('Specials').kind, WebDavFolderKind.skip);
      expect(
        show.matchesFile(
          '03 - In Perpetuity.mkv',
          insideTitle: true,
          season: 1,
        ),
        isTrue,
      );
      expect(
        show.matchesFile('04 - Other.mkv', insideTitle: true, season: 1),
        isFalse,
      );
      // Without any season, a bare number is not trusted.
      expect(show.matchesFile('03.mkv', insideTitle: true), isFalse);
    });

    test('loose episode files need the show title and the episode', () {
      final show = episode('Severance', 1, 3);
      expect(
        show.matchesFile('Severance.S01E03.1080p.mkv', insideTitle: false),
        isTrue,
      );
      expect(
        show.matchesFile('Severance.S01E04.1080p.mkv', insideTitle: false),
        isFalse,
      );
      expect(
        show.matchesFile('Other.Show.S01E03.mkv', insideTitle: false),
        isFalse,
      );
      expect(show.matchesFile('S01E03.mkv', insideTitle: true), isTrue);
    });

    test('a series without a concrete episode is not searchable', () {
      expect(
        WebDavMatchTarget(title: 'Show', isSeries: true, season: 1).searchable,
        isFalse,
      );
      expect(
        WebDavMatchTarget(title: '!!', isSeries: false).searchable,
        isFalse,
      );
    });
  });
  group('review cases', () {
    test('multi-season and complete-series packs hold the episode', () {
      final bad = episode('Breaking Bad', 3, 4, '2008');
      for (final name in [
        'Breaking.Bad.S01-S05.1080p.BluRay',
        'Breaking Bad Seasons 1-5',
        'Breaking.Bad.Complete.Series.1080p',
        'Breaking Bad (2008) Complete',
      ]) {
        expect(
          bad.libraryFolder(name).kind,
          WebDavFolderKind.title,
          reason: name,
        );
      }
      expect(
        bad.libraryFolder('Breaking.Bad.S01-S02.1080p').kind,
        WebDavFolderKind.skip,
      );
      expect(
        WebDavReleaseName.parse('A Complete Unknown (2024)').completeSeries,
        isFalse,
      );
    });

    test('titles that contain a year still match', () {
      final blade = movie('Blade Runner 2049', '2017');
      expect(
        blade.libraryFolder('Blade Runner 2049 (2017)').kind,
        WebDavFolderKind.title,
      );
      expect(
        blade.matchesFile(
          'Blade.Runner.2049.2017.1080p.mkv',
          insideTitle: false,
        ),
        isTrue,
      );
      expect(
        blade.matchesFile('Blade Runner 2049.mkv', insideTitle: false),
        isTrue,
      );
      expect(
        movie(
          'Wonder Woman 1984',
          '2020',
        ).libraryFolder('Wonder Woman 1984 (2020)').kind,
        WebDavFolderKind.title,
      );
    });

    test('movies starting with a number match as loose files', () {
      expect(
        movie(
          '300',
          '2006',
        ).matchesFile('300.2006.1080p.BluRay.mkv', insideTitle: false),
        isTrue,
      );
      expect(
        movie(
          '10 Cloverfield Lane',
          '2016',
        ).matchesFile('10.Cloverfield.Lane.2016.1080p.mkv', insideTitle: false),
        isTrue,
      );
    });

    test('accents fold away', () {
      expect(
        movie('Amélie', '2001').libraryFolder('Amelie.2001.1080p').kind,
        WebDavFolderKind.title,
      );
      expect(
        movie('Amelie', '2001').libraryFolder('Amélie (2001)').kind,
        WebDavFolderKind.title,
      );
    });

    test('a series pack dated by its season still matches', () {
      final bear = episode('The Bear', 3, 2, '2022');
      expect(
        bear.libraryFolder('The.Bear.2024.S03.1080p').kind,
        WebDavFolderKind.title,
      );
      expect(bear.libraryFolder('The Bear (2010)').kind, WebDavFolderKind.skip);
    });

    test('library folders match on any library word', () {
      final dune = movie('Dune', '2021');
      for (final name in [
        'Movies 4K',
        'Movies (4K)',
        'Kids Movies',
        'Multimedia',
        'webdl',
      ]) {
        expect(
          dune.libraryFolder(name).kind,
          WebDavFolderKind.browse,
          reason: name,
        );
      }
      final office = episode('The Office', 2, 3);
      expect(office.libraryFolder('T').kind, WebDavFolderKind.browse);
      expect(office.libraryFolder('O').kind, WebDavFolderKind.browse);
    });

    test('Plex and Jellyfin id tags match exactly', () {
      final dune = WebDavTitleMatcher(
        WebDavMatchTarget(
          title: 'Dune',
          year: '2021',
          isSeries: false,
          imdbId: 'tt1160419',
        ),
      );
      expect(
        dune.libraryFolder('Dune {tmdb-438631} (2021)').kind,
        WebDavFolderKind.title,
      );
      expect(
        dune.libraryFolder('Dune (2021) {imdb-tt1160419}').kind,
        WebDavFolderKind.title,
      );
      expect(
        dune.libraryFolder('Dune (2021) {imdb-tt0087182}').kind,
        WebDavFolderKind.skip,
      );
    });

    test('series sample files never match', () {
      final bad = episode('Breaking Bad', 3, 4);
      expect(
        bad.matchesFile('Breaking.Bad.S03E04.sample.mkv', insideTitle: true),
        isFalse,
      );
    });

    test('automatic picks need the movie year', () {
      final strict = WebDavTitleMatcher(
        WebDavMatchTarget(
          title: 'Dune',
          year: '2021',
          isSeries: false,
          requireYear: true,
        ),
      );
      // A yearless folder is at most a guess, never the title itself.
      expect(strict.libraryFolder('Dune').kind, isNot(WebDavFolderKind.title));
      expect(strict.libraryFolder('Dune (2021)').kind, WebDavFolderKind.title);
      expect(
        movie('Dune', '2021').libraryFolder('Dune').kind,
        WebDavFolderKind.title,
      );
    });

    test('the cheap prefilter never hides a real match', () {
      final dune = movie('Dune', '2021');
      expect(dune.mayName('Holiday.Photos.2019'), isFalse);
      expect(dune.mayName('DUNE.2021.mkv'), isTrue);
      expect(movie("Grey's Anatomy").mayName('Greys.Anatomy.S01'), isTrue);
    });
  });

  group('review round 2', () {
    test('apostrophe titles pass the cheap check and match', () {
      final oceans = movie("Ocean's Eleven", '2001');
      expect(
        oceans.libraryFolder("Ocean's Eleven (2001)").kind,
        WebDavFolderKind.title,
      );
      expect(
        oceans.matchesFile("Ocean's.Eleven.2001.1080p.mkv", insideTitle: false),
        isTrue,
      );
      expect(
        movie(
          "Schindler's List",
          '1993',
        ).libraryFolder('Schindlers.List.1993.1080p').kind,
        WebDavFolderKind.title,
      );
    });

    test('macrons and Central European letters fold', () {
      final shogun = episode('Shōgun', 1, 1, '2024');
      expect(
        shogun.matchesFile('Shogun.2024.S01E01.1080p.mkv', insideTitle: false),
        isTrue,
      );
      expect(
        shogun.libraryFolder('Shogun (2024)').kind,
        WebDavFolderKind.title,
      );
      expect(WebDavReleaseName.fold('Łódź Čapek'), 'lodz capek');
    });

    test('titles ending in All or Complete keep their last word', () {
      expect(
        episode(
          'Free for All',
          1,
          1,
        ).matchesFile('Free.for.All.S01E01.mkv', insideTitle: false),
        isTrue,
      );
      expect(
        movie('Winner Takes All').libraryFolder('Winner Takes All').kind,
        WebDavFolderKind.title,
      );
    });

    test('a quality tag after a season is not a season range', () {
      final name = WebDavReleaseName.parse('Show Season 1 - 4K');
      expect((name.season, name.seasonEnd), (1, 1));
    });

    test('triple-episode files cover every episode', () {
      final name = WebDavReleaseName.parse(
        'Show.S02E01E02E03.mkv',
        isFile: true,
      );
      expect((name.episode, name.episodeEnd), (1, 3));
      expect(name.coversEpisode(3), isTrue);
    });

    test('non-English library folders are browsed', () {
      final dune = movie('Dune', '2021');
      for (final name in ['Filme', 'Películas', 'Serien', 'Documentary']) {
        expect(
          dune.libraryFolder(name).kind,
          WebDavFolderKind.browse,
          reason: name,
        );
      }
    });
  });

  group('review round 3', () {
    test('decomposed accents fold like composed ones', () {
      expect(WebDavReleaseName.fold('Sho\u0304gun'), 'shogun');
    });

    test('"and" is never the cheap-check word', () {
      final meYou = movie('Me & You', '2015');
      expect(
        meYou.libraryFolder('Me & You (2015)').kind,
        WebDavFolderKind.title,
      );
    });

    test('10bit is not an episode or season range', () {
      final file = WebDavReleaseName.parse(
        'Show.S01E01-10bit.mkv',
        isFile: true,
      );
      expect((file.episode, file.episodeEnd), (1, 1));
      final pack = WebDavReleaseName.parse('Show Season 1 - 10bit');
      expect((pack.season, pack.seasonEnd), (1, 1));
      final range = WebDavReleaseName.parse('Show.S01E01-02.mkv', isFile: true);
      expect((range.episode, range.episodeEnd), (1, 2));
      final mixed = WebDavReleaseName.parse(
        'Show.S01E01E02-03.mkv',
        isFile: true,
      );
      expect(mixed.episodeEnd, 3);
    });
  });

  group('layouts users actually have', () {
    test('unrecognised short folders are guesses; system ones never', () {
      final dune = movie('Dune', '2021');
      for (final name in [
        'HDD1',
        'English',
        'New folder',
        'admin',
        'Christopher Nolan Collection',
      ]) {
        expect(
          dune.libraryFolder(name).kind,
          WebDavFolderKind.guess,
          reason: name,
        );
      }
      for (final name in [
        '@eaDir',
        '#recycle',
        r'$RECYCLE.BIN',
        '.snapshot',
        'lost+found',
        'Photos',
        'Music',
        'Subs',
        'Some.Movie.2019.1080p',
        'Other Show S01',
      ]) {
        expect(
          dune.libraryFolder(name).kind,
          WebDavFolderKind.skip,
          reason: name,
        );
      }
      for (final name in ['Hollywood', 'Cinema', 'homes', 'Storage']) {
        expect(
          dune.libraryFolder(name).kind,
          WebDavFolderKind.browse,
          reason: name,
        );
      }
    });

    test('year folders open near the title year only', () {
      final dune = movie('Dune', '2021');
      for (final name in ['2021', 'Movies 2021', '2020-2029', '2020s']) {
        expect(
          dune.libraryFolder(name).kind,
          WebDavFolderKind.browse,
          reason: name,
        );
      }
      for (final name in ['2010', 'Movies 2010', '2000s']) {
        expect(
          dune.libraryFolder(name).kind,
          WebDavFolderKind.skip,
          reason: name,
        );
      }
    });

    test('a letter index under a library name', () {
      final dune = movie('Dune', '2021');
      expect(dune.libraryFolder('Movies A-L').kind, WebDavFolderKind.browse);
      expect(dune.libraryFolder('Movies M-Z').kind, WebDavFolderKind.skip);
    });

    test('run-together names match when the year agrees', () {
      final ironMan = movie('Iron Man', '2008');
      expect(
        ironMan.matchesFile('IronMan.2008.1080p.mkv', insideTitle: false),
        isTrue,
      );
      expect(ironMan.matchesFile('IronMan.mkv', insideTitle: false), isFalse);
      expect(
        ironMan.matchesFile('Iron.Man.2.2010.mkv', insideTitle: false),
        isFalse,
      );
      expect(
        movie(
          'Spider-Man: No Way Home',
          '2021',
        ).matchesFile('Spiderman.No.Way.Home.2021.mkv', insideTitle: false),
        isTrue,
      );
      // Short titles and other years stay apart: "I.T." (2016) is not "It".
      expect(
        movie('It', '2017').matchesFile('I.T.2016.mkv', insideTitle: false),
        isFalse,
      );
      expect(
        movie(
          'Iron Man',
          '2008',
        ).matchesFile('IronMan.2009.mkv', insideTitle: false),
        isFalse,
      );
    });

    test('site prefixes, edition words and leading years', () {
      final inception = movie('Inception', '2010');
      for (final name in [
        'www.Site.xyz - Inception (2010).mkv',
        'Inception.Extended.Cut.2010.1080p.mkv',
        '2010 - Inception.mkv',
      ]) {
        expect(
          inception.matchesFile(name, insideTitle: false),
          isTrue,
          reason: name,
        );
      }
      expect(
        inception.libraryFolder("Inception Director's Cut (2010)").kind,
        WebDavFolderKind.title,
      );
      expect(
        inception.matchesFile('2014 - Interstellar.mkv', insideTitle: false),
        isFalse,
      );
      expect(
        movie(
          'Blade Runner',
          '1982',
        ).libraryFolder('Blade Runner The Final Cut (1982)').kind,
        WebDavFolderKind.title,
      );
    });

    test('a title that starts with a year is not read as a release year', () {
      final mobyDick = movie('Moby Dick', '2011');
      for (final name in [
        '2010.Moby.Dick.2010.1080p.BluRay.mkv',
        '2010 Moby Dick.mkv',
      ]) {
        expect(
          mobyDick.matchesFile(name, insideTitle: false),
          isFalse,
          reason: name,
        );
      }
      expect(
        mobyDick.libraryFolder('2010 Moby Dick (2010)').kind,
        isNot(WebDavFolderKind.title),
      );
    });

    test('an edition name without a year is not the title', () {
      final lotr = movie('The Lord of the Rings', '1978');
      expect(
        lotr.libraryFolder('The.Lord.of.the.Rings.Extended.Edition').kind,
        isNot(WebDavFolderKind.title),
      );
      expect(
        lotr.matchesFile(
          'The.Lord.of.the.Rings.Extended.Edition.mkv',
          insideTitle: false,
        ),
        isFalse,
      );
    });

    test('a collection named after the title is opened despite its words', () {
      final hungerGames = movie('The Hunger Games', '2012');
      for (final name in ['The Hunger Games Collection', 'Hunger Games Saga']) {
        expect(
          hungerGames.libraryFolder(name).kind,
          WebDavFolderKind.guess,
          reason: name,
        );
      }
      expect(hungerGames.libraryFolder('Games').kind, WebDavFolderKind.skip);
      expect(
        movie('Inception', '2010').libraryFolder('Inception Extras').kind,
        WebDavFolderKind.skip,
      );
      expect(
        movie('Inception', '2010').libraryFolder('Backup').kind,
        WebDavFolderKind.guess,
      );
    });

    test('edition words never widen a series match', () {
      expect(
        episode('Doctor Who', 1, 1).libraryFolder('Doctor Who Special').kind,
        isNot(WebDavFolderKind.title),
      );
    });

    test('automatic picks still need the year for loose forms', () {
      final strict = WebDavTitleMatcher(
        WebDavMatchTarget(
          title: 'Iron Man',
          year: '2008',
          isSeries: false,
          requireYear: true,
        ),
      );
      expect(
        strict.matchesFile('IronMan.2008.mkv', insideTitle: false),
        isTrue,
      );
      expect(
        strict.matchesFile('Iron Man Extended.mkv', insideTitle: false),
        isFalse,
      );
    });
  });
}

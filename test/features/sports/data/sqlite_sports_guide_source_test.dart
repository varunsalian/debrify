import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/data/sqlite_sports_guide_source.dart';
import 'package:debrify/features/sports/models/sports_guide_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

final DateTime _now = DateTime.utc(2026, 10, 28, 12);
final DateTime _from = _now.subtract(const Duration(hours: 2));
final DateTime _to = _now.add(const Duration(hours: 6));

const String _catalogKey = 'catalog-1';
const String _guideKey = 'guide-1';
const List<SportsGuidePlaylist> _playlists = [
  SportsGuidePlaylist(
    playlistId: 'pl-1',
    catalogKey: _catalogKey,
    guideKey: _guideKey,
  ),
];

/// Millisecond offsets around [_now]; every programme in these tests is named
/// for the moment it airs, so the window rules stay readable in the test body.
int _ms(int offsetHours) => _now.millisecondsSinceEpoch + offsetHours * 3600000;

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sports_guide_source');
    path = '${dir.path}/catalog.db';
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Closes the writer (a read-only handle must see a committed database) and
  /// runs the worker body directly, exactly as `compute` would.
  SportsGuideSnapshot run(
    _GuideDatabase db, {
    List<SportsGuidePlaylist> playlists = _playlists,
    List<String> titleNeedles = const [],
    List<String> channelNeedles = const [],
  }) {
    db.close();
    return querySportsGuide(
      path,
      playlists,
      SportsGuideQuery(
        fromUtc: _from,
        toUtc: _to,
        nowUtc: _now,
        titleNeedles: titleNeedles,
        channelNeedles: channelNeedles,
      ),
    );
  }

  group('channels', () {
    test('returns broadcaster channels in position order, capped at 200', () {
      final db = _GuideDatabase(path);
      db.catalog();
      // 205 matching channels plus a differently named one that never matches.
      for (var i = 1; i <= 205; i++) {
        db.channel(
          name: 'Sky Sports Main Event $i',
          url: 'http://h/$i.ts',
          position: i,
        );
      }
      db.channel(name: 'Eurosport 1', url: 'http://h/x.ts', position: 999);

      final snapshot = run(db, channelNeedles: const ['sky sports main event']);

      expect(snapshot.channels, hasLength(200));
      expect(snapshot.channels.first.name, 'Sky Sports Main Event 1');
      expect(snapshot.channels.every((c) => c.playlistId == 'pl-1'), isTrue);
    });

    test('matches the base name and numbered siblings only', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'UK: Sky Sports Main Event FHD',
        url: 'http://h/a.ts',
        position: 1,
      );
      db.channel(
        name: 'Sky Sports Main Event 2',
        url: 'http://h/b.ts',
        position: 2,
      );
      db.channel(
        name: 'Sky Sports Main Event Extra',
        url: 'http://h/c.ts',
        position: 3,
      );

      final snapshot = run(db, channelNeedles: const ['sky sports main event']);

      expect(snapshot.channels.map((c) => c.name), [
        'UK: Sky Sports Main Event FHD',
        'Sky Sports Main Event 2',
      ]);
    });

    test('keeps live rows only: vod and timed rows are ignored', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/live.ts',
        position: 1,
      );
      // Same channel name, so only the row kind can rule these out.
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/vod.ts',
        position: 2,
        contentType: 'movie',
      );
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/series.ts',
        position: 3,
        contentType: null,
        duration: 3600,
      );

      final snapshot = run(db, channelNeedles: const ['sky sports main event']);

      expect(snapshot.channels.map((c) => c.name), ['Sky Sports Main Event']);
    });

    test('carries logo, group, attributes and headers', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/live.ts',
        position: 1,
        group: 'Sports UK',
        logo: 'http://h/logo.png',
        attributes: const {'tvg-id': 'sky.main'},
        httpHeaders: const {'Cookie': 'x'},
      );

      final channel = run(
        db,
        channelNeedles: const ['sky sports main event'],
      ).channels.single;

      expect(channel.group, 'Sports UK');
      expect(channel.logoUrl, 'http://h/logo.png');
      expect(channel.attributes, {'tvg-id': 'sky.main'});
      expect(channel.httpHeaders, {'Cookie': 'x'});
    });

    test('ignores channels of an older generation', () {
      final db = _GuideDatabase(path);
      db.catalog(generation: 7);
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/old.ts',
        position: 1,
        generation: 6,
        attributes: const {'tvg-id': 'sky.main'},
      );
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/new.ts',
        position: 2,
        generation: 7,
        attributes: const {'tvg-id': 'sky.main'},
      );
      db.guide();
      db.programme(
        channelId: 'sky.main',
        title: 'Real Madrid v Manchester City',
        startMs: _ms(-1),
        stopMs: _ms(2),
      );

      final snapshot = run(
        db,
        titleNeedles: const ['real madrid'],
        channelNeedles: const ['sky sports main event'],
      );

      expect(snapshot.channels.map((c) => c.url), ['http://h/new.ts']);
      expect(snapshot.listings.single.channel.url, 'http://h/new.ts');
    });

    test('skips a playlist whose catalog has no row', () {
      final db = _GuideDatabase(path);
      db.catalog(catalogKey: 'other-catalog');
      db.channel(name: 'Sky Sports Main Event', url: 'http://h/a.ts');

      final snapshot = run(db, channelNeedles: const ['sky sports main event']);

      expect(snapshot.channels, isEmpty);
      expect(snapshot.listings, isEmpty);
      expect(snapshot.liveSportsListings, isEmpty);
    });
  });

  group('listings', () {
    test('finds accented guide titles from folded needles', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/a.ts',
        attributes: const {'tvg-id': 'sky.main'},
      );
      db.guide();
      db.programme(
        channelId: 'sky.main',
        title: 'Atlético Madrid v Bayern München',
        startMs: _ms(-1),
        stopMs: _ms(2),
      );

      final listings = run(
        db,
        titleNeedles: const ['atletico madrid'],
      ).listings;

      expect(listings.single.title, 'Atlético Madrid v Bayern München');
    });

    test('finds a listing through tvg-id, in UTC', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/a.ts',
        attributes: const {'tvg-id': ' SKY.MAIN '},
      );
      db.guide();
      db.programme(
        channelId: 'sky.main',
        title: 'Real Madrid v Manchester City',
        startMs: _ms(-1),
        stopMs: _ms(2),
      );

      final listing = run(
        db,
        titleNeedles: const ['real madrid'],
      ).listings.single;

      expect(listing.title, 'Real Madrid v Manchester City');
      expect(listing.channel.name, 'Sky Sports Main Event');
      expect(listing.channel.playlistId, 'pl-1');
      expect(listing.start.isUtc, isTrue);
      expect(
        listing.start,
        DateTime.fromMillisecondsSinceEpoch(_ms(-1), isUtc: true),
      );
      expect(
        listing.stop,
        DateTime.fromMillisecondsSinceEpoch(_ms(2), isUtc: true),
      );
    });

    test('resolves a channel through tvg-name and name_to_id_json', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event HD',
        url: 'http://h/a.ts',
        attributes: const {'tvg-name': 'Sky Sports Main Event'},
      );
      db.guide(nameToId: const {'skysportsmainevent': 'sky-main'});
      db.programme(
        channelId: 'sky-main',
        title: 'Real Madrid v Manchester City',
        startMs: _ms(-1),
        stopMs: _ms(2),
      );

      expect(
        run(
          db,
          titleNeedles: const ['real madrid'],
        ).listings.single.channel.name,
        'Sky Sports Main Event HD',
      );
    });

    test('falls back to the channel display name', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(name: 'Sky Sports Main Event', url: 'http://h/a.ts');
      db.guide(nameToId: const {'skysportsmainevent': 'sky-main'});
      db.programme(
        channelId: 'sky-main',
        title: 'Real Madrid v Manchester City',
        startMs: _ms(-1),
        stopMs: _ms(2),
      );

      expect(
        run(db, titleNeedles: const ['real madrid']).listings,
        hasLength(1),
      );
    });

    test('tries the tvg-id without its @suffix', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/a.ts',
        attributes: const {'tvg-id': 'sky.main@provider'},
      );
      db.guide();
      db.programme(
        channelId: 'sky.main',
        title: 'Real Madrid v Manchester City',
        startMs: _ms(-1),
        stopMs: _ms(2),
      );

      expect(
        run(db, titleNeedles: const ['real madrid']).listings,
        hasLength(1),
      );
    });

    test('emits one listing per copy of the same programme', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event 4K',
        url: 'http://h/4k.ts',
        position: 1,
        attributes: const {'tvg-id': 'sky.main'},
      );
      db.channel(
        name: 'Sky Sports Main Event HD',
        url: 'http://h/hd.ts',
        position: 2,
        attributes: const {'tvg-id': 'sky.main'},
      );
      db.guide();
      db.programme(
        channelId: 'sky.main',
        title: 'Real Madrid v Manchester City',
        startMs: _ms(-1),
        stopMs: _ms(2),
      );

      final listings = run(db, titleNeedles: const ['real madrid']).listings;

      expect(listings, hasLength(2));
      expect(listings.map((l) => l.channel.url), [
        'http://h/4k.ts',
        'http://h/hd.ts',
      ]);
      expect(
        listings.every((l) => l.title == 'Real Madrid v Manchester City'),
        isTrue,
      );
    });

    test('drops programmes whose channel is not in the guide', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/a.ts',
        attributes: const {'tvg-id': 'sky.main'},
      );
      db.guide();
      db.programme(
        channelId: 'some.other.channel',
        title: 'Real Madrid v Manchester City',
        startMs: _ms(-1),
        stopMs: _ms(2),
      );

      expect(run(db, titleNeedles: const ['real madrid']).listings, isEmpty);
    });

    test('requires the whole needle, not just the LIKE token', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/a.ts',
        attributes: const {'tvg-id': 'sky.main'},
      );
      db.guide();
      // LIKE-matches 'bayern' (the longest word of the needle) but never says
      // 'bayern munich', so it is not this fixture.
      db.programme(
        channelId: 'sky.main',
        title: 'Bayern Highlights Show',
        startMs: _ms(-1),
        stopMs: _ms(2),
      );

      expect(run(db, titleNeedles: const ['bayern munich']).listings, isEmpty);
    });

    test('ignores needles with no token of 4+ characters', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/a.ts',
        attributes: const {'tvg-id': 'sky.main'},
      );
      db.guide();
      db.programme(
        channelId: 'sky.main',
        title: 'Man Utd v Chelsea',
        startMs: _ms(-1),
        stopMs: _ms(2),
      );

      expect(run(db, titleNeedles: const ['man utd']).listings, isEmpty);
    });

    test('keeps listings inside the window only', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/a.ts',
        attributes: const {'tvg-id': 'sky.main'},
      );
      db.guide();
      db.programme(
        channelId: 'sky.main',
        title: 'Old Derby',
        startMs: _ms(-10),
        stopMs: _ms(-9),
      );
      db.programme(
        channelId: 'sky.main',
        title: 'Future Derby',
        startMs: _ms(10),
        stopMs: _ms(11),
      );
      db.programme(
        channelId: 'sky.main',
        title: 'Live Derby',
        startMs: _ms(-1),
        stopMs: _ms(1),
      );

      final titles = run(
        db,
        titleNeedles: const ['old derby', 'future derby', 'live derby'],
      ).listings.map((l) => l.title);

      expect(titles, ['Live Derby']);
    });

    test('searches tokens beyond the first chunk of 40', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/a.ts',
        attributes: const {'tvg-id': 'sky.main'},
      );
      db.guide();
      db.programme(
        channelId: 'sky.main',
        title: 'Match token45 Live',
        startMs: _ms(-1),
        stopMs: _ms(2),
      );

      final snapshot = run(
        db,
        titleNeedles: [for (var i = 1; i <= 45; i++) 'token$i'],
      );

      expect(snapshot.listings.single.title, 'Match token45 Live');
    });

    test('has no guide rows at all when the playlist has no guide key', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/a.ts',
        group: 'Sports',
        attributes: const {'tvg-id': 'sky.main'},
      );
      db.guide();
      db.programme(
        channelId: 'sky.main',
        title: 'Real Madrid v Manchester City',
        startMs: _ms(-1),
        stopMs: _ms(2),
      );

      final snapshot = run(
        db,
        playlists: const [
          SportsGuidePlaylist(playlistId: 'pl-1', catalogKey: _catalogKey),
        ],
        titleNeedles: const ['real madrid'],
        channelNeedles: const ['sky sports main event'],
      );

      expect(snapshot.channels, hasLength(1));
      expect(snapshot.listings, isEmpty);
      expect(snapshot.liveSportsListings, isEmpty);
    });

    test('has no guide rows when epg_guides holds no such guide', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/a.ts',
        group: 'Sports',
        attributes: const {'tvg-id': 'sky.main'},
      );
      db.programme(
        channelId: 'sky.main',
        title: 'Real Madrid v Manchester City',
        startMs: _ms(-1),
        stopMs: _ms(2),
      );

      final snapshot = run(
        db,
        titleNeedles: const ['real madrid'],
        channelNeedles: const ['sky sports main event'],
      );

      expect(snapshot.channels, hasLength(1));
      expect(snapshot.listings, isEmpty);
      expect(snapshot.liveSportsListings, isEmpty);
    });

    test('caps listings at 2000', () {
      final db = _GuideDatabase(path);
      db.catalog();
      for (var i = 0; i < 12; i++) {
        db.channel(
          name: 'Arena $i',
          url: 'http://h/$i.ts',
          position: i,
          attributes: const {'tvg-id': 'arena'},
        );
      }
      db.guide();
      for (var i = 0; i < 250; i++) {
        db.programme(
          channelId: 'arena',
          title: 'Real Madrid v Manchester City round $i',
          startMs: _ms(-1),
          stopMs: _ms(2),
        );
      }

      expect(
        run(db, titleNeedles: const ['real madrid']).listings,
        hasLength(2000),
      );
    });
  });

  group('live sports', () {
    test('lists what is airing now on sports groups, position first', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Arena 4K',
        url: 'http://h/4k.ts',
        position: 1,
        group: 'Sports',
        attributes: const {'tvg-id': 'arena'},
      );
      db.channel(
        name: 'Arena HD',
        url: 'http://h/hd.ts',
        position: 2,
        group: 'SPORTS',
        attributes: const {'tvg-id': 'arena'},
      );
      db.channel(
        name: 'Box Office',
        url: 'http://h/cinema.ts',
        position: 3,
        group: 'Movies',
        attributes: const {'tvg-id': 'cinema'},
      );
      db.channel(
        name: 'Ring Road',
        url: 'http://h/next.ts',
        position: 4,
        group: 'sports',
        attributes: const {'tvg-id': 'ring'},
      );
      db.guide();
      db.programme(
        channelId: 'arena',
        title: 'Live Football Tonight',
        startMs: _ms(-1),
        stopMs: _ms(1),
      );
      db.programme(
        channelId: 'cinema',
        title: 'A Film About Racing',
        startMs: _ms(-1),
        stopMs: _ms(1),
      );
      // Starts after `now`: scheduled, not live.
      db.programme(
        channelId: 'ring',
        title: 'Tomorrow Night Boxing',
        startMs: _ms(1),
        stopMs: _ms(3),
      );

      final live = run(db).liveSportsListings;

      expect(live, hasLength(1));
      expect(live.single.channel.name, 'Arena 4K');
      expect(live.single.title, 'Live Football Tonight');
    });

    test('orders by channel position then start', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Alpha',
        url: 'http://h/alpha.ts',
        position: 1,
        group: 'Sports',
        attributes: const {'tvg-id': 'alpha'},
      );
      db.channel(
        name: 'Beta',
        url: 'http://h/beta.ts',
        position: 2,
        group: 'Sports',
        attributes: const {'tvg-id': 'beta'},
      );
      db.guide();
      db.programme(
        channelId: 'beta',
        title: 'Beta Fight',
        startMs: _ms(-2),
        stopMs: _ms(1),
      );
      db.programme(
        channelId: 'alpha',
        title: 'Alpha Late Fight',
        startMs: _ms(-1),
        stopMs: _ms(2),
      );
      db.programme(
        channelId: 'alpha',
        title: 'Alpha Early Fight',
        startMs: _ms(-3),
        stopMs: _ms(2),
      );

      final live = run(db).liveSportsListings;

      expect(live.map((l) => l.title), [
        'Alpha Early Fight',
        'Alpha Late Fight',
        'Beta Fight',
      ]);
    });

    test('caps live sports at 40 channels', () {
      final db = _GuideDatabase(path);
      db.catalog();
      for (var i = 0; i < 60; i++) {
        db.channel(
          name: 'Arena $i',
          url: 'http://h/$i.ts',
          position: i,
          group: 'Sports',
          attributes: {'tvg-id': 'arena-$i'},
        );
        db.programme(
          channelId: 'arena-$i',
          title: 'Fight $i',
          startMs: _ms(-1),
          stopMs: _ms(1),
        );
      }
      db.guide();

      expect(run(db).liveSportsListings, hasLength(40));
    });
  });

  group('failure handling', () {
    test('a catalog without epg_programmes never throws', () {
      final db = _GuideDatabase(path, withProgrammes: false);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/a.ts',
        group: 'Sports',
        attributes: const {'tvg-id': 'sky.main'},
      );
      db.guide();

      final snapshot = run(
        db,
        titleNeedles: const ['real madrid'],
        channelNeedles: const ['sky sports main event'],
      );

      // Channels were read before the failing lookup, the rest is skipped.
      expect(snapshot.channels, hasLength(1));
      expect(snapshot.listings, isEmpty);
      expect(snapshot.liveSportsListings, isEmpty);
    });

    test('a playlist without a catalog row does not hide a healthy one', () {
      final db = _GuideDatabase(path);
      db.catalog(catalogKey: _catalogKey);
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/ok.ts',
        position: 1,
      );

      final snapshot = run(
        db,
        playlists: const [
          SportsGuidePlaylist(
            playlistId: 'pl-gone',
            catalogKey: 'deleted-catalog',
            guideKey: _guideKey,
          ),
          SportsGuidePlaylist(
            playlistId: 'pl-1',
            catalogKey: _catalogKey,
            guideKey: _guideKey,
          ),
        ],
        channelNeedles: const ['sky sports main event'],
      );

      expect(snapshot.channels.single.playlistId, 'pl-1');
    });

    test('a missing database file is a failure, not an empty guide', () {
      expect(
        () => querySportsGuide(
          '${dir.path}/does-not-exist.db',
          _playlists,
          SportsGuideQuery(fromUtc: _from, toUtc: _to, nowUtc: _now),
        ),
        throwsA(isA<raw.SqliteException>()),
      );
    });

    test('a corrupt attributes blob leaves the channel usable', () {
      final db = _GuideDatabase(path);
      db.catalog();
      db.channel(
        name: 'Sky Sports Main Event',
        url: 'http://h/a.ts',
        rawAttributes: '{not json',
      );

      final snapshot = run(db, channelNeedles: const ['sky sports main event']);

      expect(snapshot.channels.single.attributes, isEmpty);
    });
  });

  group('SqliteSportsGuideSource', () {
    test(
      'load resolves the playlists and runs the query off the UI thread',
      () async {
        final db = _GuideDatabase(path);
        db.catalog();
        db.channel(
          name: 'Sky Sports Main Event',
          url: 'http://h/a.ts',
          attributes: const {'tvg-id': 'sky.main'},
        );
        db.guide();
        db.programme(
          channelId: 'sky.main',
          title: 'Real Madrid v Manchester City',
          startMs: _ms(-1),
          stopMs: _ms(2),
        );
        db.close();

        var pathCalls = 0;
        final source = SqliteSportsGuideSource(
          dbPath: () {
            pathCalls++;
            return path;
          },
          playlists: () async => _playlists,
        );

        final snapshot = await source.load(
          SportsGuideQuery(
            fromUtc: _from,
            toUtc: _to,
            nowUtc: _now,
            titleNeedles: const ['real madrid'],
            channelNeedles: const ['sky sports main event'],
          ),
        );

        expect(pathCalls, 1);
        expect(snapshot.listings.single.title, 'Real Madrid v Manchester City');
        expect(snapshot.channels.single.playlistId, 'pl-1');
      },
    );

    test('load with no playlist never opens the database', () async {
      final source = SqliteSportsGuideSource(
        dbPath: () => path,
        playlists: () async => const [],
      );

      final snapshot = await source.load(
        SportsGuideQuery(fromUtc: _from, toUtc: _to, nowUtc: _now),
      );

      expect(snapshot, same(SportsGuideSnapshot.empty));
      expect(File(path).existsSync(), isFalse);
    });
  });
}

/// A throwaway catalog database holding only the columns the guide query reads.
class _GuideDatabase {
  _GuideDatabase(String path, {bool withProgrammes = true})
    : _db = raw.sqlite3.open(path) {
    _db.execute(
      'CREATE TABLE catalogs ('
      'catalog_key TEXT PRIMARY KEY, generation INTEGER NOT NULL)',
    );
    _db.execute(
      'CREATE TABLE channels ('
      'id INTEGER PRIMARY KEY, catalog_key TEXT NOT NULL, '
      'generation INTEGER NOT NULL, position INTEGER NOT NULL, '
      'name TEXT NOT NULL, url TEXT NOT NULL, logo_url TEXT, grp TEXT, '
      'duration INTEGER, content_type TEXT, attributes_json TEXT, '
      'http_headers_json TEXT)',
    );
    _db.execute(
      'CREATE TABLE epg_guides ('
      'guide_key TEXT PRIMARY KEY, name_to_id_json TEXT)',
    );
    if (withProgrammes) {
      _db.execute(
        'CREATE TABLE epg_programmes ('
        'guide_key TEXT NOT NULL, channel_id TEXT NOT NULL, '
        'start_ms INTEGER NOT NULL, stop_ms INTEGER NOT NULL, '
        "title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '')",
      );
    }
  }

  final raw.Database _db;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    _db.dispose();
  }

  void catalog({String catalogKey = _catalogKey, int generation = 1}) {
    _db.execute(
      'INSERT INTO catalogs (catalog_key, generation) VALUES (?, ?)',
      [catalogKey, generation],
    );
  }

  void channel({
    required String name,
    required String url,
    int position = 1,
    String catalogKey = _catalogKey,
    int generation = 1,
    String? group,
    String? logo,
    String? contentType = 'live',
    int? duration,
    Map<String, String> attributes = const {},
    Map<String, String> httpHeaders = const {},
    String? rawAttributes,
  }) {
    _db.execute(
      'INSERT INTO channels (catalog_key, generation, position, name, url, '
      'logo_url, grp, duration, content_type, attributes_json, '
      'http_headers_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        catalogKey,
        generation,
        position,
        name,
        url,
        logo,
        group,
        duration,
        contentType,
        rawAttributes ?? jsonEncode(attributes),
        httpHeaders.isEmpty ? null : jsonEncode(httpHeaders),
      ],
    );
  }

  void guide({String guideKey = _guideKey, Map<String, String>? nameToId}) {
    _db.execute(
      'INSERT INTO epg_guides (guide_key, name_to_id_json) VALUES (?, ?)',
      [guideKey, nameToId == null ? null : jsonEncode(nameToId)],
    );
  }

  void programme({
    String guideKey = _guideKey,
    required String channelId,
    required String title,
    required int startMs,
    required int stopMs,
  }) {
    _db.execute(
      'INSERT INTO epg_programmes (guide_key, channel_id, start_ms, stop_ms, '
      'title) VALUES (?, ?, ?, ?, ?)',
      [guideKey, channelId, startMs, stopMs, title],
    );
  }
}

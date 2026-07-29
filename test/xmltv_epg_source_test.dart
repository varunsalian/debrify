import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/services/xmltv_epg_source.dart';

void main() {
  // All times sit around this instant so the parser's ±window keeps them.
  final now = DateTime.utc(2026, 7, 26, 12, 0, 0);
  final nowMs = now.millisecondsSinceEpoch;

  const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="test">
  <channel id="ESPN.us"><display-name>ESPN</display-name></channel>
  <programme start="20260726100000 +0000" stop="20260726130000 +0000" channel="ESPN.us">
    <title lang="en">NBA Finals</title>
    <title lang="es">Finales de la NBA</title>
    <desc><![CDATA[Game 4 & the "decider".]]></desc>
  </programme>
  <programme start="20260726150000 +0200" stop="20260726170000 +0200" channel="ESPN.us">
    <title>SportsCenter</title>
  </programme>
  <programme start="20260726120000 +0000" stop="20260726140000 +0000" channel="Ignored.uk">
    <title>Should be filtered out</title>
  </programme>
  <programme start="20260720000000 +0000" stop="20260720010000 +0000" channel="ESPN.us">
    <title>Way outside the window</title>
  </programme>
  <programme start="20260726180000 +0000" stop="20260726190000 +0000" channel="ESPN.us">
    <icon src="x"/>
    <title>Evening Show</title>
  </programme>
</tv>
''';

  Future<XmltvGuide> parse(
    List<int> bytes, {
    Set<String> ids = const {'ESPN.us'},
    Set<String> names = const {},
  }) async {
    final dir = await Directory.systemTemp.createTemp('xmltv_test');
    final file = File('${dir.path}/guide.xml');
    await file.writeAsBytes(bytes);
    try {
      return await XmltvEpgSource.parseXmltvFile(
        file.path,
        ids,
        names,
        nowMs,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  }

  test('parses, filters and windows a plain XMLTV file', () async {
    final index = (await parse(xml.codeUnits)).byId;
    expect(index.keys, ['espn.us']);
    final rows = index['espn.us']!;
    // Out-of-window and other-channel programmes dropped.
    expect(rows.length, 3);
    // Sorted by start; first title wins over the second language.
    expect(rows[0][2], 'NBA Finals');
    expect(rows[0][3], 'Game 4 & the "decider".');
    expect(rows[0][0], DateTime.utc(2026, 7, 26, 10).millisecondsSinceEpoch);
    // +0200 offset converted: 15:00+0200 == 13:00 UTC.
    expect(rows[1][2], 'SportsCenter');
    expect(rows[1][0], DateTime.utc(2026, 7, 26, 13).millisecondsSinceEpoch);
    expect(rows[1][3], '');
    // Self-closing <icon/> before the title didn't derail the state machine.
    expect(rows[2][2], 'Evening Show');
  });

  test('parses the same file gzipped (magic-byte detection)', () async {
    final index = (await parse(gzip.encode(xml.codeUnits))).byId;
    expect(index['espn.us']!.length, 3);
    expect(index['espn.us']![0][2], 'NBA Finals');
  });

  test('returns empty for a file with no matching channels', () async {
    final guide = await parse('<tv></tv>'.codeUnits);
    expect(guide.byId, isEmpty);
    expect(guide.nameToId, isEmpty);
  });

  test('tvg-id matching is case-insensitive (Kodi default)', () async {
    // Playlist says "espn.US", the guide publishes "ESPN.us" — real
    // playlist/guide pairs disagree on case all the time.
    final guide = await parse(xml.codeUnits, ids: const {'espn.US'});
    expect(guide.byId['espn.us']!.length, 3);
    expect(guide.sawWantedChannel, isTrue);
  });

  test('a start time with no offset is read as UTC', () async {
    const noOffset = '''
<tv>
  <programme start="20260726110000" stop="20260726120000" channel="ESPN.us">
    <title>Offsetless</title>
  </programme>
</tv>
''';
    final index = (await parse(noOffset.codeUnits)).byId;
    final rows = index['espn.us']!;
    expect(rows[0][0], DateTime.utc(2026, 7, 26, 11).millisecondsSinceEpoch);
    expect(rows[0][1], DateTime.utc(2026, 7, 26, 12).millisecondsSinceEpoch);
  });

  test('synthesizes missing stop from the next programme start', () async {
    const noStops = '''
<tv>
  <programme start="20260726110000 +0000" channel="ESPN.us">
    <title>First</title>
  </programme>
  <programme start="20260726123000 +0000" channel="ESPN.us">
    <title>Second</title>
  </programme>
</tv>
''';
    final index = (await parse(noStops.codeUnits)).byId;
    final rows = index['espn.us']!;
    expect(rows.length, 2);
    // First runs until Second starts.
    expect(rows[0][1], DateTime.utc(2026, 7, 26, 12, 30).millisecondsSinceEpoch);
    // Last entry falls back to start + 3h.
    expect(rows[1][1], DateTime.utc(2026, 7, 26, 15, 30).millisecondsSinceEpoch);
  });

  group('normalizeChannelName', () {
    test('case, spacing and punctuation are ignored', () {
      expect(XmltvEpgSource.normalizeChannelName('BBC One HD'), 'bbconehd');
      expect(XmltvEpgSource.normalizeChannelName(' bbc-one_HD '), 'bbconehd');
      expect(XmltvEpgSource.normalizeChannelName('BBC.One.HD'), 'bbconehd');
    });

    test('unicode letters survive', () {
      expect(XmltvEpgSource.normalizeChannelName('Café +1'), 'café1');
    });

    test('pure punctuation normalizes to empty (never matches)', () {
      expect(XmltvEpgSource.normalizeChannelName(' - '), '');
    });
  });

  group('display-name fallback matching', () {
    test('matches a channel by name when its id is not asked for', () async {
      final guide =
          await parse(xml.codeUnits, ids: const {}, names: const {'espn'});
      expect(guide.nameToId, {'espn': 'espn.us'});
      expect(guide.byId['espn.us']!.length, 3);
    });

    test('id and name matches coexist without duplicating rows', () async {
      final guide = await parse(xml.codeUnits, names: const {'espn'});
      expect(guide.byId['espn.us']!.length, 3);
      expect(guide.nameToId, {'espn': 'espn.us'});
    });

    test('unwanted names are not collected', () async {
      final guide =
          await parse(xml.codeUnits, ids: const {}, names: const {'cnn'});
      expect(guide.byId, isEmpty);
      expect(guide.nameToId, isEmpty);
    });

    test('first guide channel with a name wins; the duplicate is dropped',
        () async {
      const dup = '''
<tv>
  <channel id="one.a"><display-name>News 24</display-name></channel>
  <channel id="two.b"><display-name>News 24</display-name></channel>
  <programme start="20260726110000 +0000" stop="20260726120000 +0000" channel="one.a">
    <title>Winner</title>
  </programme>
  <programme start="20260726110000 +0000" stop="20260726120000 +0000" channel="two.b">
    <title>Shadowed</title>
  </programme>
</tv>
''';
      final guide =
          await parse(dup.codeUnits, ids: const {}, names: const {'news24'});
      expect(guide.nameToId, {'news24': 'one.a'});
      expect(guide.byId.keys, ['one.a']);
      expect(guide.byId['one.a']![0][2], 'Winner');
    });

    test('sawWantedChannel: pairing worked but programmes are out of window',
        () async {
      const outOfWindow = '''
<tv>
  <channel id="ESPN.us"><display-name>ESPN</display-name></channel>
  <programme start="20260101000000 +0000" stop="20260101010000 +0000" channel="ESPN.us">
    <title>Ancient</title>
  </programme>
</tv>
''';
      // Paired by id…
      var guide = await parse(outOfWindow.codeUnits);
      expect(guide.byId, isEmpty);
      expect(guide.sawWantedChannel, isTrue);
      // …or by name alone.
      guide = await parse(outOfWindow.codeUnits,
          ids: const {}, names: const {'espn'});
      expect(guide.byId, isEmpty);
      expect(guide.sawWantedChannel, isTrue);
      // Nothing pairs → genuinely mismatched.
      guide = await parse(outOfWindow.codeUnits,
          ids: const {'CNN.us'}, names: const {'cnn'});
      expect(guide.byId, isEmpty);
      expect(guide.sawWantedChannel, isFalse);
    });

    test(
        'malformed XML: a self-closing <channel/> after an unclosed one does '
        'not inherit the previous id', () async {
      const malformed = '''
<tv>
  <channel id="a"><display-name>Alpha</display-name>
  <channel id="b"/>
  <display-name>Beta</display-name>
  <programme start="20260726110000 +0000" stop="20260726120000 +0000" channel="a">
    <title>Show</title>
  </programme>
</tv>
''';
      final guide = await parse(malformed.codeUnits,
          ids: const {}, names: const {'alpha', 'beta'});
      // "Beta" must NOT be attributed to channel "a" via stale state.
      expect(guide.nameToId, {'alpha': 'a'});
    });

    test('any of several display-names can match, normalized', () async {
      const multi = '''
<tv>
  <channel id="x.uk">
    <display-name>BBC One HD</display-name>
    <display-name>BBC 1</display-name>
  </channel>
  <programme start="20260726110000 +0000" stop="20260726120000 +0000" channel="x.uk">
    <title>Show</title>
  </programme>
</tv>
''';
      final guide =
          await parse(multi.codeUnits, ids: const {}, names: const {'bbc1'});
      expect(guide.nameToId, {'bbc1': 'x.uk'});
      expect(guide.byId['x.uk']!.length, 1);
    });
  });

  group('DB mode (rows written by the parse worker, served per lookup)', () {
    late Directory dbDir;

    setUp(() async {
      dbDir = await Directory.systemTemp.createTemp('xmltv_db_test');
      IptvCatalogDb.debugDirectoryOverride = dbDir.path;
      await IptvCatalogDb.open();
    });

    tearDown(() async {
      IptvEpgService.instance.clearM3uEpgContext();
      IptvCatalogDb.debugClose();
      IptvCatalogDb.debugDirectoryOverride = null;
      await dbDir.delete(recursive: true);
    });

    Future<XmltvGuide> parseToDb(List<int> bytes) async {
      final dir = await Directory.systemTemp.createTemp('xmltv_test');
      final file = File('${dir.path}/guide.xml');
      await file.writeAsBytes(bytes);
      try {
        return await XmltvEpgSource.parseXmltvFile(
          file.path,
          const {'ESPN.us'},
          const {},
          nowMs,
          dbPath: IptvCatalogDb.path,
          guideKey: 'guide-1',
          epgUrl: 'http://h/xmltv.php',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    }

    test('the guide lands in the DB and the return value is light', () async {
      final guide = await parseToDb(xml.codeUnits);

      expect(guide.byId, isEmpty,
          reason: 'programme rows must not cross back to the caller');
      expect(guide.guideKey, 'guide-1');
      expect(guide.channelCount, 1);
      expect(guide.isEmpty, isFalse);

      final info = IptvCatalogDb.epgGuideInfo('guide-1')!;
      expect(info.channelCount, 1);
      final rows = IptvCatalogDb.epgProgrammes('guide-1', 'espn.us');
      expect(rows.length, 3);
      expect(rows.first[2], 'NBA Finals');
    });

    test('an empty parse writes NOTHING (stale rows survive a bad refresh)',
        () async {
      await parseToDb(xml.codeUnits); // good rows in place
      const unrelated = '''
<tv>
  <programme start="20260726110000 +0000" stop="20260726120000 +0000" channel="Other.uk">
    <title>Not wanted</title>
  </programme>
</tv>
''';
      final guide = await parseToDb(unrelated.codeUnits);
      expect(guide.isEmpty, isTrue);
      expect(IptvCatalogDb.epgProgrammes('guide-1', 'espn.us').length, 3,
          reason: 'the previous guide must be intact');
    });

    test('peekNowNext answers from DB rows via the catalog binding', () async {
      // Non-Xtream-shaped URL on purpose: capability and now/next must come
      // from the XMLTV binding alone, with no per-stream-endpoint fallback
      // muddying the assertion.
      const url = 'http://cdn.example.com/espn.m3u8';
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: 'cat',
        channels: [
          IptvChannel(
            name: 'ESPN HD',
            url: url,
            duration: -1,
            attributes: const {'tvg-id': 'ESPN.us'},
          ),
        ],
      );

      // peekNowNext computes "now" from the wall clock, so anchor the
      // programme window around the real current time.
      String stamp(DateTime t) =>
          '${t.year.toString().padLeft(4, '0')}'
          '${t.month.toString().padLeft(2, '0')}'
          '${t.day.toString().padLeft(2, '0')}'
          '${t.hour.toString().padLeft(2, '0')}'
          '${t.minute.toString().padLeft(2, '0')}00 +0000';
      final realNow = DateTime.now().toUtc();
      final liveXml = '''
<tv>
  <channel id="ESPN.us"><display-name>ESPN</display-name></channel>
  <programme start="${stamp(realNow.subtract(const Duration(hours: 1)))}" stop="${stamp(realNow.add(const Duration(hours: 1)))}" channel="ESPN.us">
    <title>Airing Right Now</title>
  </programme>
  <programme start="${stamp(realNow.add(const Duration(hours: 1)))}" stop="${stamp(realNow.add(const Duration(hours: 2)))}" channel="ESPN.us">
    <title>Coming Up</title>
  </programme>
</tv>
''';
      final dir = await Directory.systemTemp.createTemp('xmltv_test');
      final file = File('${dir.path}/guide.xml');
      await file.writeAsBytes(liveXml.codeUnits);
      try {
        await XmltvEpgSource.parseXmltvFile(
          file.path,
          const {'ESPN.us'},
          const {},
          realNow.millisecondsSinceEpoch,
          dbPath: IptvCatalogDb.path,
          guideKey: 'guide-live',
          epgUrl: 'http://h/xmltv.php',
        );
      } finally {
        await dir.delete(recursive: true);
      }

      IptvEpgService.instance.debugSetDbXmltvContext(
        guideKey: 'guide-live',
        catalogKey: 'cat',
      );

      final pick = IptvEpgService.instance.peekNowNext(url);
      expect(pick, isNotNull);
      expect(pick!.now?.title, 'Airing Right Now');
      expect(pick.next?.title, 'Coming Up');

      expect(IptvEpgService.isEpgCapableUrl(url), isTrue,
          reason: 'XMLTV coverage via the DB counts as capability');
      expect(
        IptvEpgService.isEpgCapableUrl('http://cdn.example.com/other.m3u8'),
        isFalse,
        reason: 'a URL with no catalog binding has no guide',
      );
    });
  });
}

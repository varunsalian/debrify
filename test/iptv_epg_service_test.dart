import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';

void main() {
  group('xtream panel quirks (real fetch against an in-test server)', () {
    late HttpServer server;
    late int port;

    // Per-test behavior toggles for the fake panel.
    var listingsAsMap = false;
    var plainTitles = false;
    var dataTableTypoOnly = false;
    final seenActions = <String>[];

    String epgText(String s) => plainTitles ? s : base64Encode(utf8.encode(s));

    List<Map<String, dynamic>> listingsAroundNow() {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      const slot = 1800;
      final start = (now ~/ slot) * slot;
      return [
        {
          'id': '1',
          'title': epgText('Current Show'),
          'description': epgText('The one airing right now.'),
          'start_timestamp': '$start',
          'stop_timestamp': '${start + slot}',
        },
        {
          'id': '2',
          'title': epgText('Next Show'),
          'description': epgText('The one after.'),
          'start_timestamp': '${start + slot}',
          'stop_timestamp': '${start + 2 * slot}',
        },
      ];
    }

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      server.listen((request) {
        final action = request.uri.queryParameters['action'] ?? '';
        seenActions.add(action);
        Object? listings;
        if (action == 'get_short_epg' ||
            (action == 'get_simple_data_table' && !dataTableTypoOnly) ||
            (action == 'get_simple_date_table' && dataTableTypoOnly)) {
          final rows = listingsAroundNow();
          // PHP assoc-array panels serve an OBJECT keyed by index.
          listings = listingsAsMap
              ? {for (var i = 0; i < rows.length; i++) '$i': rows[i]}
              : rows;
        } else {
          listings = <Object>[];
        }
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'epg_listings': listings}));
        request.response.close();
      });
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    // Unique stream ids per test keep the service's per-URL caches from
    // leaking one test's answer into the next.
    String channelUrl(int streamId) =>
        'http://127.0.0.1:$port/live/user/pass/$streamId.ts';

    test('base64 titles decode; now/next split around the current time',
        () async {
      listingsAsMap = false;
      plainTitles = false;
      final result = await IptvEpgService.instance.nowNext(channelUrl(101));
      expect(result.now?.title, 'Current Show');
      expect(result.now?.description, 'The one airing right now.');
      expect(result.next?.title, 'Next Show');
    });

    test('plain-text titles survive the base64 heuristic', () async {
      listingsAsMap = false;
      plainTitles = true;
      final result = await IptvEpgService.instance.nowNext(channelUrl(102));
      expect(result.now?.title, 'Current Show');
      expect(result.next?.title, 'Next Show');
    });

    test('map-shaped epg_listings (PHP assoc-array panels) parse fine',
        () async {
      listingsAsMap = true;
      plainTitles = false;
      final result = await IptvEpgService.instance.nowNext(channelUrl(103));
      expect(result.now?.title, 'Current Show');
      expect(result.next?.title, 'Next Show');
    });

    test('schedule falls back to the get_simple_date_table typo action',
        () async {
      listingsAsMap = false;
      plainTitles = false;
      dataTableTypoOnly = true;
      seenActions.clear();
      final listings = await IptvEpgService.instance.schedule(channelUrl(104));
      expect(listings.map((p) => p.title), contains('Current Show'));
      expect(seenActions, contains('get_simple_data_table'));
      expect(seenActions, contains('get_simple_date_table'));
      dataTableTypoOnly = false;
    });
  });

  group('xmltv.php derivation', () {
    test('recovers the guide URL from an Xtream channel URL', () {
      expect(
        IptvEpgService.xmltvUrlForChannelUrl(
          'http://host:8080/live/us%40er/pw/55.ts',
        ),
        'http://host:8080/xmltv.php?username=us%40er&password=pw',
      );
    });

    test('non-Xtream URLs derive nothing', () {
      expect(
        IptvEpgService.xmltvUrlForChannelUrl(
          'https://cdn.example.com/a.m3u8',
        ),
        isNull,
      );
    });
  });

  group('stripFeedSuffix', () {
    test('strips an iptv-org feed suffix', () {
      expect(IptvEpgService.stripFeedSuffix('BBCOne.uk@SD'), 'BBCOne.uk');
      expect(IptvEpgService.stripFeedSuffix('CNN.us@HD'), 'CNN.us');
    });

    test('leaves ids without a suffix unchanged', () {
      expect(IptvEpgService.stripFeedSuffix('BBCOne.uk'), 'BBCOne.uk');
      expect(IptvEpgService.stripFeedSuffix('US1000005GY'), 'US1000005GY');
    });

    test('only the first @ splits — the rest stays with the feed', () {
      expect(IptvEpgService.stripFeedSuffix('Odd.id@SD@extra'), 'Odd.id');
    });

    test('a leading @ is not a suffix', () {
      expect(IptvEpgService.stripFeedSuffix('@weird'), '@weird');
    });
  });

  group('catchupStart', () {
    EpgProgramme programme({String? rawStart, DateTime? start}) => EpgProgramme(
          title: 'T',
          description: '',
          start: start ?? DateTime(2026, 7, 26, 20, 30),
          stop: DateTime(2026, 7, 26, 22, 0),
          rawStart: rawStart,
        );

    test('uses the panel-local raw string verbatim', () {
      expect(
        IptvEpgService.catchupStart(programme(rawStart: '2026-07-26 20:30:00')),
        '2026-07-26:20-30',
      );
    });

    test('tolerates a T separator and missing seconds', () {
      expect(
        IptvEpgService.catchupStart(programme(rawStart: '2026-07-26T09:05')),
        '2026-07-26:09-05',
      );
    });

    test('falls back to the parsed start when raw is absent or malformed', () {
      expect(
        IptvEpgService.catchupStart(programme(rawStart: 'garbage')),
        '2026-07-26:20-30',
      );
      expect(
        IptvEpgService.catchupStart(programme()),
        '2026-07-26:20-30',
      );
    });
  });

  group('isCatchupAvailable', () {
    final now = DateTime.now();
    IptvChannel channel({Map<String, String> attributes = const {}}) =>
        IptvChannel(
          name: 'ESPN',
          url: 'http://host:8080/live/user/pass/42.m3u8',
          duration: -1,
          attributes: attributes,
        );
    EpgProgramme finished({bool hasArchive = true, Duration age = const Duration(hours: 3)}) =>
        EpgProgramme(
          title: 'T',
          description: '',
          start: now.subtract(age + const Duration(hours: 1)),
          stop: now.subtract(age),
          hasArchive: hasArchive,
        );

    test('finished + archived + xtream url → available', () {
      expect(IptvEpgService.isCatchupAvailable(channel(), finished()), isTrue);
    });

    test('no archive flag → unavailable', () {
      expect(
        IptvEpgService.isCatchupAvailable(
          channel(),
          finished(hasArchive: false),
        ),
        isFalse,
      );
    });

    test('still airing → unavailable', () {
      final airing = EpgProgramme(
        title: 'T',
        description: '',
        start: now.subtract(const Duration(minutes: 30)),
        stop: now.add(const Duration(minutes: 30)),
        hasArchive: true,
      );
      expect(IptvEpgService.isCatchupAvailable(channel(), airing), isFalse);
    });

    test('channel explicitly archive-off → unavailable', () {
      expect(
        IptvEpgService.isCatchupAvailable(
          channel(attributes: const {'tv_archive': '0'}),
          finished(),
        ),
        isFalse,
      );
    });

    test('outside the archive window → unavailable', () {
      expect(
        IptvEpgService.isCatchupAvailable(
          channel(attributes: const {'tv_archive_duration': '1'}),
          finished(age: const Duration(days: 2)),
        ),
        isFalse,
      );
    });

    test('non-xtream url → unavailable', () {
      final m3uChannel = IptvChannel(
        name: 'X',
        url: 'http://cdn.example.com/some/stream.m3u8',
        duration: -1,
      );
      expect(
        IptvEpgService.isCatchupAvailable(m3uChannel, finished()),
        isFalse,
      );
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/utils/m3u_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

Stream<String> _lines(String body) =>
    Stream<String>.fromIterable(const LineSplitter().convert(body));

void main() {
  late Directory root;
  late Directory downloads;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    IptvService.instance.clearCache();
    root = await Directory.systemTemp.createTemp('iptv-streaming-test-');
    downloads = Directory('${root.path}/downloads')..createSync();
    final catalog = Directory('${root.path}/catalog')..createSync();
    IptvCatalogDb.debugDirectoryOverride = catalog.path;
    IptvService.debugDownloadDirectoryOverride = downloads.path;
    await IptvCatalogDb.open();
  });

  tearDown(() async {
    IptvService.debugMaxPlaylistBytesOverride = null;
    IptvService.debugDownloadDirectoryOverride = null;
    IptvService.instance.clearCache();
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    ProfileRuntime.debugReset();
    await root.delete(recursive: true);
  });

  test('URL playlist ceiling is 250 MiB', () {
    expect(IptvService.debugMaxPlaylistBytes, 250 * 1024 * 1024);
  });

  test(
    'streamed ingest preserves digest, numbering, headers, and order',
    () async {
      const catalogKey = 'm3u|streamed';
      const body = '''
#EXTM3U url-tvg="https://guide.example/epg.xml"
#EXTINF:-1 tvg-id="alpha" group-title="Sports",Alpha
#EXTVLCOPT:http-user-agent=Panel Player
http://stream.example/alpha.ts
#EXTINF:-1 tvg-id="bravo" group-title="Sports",Bravo
http://stream.example/bravo.ts
#EXTINF:120 group-title="Sports",Movie
http://stream.example/movie.mp4
''';
      final materialized = M3uParser.parse(body);

      final first = await IptvCatalogDb.ingestM3uLines(
        dbPath: IptvCatalogDb.path,
        catalogKey: catalogKey,
        lines: _lines(body),
        numberingSourceKey: 'source-1',
      );

      expect(first.hasError, isFalse, reason: first.error);
      expect(first.channels, isEmpty);
      expect(first.ingest?.channelCount, 3);
      expect(
        first.ingest?.contentDigest,
        IptvCatalogDb.contentDigest(materialized.channels),
      );
      expect(first.epgUrl, 'https://guide.example/epg.xml');
      var snapshot = IptvCatalogDb.snapshot(catalogKey)!;
      var rows = snapshot.page(offset: 0, limit: 10);
      expect(rows.map((channel) => channel.channelNumber), [1, 2, null]);
      expect(rows.first.httpHeaders['User-Agent'], 'Panel Player');

      final identities = {
        for (final entry in snapshot.groupOrderEntries('Sports'))
          entry.channel.name: entry.identity,
      };
      expect(
        await IptvCatalogDb.setGroupChannelOrder(catalogKey, 'Sports', [
          identities['Bravo']!,
          identities['Alpha']!,
          identities['Movie']!,
        ]),
        isTrue,
      );

      const reordered = '''
#EXTM3U url-tvg="https://guide.example/epg.xml"
#EXTINF:-1 tvg-id="bravo" group-title="Sports",Bravo
http://stream.example/bravo.ts
#EXTINF:120 group-title="Sports",Movie
http://stream.example/movie.mp4
#EXTINF:-1 tvg-id="alpha" group-title="Sports",Alpha
#EXTVLCOPT:http-user-agent=Panel Player
http://stream.example/alpha.ts
''';
      await IptvCatalogDb.ingestM3uLines(
        dbPath: IptvCatalogDb.path,
        catalogKey: catalogKey,
        lines: _lines(reordered),
        numberingSourceKey: 'source-1',
      );
      snapshot = IptvCatalogDb.snapshot(catalogKey)!;
      rows = snapshot.page(offset: 0, limit: 10);
      expect(rows.map((channel) => channel.name), ['Bravo', 'Movie', 'Alpha']);
      expect(rows.map((channel) => channel.channelNumber), [2, null, 1]);
      expect(
        snapshot
            .page(offset: 0, limit: 10, group: 'Sports')
            .map((channel) => channel.name),
        ['Bravo', 'Alpha', 'Movie'],
        reason: 'saved category order must survive the streamed refresh',
      );
    },
  );

  test(
    'failed streamed parse removes committed chunks and keeps old catalog',
    () async {
      const catalogKey = 'm3u|atomic';
      IptvCatalogDb.ingest(
        dbPath: IptvCatalogDb.path,
        catalogKey: catalogKey,
        channels: [
          IptvChannel(name: 'Old', url: 'http://stream.example/old.ts'),
        ],
      );

      Stream<String> broken() async* {
        yield '#EXTM3U';
        for (var i = 0; i < 3000; i++) {
          yield '#EXTINF:-1,Channel $i';
          yield 'http://stream.example/$i.ts';
        }
        throw StateError('fixture interrupted');
      }

      await expectLater(
        IptvCatalogDb.ingestM3uLines(
          dbPath: IptvCatalogDb.path,
          catalogKey: catalogKey,
          lines: broken(),
          numberingSourceKey: 'source-atomic',
        ),
        throwsStateError,
      );
      expect(
        IptvCatalogDb.snapshot(
          catalogKey,
        )!.page(offset: 0, limit: 10).single.name,
        'Old',
      );
      final db = raw.sqlite3.open(IptvCatalogDb.path);
      try {
        expect(
          db.select(
            'SELECT COUNT(*) AS c FROM channels WHERE catalog_key = ?',
            [catalogKey],
          ).single['c'],
          1,
          reason: 'already committed unpublished chunks must be swept',
        );
      } finally {
        db.dispose();
      }
    },
  );

  test(
    'chunked response is capped while streaming and staging is removed',
    () async {
      IptvService.debugMaxPlaylistBytesOverride = 1024;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.chunkedTransferEncoding = true;
        try {
          request.response.add(List<int>.filled(700, 65));
          await request.response.flush();
          request.response.add(List<int>.filled(700, 66));
          await request.response.close();
        } catch (_) {}
      });
      try {
        final url = 'http://127.0.0.1:${server.port}/too-large.m3u';
        final result = await IptvService.instance.fetchPlaylist(
          url,
          allowUnbound: true,
        );
        expect(result.error, contains('Playlist is too large'));
        expect(IptvCatalogDb.snapshot(IptvCatalogKey.forUrl(url)), isNull);
        expect(await downloads.list().toList(), isEmpty);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test('latin1 URL playlist retries from disk and removes staging', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.add(<int>[
        ...ascii.encode('#EXTM3U\n#EXTINF:-1,Caf'),
        0xE9,
        ...ascii.encode('\nhttp://stream.example/cafe.ts\n'),
      ]);
      await request.response.close();
    });
    try {
      final url = 'http://127.0.0.1:${server.port}/latin1.m3u';
      final result = await IptvService.instance.fetchPlaylist(
        url,
        allowUnbound: true,
      );
      expect(result.hasError, isFalse, reason: result.error);
      expect(result.ingest?.channelCount, 1);
      expect(
        IptvCatalogDb.snapshot(
          IptvCatalogKey.forUrl(url),
        )!.page(offset: 0, limit: 1).single.name,
        'Café',
      );
      expect(await downloads.list().toList(), isEmpty);
    } finally {
      await server.close(force: true);
    }
  });

  test('CR-only URL playlist keeps every channel line', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.write(
        '#EXTM3U\r'
        '#EXTINF:-1 group-title="News",CR Channel\r'
        'http://stream.example/cr.ts\r',
      );
      await request.response.close();
    });
    try {
      final url = 'http://127.0.0.1:${server.port}/cr-only.m3u';
      final result = await IptvService.instance.fetchPlaylist(
        url,
        allowUnbound: true,
      );
      expect(result.hasError, isFalse, reason: result.error);
      expect(result.ingest?.channelCount, 1);
      expect(
        IptvCatalogDb.snapshot(
          IptvCatalogKey.forUrl(url),
        )!.page(offset: 0, limit: 1).single.name,
        'CR Channel',
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('CRLF split across file-read chunks is one line ending', () async {
    // File.openRead uses 64 KiB chunks. Put CR at the last byte of the first
    // chunk and LF at the first byte of the second to exercise boundary state.
    final paddedHeader =
        '#EXTM3U${List<String>.filled(65535 - '#EXTM3U'.length, ' ').join()}';
    final body =
        '$paddedHeader\r\n'
        '#EXTINF:-1,Boundary Channel\r\n'
        'http://stream.example/boundary.ts\r\n';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.add(ascii.encode(body));
      await request.response.close();
    });
    try {
      final url = 'http://127.0.0.1:${server.port}/boundary.m3u';
      final result = await IptvService.instance.fetchPlaylist(
        url,
        allowUnbound: true,
      );
      expect(result.hasError, isFalse, reason: result.error);
      expect(result.ingest?.channelCount, 1);
      expect(
        IptvCatalogDb.snapshot(
          IptvCatalogKey.forUrl(url),
        )!.page(offset: 0, limit: 1).single.name,
        'Boundary Channel',
      );
    } finally {
      await server.close(force: true);
    }
  });

  test(
    'newline-free body cannot become one body-sized parser allocation',
    () async {
      IptvService.debugMaxPlaylistBytesOverride = 2 * 1024 * 1024;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.add(List<int>.filled(1024 * 1024 + 1, 65));
        await request.response.close();
      });
      try {
        final url = 'http://127.0.0.1:${server.port}/one-line.m3u';
        final result = await IptvService.instance.fetchPlaylist(
          url,
          allowUnbound: true,
        );
        expect(result.error, 'Failed to fetch playlist');
        expect(IptvCatalogDb.snapshot(IptvCatalogKey.forUrl(url)), isNull);
        expect(await downloads.list().toList(), isEmpty);
      } finally {
        await server.close(force: true);
      }
    },
  );
}

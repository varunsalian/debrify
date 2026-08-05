import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/live_recording_service.dart';

/// The probe that stops the stage's Record button promising a recording of a
/// stream the engine cannot capture. It must be affirmative-only: anything it
/// can't positively identify as a playlist has to fail OPEN, or a flaky
/// network would block recordings that work today.
void main() {
  late HttpServer server;
  late String base;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://${server.address.address}:${server.port}';
  });

  tearDown(() async => server.close(force: true));

  void serve(Future<void> Function(HttpRequest req) handler) {
    server.listen((req) async {
      await handler(req);
      await req.response.close();
    });
  }

  test('an HLS playlist body is detected even with a lying content-type', () async {
    serve((req) async {
      // IPTV panels routinely mislabel these as video/mp2t.
      req.response.headers.contentType = ContentType('video', 'mp2t');
      req.response.write('#EXTM3U\n#EXT-X-VERSION:3\n');
    });

    expect(await LiveRecordingService.servesPlaylist(base), isTrue);
  });

  test('an HLS content-type is detected', () async {
    serve((req) async {
      req.response.headers.contentType =
          ContentType('application', 'vnd.apple.mpegurl');
      req.response.write('whatever');
    });

    expect(await LiveRecordingService.servesPlaylist(base), isTrue);
  });

  // The first version read ONE stream event and assumed it held the whole
  // signature. Chunk boundaries are arbitrary, so a dribbling server defeated
  // it and the original bug survived.
  test('the signature is found even when it dribbles in byte by byte', () async {
    serve((req) async {
      req.response.headers.contentType = ContentType('video', 'mp2t');
      for (final code in '#EXTM3U\n'.codeUnits) {
        req.response.add([code]);
        await req.response.flush();
      }
    });

    expect(await LiveRecordingService.servesPlaylist(base), isTrue);
  });

  // Likewise, slicing seven bytes BEFORE trimming missed a BOM entirely.
  test('a UTF-8 BOM before the signature still counts', () async {
    serve((req) async {
      req.response.headers.contentType = ContentType('video', 'mp2t');
      req.response.add([0xEF, 0xBB, 0xBF]);
      req.response.write('#EXTM3U\n');
    });

    expect(await LiveRecordingService.servesPlaylist(base), isTrue);
  });

  test('progressive bytes are left alone', () async {
    serve((req) async {
      req.response.headers.contentType = ContentType('video', 'mp2t');
      // MPEG-TS sync byte, nothing playlist-like.
      req.response.add(List<int>.filled(512, 0x47));
    });

    expect(await LiveRecordingService.servesPlaylist(base), isFalse);
  });

  test('fails open when the server is unreachable', () async {
    await server.close(force: true);

    expect(await LiveRecordingService.servesPlaylist(base), isFalse);
  });

  // Channel headers come from #EXTHTTP and routinely carry credentials. The
  // native recorder drops them once the chain leaves the configured origin;
  // the probe follows redirects by hand for exactly this reason.
  test('channel headers do not follow a redirect off-origin', () async {
    final foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => foreign.close(force: true));
    String? leaked = 'unset';
    foreign.listen((req) async {
      leaked = req.headers.value('x-secret');
      req.response.headers.contentType = ContentType('video', 'mp2t');
      req.response.add(List<int>.filled(16, 0x47));
      await req.response.close();
    });

    serve((req) async {
      req.response.statusCode = HttpStatus.found;
      // A DIFFERENT origin (port differs), so the headers must be dropped.
      req.response.headers.set(
        HttpHeaders.locationHeader,
        'http://${foreign.address.address}:${foreign.port}/stream',
      );
    });

    await LiveRecordingService.servesPlaylist(
      base,
      headers: const {'X-Secret': 'do-not-leak'},
    );

    expect(leaked, isNull);
  });
}

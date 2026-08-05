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

  void serve(void Function(HttpRequest req) handler) {
    server.listen((req) async {
      handler(req);
      await req.response.close();
    });
  }

  test('an HLS playlist body is detected even with a lying content-type', () async {
    serve((req) {
      // IPTV panels routinely mislabel these as video/mp2t.
      req.response.headers.contentType = ContentType('video', 'mp2t');
      req.response.write('#EXTM3U\n#EXT-X-VERSION:3\n');
    });

    expect(await LiveRecordingService.servesPlaylist(base), isTrue);
  });

  test('an HLS content-type is detected', () async {
    serve((req) {
      req.response.headers.contentType =
          ContentType('application', 'vnd.apple.mpegurl');
      req.response.write('whatever');
    });

    expect(await LiveRecordingService.servesPlaylist(base), isTrue);
  });

  test('progressive bytes are left alone', () async {
    serve((req) {
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
}

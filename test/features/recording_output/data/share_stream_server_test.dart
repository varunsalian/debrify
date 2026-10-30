// Share recordings streamed to the player over loopback HTTP: whole files,
// byte ranges for seeking, stable URLs, and profile isolation.
import 'dart:io';

import 'package:debrify/features/recording_output/data/share_stream_server.dart';
import 'package:debrify/features/recording_output/models/share_recording.dart';
import 'package:debrify/features/recording_output/models/smb_target.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/smb_fakes.dart';

const _target = SmbTarget(enabled: true, host: 'nas', share: 'media');

final class _RealNetwork extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late FakeShare share;
  late FakeSettings settings;
  late String profile;
  late ShareStreamServer server;
  final bytes = List<int>.generate(3 * 1024 * 1024 + 7, (i) => i % 251);
  final recording = ShareRecording(
    name: 'News 30-10.ts',
    path: 'News 30-10.ts',
    bytes: bytes.length,
    modified: DateTime.utc(2026, 10, 30),
  );

  ShareStreamServer newServer() => ShareStreamServer(
    connector: share,
    store: settings,
    activeProfile: () => profile,
    stateFile: () async => File('${temp.path}/state.json'),
  );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('share_stream');
    share = FakeShare()..files['News 30-10.ts'] = bytes;
    settings = FakeSettings(target: _target, password: 'pw');
    profile = 'profile-a';
    server = newServer();
  });

  tearDown(() async {
    await server.close();
    temp.deleteSync(recursive: true);
  });

  Future<(int, Map<String, String>, List<int>)> get(Uri url, {String? range}) =>
      HttpOverrides.runWithHttpOverrides(() async {
        final client = HttpClient();
        try {
          final request = await client.getUrl(url);
          if (range != null) request.headers.set('range', range);
          final response = await request.close();
          final body = <int>[];
          await for (final piece in response) {
            body.addAll(piece);
          }
          final headers = <String, String>{};
          response.headers.forEach((k, v) => headers[k] = v.join(','));
          return (response.statusCode, headers, body);
        } finally {
          client.close(force: true);
        }
      }, _RealNetwork());

  test('the whole file plays, labelled for the player', () async {
    final url = await server.urlFor(recording);
    expect(url.host, '127.0.0.1');
    expect(url.pathSegments.last, 'News 30-10.ts');

    final (status, headers, body) = await get(url);
    expect(status, 200);
    expect(headers['content-type'], 'video/mp2t');
    expect(headers['accept-ranges'], 'bytes');
    expect(body, bytes);
  });

  test('byte ranges serve exactly the requested part (seeking)', () async {
    final url = await server.urlFor(recording);
    final (status, headers, body) = await get(
      url,
      range: 'bytes=1048570-1048590',
    );
    expect(status, 206);
    expect(headers['content-range'], 'bytes 1048570-1048590/${bytes.length}');
    expect(body, bytes.sublist(1048570, 1048591));

    final (tailStatus, _, tail) = await get(url, range: 'bytes=-10');
    expect(tailStatus, 206);
    expect(tail, bytes.sublist(bytes.length - 10));

    final (beyond, beyondHeaders, _) = await get(url, range: 'bytes=99999999-');
    expect(beyond, 416);
    expect(beyondHeaders['content-range'], 'bytes */${bytes.length}');
  });

  test('one session serves every request until it idles', () async {
    final url = await server.urlFor(recording);
    await get(url, range: 'bytes=0-99');
    await get(url, range: 'bytes=100-199');
    expect(share.connects, 1);
  });

  test('a URL stays the same for the same file, across restarts', () async {
    final first = await server.urlFor(recording);
    expect(await server.urlFor(recording), first);
    await server.close();

    final restarted = newServer();
    expect(await restarted.urlFor(recording), first, reason: 'resume survives');
    await restarted.close();
  });

  test('another profile gets another URL, and cannot use the first', () async {
    final mine = await server.urlFor(recording);
    profile = 'profile-b';
    expect(await server.urlFor(recording), isNot(mine));
    final (status, _, body) = await get(mine);
    expect(status, 403);
    expect(body, isEmpty);
  });

  test('unknown paths and tokens are refused', () async {
    final url = await server.urlFor(recording);
    final wrong = url.replace(pathSegments: ['r', 'f' * 32, 'x.ts']);
    expect((await get(wrong)).$1, 404);
    expect((await get(url.replace(path: '/'))).$1, 404);
  });

  test('without a share set up there is no URL', () async {
    settings.target = const SmbTarget();
    await expectLater(server.urlFor(recording), throwsStateError);
  });

  group('parseByteRange', () {
    test('forms players send', () {
      expect(parseByteRange('bytes=0-', 100), (0, 99));
      expect(parseByteRange('bytes=10-19', 100), (10, 19));
      expect(parseByteRange('bytes=90-500', 100), (90, 99));
      expect(parseByteRange('bytes=-5', 100), (95, 99));
      expect(parseByteRange('bytes=-500', 100), (0, 99));
    });

    test('nothing usable', () {
      expect(parseByteRange(null, 100), isNull);
      expect(parseByteRange('bytes=100-', 100), isNull);
      expect(parseByteRange('bytes=20-10', 100), isNull);
      expect(parseByteRange('bytes=0-1,5-6', 100), isNull);
      expect(parseByteRange('items=0-1', 100), isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debrify/services/stream_url_validator.dart';

const _big = 100 * 1024 * 1024; // 100 MB
const _small = 5 * 1024 * 1024; // 5 MB

/// Installs a MockClient whose responses come from [routes]:
/// url → (status, headers). Records every requested url in the returned list.
List<String> mock(Map<String, (int, Map<String, String>)> routes) {
  final requested = <String>[];
  StreamUrlValidator.clientFactory = () => MockClient((request) async {
        requested.add(request.url.toString());
        expect(request.method, 'HEAD');
        final route = routes[request.url.toString()];
        if (route == null) return http.Response('', 404);
        return http.Response('', route.$1, headers: route.$2);
      });
  return requested;
}

/// A client that never answers, so the per-hop timeout fires. [before]
/// optionally serves earlier hops so the stall can be placed mid-chain.
/// Records every requested url.
List<String> stallingClient({Map<String, (int, Map<String, String>)> before = const {}}) {
  final requested = <String>[];
  StreamUrlValidator.clientFactory = () => MockClient((request) async {
        final url = request.url.toString();
        requested.add(url);
        final early = before[url];
        if (early != null) return http.Response('', early.$1, headers: early.$2);
        await Future<void>.delayed(StreamUrlValidator.timeout * 4);
        return http.Response('', 200, headers: {'content-length': '$_big'});
      });
  return requested;
}

void main() {
  final realTimeout = StreamUrlValidator.timeout;

  setUp(() {
    // Timeout cases are real waits, so shrink the per-hop budget rather than
    // sleeping seconds per test.
    StreamUrlValidator.timeout = const Duration(milliseconds: 50);
  });

  tearDown(() {
    StreamUrlValidator.clientFactory = http.Client.new;
    StreamUrlValidator.timeout = realTimeout;
  });

  test('2xx with a big content-length is alive', () async {
    mock({
      'https://x/movie.mp4': (200, {'content-length': '$_big'}),
    });
    expect(
        await StreamUrlValidator.isPlayableVideoUrl('https://x/movie.mp4'),
        isTrue);
  });

  test('placeholder-sized body (< 50 MB) is dead', () async {
    mock({
      'https://x/movie.mp4': (200, {'content-length': '$_small'}),
    });
    expect(
        await StreamUrlValidator.isPlayableVideoUrl('https://x/movie.mp4'),
        isFalse);
  });

  test('non-2xx is dead', () async {
    mock({
      'https://x/movie.mp4': (404, {'content-length': '$_big'}),
    });
    expect(
        await StreamUrlValidator.isPlayableVideoUrl('https://x/movie.mp4'),
        isFalse);
  });

  test('missing content-length is dead', () async {
    mock({'https://x/movie.mp4': (200, {})});
    expect(
        await StreamUrlValidator.isPlayableVideoUrl('https://x/movie.mp4'),
        isFalse);
  });

  test('redirect chain is followed and the FINAL url judged', () async {
    final requested = mock({
      'https://x/a': (302, {'location': 'https://x/b'}),
      'https://x/b': (307, {'location': '/c.mp4'}), // relative
      'https://x/c.mp4': (200, {'content-length': '$_big'}),
    });
    expect(await StreamUrlValidator.isPlayableVideoUrl('https://x/a'), isTrue);
    expect(requested, ['https://x/a', 'https://x/b', 'https://x/c.mp4']);
  });

  test('redirect without a location is dead', () async {
    mock({'https://x/a': (302, {})});
    expect(await StreamUrlValidator.isPlayableVideoUrl('https://x/a'), isFalse);
  });

  test('more than 5 redirect hops is dead', () async {
    mock({
      for (var i = 0; i < 9; i++)
        'https://x/$i': (302, {'location': 'https://x/${i + 1}'}),
      'https://x/9': (200, {'content-length': '$_big'}),
    });
    expect(await StreamUrlValidator.isPlayableVideoUrl('https://x/0'), isFalse);
  });

  test('HLS playlist by content-type is alive without a length', () async {
    mock({
      'https://x/live': (200, {'content-type': 'application/vnd.apple.mpegurl'}),
    });
    expect(await StreamUrlValidator.isPlayableVideoUrl('https://x/live'), isTrue);
  });

  test('HLS playlist by .m3u8 path is alive without a length', () async {
    mock({'https://x/master.m3u8': (200, {})});
    expect(
        await StreamUrlValidator.isPlayableVideoUrl('https://x/master.m3u8'),
        isTrue);
  });

  test('thrown transport errors read as dead, never throw', () async {
    StreamUrlValidator.clientFactory =
        () => MockClient((_) async => throw Exception('socket down'));
    expect(await StreamUrlValidator.isPlayableVideoUrl('https://x/a'), isFalse);
  });

  test('exactly 4 redirects (5 requests total) still succeeds', () async {
    mock({
      for (var i = 0; i < 4; i++)
        'https://x/$i': (302, {'location': 'https://x/${i + 1}'}),
      'https://x/4': (200, {'content-length': '$_big'}),
    });
    expect(await StreamUrlValidator.isPlayableVideoUrl('https://x/0'), isTrue);
  });

  test('custom minBytes floor is honored', () async {
    mock({
      'https://x/ep.mp4': (200, {'content-length': '${30 * 1024 * 1024}'}),
    });
    expect(
        await StreamUrlValidator.isPlayableVideoUrl('https://x/ep.mp4'),
        isFalse); // default 50MB floor
    expect(
        await StreamUrlValidator.isPlayableVideoUrl('https://x/ep.mp4',
            minBytes: 10 * 1024 * 1024),
        isTrue);
  });

  group('lenient mode', () {
    test('405/501 (host refuses HEAD) is alive', () async {
      mock({'https://x/a.mp4': (405, {})});
      expect(
          await StreamUrlValidator.isPlayableVideoUrl('https://x/a.mp4',
              lenient: true),
          isTrue);
      expect(
          await StreamUrlValidator.isPlayableVideoUrl('https://x/a.mp4'),
          isFalse); // strict keeps rejecting
    });

    test('2xx without content-length is alive', () async {
      mock({'https://x/a.mp4': (200, {})});
      expect(
          await StreamUrlValidator.isPlayableVideoUrl('https://x/a.mp4',
              lenient: true),
          isTrue);
      expect(
          await StreamUrlValidator.isPlayableVideoUrl('https://x/a.mp4'),
          isFalse); // strict keeps rejecting
    });

    // A slow-to-first-byte origin (a Plex server waking up behind an addon)
    // is the case this carve-out exists for: the link plays fine, it just
    // answers later than the probe waits.
    test('a timed-out probe is alive (strict still rejects)', () async {
      stallingClient();
      expect(
          await StreamUrlValidator.isPlayableVideoUrl('https://slow/a.mp4',
              lenient: true),
          isTrue);
      expect(
          await StreamUrlValidator.isPlayableVideoUrl('https://slow/a.mp4'),
          isFalse);
    });

    // The timeout is per HOP, so a chain that stalls midway must land in the
    // same carve-out rather than falling through to the dead path.
    test('a timeout MID-redirect-chain is alive (strict rejects)', () async {
      const chain = {
        'https://x/a': (302, {'location': 'https://slow/b'}),
      };
      var requested = stallingClient(before: chain);
      expect(
          await StreamUrlValidator.isPlayableVideoUrl('https://x/a',
              lenient: true),
          isTrue);
      // Pins that the redirect was really followed — without this a
      // regression that stopped following redirects would time out on hop 1
      // and still return true.
      expect(requested, ['https://x/a', 'https://slow/b']);

      requested = stallingClient(before: chain);
      expect(
          await StreamUrlValidator.isPlayableVideoUrl('https://x/a'), isFalse);
      expect(requested, ['https://x/a', 'https://slow/b']);
    });

    // The guard must be narrow: only a timeout is "no signal". A refused
    // connection is the host answering no, and must still reject.
    test('transport errors are NOT excused by lenient mode', () async {
      StreamUrlValidator.clientFactory =
          () => MockClient((_) async => throw Exception('connection refused'));
      expect(
          await StreamUrlValidator.isPlayableVideoUrl('https://x/a.mp4',
              lenient: true),
          isFalse);
    });

    test('positive evidence of death still rejects', () async {
      mock({
        'https://x/gone.mp4': (404, {}),
        'https://x/tiny.mp4': (200, {'content-length': '$_small'}),
      });
      expect(
          await StreamUrlValidator.isPlayableVideoUrl('https://x/gone.mp4',
              lenient: true),
          isFalse);
      expect(
          await StreamUrlValidator.isPlayableVideoUrl('https://x/tiny.mp4',
              lenient: true),
          isFalse);
    });
  });
}

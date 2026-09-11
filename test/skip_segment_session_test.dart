import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/playback/skip_segment_session.dart';
import 'package:debrify/services/skip_segment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

// Transport boundary only: the production provider constructs requests and
// parses response bodies. The fixture never copies session selection logic.
class _Transport extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final replies = <Completer<http.StreamedResponse>>[];
  int closes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    final reply = Completer<http.StreamedResponse>();
    replies.add(reply);
    return reply.future;
  }

  void complete(int index, {int endSeconds = 20}) {
    replies[index].complete(
      http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'segments': {
                'intro': {'start_ms': 10000, 'end_ms': endSeconds * 1000},
              },
            }),
          ),
        ),
        200,
      ),
    );
  }

  @override
  void close() {
    closes++;
  }
}

SkipSegmentRequest request(int episode) => (
  imdbId: 'tt1234567',
  season: 1,
  episode: episode,
  duration: const Duration(seconds: 60),
  key: 'skipdb:tt1234567:1:$episode:60',
);

void main() {
  late SkipSegmentSession session;
  late _Transport transport;
  SkipSegmentRequest? current;
  String? loaded;
  bool mounted = true;
  final publications = <(String, SkipSegments)>[];

  // An event turn settles the real provider's response stream and the session
  // callback chain. No native time, sleeps, or copied completion algorithm.
  Future<void> drain() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>(() {});
    }
  }

  void configure(bool enabled, {_Transport? client}) {
    http.runWithClient(
      () => session.configure(enabled, 'skipdb'),
      () => client ?? transport,
    );
  }

  setUp(() {
    transport = _Transport();
    current = request(1);
    loaded = null;
    mounted = true;
    publications.clear();
    session = SkipSegmentSession(
      currentRequest: () => current,
      isMounted: () => mounted,
      loadedKey: () => loaded,
      publish: (segments, key) {
        loaded = key;
        publications.add((key, segments));
      },
    );
  });
  tearDown(() async {
    mounted = false;
    session.close();
    for (final reply in transport.replies) {
      if (!reply.isCompleted) {
        reply.complete(http.StreamedResponse(const Stream.empty(), 404));
      }
    }
    await drain();
  });

  test('missing provider or current identity starts no transport', () {
    session.sync();
    configure(true);
    current = null;
    session.sync();
    expect(transport.requests, isEmpty);
    expect(publications, isEmpty);
  });

  test(
    'pending and loaded requests deduplicate real provider traffic',
    () async {
      configure(true);
      session.sync();
      session.sync();
      expect(transport.requests, hasLength(1));
      expect(transport.requests.single.url.queryParameters, {
        'imdb_id': 'tt1234567',
        'season': '1',
        'episode': '1',
        'duration': '60',
      });
      transport.complete(0);
      await drain();
      expect(publications.single.$2.intro!.end, const Duration(seconds: 20));
      session.sync();
      expect(transport.requests, hasLength(1));
      expect(publications, hasLength(1));
    },
  );

  test(
    'reset retains cache for synchronous revisit without another fetch',
    () async {
      configure(true);
      session.sync();
      transport.complete(0);
      await drain();
      session.reset();
      loaded = null;
      session.sync();
      expect(transport.requests, hasLength(1));
      expect(publications, hasLength(2));
      expect(publications.last.$2, same(publications.first.$2));
    },
  );

  test(
    'out-of-order old success caches but does not replace newer episode',
    () async {
      configure(true);
      session.sync();
      current = request(2);
      session.sync();
      transport.complete(1, endSeconds: 30);
      await drain();
      transport.complete(0);
      await drain();
      expect(publications, hasLength(1));
      expect(publications.single.$1, request(2).key);
      expect(publications.single.$2.intro!.end, const Duration(seconds: 30));
      current = request(1);
      loaded = null;
      session.sync();
      expect(publications.last.$2.intro!.end, const Duration(seconds: 20));
      expect(transport.requests, hasLength(2));
    },
  );

  test(
    'live identity guard rejects completion even without another fetch',
    () async {
      configure(true);
      session.sync();
      current = request(2);
      transport.complete(0);
      await drain();
      expect(publications, isEmpty);
      current = request(1);
      session.sync();
      expect(publications.single.$1, request(1).key);
      expect(transport.requests, hasLength(1));
    },
  );

  test(
    'reset invalidates held same-key success but still caches its result',
    () async {
      configure(true);
      session.sync();
      session.reset();
      transport.complete(0);
      await drain();
      expect(publications, isEmpty);
      session.sync();
      expect(publications.single.$2.intro!.end, const Duration(seconds: 20));
      expect(transport.requests, hasLength(1));
    },
  );

  test(
    'transport failure publishes an empty result and caches the miss',
    () async {
      configure(true);
      session.sync();
      transport.replies.single.completeError(
        const FormatException('invalid JSON'),
      );
      await drain();
      expect(publications.single.$2, same(SkipSegments.empty));
      session.reset();
      loaded = null;
      session.sync();
      expect(publications, hasLength(2));
      expect(publications.last.$2, same(SkipSegments.empty));
      expect(transport.requests, hasLength(1));
    },
  );

  test(
    'reset invalidates held error and retains the empty cache entry',
    () async {
      configure(true);
      session.sync();
      session.reset();
      transport.replies.single.completeError(
        const FormatException('invalid JSON'),
      );
      await drain();
      expect(publications, isEmpty);
      session.sync();
      expect(publications.single.$2, same(SkipSegments.empty));
      expect(transport.requests, hasLength(1));
    },
  );

  for (final failure in [false, true]) {
    test(
      'unmounted host receives no late ${failure ? 'failure' : 'success'} publication',
      () async {
        configure(true);
        session.sync();
        mounted = false;
        if (failure) {
          transport.replies.single.completeError(
            const FormatException('invalid JSON'),
          );
        } else {
          transport.complete(0);
        }
        await drain();
        session.sync();
        expect(publications, isEmpty);
        expect(transport.requests, hasLength(1));
      },
    );
  }

  test(
    'close invalidates in-flight result and releases provider once',
    () async {
      configure(true);
      session.sync();
      session.close();
      expect(transport.closes, 1);
      transport.complete(0);
      await drain();
      session.sync();
      session.close();
      expect(publications, isEmpty);
      expect(transport.requests, hasLength(1));
      expect(transport.closes, 1);
    },
  );

  test(
    'reconfigure closes previous provider and disabled mode starts no fetch',
    () async {
      configure(true);
      final replacement = _Transport();
      configure(true, client: replacement);
      expect(transport.closes, 1);
      configure(false);
      expect(replacement.closes, 1);
      session.sync();
      expect(transport.requests, isEmpty);
      expect(replacement.requests, isEmpty);
    },
  );

  test(
    'legacy same-key cleanup exposes old cached result while replacement is pending',
    () async {
      configure(true);
      session.sync();
      session.reset();
      session.sync();
      expect(transport.requests, hasLength(2));
      transport.complete(0);
      await drain();
      expect(publications, isEmpty);
      // Preserve the current host's key-only whenComplete quirk: completion of
      // the old request clears the same-key loading marker for its replacement.
      session.sync();
      expect(publications.single.$2.intro!.end, const Duration(seconds: 20));
      expect(transport.requests, hasLength(2));
      transport.complete(1, endSeconds: 30);
      await drain();
      expect(publications, hasLength(2));
      expect(publications.last.$2.intro!.end, const Duration(seconds: 30));
    },
  );
}

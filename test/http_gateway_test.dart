import 'dart:async';
import 'dart:convert';

import 'package:debrify/core/http/gateway.dart';
import 'package:debrify/core/http/default_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Plain `test()`, not `testWidgets()`: no binding, no SharedPreferences mock,
/// no socket. That is the point of the port.
void main() {
  late List<Duration> slept;

  setUp(() => slept = []);

  DefaultHttpGateway gatewayFor(
    Future<http.Response> Function(http.Request) handler, {
    Duration defaultTimeout = const Duration(seconds: 15),
    RetryPolicy defaultRetry = RetryPolicy.standard,
  }) => DefaultHttpGateway(
    client: MockClient(handler),
    userAgent: 'Debrify/9.9.9 (test)',
    defaultTimeout: defaultTimeout,
    defaultRetry: defaultRetry,
    sleep: (d) async => slept.add(d),
  );

  final url = Uri.parse('https://example.test/thing');

  group('headers', () {
    test('every request carries the one User-Agent', () async {
      String? seen;
      final gateway = gatewayFor((request) async {
        seen = request.headers['user-agent'];
        return http.Response('ok', 200);
      });

      await gateway.get(url);

      expect(seen, 'Debrify/9.9.9 (test)');
    });

    test('a caller header wins over the default, case-insensitively', () async {
      String? seen;
      final gateway = gatewayFor((request) async {
        seen = request.headers['user-agent'];
        return http.Response('ok', 200);
      });

      await gateway.get(url, headers: {'User-Agent': 'Custom/1'});

      expect(seen, 'Custom/1');
    });
  });

  group('timeouts', () {
    test('a request with no answer fails as HttpTimeoutFailure', () async {
      final gateway = gatewayFor(
        (_) => Completer<http.Response>().future,
        defaultTimeout: const Duration(milliseconds: 20),
        defaultRetry: RetryPolicy.none,
      );

      await expectLater(
        gateway.get(url),
        throwsA(
          isA<HttpTimeoutFailure>()
              .having((e) => e.timeout.inMilliseconds, 'timeout', 20)
              .having((e) => e.attempts, 'attempts', 1),
        ),
      );
    });

    test('the per-call timeout overrides the default', () async {
      final gateway = gatewayFor(
        (_) => Completer<http.Response>().future,
        defaultTimeout: const Duration(seconds: 30),
        defaultRetry: RetryPolicy.none,
      );

      await expectLater(
        gateway.get(url, timeout: const Duration(milliseconds: 15)),
        throwsA(
          isA<HttpTimeoutFailure>().having(
            (e) => e.timeout.inMilliseconds,
            'timeout',
            15,
          ),
        ),
      );
    });

    test(
      'a timeout is transient, so the retry budget is spent on it',
      () async {
        var calls = 0;
        final gateway = gatewayFor((_) {
          calls++;
          return Completer<http.Response>().future;
        }, defaultTimeout: const Duration(milliseconds: 10));

        await expectLater(gateway.get(url), throwsA(isA<HttpTimeoutFailure>()));

        expect(calls, 3);
        expect(slept, [
          const Duration(milliseconds: 500),
          const Duration(seconds: 1),
        ]);
      },
    );
  });

  group('retries', () {
    test('a 500 is retried and a later success is returned', () async {
      var calls = 0;
      final gateway = gatewayFor((_) async {
        calls++;
        if (calls < 3) return http.Response('down', 500);
        return http.Response('recovered', 200);
      });

      final response = await gateway.get(url);

      expect(calls, 3);
      expect(response.statusCode, 200);
      expect(response.body, 'recovered');
    });

    test('a 404 is the answer, not a hiccup — no retry', () async {
      var calls = 0;
      final gateway = gatewayFor((_) async {
        calls++;
        return http.Response('nope', 404);
      });

      final response = await gateway.get(url);

      expect(calls, 1);
      expect(response.statusCode, 404);
      expect(slept, isEmpty);
    });

    test('a dropped connection is retried', () async {
      var calls = 0;
      final gateway = gatewayFor((_) async {
        calls++;
        if (calls < 2) throw http.ClientException('Connection closed', url);
        return http.Response('ok', 200);
      });

      final response = await gateway.get(url);

      expect(calls, 2);
      expect(response.ok, isTrue);
    });

    test('the budget is finite and the last failure surfaces', () async {
      var calls = 0;
      final gateway = gatewayFor((_) async {
        calls++;
        throw http.ClientException('refused', url);
      });

      await expectLater(
        gateway.get(url),
        throwsA(
          isA<HttpNetworkFailure>().having((e) => e.attempts, 'attempts', 3),
        ),
      );
      expect(calls, 3);
    });

    test('RetryPolicy.none makes exactly one attempt', () async {
      var calls = 0;
      final gateway = gatewayFor((_) async {
        calls++;
        return http.Response('down', 500);
      }, defaultRetry: RetryPolicy.none);

      final response = await gateway.get(url);

      expect(calls, 1);
      expect(response.statusCode, 500);
    });

    test('backoff grows geometrically and stops at the cap', () {
      const policy = RetryPolicy(
        initialBackoff: Duration(milliseconds: 500),
        multiplier: 2,
        maxBackoff: Duration(seconds: 2),
      );

      expect(policy.backoffFor(1), const Duration(milliseconds: 500));
      expect(policy.backoffFor(2), const Duration(seconds: 1));
      expect(policy.backoffFor(3), const Duration(seconds: 2));
      expect(policy.backoffFor(9), const Duration(seconds: 2));
    });
  });

  group('Retry-After', () {
    test(
      'a 429 waits the header out instead of the computed backoff',
      () async {
        var calls = 0;
        final gateway = gatewayFor((_) async {
          calls++;
          if (calls == 1) {
            return http.Response(
              'slow down',
              429,
              headers: {'retry-after': '3'},
            );
          }
          return http.Response('ok', 200);
        });

        await gateway.get(url);

        expect(slept, [const Duration(seconds: 3)]);
      },
    );

    test('a hostile Retry-After cannot stall past the cap', () async {
      var calls = 0;
      final gateway = gatewayFor((_) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            'go away',
            503,
            headers: {'retry-after': '86400'},
          );
        }
        return http.Response('ok', 200);
      });

      await gateway.get(url);

      expect(slept, [const Duration(seconds: 10)]);
    });

    test('an unparseable Retry-After falls back to the backoff', () async {
      var calls = 0;
      final gateway = gatewayFor((_) async {
        calls++;
        if (calls == 1) {
          return http.Response('?', 503, headers: {'retry-after': 'soonish'});
        }
        return http.Response('ok', 200);
      });

      await gateway.get(url);

      expect(slept, [const Duration(milliseconds: 500)]);
    });
  });

  group('size cap', () {
    test('an oversized body is abandoned rather than buffered', () async {
      final gateway = gatewayFor((_) async => http.Response('x' * 5000, 200));

      await expectLater(
        gateway.get(url, maxBytes: 1000),
        throwsA(
          isA<HttpTooLargeFailure>().having(
            (e) => e.maxBytes,
            'maxBytes',
            1000,
          ),
        ),
      );
    });

    test(
      'over-cap is not retried — the payload is that size every time',
      () async {
        var calls = 0;
        final gateway = gatewayFor((_) async {
          calls++;
          return http.Response('x' * 5000, 200);
        });

        await expectLater(
          gateway.get(url, maxBytes: 10),
          throwsA(isA<HttpTooLargeFailure>()),
        );
        expect(calls, 1);
      },
    );
  });

  group('expectOk', () {
    test('off by default, so a status comes back as data', () async {
      final gateway = gatewayFor(
        (_) async => http.Response('teapot', 418),
        defaultRetry: RetryPolicy.none,
      );

      final response = await gateway.get(url);

      expect(response.statusCode, 418);
      expect(response.ok, isFalse);
    });

    test('on, a non-2xx throws and carries the response', () async {
      final gateway = gatewayFor(
        (_) async => http.Response('teapot', 418),
        defaultRetry: RetryPolicy.none,
      );

      await expectLater(
        gateway.get(url, expectOk: true),
        throwsA(
          isA<HttpStatusFailure>()
              .having((e) => e.statusCode, 'statusCode', 418)
              .having((e) => e.response.body, 'body', 'teapot'),
        ),
      );
    });
  });

  group('decoding', () {
    test('a malformed byte does not lose the whole payload', () async {
      final gateway = gatewayFor(
        (_) async => http.Response.bytes([0x68, 0x69, 0xff], 200),
      );

      final response = await gateway.get(url);

      expect(response.body, startsWith('hi'));
    });

    test('a declared latin-1 charset is honoured', () async {
      final gateway = gatewayFor(
        (_) async => http.Response.bytes(
          [0x63, 0x61, 0x66, 0xe9],
          200,
          headers: {'content-type': 'text/plain; charset=iso-8859-1'},
        ),
      );

      final response = await gateway.get(url);

      expect(response.body, 'café');
    });

    test(
      'declaredContentLength reads the header, length reads the bytes',
      () async {
        final gateway = gatewayFor(
          (_) async =>
              http.Response('abc', 200, headers: {'content-length': '999'}),
        );

        final response = await gateway.get(url);

        expect(response.declaredContentLength, 999);
        expect(response.length, 3);
      },
    );
  });

  group('bodies', () {
    test('a form map is sent as bodyFields', () async {
      String? seen;
      final gateway = gatewayFor((request) async {
        seen = request.body;
        return http.Response('ok', 200);
      });

      await gateway.post(url, body: {'a': '1', 'b': '2'});

      expect(seen, 'a=1&b=2');
    });

    test('a JSON string rides through untouched', () async {
      String? seen;
      final gateway = gatewayFor((request) async {
        seen = request.body;
        return http.Response('ok', 200);
      });

      await gateway.post(
        url,
        body: jsonEncode({'hash': 'abc'}),
        headers: {'content-type': 'application/json'},
      );

      expect(seen, '{"hash":"abc"}');
    });

    test('an unsupported body type is rejected before any socket opens', () {
      final gateway = gatewayFor((_) async => http.Response('ok', 200));

      expect(() => gateway.post(url, body: 42), throwsA(isA<ArgumentError>()));
    });
  });

  test('HEAD does not follow redirects', () async {
    bool? follow;
    final gateway = gatewayFor((request) async {
      follow = request.followRedirects;
      return http.Response('', 302, headers: {'location': '/elsewhere'});
    }, defaultRetry: RetryPolicy.none);

    await gateway.head(url);

    expect(follow, isFalse);
  });

  group('typed decoding', () {
    test('getJson hands the decoded tree to the caller\'s decoder', () async {
      final gateway = gatewayFor(
        (_) async => http.Response('{"id":"abc","size":12}', 200),
      );

      final torrent = await gateway.getJson(url, _Torrent.fromJson);

      expect(torrent.id, 'abc');
      expect(torrent.size, 12);
    });

    test('getJsonList decodes an array of objects', () async {
      final gateway = gatewayFor(
        (_) async =>
            http.Response('[{"id":"a","size":1},{"id":"b","size":2}]', 200),
      );

      final torrents = await gateway.getJsonList(url, _Torrent.fromJson);

      expect(torrents.map((t) => t.id), ['a', 'b']);
    });

    test(
      'an HTML error page behind a 200 is HttpDecodeFailure, not a crash',
      () async {
        final gateway = gatewayFor(
          (_) async => http.Response('<html>captive portal</html>', 200),
        );

        await expectLater(
          gateway.getJson(url, _Torrent.fromJson),
          throwsA(isA<HttpDecodeFailure>()),
        );
      },
    );

    test('a field that changed type fails the same way', () async {
      final gateway = gatewayFor(
        (_) async => http.Response('{"id":"abc","size":"huge"}', 200),
      );

      await expectLater(
        gateway.getJson(url, _Torrent.fromJson),
        throwsA(isA<HttpDecodeFailure>()),
      );
    });

    test('a typed request treats a non-2xx as a failure, not a body', () async {
      final gateway = gatewayFor(
        (_) async => http.Response('{"error":"nope"}', 401),
        defaultRetry: RetryPolicy.none,
      );

      await expectLater(
        gateway.getJson(url, _Torrent.fromJson),
        throwsA(
          isA<HttpStatusFailure>().having((e) => e.statusCode, 'status', 401),
        ),
      );
    });

    test('postJson encodes the payload and sets the content type', () async {
      String? seenBody;
      String? seenType;
      final gateway = gatewayFor((request) async {
        seenBody = request.body;
        seenType = request.headers['content-type'];
        return http.Response('{"id":"x","size":0}', 200);
      });

      await gateway.postJson(
        url,
        _Torrent.fromJson,
        json: {'magnet': 'magnet:?xt=abc'},
      );

      expect(seenBody, '{"magnet":"magnet:?xt=abc"}');
      expect(seenType, startsWith('application/json'));
    });

    test('a caller content-type still wins', () async {
      String? seenType;
      final gateway = gatewayFor((request) async {
        seenType = request.headers['content-type'];
        return http.Response('{"id":"x","size":0}', 200);
      });

      await gateway.postJson(
        url,
        _Torrent.fromJson,
        json: {'a': 1},
        headers: {'content-type': 'application/vnd.custom+json'},
      );

      expect(seenType, startsWith('application/vnd.custom+json'));
    });

    test('the retry count survives into the decode failure', () async {
      var calls = 0;
      final gateway = gatewayFor((_) async {
        calls++;
        if (calls < 3) return http.Response('down', 500);
        return http.Response('not json', 200);
      });

      await expectLater(
        gateway.getJson(url, _Torrent.fromJson),
        throwsA(
          isA<HttpDecodeFailure>().having((e) => e.attempts, 'attempts', 3),
        ),
      );
    });
  });

  group('send — the single generic entry point', () {
    test('dispatches on the method and decodes into K', () async {
      final seen = <String>[];
      final gateway = gatewayFor((request) async {
        seen.add(request.method);
        return http.Response('{"id":"a","size":1}', 200);
      });

      for (final method in HttpMethod.values) {
        await gateway.send(
          url: url,
          decode: _Torrent.fromJson,
          method: method,
          json: const {'x': 1},
        );
      }

      expect(seen, ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']);
    });

    test('defaults to GET', () async {
      String? seen;
      final gateway = gatewayFor((request) async {
        seen = request.method;
        return http.Response('{"id":"a","size":1}', 200);
      });

      await gateway.send(url: url, decode: _Torrent.fromJson);

      expect(seen, 'GET');
    });

    test(
      'carries the timeout and retry policy like every other call',
      () async {
        var calls = 0;
        final gateway = gatewayFor((_) {
          calls++;
          return Completer<http.Response>().future;
        }, defaultTimeout: const Duration(milliseconds: 10));

        await expectLater(
          gateway.send(url: url, decode: _Torrent.fromJson),
          throwsA(isA<HttpTimeoutFailure>()),
        );
        expect(calls, 3);
      },
    );
  });

  group('empty bodies', () {
    test(
      'a 204 hands the decoder null instead of failing to parse ""',
      () async {
        final gateway = gatewayFor((_) async => http.Response('', 204));

        final result = await gateway.send<bool>(
          url: url,
          decode: (json) => json == null,
          method: HttpMethod.delete,
        );

        expect(result, isTrue);
      },
    );

    test('a 200 with no body is treated the same way', () async {
      final gateway = gatewayFor((_) async => http.Response('', 200));

      final result = await gateway.getJson<String>(url, (json) => '$json');

      expect(result, 'null');
    });

    test(
      'a decoder that cannot accept null says so as HttpDecodeFailure',
      () async {
        final gateway = gatewayFor((_) async => http.Response('', 204));

        await expectLater(
          gateway.getJson(url, _Torrent.fromJson),
          throwsA(isA<HttpDecodeFailure>()),
        );
      },
    );
  });
}

/// Stands in for the 25 models that already carry a `fromJson`.
class _Torrent {
  final String id;
  final int size;

  const _Torrent(this.id, this.size);

  static _Torrent fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return _Torrent(map['id'] as String, map['size'] as int);
  }
}

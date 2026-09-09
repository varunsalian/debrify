import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:debrify/services/tmdb_http_client.dart';

class _Socket extends Fake implements Socket {
  bool destroyed = false;
  @override
  InternetAddress get remoteAddress => InternetAddress('13.1.2.3');
  @override
  void destroy() {
    destroyed = true;
  }
}

Future<Directory> _tlsFixture({String host = 'api.themoviedb.org'}) async {
  final dir = await Directory.systemTemp.createTemp('debrify-tmdb-tls-');
  addTearDown(() => dir.delete(recursive: true));
  Future<void> openssl(List<String> args) async {
    final result = await Process.run(
      'openssl',
      args,
      workingDirectory: dir.path,
    );
    if (result.exitCode != 0) {
      throw StateError('Test certificate generation failed: ${result.stderr}');
    }
  }

  await openssl([
    'req',
    '-x509',
    '-newkey',
    'rsa:2048',
    '-nodes',
    '-keyout',
    'root.key',
    '-out',
    'root.pem',
    '-days',
    '365',
    '-subj',
    '/CN=Debrify test CA',
    '-addext',
    'basicConstraints=critical,CA:TRUE',
  ]);
  await openssl([
    'req',
    '-new',
    '-newkey',
    'rsa:2048',
    '-nodes',
    '-keyout',
    'server.key',
    '-out',
    'server.csr',
    '-subj',
    '/CN=$host',
  ]);
  await File('${dir.path}/extensions').writeAsString(
    'subjectAltName=DNS:$host\nbasicConstraints=critical,CA:FALSE\n'
    'keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n',
  );
  await openssl([
    'x509',
    '-req',
    '-in',
    'server.csr',
    '-CA',
    'root.pem',
    '-CAkey',
    'root.key',
    '-set_serial',
    '2',
    '-out',
    'server.pem',
    '-days',
    '30',
    '-extfile',
    'extensions',
  ]);
  return dir;
}

void main() {
  final uri = Uri.parse('https://api.themoviedb.org/3/discover/movie');
  http.Response answer({int ttl = 60, List<String> ips = const ['13.1.2.3']}) =>
      http.Response(
        jsonEncode({
          'Status': 0,
          'Answer': [
            for (final ip in ips) {'type': 1, 'TTL': ttl, 'data': ip},
          ],
        }),
        200,
      );
  ConnectionTask<Socket> success() =>
      ConnectionTask.fromSocket(Future.value(_Socket()), () {});

  test(
    'read failover is scoped, shared, expires, and can return to primary',
    () {
      var now = DateTime.utc(2026, 9, 9);
      final cache = TmdbDnsCache();
      final first = TmdbConnections(dnsCache: cache, now: () => now);
      final read = uri.replace(query: 'page=2&with_genres=28%2C12');
      expect(first.readUri(read), read);
      first.reportTransportFailure(read);
      first.close();
      final next = TmdbConnections(dnsCache: cache, now: () => now);
      addTearDown(next.close);
      final alternate = read.replace(host: TmdbConnections.alternateHost);
      expect(next.readUri(read), alternate);
      for (final excluded in [
        read.replace(host: 'image.tmdb.org'),
        read.replace(host: 'addon.example'),
        read.replace(scheme: 'http'),
        read.replace(port: 8443),
        read.replace(userInfo: 'user:secret'),
        read.replace(path: '/not-api'),
      ]) {
        expect(next.readUri(excluded), excluded);
      }
      next.reportTransportFailure(alternate);
      expect(next.readUri(read), read);
      next.reportTransportFailure(read);
      expect(
        next.readUri(read),
        read,
        reason: 'alternate failure has a cooldown',
      );
      now = now.add(const Duration(seconds: 31));
      next.reportTransportFailure(read);
      expect(next.readUri(read), alternate);
      now = now.add(const Duration(minutes: 5));
      expect(next.readUri(read), read);
    },
  );

  test(
    'alternate read uses its own verified TLS hostname and Host header',
    () async {
      final fixture = await _tlsFixture(host: TmdbConnections.alternateHost);
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext()
          ..useCertificateChain('${fixture.path}/server.pem')
          ..usePrivateKey('${fixture.path}/server.key'),
      );
      addTearDown(() => server.close(force: true));
      final hosts = <String>[];
      server.listen((request) {
        hosts.add(request.headers.host!);
        request.response.write('ok');
        request.response.close();
      }, onError: (_) {});
      final routes = TmdbConnections(
        startConnect: (_, __) => TmdbConnections.startSocket(
          InternetAddress.loopbackIPv4,
          server.port,
        ),
      );
      addTearDown(routes.close);
      final client = routes.httpClient(
        context: SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates('${fixture.path}/root.pem'),
      );
      addTearDown(() => client.close(force: true));
      routes.reportTransportFailure(uri);
      final response = await (await client.getUrl(routes.readUri(uri))).close();
      expect(await response.transform(utf8.decoder).join(), 'ok');
      expect(hosts, [TmdbConnections.alternateHost]);
      await expectLater(client.getUrl(uri), throwsA(isA<HandshakeException>()));
    },
  );

  test(
    'HTTP resets rotate a cached edge instead of retrying the same address',
    () async {
      final cache = TmdbDnsCache()
        ..addresses = [InternetAddress('13.1.2.3'), InternetAddress('13.1.2.4')]
        ..expires = DateTime.now().add(const Duration(minutes: 1));
      final targets = <String>[];
      final c = TmdbConnections(
        dnsCache: cache,
        startConnect: (host, _) async {
          targets.add((host as InternetAddress).address);
          return success();
        },
      );
      addTearDown(c.close);
      await (await c.connect(uri, null, null)).socket;
      c.reportTransportFailure(uri);
      await (await c.connect(uri, null, null)).socket;
      expect(targets, ['13.1.2.3', '13.1.2.4']);
    },
  );

  test(
    'TLS or HTTP route failure survives client replacement and tries public DNS first',
    () async {
      final cache = TmdbDnsCache();
      final first = TmdbConnections(
        dnsCache: cache,
        startConnect: (_, __) async => success(),
      );
      await (await first.connect(uri, null, null)).socket;
      // TCP succeeded, but the request transport subsequently reported failure.
      first.reportTransportFailure(uri);
      first.close();
      final targets = <dynamic>[];
      var lookups = 0;
      var now = DateTime.now();
      final second = TmdbConnections(
        dnsCache: cache,
        now: () => now,
        dnsClientFactory: () => MockClient((_) async {
          lookups++;
          return answer();
        }),
        startConnect: (host, _) async {
          targets.add(host);
          return success();
        },
      );
      addTearDown(second.close);
      await (await second.connect(uri, null, null)).socket;
      expect(lookups, 1);
      expect((targets.single as InternetAddress).address, '13.1.2.3');
      now = now.add(const Duration(minutes: 6));
      targets.clear();
      await (await second.connect(uri, null, null)).socket;
      expect(targets, [TmdbConnections.host]);
    },
  );

  test('blocked public DNS can still use a healthy local route', () async {
    final c = TmdbConnections(
      dnsClientFactory: () => MockClient((_) async => http.Response('', 503)),
      startConnect: (host, _) async {
        expect(host, TmdbConnections.host);
        return success();
      },
    );
    addTearDown(c.close);
    c.reportTransportFailure(uri);
    await (await c.connect(uri, null, null)).socket;
  });

  test(
    'cancelled clients and unrelated origins do not poison shared routing',
    () {
      final cache = TmdbDnsCache();
      final c = TmdbConnections(dnsCache: cache);
      c.reportTransportFailure(Uri.https('example.com', '/'));
      expect(cache.preferPublicUntil, isNull);
      c.close();
      c.reportTransportFailure(uri);
      expect(cache.preferPublicUntil, isNull);
    },
  );

  test(
    'fallback retains TLS hostname verification and API Host header',
    () async {
      final fixture = await _tlsFixture();
      final cert = File('${fixture.path}/server.pem').readAsBytesSync();
      final serverContext = SecurityContext()
        ..useCertificateChainBytes(cert)
        ..usePrivateKey('${fixture.path}/server.key');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      addTearDown(() => server.close(force: true));
      final hosts = <String>[];
      server.listen((request) async {
        hosts.add(request.headers.host!);
        if (request.uri.path == '/large') {
          final received = await request.fold<int>(
            0,
            (n, bytes) => n + bytes.length,
          );
          request.response.headers.set('x-received', '$received');
          request.response.add(List<int>.filled(2 * 1024 * 1024, 65));
          await request.response.close();
          return;
        }
        request.response.write('ok');
        request.response.close();
      }, onError: (_) {});
      final c = TmdbConnections(
        dnsClientFactory: () => MockClient((_) async => answer()),
        startConnect: (host, port) async {
          if (host is String && host == TmdbConnections.host) {
            throw const SocketException('DNS failed');
          }
          return TmdbConnections.startSocket(
            InternetAddress.loopbackIPv4,
            server.port,
          );
        },
      );
      addTearDown(c.close);
      final client = c.httpClient(
        context: SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificates('${fixture.path}/root.pem'),
      );
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(uri)).close();
      expect(await response.transform(utf8.decoder).join(), 'ok');
      expect(hosts, [TmdbConnections.host]);
      final upload = await client.postUrl(uri.replace(path: '/large'));
      upload.add(List<int>.filled(2 * 1024 * 1024, 66));
      final downloaded = await upload.close();
      expect(downloaded.headers.value('x-received'), '${2 * 1024 * 1024}');
      expect(
        await downloaded.fold<int>(0, (n, bytes) => n + bytes.length),
        2 * 1024 * 1024,
      );
      // The same trusted certificate must fail for a different requested host.
      await expectLater(
        client.getUrl(Uri.parse('https://wrong-host.invalid/')),
        throwsA(isA<HandshakeException>()),
      );
      expect(hosts, [TmdbConnections.host, TmdbConnections.host]);
    },
  );

  for (final action in ['timeout', 'connections.close', 'http.close']) {
    test('stalled TLS closes transport on $action', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final receivedHello = Completer<void>();
      final disconnected = Completer<void>();
      final peers = <Socket>[];
      server.listen((peer) {
        peers.add(peer);
        peer.listen(
          (_) {
            if (!receivedHello.isCompleted) receivedHello.complete();
          },
          onDone: () {
            if (!disconnected.isCompleted) disconnected.complete();
          },
          onError: (_) {
            if (!disconnected.isCompleted) disconnected.complete();
          },
        );
      });
      addTearDown(() async {
        for (final peer in peers) {
          peer.destroy();
        }
        await server.close();
      });
      final c = TmdbConnections(
        tlsBudget: const Duration(milliseconds: 150),
        startConnect: (_, __) => TmdbConnections.startSocket(
          InternetAddress.loopbackIPv4,
          server.port,
        ),
      );
      final client = c.httpClient();
      addTearDown(() {
        client.close(force: true);
        c.close();
      });
      final result = expectLater(client.getUrl(uri), throwsA(isA<Exception>()));
      await receivedHello.future.timeout(const Duration(seconds: 2));
      if (action == 'connections.close') c.close();
      if (action == 'http.close') client.close(force: true);
      await result;
      await disconnected.future.timeout(const Duration(seconds: 2));
    });
  }

  test('configured HTTP proxy keeps the SDK CONNECT path', () async {
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    final methods = <String>[];
    proxy.listen((request) {
      methods.add(request.method);
      request.response.statusCode = 407;
      request.response.close();
    });
    final c = TmdbConnections(
      dnsClientFactory: () => MockClient((_) async {
        fail('Proxy connections must not use public DNS');
      }),
    );
    final client = c.httpClient()
      ..findProxy = (_) => 'PROXY 127.0.0.1:${proxy.port}';
    addTearDown(() {
      client.close(force: true);
      c.close();
    });
    await expectLater(client.getUrl(uri), throwsA(isA<HttpException>()));
    expect(methods, ['CONNECT']);
  });

  test('working system DNS does not contact a public resolver', () async {
    var lookups = 0;
    final c = TmdbConnections(
      dnsClientFactory: () => MockClient((_) async {
        lookups++;
        return answer();
      }),
      startConnect: (host, port) async {
        expect(host, TmdbConnections.host);
        return success();
      },
    );
    addTearDown(c.close);
    await (await c.connect(uri, null, null)).socket;
    expect(lookups, 0);
  });

  test(
    'fallback coalesces lookups, strips credentials and caches until TTL',
    () async {
      var lookups = 0;
      var now = DateTime(2026);
      final destinations = <String>[];
      final c = TmdbConnections(
        now: () => now,
        dnsClientFactory: () => MockClient((request) async {
          lookups++;
          expect(request.headers.containsKey('authorization'), false);
          expect(request.url.queryParameters['name'], TmdbConnections.host);
          expect(request.followRedirects, false);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return answer();
        }),
        startConnect: (host, port) async {
          destinations.add(
            host is InternetAddress ? host.address : host as String,
          );
          if (host is String) {
            throw const SocketException('system DNS unavailable');
          }
          return success();
        },
      );
      addTearDown(c.close);
      await Future.wait(
        List.generate(
          4,
          (_) async => (await c.connect(uri, null, null)).socket,
        ),
      );
      expect(lookups, 1);
      destinations.clear();
      await (await c.connect(uri, null, null)).socket;
      expect(destinations, ['13.1.2.3']);
      now = now.add(const Duration(seconds: 61));
      await (await c.connect(uri, null, null)).socket;
      expect(lookups, 2);
    },
  );

  test(
    'short-lived clients share DNS answers without sharing socket ownership',
    () async {
      final cache = TmdbDnsCache();
      var lookups = 0;
      TmdbConnections client() => TmdbConnections(
        dnsCache: cache,
        dnsClientFactory: () => MockClient((_) async {
          lookups++;
          return answer();
        }),
        startConnect: (host, port) async {
          if (host is String)
            throw const SocketException('system DNS unavailable');
          return success();
        },
      );
      final first = client();
      await (await first.connect(uri, null, null)).socket;
      first.close();
      final second = client();
      addTearDown(second.close);
      await (await second.connect(uri, null, null)).socket;
      expect(lookups, 1);
    },
  );

  test('proxy and other hosts bypass fallback', () async {
    final destinations = <String>[];
    final c = TmdbConnections(
      dnsClientFactory: () =>
          MockClient((_) async => throw StateError('unexpected DNS')),
      startConnect: (host, port) async {
        destinations.add('$host:$port');
        return success();
      },
    );
    addTearDown(c.close);
    await (await c.connect(uri, 'proxy.local', 8080)).socket;
    await (await c.connect(
      Uri.parse('https://api.trakt.tv/lists'),
      null,
      null,
    )).socket;
    await (await c.connect(
      Uri.parse('http://api.themoviedb.org/'),
      null,
      null,
    )).socket;
    expect(destinations, [
      'proxy.local:8080',
      'api.trakt.tv:443',
      'api.themoviedb.org:80',
    ]);
  });

  test('rejects private addresses and uses secondary resolver', () async {
    final hosts = <String>[];
    final c = TmdbConnections(
      dnsClientFactory: () => MockClient((r) async {
        hosts.add(r.url.host);
        return hosts.length == 1
            ? answer(ips: ['127.0.0.1', '192.168.1.1'])
            : answer();
      }),
      startConnect: (host, port) async {
        if (host is String) throw const SocketException('failed');
        expect((host as InternetAddress).address, '13.1.2.3');
        return success();
      },
    );
    addTearDown(c.close);
    await (await c.connect(uri, null, null)).socket;
    expect(hosts, ['dns.google', 'cloudflare-dns.com']);
  });

  test('failed resolvers are bounded and negatively cached', () async {
    var lookups = 0;
    final c = TmdbConnections(
      dnsClientFactory: () => MockClient((_) async {
        lookups++;
        return http.Response('bad', 503);
      }),
      startConnect: (_, __) async => throw const SocketException('failed'),
    );
    addTearDown(c.close);
    for (var i = 0; i < 2; i++) {
      await expectLater(
        (await c.connect(uri, null, null)).socket,
        throwsA(isA<SocketException>()),
      );
    }
    expect(lookups, 2);
  });

  test('stalled system connection is cancelled before fallback', () async {
    var cancelled = false;
    final stalled = Completer<Socket>();
    final c = TmdbConnections(
      connectBudget: const Duration(milliseconds: 10),
      dnsClientFactory: () => MockClient((_) async => answer()),
      startConnect: (host, port) async {
        if (host is String) {
          return ConnectionTask.fromSocket(stalled.future, () {
            cancelled = true;
          });
        }
        return success();
      },
    );
    addTearDown(c.close);
    await (await c.connect(uri, null, null)).socket;
    expect(cancelled, true);
    final lateSocket = _Socket();
    stalled.complete(lateSocket);
    await Future<void>.delayed(Duration.zero);
    expect(lateSocket.destroyed, true);
  });

  test(
    'closing during DNS lookup prevents a later socket connection',
    () async {
      final dns = Completer<http.Response>();
      var connects = 0;
      final c = TmdbConnections(
        dnsClientFactory: () => MockClient((_) => dns.future),
        startConnect: (_, __) async {
          connects++;
          throw const SocketException('failed');
        },
      );
      final task = await c.connect(uri, null, null);
      final check = expectLater(task.socket, throwsA(isA<SocketException>()));
      await Future<void>.delayed(Duration.zero);
      c.close();
      dns.complete(answer());
      await check;
      expect(connects, 1);
    },
  );
}

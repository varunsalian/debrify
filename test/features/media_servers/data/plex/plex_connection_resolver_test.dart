import 'dart:async';
import 'dart:convert';

import 'package:debrify/features/media_servers/data/media_server_http.dart';
import 'package:debrify/features/media_servers/data/plex/plex_account_link.dart';
import 'package:debrify/features/media_servers/data/plex/plex_connection_resolver.dart';
import 'package:debrify/features/media_servers/models/media_server_errors.dart';
import 'package:debrify/models/media_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/fake_plex_server.dart';

void main() {
  group('which addresses may be stored', () {
    const localHttps = PlexAccountConnection(
      uri: 'https://192-168-1-5.abc.plex.direct:32400/',
      https: true,
      local: true,
      relay: false,
    );
    const remoteHttps = PlexAccountConnection(
      uri: 'https://81-2-3-4.abc.plex.direct:32400/',
      https: true,
      local: false,
      relay: false,
    );
    const localHttp = PlexAccountConnection(
      uri: 'http://192.168.1.5:32400/',
      https: false,
      local: true,
      relay: false,
    );
    const remoteHttp = PlexAccountConnection(
      uri: 'http://81.2.3.4:32400/',
      https: false,
      local: false,
      relay: false,
    );
    const relay = PlexAccountConnection(
      uri: 'https://relay.abc.plex.direct:8443/',
      https: true,
      local: false,
      relay: true,
    );
    const all = [relay, remoteHttp, localHttp, remoteHttps, localHttps];

    test('encrypted addresses only, local first and relay last', () {
      expect(
        plexAllowedConnections(
          all,
          allowInsecureLocal: false,
        ).map((c) => (c.uri, c.relay)),
        [(localHttps.uri, false), (remoteHttps.uri, false), (relay.uri, true)],
      );
    });

    test('the opt-in adds only the local unencrypted address', () {
      expect(
        plexAllowedConnections(all, allowInsecureLocal: true).map((c) => c.uri),
        [localHttps.uri, remoteHttps.uri, localHttp.uri, relay.uri],
      );
      expect(plexHasInsecureLocal(all), isTrue);
      expect(plexHasInsecureLocal([remoteHttp, localHttps]), isFalse);
    });

    test('a remote unencrypted address is never used', () {
      expect(
        plexAllowedConnections([remoteHttp], allowInsecureLocal: true),
        isEmpty,
      );
    });
  });

  group('resolver', () {
    const home = 'https://home.plex.direct:32400/';
    const away = 'https://away.plex.direct:32400/';
    final account = plexAccount(
      baseUrl: home,
      connections: const [
        MediaServerConnection(uri: home),
        MediaServerConnection(uri: away, relay: true),
      ],
    );

    tearDown(() => PlexConnectionResolver.forget(account));

    PlexConnectionResolver resolver(
      List<http.Request> seen,
      String? Function(Uri) identity,
    ) => PlexConnectionResolver(
      MediaServerHttp(
        MockClient((request) async {
          seen.add(request);
          final id = identity(request.url);
          if (id == null) throw http.ClientException('unreachable');
          return http.Response(
            jsonEncode({
              'MediaContainer': {'machineIdentifier': id},
            }),
            200,
          );
        }),
        timeout: const Duration(seconds: 5),
      ),
    );

    test(
      'the first address in priority order that proves its identity wins',
      () async {
        final seen = <http.Request>[];
        final resolved = await resolver(
          seen,
          (_) => plexServerId,
        ).resolve(account, cacheScope: 'a');
        expect(resolved.baseUrl, home);
        expect(resolved.usesRelay, isFalse);
        for (final request in seen) {
          expect(request.headers.containsKey('X-Plex-Token'), isFalse);
        }
      },
    );

    test('another server at the same address is never trusted', () async {
      final seen = <http.Request>[];
      final resolved = await resolver(
        seen,
        (url) =>
            url.host == 'home.plex.direct' ? 'some-other-server' : plexServerId,
      ).resolve(account, cacheScope: 'b');
      expect(resolved.baseUrl, away);
      expect(resolved.usesRelay, isTrue);
    });

    test('nothing reachable is an unreachable error', () async {
      await expectLater(
        resolver([], (_) => null).resolve(account, cacheScope: 'c'),
        throwsA(isA<MediaServerUnreachable>()),
      );
    });

    test('a result is reused until forgotten, then probed again', () async {
      final seen = <http.Request>[];
      final probe = resolver(seen, (_) => plexServerId);
      await probe.resolve(account, cacheScope: 'd');
      await probe.resolve(account, cacheScope: 'd');
      expect(seen, hasLength(2));
      PlexConnectionResolver.forget(account.withBaseUrl(away));
      await probe.resolve(account, cacheScope: 'd');
      expect(seen, hasLength(4));
    });

    test('scopes do not share a result', () async {
      final seen = <http.Request>[];
      final probe = resolver(seen, (_) => plexServerId);
      await probe.resolve(account, cacheScope: 'profile-1');
      await probe.resolve(account, cacheScope: 'profile-2');
      expect(seen, hasLength(4));
    });

    test('parallel callers share one probe', () async {
      final seen = <http.Request>[];
      final probe = resolver(seen, (_) => plexServerId);
      await Future.wait([
        probe.resolve(account, cacheScope: 'e'),
        probe.resolve(account, cacheScope: 'e'),
      ]);
      expect(seen, hasLength(2));
    });

    test('a slow lower-priority address does not delay the answer', () async {
      final never = Completer<http.Response>();
      final probe = PlexConnectionResolver(
        MediaServerHttp(
          MockClient((request) async {
            if (request.url.host == 'away.plex.direct') return never.future;
            return http.Response(
              jsonEncode({
                'MediaContainer': {'machineIdentifier': plexServerId},
              }),
              200,
            );
          }),
          timeout: const Duration(seconds: 5),
        ),
      );
      final resolved = await probe
          .resolve(account, cacheScope: 'g')
          .timeout(const Duration(seconds: 1));
      expect(resolved.baseUrl, home);
    });

    test(
      'a probe cut short by the search budget is not "unreachable"',
      () async {
        await expectLater(
          resolver([], (_) => null).resolve(
            account,
            cacheScope: 'h',
            deadline: DateTime.now().add(const Duration(milliseconds: 200)),
          ),
          throwsA(isA<MediaServerLookupBudgetExhausted>()),
        );
      },
    );

    test(
      'forgetting during a probe keeps its result out of the cache',
      () async {
        final seen = <http.Request>[];
        final gate = Completer<void>();
        final probe = PlexConnectionResolver(
          MediaServerHttp(
            MockClient((request) async {
              seen.add(request);
              await gate.future;
              return http.Response(
                jsonEncode({
                  'MediaContainer': {'machineIdentifier': plexServerId},
                }),
                200,
              );
            }),
            timeout: const Duration(seconds: 5),
          ),
        );
        final first = probe.resolve(account, cacheScope: 'i');
        await Future<void>.delayed(Duration.zero);
        PlexConnectionResolver.forget(account);
        gate.complete();
        await first;
        await probe.resolve(account, cacheScope: 'i');
        expect(seen, hasLength(4));
      },
    );

    test('an exhausted search budget is reported as such', () async {
      await expectLater(
        resolver([], (_) => plexServerId).resolve(
          account,
          cacheScope: 'f',
          deadline: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
        throwsA(isA<MediaServerLookupBudgetExhausted>()),
      );
    });
  });
}

import 'dart:convert';
import 'package:debrify/models/media_server.dart';
import 'package:debrify/models/media_server_library.dart';
import 'package:debrify/services/media_server_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final kind in MediaServerKind.values) {
    final account = MediaServerAccount(
      kind: kind,
      baseUrl: 'https://server.example/base/',
      userId: 'user1',
      token: 'private-token',
      serverId: 'server1',
      deviceId: 'device1',
    );
    test(
      '${kind.label} browse, search and resume use authenticated user scope',
      () async {
        final requests = <http.Request>[];
        var checks = 0;
        final client = MediaServerClient(
          client: MockClient((request) async {
            requests.add(request);
            expect(request.headers['X-Emby-Token'], account.token);
            expect(request.followRedirects, false);
            expect(request.url.toString(), isNot(contains(account.token)));
            return http.Response(
              jsonEncode({
                'Items': [
                  {'Id': 'recording1', 'Name': 'Recording', 'Type': 'Video'},
                ],
                'TotalRecordCount': 61,
              }),
              200,
            );
          }),
        );
        addTearDown(client.close);
        await client.library(
          account,
          views: true,
          authorize: () async {
            checks++;
          },
        );
        expect(requests.last.url.path, '/base/Users/user1/Views');
        final page = await client.library(
          account,
          parentId: 'library1',
          offset: 60,
        );
        expect(page.nextOffset, isNull);
        expect(page.items.single.playable, true);
        expect(
          requests.last.url.queryParameters,
          containsPair('Recursive', 'false'),
        );
        expect(
          requests.last.url.queryParameters,
          containsPair('StartIndex', '60'),
        );
        await client.library(account, parentId: 'series1', episodeOrder: true);
        expect(
          requests.last.url.queryParameters['SortBy'],
          'ParentIndexNumber,IndexNumber,SortName',
        );
        await client.library(
          account,
          parentId: 'library1',
          search: '  résumé  ',
        );
        expect(requests.last.url.queryParameters['SearchTerm'], 'résumé');
        expect(requests.last.url.queryParameters['Recursive'], 'true');
        await client.library(account, parentId: 'library1', mode: 'resume');
        expect(requests.last.url.queryParameters['Filters'], 'IsResumable');
        expect(
          requests.last.url.queryParameters['SortBy'],
          'DatePlayed,SortName',
        );
        expect(checks, greaterThanOrEqualTo(2));
      },
    );
    test(
      '${kind.label} artwork keeps auth in headers and rechecks after response',
      () async {
        var checks = 0;
        final client = MediaServerClient(
          client: MockClient((request) async {
            expect(request.url.path, '/base/Items/item1/Images/Primary');
            expect(request.headers['X-Emby-Token'], account.token);
            expect(request.followRedirects, false);
            expect(request.url.toString(), isNot(contains(account.token)));
            return http.Response.bytes([1, 2, 3], 200);
          }),
        );
        addTearDown(client.close);
        await expectLater(
          client.libraryImage(
            account,
            'item1',
            authorize: () async {
              if (++checks == 2) throw StateError('revoked');
            },
          ),
          throwsStateError,
        );
      },
    );
    test(
      '${kind.label} malformed identities never request another path',
      () async {
        var requests = 0;
        final client = MediaServerClient(
          client: MockClient((request) async {
            requests++;
            return http.Response('{"Id":"different","Type":"Movie"}', 200);
          }),
        );
        addTearDown(client.close);
        await expectLater(
          client.library(account, parentId: '../secret'),
          throwsA(isA<MediaServerException>()),
        );
        await expectLater(
          client.libraryImage(account, '../secret'),
          throwsA(isA<MediaServerException>()),
        );
        expect(requests, 0);
        await expectLater(
          client.libraryItem(account, 'wanted'),
          throwsA(isA<MediaServerException>()),
        );
      },
    );
    test(
      '${kind.label} missing artwork is optional; oversized artwork is rejected',
      () async {
        var status = 302;
        final client = MediaServerClient(
          client: MockClient(
            (_) async => status == 200
                ? http.Response.bytes(List.filled(2 * 1024 * 1024 + 1, 0), 200)
                : http.Response(
                    '',
                    status,
                    headers: {'location': 'https://other.example/image'},
                  ),
          ),
        );
        addTearDown(client.close);
        expect(await client.libraryImage(account, 'item1'), isNull);
        status = 200;
        await expectLater(
          client.libraryImage(account, 'item1'),
          throwsA(isA<MediaServerException>()),
        );
      },
    );
  }
  test(
    'paging advances through unsupported rows and recordings need no catalog IDs',
    () {
      final page = MediaServerLibraryPage.fromJson(
        {
          'Items': [
            {'Id': 'audio', 'Type': 'Audio'},
            {'Id': 'video', 'Type': 'Video'},
          ],
          'TotalRecordCount': 3,
        },
        0,
        60,
      );
      expect(page.nextOffset, 2);
      expect(page.items.where((i) => i.playable).single.id, 'video');
      final recording = MediaServerLibraryItem.fromJson({
        'Id': 'rec',
        'Type': 'Episode',
      });
      expect(recording.playable, true);
      expect(recording.numberedEpisode, false);
      expect(
        recording.progressId('server-a'),
        isNot(recording.progressId('server-b')),
      );
    },
  );
}

import 'dart:convert';

import 'package:debrify/features/media_servers/models/media_server_errors.dart';
import 'package:debrify/models/media_server.dart';
import 'package:debrify/services/media_server_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Behaviour the Jellyfin/Emby code must keep after moving into the shared
/// request core: error types must not turn failures into partial results.
void main() {
  for (final kind in const [MediaServerKind.jellyfin, MediaServerKind.emby]) {
    final account = MediaServerAccount(
      kind: kind,
      baseUrl: 'https://media.example/',
      userId: 'user1',
      token: 'token-secret',
      serverId: 'server1',
      deviceId: 'device1',
    );

    test('${kind.label} network failure mid-lookup fails the search', () async {
      var pages = 0;
      final client = MediaServerClient(
        client: MockClient((request) async {
          if (++pages > 1) throw http.ClientException('connection reset');
          return http.Response(
            jsonEncode({
              'Items': [
                for (
                  var i = 0;
                  i < (kind == MediaServerKind.jellyfin ? 500 : 100);
                  i++
                )
                  {'Id': 'item$i', 'Type': 'Movie', 'ProviderIds': {}},
              ],
              'TotalRecordCount': 5000,
            }),
            200,
          );
        }),
      );
      var incomplete = false;
      await expectLater(
        client.findItems(
          account,
          id: 'tt1',
          isMovie: true,
          onIncomplete: () => incomplete = true,
        ),
        throwsA(isA<MediaServerUnreachable>()),
      );
      expect(incomplete, isFalse);
    });

    test('${kind.label} marking watched is still a POST', () async {
      late http.Request sent;
      final client = MediaServerClient(
        client: MockClient((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      );
      await client.markWatched(account, 'item1');
      expect(sent.method, 'POST');
      expect(sent.url.path, '/Users/user1/PlayedItems/item1');
    });
  }
}

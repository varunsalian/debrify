import 'dart:convert';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/services/mdblist/mdblist_continue_watching_service.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final status in [200, 403]) {
    test(
      'clear status $status preserves payload and invalidates only on success',
      () async {
        var playbackReads = 0;
        final clears = <http.Request>[];
        final service = MdblistContinueWatchingService.forTesting(
          MdblistService.forTesting(
            apiKeyProvider: () async => 'fixture-key',
            featureEnabled: () => true,
            client: MockClient((request) async {
              if (request.url.path == '/scrobble/clear') {
                clears.add(request);
                return http.Response('{}', status);
              }
              if (request.url.path == '/sync/playback') playbackReads++;
              return http.Response(
                request.url.path == '/upnext'
                    ? '{"items":[],"has_more":false}'
                    : '[]',
                200,
              );
            }),
          ),
        );
        expect((await service.fetch()).isSuccess, isTrue);
        expect(playbackReads, 1);
        const item = MdblistContinueWatchingItem(
          selection: AdvancedSearchSelection(
            imdbId: 'tt1',
            isSeries: true,
            title: 'Episode',
            season: 2,
            episode: 3,
          ),
          paused: true,
          playbackId: 42,
          clearTarget: MdblistScrobbleTarget.episode(
            MdblistMediaIds(imdb: 'tt1'),
            season: 2,
            episode: 3,
          ),
        );
        expect(await service.clear(item), status == 200);
        expect(clears.single.method, 'POST');
        expect(jsonDecode(clears.single.body), {
          'show': {
            'ids': {'imdb': 'tt1'},
            'season': 2,
            'episode': 3,
          },
          'progress': 0,
        });
        expect((await service.fetch()).isSuccess, isTrue);
        expect(playbackReads, status == 200 ? 2 : 1);
      },
    );
  }
}

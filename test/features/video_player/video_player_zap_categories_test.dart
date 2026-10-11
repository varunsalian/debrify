import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'IPTV category crossing carries page category source and replacement directory',
    (tester) async {
      final fixture = VideoPlayerEnvironment();
      await tester.runAsync(fixture.initialize);
      final requests = <Map<String, dynamic>>[];
      Map<String, dynamic> page(
        String category,
        List<int> ids,
        String source,
        List<String> categories,
      ) => {
        'channels': [
          for (final id in ids)
            {
              'url': 'https://iptv.test/$id.ts',
              'name': 'Channel $id',
              'group': category,
              'contentType': 'live',
            },
        ],
        'pageOffset': 0,
        'totalChannels': 2,
        'sourceId': source,
        'selectedCategory': category,
        'categories': categories,
      };
      Future<void> tune(WidgetTester tester, int id) async {
        await fixture.key(tester, LogicalKeyboardKey.channelUp);
        await fixture.until(
          tester,
          () =>
              fixture.player.state.playlist.medias.single.uri ==
              'https://iptv.test/$id.ts',
        );
      }

      try {
        await fixture.mount(
          tester,
          VideoPlayerScreen(
            videoUrl: 'https://iptv.test/0.ts',
            title: 'Channel 0',
            iptvChannels: [
              IptvChannel(
                name: 'Channel 0',
                url: 'https://iptv.test/0.ts',
                group: 'News',
                contentType: 'live',
              ),
            ],
            iptvSourceId: 'launch-source',
            iptvBrowseProvider: (request) async {
              requests.add(Map.from(request));
              if (request.containsKey('anchorUrl')) {
                return page('News', [0, 1], 'news-source', ['News', 'Sports']);
              }
              if (request['category'] == 'Sports') {
                return page(
                  'Sports',
                  [20, 21],
                  'sports-source',
                  ['News', 'Sports', 'Movies'],
                );
              }
              if (request['category'] == 'Movies') {
                return page(
                  'Movies',
                  [30, 31],
                  'movies-source',
                  ['News', 'Sports', 'Movies'],
                );
              }
              return page('News', [0, 1], 'news-source', ['News', 'Sports']);
            },
          ),
        );
        await tune(tester, 1);
        await fixture.until(
          tester,
          () => requests.any((r) => r['category'] == 'Sports'),
        );
        expect(
          requests.firstWhere((r) => r['category'] == 'Sports')['sourceId'],
          'news-source',
        );
        await tune(tester, 20);
        await tune(tester, 21);
        await fixture.until(
          tester,
          () => requests.any((r) => r['category'] == 'Movies'),
        );
        expect(
          requests.firstWhere((r) => r['category'] == 'Movies')['sourceId'],
          'sports-source',
        );
        expect(
          requests.firstWhere((r) => r['category'] == 'Movies')['fromEnd'],
          isFalse,
        );
        await tune(tester, 30);
        expect(
          fixture.player.state.playlist.medias.single.uri,
          'https://iptv.test/30.ts',
        );
      } finally {
        await fixture.close(tester);
      }
    },
  );
}

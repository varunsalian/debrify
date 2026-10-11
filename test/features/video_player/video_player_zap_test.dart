import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/video_player_environment.dart';

void main() {
  for (final total in [104, 100]) {
    testWidgets(
      'IPTV zap preserves nonzero page offsets and ${total == 104 ? 'fetches the next page' : 'clamps the reported total'}',
      (tester) async {
        final fixture = VideoPlayerEnvironment();
        await tester.runAsync(fixture.initialize);
        final requests = <Map<String, dynamic>>[];
        Map<String, dynamic> page(int offset, List<int> ids) => {
          'channels': [
            for (final id in ids)
              {
                'url': 'https://iptv.test/$id.ts',
                'name': 'Channel $id',
                'group': 'News',
                'contentType': 'live',
              },
          ],
          'pageOffset': offset,
          'totalChannels': total,
          'sourceId': 'original-source',
          'selectedCategory': 'News',
          'categories': ['News'],
        };
        try {
          await fixture.mount(
            tester,
            VideoPlayerScreen(
              videoUrl: 'https://iptv.test/100.ts',
              title: 'Channel 100',
              iptvChannels: [
                IptvChannel(
                  name: 'Channel 100',
                  url: 'https://iptv.test/100.ts',
                  group: 'News',
                  contentType: 'live',
                ),
              ],
              iptvSourceId: 'launch-source',
              iptvBrowseProvider: (request) async {
                requests.add(Map.from(request));
                if (request.containsKey('anchorUrl')) {
                  return page(100, [100, 101]);
                }
                if (request['offset'] == 102) return page(102, [102, 103]);
                return page(0, [0, 1]);
              },
            ),
          );
          expect(requests.single['anchorUrl'], 'https://iptv.test/100.ts');
          await fixture.key(tester, LogicalKeyboardKey.channelUp);
          await fixture.until(
            tester,
            () =>
                fixture.player.state.playlist.medias.single.uri ==
                'https://iptv.test/101.ts',
          );
          if (total == 104) {
            await fixture.until(
              tester,
              () => requests.any((r) => r['offset'] == 102),
            );
            expect(
              requests.where((r) => r['offset'] == 102).single,
              containsPair('sourceId', 'original-source'),
            );
            await fixture.key(tester, LogicalKeyboardKey.channelUp);
            await fixture.until(
              tester,
              () =>
                  fixture.player.state.playlist.medias.single.uri ==
                  'https://iptv.test/102.ts',
            );
            await fixture.key(tester, LogicalKeyboardKey.channelUp);
            await fixture.until(
              tester,
              () =>
                  fixture.player.state.playlist.medias.single.uri ==
                  'https://iptv.test/103.ts',
            );
          } else {
            expect(requests.any((r) => r['offset'] == 102), isFalse);
          }
          await fixture.key(tester, LogicalKeyboardKey.channelUp);
          await fixture.until(
            tester,
            () =>
                fixture.player.state.playlist.medias.single.uri ==
                'https://iptv.test/0.ts',
          );
          expect(
            requests.where((r) => r.containsKey('fromEnd')).last['fromEnd'],
            isFalse,
          );
          expect(
            requests
                .where((r) => r['fromEnd'] == false)
                .map((r) => r['offset']),
            contains(0),
          );
        } finally {
          await fixture.close(tester);
        }
      },
    );
  }
}

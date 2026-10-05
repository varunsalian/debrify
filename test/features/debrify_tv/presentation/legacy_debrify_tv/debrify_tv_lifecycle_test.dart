import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/debrify_tv_fixture.dart';

void main() {
  testWidgets(
    'C1 R/O mounted hooks focus Quick Play and dispose clears watch',
    (t) async {
      await debrifyTvCase(t, (f) async {
        f.television = true;
        await f.mount(t);
        expect(MainPageBridge.watchDebrifyTvChannel, isNotNull);
        expect(MainPageBridge.requestTvContentFocus(), isTrue);
        await t.pump();
        expect(f.node('DebrifyTVQuickPlay').hasFocus, isTrue);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump();
        expect(MainPageBridge.watchDebrifyTvChannel, isNull);
      });
    },
  );
  testWidgets(
    'C3 O original route interceptor captures P5 before player mounts',
    (t) async {
      await debrifyTvCase(t, (f) async {
        await f.mount(t);
        await f.watch(t);
        await f.until(t, () => f.observer.players.isNotEmpty);
        final player = f.observer.players.single;
        expect(player.videoUrl, 'https://streams.test/Original.720p.mkv');
        expect(player.title, 'Original.720p.mkv');
        expect(
          player.startFromRandom,
          isFalse,
          reason: 'P5 passes the channel startFromRandom',
        );
        expect(player.randomStartMaxPercent, 23);
        expect(player.hideSeekbar, isFalse);
        expect(player.showChannelName, isFalse);
        expect(player.showVideoTitle, isFalse);
        expect(player.hideOptions, isFalse);
        expect(player.channelName, 'Original channel 1');
        expect(player.channelNumber, 1);
        expect(player.requestMagicNext, isNotNull);
        expect(player.requestNextChannel, isNotNull);
        expect(player.requestChannelById, isNotNull);
        expect(player.channelDirectory!.map((e) => e['id']), [
          'original-1',
          'original-2',
        ]);
        expect(find.byType(VideoPlayerScreen), findsNothing);
        expect(
          f.observer.events,
          containsAllInOrder(['dialog', 'pop', 'player', 'player removed']),
        );
        expect(
          f.requests.map(f.requestIdentity),
          containsAllInOrder([
            'POST /rest/1.0/torrents/addMagnet',
            'GET /rest/1.0/torrents/info/original-1',
            'POST /rest/1.0/unrestrict/link',
          ]),
        );
      });
    },
  );
}

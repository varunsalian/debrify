import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final cancel in [false, true]) {
    testWidgets(
      'original catchup caller ${cancel ? 'cancels on channel change' : 'ignores a superseded replay lookup'}',
      (tester) async {
        final fixture = VideoPlayerEnvironment();
        await tester.runAsync(fixture.initialize);
        final host = cancel ? 'cancel-replay.test' : 'stale-replay.test';
        final live = IptvChannel(
          name: 'Live',
          url: 'https://$host/live/user/pass/123.ts',
          contentType: 'live',
        );
        final next = IptvChannel(
          name: 'Next',
          url: 'https://$host/live/user/pass/456.ts',
          contentType: 'live',
        );
        final oldReply = Completer<http.Response>();
        fixture.network.handler = (request) {
          if (request.url.path.contains('/timeshift/')) {
            if (request.url.path.contains('2020-01-01:01-00')) {
              return oldReply.future;
            }
            return http.Response('', 200);
          }
          return http.Response('{}', 404);
        };
        EpgProgramme programme(String title, int hour) => EpgProgramme(
          title: title,
          description: '',
          start: DateTime(2020, 1, 1, hour),
          stop: DateTime(2020, 1, 1, hour + 1),
          hasArchive: true,
          rawStart: '2020-01-01 ${hour.toString().padLeft(2, '0')}:00:00',
        );
        try {
          await fixture.mount(
            tester,
            VideoPlayerScreen(
              videoUrl: live.url,
              title: 'Live',
              iptvChannels: [live, next],
            ),
          );
          playerControls(tester).onShowIptvChannels!();
          await fixture.until(
            tester,
            () => find.byType(IptvChannelSheet).evaluate().isNotEmpty,
          );
          final sheet = tester.widget<IptvChannelSheet>(
            find.byType(IptvChannelSheet),
          );
          final old = sheet.onPlayProgramme!(live, programme('Old replay', 1));
          await fixture.until(
            tester,
            () => fixture.network.requests.any(
              (r) => r.url.path.contains('/timeshift/'),
            ),
          );
          expect(oldReply.isCompleted, isFalse);
          sheet.onClose();
          await fixture.advance(tester, const Duration(milliseconds: 350));
          if (cancel) {
            await fixture.key(tester, LogicalKeyboardKey.channelUp);
            await fixture.until(
              tester,
              () => fixture.player.state.playlist.medias.single.uri == next.url,
            );
          } else {
            await fixture.finish(
              tester,
              sheet.onPlayProgramme!(live, programme('Latest replay', 2)),
            );
            expect(
              fixture.player.state.playlist.medias.single.uri,
              contains('2020-01-01:02-00'),
            );
          }
          final acceptedUrl = fixture.player.state.playlist.medias.single.uri;
          oldReply.complete(http.Response('', 200));
          await fixture.finish(tester, old);
          await fixture.advance(tester, const Duration(milliseconds: 300));
          expect(fixture.player.state.playlist.medias.single.uri, acceptedUrl);
          expect(fixture.player.calls.where((c) => c.$1 == 'open').length, 2);
          expect(find.text('Preparing replay of "Old replay"…'), findsNothing);
        } finally {
          if (!oldReply.isCompleted) oldReply.complete(http.Response('', 404));
          await fixture.close(tester);
        }
      },
    );
  }
}

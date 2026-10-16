import 'dart:async';
import 'dart:convert';
import 'support/iptv_workflow_driver.dart';
import 'support/trakt_transport.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode;

void main() {
  testWidgets(
    'P15 review2 a zap heartbeat reports live progress after retiring the outgoing resume target',
    (t) async {
      final d = IptvWorkflowDriver(
        t,
        configurePlayer: (p) => p.publishPositionOnSeekAcknowledgement = false,
      );
      await d.initialize();
      final cipher = (await t.runAsync(seedTrakt))!;
      d.response = traktReply;
      final channels = [iptvEpisode(1), iptvEpisode(2)];
      Completer<void>? pause;
      try {
        await d.observe(
          () => d.f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: channels.first.url,
              title: 'P15 resume handoff',
              iptvChannels: channels,
              iptvStartIndex: 0,
              contentImdbId: 'tt5100000',
              contentType: 'series',
              contentSeason: 2,
              contentEpisode: 1,
              traktScrobble: true,
              traktProgressPercent: 25,
            ),
          ),
        );
        await d.f.until(t, () => d.calls('seek').isNotEmpty);
        expect(d.calls('seek').last.$2, const Duration(minutes: 5));
        for (var i = 0; i < 4; i++) {
          await d.advance(const Duration(seconds: 4));
        }
        await d.f.until(
          t,
          () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
        );
        await d.settle();
        final before = d.f.network.requests.length;
        pause = d.holdOperation('pause');
        await d.zap(1);
        expect(d.player.state.playing, true);
        expect(
          d.periodic.where(
            (v) => v.$1 == const Duration(minutes: 2) && v.$2.isActive,
          ),
          isNotEmpty,
        );
        await d.advance(const Duration(minutes: 2));
        await d.settle();
        final checkpoints = d.f.network.requests
            .skip(before)
            .where(
              (r) =>
                  r.url.host == 'api.trakt.tv' &&
                  r.url.path == '/scrobble/start',
            )
            .toList();
        expect(checkpoints, hasLength(1));
        final payload =
            jsonDecode(checkpoints.single.body) as Map<String, dynamic>;
        expect((payload['progress'] as num).toDouble(), lessThan(1));
        expect(d.errors, isEmpty);
      } finally {
        if (pause != null && !pause.isCompleted) pause.complete();
        cipher.releaseAll();
        await d.close();
      }
    },
  );
}

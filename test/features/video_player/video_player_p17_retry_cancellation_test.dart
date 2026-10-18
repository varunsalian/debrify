import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/tv_episode_driver.dart';
import 'support/local_completion_driver.dart' show CompletionDelivery;

void main() {
  for (final route in ['next', 'by id', 'Stremio guide']) {
    testWidgets(
      'P17 $route cancels an outgoing PikPak metadata retry before the new open can acquire duration',
      (t) async {
        final d = TvEpisodeDriver(t, configurePlayer: (p) => p.onOpen = () {});
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://mypikpak.com/outgoing.mp4',
              title: 'Outgoing',
              channelDirectory: route == 'by id' ? tvDirectory : null,
              requestChannelById: route == 'by id'
                  ? (id) async => {'url': 'https://player.test/new.mp4'}
                  : null,
              requestNextChannel: route == 'next'
                  ? () async => {'url': 'https://player.test/new.mp4'}
                  : null,
              stremioTvChannels: route == 'Stremio guide' ? tvDirectory : null,
              stremioTvChannelSwitchProvider: route == 'Stremio guide'
                  ? (id) async => null
                  : null,
            ),
          );
          expect(
            d.logs.any((v) => v.contains('PikPak: Waiting for video duration')),
            isTrue,
          );
          expect(
            d.logs.any((v) => v.contains('Retry cancelled (token mismatch')),
            isFalse,
          );
          if (route == 'next') {
            await d.nextChannel();
          } else if (route == 'by id') {
            final g = await d.debrifyGuide();
            await d.byId(g, g.channels.last);
          } else {
            final g = await d.stremioGuide();
            await d.stremioPick(g, 'b', url: 'https://player.test/new.mp4');
          }
          await d.f.until(
            t,
            () => d.logs.any(
              (v) => v.contains('Retry cancelled (token mismatch'),
            ),
          );
          expect(d.opens.map((v) => v.uri), [
            'https://mypikpak.com/outgoing.mp4',
            'https://player.test/new.mp4',
          ]);
          expect(d.player.state.duration, Duration.zero);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final route in ['next', 'by id', 'Stremio guide']) {
    testWidgets(
      'P17 $route token advance cannot resurrect an older held PikPak startup after a newer retry',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final delivery = CompletionDelivery(
          '_waitForVideoMetadata',
          (v) => v == null,
        );
        delivery.multiple = true;
        Future<dynamic>? selection;
        try {
          await delivery.run(
            () => d.mount(
              screen: VideoPlayerScreen(
                videoUrl: 'https://mypikpak.com/one.mp4',
                title: 'Show.S01E01.mkv',
                startAtPercent: 0.5,
                playlist: const [
                  PlaylistEntry(
                    url: 'https://mypikpak.com/one.mp4',
                    title: 'Show.S01E01.mkv',
                    provider: 'pikpak',
                  ),
                  PlaylistEntry(
                    url: 'https://mypikpak.com/two.mp4',
                    title: 'Show.S01E02.mkv',
                    provider: 'pikpak',
                  ),
                ],
                channelDirectory: route == 'by id' ? tvDirectory : null,
                requestChannelById: route == 'by id'
                    ? (id) async => {'url': 'https://player.test/new.mp4'}
                    : null,
                requestNextChannel: route == 'next'
                    ? () async => {'url': 'https://player.test/new.mp4'}
                    : null,
                stremioTvChannels: route == 'Stremio guide'
                    ? tvDirectory
                    : null,
                stremioTvChannelSwitchProvider: route == 'Stremio guide'
                    ? (id) async => null
                    : null,
              ),
            ),
          );
          expect(delivery.pending, hasLength(1));
          final browser = await d.browser();
          d.f.navigator.currentState!.pop();
          await d.f.advance(t, const Duration(milliseconds: 400));
          selection =
              d.observe<dynamic>(
                    () => delivery.run(() => browser.onEpisodeSelected(1, 2)),
                  )
                  as Future<dynamic>;
          await d.f.until(t, () => delivery.pending.length == 2);
          if (route == 'next') {
            await d.nextChannel();
          } else if (route == 'by id') {
            final g = await d.debrifyGuide();
            await d.byId(g, g.channels.last);
          } else {
            final g = await d.stremioGuide();
            await d.stremioPick(g, 'b', url: 'https://player.test/new.mp4');
          }
          final before = d.seeks.length;
          delivery.releaseAt(0);
          await d.f.advance(t, const Duration(milliseconds: 100));
          await d.f.actions.settle(t);
          expect(
            d.seeks.length,
            before,
            reason:
                'The older initial callback must remain cancelled rather than apply its 50% launch seek to the new channel',
          );
          expect(
            d.player.state.playlist.medias.single.uri,
            'https://player.test/new.mp4',
          );
          delivery.release();
          await d.f.finish(t, selection);
          selection = null;
          expect(d.errors, isEmpty);
        } finally {
          delivery.release();
          if (selection != null) {
            await d.f.finish(t, selection);
          }
          await d.close();
        }
      },
    );
  }
}

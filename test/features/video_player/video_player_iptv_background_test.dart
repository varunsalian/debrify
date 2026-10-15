import 'dart:async';
import 'support/iptv_workflow_driver.dart';
import 'support/pip_lifecycle_driver.dart';
import 'video_player_pip_lifecycle_test.dart' show background, foreground;

void main() {
  testWidgets(
    'P15 lifecycle pause blocks live recovery and cancels a pending catchup lookup',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-background.test/live/u/p/123.ts',
      );
      final reply = Completer<Response>();
      f.network.handler = (r) => r.url.path.contains('/timeshift/')
          ? reply.future
          : Response('{}', 404);
      try {
        await d.mount(
          VideoPlayerScreen(
            videoUrl: live.url,
            title: live.name,
            iptvChannels: [live],
          ),
        );
        playerControls(t).onShowIptvChannels!();
        await f.advance(t, const Duration(milliseconds: 350));
        final s = t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
        final pending = d.observe(
          () => s.onPlayProgramme!(live, iptvProgramme()),
        );
        await f.until(
          t,
          () =>
              f.network.requests.any((r) => r.url.path.contains('/timeshift/')),
        );
        await background(d);
        f.player.emit('error', 'lost while in background');
        await d.settle();
        expect(d.operations('open').length, 1);
        reply.complete(Response('', 200));
        await f.finish(t, pending);
        expect(d.operations('open').length, 1);
        await foreground(d);
        expect(d.operations('open').length, 1);
        expect(d.errors, isEmpty);
      } finally {
        if (!reply.isCompleted) {
          reply.complete(Response('', 404));
        }
        await d.close();
      }
    },
  );
}

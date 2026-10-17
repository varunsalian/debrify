import 'dart:async';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final boundary in ['lookup', 'recording-stop', 'before-open']) {
    testWidgets(
      'P15 review2 Start Over rejects a page-replaced URL at $boundary',
      (t) async {
        final d = IptvWorkflowDriver(t, native: true);
        await d.initialize();
        final channels = [
          for (var i = 0; i < 30; i++)
            iptvChannel(
              i,
              url: 'https://p15-url-$boundary.test/live/u/p/${100 + i}.ts',
            ),
        ];
        final replacement = iptvChannel(
          90,
          url: 'https://p15-url-$boundary.test/live/u/p/999.ts',
        );
        final page = Completer<Map<String, dynamic>?>();
        final lookup = IptvAwaitDelivery(
          'startIptvProgrammeFromBeginning',
          (value) => value is String,
        );
        final gate = Completer<void>();
        var entered = false;
        var completed = false;
        final stop = IptvAwaitDelivery(
          'startIptvProgrammeFromBeginning',
          (value) => value == null,
        );
        Future<void>? start;
        d.response = iptvPanelReply;
        d.provider = (r) => r.containsKey('anchorUrl')
            ? iptvPage(channels, total: 60)
            : page.future;
        try {
          await d.mount(channels, index: 18, paged: true);
          await d.zap(1);
          expect(d.playingUrl, channels[19].url);
          final sheet = await d.guide();
          final native = d.player.platform as FakeNativePlayer;
          if (boundary == 'before-open') {
            native.heldOperation = (name, value) =>
                name == 'setProperty' &&
                value is (String, String) &&
                value.$1 == 'sub-visibility' &&
                !entered;
            native.beforeOperation = (name, value) async {
              if (native.heldOperation!(name, value)) {
                entered = true;
                await gate.future;
              }
            };
          }
          Future<void> play() => d.observe(
            () => sheet.onPlayProgramme!(
              channels[19],
              iptvProgramme(airing: true),
            ),
          );
          start =
              (boundary == 'lookup'
                      ? stop.run(() => lookup.run(play))
                      : boundary == 'recording-stop'
                      ? stop.run(play)
                      : play())
                  .then((_) => completed = true);
          await d.f.until(
            t,
            () => boundary == 'lookup'
                ? lookup.pending.isNotEmpty
                : boundary == 'recording-stop'
                ? stop.pending.isNotEmpty
                : entered,
          );
          final opened = d.opened.length;
          final setupWrites = native.calls
              .where(
                (c) =>
                    c.$1 == 'setProperty' &&
                    c.$2 is (String, String) &&
                    (c.$2 as (String, String)).$1 == 'sub-visibility',
              )
              .length;
          page.complete(
            iptvPage([
              ...channels.take(19),
              replacement,
              ...channels.skip(20),
            ], total: 60),
          );
          await d.settle();
          final updated = t.widget<IptvChannelSheet>(
            find.byType(IptvChannelSheet),
          );
          expect(updated.channels[updated.currentIndex].url, replacement.url);
          expect(d.playingUrl, channels[19].url);
          lookup.release();
          if (boundary == 'lookup') {
            // Rejection completes the actual guide action without entering
            // recording-stop. A removed URL guard takes that extra await.
            await d.settle();
            expect(completed, true);
          }
          stop.release();
          gate.complete();
          await d.f.finish(t, start);
          await d.settle();
          expect(d.opened, hasLength(opened));
          expect(playerControls(t).liveEdgeActionLoading, true);
          if (boundary == 'recording-stop') {
            expect(
              native.calls
                  .where(
                    (c) =>
                        c.$1 == 'setProperty' &&
                        c.$2 is (String, String) &&
                        (c.$2 as (String, String)).$1 == 'sub-visibility',
                  )
                  .length,
              setupWrites,
            );
          }
          expect(d.errors, isEmpty);
        } finally {
          lookup.release();
          stop.release();
          if (!gate.isCompleted) gate.complete();
          if (!page.isCompleted) page.complete(null);
          if (start != null) await d.f.finish(t, start);
          await d.close();
        }
      },
    );
  }
}

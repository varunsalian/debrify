import 'dart:async';
import 'package:media_kit/media_kit.dart' as mk;
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final superseded in [false, true]) {
    testWidgets(
      'P15 review2 archive open failure respects superseded=$superseded ownership',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final channels = [
          for (var i = 0; i < 2; i++)
            iptvChannel(
              i,
              url:
                  'https://p15-archive-failure-$superseded.test/live/u/p/${123 + i}.ts',
              attributes: {'tv_archive': '1'},
            ),
        ];
        d.response = iptvPanelReply;
        final open = Completer<void>();
        final fallback = IptvAwaitDelivery(
          'switchToIptvChannel',
          (v) => v == null,
        );
        var entered = false;
        Future<void>? work;
        try {
          await d.mount(channels);
          final sheet = await d.guide();
          bool firstArchive(String name, Object? value) =>
              name == 'open' &&
              !entered &&
              ((value as (mk.Playable, bool)).$1 as mk.Media).uri.contains(
                '/timeshift/',
              );
          d.player.heldOperation = firstArchive;
          d.player.beforeOperation = (name, value) async {
            if (firstArchive(name, value)) {
              entered = true;
              await open.future;
              throw StateError('The pending archive open failed');
            }
          };
          Future<void> play() => d.observe(
            () => sheet.onPlayProgramme!(
              channels.first,
              iptvProgramme(airing: true),
            ),
          );
          work = superseded ? play() : fallback.run(play);
          await d.f.until(t, () => entered);
          expect(playerControls(t).liveEdgeActionActive, true);
          if (superseded) {
            await d.zap(1);
            await d.f.finish(
              t,
              d.observe(
                () => sheet.onPlayProgramme!(
                  channels.last,
                  iptvProgramme(airing: true),
                ),
              ),
            );
            final newer = d.playingUrl;
            final attempts = d.opened.length;
            expect(newer, contains('/timeshift/'));
            expect(playerControls(t).liveEdgeActionActive, true);
            open.complete();
            await d.f.finish(t, work!);
            expect(d.playingUrl, newer);
            expect(d.opened.length, attempts);
            expect(playerControls(t).liveEdgeActionActive, true);
          } else {
            open.complete();
            await d.f.until(t, () => fallback.pending.isNotEmpty);
            // The fallback switch is still at its recording-stop await. The
            // failed archive action must already have retired the archive UI.
            expect(playerControls(t).liveEdgeActionActive, false);
            expect(playerControls(t).startOverTimelineVisible, false);
            fallback.release();
            await d.f.finish(t, work!);
            expect(d.playingUrl, channels.first.url);
          }
          expect(d.errors, isEmpty);
        } finally {
          if (!open.isCompleted) open.complete();
          fallback.release();
          if (work != null) await d.f.finish(t, work);
          await d.close();
        }
      },
    );
  }
}

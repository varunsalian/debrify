import 'support/iptv_workflow_driver.dart';

void main() {
  for (final archive in [false, true]) {
    testWidgets(
      'P15 review2 real stall admission preserves archive=$archive ownership',
      (t) async {
        final d = IptvWorkflowDriver(t, native: true);
        await d.initialize();
        final live = iptvChannel(
          0,
          url: 'https://p15-stall-archive-$archive.test/live/u/p/123.ts',
          attributes: {'tv_archive': '1'},
        );
        final vod = iptvChannel(1, live: false);
        d.response = iptvPanelReply;
        final lines = <String>[];
        final oldPrint = debugPrint;
        debugPrint = (String? line, {int? wrapWidth}) {
          if (line != null) lines.add(line);
        };
        try {
          await d.mount([live, vod]);
          if (archive) {
            final sheet = await d.guide();
            await d.f.finish(
              t,
              d.observe(
                () => sheet.onPlayProgramme!(live, iptvProgramme(airing: true)),
              ),
            );
            await d.closeGuide(sheet);
            playerControls(t).onToggleStartOverTimeline!();
            await d.settle();
            expect(playerControls(t).startOverTimelineVisible, true);
          } else {
            await d.zap(1);
            expect(d.playingUrl, vod.url);
          }
          final opens = d.opened.length;
          final timers = d.timed.length;
          lines.clear();
          // The production recovery owner reads DateTime.now(), rather than
          // Flutter's fake clock. This is deliberately a real elapsed window.
          d.player.emit('position', d.player.framePosition);
          await d.settle();
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 12100)),
          );
          d.player.emit('position', d.player.framePosition);
          await d.settle();
          if (archive) {
            await d.f.until(t, () => d.opened.length > opens);
            expect(d.playingUrl, live.url);
            expect(playerControls(t).liveEdgeActionActive, false);
            expect(playerControls(t).liveEdgeActionLoading, false);
            expect(playerControls(t).startOverTimelineVisible, false);
            final native = d.player.platform as FakeNativePlayer;
            expect(
              native.properties['stream-lavf-o'],
              'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_on_http_error=5xx,reconnect_delay_max=5',
            );
            expect(
              lines.where(
                (s) =>
                    s.contains('IptvDiag:') &&
                    s.contains('event=tune-start') &&
                    s.contains('live=true'),
              ),
              hasLength(1),
            );
          } else {
            expect(d.opened.length, opens);
            expect(
              d.timed
                  .skip(timers)
                  .where(
                    (v) =>
                        d.timerOwners[v.$2]!.contains('IptvLiveRecovery._fire'),
                  ),
              isEmpty,
              reason: 'A VOD stall must not allocate a live recovery episode',
            );
            expect(find.text('Reconnecting…'), findsNothing);
          }
          expect(d.errors, isEmpty);
        } finally {
          debugPrint = oldPrint;
          await d.close();
        }
      },
    );
  }
}

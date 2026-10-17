import 'dart:async';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final mode in [
    'toggle',
    'unavailable',
    'open-failure',
    'pre-open-cancel',
  ]) {
    testWidgets(
      'P15 Start Over $mode pins flags live return and guarded open',
      (t) async {
        final d = IptvWorkflowDriver(t, native: mode == 'pre-open-cancel');
        await d.initialize();
        final live = iptvChannel(
          0,
          url: 'https://p15-start-$mode.test/live/u/p/123.ts',
          attributes: {'tv_archive': '1'},
          headers: {'X-Start': 'yes'},
        );
        final gate = Completer<void>();
        var entered = false;
        d.response = (r) =>
            mode == 'unavailable' && r.url.path.contains('/timeshift/')
            ? Response('', 404)
            : iptvPanelReply(r);
        try {
          await d.mount([live]);
          await d.f.until(t, () => playerControls(t).onLiveEdgeAction != null);
          final s = await d.guide();
          if (mode == 'open-failure') {
            d.player.failures['open'] = StateError('archive failed');
          }
          if (mode == 'pre-open-cancel') {
            final native = d.player.platform as FakeNativePlayer;
            native.heldOperation = (n, v) =>
                n == 'setProperty' &&
                (v as (String, String)).$1 == 'sub-visibility' &&
                !entered;
            native.beforeOperation = (n, v) async {
              if (n == 'setProperty' &&
                  (v as (String, String)).$1 == 'sub-visibility' &&
                  !entered) {
                entered = true;
                await gate.future;
              }
            };
          }
          final pending = d.observe(
            () => s.onPlayProgramme!(live, iptvProgramme(airing: true)),
          );
          if (mode == 'pre-open-cancel') {
            await d.f.until(t, () => entered);
            expect(d.opened.length, 1);
            s.onClose();
            gate.complete();
          }
          await d.f.finish(t, pending);
          await d.settle();
          if (mode == 'toggle') {
            expect(d.playingUrl, contains('/timeshift/'));
            expect(
              d.player.state.playlist.medias.single.httpHeaders,
              containsPair('X-Start', 'yes'),
            );
            expect(playerControls(t).onToggleStartOverTimeline, isNotNull);
            playerControls(t).onToggleStartOverTimeline!();
            await d.settle();
            expect(playerControls(t).startOverTimelineVisible, true);
            expect(playerControls(t).hideSeekbar, false);
            playerControls(t).onToggleStartOverTimeline!();
            await d.settle();
            expect(playerControls(t).startOverTimelineVisible, false);
            expect(playerControls(t).hideSeekbar, true);
            await d.closeGuide(s);
            playerControls(t).onLiveEdgeAction!();
            await d.settle();
            expect(d.playingUrl, live.url);
            expect(playerControls(t).onToggleStartOverTimeline, isNull);
          } else if (mode == 'unavailable') {
            expect(d.opened.length, 1);
            expect(find.text('Start over is not available'), findsOneWidget);
          } else if (mode == 'open-failure') {
            expect(d.opened.length, 3);
            expect(d.playingUrl, live.url);
            expect(playerControls(t).onToggleStartOverTimeline, isNull);
          } else {
            expect(d.opened.length, 1);
            expect(d.playingUrl, live.url);
            expect(playerControls(t).onToggleStartOverTimeline, isNull);
          }
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) {
            gate.complete();
          }
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 live-edge action does not duplicate a loading lookup and airing guide pick switches before Start Over',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final old = iptvChannel(0);
      final live = iptvChannel(
        1,
        url: 'https://p15-airing-pick.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      final reply = Completer<Response>();
      d.response = (r) =>
          r.url.path.contains('/timeshift/') ? reply.future : iptvPanelReply(r);
      try {
        await d.mount([old, live]);
        final s = await d.guide();
        final pending = d.observe(
          () => s.onPlayProgramme!(live, iptvProgramme(airing: true)),
        );
        await d.f.until(
          t,
          () => d.f.network.requests.any(
            (r) => r.url.path.contains('/timeshift/'),
          ),
        );
        expect(d.playingUrl, live.url);
        await d.settle();
        final action = playerControls(t).onLiveEdgeAction;
        if (action != null) {
          action();
        }
        await d.settle();
        expect(
          d.f.network.requests
              .where((r) => r.url.path.contains('/timeshift/'))
              .length,
          1,
        );
        reply.complete(Response('', 200));
        await d.f.finish(t, pending);
        expect(d.playingUrl, contains('/timeshift/'));
        expect(d.opened.length, 3);
        expect(d.errors, isEmpty);
      } finally {
        if (!reply.isCompleted) {
          reply.complete(Response('', 404));
        }
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 zero-duration Start Over timeline reports loading without revealing',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-timeline-loading.test/live/u/p/123.ts',
      );
      d.response = iptvPanelReply;
      try {
        await d.mount([live]);
        final s = await d.guide();
        await d.f.finish(
          t,
          s.onPlayProgramme!(live, iptvProgramme(airing: true)),
        );
        d.player.emit('duration', Duration.zero);
        await d.settle();
        playerControls(t).onToggleStartOverTimeline!();
        await d.settle();
        expect(playerControls(t).startOverTimelineVisible, false);
        expect(find.text('Timeline is still loading'), findsOneWidget);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}

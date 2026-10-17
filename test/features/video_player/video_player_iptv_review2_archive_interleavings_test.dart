import 'dart:async';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 an unlisted airing pick cannot start over the valid current channel',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-unlisted-valid.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      final unlisted = iptvChannel(
        1,
        url: 'https://p15-unlisted-valid.test/live/u/p/456.ts',
        attributes: {'tv_archive': '1'},
      );
      d.response = iptvPanelReply;
      try {
        await d.mount([live]);
        final sheet = await d.guide();
        final opened = d.opened.length;
        await d.f.finish(
          t,
          d.observe(
            () => sheet.onPlayProgramme!(unlisted, iptvProgramme(airing: true)),
          ),
        );
        expect(d.opened.length, opened);
        expect(d.playingUrl, live.url);
        expect(playerControls(t).liveEdgeActionActive, false);
        expect(playerControls(t).liveEdgeActionLoading, false);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  for (final airing in [false, true]) {
    testWidgets(
      'P15 review2 an issued archive failure cancels a newer same-channel lookup airing=$airing',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = iptvChannel(
          0,
          url: 'https://p15-overlapping-archive-$airing.test/live/u/p/123.ts',
          attributes: {'tv_archive': '1'},
        );
        d.response = iptvPanelReply;
        final failedOpen = Completer<void>();
        final lookup = IptvAwaitDelivery(
          airing ? 'startIptvProgrammeFromBeginning' : 'playIptvCatchup',
          (v) => v is String,
        );
        final fallback = IptvAwaitDelivery(
          'switchToIptvChannel',
          (v) => v == null,
        );
        var entered = false;
        Future<void>? oldWork;
        Future<void>? newWork;
        try {
          await d.mount([live]);
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
              await failedOpen.future;
              throw StateError('The earlier issued archive open failed');
            }
          };
          oldWork = fallback.run(
            () => d.observe(
              () => sheet.onPlayProgramme!(live, iptvProgramme(airing: true)),
            ),
          );
          await d.f.until(t, () => entered);
          expect(playerControls(t).liveEdgeActionActive, true);
          newWork = lookup.run(
            () => d.observe(
              () => sheet.onPlayProgramme!(live, iptvProgramme(airing: airing)),
            ),
          );
          await d.f.until(t, () => lookup.pending.isNotEmpty);
          if (airing) {
            expect(playerControls(t).liveEdgeActionLoading, true);
          } else {
            await d.advance(const Duration(milliseconds: 300));
            expect(find.textContaining('Preparing replay of'), findsOneWidget);
          }
          failedOpen.complete();
          await d.f.until(t, () => fallback.pending.isNotEmpty);
          // Pin the existing early failure outcome before fallback cleanup.
          // The issued older open has not changed the channel-switch ticket.
          expect(playerControls(t).liveEdgeActionLoading, false);
          expect(playerControls(t).liveEdgeActionActive, false);
          if (!airing) {
            await d.advance(const Duration(milliseconds: 300));
            expect(find.textContaining('Preparing replay of'), findsOneWidget);
          }
          final attempts = d.opened.length;
          lookup.release();
          await d.f.finish(t, newWork!);
          expect(d.opened.length, attempts);
          fallback.release();
          await d.f.finish(t, oldWork!);
          expect(d.playingUrl, live.url);
          expect(find.byType(TransitionOverlay), findsNothing);
          expect(d.errors, isEmpty);
        } finally {
          if (!failedOpen.isCompleted) failedOpen.complete();
          lookup.release();
          fallback.release();
          if (newWork != null) await d.f.finish(t, newWork);
          if (oldWork != null) await d.f.finish(t, oldWork);
          await d.close();
        }
      },
    );
  }
}

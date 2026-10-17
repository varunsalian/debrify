import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final status in ['401', '403', '404', 'x401x']) {
    testWidgets(
      'P15 stream error auth classification requires a word boundary $status',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = iptvChannel(0);
        try {
          await d.mount([live]);
          d.player.emit('error', 'HTTP $status fixture');
          await d.settle();
          final auth = status != 'x401x';
          expect(d.opened.length, auth ? 1 : 2);
          expect(
            find.text("${live.name} didn't play — HTTP $status fixture"),
            auth ? findsOneWidget : findsNothing,
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final gate in [
    'user-pause',
    'end-item',
    'sleep-latch',
    'non-live',
    'disposed',
  ]) {
    testWidgets('P15 live recovery eligibility rejects $gate', (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(0, live: gate != 'non-live');
      try {
        await d.mount([live]);
        if (gate == 'user-pause') {
          playerControls(t).onPlayPause();
          await d.settle();
        }
        if (gate == 'end-item' || gate == 'sleep-latch') {
          final menu = await openPlayerMenu(t, d.f);
          menu.onSleepSelected(
            SleepTimerSelection(
              gate == 'end-item'
                  ? SleepTimerMode.endOfItem
                  : SleepTimerMode.countdown,
              0,
            ),
          );
          await d.settle();
        }
        if (gate == 'disposed') {
          await d.retire();
        }
        final before = d.opened.length;
        d.player.emit('error', 'connection lost');
        await d.settle();
        expect(d.opened.length, before);
        if (gate == 'non-live') {
          expect(
            find.text("${live.name} didn't play — connection lost"),
            findsOneWidget,
          );
        }
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    });
  }
  testWidgets(
    'P15 stream errors use real six-second debounce independent of timer advancement',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(0, live: false);
      try {
        await d.mount([live]);
        d.player.emit('error', 'first');
        await d.settle();
        await d.advance(const Duration(milliseconds: 300));
        expect(find.text("${live.name} didn't play — first"), findsOneWidget);
        d.player.emit('error', 'second');
        await d.settle();
        await d.advance(const Duration(seconds: 7));
        await d.advance(const Duration(milliseconds: 300));
        expect(find.text("${live.name} didn't play — second"), findsNothing);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 6100)),
        );
        d.player.emit('error', 'third');
        await d.settle();
        await d.f.until(
          t,
          () => find
              .text("${live.name} didn't play — third")
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text("${live.name} didn't play — third"), findsOneWidget);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 a Start Over auth failure returns quietly to live before auth snackbar classification',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-archive-auth.test/live/u/p/123.ts',
      );
      d.response = iptvPanelReply;
      try {
        await d.mount([live]);
        final s = await d.guide();
        await d.f.finish(
          t,
          s.onPlayProgramme!(live, iptvProgramme(airing: true)),
        );
        expect(d.playingUrl, contains('/timeshift/'));
        d.player.emit('error', 'HTTP 403 archive');
        await d.settle();
        expect(d.playingUrl, live.url);
        expect(
          find.text("${live.name} didn't play — HTTP 403 archive"),
          findsNothing,
        );
        expect(playerControls(t).onToggleStartOverTimeline, isNull);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}

import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'support/iptv_probe_streams.dart';
import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode;

class PlayingDelivery extends IptvProbeController<bool> {
  bool suppress = false;
  @override
  void add(bool event) {
    if (!suppress) super.add(event);
  }
}

void main() {
  testWidgets('P15 review2 a zap retires its reveal overlay at 1500ms', (
    t,
  ) async {
    final playing = PlayingDelivery();
    final d = IptvWorkflowDriver(
      t,
      configurePlayer: (p) {
        p.events['playing'] = playing;
      },
    );
    await d.initialize();
    try {
      await d.mount([iptvChannel(0), iptvChannel(1)]);
      // Some live engines do not emit playing again on a handoff. The IPTV
      // switch owns a shorter fallback reveal for that original path.
      playing.suppress = true;
      await d.zap(1);
      final deadline = d.timed
          .lastWhere(
            (v) =>
                v.$1 == const Duration(milliseconds: 1500) &&
                d.timerOwners[v.$2]!.contains('switchToIptvChannel'),
          )
          .$2;
      await d.timerAge(deadline, const Duration(milliseconds: 1499));
      expect(find.byType(TransitionOverlay), findsOneWidget);
      await d.timerAge(deadline, const Duration(milliseconds: 1500));
      expect(find.byType(TransitionOverlay), findsNothing);
      final before = d.timed.length;
      playing.suppress = false;
      d.player.emit('playing', true);
      await d.settle();
      expect(
        d.timed.skip(before).where((v) => v.$1 == const Duration(seconds: 3)),
        isEmpty,
        reason:
            'A later playing event must not restart an already retired reveal',
      );
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P15 review2 a trackless series tune spends twenty 100ms audio waits',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.mount([iptvEpisode(1), iptvEpisode(2)]);
        final before = d.timed.length;
        await d.zap(1);
        for (var i = 0; i < 30; i++) {
          await d.advance(const Duration(milliseconds: 100));
        }
        final waits = d.timed
            .skip(before)
            .where(
              (v) => d.timerOwners[v.$2]!.contains('applyIptvAudioPreference'),
            )
            .toList();
        expect(waits, hasLength(20));
        expect(waits.map((v) => v.$1).toSet(), {
          const Duration(milliseconds: 100),
        });
        expect(waits.where((v) => v.$2.isActive), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}

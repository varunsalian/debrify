import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a Stremio recovery probe keeps the zap overlay absent',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('quiet-retune');
      var finished = false;
      try {
        await d.mount([live], initialUrl: 'https://probe.test/first.ts');
        await d.advance(const Duration(seconds: 4));
        expect(find.byType(TransitionOverlay), findsNothing);
        d.probeMode();
        d.player.emit('error', 'network connection reset');
        await d.settle();
        await d.f.until(t, () => d.opened.length == 2);
        expect(find.byType(TransitionOverlay), findsNothing);
        await d.probeEvent('width');
        await d.settle();
        expect(find.byType(TransitionOverlay), findsNothing);
        expect(d.playingUrl, 'https://probe.test/first.ts');
        expect(d.errors, isEmpty);
        finished = true;
      } finally {
        if (!finished) await d.probeEvent('width');
        await d.close();
      }
    },
  );
}

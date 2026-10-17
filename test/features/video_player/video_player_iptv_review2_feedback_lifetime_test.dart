import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 stream failure feedback has a five second lifetime',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.mount([iptvChannel(0, live: false)]);
        d.player.emit('error', '403 rejected');
        await d.settle();
        final feedback = t.widget<SnackBar>(find.byType(SnackBar));
        expect((feedback.content as Text).data, contains('403 rejected'));
        expect(feedback.duration, const Duration(seconds: 5));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}

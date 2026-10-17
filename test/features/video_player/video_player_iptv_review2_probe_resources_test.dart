import 'support/iptv_probe_streams.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final result in ['width', 'position', 'error', 'timeout']) {
    testWidgets(
      'P15 review2 candidate $result releases each probe subscription',
      (t) async {
        final controllers = {
          for (final name in ['error', 'width', 'position'])
            name: IptvProbeController<dynamic>(),
        };
        final d = IptvWorkflowDriver(
          t,
          configurePlayer: (p) => p.events.addAll(controllers),
        );
        await d.initialize();
        final live = await d.installAddon('resource-$result');
        try {
          await d.mount([iptvChannel(0), live]);
          d.probeMode();
          final sheet = await d.guide();
          final work = d.observe(
            () => sheet.onChannelSelected([iptvChannel(0), live], 1),
          );
          await d.f.until(t, () => d.opened.length == 2);
          await d.settle();
          for (final entry in controllers.entries) {
            expect(
              entry.value.observed.leases.where(
                (s) => s.owner.contains('tryOpenLiveStream') && !s.cancelled,
              ),
              hasLength(1),
              reason: '${entry.key} probe must be pending',
            );
          }
          if (result == 'timeout') {
            await d.advance(const Duration(seconds: 12));
          } else {
            await d.probeEvent(result);
          }
          if (result == 'error' || result == 'timeout') {
            await d.f.until(t, () => d.opened.length == 3);
            await d.settle();
            await d.probeEvent('width');
          }
          await d.f.finish(t, work);
          for (final entry in controllers.entries) {
            expect(
              entry.value.observed.leases.where(
                (s) => s.owner.contains('tryOpenLiveStream') && !s.cancelled,
              ),
              isEmpty,
              reason:
                  '${entry.key} probe must cancel independently of other listeners',
            );
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}

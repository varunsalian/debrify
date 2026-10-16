import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final close in [false, true]) {
    testWidgets(
      'P15 review2 a retained guide callback preserves its original disposed error close=$close',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = iptvChannel(
          0,
          url: 'https://p15-retired-guide-$close.test/live/u/p/123.ts',
          attributes: {'tv_archive': '1'},
        );
        d.response = iptvPanelReply;
        final lookup = IptvAwaitDelivery(
          'startIptvProgrammeFromBeginning',
          (v) => v is String && v.contains('/timeshift/'),
        );
        Future<void>? outgoing;
        try {
          await d.mount([live]);
          final sheet = await d.guide();
          outgoing = lookup.run(
            () => d.observe(
              () => sheet.onPlayProgramme!(live, iptvProgramme(airing: true)),
            ),
          );
          await d.f.until(t, () => lookup.pending.isNotEmpty);
          expect(playerControls(t).liveEdgeActionLoading, true);
          await d.retire();
          Object? rejected;
          await d.f.finish(
            t,
            d.observe(() async {
              try {
                if (close) {
                  sheet.onClose();
                } else {
                  await sheet.onPlayProgramme!(
                    live,
                    iptvProgramme(airing: false),
                  );
                }
              } catch (error) {
                rejected = error;
              }
            }),
          );
          // These are existing rejected callbacks, not supported disposed UI
          // actions. Pin the real rejection boundary without checking stacks.
          expect(rejected, isA<FlutterError>());
          expect(
            rejected.toString(),
            contains(
              close ? 'setState() called after dispose' : 'has been unmounted',
            ),
          );
          expect(d.errors, isEmpty);
        } finally {
          lookup.release();
          if (outgoing != null) await d.f.finish(t, outgoing);
          await d.close();
        }
      },
    );
  }
}

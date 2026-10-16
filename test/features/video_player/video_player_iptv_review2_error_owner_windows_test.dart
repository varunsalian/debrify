import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final stremio in [false, true]) {
    testWidgets(
      'P15 review2 error ownership spans recording stop and resolve stremio=$stremio',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final outgoing = iptvChannel(0);
        final incoming = stremio
            ? await d.installAddon('error-owner')
            : iptvChannel(1);
        final stop = IptvAwaitDelivery('switchToIptvChannel', (v) => v == null);
        final resolve = IptvAwaitDelivery(
          'switchToIptvChannel',
          (v) => v is List<StremioIptvCandidate>,
        );
        try {
          await d.mount([outgoing, incoming]);
          d.player.emit('error', 'HTTP 401 first');
          await d.settle();
          expect(
            find.text("${outgoing.name} didn't play — HTTP 401 first"),
            findsOneWidget,
          );
          ScaffoldMessenger.of(
            t.element(find.byType(VideoPlayerScreen)),
          ).hideCurrentSnackBar();
          await d.advance(const Duration(milliseconds: 350));
          if (stremio) d.probeMode();
          await stop.run(() => resolve.run(() => d.zap(1)));
          await d.f.until(t, () => stop.pending.isNotEmpty);
          d.player.emit('error', 'HTTP 403 held');
          await d.settle();
          expect(
            find.text("${outgoing.name} didn't play — HTTP 403 held"),
            findsNothing,
          );
          stop.release();
          if (stremio) {
            await d.f.until(t, () => resolve.pending.isNotEmpty);
            d.player.emit('error', 'HTTP 403 resolving');
            await d.settle();
            expect(
              find.text("${incoming.name} didn't play — HTTP 403 resolving"),
              findsNothing,
            );
            resolve.release();
          }
          await d.f.until(t, () => d.opened.length == 2);
          await d.settle();
          if (stremio) {
            await d.probeEvent('width');
          }
          await d.settle();
          d.player.emit('error', 'HTTP 401 incoming');
          await d.settle();
          expect(
            find.text("${incoming.name} didn't play — HTTP 401 incoming"),
            findsOneWidget,
          );
          expect(d.errors, isEmpty);
        } finally {
          stop.release();
          resolve.release();
          if (stremio) await d.probeEvent('width');
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P15 review2 archive stream error retires archive UI before quiet fallback recording stop',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-archive-error-window.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      d.response = iptvPanelReply;
      final stop = IptvAwaitDelivery('switchToIptvChannel', (v) => v == null)
        ..armed = false;
      try {
        await stop.run(() => d.mount([live]));
        final guide = await d.guide();
        await d.f.finish(
          t,
          d.observe(
            () => guide.onPlayProgramme!(live, iptvProgramme(airing: true)),
          ),
        );
        await d.closeGuide(guide);
        expect(playerControls(t).liveEdgeActionActive, true);
        stop.armed = true;
        d.player.emit('error', 'HTTP 403 archive');
        await d.f.until(t, () => stop.pending.isNotEmpty);
        await d.settle();
        expect(d.playingUrl, contains('/timeshift/'));
        expect(playerControls(t).liveEdgeActionActive, false);
        stop.release();
        await d.f.until(t, () => d.playingUrl == live.url);
        await d.settle();
        expect(d.banners.where((v) => !v.flush), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        stop.release();
        await d.close();
      }
    },
  );
}

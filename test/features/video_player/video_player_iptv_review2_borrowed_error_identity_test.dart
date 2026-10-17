import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 archive error classification reads a changed borrowed channel row',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-error-row.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      final rows = [live];
      d.response = iptvPanelReply;
      try {
        await d.mount(rows);
        final sheet = await d.guide();
        await d.f.finish(
          t,
          d.observe(
            () => sheet.onPlayProgramme!(live, iptvProgramme(airing: true)),
          ),
        );
        expect(playerControls(t).liveEdgeActionActive, true);
        rows[0] = iptvChannel(0, live: false, url: live.url);
        d.player.emit('error', '403 changed-row');
        await d.settle();
        expect(
          find.text('${live.name} didn\'t play — 403 changed-row'),
          findsOneWidget,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}

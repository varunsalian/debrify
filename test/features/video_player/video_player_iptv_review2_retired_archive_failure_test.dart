import 'dart:async';
import 'package:media_kit/media_kit.dart' as mk;
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 an archive failure after a direct stall retune cannot start another fallback',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-retired-archive.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      final gate = Completer<void>();
      var entered = false;
      Future<void>? replay;
      d.response = iptvPanelReply;
      try {
        await d.mount([live]);
        bool archive(String name, Object? value) =>
            name == 'open' &&
            !entered &&
            ((value as (mk.Playable, bool)).$1 as mk.Media).uri.contains(
              '/timeshift/',
            );
        d.player.heldOperation = archive;
        d.player.beforeOperation = (name, value) async {
          if (archive(name, value)) {
            entered = true;
            await gate.future;
            throw StateError('The retired archive open failed');
          }
        };
        final sheet = await d.guide();
        replay = d.observe(
          () => sheet.onPlayProgramme!(live, iptvProgramme(airing: true)),
        );
        await d.f.until(t, () => entered);
        expect(playerControls(t).liveEdgeActionActive, true);
        d.player.emit('position', d.player.framePosition);
        await d.settle();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 12300)),
        );
        d.player.emit('position', d.player.framePosition);
        await d.settle();
        await d.f.until(t, () => d.opened.length >= 3);
        expect(d.playingUrl, live.url);
        expect(playerControls(t).liveEdgeActionActive, false);
        final before = d.opened.length;
        gate.complete();
        await d.f.finish(t, replay!);
        await d.settle();
        expect(d.opened, hasLength(before));
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        if (replay != null) await d.f.finish(t, replay);
        await d.close();
      }
    },
  );
}

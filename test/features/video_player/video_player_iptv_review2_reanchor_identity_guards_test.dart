import 'dart:async';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a reanchor without categories retains its prior zap directory',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(0);
      var anchors = 0;
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage([
              live,
            ], categories: ++anchors == 1 ? ['News', 'Sports'] : [])
          : null;
      try {
        await d.mount([live], paged: true);
        await d.pick([live], 0);
        await d.f.until(t, () => anchors == 2);
        await d.settle();
        await d.zap(1);
        final requests = d.browse
            .where((r) => !r.containsKey('anchorUrl'))
            .toList();
        expect(requests, isNotEmpty);
        expect(requests.first['category'], 'Sports');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 a guide switch disposed at recording stop cannot issue a reanchor',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(0);
      final stop = IptvAwaitDelivery('switchToIptvChannel', (v) => v == null);
      Future<void>? tune;
      Object? rejected;
      d.provider = (r) => iptvPage([live]);
      try {
        await d.mount([live], paged: true);
        final guide = await d.guide();
        tune = stop.run(
          () => d.observe(() async {
            try {
              await guide.onChannelSelected([live], 0);
            } catch (error) {
              rejected = error;
            }
          }),
        );
        await d.f.until(t, () => stop.pending.isNotEmpty);
        await d.retire();
        final before = d.browse.length;
        stop.release();
        await d.f.finish(t, tune!);
        await d.settle();
        expect(rejected, isNull);
        expect(d.browse, hasLength(before));
        expect(d.errors, isEmpty);
      } finally {
        stop.release();
        if (tune != null) await d.f.finish(t, tune);
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 a newer reanchor of the same playing row owns its neighbors',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(0);
      final old = Completer<Map<String, dynamic>?>();
      var anchors = 0;
      d.provider = (r) => ++anchors == 2
          ? old.future
          : iptvPage([live, iptvChannel(anchors == 1 ? 1 : 9)]);
      try {
        await d.mount([live], paged: true);
        await d.pick([live], 0);
        await d.f.until(t, () => anchors == 2);
        await d.pick([live], 0);
        await d.f.until(t, () => anchors == 3);
        await d.settle();
        old.complete(iptvPage([live, iptvChannel(7)]));
        await d.settle();
        final guide = await d.guide();
        expect(guide.channels.map((c) => c.url), [
          live.url,
          iptvChannel(9).url,
        ]);
        expect(d.errors, isEmpty);
      } finally {
        if (!old.isCompleted) old.complete(null);
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 bootstrap reanchor validates a changed borrowed playing row',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(0);
      final replacement = iptvChannel(8);
      final rows = [live, iptvChannel(1)];
      final page = Completer<Map<String, dynamic>?>();
      d.provider = (r) => page.future;
      try {
        await d.mount(rows, paged: true);
        expect(d.browse, hasLength(1));
        rows[0] = replacement;
        page.complete(iptvPage([live, iptvChannel(7)]));
        await d.settle();
        final guide = await d.guide();
        expect(guide.channels.first.url, replacement.url);
        expect(d.errors, isEmpty);
      } finally {
        if (!page.isCompleted) page.complete(null);
        await d.close();
      }
    },
  );
}

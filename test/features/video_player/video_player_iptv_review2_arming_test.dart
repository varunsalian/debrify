import 'dart:async';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a pending bootstrap suppresses additional unpaged arming',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [iptvChannel(0), iptvChannel(1)];
      final page = Completer<Map<String, dynamic>?>();
      d.provider = (r) =>
          d.browse.length == 1 ? page.future : iptvPage(channels);
      try {
        await d.mount(channels, paged: true);
        expect(d.browse, hasLength(1));
        await d.zap(1);
        await d.zap(-1);
        expect(d.browse, hasLength(1));
        page.complete(null);
        await d.settle();
        await d.zap(1);
        expect(d.browse, hasLength(2));
        expect(d.playingUrl, channels.last.url);
        expect(d.errors, isEmpty);
      } finally {
        if (!page.isCompleted) page.complete(null);
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 reset releases an old page mutex and retires its queued press',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [for (var i = 0; i < 4; i++) iptvChannel(i)];
      final old = Completer<Map<String, dynamic>?>();
      final newer = Completer<Map<String, dynamic>?>();
      var pages = 0;
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage(channels.take(2).toList(), total: 4)
          : ++pages == 1
          ? old.future
          : newer.future;
      try {
        await d.mount(channels.take(2).toList(), paged: true);
        await d.zap(1);
        await d.zap(1);
        expect(pages, 1);
        await d.pick(channels.take(2).toList(), 0);
        await d.zap(1);
        expect(pages, 2);
        old.complete(iptvPage(channels.skip(2).toList(), offset: 2, total: 4));
        await d.settle();
        expect(d.playingUrl, channels[1].url);
        newer.complete(
          iptvPage(channels.skip(2).toList(), offset: 2, total: 4),
        );
        await d.settle();
        expect(d.playingUrl, channels[1].url);
        expect(d.errors, isEmpty);
      } finally {
        if (!old.isCompleted) old.complete(null);
        if (!newer.isCompleted) newer.complete(null);
        await d.close();
      }
    },
  );
}

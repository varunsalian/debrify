import 'dart:async';
import 'package:debrify/features/video_player/models/vp_iptv_zap_page.dart';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a backward uncategorized wrap lands on the final row of a multirow page',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final initial = iptvChannel(0);
      final landing = [iptvChannel(7), iptvChannel(8)];
      d.provider = (r) => iptvPage(
        r.containsKey('anchorUrl') ? [initial] : landing,
        category: null,
        categories: [],
      );
      try {
        await d.mount([initial], paged: true);
        await d.zap(-1);
        expect(d.playingUrl, landing.last.url);
        final requests = d.browse
            .where((r) => !r.containsKey('anchorUrl'))
            .toList();
        expect(requests.first['fromEnd'], true);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  for (final mode in ['no-directory', 'all-with-directory']) {
    testWidgets('P15 review2 boundary wrap preserves $mode admission', (
      t,
    ) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final initial = iptvChannel(0);
      final landing = [iptvChannel(7), iptvChannel(8)];
      final category = mode == 'no-directory' ? 'News' : null;
      final categories = mode == 'no-directory'
          ? <String>[]
          : ['News', 'Sports'];
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage([initial], category: category, categories: categories)
          : iptvPage(landing, category: null, categories: categories);
      try {
        await d.mount([initial], paged: true);
        await d.zap(1);
        final requests = d.browse
            .where((r) => !r.containsKey('anchorUrl'))
            .toList();
        expect(requests, isNotEmpty);
        expect(requests.first['category'], isNull);
        expect(d.playingUrl, landing.first.url);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    });
  }

  for (final empty in [false, true]) {
    testWidgets(
      'P15 review2 an uncategorized landing owns queued presses empty=$empty',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final initial = iptvChannel(0);
        final landing = [iptvChannel(7), iptvChannel(8)];
        final page = Completer<Map<String, dynamic>?>();
        var requests = 0;
        d.provider = (r) => r.containsKey('anchorUrl')
            ? iptvPage([initial], category: null, categories: [])
            : ++requests == 1
            ? page.future
            : iptvPage(landing, category: null, categories: []);
        try {
          await d.mount([initial], paged: true);
          await d.zap(1);
          await d.zap(1);
          expect(requests, 1);
          page.complete(
            iptvPage(empty ? [] : landing, category: null, categories: []),
          );
          await d.settle();
          if (empty) {
            // An empty wrap must neither install an empty ring nor carry its
            // queued press into a later independent successful wrap.
            expect(playerControls(t).hasIptvChannels, true);
            expect(d.playingUrl, initial.url);
            await d.zap(1);
            await d.settle();
            expect(d.playingUrl, landing.first.url);
          } else {
            expect(d.playingUrl, landing.last.url);
          }
          expect(d.errors, isEmpty);
        } finally {
          if (!page.isCompleted) page.complete(null);
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P15 review2 a parsed uncategorized wrap cannot install after disposal',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final initial = iptvChannel(0);
      final parsed = IptvAwaitDelivery(
        'requestAdjacentIptvCategory',
        (v) => v is VpIptvZapPage,
      );
      d.provider = (r) => iptvPage(
        r.containsKey('anchorUrl') ? [initial] : [iptvChannel(7)],
        category: null,
        categories: [],
      );
      try {
        await d.mount([initial], paged: true);
        await parsed.run(() => d.zap(1));
        await d.f.until(t, () => parsed.pending.isNotEmpty);
        await d.retire();
        final before = d.opened.length;
        parsed.release();
        await d.settle();
        expect(d.opened, hasLength(before));
        expect(d.errors, isEmpty);
      } finally {
        parsed.release();
        await d.close();
      }
    },
  );
}

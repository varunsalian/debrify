import 'dart:async';
import 'package:debrify/features/video_player/models/vp_iptv_zap_page.dart';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final caller in ['same-page', 'prefetch-category', 'request-category']) {
    testWidgets(
      'P15 review2 parsed page delivery respects disposal in $caller',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final channels = [
          for (
            var i = 0;
            i <
                (caller == 'same-page'
                    ? 30
                    : caller == 'prefetch-category'
                    ? 2
                    : 1);
            i++
          )
            iptvChannel(i),
        ];
        final response = Completer<Map<String, dynamic>?>();
        final delivery = IptvAwaitDelivery(
          caller == 'same-page'
              ? 'prefetchIptvZapPage'
              : caller == 'prefetch-category'
              ? 'prefetchAdjacentIptvCategory'
              : 'requestAdjacentIptvCategory',
          (v) => v is VpIptvZapPage,
        );
        d.provider = (r) => r.containsKey('anchorUrl')
            ? iptvPage(
                channels,
                total: caller == 'same-page' ? 60 : channels.length,
                categories: ['News', 'Sports'],
              )
            : response.future;
        try {
          await d.mount(
            channels,
            index: caller == 'same-page' ? 18 : 0,
            paged: true,
          );
          await delivery.run(() => d.zap(1));
          expect(
            d.browse.where((r) => !r.containsKey('anchorUrl')),
            hasLength(1),
          );
          if (caller == 'prefetch-category') {
            await d.zap(1);
          }
          response.complete(
            iptvPage(
              [
                iptvChannel(
                  30,
                  group: caller == 'same-page' ? 'News' : 'Sports',
                ),
              ],
              offset: caller == 'same-page' ? 30 : 0,
              total: caller == 'same-page' ? 60 : 1,
              category: caller == 'same-page' ? 'News' : 'Sports',
              categories: ['News', 'Sports'],
            ),
          );
          await d.f.until(t, () => delivery.pending.isNotEmpty);
          final issued = d.browse.length;
          await d.retire();
          delivery.release();
          await d.settle();
          expect(d.browse, hasLength(issued));
          expect(d.errors, isEmpty);
        } finally {
          delivery.release();
          if (!response.isCompleted) {
            response.complete(null);
          }
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 review2 disposed page request does not decode a malformed source',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [for (var i = 0; i < 30; i++) iptvChannel(i)];
      final response = Completer<Map<String, dynamic>?>();
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage(channels, total: 60)
          : response.future;
      try {
        await d.mount(channels, index: 18, paged: true);
        await d.zap(1);
        expect(
          d.browse.where((r) => !r.containsKey('anchorUrl')),
          hasLength(1),
        );
        await d.retire();
        response.complete(
          iptvPage([iptvChannel(30)], offset: 30, total: 60)..['sourceId'] = 7,
        );
        await d.settle();
        expect(d.errors, isEmpty);
      } finally {
        if (!response.isCompleted) {
          response.complete(null);
        }
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 already parsed adjacent page can retune after a guide reset',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(0);
      final movie = iptvChannel(8, live: false);
      final late = [iptvChannel(90), iptvChannel(91)];
      final response = Completer<Map<String, dynamic>?>();
      final tail = Completer<Map<String, dynamic>?>();
      final delivery = IptvAwaitDelivery(
        'requestAdjacentIptvCategory',
        (v) => v is VpIptvZapPage,
      );
      var requests = 0;
      d.provider = (r) {
        if (r.containsKey('anchorUrl')) {
          return iptvPage([live], categories: ['News', 'Sports']);
        }
        return requests++ == 0 ? response.future : tail.future;
      };
      try {
        await d.mount([live], paged: true, source: 'WidgetOwner');
        final context = await d.guide();
        context.onContextChanged!(
          IptvGuideContext(
            categories: ['News', 'Sports'],
            sourceId: null,
            sourceName: 'All sources',
            selectedCategory: 'News',
            contentType: 'live',
          ),
        );
        await d.closeGuide(context);
        await delivery.run(() => d.zap(1));
        response.complete(
          iptvPage(
            late,
            source: null,
            total: 100,
            categories: ['News', 'Sports'],
          ),
        );
        await d.f.until(t, () => delivery.pending.isNotEmpty);
        await d.pick([movie], 0);
        expect(d.playingUrl, movie.url);
        expect(playerControls(t).onNext, isNull);
        delivery.release();
        await d.f.until(t, () => d.playingUrl == late.first.url);
        expect(d.browse.last['sourceId'], 'WidgetOwner');
        expect(d.browse.last['category'], 'News');
        expect(d.browse.last['offset'], 2);
        expect(d.errors, isEmpty);
      } finally {
        delivery.release();
        if (!response.isCompleted) {
          response.complete(null);
        }
        if (!tail.isCompleted) {
          tail.complete(null);
        }
        await d.close();
      }
    },
  );
}

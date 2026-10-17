import 'dart:async';
import 'package:debrify/features/video_player/models/vp_iptv_zap_page.dart';
import 'package:flutter/services.dart';
// Existing resolved preference transport.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/display_defaults_reads.dart';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 reanchor clears a cache published after a concurrent early bootstrap',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final previous = SharedPreferencesStorePlatform.instance;
      final reads = (await t.runAsync(DisplayDefaultsReads.install))!;
      final news = [iptvChannel(0), iptvChannel(1)];
      final replacement = [news.first, iptvChannel(2)];
      const categories = ['News', 'Sports'];
      final reanchor = Completer<Map<String, dynamic>?>();
      final cache = IptvAwaitDelivery(
        'prefetchAdjacentIptvCategory',
        (v) => v is VpIptvZapPage,
      );
      var anchors = 0;
      var sports = 0;
      d.provider = (r) {
        if (r.containsKey('anchorUrl')) {
          anchors++;
          if (anchors == 2) return reanchor.future;
          return iptvPage(
            anchors == 1 ? news : replacement,
            categories: categories,
          );
        }
        sports++;
        return iptvPage(
          [iptvChannel(90 + sports, group: 'Sports')],
          category: 'Sports',
          categories: categories,
        );
      };
      try {
        await d.observe(
          () => t.pumpWidget(
            MaterialApp(
              navigatorKey: d.f.navigator,
              theme: ThemeData.dark(),
              home: d.screen([news.first], paged: true),
            ),
          ),
        );
        await d.f.until(t, () => reads.entered);
        await d.observe(() => d.f.key(t, LogicalKeyboardKey.keyG));
        var sheet = t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
        await d.f.finish(t, d.observe(() => sheet.onChannelSelected(news, 0)));
        await d.f.until(t, () => anchors == 1);
        await d.settle();
        await cache.run(
          () => d.observe(() => d.f.key(t, LogicalKeyboardKey.pageUp)),
        );
        await d.f.until(t, () => cache.pending.isNotEmpty);
        expect(sports, 1);
        await d.observe(() => d.f.key(t, LogicalKeyboardKey.keyG));
        sheet = t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
        await d.f.finish(
          t,
          d.observe(() => sheet.onChannelSelected(replacement, 0)),
        );
        await d.f.until(t, () => anchors == 2);
        expect(d.f.players, isEmpty);
        reads.unblock();
        await d.f.until(t, () => d.f.controllers.isNotEmpty);
        d.player.deliverReady();
        await d.f.until(t, () => d.opened.isNotEmpty);
        await d.f.until(t, () => anchors == 3);
        await d.f.until(
          t,
          () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
        );
        await d.settle();
        cache.release();
        await d.settle();
        reanchor.complete(iptvPage(replacement, categories: categories));
        await d.settle();
        await d.zap(1);
        expect(
          sports,
          2,
          reason: 'The late reanchor must retire the intervening cache',
        );
        expect(d.playingUrl, replacement.last.url);
        expect(d.errors, isEmpty);
      } finally {
        reads.unblock();
        cache.release();
        if (!reanchor.isCompleted) reanchor.complete(null);
        await d.close();
        SharedPreferencesStorePlatform.instance = previous;
      }
    },
  );

  testWidgets(
    'P15 review2 a reset category rejects an old cache before a same-category late landing',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final news = [iptvChannel(0), iptvChannel(1)];
      final landing = iptvChannel(7);
      const categories = ['News', 'Sports'];
      final cache = IptvAwaitDelivery(
        'prefetchAdjacentIptvCategory',
        (v) => v is VpIptvZapPage,
      );
      final crossing = IptvAwaitDelivery(
        'requestAdjacentIptvCategory',
        (v) => v is VpIptvZapPage,
      );
      var sports = 0;
      d.provider = (r) {
        if (r.containsKey('anchorUrl')) {
          return iptvPage(news, categories: categories);
        }
        sports++;
        // The original accepts a nonempty adjacent response's reported category,
        // even when it differs from the requested one. Pin that existing path.
        return sports == 2
            ? iptvPage([landing], category: 'News', categories: categories)
            : iptvPage(
                [iptvChannel(90 + sports, group: 'Sports')],
                category: 'Sports',
                categories: categories,
              );
      };
      try {
        await d.mount(news, paged: true);
        await cache.run(() => d.zap(1));
        await d.f.until(t, () => cache.pending.isNotEmpty);
        await crossing.run(() => d.zap(1));
        await d.f.until(t, () => crossing.pending.isNotEmpty);
        expect(sports, 2);
        await d.pick([iptvChannel(50, live: false)], 0);
        cache.release();
        await d.settle();
        crossing.release();
        await d.settle();
        expect(d.playingUrl, landing.url);
        expect(
          sports,
          3,
          reason: 'A cache delivered while paging was reset cannot be reused',
        );
        expect(d.errors, isEmpty);
      } finally {
        cache.release();
        crossing.release();
        await d.close();
      }
    },
  );
}

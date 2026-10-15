import 'dart:async';
import 'support/iptv_workflow_driver.dart';
import 'support/local_completion_driver.dart';

void main() {
  for (final delta in [-1, 1]) {
    testWidgets(
      'P15 unpaged ring wraps direction=$delta and keeps headers and identity',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final channels = [
          for (var i = 0; i < 3; i++)
            iptvChannel(i, headers: {'X-Channel': '$i'}),
        ];
        try {
          await d.mount(channels, index: delta > 0 ? 2 : 0);
          await d.zap(delta);
          expect(d.playingUrl, channels[delta > 0 ? 0 : 2].url);
          final sheet = await d.guide();
          expect(sheet.currentIndex, delta > 0 ? 0 : 2);
          expect(sheet.selectedCategory, 'News');
          expect(sheet.sourceName, 'IPTV');
          expect(sheet.contentType, 'live');
          expect(d.opened.length, 2);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
    testWidgets(
      'P15 edge margin prefetches direction=$delta with the ring source and fixed page size',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final channels = [for (var i = 0; i < 30; i++) iptvChannel(i)];
        d.provider = (r) => r.containsKey('anchorUrl')
            ? iptvPage(channels, offset: delta > 0 ? 0 : 1500, total: 2000)
            : null;
        try {
          await d.mount(channels, index: delta > 0 ? 18 : 11, paged: true);
          await d.zap(delta);
          final request = d.browse.firstWhere(
            (r) => !r.containsKey('anchorUrl'),
          );
          expect(request, containsPair('sourceId', 'ring-source'));
          expect(request['category'], 'News');
          expect(request['offset'], delta > 0 ? 30 : 0);
          expect(request['limit'], 1500);
          expect(request['fromEnd'], false);
        } finally {
          await d.close();
        }
      },
    );
    testWidgets(
      'P15 category prefetch is consumed without a crossing round trip direction=$delta',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final a = [iptvChannel(1), iptvChannel(2)];
        final b = [
          iptvChannel(3, group: 'Sports'),
          iptvChannel(4, group: 'Sports'),
        ];
        d.provider = (r) => iptvPage(
          r['category'] == 'Sports' ? b : a,
          category: r['category'] == 'Sports' ? 'Sports' : 'News',
          categories: ['News', 'Sports'],
        );
        try {
          await d.mount(a, index: delta > 0 ? 0 : 1, paged: true);
          await d.zap(delta);
          expect(d.browse.where((r) => r['category'] == 'Sports').length, 1);
          final before = d.browse.length;
          await d.zap(delta);
          expect(d.playingUrl, b[delta > 0 ? 0 : 1].url);
          expect(d.browse.where((r) => r['category'] == 'Sports').length, 1);
          final cross = d.browse.where((r) => r['category'] == 'Sports').single;
          expect(cross['fromEnd'], delta < 0);
          expect(cross['offset'], 0);
          expect(d.browse.length, greaterThanOrEqualTo(before));
          final sheet = await d.guide();
          expect(sheet.selectedCategory, 'Sports');
          expect(sheet.categories, ['News', 'Sports']);
        } finally {
          await d.close();
        }
      },
    );
    testWidgets(
      'P15 uncategorized paging wraps to the opposite end direction=$delta',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final a = [iptvChannel(1, group: null)];
        d.provider = (r) => r.containsKey('anchorUrl')
            ? iptvPage(a, category: null, categories: [])
            : iptvPage(
                [iptvChannel(9, group: 'Actual')],
                category: null,
                categories: [],
              );
        try {
          await d.mount(a, paged: true);
          await d.zap(delta);
          expect(d.playingUrl, 'https://p15.test/9.ts');
          final req = d.browse.firstWhere((r) => !r.containsKey('anchorUrl'));
          expect(req['category'], isNull);
          expect(req['fromEnd'], delta < 0);
          final sheet = await d.guide();
          expect(sheet.selectedCategory, isNull);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final delta in [-1, 1]) {
    testWidgets(
      'P15 edge margin does not prefetch one press before direction=$delta threshold',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final a = [for (var i = 0; i < 30; i++) iptvChannel(i)];
        d.provider = (r) => r.containsKey('anchorUrl')
            ? iptvPage(a, offset: delta > 0 ? 0 : 1500, total: 2000)
            : null;
        try {
          await d.mount(a, index: delta > 0 ? 17 : 12, paged: true);
          await d.zap(delta);
          expect(d.browse.where((r) => !r.containsKey('anchorUrl')), isEmpty);
          await d.zap(delta);
          expect(d.browse.where((r) => !r.containsKey('anchorUrl')).length, 1);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final bad in ['null', 'shape', 'missing-playing', 'throw']) {
    testWidgets(
      'P15 bootstrap rejection $bad preserves launch window and retries arming',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final a = [iptvChannel(0), iptvChannel(1)];
        var attempts = 0;
        d.provider = (r) {
          if (!r.containsKey('anchorUrl')) {
            return null;
          }
          attempts++;
          return switch (bad) {
            'null' => null,
            'shape' => {'channels': 'bad'},
            'missing-playing' => iptvPage([iptvChannel(9)]),
            _ => throw StateError('fixture browse'),
          };
        };
        try {
          await d.mount(a, paged: true);
          expect(attempts, 1);
          await d.zap(1);
          expect(attempts, 2);
          expect(d.playingUrl, a[1].url);
          final s = await d.guide();
          expect(s.channels.map((c) => c.url), a.map((c) => c.url));
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final retire in ['browse', 'guide-pick', 'dispose']) {
    testWidgets(
      'P15 pending page is stranded by $retire and pending inputs do not replay',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final reply = Completer<Map<String, dynamic>?>();
        final a = [iptvChannel(0), iptvChannel(1)];
        d.provider = (r) =>
            r.containsKey('anchorUrl') ? iptvPage(a, total: 4) : reply.future;
        try {
          await d.mount(a, index: 1, paged: true);
          await d.zap(1);
          await d.zap(1);
          expect(d.browse.where((r) => !r.containsKey('anchorUrl')).length, 1);
          final s = await d.guide();
          if (retire == 'browse') {
            s.onContextChanged!(
              IptvGuideContext(
                categories: ['User'],
                sourceId: 'user-source',
                sourceName: 'User',
                selectedCategory: 'User',
                contentType: 'live',
              ),
            );
            await d.closeGuide(s);
          }
          if (retire == 'guide-pick') {
            await d.f.finish(t, s.onChannelSelected([iptvChannel(9)], 0));
          }
          if (retire == 'dispose') {
            await d.retire();
          }
          final before = d.opened.length;
          reply.complete(
            iptvPage([iptvChannel(2), iptvChannel(3)], offset: 2, total: 4),
          );
          await d.settle();
          expect(d.opened.length, before);
          if (retire != 'dispose') {
            final after = await d.guide();
            expect(after.channels.any((c) => c.url.endsWith('/2.ts')), false);
          }
        } finally {
          if (!reply.isCompleted) {
            reply.complete(null);
          }
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 pending page queues at most 24 presses and same-turn drain shares the old index',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final reply = Completer<Map<String, dynamic>?>();
      final a = [iptvChannel(0), iptvChannel(1)];
      final held = CompletionDelivery('switchToIptvChannel', (v) => v == null)
        ..multiple = true;
      var roundTrips = 0;
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage(a, total: 50)
          : ++roundTrips == 1
          ? reply.future
          : null;
      try {
        await d.mount(a, index: 1, paged: true);
        final next = playerControls(t).onNext!;
        held.run(() {
          for (var i = 0; i < 30; i++) {
            next();
          }
        });
        await d.settle();
        expect(d.browse.where((r) => !r.containsKey('anchorUrl')).length, 1);
        reply.complete(
          iptvPage(
            [for (var i = 2; i < 50; i++) iptvChannel(i)],
            offset: 2,
            total: 50,
          ),
        );
        await d.f.until(t, () => held.pending.isNotEmpty);
        expect(held.pending.length, 24);
        held.release();
        await d.settle();
        expect(d.playingUrl, 'https://p15.test/2.ts');
        expect(d.opened.length, 2);
      } finally {
        held.release();
        if (!reply.isCompleted) {
          reply.complete(null);
        }
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 full empty category walk clears queued inputs without looping',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final a = [iptvChannel(0)];
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage(a, categories: ['News', 'Empty'])
          : iptvPage(
              [],
              category: r['category'] as String?,
              categories: ['News', 'Empty'],
            );
      try {
        await d.mount(a, paged: true);
        await d.zap(1);
        await d.settle();
        expect(d.opened.length, 1);
        expect(
          d.browse
              .where((r) => !r.containsKey('anchorUrl'))
              .map((r) => r['category']),
          ['Empty', 'News'],
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 guide pick of one unmatched channel retires paging before reanchor',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final a = [iptvChannel(0), iptvChannel(1)];
      final lone = iptvChannel(9);
      d.provider = (r) => r['anchorUrl'] == lone.url ? null : iptvPage(a);
      try {
        await d.mount(a, paged: true);
        await d.pick([lone], 0);
        expect(d.playingUrl, lone.url);
        expect(playerControls(t).onNext, isNull);
        expect(playerControls(t).onPrevious, isNull);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  for (final delta in [-1, 1]) {
    testWidgets(
      'P15 touching page merge grows both directions and preserves playing identity direction=$delta',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final a = [for (var i = 0; i < 30; i++) iptvChannel(i)];
        final extra = [iptvChannel(98), iptvChannel(99)];
        var requests = 0;
        d.provider = (r) => r.containsKey('anchorUrl')
            ? iptvPage(a, offset: delta > 0 ? 0 : 2, total: 34)
            : ++requests == 1
            ? iptvPage(extra, offset: delta > 0 ? 30 : 0, total: 34)
            : null;
        try {
          await d.mount(a, index: delta > 0 ? 18 : 11, paged: true);
          await d.zap(delta);
          final guide = await d.guide();
          expect(guide.channels.length, 32);
          expect(guide.currentIndex, delta > 0 ? 19 : 12);
          expect(
            guide.channels[guide.currentIndex].url,
            a[delta > 0 ? 19 : 10].url,
          );
          expect(d.playingUrl, a[delta > 0 ? 19 : 10].url);
          expect(guide.channels.map((c) => c.url), [
            if (delta < 0) ...extra.map((c) => c.url),
            ...a.map((c) => c.url),
            if (delta > 0) ...extra.map((c) => c.url),
          ]);
          expect(d.opened.length, 2);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 reversing direction invalidates an adjacent category cache before reuse',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final a = [iptvChannel(0), iptvChannel(1), iptvChannel(2)];
      final sports = [iptvChannel(8, group: 'Sports')];
      final categories = ['Other', 'News', 'Sports'];
      d.provider = (r) => iptvPage(
        r['category'] == 'Sports' ? sports : a,
        category: r['category'] as String?,
        categories: categories,
      );
      try {
        await d.mount(a, paged: true);
        await d.zap(1);
        expect(d.browse.where((r) => r['category'] == 'Sports').length, 1);
        await d.zap(-1);
        expect(d.browse.where((r) => r['category'] == 'Other').length, 1);
        await d.zap(1);
        expect(d.browse.where((r) => r['category'] == 'Sports').length, 2);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}

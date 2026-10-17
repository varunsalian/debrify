import 'dart:async';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a guide switch disposed at recording stop cannot request an anchor',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [iptvChannel(0), iptvChannel(1)];
      d.provider = (r) => iptvPage(channels);
      final stop = IptvAwaitDelivery('switchToIptvChannel', (v) => v == null);
      Future<void>? pick;
      try {
        await d.mount(channels, paged: true);
        final sheet = await d.guide();
        pick = stop.run(
          () => d.observe(() => sheet.onChannelSelected(channels, 1)),
        );
        await d.f.until(t, () => stop.pending.isNotEmpty);
        await d.retire();
        final before = d.browse.length;
        stop.release();
        await d.f.finish(t, pick!);
        await d.settle();
        expect(d.browse.length, before);
        expect(d.errors, isEmpty);
      } finally {
        stop.release();
        if (pick != null) await d.f.finish(t, pick);
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 guide reset strands a page before the adopted VOD switch',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [for (var i = 0; i < 30; i++) iptvChannel(i)];
      final movie = iptvChannel(90, live: false);
      final page = Completer<Map<String, dynamic>?>();
      d.provider = (r) => r.containsKey('anchorUrl')
          ? iptvPage(channels, total: 60)
          : page.future;
      final stop = IptvAwaitDelivery('switchToIptvChannel', (v) => v == null);
      Future<void>? pick;
      try {
        await d.mount(channels, index: 18, paged: true);
        await d.zap(1);
        expect(
          d.browse.where((r) => !r.containsKey('anchorUrl')),
          hasLength(1),
        );
        final sheet = await d.guide();
        pick = stop.run(
          () => d.observe(() => sheet.onChannelSelected([movie], 0)),
        );
        await d.f.until(t, () => stop.pending.isNotEmpty);
        expect(
          t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet)).channels,
          hasLength(30),
          reason: 'Adopting the list alone does not publish a rebuild',
        );
        page.complete(iptvPage([iptvChannel(30)], total: 60));
        // Adoption precedes the switch's setState. The original duration
        // listener supplies a real rebuild while recording stop is held.
        d.player.emit('duration', const Duration(minutes: 21));
        await d.settle();
        final visible = t
            .widget<IptvChannelSheet>(find.byType(IptvChannelSheet))
            .channels;
        expect(visible, hasLength(1));
        expect(visible.single.url, movie.url);
        stop.release();
        await d.f.finish(t, pick!);
        expect(d.playingUrl, movie.url);
        await d.settle();
        expect(d.browse.where((r) => r.containsKey('anchorUrl')), hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        if (!page.isCompleted) page.complete(null);
        stop.release();
        if (pick != null) await d.f.finish(t, pick);
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 guide validates both index bounds and accepts row zero',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [iptvChannel(0), iptvChannel(1)];
      try {
        await d.mount(channels, index: 1);
        final sheet = await d.guide();
        final before = d.opened.length;
        for (final index in [-1, channels.length]) {
          Object? failure;
          try {
            await sheet.onChannelSelected(channels, index);
          } catch (error) {
            failure = error;
          }
          expect(failure, isNull, reason: 'An invalid guide row is ignored');
          expect(d.opened.length, before);
          expect(d.playingUrl, channels[1].url);
        }
        await d.f.finish(
          t,
          d.observe(() => sheet.onChannelSelected(channels, 0)),
        );
        expect(d.opened.length, before + 1);
        expect(d.playingUrl, channels.first.url);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 guide retires archive lookup before its switch stop await',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-guide-entry.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      final next = iptvChannel(1);
      d.response = iptvPanelReply;
      final lookup = IptvAwaitDelivery(
        'startIptvProgrammeFromBeginning',
        (v) => v is String,
      );
      final stop = IptvAwaitDelivery('switchToIptvChannel', (v) => v == null);
      Future<void>? start;
      Future<void>? pick;
      try {
        await d.mount([live, next]);
        final sheet = await d.guide();
        start = lookup.run(
          () => d.observe(
            () => sheet.onPlayProgramme!(live, iptvProgramme(airing: true)),
          ),
        );
        await d.f.until(t, () => lookup.pending.isNotEmpty);
        expect(playerControls(t).liveEdgeActionLoading, true);
        pick = stop.run(
          () => d.observe(() => sheet.onChannelSelected([live, next], 1)),
        );
        await d.f.until(t, () => stop.pending.isNotEmpty);
        expect(playerControls(t).liveEdgeActionLoading, false);
        lookup.release();
        await d.f.finish(t, start!);
        stop.release();
        await d.f.finish(t, pick!);
        expect(d.playingUrl, next.url);
        expect(d.errors, isEmpty);
      } finally {
        lookup.release();
        stop.release();
        if (start != null) await d.f.finish(t, start);
        if (pick != null) await d.f.finish(t, pick);
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 guide waits for the switch before requesting its anchor',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [iptvChannel(0), iptvChannel(1)];
      d.provider = (r) => iptvPage(channels);
      final stop = IptvAwaitDelivery('switchToIptvChannel', (v) => v == null);
      Future<void>? pick;
      try {
        await d.mount(channels, paged: true);
        final sheet = await d.guide();
        final before = d.browse.length;
        pick = stop.run(
          () => d.observe(() => sheet.onChannelSelected(channels, 1)),
        );
        await d.f.until(t, () => stop.pending.isNotEmpty);
        await d.settle();
        expect(d.browse.length, before);
        stop.release();
        await d.f.finish(t, pick!);
        await d.f.until(t, () => d.browse.length > before);
        expect(d.browse.last['anchorUrl'], channels[1].url);
        expect(d.errors, isEmpty);
      } finally {
        stop.release();
        if (pick != null) await d.f.finish(t, pick);
        await d.close();
      }
    },
  );
}

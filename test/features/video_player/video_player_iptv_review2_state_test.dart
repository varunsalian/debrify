import 'dart:async';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 unavailable Start Over clears dock loading and admits retry',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-j1.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      final reply = Completer<Response>();
      d.response = (r) =>
          r.url.path.contains('/timeshift/') ? reply.future : iptvPanelReply(r);
      try {
        await d.mount([live]);
        await d.f.until(t, () => playerControls(t).onLiveEdgeAction != null);
        d.observe(() => playerControls(t).onLiveEdgeAction!());
        await d.f.until(
          t,
          () => d.f.network.requests.any(
            (r) => r.url.path.contains('/timeshift/'),
          ),
        );
        await d.settle();
        expect(playerControls(t).liveEdgeActionLoading, true);
        reply.complete(Response('', 404));
        await d.f.until(
          t,
          () => find.text('Start over is not available').evaluate().isNotEmpty,
        );
        expect(playerControls(t).liveEdgeActionLoading, false);
        expect(d.opened.length, 1);
        expect(d.errors, isEmpty);
      } finally {
        if (!reply.isCompleted) {
          reply.complete(Response('', 404));
        }
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 replay retires paged ring and strands a touching pending page',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(0, url: 'https://p15-j5.test/live/u/p/123.ts');
      final page = Completer<Map<String, dynamic>?>();
      d.provider = (r) =>
          r.containsKey('anchorUrl') ? iptvPage([live], total: 2) : page.future;
      d.response = iptvPanelReply;
      try {
        await d.mount([live], paged: true);
        await d.zap(1);
        expect(d.browse.where((r) => !r.containsKey('anchorUrl')).length, 1);
        final sheet = await d.guide();
        await d.f.finish(
          t,
          d.observe(() => sheet.onPlayProgramme!(live, iptvProgramme())),
        );
        expect(d.playingUrl, contains('/timeshift/'));
        page.complete(iptvPage([iptvChannel(1)], offset: 1, total: 2));
        await d.settle();
        final replay = await d.guide();
        expect(replay.channels.length, 1);
        expect(replay.channels.single.contentType, 'vod');
        expect(replay.channels.single.url, d.playingUrl);
        expect(playerControls(t).onNext, isNull);
        expect(d.browse.where((r) => !r.containsKey('anchorUrl')).length, 1);
        expect(d.errors, isEmpty);
      } finally {
        if (!page.isCompleted) {
          page.complete(null);
        }
        await d.close();
      }
    },
  );
  for (final value in [null, 'false', 'true']) {
    testWidgets(
      'P15 review2 has-next $value reaches physical nullable history column',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final movie = iptvChannel(
          1,
          live: false,
          attributes: {if (value != null) 'has_next_episode': value},
        );
        try {
          await d.mount([iptvChannel(0), movie]);
          await d.pick([movie], 0);
          final scope = ProfileRuntime.capture();
          List<Map<String, Object?>> rows = [];
          for (var attempt = 0; attempt < 50 && rows.isEmpty; attempt++) {
            rows = (await t.runAsync(() => iptvPhysicalHistory(d, scope)))!;
            if (rows.isEmpty) {
              await d.advance(const Duration(milliseconds: 50));
            }
          }
          expect(rows, hasLength(1));
          expect(
            rows.single['has_next'],
            value == null
                ? null
                : value == 'true'
                ? 1
                : 0,
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 review2 visible non-live dock does not retain live identity ticker',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [iptvChannel(0), iptvChannel(1, live: false)];
      try {
        await d.mount(channels);
        expect(
          d.periodic.where(
            (v) => v.$1 == const Duration(seconds: 1) && v.$2.isActive,
          ),
          isNotEmpty,
        );
        await d.pick(channels, 1);
        await d.observe(() => t.tapAt(const Offset(600, 300)));
        await d.advance(const Duration(milliseconds: 400));
        expect(d.playingUrl, channels[1].url);
        expect(
          d.periodic.where(
            (v) => v.$1 == const Duration(seconds: 1) && v.$2.isActive,
          ),
          isEmpty,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}

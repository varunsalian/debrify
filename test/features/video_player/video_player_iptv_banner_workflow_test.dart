import 'dart:async';
import 'package:flutter/services.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 banner paints warm guide immediately then archive metadata enables live edge',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-warm-banner.test/live/u/p/123.ts',
      );
      final archive = Completer<Response>();
      d.response = (r) =>
          r.url.queryParameters['action'] == 'get_simple_data_table'
          ? archive.future
          : iptvPanelReply(r, archive: false);
      try {
        await d.f.finish(t, IptvEpgService.instance.nowNext(live.url));
        await d.mount([live]);
        expect(d.banners, isNotEmpty);
        expect(d.banners.first.epg?.now?.title, 'P15 current programme');
        expect(d.banners.first.epgLoading, false);
        expect(playerControls(t).onLiveEdgeAction, isNull);
        archive.complete(
          iptvPanelReply(
            Request(
              'GET',
              Uri.parse('https://p15-warm-banner.test/player_api.php'),
            ),
          ),
        );
        await d.settle();
        expect(playerControls(t).onLiveEdgeAction, isNotNull);
        expect(d.banners.first.epg?.now?.hasArchive, true);
        expect(d.errors, isEmpty);
      } finally {
        if (!archive.isCompleted) {
          archive.complete(Response('{}', 404));
        }
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 banner late EPG from an outgoing channel cannot paint the incoming identity',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final a = iptvChannel(0, url: 'https://p15-late-a.test/live/u/p/123.ts');
      final b = iptvChannel(1, url: 'https://p15-late-b.test/live/u/p/456.ts');
      final reply = Completer<Response>();
      d.response = (r) => r.url.host == 'p15-late-a.test'
          ? reply.future
          : iptvPanelReply(r, title: 'B programme');
      try {
        await d.mount([a, b]);
        await d.zap(1);
        reply.complete(
          iptvPanelReply(
            Request('GET', Uri.parse('https://p15-late-a.test/player_api.php')),
            title: 'A stale',
          ),
        );
        await d.settle();
        final guide = await d.guide();
        expect(guide.channels[guide.currentIndex].url, b.url);
        expect(find.text('A stale'), findsNothing);
        expect(d.errors, isEmpty);
      } finally {
        if (!reply.isCompleted) {
          reply.complete(Response('{}', 404));
        }
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 floating banner fades at 4500ms and hands immediately to dock',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final a = [iptvChannel(0), iptvChannel(1), iptvChannel(2)];
      try {
        await d.mount(a);
        await d.advance(const Duration(seconds: 6));
        await d.zap(1);
        expect(
          d.timed.where((v) => v.$1 == const Duration(milliseconds: 4500)),
          isNotEmpty,
        );
        final hide = d.timed
            .lastWhere((v) => v.$1 == const Duration(milliseconds: 4500))
            .$2;
        expect(hide.isActive, true);
        await d.timerAge(hide, const Duration(milliseconds: 4499));
        expect(hide.isActive, true);
        await d.advance(const Duration(milliseconds: 1));
        expect(hide.isActive, false);
        await d.zap(1);
        final second = d.timed
            .lastWhere((v) => v.$1 == const Duration(milliseconds: 4500))
            .$2;
        expect(second.isActive, true);
        await t.tapAt(const Offset(600, 300));
        await d.f.until(t, () => !second.isActive);
        expect(second.isActive, false);
        expect(d.banners.length, 1);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 banner ticker is one second only while the live identity is visible',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(0);
      try {
        await d.mount([live]);
        final tickers = d.periodic
            .where((v) => v.$1 == const Duration(seconds: 1))
            .toList();
        expect(tickers, isNotEmpty);
        expect(tickers.last.$2.isActive, true);
        final s = await d.guide();
        expect(tickers.last.$2.isActive, false);
        await d.closeGuide(s);
        await d.observe(() => d.f.key(t, LogicalKeyboardKey.enter));
        await d.f.until(
          t,
          () => d.periodic.any(
            (v) => v.$1 == const Duration(seconds: 1) && v.$2.isActive,
          ),
        );
        final active = d.periodic.where(
          (v) => v.$1 == const Duration(seconds: 1) && v.$2.isActive,
        );
        expect(active.length, 1);
        await d.advance(const Duration(seconds: 1));
        await t.tapAt(const Offset(600, 300));
        await d.f.until(t, () => active.every((v) => !v.$2.isActive));
        expect(active.every((v) => !v.$2.isActive), true);
        await d.observe(() => d.f.key(t, LogicalKeyboardKey.enter));
        await d.settle();
        final reopened = d.periodic.where(
          (v) => v.$1 == const Duration(seconds: 1) && v.$2.isActive,
        );
        expect(reopened.length, 1);
        await d.retire();
        expect(reopened.every((v) => !v.$2.isActive), true);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}

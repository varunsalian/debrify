import 'dart:async';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'support/iptv_workflow_driver.dart';
import 'support/local_completion_driver.dart';

void main() {
  for (final category in [null, ' Sports ']) {
    testWidgets(
      'P15 guide anchors trimmed category $category and preserves user context',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final a = iptvChannel(0, group: category);
        try {
          await d.mount([a, iptvChannel(1)]);
          final s = await d.guide();
          expect(s.selectedCategory, category?.trim());
          s.onContextChanged!(
            IptvGuideContext(
              categories: ['User', 'Other'],
              sourceId: 'user',
              sourceName: 'Mine',
              selectedCategory: 'User',
              contentType: 'vod',
            ),
          );
          await d.closeGuide(s);
          expect(find.byType(IptvChannelSheet), findsNothing);
          final reopened = await d.guide();
          expect(reopened.sourceId, 'user');
          expect(reopened.sourceName, 'Mine');
          expect(reopened.contentType, 'vod');
          expect(reopened.selectedCategory, 'User');
          expect(reopened.categories, ['User', 'Other']);
          expect(reopened.onChannelSelected, s.onChannelSelected);
          expect(reopened.onClose, s.onClose);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final retire in ['switch', 'browse', 'dispose', 'missing-playing']) {
    testWidgets('P15 guide pick reanchor rejects late $retire results', (
      t,
    ) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final a = iptvChannel(0);
      final b = iptvChannel(1, group: 'Sports');
      final c = iptvChannel(2, group: 'User');
      final reply = Completer<Map<String, dynamic>?>();
      var hold = false;
      d.provider = (r) => hold ? reply.future : iptvPage([a]);
      try {
        await d.mount([a], paged: true);
        hold = true;
        final s = await d.guide();
        await d.f.finish(t, s.onChannelSelected([a, b], 1));
        await d.settle();
        expect(d.browse, isNotEmpty);
        expect(d.browse.last['anchorUrl'], b.url);
        expect(d.playingUrl, b.url);
        if (retire == 'switch') {
          await d.pick([a, b, c], 2);
        }
        if (retire == 'browse') {
          final current = await d.guide();
          current.onContextChanged!(
            IptvGuideContext(
              categories: ['User'],
              sourceId: 'user',
              sourceName: 'User',
              selectedCategory: 'User',
              contentType: 'live',
            ),
          );
          await d.closeGuide(current);
        }
        if (retire == 'dispose') {
          await d.retire();
        }
        reply.complete(
          iptvPage(
            retire == 'missing-playing' ? [a] : [b, iptvChannel(8)],
            category: 'Sports',
          ),
        );
        await d.settle();
        if (retire != 'dispose') {
          final current = await d.guide();
          expect(current.channels.any((ch) => ch.url.endsWith('/8.ts')), false);
          expect(d.playingUrl, retire == 'switch' ? c.url : b.url);
          if (retire == 'missing-playing') {
            expect(current.channels.map((c) => c.url), [a.url, b.url]);
            expect(current.currentIndex, 1);
          }
        }
        expect(d.errors, isEmpty);
      } finally {
        if (!reply.isCompleted) {
          reply.complete(null);
        }
        await d.close();
      }
    });
  }
  for (final invalid in [-1, 3]) {
    testWidgets(
      'P15 guide rejects index $invalid without adopting the incoming list',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final a = iptvChannel(0);
        try {
          await d.mount([a]);
          final s = await d.guide();
          await d.f.finish(t, s.onChannelSelected([iptvChannel(1)], invalid));
          expect(d.opened.length, 1);
          expect(d.playingUrl, a.url);
          expect(find.byType(IptvChannelSheet), findsOneWidget);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final available in [false, true]) {
    testWidgets(
      'P15 archived replay available=$available pins snackbar history and single item',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = iptvChannel(
          0,
          url: 'https://p15-replay-$available.test/live/u/p/123.ts',
          headers: {'X-Replay': 'yes'},
          attributes: {'source_playlist_id': 'origin'},
        );
        d.response = (r) => r.url.path.contains('/timeshift/')
            ? Response('', available ? 200 : 404)
            : Response('{}', 404);
        try {
          await d.mount([live]);
          final s = await d.guide();
          await d.f.finish(
            t,
            d.observe(() => s.onPlayProgramme!(live, iptvProgramme())),
          );
          await d.settle();
          if (!available) {
            expect(find.text('Replay is not available'), findsOneWidget);
            expect(d.opened.length, 1);
          } else {
            expect(d.playingUrl, contains('/timeshift/'));
            final replay = await d.guide();
            expect(replay.channels.length, 1);
            expect(replay.channels.single.contentType, 'vod');
            expect(replay.channels.single.name, 'P15 replay');
            expect(replay.channels.single.group, live.name);
            expect(
              replay.channels.single.attributes['source_playlist_id'],
              'origin',
            );
            final rows = await d.f.finish(
              t,
              IptvHistoryStorage.getIptvWatchHistory(),
            );
            expect(rows[d.playingUrl]!['playlistId'], 'origin');
            expect(rows[d.playingUrl]!['name'], 'P15 replay');
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 cancelled replay still writes history while rejecting the later native open',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-history-cancel.test/live/u/p/123.ts',
      );
      final held = CompletionDelivery('playIptvCatchup', (v) => v == null);
      d.response = iptvPanelReply;
      try {
        await d.mount([live]);
        final s = await d.guide();
        final pending = d.observe(
          () => held.run(() => s.onPlayProgramme!(live, iptvProgramme())),
        );
        await d.f.until(t, () => held.pending.isNotEmpty);
        expect(d.opened.length, 1);
        s.onClose();
        held.release();
        await d.f.finish(t, pending);
        final history = await d.f.finish(
          t,
          IptvHistoryStorage.getIptvWatchHistory(),
        );
        expect(history.length, 1);
        expect(history.keys.single, contains('/timeshift/'));
        expect(d.opened.length, 1);
        expect(d.playingUrl, live.url);
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await d.close();
      }
    },
  );
  for (final cancel in ['sheet-close', 'zap', 'dispose']) {
    testWidgets(
      'P15 catchup lookup held across $cancel cannot open or register history',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = iptvChannel(
          0,
          url: 'https://p15-cancel-$cancel.test/live/u/p/123.ts',
        );
        final next = iptvChannel(1);
        final reply = Completer<Response>();
        d.response = (r) => r.url.path.contains('/timeshift/')
            ? reply.future
            : Response('{}', 404);
        try {
          await d.mount([live, next]);
          final s = await d.guide();
          final pending = d.observe(
            () => s.onPlayProgramme!(live, iptvProgramme()),
          );
          await d.f.until(
            t,
            () => d.f.network.requests.any(
              (r) => r.url.path.contains('/timeshift/'),
            ),
          );
          if (cancel == 'dispose') {
            await d.retire();
          } else if (cancel == 'sheet-close') {
            await d.closeGuide(s);
          } else {
            await d.f.finish(t, s.onChannelSelected([live, next], 1));
          }
          final count = d.opened.length;
          reply.complete(Response('', 200));
          await d.f.finish(t, pending);
          expect(d.opened.length, count);
          final history = await d.f.finish(
            t,
            IptvHistoryStorage.getIptvWatchHistory(),
          );
          expect(history, isEmpty);
          expect(d.errors, isEmpty);
        } finally {
          if (!reply.isCompleted) {
            reply.complete(Response('', 404));
          }
          await d.close();
        }
      },
    );
  }
}

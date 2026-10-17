import 'dart:async';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';
import 'support/local_completion_driver.dart';

Future<void> feedbackSurvivesClose(
  IptvWorkflowDriver d,
  IptvChannelSheet sheet,
) async {
  final messenger = ScaffoldMessenger.of(
    d.t.element(find.byType(VideoPlayerScreen)),
  );
  messenger.clearSnackBars();
  await d.advance(const Duration(milliseconds: 300));
  messenger.showSnackBar(
    const SnackBar(
      content: Text('Independent feedback'),
      duration: Duration(seconds: 30),
    ),
  );
  await d.advance(const Duration(milliseconds: 300));
  expect(find.text('Independent feedback'), findsOneWidget);
  await d.closeGuide(sheet);
  await d.advance(const Duration(milliseconds: 300));
  expect(find.text('Independent feedback'), findsOneWidget);
}

void main() {
  for (final airing in [false, true]) {
    testWidgets(
      'P15 review2 unavailable programme retires its feedback gate airing=$airing',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = iptvChannel(
          0,
          url: 'https://p15-gate-unavailable-$airing.test/live/u/p/123.ts',
          attributes: {'tv_archive': '1'},
        );
        d.response = (r) => r.url.path.contains('timeshift')
            ? Response('', 404)
            : iptvPanelReply(r);
        try {
          await d.mount([live]);
          final sheet = await d.guide();
          await d.f.finish(
            t,
            d.observe(
              () => sheet.onPlayProgramme!(live, iptvProgramme(airing: airing)),
            ),
          );
          await d.f.until(
            t,
            () => find
                .text(
                  airing
                      ? 'Start over is not available'
                      : 'Replay is not available',
                )
                .evaluate()
                .isNotEmpty,
          );
          expect(playerControls(t).liveEdgeActionLoading, false);
          await feedbackSurvivesClose(d, sheet);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 review2 replay gate completes before switch recording stop returns',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-replay-switch-gate.test/live/u/p/123.ts',
      );
      d.response = iptvPanelReply;
      final stop = CompletionDelivery('switchToIptvChannel', (v) => v == null);
      Future<void>? work;
      try {
        await d.mount([live]);
        final sheet = await d.guide();
        work = stop.run(
          () => d.observe(() => sheet.onPlayProgramme!(live, iptvProgramme())),
        );
        await d.f.until(t, () => stop.pending.isNotEmpty);
        await feedbackSurvivesClose(d, sheet);
        stop.release();
        await d.f.finish(t, work!);
        expect(d.playingUrl, contains('/timeshift/'));
        expect(d.errors, isEmpty);
      } finally {
        stop.release();
        if (work != null) {
          await d.f.finish(t, work);
        }
        await d.close();
      }
    },
  );
  for (final recovering in [false, true]) {
    testWidgets(
      'P15 review2 native Start Over preserves live tuning and resets recovery recovering=$recovering',
      (t) async {
        final d = IptvWorkflowDriver(t, native: true);
        await d.initialize();
        final live = iptvChannel(
          0,
          url: 'https://p15-native-archive-$recovering.test/live/u/p/123.ts',
          attributes: {'tv_archive': '1'},
        );
        d.response = iptvPanelReply;
        final lines = <String>[];
        final oldPrint = debugPrint;
        final admission = IptvAwaitDelivery(
          'startIptvProgrammeFromBeginning',
          (v) => v == null,
        );
        Future<void>? start;
        debugPrint = (String? line, {int? wrapWidth}) {
          if (line != null) {
            lines.add(line);
          }
        };
        try {
          await d.mount([live]);
          if (recovering) {
            d.player.onOpen = () {};
            d.player.emit('error', 'first disconnect');
            await d.settle();
            await d.f.until(t, () => d.opened.length >= 2);
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 350)),
            );
          }
          final sheet = await d.guide();
          lines.clear();
          start = recovering
              ? admission.run(
                  () => d.observe(
                    () => sheet.onPlayProgramme!(
                      live,
                      iptvProgramme(airing: true),
                    ),
                  ),
                )
              : d.observe(
                  () =>
                      sheet.onPlayProgramme!(live, iptvProgramme(airing: true)),
                );
          if (recovering) {
            await d.f.until(t, () => admission.pending.isNotEmpty);
            d.player.emit('error', 'second disconnect');
            await d.settle();
            expect(find.text('Reconnecting…'), findsOneWidget);
            admission.release();
          }
          await d.f.finish(t, start!);
          expect(d.playingUrl, contains('/timeshift/'));
          final native = d.player.platform as FakeNativePlayer;
          expect(
            native.properties['stream-lavf-o'],
            'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_on_http_error=5xx,reconnect_delay_max=5',
          );
          expect(
            lines.where(
              (s) =>
                  s.contains('IptvDiag:') &&
                  s.contains('event=tune-start') &&
                  s.contains('live=true'),
            ),
            hasLength(1),
          );
          expect(playerControls(t).liveEdgeActionLoading, false);
          expect(playerControls(t).onToggleStartOverTimeline, isNotNull);
          if (!recovering) {
            playerControls(t).onToggleStartOverTimeline!();
            await d.settle();
            expect(playerControls(t).startOverTimelineVisible, true);
            d.player.emit('duration', Duration.zero);
            await d.settle();
            expect(playerControls(t).startOverTimelineVisible, false);
            d.player.emit('duration', const Duration(minutes: 20));
            await d.settle();
            expect(playerControls(t).startOverTimelineVisible, true);
            await d.f.finish(
              t,
              d.observe(
                () => sheet.onPlayProgramme!(live, iptvProgramme(airing: true)),
              ),
            );
            expect(playerControls(t).startOverTimelineVisible, false);
          } else {
            await d.advance(const Duration(seconds: 2));
            expect(d.playingUrl, contains('/timeshift/'));
          }
          await feedbackSurvivesClose(d, sheet);
          expect(d.errors, isEmpty);
        } finally {
          debugPrint = oldPrint;
          admission.release();
          if (start != null) {
            await d.f.finish(t, start);
          }
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 review2 a newer replay replaces pending preparation feedback',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-replay-feedback.test/live/u/p/123.ts',
      );
      final first = Completer<Response>();
      final second = Completer<Response>();
      var probes = 0;
      d.response = (r) {
        if (!r.url.path.contains('timeshift')) {
          return iptvPanelReply(r);
        }
        return switch (probes++) {
          0 => first.future,
          1 => second.future,
          _ => Response('', 404),
        };
      };
      Future<void>? old;
      Future<void>? next;
      try {
        await d.mount([live]);
        final sheet = await d.guide();
        old = d.observe(
          () =>
              sheet.onPlayProgramme!(live, iptvProgramme(title: 'Old replay')),
        );
        await d.f.until(t, () => probes == 1);
        await d.advance(const Duration(milliseconds: 300));
        expect(find.text('Preparing replay of "Old replay"…'), findsOneWidget);
        next = d.observe(
          () =>
              sheet.onPlayProgramme!(live, iptvProgramme(title: 'New replay')),
        );
        await d.f.until(t, () => probes == 2);
        await d.advance(const Duration(milliseconds: 600));
        expect(find.text('Preparing replay of "New replay"…'), findsOneWidget);
        expect(find.text('Preparing replay of "Old replay"…'), findsNothing);
        second.complete(Response('', 200));
        await d.f.finish(t, next!);
        first.complete(Response('', 404));
        await d.f.finish(t, old!);
        expect(d.errors, isEmpty);
      } finally {
        if (!first.isCompleted) {
          first.complete(Response('', 404));
        }
        if (!second.isCompleted) {
          second.complete(Response('', 404));
        }
        if (old != null) {
          await d.f.finish(t, old);
        }
        if (next != null) {
          await d.f.finish(t, next);
        }
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 pending replay advertises thirty-second preparation feedback',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(
        0,
        url: 'https://p15-replay-feedback-expiry.test/live/u/p/123.ts',
      );
      d.response = iptvPanelReply;
      final delivery = IptvAwaitDelivery(
        'playIptvCatchup',
        (v) => v is String && v.contains('/timeshift/'),
      );
      Future<void>? work;
      try {
        await d.mount([live]);
        final sheet = await d.guide();
        work = delivery.run(
          () => d.observe(() => sheet.onPlayProgramme!(live, iptvProgramme())),
        );
        await d.f.until(t, () => delivery.pending.isNotEmpty);
        await d.advance(const Duration(milliseconds: 300));
        expect(find.text('Preparing replay of "P15 replay"…'), findsOneWidget);
        expect(
          t.widget<SnackBar>(find.byType(SnackBar)).duration,
          const Duration(seconds: 30),
        );
        delivery.release();
        await d.f.finish(t, work!);
        expect(d.errors, isEmpty);
      } finally {
        delivery.release();
        if (work != null) {
          await d.f.finish(t, work);
        }
        await d.close();
      }
    },
  );
}

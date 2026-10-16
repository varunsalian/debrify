import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/startup_driver.dart';

void main() {
  for (final recover in [false, true]) {
    testWidgets(
      'P16 startup failure ${recover ? '250ms recovery' : '900ms close'} still pops after a same-route source winner',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final a = startupSource('failure-a');
        final b = startupSource('failure-b');
        var invoked = 0;
        d.openFailures[a.directUrl!] = StateError('source failed');
        try {
          await d.begin(
            d.screen(
              sources: [a, b],
              resolve: (s) async => s.directUrl,
              exhausted: recover
                  ? () async {
                      invoked++;
                    }
                  : null,
            ),
          );
          await d.f.until(t, () => d.event('exhausted').isNotEmpty);
          await d.tick();
          final text = recover
              ? 'Saved source failed. Looking for another source…'
              : 'No playable source could be started.';
          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.text(text),
            ),
            findsNWidgets(2),
          );
          final delay = Duration(milliseconds: recover ? 250 : 900);
          final failureTimer = d.timers
              .singleWhere(
                (r) =>
                    r.$1 == delay &&
                    (d.timerOrigins[r.$2]?.contains('reportStartupFailure') ??
                        false),
              )
              .$2;
          final sheet = await d.sheet(duration: Duration.zero);
          final selection = d.select(sheet, 1, b.directUrl!);
          await d.f.finish(t, selection.future);
          await d.committed();
          expect(d.commits, [b]);
          expect(d.player.state.playlist.medias.single.uri, b.directUrl);
          expect(d.routeReturned, isFalse);
          final remaining =
              delay -
              t.binding.clock.now().difference(d.timerCreated[failureTimer]!);
          expect(remaining, greaterThan(Duration.zero));
          await d.tick(remaining - const Duration(milliseconds: 1));
          expect(d.routeReturned, isFalse);
          await d.tick(const Duration(milliseconds: 1));
          await d.f.until(t, () => d.routeReturned);
          expect(
            d.routeResult,
            recover ? {'startupSourcesExhausted': true} : isNull,
          );
          expect(
            invoked,
            0,
            reason:
                'The original uses the callback as a recovery flag; it returns a route result instead of invoking it',
          );
          expect(d.opens, [a.directUrl, b.directUrl]);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P16 startup failure waits while a dialog covers its exact route and then returns recovery',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();
      final a = startupSource('cover');
      d.openFailures[a.directUrl!] = StateError('dead');
      Future<void>? dialog;
      try {
        await d.begin(d.screen(sources: [a], exhausted: () async {}));
        await d.f.until(t, () => d.event('exhausted').isNotEmpty);
        dialog = showDialog<void>(
          context: t.element(find.byType(VideoPlayerScreen)),
          builder: (_) =>
              const AlertDialog(content: Text('P16 covering dialog')),
        );
        await d.tick(const Duration(milliseconds: 400));
        expect(d.routeReturned, isFalse);
        expect(find.text('P16 covering dialog'), findsOneWidget);
        expect(
          d.timers.where(
            (r) =>
                r.$1 == const Duration(milliseconds: 50) &&
                (d.timerOrigins[r.$2]?.contains('reportStartupFailure') ??
                    false),
          ),
          isNotEmpty,
        );
        await d.tick(const Duration(milliseconds: 200));
        expect(d.routeReturned, isFalse);
        d.f.navigator.currentState!.pop();
        await d.f.finish(t, dialog);
        await d.tick(const Duration(milliseconds: 50));
        await d.f.until(t, () => d.routeReturned);
        expect(d.routeResult, {'startupSourcesExhausted': true});
      } finally {
        if (find.text('P16 covering dialog').evaluate().isNotEmpty) {
          d.f.navigator.currentState!.pop();
        }
        await d.close();
      }
    },
  );

  testWidgets(
    'P16 default failure abandons a replaced player route instead of popping its replacement',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();
      final a = startupSource('replace-route');
      d.openFailures[a.directUrl!] = StateError('dead');
      try {
        await d.begin(d.screen(sources: [a]));
        await d.f.until(t, () => d.event('exhausted').isNotEmpty);
        d.f.navigator.currentState!.pushReplacement<void, Object?>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('P16 replacement route')),
          ),
        );
        await d.tick(const Duration(seconds: 2));
        await d.settle();
        expect(find.text('P16 replacement route'), findsOneWidget);
        await d.f.until(t, () => d.player.disposed.isCompleted);
        expect(d.routeResult, isNull);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P16 watch-epoch failure abandons recovery after a same-route source change',
    (t) async {
      final d = StartupDriver(t, autoFrame: false);
      await d.initialize();
      final a = startupSource('tv-original', addon: 'AIOStreams');
      final b = startupSource('tv-winner');
      try {
        await d.begin(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'P16 TV failure',
            stremioTvChannels: const [
              {'id': 'slot', 'name': 'P16 TV', 'channelNumber': 7},
            ],
            stremioTvCurrentChannelId: 'slot',
            stremioSources: [a, b],
            resolveStremioSource: (s) async => s.directUrl,
            onStartupSourcesExhausted: () async {},
            onStremioSourceCommitted: (s) async => d.commits.add(s),
          ),
        );
        await d.openEntered();
        d.player.emit('error', 'fixture channel start failed');
        await d.tick();
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(
              'Saved source failed. Looking for another source…',
            ),
          ),
          findsNWidgets(2),
        );
        final sheet = await d.sheet(duration: Duration.zero);
        d.replies[b.directUrl!] = (p) {
          p.publishFrame();
          d.f.controllers.last.publishFrame();
        };
        final selected = d.select(sheet, 1, b.directUrl!);
        await d.f.finish(t, selected.future);
        await d.committed();
        await d.tick(const Duration(seconds: 2));
        expect(
          d.routeReturned,
          isFalse,
          reason:
              'Unlike the initial reporter, the watch passes its epoch predicate',
        );
        expect(d.player.state.playlist.medias.single.uri, b.directUrl);
        expect(find.byType(VideoPlayerScreen), findsOneWidget);
      } finally {
        await d.close();
      }
    },
  );
}

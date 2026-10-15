import 'dart:async';
import 'support/iptv_workflow_driver.dart';
import 'support/local_completion_driver.dart';

void main() {
  for (final signal in ['width', 'position', 'error', 'throw', 'timeout']) {
    testWidgets(
      'P15 candidate probe separates open acknowledgement from $signal events',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = await d.installAddon('probe-$signal');
        final ack = Completer<void>();
        var entered = false;
        try {
          await d.mount([iptvChannel(0), live]);
          d.probeMode();
          d.player.beforeOperation = (n, v) async {
            if (n == 'open' && !entered) {
              entered = true;
              await ack.future;
              if (signal == 'throw') {
                throw StateError('candidate rejected');
              }
            }
          };
          d.player.heldOperation = (n, v) => n == 'open' && !ack.isCompleted;
          final s = await d.guide();
          var done = false;
          final pending = d.observe(
            () => s
                .onChannelSelected([iptvChannel(0), live], 1)
                .then((_) => done = true),
          );
          await d.f.until(t, () => entered);
          // Neither a decoded frame nor an outgoing error can settle before ack.
          await d.probeEvent('width');
          await d.probeEvent('position');
          await d.probeEvent('error');
          expect(done, false);
          expect(StremioIptvService.instance.cachedWinner(live.url), isNull);
          ack.complete();
          await d.settle();
          if (signal != 'throw') {
            expect(done, false);
            expect(d.opened.length, 2);
          }
          if (signal == 'width' || signal == 'position') {
            await d.probeEvent(signal);
          } else {
            if (signal == 'error') {
              await d.probeEvent('error');
            }
            if (signal == 'timeout') {
              await d.advance(const Duration(seconds: 11));
              expect(d.opened.length, 2);
              expect(done, false);
              await d.advance(const Duration(seconds: 1));
            }
            await d.f.until(t, () => d.opened.length == 3);
            await d.settle();
            await d.probeEvent('width');
          }
          await d.f.finish(t, pending);
          expect(done, true);
          final chosen = signal == 'width' || signal == 'position'
              ? 'https://probe.test/first.ts'
              : 'https://probe.test/second.ts';
          expect(StremioIptvService.instance.cachedWinner(live.url), chosen);
          expect(d.playingUrl, chosen);
          expect(
            d.player.state.playlist.medias.single.httpHeaders,
            containsPair('X-P15', 'channel-header'),
          );
          // Late events after completion must not start another open.
          // The source sweep separately audits all three cancellation calls.
          final before = d.opened.length;
          await d.probeEvent('width');
          expect(d.opened.length, before);
          expect(d.errors, isEmpty);
        } finally {
          if (!ack.isCompleted) {
            ack.complete();
          }
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 candidate recording-stop await has no ticket and can issue a stale open',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('probe-stop');
      final newer = iptvChannel(9);
      final stop = CompletionDelivery('tryOpenLiveStream', (v) => v == null);
      try {
        await d.mount([iptvChannel(0), live, newer]);
        d.probeMode();
        final s = await d.guide();
        final pending = d.observe(
          () => stop.run(
            () => s.onChannelSelected([iptvChannel(0), live, newer], 1),
          ),
        );
        await d.f.until(t, () => stop.pending.isNotEmpty);
        expect(d.opened.length, 1);
        await d.f.finish(
          t,
          s.onChannelSelected([iptvChannel(0), live, newer], 2),
        );
        expect(d.playingUrl, newer.url);
        stop.release();
        await d.f.until(t, () => d.opened.length == 3);
        await d.settle();
        await d.probeEvent('width');
        await d.f.finish(t, pending);
        expect(d.playingUrl, 'https://probe.test/first.ts');
        expect(StremioIptvService.instance.cachedWinner(live.url), isNull);
        expect(d.errors, isEmpty);
      } finally {
        stop.release();
        await d.close();
      }
    },
  );
  for (final result in ['success', 'throw', 'timeout', 'superseded']) {
    testWidgets('P15 source pick $result pins winner and source highlight', (
      t,
    ) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('source-$result');
      final next = iptvChannel(9);
      try {
        await d.mount([live, next], initialUrl: 'https://probe.test/first.ts');
        final s = await d.sources();
        expect(s.sources.length, 2);
        expect(s.currentSourceIndex, 0);
        d.probeMode();
        if (result == 'throw') {
          d.player.failures['open'] = StateError('pick rejected');
        }
        d.observe(() => s.onSourceSelected(1, 'https://probe.test/second.ts'));
        await d.f.until(t, () => d.opened.length == 2);
        await d.settle();
        if (result == 'success') {
          await d.probeEvent('width');
        }
        if (result == 'timeout') {
          await d.advance(const Duration(seconds: 12));
        }
        if (result == 'superseded') {
          await d.pick([live, next], 1);
          await d.probeEvent('width');
        }
        await d.settle();
        expect(
          StremioIptvService.instance.cachedWinner(live.url),
          result == 'success' ? 'https://probe.test/second.ts' : isNull,
        );
        if (result != 'superseded') {
          final after = await d.sources();
          expect(after.currentSourceIndex, result == 'success' ? 1 : 0);
        } else {
          expect(playerControls(t).onShowStremioSources, isNull);
        }
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    });
  }
}

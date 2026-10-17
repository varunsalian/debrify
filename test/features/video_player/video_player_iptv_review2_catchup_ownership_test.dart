import 'dart:async';
import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final boundary in ['lookup', 'recording-stop', 'before-open']) {
    for (final retire in ['guide', 'zap']) {
      testWidgets(
        'P15 review2 Start Over $boundary independently rejects $retire ownership',
        (t) async {
          final d = IptvWorkflowDriver(t, native: true);
          await d.initialize();
          final channels = [
            for (var i = 0; i < 2; i++)
              iptvChannel(
                i,
                url:
                    'https://p15-owner-$boundary-$retire.test/live/u/p/${123 + i}.ts',
              ),
          ];
          d.response = iptvPanelReply;
          final lookup = IptvAwaitDelivery(
            'startIptvProgrammeFromBeginning',
            (v) => v is String,
          );
          final stop = IptvAwaitDelivery(
            'startIptvProgrammeFromBeginning',
            (v) => v == null,
          );
          final newerStop = IptvAwaitDelivery(
            'switchToIptvChannel',
            (v) => v == null,
          );
          final nativeGate = Completer<void>();
          var entered = false;
          var completed = false;
          Future<void>? work;
          try {
            await d.mount(channels);
            final sheet = await d.guide();
            final native = d.player.platform as FakeNativePlayer;
            if (boundary == 'before-open') {
              native.heldOperation = (name, value) =>
                  name == 'setProperty' &&
                  value is (String, String) &&
                  value.$1 == 'sub-visibility' &&
                  !entered;
              native.beforeOperation = (name, value) async {
                if (native.heldOperation!(name, value)) {
                  entered = true;
                  await nativeGate.future;
                }
              };
            }
            Future<void> play() => d.observe(
              () => sheet.onPlayProgramme!(
                channels.first,
                iptvProgramme(airing: true),
              ),
            );
            work =
                (boundary == 'lookup'
                        ? stop.run(() => lookup.run(play))
                        : boundary == 'recording-stop'
                        ? stop.run(play)
                        : play())
                    .then((_) => completed = true);
            await d.f.until(
              t,
              () => boundary == 'lookup'
                  ? lookup.pending.isNotEmpty
                  : boundary == 'recording-stop'
                  ? stop.pending.isNotEmpty
                  : entered,
            );
            final setup = native.calls
                .where(
                  (c) =>
                      c.$1 == 'setProperty' &&
                      c.$2 is (String, String) &&
                      (c.$2 as (String, String)).$1 == 'sub-visibility',
                )
                .length;
            if (retire == 'guide') {
              await d.closeGuide(sheet);
            } else {
              await newerStop.run(() => d.zap(1));
              await d.f.until(t, () => newerStop.pending.isNotEmpty);
              expect(d.playingUrl, channels.first.url);
            }
            lookup.release();
            if (boundary == 'lookup') {
              await d.settle();
              expect(
                completed,
                true,
                reason: 'Reject before entering another recording-stop await',
              );
            }
            stop.release();
            nativeGate.complete();
            await d.f.finish(t, work);
            expect(d.opened, hasLength(1));
            if (boundary == 'recording-stop') {
              expect(
                native.calls
                    .where(
                      (c) =>
                          c.$1 == 'setProperty' &&
                          c.$2 is (String, String) &&
                          (c.$2 as (String, String)).$1 == 'sub-visibility',
                    )
                    .length,
                setup,
              );
            }
            expect(playerControls(t).liveEdgeActionLoading, retire == 'zap');
            expect(d.errors, isEmpty);
          } finally {
            lookup.release();
            stop.release();
            if (!nativeGate.isCompleted) nativeGate.complete();
            newerStop.release();
            if (work != null) await d.f.finish(t, work);
            await d.settle();
            await d.close();
          }
        },
      );
    }
  }

  for (final kind in ['start-over', 'replay']) {
    testWidgets(
      'P15 review2 live recovery cancels pending $kind without stealing feedback',
      (t) async {
        final d = IptvWorkflowDriver(t, native: true);
        await d.initialize();
        final live = iptvChannel(
          0,
          url: 'https://p15-recovery-lookup-$kind.test/live/u/p/123.ts',
        );
        d.response = iptvPanelReply;
        final lookup = IptvAwaitDelivery(
          kind == 'start-over'
              ? 'startIptvProgrammeFromBeginning'
              : 'playIptvCatchup',
          (v) => v is String,
        );
        Future<void>? work;
        try {
          await d.mount([live]);
          final sheet = await d.guide();
          work = lookup.run(
            () => d.observe(
              () => sheet.onPlayProgramme!(
                live,
                iptvProgramme(airing: kind == 'start-over'),
              ),
            ),
          );
          await d.f.until(t, () => lookup.pending.isNotEmpty);
          d.probeMode();
          d.player.emit('error', 'network disconnected');
          await d.f.until(t, () => d.opened.length == 2);
          await d.advance(const Duration(milliseconds: 400));
          expect(d.playingUrl, live.url);
          expect(playerControls(t).liveEdgeActionLoading, false);
          if (kind == 'replay') {
            expect(find.textContaining('Preparing replay'), findsOneWidget);
          }
          lookup.release();
          await d.f.finish(t, work!);
          expect(d.opened, hasLength(2));
          expect(d.playingUrl, live.url);
          expect(d.errors, isEmpty);
        } finally {
          lookup.release();
          if (work != null) await d.f.finish(t, work);
          await d.probeEvent('width');
          await d.close();
        }
      },
    );
  }
  for (final retire in ['zap', 'dispose']) {
    testWidgets(
      'P15 review2 late recovery recording stop respects $retire ownership',
      (t) async {
        final d = IptvWorkflowDriver(t, native: true);
        await d.initialize();
        final live = iptvChannel(0);
        final next = iptvChannel(1);
        final stop = IptvAwaitDelivery(
          'performIptvLiveRetune',
          (v) => v == null,
        );
        try {
          await stop.run(() => d.mount([live, next]));
          d.observe(() => d.player.emit('error', 'network disconnected'));
          await d.f.until(t, () => stop.pending.isNotEmpty);
          if (retire == 'dispose') {
            await d.retire();
          } else {
            await d.zap(1);
            expect(d.playingUrl, next.url);
          }
          final issued = d.opened.length;
          stop.release();
          await d.settle();
          expect(d.opened, hasLength(issued));
          if (retire == 'dispose') {
            expect(
              d.timed.where(
                (v) => v.$1 == const Duration(seconds: 20) && v.$2.isActive,
              ),
              isEmpty,
              reason:
                  'An obsolete retune cannot re-arm a tune watchdog after disposal',
            );
          } else {
            expect(d.playingUrl, next.url);
          }
          expect(d.errors, isEmpty);
        } finally {
          stop.release();
          await d.advance(const Duration(seconds: 21));
          await d.close();
        }
      },
    );
  }
}

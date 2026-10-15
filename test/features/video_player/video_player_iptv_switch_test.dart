import 'dart:async';
import 'support/iptv_workflow_driver.dart';
import 'support/local_completion_driver.dart';

void main() {
  for (final boundary in [
    'recording-stop',
    'pause',
    'player-stop',
    'resolution',
    'pre-open',
    'issued-open',
    'probe',
  ]) {
    testWidgets('P15 overlapping switches pin stale outcome at $boundary', (
      t,
    ) async {
      final d = IptvWorkflowDriver(t, native: boundary == 'pre-open');
      await d.initialize();
      final a = iptvChannel(0);
      final b = iptvChannel(2);
      final stremio = ['player-stop', 'resolution', 'probe'].contains(boundary);
      final old = stremio
          ? await d.installAddon('stale-$boundary')
          : iptvChannel(1);
      final channels = [a, old, b];
      final gate = Completer<void>();
      final resolve = Completer<Response>();
      final stop = CompletionDelivery('switchToIptvChannel', (v) => v == null)
        ..armed = false;
      var entered = false;
      try {
        await d.mount(channels);
        final sheet = await d.guide();
        if (boundary == 'recording-stop') {
          stop.armed = true;
        }
        if (boundary == 'resolution') {
          d.response = (r) => r.url.path.contains('/stream/tv/')
              ? resolve.future
              : Response('{}', 404);
        }
        if (['pause', 'player-stop', 'issued-open'].contains(boundary)) {
          final operation = boundary == 'pause'
              ? 'pause'
              : boundary == 'player-stop'
              ? 'stop'
              : 'open';
          d.player.heldOperation = (n, v) => n == operation && !entered;
          d.player.beforeOperation = (n, v) async {
            if (n == operation && !entered) {
              entered = true;
              await gate.future;
            }
          };
        }
        if (boundary == 'pre-open') {
          final native = d.player.platform as FakeNativePlayer;
          native.heldOperation = (n, v) =>
              n == 'setProperty' &&
              (v as (String, String)).$1 == 'sub-visibility' &&
              !entered;
          native.beforeOperation = (n, v) async {
            if (n == 'setProperty' &&
                (v as (String, String)).$1 == 'sub-visibility' &&
                !entered) {
              entered = true;
              await gate.future;
            }
          };
        }
        if (boundary == 'probe') {
          d.probeMode();
        }
        final pending = d.observe(
          () => stop.run(() => sheet.onChannelSelected(channels, 1)),
        );
        if (boundary == 'recording-stop') {
          await d.f.until(t, () => stop.pending.isNotEmpty);
        } else if (boundary == 'resolution') {
          await d.f.until(
            t,
            () => d.f.network.requests.any(
              (r) => r.url.path.contains('/stream/tv/'),
            ),
          );
        } else if (boundary == 'probe') {
          await d.f.until(t, () => d.opened.length == 2);
        } else {
          await d.f.until(t, () => entered);
        }
        // Newer direct switch finishes while the older one remains held.
        await d.f.finish(
          t,
          d.observe(() => sheet.onChannelSelected(channels, 2)),
        );
        await d.settle();
        expect(d.playingUrl, b.url);
        final before = d.opened.length;
        stop.release();
        if (!gate.isCompleted) {
          gate.complete();
        }
        if (!resolve.isCompleted) {
          resolve.complete(
            Response(
              '{"streams":[{"url":"https://probe.test/stale.ts"}]}',
              200,
            ),
          );
        }
        if (boundary == 'probe') {
          await d.probeEvent('width');
        }
        await d.f.finish(t, pending);
        await d.settle();
        final opensLate = ['pause', 'issued-open'].contains(boundary);
        expect(d.playingUrl, opensLate ? old.url : b.url);
        expect(d.opened.length, before + (boundary == 'pause' ? 1 : 0));
        final after = await d.guide();
        expect(after.currentIndex, 2);
        expect(after.channels[after.currentIndex].name, b.name);
        if (stremio) {
          expect(StremioIptvService.instance.cachedWinner(old.url), isNull);
        }
        // Stale completion must not own a new transition cleanup timer.
        expect(
          d.timed
              .where(
                (v) =>
                    v.$1 == const Duration(milliseconds: 1500) &&
                    (d.timerOwners[v.$2]?.contains('switchToIptvChannel') ??
                        false),
              )
              .length,
          1,
        );
        expect(d.errors, isEmpty);
      } finally {
        stop.release();
        if (!gate.isCompleted) {
          gate.complete();
        }
        if (!resolve.isCompleted) {
          resolve.complete(Response('{}', 404));
        }
        await d.close();
      }
    });
  }
  testWidgets(
    'P15 same-turn repeated zap increments tickets before recording stop but shares the old index',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final a = [for (var i = 0; i < 4; i++) iptvChannel(i)];
      final stop = CompletionDelivery('switchToIptvChannel', (v) => v == null)
        ..multiple = true;
      try {
        await d.mount(a);
        final next = playerControls(t).onNext!;
        d.observe(
          () => stop.run(() {
            next();
            next();
            next();
          }),
        );
        await d.f.until(t, () => stop.pending.length == 3);
        expect(d.opened.length, 1);
        stop.release();
        await d.settle();
        expect(d.opened.length, 2);
        expect(d.playingUrl, a[1].url);
        expect(d.errors, isEmpty);
      } finally {
        stop.release();
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 disposal during acknowledged candidate probe still marks a winner without a mounted check',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('disposed-winner');
      try {
        await d.mount([iptvChannel(0), live]);
        d.probeMode();
        final s = await d.guide();
        final pending = d.observe(
          () => s.onChannelSelected([iptvChannel(0), live], 1),
        );
        await d.f.until(t, () => d.opened.length == 2);
        await d.settle();
        await d.retire();
        await d.probeEvent('width');
        await d.f.finish(t, pending);
        expect(
          StremioIptvService.instance.cachedWinner(live.url),
          'https://probe.test/first.ts',
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 direct switch order is pause then channel-header open and 1500ms transition cleanup',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final a = [
        iptvChannel(0),
        iptvChannel(1, headers: {'X-Own': 'yes'}),
      ];
      try {
        await d.mount(a);
        final before = d.player.calls.length;
        await d.zap(1);
        final calls = d.player.calls.skip(before).map((c) => c.$1).toList();
        expect(calls, containsAllInOrder(['pause', 'open']));
        expect(calls.indexOf('pause'), lessThan(calls.indexOf('open')));
        expect(d.playingUrl, a[1].url);
        expect(
          d.player.state.playlist.medias.single.httpHeaders,
          containsPair('X-Own', 'yes'),
        );
        final timer = d.timed
            .lastWhere((v) => v.$1 == const Duration(milliseconds: 1500))
            .$2;
        expect(timer.isActive, true);
        await d.timerAge(timer, const Duration(milliseconds: 1499));
        expect(timer.isActive, true);
        await d.advance(const Duration(milliseconds: 1));
        expect(timer.isActive, false);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}

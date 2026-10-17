import 'dart:async';
import 'support/iptv_workflow_driver.dart';

void main() {
  for (final mode in [
    'failed-after-dispose',
    'second-after-dispose',
    'second-mounted',
    'all-failed',
  ]) {
    testWidgets('P15 review2 candidate ladder lifetime $mode', (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('ladder-$mode');
      final failures = <Object>[];
      Future<void>? tune;
      try {
        final channels = [iptvChannel(0), live];
        await d.mount(channels);
        d.probeMode();
        final guide = await d.guide();
        tune = d.observe(
          () => guide
              .onChannelSelected(channels, 1)
              .then<void>(
                (_) {},
                onError: (Object e) {
                  failures.add(e);
                },
              ),
        );
        await d.f.until(t, () => d.opened.length == 2);
        await d.settle();
        if (mode != 'failed-after-dispose') {
          await d.probeEvent('error');
          await d.f.until(t, () => d.opened.length == 3);
          await d.settle();
        }
        if (mode.contains('dispose')) await d.retire();
        final before = d.timed.length;
        await d.probeEvent(
          mode == 'failed-after-dispose' || mode == 'all-failed'
              ? 'error'
              : 'width',
        );
        if (mode == 'failed-after-dispose') {
          expect(
            d.timed
                .skip(before)
                .where((v) => v.$1 == const Duration(seconds: 12)),
            isEmpty,
            reason: 'A failed disposed ladder cannot start another probe',
          );
        }
        await d.f.finish(t, tune!);
        expect(
          failures,
          isEmpty,
          reason: 'A late winner must not publish State after disposal',
        );
        if (mode == 'second-mounted') {
          final sources = await d.sources();
          expect(sources.currentSourceIndex, 1);
        }
        if (mode == 'second-after-dispose') {
          // The original still records this late winner; preserve that gap.
          expect(
            StremioIptvService.instance.cachedWinner(live.url),
            'https://probe.test/second.ts',
          );
        }
        if (mode == 'all-failed') {
          final beforeRequests = d.f.network.requests
              .where((r) => r.url.path.contains('/stream/tv/'))
              .length;
          await d.f.finish(
            t,
            StremioIptvService.instance.resolveCandidates(live.url),
          );
          expect(
            d.f.network.requests.where(
              (r) => r.url.path.contains('/stream/tv/'),
            ),
            hasLength(beforeRequests + 1),
          );
        }
        expect(d.errors, isEmpty);
      } finally {
        await d.probeEvent('width');
        if (tune != null) await d.f.finish(t, tune);
        await d.close();
      }
    });
  }

  testWidgets(
    'P15 review2 a plain switch pause completed after disposal cannot clear source State',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('disposed-source-clear');
      final failures = <Object>[];
      try {
        final channels = [live, iptvChannel(1)];
        await d.mount(channels, initialUrl: 'https://probe.test/first.ts');
        final guide = await d.guide();
        final before = d.calls('pause').length;
        final gate = d.holdOperation('pause');
        final tune = d.observe(
          () => guide
              .onChannelSelected(channels, 1)
              .then<void>(
                (_) {},
                onError: (Object e) {
                  failures.add(e);
                },
              ),
        );
        await d.f.until(t, () => d.calls('pause').length > before);
        expect(playerControls(t).onShowStremioSources, isNotNull);
        await d.retire();
        gate.complete();
        await d.f.finish(t, tune);
        await d.settle();
        expect(failures, isEmpty);
        expect(d.opened, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 a disposed empty resolve retains its cached empty result',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('disposed-empty');
      final reply = Completer<Response>();
      final failures = <Object>[];
      d.response = (r) => r.url.path.contains('/stream/tv/')
          ? reply.future
          : Response('{}', 404);
      try {
        final channels = [iptvChannel(0), live];
        await d.mount(channels);
        final guide = await d.guide();
        final tune = d.observe(
          () => guide
              .onChannelSelected(channels, 1)
              .then<void>(
                (_) {},
                onError: (Object e) {
                  failures.add(e);
                },
              ),
        );
        await d.f.until(
          t,
          () => d.f.network.requests.any(
            (r) => r.url.path.contains('/stream/tv/'),
          ),
        );
        await d.retire();
        reply.complete(Response('{"streams":[]}', 200));
        await d.f.finish(t, tune);
        final requests = d.f.network.requests.length;
        expect(
          await d.f.finish(
            t,
            StremioIptvService.instance.resolveCandidates(live.url),
          ),
          isEmpty,
        );
        expect(d.f.network.requests, hasLength(requests));
        expect(failures, isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        if (!reply.isCompleted) reply.complete(Response('{}', 404));
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 an explicit tune retries cached-empty addon candidates',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('refresh-empty');
      final healthy = d.response!;
      try {
        d.response = (r) => Response('{"streams":[]}', 200);
        expect(
          await d.f.finish(
            t,
            StremioIptvService.instance.resolveCandidates(live.url),
          ),
          isEmpty,
        );
        d.response = healthy;
        await d.mount([iptvChannel(0), live]);
        d.probeMode();
        await d.zap(1);
        await d.f.until(t, () => d.opened.length == 2);
        await d.probeEvent('width');
        expect(
          d.f.network.requests.where((r) => r.url.path.contains('/stream/tv/')),
          hasLength(2),
        );
        expect(d.playingUrl, 'https://probe.test/first.ts');
        expect(d.errors, isEmpty);
      } finally {
        await d.probeEvent('width');
        await d.close();
      }
    },
  );
}

import 'dart:async';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 manual source error is unmuted and a quiet recovery ladder can replace the pick',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('manual-error');
      try {
        await d.mount([live], initialUrl: 'https://probe.test/first.ts');
        final sources = await d.sources();
        d.probeMode();
        sources.onSourceSelected(1, 'https://probe.test/second.ts');
        await d.f.until(t, () => d.opened.length == 2);
        await d.settle();
        await d.probeEvent('error');
        await d.f.until(t, () => d.opened.length == 3);
        expect(d.opened.last, 'https://probe.test/first.ts');
        await d.settle();
        await d.probeEvent('width');
        expect(
          StremioIptvService.instance.cachedWinner(live.url),
          'https://probe.test/first.ts',
        );
        expect(d.playingUrl, 'https://probe.test/first.ts');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  for (final initial in [
    'https://probe.test/second.ts',
    'https://probe.test/missing.ts',
  ]) {
    testWidgets(
      'P15 initial source rows locate or clamp the launch URL $initial',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = await d.installAddon(
          initial.endsWith('missing.ts') ? 'initial-missing' : 'initial-second',
        );
        try {
          await d.mount([live, iptvChannel(9)], initialUrl: initial);
          final s = await d.sources();
          expect(
            d.timed
                .where((v) => v.$1 == const Duration(milliseconds: 4500))
                .every((v) => !v.$2.isActive),
            true,
          );
          expect(s.sources.length, 2);
          expect(s.currentSourceIndex, initial.endsWith('second.ts') ? 1 : 0);
          expect(
            await d.f.finish(t, s.resolveSource(s.sources[1])),
            'https://probe.test/second.ts',
          );
          s.onClose();
          await d.pick([live, iptvChannel(9)], 1);
          expect(playerControls(t).onShowStremioSources, isNull);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 initial candidate resolution cannot repopulate source rows after zapping away',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('init-late');
      final reply = Completer<Response>();
      final other = iptvChannel(9);
      d.response = (r) => r.url.path.contains('/stream/tv/')
          ? reply.future
          : Response('{}', 404);
      try {
        await d.mount([live, other], initialUrl: 'https://probe.test/first.ts');
        await d.f.until(
          t,
          () => d.f.network.requests.any(
            (r) => r.url.path.contains('/stream/tv/'),
          ),
        );
        await d.pick([live, other], 1);
        reply.complete(
          Response('{"streams":[{"url":"https://probe.test/late.ts"}]}', 200),
        );
        await d.settle();
        expect(d.playingUrl, other.url);
        expect(playerControls(t).onShowStremioSources, isNull);
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
    'P15 a public mutable channel list can leave stream feedback using the fallback name',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [iptvChannel(0, live: false)];
      try {
        await d.mount(channels);
        channels.clear();
        d.player.emit('error', 'no current row');
        await d.settle();
        expect(
          find.text("This channel didn't play — no current row"),
          findsOneWidget,
        );
        expect(d.opened.length, 1);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}

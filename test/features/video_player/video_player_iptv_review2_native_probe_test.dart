import 'support/iptv_workflow_driver.dart';

const reconnectPolicy =
    'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_on_http_error=5xx,reconnect_delay_max=5';

void main() {
  testWidgets(
    'P15 review2 native live policy follows candidate source and direct zap',
    (t) async {
      final d = IptvWorkflowDriver(t, native: true);
      await d.initialize();
      final live = await d.installAddon('native-policy');
      final direct = iptvChannel(0);
      var finished = false;
      try {
        await d.mount([direct, live]);
        final native = d.player.platform as FakeNativePlayer;
        void expectLiveSetup() => expect(
          native.calls.where(
            (c) =>
                c.$1 == 'setProperty' &&
                c.$2 == ('stream-lavf-o', reconnectPolicy),
          ),
          hasLength(1),
        );
        d.probeMode();
        native.calls.clear();
        await d.zap(1);
        await d.f.until(t, () => d.opened.length == 2);
        await d.probeEvent('width');
        await d.settle();
        expect(d.playingUrl, 'https://probe.test/first.ts');
        expectLiveSetup();
        final sources = await d.sources();
        native.calls.clear();
        d.observe(
          () => sources.onSourceSelected(1, 'https://probe.test/second.ts'),
        );
        await d.f.until(t, () => d.opened.length == 3);
        await d.settle();
        await d.probeEvent('width');
        await d.settle();
        expect(d.playingUrl, 'https://probe.test/second.ts');
        expectLiveSetup();
        sources.onClose();
        await d.settle();
        native.calls.clear();
        await d.zap(-1);
        expect(d.playingUrl, direct.url);
        expectLiveSetup();
        expect(d.errors, isEmpty);
        finished = true;
      } finally {
        if (!finished) await d.probeEvent('width');
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 acknowledged live probe advances the ladder at exactly twelve seconds',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('exact-timeout');
      var finished = false;
      try {
        await d.mount([iptvChannel(0), live]);
        d.probeMode();
        final sheet = await d.guide();
        final work = d.observe(
          () => sheet.onChannelSelected([iptvChannel(0), live], 1),
        );
        await d.f.until(t, () => d.opened.length == 2);
        await d.settle();
        final timers = d.timed
            .where(
              (v) => d.timerOwners[v.$2]?.contains('tryOpenLiveStream') == true,
            )
            .toList();
        expect(timers, hasLength(1));
        final probe = timers.single.$2;
        await d.timerAge(probe, const Duration(milliseconds: 11999));
        expect(d.opened, hasLength(2));
        await d.timerAge(probe, const Duration(seconds: 12));
        // Poll asynchronous I/O without allowing an extra fake second to make
        // a thirteen-second mutant look like an on-time twelve-second retry.
        for (var i = 0; i < 100 && d.opened.length < 3; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await t.pump();
        }
        expect(d.opened, hasLength(3));
        await d.probeEvent('width');
        await d.f.finish(t, work);
        expect(d.playingUrl, 'https://probe.test/second.ts');
        expect(d.errors, isEmpty);
        finished = true;
      } finally {
        if (!finished) await d.probeEvent('width');
        await d.close();
      }
    },
  );
}

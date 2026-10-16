import 'support/iptv_workflow_driver.dart';

void main() {
  for (final index in [-1, 3]) {
    testWidgets(
      'P15 review2 an invalid guide dispatch returns without throwing index=$index',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        try {
          await d.mount([iptvChannel(0), iptvChannel(1)]);
          final guide = await d.guide();
          Object? rejected;
          await d.f.finish(
            t,
            d.observe(() async {
              try {
                await guide.onChannelSelected([iptvChannel(7)], index);
              } catch (error) {
                rejected = error;
              }
            }),
          );
          expect(rejected, isNull);
          expect(d.playingUrl, 'https://p15.test/0.ts');
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P15 review2 a rendered live zap rejects a now singleton borrowed window',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final rows = [iptvChannel(0), iptvChannel(1)];
      try {
        await d.mount(rows);
        final press = playerControls(t).onNext;
        expect(press, isNotNull);
        rows.removeLast();
        final before = d.opened.length;
        d.observe(press!);
        await d.settle();
        expect(d.opened, hasLength(before));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 a backgrounded live player rejects a later recovery error',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => true, ios: () => false));
      try {
        await d.mount([iptvChannel(0)]);
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          d.observe(() => t.binding.handleAppLifecycleStateChanged(state));
          await d.settle();
        }
        expect(d.player.state.playing, false);
        final before = d.opened.length;
        d.player.emit('error', 'background disconnect');
        await d.settle();
        expect(d.opened, hasLength(before));
        // The paused binding does not paint new snackbars. The operation
        // count above observes recovery admission at the delivery boundary.
        expect(d.errors, isEmpty);
      } finally {
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          t.binding.handleAppLifecycleStateChanged(state);
        }
        await d.settle();
        await d.close();
        VpS2Hooks.install(null);
      }
    },
  );
}

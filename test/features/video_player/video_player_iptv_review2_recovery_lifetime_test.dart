import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 a messenger retry after route replacement cannot resurrect recovery',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('retained-recovery');
      try {
        await d.mount([live], initialUrl: 'https://probe.test/first.ts');
        d.probeMode();
        d.player.emit('error', 'network disconnected');
        await d.f.until(t, () => d.opened.length == 2);
        await d.probeEvent('width');
        // Recovery uses DateTime.now, independently of the test timer clock.
        // No position event confirms a stable recovery while real time passes.
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 75100)),
        );
        d.player.emit('error', 'network still disconnected');
        await d.settle();
        await d.advance(const Duration(milliseconds: 300));
        expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
        d.observe(
          () => d.f.navigator.currentState!.pushReplacement<void, void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Browser route')),
            ),
          ),
        );
        await d.advance(const Duration(milliseconds: 400));
        await d.advance(const Duration(milliseconds: 400));
        await d.f.until(
          t,
          () => d.f.players.every((p) => p.disposed.isCompleted),
        );
        d.disposed = true;
        expect(find.byType(VideoPlayerScreen), findsNothing);
        // ScaffoldMessenger belongs above the Navigator, so the actual Retry
        // button survives the outgoing player route and can still be pressed.
        expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
        final before = d.timed.length;
        await d.observe(
          () => t.tap(find.widgetWithText(SnackBarAction, 'Retry')),
        );
        await d.settle();
        expect(
          d.timed
              .skip(before)
              .where(
                (v) =>
                    v.$1 == const Duration(seconds: 20) &&
                    d.timerOwners[v.$2]!.contains('IptvLiveRecovery'),
              ),
          isEmpty,
        );
        expect(d.opened, hasLength(2));
        expect(d.errors, isEmpty);
      } finally {
        // A failed candidate must not leave its newly armed dead-owner timer
        // behind after the resource assertion has already observed it.
        for (final item in d.timed) {
          if (item.$1 == const Duration(seconds: 20)) item.$2.cancel();
        }
        await d.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

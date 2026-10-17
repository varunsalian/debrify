import 'support/iptv_workflow_driver.dart';
import 'dart:async';

/// The initializer uses an unawaited then callback, whose inferred return type
/// is Null. Hold that delivered service list without replacing the result or
/// calling the private initializer directly.
class InitialSourceDelivery {
  bool armed = true;
  final pending = <void Function()>[];
  Result run<Result>(Result Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      registerUnaryCallback:
          <R, T>(self, parent, zone, R Function(T) callback) {
            final selected =
                StackTrace.current
                    .toString()
                    .split('\n')
                    .where((s) => s.contains('package:debrify/'))
                    .firstOrNull
                    ?.contains('initIptvStremioSources') ??
                false;
            return parent.registerUnaryCallback(zone, (T value) {
              if (armed && selected && value is List<StremioIptvCandidate>) {
                armed = false;
                pending.add(() => zone.runUnary(callback, value));
                return null as R;
              }
              return callback(value);
            });
          },
    ),
  );
  void release() {
    armed = false;
    final callbacks = List<void Function()>.of(pending);
    pending.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}

void main() {
  for (final index in <int?>[null, 1, -1, 2]) {
    testWidgets(
      'P15 review2 source initialization respects launch index $index',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final live = await d.installAddon('startup-index-$index');
        final channels = index == 1
            ? [iptvChannel(0), live]
            : [live, iptvChannel(0)];
        final failures = <FlutterErrorDetails>[];
        final handler = FlutterError.onError;
        try {
          // Capture construction errors before waiting for a controller: a bad
          // bounds guard must fail this assertion, not a later fixture timeout.
          FlutterError.onError = failures.add;
          try {
            await d.observe(
              () => t.pumpWidget(
                MaterialApp(
                  navigatorKey: d.f.navigator,
                  theme: ThemeData.dark(),
                  home: VideoPlayerScreen(
                    videoUrl: 'https://probe.test/first.ts',
                    title: 'Launch row',
                    iptvChannels: channels,
                    iptvStartIndex: index,
                  ),
                ),
              ),
            );
          } finally {
            FlutterError.onError = handler;
          }
          expect(
            failures,
            isEmpty,
            reason: 'Invalid launch rows are safely ignored',
          );
          await d.f.until(t, () => d.f.controllers.isNotEmpty);
          d.player.deliverReady();
          await d.f.until(t, () => d.opened.isNotEmpty);
          await d.f.until(
            t,
            () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
          );
          await d.settle();
          expect(
            playerControls(t).onShowStremioSources != null,
            index == null || index == 1,
          );
          if (index == null || index == 1) {
            final sources = await d.sources();
            expect(sources.sources, hasLength(2));
            expect(sources.currentSourceIndex, 0);
          }
          expect(d.errors, isEmpty);
        } finally {
          FlutterError.onError = handler;
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P15 review2 empty explicit zap candidates retire the old source browser',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('empty-explicit', urls: const []);
      try {
        await d.mount([iptvChannel(0), live]);
        await d.zap(1);
        await d.settle();
        expect(
          d.errors,
          isEmpty,
          reason: 'An empty candidate list never enters row-index clamping',
        );
        expect(playerControls(t).onShowStremioSources, isNull);
        expect(d.calls('stop'), isNotEmpty);
        expect(d.opened, hasLength(1));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 late initial sources cannot replace a same-channel manual selection',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('initial-vs-manual');
      final delivery = InitialSourceDelivery();
      try {
        await delivery.run(
          () => d.mount([live], initialUrl: 'https://probe.test/first.ts'),
        );
        await d.f.until(t, () => delivery.pending.isNotEmpty);
        final guide = await d.guide();
        d.probeMode();
        final tune = d.observe(() => guide.onChannelSelected([live], 0));
        await d.f.until(t, () => d.opened.length == 2);
        await d.probeEvent('width');
        await d.f.finish(t, tune);
        final sources = await d.sources();
        sources.onSourceSelected(1, 'https://probe.test/second.ts');
        await d.f.until(t, () => d.opened.length == 3);
        await d.probeEvent('width');
        delivery.release();
        await d.settle();
        expect(d.playingUrl, 'https://probe.test/second.ts');
        final selected = await d.sources();
        expect(selected.currentSourceIndex, 1);
        expect(d.errors, isEmpty);
      } finally {
        delivery.release();
        await d.close();
      }
    },
  );
}

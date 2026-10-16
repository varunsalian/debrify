import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:flutter/services.dart';
// Existing resolved preference transport.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/display_defaults_reads.dart';
import 'support/iptv_workflow_driver.dart';
import 'support/iptv_storage_driver.dart';

void main() {
  testWidgets(
    'P15 review2 an early source sheet blocks initial floating feedback',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = await d.installAddon('early-source-overlay');
      final previous = SharedPreferencesStorePlatform.instance;
      final reads = (await t.runAsync(DisplayDefaultsReads.install))!;
      try {
        t.view.physicalSize = const Size(1280, 800);
        t.view.devicePixelRatio = 1;
        await d.observe(
          () => t.pumpWidget(
            MaterialApp(
              navigatorKey: d.f.navigator,
              theme: ThemeData.dark(),
              home: d.screen([live], initialUrl: 'https://probe.test/first.ts'),
            ),
          ),
        );
        await d.f.until(t, () => reads.entered);
        await d.f.until(
          t,
          () => d.f.network.requests.any(
            (r) => r.url.path.contains('/stream/tv/'),
          ),
        );
        await d.settle();
        await d.observe(() => d.f.key(t, LogicalKeyboardKey.keyS));
        expect(find.byType(SourceSheet), findsOneWidget);
        expect(d.f.players, isEmpty);
        reads.unblock();
        await d.f.until(t, () => d.f.controllers.isNotEmpty);
        d.player.deliverReady();
        await d.f.until(t, () => d.opened.isNotEmpty);
        await d.f.until(
          t,
          () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
        );
        await d.settle();
        expect(d.banners.where((v) => !v.flush), isEmpty);
        expect(
          d.timed.where((v) => v.$1 == const Duration(milliseconds: 4500)),
          isEmpty,
        );
        expect(d.errors, isEmpty);
      } finally {
        reads.unblock();
        await d.close();
        SharedPreferencesStorePlatform.instance = previous;
      }
    },
  );

  testWidgets(
    'P15 review2 a directory opened during recording stop keeps the later zap banner blocked',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final channels = [iptvChannel(0), iptvChannel(1)];
      final stop = IptvAwaitDelivery('switchToIptvChannel', (v) => v == null);
      final previousError = FlutterError.onError;
      final overflows = <FlutterErrorDetails>[];
      // Original ChannelGuide rows exceed their item extent by one pixel at
      // default test font metrics. Pin that existing error here; every other
      // framework error still goes to the normal test binding.
      FlutterError.onError = (details) {
        if (details.library == 'rendering library' &&
            details.exceptionAsString() ==
                'A RenderFlex overflowed by 1.00 pixels on the bottom.') {
          overflows.add(details);
        } else {
          previousError?.call(details);
        }
      };
      try {
        await d.observe(
          () => d.f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: channels.first.url,
              title: channels.first.name,
              iptvChannels: channels,
              iptvStartIndex: 0,
              channelDirectory: [
                {'id': 'c', 'name': 'Composite', 'channelNumber': 1},
              ],
              requestChannelById: (_) async => null,
            ),
          ),
        );
        await d.f.until(
          t,
          () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
        );
        await stop.run(() => d.zap(1));
        await d.f.until(t, () => stop.pending.isNotEmpty);
        await d.f.key(t, LogicalKeyboardKey.keyG);
        expect(find.byType(ChannelGuide), findsOneWidget);
        stop.release();
        await d.f.until(t, () => d.opened.length == 2);
        await d.settle();
        expect(find.byType(ChannelGuide), findsOneWidget);
        // Opening the directory starts the outgoing banner's 180 ms fade.
        // A retained fading subtree is legal; a newly raised banner is not.
        for (final banner in d.banners.where((v) => !v.flush)) {
          final opacity = t.widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.byWidget(banner),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          );
          expect(opacity.opacity, 0);
        }
        expect(
          d.timed.where(
            (v) => v.$1 == const Duration(milliseconds: 4500) && v.$2.isActive,
          ),
          isEmpty,
        );
        expect(d.errors, isEmpty);
        expect(
          overflows,
          hasLength(1),
          reason:
              'Preserve the original directory-row overflow; no blanket error filtering',
        );
      } finally {
        FlutterError.onError = previousError;
        stop.release();
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 opening the dock during banner fade removes the floating subtree immediately',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.mount([iptvChannel(0)]);
        final hides = d.timed
            .where((v) => v.$1 == const Duration(milliseconds: 4500))
            .toList();
        expect(hides, isNotEmpty);
        await d.timerAge(hides.last.$2, const Duration(milliseconds: 4500));
        final floats = d.banners.where((v) => !v.flush).toList();
        expect(floats, isNotEmpty);
        final fade = t.widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.byWidget(floats.first),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        );
        expect(fade.opacity, 0);
        await d.f.key(t, LogicalKeyboardKey.arrowDown);
        expect(d.banners.where((v) => v.flush), isNotEmpty);
        expect(d.banners.where((v) => !v.flush), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P15 review2 a repeated raise cancels the outgoing floating deadline',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      try {
        await d.mount([iptvChannel(0), iptvChannel(1)]);
        await d.zap(1);
        final hides = d.timed
            .where((v) => v.$1 == const Duration(milliseconds: 4500))
            .toList();
        expect(hides, hasLength(2));
        expect(hides.first.$2.isActive, false);
        expect(hides.last.$2.isActive, true);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}

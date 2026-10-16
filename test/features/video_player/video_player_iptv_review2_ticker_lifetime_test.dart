import 'package:flutter/services.dart';
// Existing resolved preference transport.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/display_defaults_reads.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 banner clock stops offscreen and rearms on the dock',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      int active() => d.periodic
          .where((v) => v.$1 == const Duration(seconds: 1) && v.$2.isActive)
          .length;
      try {
        await d.mount([iptvChannel(0)]);
        expect(active(), 1);
        await d.advance(const Duration(milliseconds: 4500));
        expect(active(), 0);
        await d.observe(() => t.tapAt(const Offset(600, 300)));
        await d.advance(const Duration(milliseconds: 400));
        expect(active(), 1);
        final guide = await d.guide();
        expect(active(), 0);
        await d.closeGuide(guide);
        await d.observe(() => t.tapAt(const Offset(600, 300)));
        await d.advance(const Duration(milliseconds: 400));
        expect(active(), 1);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 review2 opening an early guide allocates no identity clock',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final previous = SharedPreferencesStorePlatform.instance;
      final reads = (await t.runAsync(DisplayDefaultsReads.install))!;
      try {
        await d.observe(
          () => t.pumpWidget(
            MaterialApp(
              navigatorKey: d.f.navigator,
              theme: ThemeData.dark(),
              home: d.screen([iptvChannel(0)]),
            ),
          ),
        );
        await d.f.until(t, () => reads.entered);
        expect(d.f.players, isEmpty);
        await d.observe(() => d.f.key(t, LogicalKeyboardKey.keyG));
        expect(find.byType(IptvChannelSheet), findsOneWidget);
        expect(
          d.periodic.where((v) => v.$1 == const Duration(seconds: 1)),
          isEmpty,
        );
        reads.unblock();
        await d.f.until(t, () => d.f.controllers.isNotEmpty);
        d.player.deliverReady();
        await d.f.until(t, () => d.opened.isNotEmpty);
        await d.f.until(
          t,
          () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
        );
        await d.settle();
        expect(d.errors, isEmpty);
      } finally {
        reads.unblock();
        await d.close();
        SharedPreferencesStorePlatform.instance = previous;
      }
    },
  );
}

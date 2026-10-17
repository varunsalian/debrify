import 'package:flutter/services.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
// Existing resolved preference transport.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/iptv_workflow_driver.dart';
import 'support/display_defaults_reads.dart';

void main() {
  for (final action in ['idle', 'guide', 'zap']) {
    testWidgets(
      'P15 early $action window before player construction preserves initializer semantics',
      (t) async {
        final d = IptvWorkflowDriver(t);
        await d.initialize();
        final previous = SharedPreferencesStorePlatform.instance;
        final reads = (await t.runAsync(DisplayDefaultsReads.install))!;
        final a = [iptvChannel(0), iptvChannel(1)];
        d.provider = (r) => iptvPage(a);
        try {
          await d.observe(
            () => t.pumpWidget(
              MaterialApp(
                navigatorKey: d.f.navigator,
                theme: ThemeData.dark(),
                home: d.screen(a, paged: true),
              ),
            ),
          );
          await d.f.until(t, () => reads.entered);
          expect(d.f.players, isEmpty);
          expect(find.byType(Controls), findsNothing);
          expect(d.browse, isEmpty);
          if (action == 'guide') {
            await d.f.key(t, LogicalKeyboardKey.keyG);
            expect(find.byType(IptvChannelSheet), findsOneWidget);
            final sheet = t.widget<IptvChannelSheet>(
              find.byType(IptvChannelSheet),
            );
            expect(sheet.currentIndex, 0);
            sheet.onClose();
          }
          if (action == 'zap') {
            await d.f.key(t, LogicalKeyboardKey.channelUp);
            expect(d.f.players, isEmpty);
            expect(d.browse.length, 1);
          }
          reads.unblock();
          await d.f.until(t, () => d.f.controllers.isNotEmpty);
          d.player.deliverReady();
          await d.f.until(t, () => d.opened.isNotEmpty);
          await d.f.until(
            t,
            () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
          );
          await d.settle();
          expect(d.opened.length, 1);
          expect(d.opened.single, a[0].url);
          expect(d.errors, isEmpty);
        } finally {
          reads.unblock();
          await d.close();
          SharedPreferencesStorePlatform.instance = previous;
        }
      },
    );
  }
}

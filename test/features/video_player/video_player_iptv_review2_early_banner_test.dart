import 'package:flutter/services.dart';
// Existing resolved preference transport.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/display_defaults_reads.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 an early dock cannot start a ticker before banner identity',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final previous = SharedPreferencesStorePlatform.instance;
      final reads = (await t.runAsync(DisplayDefaultsReads.install))!;
      final live = iptvChannel(0);
      try {
        await d.observe(
          () => t.pumpWidget(
            MaterialApp(
              navigatorKey: d.f.navigator,
              theme: ThemeData.dark(),
              home: d.screen([live]),
            ),
          ),
        );
        await d.f.until(t, () => reads.entered);
        expect(d.f.players, isEmpty);
        await d.f.key(t, LogicalKeyboardKey.keyG);
        final sheet = t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
        sheet.onClose();
        await d.settle();
        await d.observe(() => t.tapAt(const Offset(600, 300)));
        await d.settle();
        expect(
          d.periodic.where(
            (v) => v.$1 == const Duration(seconds: 1) && v.$2.isActive,
          ),
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

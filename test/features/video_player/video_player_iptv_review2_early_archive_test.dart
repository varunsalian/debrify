import 'package:flutter/services.dart';
// Existing resolved preference transport.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/display_defaults_reads.dart';
import 'support/iptv_workflow_driver.dart';

void main() {
  testWidgets(
    'P15 review2 presentation does not rearm a ring installed by an early guide pick',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final previous = SharedPreferencesStorePlatform.instance;
      final reads = (await t.runAsync(DisplayDefaultsReads.install))!;
      final live = iptvChannel(0);
      d.provider = (r) => iptvPage([live, iptvChannel(1)]);
      try {
        await d.observe(
          () => t.pumpWidget(
            MaterialApp(
              navigatorKey: d.f.navigator,
              theme: ThemeData.dark(),
              home: d.screen([live], paged: true),
            ),
          ),
        );
        await d.f.until(t, () => reads.entered);
        await d.observe(() => d.f.key(t, LogicalKeyboardKey.keyG));
        final sheet = t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
        await d.f.finish(
          t,
          d.observe(() => sheet.onChannelSelected([live], 0)),
        );
        await d.f.until(t, () => d.browse.length == 1);
        await d.settle();
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
        expect(d.browse, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        reads.unblock();
        await d.close();
        SharedPreferencesStorePlatform.instance = previous;
      }
    },
  );
  testWidgets(
    'P15 review2 a pre-player archive open failure retires its current lookup',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final previous = SharedPreferencesStorePlatform.instance;
      final reads = (await t.runAsync(DisplayDefaultsReads.install))!;
      final live = iptvChannel(
        0,
        url: 'https://p15-before-player-archive.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      d.response = iptvPanelReply;
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
        await d.observe(() => d.f.key(t, LogicalKeyboardKey.keyG));
        final sheet = t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
        await d.f.finish(
          t,
          d.observe(
            () => sheet.onPlayProgramme!(live, iptvProgramme(airing: true)),
          ),
        );
        // The original accepts the lookup before player construction, catches
        // that pre-open failure and performs the quiet fallback's UI cleanup.
        expect(find.byType(IptvChannelSheet), findsNothing);
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
        expect(playerControls(t).liveEdgeActionActive, false);
        expect(playerControls(t).liveEdgeActionLoading, false);
        expect(d.errors, isEmpty);
      } finally {
        reads.unblock();
        await d.close();
        SharedPreferencesStorePlatform.instance = previous;
      }
    },
  );
}

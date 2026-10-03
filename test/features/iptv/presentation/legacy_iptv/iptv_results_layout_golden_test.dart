import 'dart:io';

import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_live_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/iptv_results_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final layouts = [
    (name: 'classic', style: 'command', size: const Size(640, 480)),
    (name: 'tv_two_pane', style: 'command', size: const Size(1280, 720)),
    (name: 'cockpit', style: 'edition', size: const Size(1280, 720)),
    (name: 'spotlight', style: 'spotlight', size: const Size(1280, 720)),
  ];
  for (final layout in layouts) {
    testWidgets(
      'SQL ${layout.name} layout preserves original preview paint',
      (tester) => iptvResultsCase(tester, (view) async {
        await view.mount(tester, size: layout.size);
        // Finish only initial layout animations. No two-second maintenance,
        // provider EPG, programme actions or native playback is in this fixture.
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        expect(find.text('Channel 1'), findsWidgets);
        expect(
          find.byType(HeroTrailerBackdrop),
          findsNothing,
          reason: 'Preview is disabled for a strict Flutter paint reference',
        );
        if (layout.name == 'spotlight') {
          final timeline = tester.widget<SpotlightLiveTimeline>(
            find.byType(SpotlightLiveTimeline),
          );
          expect(timeline.now(), IptvResultsFixture.clock);
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('iptv-characterization-canvas')),
          matchesGoldenFile(
            '../../../../goldens/iptv_results/'
            '${Platform.isLinux ? 'linux' : 'macos'}/${layout.name}.png',
          ),
        );
      }, style: layout.style),
    );
  }
}

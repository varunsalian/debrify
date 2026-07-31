import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/iptv_zap_banner.dart';
import 'package:debrify/services/iptv_epg_service.dart';

void main() {
  final now = DateTime(2026, 7, 31, 20, 24);

  Widget host(Widget banner, Size size) => MediaQuery(
    data: MediaQueryData(size: size),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Positioned(left: 0, right: 0, bottom: 0, child: banner),
        ],
      ),
    ),
  );

  IptvChannel channel({String? name, int? number, String? group}) => IptvChannel(
    channelNumber: number,
    name: name ?? 'Sky Sports Main Event',
    url: 'http://example.com/live/1.ts',
    group: group ?? 'Sports',
    duration: -1,
  );

  final epg = EpgNowNext(
    now: EpgProgramme(
      title: 'Premier League: Arsenal v Liverpool',
      description: '',
      start: DateTime(2026, 7, 31, 20, 0),
      stop: DateTime(2026, 7, 31, 22, 0),
    ),
    next: EpgProgramme(
      title: 'Match of the Day',
      description: '',
      start: DateTime(2026, 7, 31, 22, 0),
      stop: DateTime(2026, 7, 31, 23, 0),
    ),
  );

  for (final size in const [
    Size(400, 800), // phone portrait
    Size(800, 400), // phone landscape
    Size(1280, 720), // tablet / TV
  ]) {
    testWidgets('renders at $size with full guide data', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          IptvZapBanner(
            channel: channel(number: 7),
            epg: epg,
            epgLoading: false,
            now: now,
          ),
          size,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Sky Sports Main Event'), findsOneWidget);
      expect(find.text('Premier League: Arsenal v Liverpool'), findsOneWidget);

      // The name must get real room, not whatever the programme column left
      // over — that squeeze is what the narrow layout exists to prevent.
      // Pre-fix, the wide layout gave the name whatever the programme column
      // left over — about a quarter of a phone's width.
      final nameWidth = tester.getSize(find.text('Sky Sports Main Event')).width;
      expect(nameWidth, greaterThan(size.width * 0.35));
    });

    testWidgets('renders at $size with a very long name and no guide', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          IptvZapBanner(
            channel: channel(
              name: 'UK | SKY SPORTS MAIN EVENT ULTRA HD BACKUP FEED 03',
              number: 1042,
              group: 'UNITED KINGDOM — SPORTS PREMIUM',
            ),
            epg: null,
            epgLoading: true,
            now: now,
          ),
          size,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Loading guide…'), findsOneWidget);
    });
  }

  // Embedded in the controls dock, the panel shares the screen with the top
  // bar and the transport bar. On a short landscape phone all three have to
  // fit, so the panel has to stay a modest slice of the viewport.
  for (final size in const [
    Size(568, 320), // smallest plausible phone landscape
    Size(800, 400),
    Size(1280, 720),
  ]) {
    testWidgets('flush panel stays compact at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          IptvZapBanner(
            channel: channel(number: 7),
            epg: epg,
            epgLoading: false,
            now: now,
            flush: true,
          ),
          size,
        ),
      );
      expect(tester.takeException(), isNull);
      final height = tester.getSize(find.byType(IptvZapBanner)).height;
      expect(
        height,
        lessThan(size.height * 0.45),
        reason: 'panel + top bar + transport bar must fit on $size',
      );
    });
  }

  testWidgets('unnumbered channel omits the number slot', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        IptvZapBanner(
          channel: channel(),
          epg: null,
          epgLoading: false,
          now: now,
        ),
        const Size(800, 400),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('No guide data'), findsOneWidget);
  });
}

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_programme_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selected timeline programme drives the hero headline', (
    tester,
  ) async {
    final channel = IptvChannel(
      name: 'News One',
      url: 'https://example.com/live.ts',
      duration: -1,
      contentType: 'live',
    );
    final start = DateTime.now().add(const Duration(minutes: 45));
    final programme = EpgProgramme(
      title: 'Evening Report',
      description: 'The latest headlines.',
      start: start,
      stop: start.add(const Duration(hours: 1)),
    );

    Widget host(EpgProgramme? selected) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 300,
          child: SpotlightProgrammeHero(
            channel: channel,
            selectedProgramme: selected,
            previewSlot: const ColoredBox(color: Colors.black),
            actionsBuilder: (_, _, _) => const Text('Action'),
          ),
        ),
      ),
    );

    await tester.pumpWidget(host(programme));
    expect(find.text('Evening Report'), findsOneWidget);
    expect(find.textContaining('Starts in'), findsOneWidget);
    expect(find.text('The latest headlines.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(host(null));
    expect(find.text('News One'), findsOneWidget);
    expect(find.text('Evening Report'), findsNothing);
  });

  testWidgets('programme actions rebuild when a future show becomes live', (
    tester,
  ) async {
    final channel = IptvChannel(
      name: 'News One',
      url: 'https://example.com/live.ts',
      duration: -1,
      contentType: 'live',
    );
    final start = DateTime.now().add(const Duration(milliseconds: 500));
    final programme = EpgProgramme(
      title: 'Starting shortly',
      description: '',
      start: start,
      stop: start.add(const Duration(hours: 1)),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 300,
            child: SpotlightProgrammeHero(
              channel: channel,
              selectedProgramme: programme,
              previewSlot: const ColoredBox(color: Colors.black),
              actionsBuilder: (_, selected, _) => Text(
                selected!.airsAt(DateTime.now()) ? 'Watch now' : 'Record',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Record'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 550)),
    );
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Watch now'), findsOneWidget);
  });
}

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_category_control.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_content_type_control.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_hero_chrome.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_programme_hero.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_shell.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _labelSlot(String label, {double? height}) => SizedBox(
  height: height,
  child: Center(child: Text(label)),
);

Future<void> _pumpShell(
  WidgetTester tester, {
  required Size size,
  required IptvSpotlightLayoutMode mode,
  required VoidCallback onOpenSources,
  Widget? rail,
  Widget? hero,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  const t = IptvStyleTokens.spotlight;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: t.bg,
        body: SpotlightShell(
          mode: mode,
          searchSlot: _labelSlot('Parent search', height: 52),
          railSlot: rail ?? _labelSlot('Persistent rail'),
          categorySlot: SpotlightCategoryControl(
            categoryLabel: 'All channels',
            channelCount: 26,
            onPressed: () {},
          ),
          contentTypeSlot: SpotlightContentTypeControl(
            value: SpotlightContentTypeControl.live,
            onChanged: (_) {},
          ),
          heroSlot:
              hero ??
              SpotlightHeroChrome(
                previewSlot: const ColoredBox(
                  key: ValueKey<String>('native-preview-probe'),
                  color: Colors.black,
                ),
                identitySlot: const Text('177 · CBBC HD'),
                titleSlot: const Text('This is CBBC'),
                metadataSlot: const Text('18:58–02:58 · LIVE'),
                descriptionSlot: const Text('A mix of great shows.'),
                actionsSlot: const Text('Watch  Favorite  More info'),
              ),
          contentSlot: _labelSlot('Independent content'),
          compactSourceLabel: 'My provider',
          compactSourceCount: 26,
          onOpenSources: onOpenSources,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'wide shell mounts one search, persistent rail, hero and content',
    (tester) async {
      await _pumpShell(
        tester,
        size: const Size(896, 540),
        mode: IptvSpotlightLayoutMode.wide,
        onOpenSources: () {},
      );

      expect(
        find.byKey(const ValueKey<String>('spotlight-shell-wide')),
        findsOneWidget,
      );
      expect(find.text('Parent search'), findsOneWidget);
      expect(find.text('Persistent rail'), findsOneWidget);
      expect(find.text('CATEGORY'), findsOneWidget);
      expect(find.text('All channels · 26'), findsOneWidget);
      expect(find.text('Live TV'), findsOneWidget);
      expect(find.text('Movies'), findsOneWidget);
      expect(find.text('Series'), findsOneWidget);
      expect(find.text('Debrify'), findsOneWidget);
      expect(find.text('A mix of great shows.'), findsOneWidget);
      expect(find.text('Independent content'), findsOneWidget);
      final preview = find.byKey(
        const ValueKey<String>('native-preview-probe'),
      );
      expect(preview, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('spotlight-source-trigger')),
        findsNothing,
      );

      final previewSize = tester.getSize(preview);
      final hero = find.byKey(const ValueKey<String>('spotlight-hero'));
      expect(previewSize.width / previewSize.height, closeTo(16 / 9, 0.001));
      expect(previewSize.height, closeTo(tester.getSize(hero).height, 0.01));
      expect(
        tester.getTopRight(preview).dx,
        closeTo(tester.getTopRight(hero).dx, 0.01),
      );

      expect(
        tester.getTopLeft(find.text('Persistent rail')).dx,
        lessThan(tester.getTopLeft(find.text('Independent content')).dx),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact shell replaces rail with focusable source-sheet trigger',
    (tester) async {
      var opened = 0;
      await _pumpShell(
        tester,
        size: const Size(760, 480),
        mode: IptvSpotlightLayoutMode.compact,
        onOpenSources: () => opened++,
      );

      expect(
        find.byKey(const ValueKey<String>('spotlight-shell-compact')),
        findsOneWidget,
      );
      expect(find.text('Persistent rail'), findsNothing);
      expect(find.text('Parent search'), findsOneWidget);
      expect(find.text('My provider · 26'), findsOneWidget);
      expect(find.text('All channels · 26'), findsOneWidget);
      expect(find.text('Debrify'), findsNothing);
      expect(find.text('Live TV'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('native-preview-probe')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('spotlight-source-trigger')),
      );
      await tester.pump();

      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hero inserts the caller preview exactly once without paint wrappers',
    (tester) async {
      await _pumpShell(
        tester,
        size: const Size(1000, 620),
        mode: IptvSpotlightLayoutMode.wide,
        onOpenSources: () {},
      );

      final preview = find.byKey(
        const ValueKey<String>('native-preview-probe'),
      );
      expect(preview, findsOneWidget);
      expect(
        find.ancestor(of: preview, matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(
        find.ancestor(of: preview, matching: find.byType(ClipRect)),
        findsNothing,
      );
      expect(
        find.ancestor(of: preview, matching: find.byType(ClipRRect)),
        findsNothing,
      );
      expect(
        find.ancestor(of: preview, matching: find.byType(DecoratedBox)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hero loosely centers a width-limited 16:9 preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const previewKey = ValueKey<String>('loose-preview-probe');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: SpotlightHeroChrome(
            previewSlot: ColoredBox(key: previewKey, color: Colors.black),
            identitySlot: Text('177 · CBBC HD'),
            titleSlot: Text('This is CBBC'),
            metadataSlot: Text('18:58–02:58 · LIVE'),
            descriptionSlot: Text('A mix of great shows.'),
            actionsSlot: Text('Watch  Favorite  More info'),
          ),
        ),
      ),
    );

    final preview = find.byKey(previewKey);
    final hero = find.byKey(const ValueKey<String>('spotlight-hero'));
    final previewSize = tester.getSize(preview);
    final heroSize = tester.getSize(hero);
    expect(previewSize.width / previewSize.height, closeTo(16 / 9, 0.001));
    expect(previewSize.height, lessThan(heroSize.height));
    expect(
      tester.getCenter(preview).dy,
      closeTo(tester.getCenter(hero).dy, 0.01),
    );
    expect(
      tester.getTopRight(preview).dx,
      closeTo(tester.getTopRight(hero).dx, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact boundary fits a populated programme hero', (
    tester,
  ) async {
    final now = DateTime.now();
    final channel = IptvChannel(
      name: 'News One',
      url: 'https://example.com/live.ts',
      duration: -1,
      contentType: 'live',
    );
    final programme = EpgProgramme(
      title: 'Evening Report',
      description: 'The latest headlines from around the world.',
      start: now.subtract(const Duration(minutes: 10)),
      stop: now.add(const Duration(minutes: 50)),
    );

    await _pumpShell(
      tester,
      size: const Size(760, 480),
      mode: IptvSpotlightLayoutMode.compact,
      onOpenSources: () {},
      hero: SpotlightProgrammeHero(
        channel: channel,
        selectedProgramme: programme,
        previewSlot: const ColoredBox(color: Colors.black),
        actionsBuilder: (_, _, _) => const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(Icons.play_arrow_rounded), Icon(Icons.more_horiz)],
        ),
      ),
    );

    expect(find.text('Evening Report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standard TV hero compacts a maximal action set', (tester) async {
    final now = DateTime.now();
    final channel = IptvChannel(
      name: 'News One',
      url: 'https://example.com/live.ts',
      duration: -1,
      contentType: 'live',
    );
    final programme = EpgProgramme(
      title: 'Evening Report',
      description: 'The latest headlines from around the world.',
      start: now.subtract(const Duration(minutes: 10)),
      stop: now.add(const Duration(minutes: 50)),
    );
    bool? denseActions;

    await _pumpShell(
      tester,
      size: const Size(896, 540),
      mode: IptvSpotlightLayoutMode.wide,
      onOpenSources: () {},
      hero: SpotlightProgrammeHero(
        channel: channel,
        selectedProgramme: programme,
        previewSlot: const ColoredBox(color: Colors.black),
        actionsBuilder: (_, _, dense) {
          denseActions = dense;
          if (dense) {
            return const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded),
                Icon(Icons.more_horiz_rounded),
              ],
            );
          }
          return Wrap(
            children: [
              FilledButton(onPressed: () {}, child: const Text('Watch')),
              OutlinedButton(onPressed: () {}, child: const Text('Record')),
              IconButton(onPressed: () {}, icon: const Icon(Icons.favorite)),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          );
        },
      ),
    );

    expect(denseActions, isTrue);
    expect(
      find.text('The latest headlines from around the world.'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/screens/settings/parents_guide_style_page.dart';
import 'package:debrify/services/imdb_parents_guide_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/parents_guide_section.dart';

const _guide = ParentsGuideResult(
  categories: [
    ParentsGuideCategory(
      id: 'violence',
      label: 'Violence & Gore',
      severity: 'Moderate',
      severityVotes: 12,
      totalVotes: 20,
      items: [
        ParentsGuideItem(text: 'Several tense confrontations are shown.'),
        ParentsGuideItem(text: 'A hidden plot detail.', isSpoiler: true),
      ],
    ),
    ParentsGuideCategory(
      id: 'profanity',
      label: 'Profanity',
      severity: 'Mild',
      severityVotes: 8,
      totalVotes: 20,
      items: [ParentsGuideItem(text: 'Occasional strong language is used.')],
    ),
    ParentsGuideCategory(
      id: 'substances',
      label: 'Alcohol, Drugs & Smoking',
      severity: 'Severe',
      severityVotes: 18,
      totalVotes: 20,
      items: [ParentsGuideItem(text: 'Drug use is central to the story.')],
    ),
    ParentsGuideCategory(
      id: 'nudity',
      label: 'Sex & Nudity',
      severity: 'None',
      severityVotes: 20,
      totalVotes: 20,
      items: [],
    ),
    ParentsGuideCategory(
      id: 'frightening',
      label: 'Frightening & Intense Scenes',
      severity: 'Moderate',
      severityVotes: 11,
      totalVotes: 20,
      items: [ParentsGuideItem(text: 'Some scenes sustain a tense mood.')],
    ),
  ],
);

void main() {
  group('parents guide style preference', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      StorageService.parentsGuideStyleCached = 'compass';
    });

    test('Compass is the default and invalid values normalize to it', () async {
      expect(await StorageService.getParentsGuideStyle(), 'compass');
      await StorageService.setParentsGuideStyle('unknown');
      expect(await StorageService.getParentsGuideStyle(), 'compass');
      expect(parentsGuideStyleLabel('unknown'), 'Compass');
    });

    test('Classic round-trips and updates the synchronous cache', () async {
      await StorageService.setParentsGuideStyle('classic');
      expect(StorageService.parentsGuideStyleCached, 'classic');
      expect(await StorageService.getParentsGuideStyle(), 'classic');
      expect(parentsGuideStyleLabel('classic'), 'Classic');
    });
  });

  group('Compass Parents Guide', () {
    setUp(() => StorageService.parentsGuideStyleCached = 'compass');

    for (final size in const [
      Size(390, 844),
      Size(834, 1112),
      Size(960, 540),
    ]) {
      testWidgets('fits ${size.width}×${size.height}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ParentsGuideSection(
                  guide: _guide,
                  tv: size.width == 960,
                  theme: DetailThemes.signal,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('AT A GLANCE'), findsOneWidget);
        expect(find.text('A hidden plot detail.'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('selecting a category updates its guidance', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: ParentsGuideSection(guide: _guide),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Profanity'));
      await tester.pumpAndSettle();
      expect(find.text('Occasional strong language is used.'), findsOneWidget);
    });

    testWidgets('theme typography reaches display, body, and data text', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ParentsGuideSection(
              guide: _guide,
              theme: DetailThemes.broadsheet,
            ),
          ),
        ),
      );

      expect(
        tester
            .widget<Text>(find.text('Know before you watch.'))
            .style!
            .fontFamily,
        DetailFontRole.serif.family,
      );
      expect(
        tester.widget<Text>(find.text('AT A GLANCE')).style!.fontFamily,
        DetailFontRole.mono.family,
      );
      expect(
        tester.widget<Text>(find.text('Select a category')).style!.fontFamily,
        DetailFontRole.serif.family,
      );
    });

    testWidgets('resolved title accent overrides the theme fallback', (
      tester,
    ) async {
      const resolvedAccent = Color(0xFF31D17C);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ParentsGuideSection(
              guide: _guide,
              theme: DetailThemes.signal,
              accent: resolvedAccent,
            ),
          ),
        ),
      );

      expect(
        tester.widget<Text>(find.text('PARENTS GUIDE')).style!.color,
        resolvedAccent,
      );
      expect(
        tester.widget<Text>(find.text('AT A GLANCE')).style!.color,
        resolvedAccent,
      );
    });

    testWidgets('None severity has a zero-length meter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ParentsGuideSection(guide: _guide)),
        ),
      );
      final tile = find.ancestor(
        of: find.text('Sex & Nudity'),
        matching: find.byType(AnimatedContainer),
      );
      final meter = find.descendant(
        of: tile,
        matching: find.byType(FractionallySizedBox),
      );
      expect(tester.widget<FractionallySizedBox>(meter).widthFactor, 0);
    });

    testWidgets('TV Down moves through a wrapped grid before its scroll host', (
      tester,
    ) async {
      var parentDownEvents = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Focus(
              canRequestFocus: false,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  parentDownEvents++;
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: const SizedBox(
                width: 420,
                child: ParentsGuideSection(guide: _guide, tv: true),
              ),
            ),
          ),
        ),
      );
      final firstContext = tester.element(find.text('Violence & Gore'));
      Focus.of(firstContext).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(parentDownEvents, 0);
      expect(find.text('Drug use is central to the story.'), findsOneWidget);
    });

    testWidgets('read-only Compass exposes the dashboard without controls', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 232,
                child: ParentsGuideSection(
                  guide: _guide,
                  interactive: false,
                  dense: true,
                  theme: DetailThemes.signal,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('AT A GLANCE'), findsOneWidget);
      expect(find.text('Select a category'), findsNothing);
      expect(
        find.text('Several tense confrontations are shown.'),
        findsOneWidget,
      );
      expect(find.text('Occasional strong language is used.'), findsOneWidget);
      expect(find.text('Drug use is central to the story.'), findsOneWidget);
      expect(find.text('Some scenes sustain a tense mood.'), findsOneWidget);
      expect(find.text('A hidden plot detail.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Classic remains available', (tester) async {
      StorageService.parentsGuideStyleCached = 'classic';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ParentsGuideSection(guide: _guide)),
        ),
      );
      expect(find.text('PARENTS GUIDE'), findsOneWidget);
      expect(find.text('AT A GLANCE'), findsNothing);
    });
  });
}

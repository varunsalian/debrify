import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_explore_service.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/widgets/metadata_explore_spotlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    ProfileRuntime.debugReset();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfileRuntime.debugReset);
  const data = MetadataExploreData(
    people: [
      {'id': 1, 'name': 'Actor One', 'character': 'Character'},
      {'id': 2, 'name': 'Actor Two'},
      {'id': 3, 'name': 'Director', 'job': 'Director'},
    ],
    companies: [
      {'id': 4, 'name': 'Studio'},
    ],
    providers: {
      'flatrate': [
        {'provider_name': 'Subscription service'},
      ],
      'rent': [
        {'provider_name': 'Rental service'},
      ],
    },
  );
  Widget page({
    MetadataPreferences? preferences,
    MetadataExploreData? content,
    void Function(String, Map<String, dynamic>)? onEntity,
  }) => MaterialApp(
    home: MetadataExploreSpotlight(
      item: const StremioMeta(id: 'tmdb:1', type: 'movie', name: 'A Movie'),
      preferences: preferences ?? MetadataPreferences(),
      data: content ?? data,
      loading: false,
      failed: false,
      isTelevision: true,
      onRetry: () {},
      onEntity: onEntity ?? (_, _) {},
      onDiscover: () {},
      titleBuilder: (item, focusNode) => Text(item.name),
    ),
  );
  testWidgets('cast opens by tap and keyboard; View all opens a grid', (
    tester,
  ) async {
    final opened = <int>[];
    await tester.pumpWidget(
      page(onEntity: (_, row) => opened.add(row['id'] as int)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Actor One'));
    await tester.tap(find.text('Actor One'));
    expect(opened, [1]);
    Focus.of(tester.element(find.text('Actor Two'))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(opened, [1, 2]);
    await tester.ensureVisible(find.text('View all →'));
    await tester.tap(find.text('View all →'));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    final actor = find.descendant(
      of: find.byType(Dialog),
      matching: find.text('Actor One'),
    );
    await tester.tap(actor);
    await tester.pumpAndSettle();
    expect(opened, [1, 2, 1]);
    expect(find.byType(Dialog), findsNothing);
  });
  testWidgets(
    'availability tabs switch providers without affecting studio navigation',
    (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        page(onEntity: (kind, row) => opened.add('$kind:${row['id']}')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Rent'));
      await tester.pumpAndSettle();
      expect(find.text('Subscription service'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Rent'));
      await tester.pumpAndSettle();
      expect(find.text('Rental service'), findsOneWidget);
      expect(find.text('Subscription service'), findsNothing);
      await tester.ensureVisible(find.text('Studio'));
      await tester.tap(find.text('Studio'));
      expect(opened, ['company:4']);
    },
  );
  testWidgets('disabled features do not expose cached sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(preferences: MetadataPreferences(features: {})),
    );
    await tester.pumpAndSettle();
    expect(find.text('Actor One'), findsNothing);
    expect(find.text('Studio'), findsNothing);
    expect(find.text('Where to watch'), findsNothing);
    expect(find.text('Discover movies and shows'), findsNothing);
  });
  testWidgets('narrow layout scrolls through stacked panels without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Rent'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Rent'));
    await tester.pumpAndSettle();
    expect(find.text('Rental service'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final change in ['profile', 'policy', 'disposal']) {
    testWidgets('cast dialog rejects stale navigation on $change', (
      tester,
    ) async {
      final opened = <int>[];
      await tester.pumpWidget(
        page(onEntity: (_, row) => opened.add(row['id'] as int)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View all →'));
      await tester.tap(find.text('View all →'));
      await tester.pumpAndSettle();
      final actor = find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Actor One'),
      );
      final gesture = find
          .ancestor(of: actor, matching: find.byType(GestureDetector))
          .first;
      final staleTap = tester.widget<GestureDetector>(gesture).onTap!;
      if (change == 'profile') {
        ProfileRuntime.scope.value = ProfileScope(
          profileId: 'other',
          dataGeneration: 1,
          sessionEpoch: 1,
        );
      } else if (change == 'policy') {
        MetadataPreferencesService.revision.value++;
      } else {
        // Retain the Navigator and its independently pushed dialog.
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      }
      staleTap();
      expect(opened, isEmpty);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'numpad Enter activates cast, director, studio and dialog people',
    (tester) async {
      final opened = <int>[];
      await tester.pumpWidget(
        page(onEntity: (_, row) => opened.add(row['id'] as int)),
      );
      await tester.pumpAndSettle();
      for (final name in ['Actor One', 'Director', 'Studio']) {
        final label = find.text(name).first;
        await tester.ensureVisible(label);
        Focus.of(tester.element(label)).requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      }
      expect(opened, [1, 3, 4]);
      await tester.ensureVisible(find.text('View all →'));
      await tester.tap(find.text('View all →'));
      await tester.pumpAndSettle();
      final actor = find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Actor Two'),
      );
      Focus.of(tester.element(actor)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();
      expect(opened, [1, 3, 4, 2]);
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets('cast shortcut restores a scrolled rail before focusing', (
    tester,
  ) async {
    final opened = <int>[];
    await tester.pumpWidget(
      page(
        content: MetadataExploreData(
          people: List.generate(30, (i) => {'id': i + 1, 'name': 'Actor $i'}),
        ),
        preferences: MetadataPreferences(features: {MetadataFeature.people}),
        onEntity: (_, row) => opened.add(row['id'] as int),
      ),
    );
    await tester.pumpAndSettle();
    final rail = tester.widget<ListView>(find.byType(ListView));
    rail.controller!.jumpTo(rail.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Actor 0'), findsNothing);
    final shortcut = find.widgetWithText(OutlinedButton, 'Cast & crew');
    await tester.ensureVisible(shortcut);
    await tester.tap(shortcut);
    await tester.pumpAndSettle();
    expect(rail.controller!.offset, 0);
    expect(find.text('Actor 0'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pumpAndSettle();
    expect(opened, [1]);
    expect(tester.takeException(), isNull);
  });
}

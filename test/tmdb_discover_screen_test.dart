import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/screens/metadata_explore_page.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/screens/see_all/trakt_see_all_screen.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    StremioService.instance.invalidateCache();
  });

  tearDown(() {
    StremioService.instance.invalidateCache();
    ProfileRuntime.debugReset();
  });

  Future<void> drive(
    WidgetTester tester,
    Future<void> Function() action,
  ) async {
    final client = MockClient((_) async => http.Response('{}', 404));
    await tester.runAsync(
      () => http.runWithClient(() async {
        await action();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }, () => client),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> mount(
    WidgetTester tester,
    GlobalKey<NavigatorState> navigator,
  ) => drive(
    tester,
    () => tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const SearchScreen(discoverMode: true),
      ),
    ),
  );

  StremioDropdown<String> source(WidgetTester tester) =>
      tester.widget<StremioDropdown<String>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is StremioDropdown<String> && widget.label == 'Source',
        ),
      );

  testWidgets(
    'TMDB selection stays in Discover, has no floating button and reopens',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await mount(tester, navigator);
      expect(
        source(tester).options.map((o) => o.value),
        containsAll(['trakt', 'simkl', 'tmdb']),
      );
      expect(find.byType(FloatingActionButton), findsNothing);

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is StremioDropdown<String> && w.label == 'Source',
        ),
      );
      await tester.pumpAndSettle();
      await drive(tester, () => tester.tap(find.text('TMDB').last));
      expect(source(tester).value, 'tmdb');
      expect(
        tester
            .widget<MetadataBrowsePage>(find.byType(MetadataBrowsePage))
            .embedded,
        isTrue,
      );
      expect(navigator.currentState!.canPop(), isFalse);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(await StorageService.getDiscoverLastSource(), 'tmdb');

      await drive(tester, () async => source(tester).onSelected('trakt'));
      expect(find.byType(TraktSeeAllScreen), findsOneWidget);
      expect(find.byType(MetadataBrowsePage), findsNothing);
      await drive(tester, () async => source(tester).onSelected('tmdb'));
      await tester.pumpWidget(const SizedBox());
      await mount(tester, navigator);
      expect(source(tester).value, 'tmdb');
      expect(find.byType(MetadataBrowsePage), findsOneWidget);
      expect(navigator.currentState!.canPop(), isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TMDB default is respected and disabling it leaves a usable source',
    (tester) async {
      await StorageService.setDiscoverDefaultSource('tmdb');
      await StorageService.setDiscoverLastSource('trakt');
      final navigator = GlobalKey<NavigatorState>();
      await mount(tester, navigator);
      expect(source(tester).value, 'tmdb');
      await drive(
        tester,
        () =>
            MetadataPreferencesService.save(MetadataPreferences(features: {})),
      );
      expect(source(tester).value, 'cw');
      expect(
        source(tester).options.map((o) => o.value),
        isNot(contains('tmdb')),
      );
      expect(find.byType(MetadataBrowsePage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await mount(tester, navigator);
      expect(source(tester).value, 'cw');
      expect(find.byType(MetadataBrowsePage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );
}

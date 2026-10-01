import 'package:debrify/features/search/application/search_providers.dart';
import 'package:debrify/models/source_appearance.dart';
import 'dart:async';
import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/features/home/data/home_catalog_preferences_repository.dart';
import 'package:debrify/features/home/data/home_collections_repository.dart';
import 'package:debrify/models/home_preferences.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;

HomeCatalogPreferencesRepository preferences(
  Future<Set<String>> Function() disabled,
) => HomeCatalogPreferencesRepository(
  readDisabled: disabled,
  readExtras: () async => [],
  readRowOrder: () async => [],
  readHeroSource: () async =>
      (mode: HomeHeroSourceMode.random, ids: <String>[]),
);

void main() {
  testWidgets(
    'superseded appearance await cannot restart the remaining Home refresh',
    (tester) async {
      final appearance = Completer<SourceAppearance>();
      var appearanceReads = 0;
      var catalogReads = 0;
      final home = HomeFixture(tester);
      await home.mount(
        wrap: (child) => ProviderScope(
          overrides: [
            keywordAppearanceReaderProvider.overrideWith(
              (ref, session) => () {
                appearanceReads++;
                return appearanceReads == 2
                    ? appearance.future
                    : Future.value((text: true, logos: true));
              },
            ),
            homeCatalogPreferencesRepositoryProvider.overrideWithValue(
              preferences(() async {
                catalogReads++;
                return {};
              }),
            ),
          ],
          child: child,
        ),
      );
      await home.drive(() => home.slow.complete(page('Slow')));
      await home.settle();
      final before = catalogReads;
      final requests = List.of(home.requests);
      await home.drive(MainPageBridge.notifyHomeSettingsChanged);
      expect(appearanceReads, 2);
      expect(catalogReads, before);
      await home.drive(MainPageBridge.notifyHomeSettingsChanged);
      await home.settle();
      expect(catalogReads, before + 1);
      await home.drive(() => appearance.complete((text: false, logos: false)));
      await home.settle();
      expect(catalogReads, before + 1);
      expect(home.requests, requests);
      expect(find.text('Fast 0'), findsWidgets);
      await home.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings refresh removes and restores a catalog; unchanged refresh does not fetch',
    (tester) async {
      Set<String> disabled = {};
      final home = HomeFixture(tester);
      await home.mount(
        wrap: (child) => ProviderScope(
          overrides: [
            homeCatalogPreferencesRepositoryProvider.overrideWithValue(
              preferences(() async => disabled),
            ),
          ],
          child: child,
        ),
      );
      await home.drive(() => home.slow.complete(page('Slow')));
      await home.settle();
      final before = List.of(home.requests);
      await home.drive(MainPageBridge.notifyHomeSettingsChanged);
      await home.settle();
      expect(home.requests, before);
      expect(find.text('Fast 0'), findsWidgets);
      disabled = {'paging:movie:fast'};
      await home.drive(MainPageBridge.notifyHomeSettingsChanged);
      await home.settle();
      expect(find.text('Fast 0'), findsNothing);
      disabled = {};
      await home.drive(MainPageBridge.notifyHomeSettingsChanged);
      await home.settle();
      expect(find.text('Fast 0'), findsWidgets);
      await home.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disposed settings refresh does not start collection reads after preferences finish',
    (tester) async {
      final pending = Completer<Set<String>>();
      var refresh = false;
      var reads = 0;
      final home = HomeFixture(tester);
      await home.mount(
        wrap: (child) => ProviderScope(
          overrides: [
            homeCatalogPreferencesRepositoryProvider.overrideWithValue(
              preferences(() => refresh ? pending.future : Future.value({})),
            ),
            homeCollectionsRepositoryProvider.overrideWithValue(
              HomeCollectionsRepository(
                read: () async {
                  reads++;
                  return [];
                },
                signature: (_) async => '',
                onReadFailure: () => fail('collections failed'),
              ),
            ),
          ],
          child: child,
        ),
      );
      await home.drive(() => home.slow.complete(page('Slow')));
      await home.settle();
      refresh = true;
      await home.drive(MainPageBridge.notifyHomeSettingsChanged);
      final before = reads;
      await home.dispose();
      await home.drive(() => pending.complete({'paging:movie:fast'}));
      expect(reads, before);
      expect(tester.takeException(), isNull);
    },
  );
}

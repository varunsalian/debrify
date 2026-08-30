import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDetail(
    WidgetTester tester, {
    required StremioMeta item,
    required VoidCallback onPlay,
    required VoidCallback onBrowse,
    Future<void> Function()? onBrowsePrimaryEpisodeSources,
    void Function(TraktItemMenuAction action)? onTraktAction,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppThemeScope(theme: AppThemes.legacy, child: child!),
        home: CatalogItemDetailScreen(
          item: item,
          isTelevision: true,
          onPlay: onPlay,
          onBrowse: onBrowse,
          onBrowsePrimaryEpisodeSources: onBrowsePrimaryEpisodeSources,
          traktMenuOptions: onTraktAction == null
              ? const []
              : const [
                  TraktMenuOption(
                    action: TraktItemMenuAction.searchPacks,
                    icon: Icons.inventory_2_rounded,
                    color: Colors.amber,
                    label: 'Search Season Packs',
                    caption: 'Packs',
                  ),
                ],
          onTraktAction: onTraktAction,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('legacy movie Play hold reuses its Sources callback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    var plays = 0;
    var sourceOpens = 0;

    await pumpDetail(
      tester,
      item: const StremioMeta(
        id: 'legacy-movie',
        type: 'movie',
        name: 'Legacy Movie',
      ),
      onPlay: () => plays++,
      onBrowse: () => sourceOpens++,
    );

    await tester.longPress(find.text('Play'));
    await tester.pump();

    expect(sourceOpens, 1);
    expect(plays, 0);
  });

  testWidgets('legacy series with packs off opens episode sources directly', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageService.setQuickPlayRules(
      QuickPlayRules.debrifyDefault(
        isMovie: false,
      ).copyWith(preferSeriesPacks: false),
      isMovie: false,
    );
    var plays = 0;
    var sourceOpens = 0;

    await pumpDetail(
      tester,
      item: const StremioMeta(
        id: 'legacy-series',
        type: 'series',
        name: 'Legacy Series',
      ),
      onPlay: () => plays++,
      onBrowse: () {},
      onBrowsePrimaryEpisodeSources: () async => sourceOpens++,
      onTraktAction: (_) {},
    );

    await tester.longPress(find.text('Play'));
    await tester.pumpAndSettle();

    expect(find.text('Choose sources'), findsNothing);
    expect(sourceOpens, 1);
    expect(plays, 0);
  });

  testWidgets('legacy series with packs on shows both source choices', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    var sourceOpens = 0;
    TraktItemMenuAction? action;

    await pumpDetail(
      tester,
      item: const StremioMeta(
        id: 'legacy-series-packs',
        type: 'series',
        name: 'Legacy Series Packs',
      ),
      onPlay: () {},
      onBrowse: () {},
      onBrowsePrimaryEpisodeSources: () async => sourceOpens++,
      onTraktAction: (value) => action = value,
    );

    await tester.longPress(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.text('Season pack sources'), findsOneWidget);
    expect(find.text('Episode sources'), findsOneWidget);

    await tester.tap(find.text('Season pack sources'));
    await tester.pumpAndSettle();
    expect(action, TraktItemMenuAction.searchPacks);
    expect(sourceOpens, 0);
  });
}

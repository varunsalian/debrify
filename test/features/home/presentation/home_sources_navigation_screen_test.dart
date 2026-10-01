import 'package:debrify/features/sources/application/sources_providers.dart';
import 'package:debrify/features/sources/data/service_source_search_repository.dart';
import 'package:debrify/features/sources/presentation/sources_screen.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../sources/source_cache_screen_test.dart' show ReadySettings;
import 'package:debrify/screens/search_screen/home_sources_entry.dart';

void main() {
  for (final mode in ['browse', 'play', 'bind', 'keyword']) {
    testWidgets('default $mode bridge builds the real Sources feature', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      late BuildContext origin;
      var searches = 0;
      var returns = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceSettingsRepositoryProvider.overrideWith(
              (ref, key) => ReadySettings(),
            ),
            sourceSearchRepositoryProvider.overrideWith(
              (ref, session) => ServiceSourceSearchRepository(
                owner: session.owner,
                searchOverride: (_) async {
                  searches++;
                  return {'torrents': []};
                },
              ),
            ),
          ],
          child: MaterialApp(
            builder: (_, child) =>
                AppThemeScope(theme: AppThemes.legacy, child: child!),
            home: Builder(
              builder: (context) {
                origin = context;
                return const Scaffold();
              },
            ),
          ),
        ),
      );
      final bridge = ProviderScope.containerOf(
        origin,
      ).read(homeSourcesNavigationProvider);
      const selection = AdvancedSearchSelection(
        imdbId: 'tt123',
        title: 'Fixture',
        isSeries: false,
      );
      const meta = PlaybackMeta.catalog(addonId: 'exact-origin');
      final browse = mode == 'browse' || mode == 'play';
      final action = browse
          ? bridge.browse(
              origin,
              selection: selection,
              buildMeta: () => meta,
              isTelevision: () => true,
              forcePlayOnTap: mode == 'play',
              isCurrent: () => true,
              onReturned: () async => returns++,
            )
          : bridge.bind(
              origin,
              selection: selection,
              buildMeta: () => meta,
              isTelevision: () => true,
              keywordSeed: mode == 'keyword' ? 'Fixture 2026' : null,
              isCurrent: () => true,
              onReturned: () async => returns++,
            );
      await tester.pumpAndSettle();
      final screen = tester.widget<SourcesScreen>(find.byType(SourcesScreen));
      expect(screen.selection, same(selection));
      expect(screen.meta, same(meta));
      expect(screen.isTelevision, true);
      expect(screen.bindMode, !browse);
      expect(screen.forcePlayOnTap, mode == 'play');
      expect(screen.keywordSeed, mode == 'keyword' ? 'Fixture 2026' : null);
      expect(
        find.byType(TvHeldKeyGuard),
        browse ? findsOneWidget : findsNothing,
      );
      expect(searches, 1);
      expect(returns, 0);
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await action;
      expect(returns, 1);
      expect(find.byType(SourcesScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

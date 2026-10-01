import 'dart:async';
import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/features/home/data/home_display_preferences_repository.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'data/home_display_preferences_repository_test.dart'
    show displayRepository;
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;
import 'package:debrify/models/home_preferences.dart';

void main() {
  testWidgets(
    'Home renders injected display settings and rejects late startup',
    (tester) async {
      final startup = Completer<bool>();
      var calls = 0;
      var enabled = true;
      final repo = HomeDisplayPreferencesRepository(
        readFocusDetails: () =>
            ++calls == 1 ? startup.future : Future.value(enabled),
        readAnimationsEnabled: () async => enabled,
        readAnimationStyle: () async => 'moonlit_ocean',
        readOrientation: () async => HomeCardOrientation.portrait,
        readHideTitles: () async => enabled,
        readHideAddonNames: () async => enabled,
        readHideCollectionNames: () async => enabled,
      );
      final home = HomeFixture(tester, style: 'spotlight');
      await home.mount(
        wrap: (child) => ProviderScope(
          overrides: [
            homeDisplayPreferencesRepositoryProvider.overrideWithValue(repo),
          ],
          child: child,
        ),
      );
      SpotlightBoard board() =>
          tester.widget<SpotlightBoard>(find.byType(SpotlightBoard));
      expect(board().showCardTitlesAndRatings, isTrue);
      expect(board().expandFocusedCard, isFalse);
      await home.drive(() {
        home.slow.complete(page('Slow'));
        MainPageBridge.notifyHomeSettingsChanged();
      });
      await home.settle();
      expect(board().showCardTitlesAndRatings, isFalse);
      expect(board().expandFocusedCard, isTrue);
      expect(board().animationsEnabled, isTrue);
      expect(board().animationStyle, 'moonlit_ocean');
      expect(
        board().sections.first.items.first.shape,
        SpotlightCardShape.poster,
      );
      await home.drive(() => startup.complete(false));
      await home.settle();
      expect(board().expandFocusedCard, isTrue);
      enabled = false;
      await home.drive(MainPageBridge.notifyHomeSettingsChanged);
      await home.settle();
      expect(board().showCardTitlesAndRatings, isTrue);
      expect(board().expandFocusedCard, isFalse);
      expect(board().animationsEnabled, isFalse);
      expect(calls, 3);
      await home.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cached return seeds portrait and hidden titles on its first frame',
    (tester) async {
      final initial = Completer<bool>();
      final returning = Completer<bool>();
      var reads = 0;
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final repo = displayRepository(
        focus: () => ++reads == 1 ? initial.future : returning.future,
      );
      final home = HomeFixture(tester, style: 'spotlight');
      await home.mount(
        wrap: (child) => ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, shown, _) => shown
              ? ProviderScope(
                  overrides: [
                    homeDisplayPreferencesRepositoryProvider.overrideWithValue(
                      repo,
                    ),
                  ],
                  child: child,
                )
              : const SizedBox(),
        ),
      );
      await home.drive(() {
        initial.complete(true);
        home.slow.complete(page('Slow'));
      });
      await home.settle();
      SpotlightBoard board() =>
          tester.widget<SpotlightBoard>(find.byType(SpotlightBoard));
      expect(
        board().sections.first.items.first.shape,
        SpotlightCardShape.poster,
      );
      expect(board().showCardTitlesAndRatings, isFalse);
      visible.value = false;
      await home.pump(Duration.zero);
      visible.value = true;
      await home.pump(Duration.zero);
      expect(
        board().sections.first.items.first.shape,
        SpotlightCardShape.poster,
      );
      expect(board().showCardTitlesAndRatings, isFalse);
      // These flags were never part of the legacy return snapshot.
      expect(board().expandFocusedCard, isFalse);
      expect(board().animationsEnabled, isFalse);
      await home.drive(() => returning.complete(true));
      await home.settle();
      expect(board().expandFocusedCard, isTrue);
      await home.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}

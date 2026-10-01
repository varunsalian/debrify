import 'dart:async';
import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/features/home/data/home_layout_preferences.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;

void main() {
  for (final television in [true, false]) {
    testWidgets(
      'Home uses injected cached layout and latest transition: TV=$television',
      (tester) async {
        final startup = Completer<String>();
        var reads = 0;
        final preferences = HomeLayoutPreferences(
          readCached: () => 'classic',
          readSaved: () =>
              ++reads == 1 ? startup.future : Future.value('spotlight'),
        );
        final home = HomeFixture(
          tester,
          style: 'spotlight',
          television: television,
        );
        home.slow.complete(page('Slow'));
        await home.mount(
          wrap: (child) => ProviderScope(
            overrides: [
              homeLayoutPreferencesProvider.overrideWithValue(preferences),
            ],
            child: child,
          ),
        );
        expect(find.byType(SpotlightBoard), findsNothing);
        await home.drive(() => MainPageBridge.tvHomeStyleChanged!());
        await home.settle();
        expect(find.byType(SpotlightBoard), findsOneWidget);
        await home.drive(() => startup.complete('classic'));
        await home.settle();
        expect(find.byType(SpotlightBoard), findsOneWidget);
        expect(reads, 2);
        await home.dispose();
      },
    );
  }
}

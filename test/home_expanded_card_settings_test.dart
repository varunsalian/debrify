import 'package:debrify/features/discover/application/discover_card_settings_dependencies.dart';
import 'package:debrify/ui/core/see_all_link.dart';
import 'package:debrify/widgets/see_all/discover_card_settings_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_progressive_pagination_test.dart' show HomeFixture, page;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Home expansion reads fresh injected flags without Discover refresh',
    (tester) async {
      var settings = (showTypeTags: true, showRatings: true, showTitles: true);
      final home = HomeFixture(tester, television: false);
      home.slow.complete(page('Slow'));
      await home.mount(
        wrap: (child) => ProviderScope(
          overrides: [
            discoverCardSettingsReaderProvider.overrideWith(
              (ref, session) =>
                  () => settings,
            ),
          ],
          child: child,
        ),
      );
      await home.settle();
      settings = (showTypeTags: false, showRatings: false, showTitles: false);
      await home.drive(() => tester.tap(find.byType(SeeAllLink).first));
      await home.settle();
      final scope = tester.widget<DiscoverCardSettingsScope>(
        find.byType(DiscoverCardSettingsScope),
      );
      expect(scope.showTypeTags, isFalse);
      expect(scope.showRatings, isFalse);
      expect(scope.showTitles, isFalse);
      await home.dispose();
    },
  );

  late String source;

  setUpAll(() {
    source = File('lib/screens/search_screen.dart').readAsStringSync();
  });

  test('every Home poster-browser route applies Discover card settings', () {
    final helperStart = source.indexOf(
      'Widget _withHomeExpandedCardSettings(Widget child)',
    );
    final catalogStart = source.indexOf(
      'void _openCatalogSeeAll(',
      helperStart,
    );
    expect(helperStart, isNonNegative);
    expect(catalogStart, isNonNegative);

    final helper = source.substring(helperStart, catalogStart);
    expect(helper, contains('_discoverCardSettingsController.readSnapshot('));
    expect(helper, contains('isCurrent: () => mounted'));
    expect(helper, contains('showTypeTags: settings.showTypeTags'));
    expect(helper, contains('showRatings: settings.showRatings'));
    expect(helper, contains('showTitles: settings.showTitles'));

    // Catalog rows, tracker-list rows, generic Continue Watching rows (also
    // used by Simkl/MDBList), Trakt Continue Watching, and collection folders
    // each push a different screen. All five builders must use the helper.
    final routeUses = RegExp(
      r'builder: \(_\) => _withHomeExpandedCardSettings\(',
    ).allMatches(source);
    expect(routeUses.length, 5);
  });
}

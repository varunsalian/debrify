import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(helper, contains('showTypeTags: DiscoverPrefs.showTypeTags'));
    expect(helper, contains('showRatings: DiscoverPrefs.showRatings'));
    expect(helper, contains('showTitles: DiscoverPrefs.showTitles'));

    // Catalog rows, tracker-list rows, generic Continue Watching rows (also
    // used by Simkl/MDBList), Trakt Continue Watching, and collection folders
    // each push a different screen. All five builders must use the helper.
    final routeUses = RegExp(
      r'builder: \(_\) => _withHomeExpandedCardSettings\(',
    ).allMatches(source);
    expect(routeUses.length, 5);
  });
}

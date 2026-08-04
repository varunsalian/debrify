import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/services/discover_prefs.dart';

/// Mirrors a panel's private sort enum: what matters is that the stored id is
/// the enum's [Enum.name], so a rename would be caught by these tests.
enum _FakeSort { natural, az, za }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DiscoverPrefs.debugReset();
  });

  test('a source with nothing stored keeps its default sort', () async {
    await DiscoverPrefs.warmUp();
    expect(DiscoverPrefs.sortFor(DiscoverPrefs.trakt), isNull);
    expect(
      DiscoverPrefs.enumSortFor(DiscoverPrefs.trakt, _FakeSort.values),
      isNull,
    );
  });

  test('a picked sort survives a restart', () async {
    await DiscoverPrefs.warmUp();
    await DiscoverPrefs.setEnumSort(DiscoverPrefs.trakt, _FakeSort.az);

    // Restart: fresh cache, same on-disk prefs.
    DiscoverPrefs.debugReset();
    await DiscoverPrefs.warmUp();

    expect(
      DiscoverPrefs.enumSortFor(DiscoverPrefs.trakt, _FakeSort.values),
      _FakeSort.az,
    );
  });

  test('sources remember their sorts independently', () async {
    await DiscoverPrefs.warmUp();
    await DiscoverPrefs.setEnumSort(DiscoverPrefs.cw, _FakeSort.za);
    await DiscoverPrefs.setSort(DiscoverPrefs.catalog, 'imdbDesc');

    DiscoverPrefs.debugReset();
    await DiscoverPrefs.warmUp();

    expect(
      DiscoverPrefs.enumSortFor(DiscoverPrefs.cw, _FakeSort.values),
      _FakeSort.za,
    );
    expect(DiscoverPrefs.sortFor(DiscoverPrefs.catalog), 'imdbDesc');
    expect(DiscoverPrefs.sortFor(DiscoverPrefs.simkl), isNull);
  });

  test('the newest pick wins', () async {
    await DiscoverPrefs.warmUp();
    await DiscoverPrefs.setEnumSort(DiscoverPrefs.simkl, _FakeSort.az);
    await DiscoverPrefs.setEnumSort(DiscoverPrefs.simkl, _FakeSort.natural);

    DiscoverPrefs.debugReset();
    await DiscoverPrefs.warmUp();

    expect(
      DiscoverPrefs.enumSortFor(DiscoverPrefs.simkl, _FakeSort.values),
      _FakeSort.natural,
    );
  });

  test('a stored id that is no longer an option falls back to the default',
      () async {
    SharedPreferences.setMockInitialValues({
      'discover_sort_mdblist': 'sortThatShipped_thenVanished',
    });
    await DiscoverPrefs.warmUp();

    expect(
      DiscoverPrefs.enumSortFor(DiscoverPrefs.mdblist, _FakeSort.values),
      isNull,
    );
  });

  test('a pick is readable immediately, before the disk write lands', () async {
    await DiscoverPrefs.warmUp();
    final write = DiscoverPrefs.setEnumSort(DiscoverPrefs.cw, _FakeSort.az);
    expect(
      DiscoverPrefs.enumSortFor(DiscoverPrefs.cw, _FakeSort.values),
      _FakeSort.az,
    );
    await write;
  });
}

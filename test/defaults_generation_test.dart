import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('defaults generation (update-aware flagship look)', () {
    test('a pre-Spotlight install adopts the full bundle once', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.migrateDefaultsGeneration();
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getString('app_theme'), 'spotlight');
      // The controller's write-through mirror — without it, details render
      // Signal and the Looks picker reports Custom.
      expect(prefs.getString('detail_theme'), 'spotlight');
      expect(prefs.getString('detail_page_style'), 'showcase');
      expect(prefs.getString('tv_home_style'), 'spotlight');
      expect(prefs.getString('tv_sidebar_style'), 'pill');
      expect(prefs.getString('desktop_sidebar_style'), 'pill');
      expect(prefs.getInt('defaults_generation'), 2);

      // The getters resolve the migrated values (they validate the sets).
      expect(await StorageService.getAppTheme(), 'spotlight');
      expect(await StorageService.getTvHomeStyle(), 'spotlight');
      expect(await StorageService.getTvSidebarStyle(), 'pill');
      expect(await StorageService.getDesktopSidebarStyle(), 'pill');
    });

    test('explicit choices survive; only unwritten prefs adopt', () async {
      SharedPreferences.setMockInitialValues({
        'app_theme': 'signal',
        'tv_sidebar_style': 'ghost',
      });
      await StorageService.migrateDefaultsGeneration();
      final prefs = await SharedPreferences.getInstance();

      // The user's picks are untouched...
      expect(prefs.getString('app_theme'), 'signal');
      expect(prefs.getString('tv_sidebar_style'), 'ghost');
      // ...while the never-written prefs adopt.
      expect(prefs.getString('tv_home_style'), 'spotlight');
      expect(prefs.getString('desktop_sidebar_style'), 'pill');
      expect(prefs.getInt('defaults_generation'), 2);
    });

    test('an already-migrated install is a strict no-op', () async {
      SharedPreferences.setMockInitialValues({'defaults_generation': 2});
      await StorageService.migrateDefaultsGeneration();
      final prefs = await SharedPreferences.getInstance();

      // Nothing written: the user cleared/never-set these AFTER migration,
      // and re-running must not re-impose the bundle.
      expect(prefs.getString('app_theme'), isNull);
      expect(prefs.getString('tv_sidebar_style'), isNull);
      expect(prefs.getBool('home_hero_trailer_enabled'), isNull);
      expect(prefs.getInt('defaults_generation'), 2);
    });

    test('generation 2 turns both ambient trailer surfaces on', () async {
      // A Spotlight-era install: already migrated once, and it never had an
      // opinion about trailers — whichever surface its form factor defaulted
      // off was simply never written.
      SharedPreferences.setMockInitialValues({'defaults_generation': 1});
      await StorageService.migrateDefaultsGeneration();
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getBool('home_hero_trailer_enabled'), isTrue);
      expect(prefs.getBool('detail_trailer_autoplay_enabled'), isTrue);
      expect(prefs.getInt('defaults_generation'), 2);
      // Generation 1's bundle is NOT replayed onto an install that already
      // passed it and has since changed its mind.
      expect(prefs.getString('app_theme'), isNull);

      expect(await StorageService.getHomeHeroTrailerEnabled(), isTrue);
      expect(await StorageService.getDetailTrailerAutoplayEnabled(), isTrue);
    });

    test('an explicit trailer OFF is never overridden', () async {
      SharedPreferences.setMockInitialValues({
        'defaults_generation': 1,
        'home_hero_trailer_enabled': false,
      });
      await StorageService.migrateDefaultsGeneration();
      final prefs = await SharedPreferences.getInstance();

      // Said no, stays no...
      expect(prefs.getBool('home_hero_trailer_enabled'), isFalse);
      expect(await StorageService.getHomeHeroTrailerEnabled(), isFalse);
      // ...while the surface they never ruled on adopts.
      expect(prefs.getBool('detail_trailer_autoplay_enabled'), isTrue);
    });

    test('a fresh install gets both trailer surfaces on', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await StorageService.getHomeHeroTrailerEnabled(), isTrue);
      expect(await StorageService.getDetailTrailerAutoplayEnabled(), isTrue);
    });

    test('an explicit Classic pick (post-pinning) is fully preserved',
        () async {
      // What applying the Classic Look stores as of the pinned bundle.
      SharedPreferences.setMockInitialValues({
        'app_theme': 'legacy',
        'detail_page_style': 'classic',
        'tv_home_style': 'canvas',
        'tv_sidebar_style': 'ghost',
        'desktop_sidebar_style': 'rail',
      });
      await StorageService.migrateDefaultsGeneration();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme'), 'legacy');
      expect(prefs.getString('tv_home_style'), 'canvas');
      expect(prefs.getString('tv_sidebar_style'), 'ghost');
      expect(prefs.getString('desktop_sidebar_style'), 'rail');
      // legacy has no mirror, and none was invented for it.
      expect(prefs.getString('detail_theme'), isNull);
    });

    test('running twice changes nothing after the first pass', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.migrateDefaultsGeneration();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_theme', 'noir'); // user changes their mind
      await StorageService.migrateDefaultsGeneration();
      expect(prefs.getString('app_theme'), 'noir');
    });
  });
}

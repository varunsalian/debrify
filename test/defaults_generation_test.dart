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
      // Gen 0 → 3 in one pass ends on spotlight: the gen-1 block wrote
      // `app_theme` FIRST, and the gen-3 block reads what it wrote. This is
      // the ordering the gen-3 block depends on.
      expect(prefs.getString('debrify_tv_style'), 'spotlight');
      expect(prefs.getInt('defaults_generation'), 3);

      // The getters resolve the migrated values (they validate the sets).
      expect(await StorageService.getAppTheme(), 'spotlight');
      expect(await StorageService.getTvHomeStyle(), 'spotlight');
      expect(await StorageService.getTvSidebarStyle(), 'pill');
      expect(await StorageService.getDesktopSidebarStyle(), 'pill');
      expect(await StorageService.getDebrifyTvStyle(), 'spotlight');
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
      // Gen 3's proxy is the theme: signal is not spotlight, so Debrify TV
      // keeps the grid rather than restyling a non-flagship install.
      expect(prefs.getString('debrify_tv_style'), 'grid');
      expect(prefs.getInt('defaults_generation'), 3);
    });

    test('an already-migrated install is a strict no-op', () async {
      SharedPreferences.setMockInitialValues({'defaults_generation': 3});
      await StorageService.migrateDefaultsGeneration();
      final prefs = await SharedPreferences.getInstance();

      // Nothing written: the user cleared/never-set these AFTER migration,
      // and re-running must not re-impose the bundle.
      expect(prefs.getString('app_theme'), isNull);
      expect(prefs.getString('tv_sidebar_style'), isNull);
      expect(prefs.getBool('home_hero_trailer_enabled'), isNull);
      expect(prefs.getString('debrify_tv_style'), isNull);
      expect(prefs.getInt('defaults_generation'), 3);
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
      expect(prefs.getInt('defaults_generation'), 3);
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
      // Gen 3 does NOT restyle a Classic install — and because the stored
      // value equals the pin the Classic bundle now carries, the Presets
      // picker keeps reporting Classic rather than flipping to Custom.
      expect(prefs.getString('debrify_tv_style'), 'grid');
    });

    test('generation 3: an install on the Spotlight Look adopts spotlight',
        () async {
      // A Spotlight-era install that already passed generations 1 and 2.
      // Without the gen-3 write, adding `debrify_tv_style` to the Spotlight
      // bundle would flip these users to "Custom" in the Presets picker —
      // isActive compares every key a bundle names against stored prefs.
      SharedPreferences.setMockInitialValues({
        'defaults_generation': 2,
        'app_theme': 'spotlight',
        'detail_theme': 'spotlight',
        'tv_home_style': 'spotlight',
      });
      await StorageService.migrateDefaultsGeneration();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('debrify_tv_style'), 'spotlight');
      expect(prefs.getInt('defaults_generation'), 3);
    });

    test('generation 3: a Custom mix that kept the Spotlight theme adopts it',
        () async {
      // The proxy is the THEME, not Look activity: this install reports
      // Custom (hand-picked TV home), but its theme is Spotlight, so the
      // layout follows the theme. Their picker already says Custom — nothing
      // flips.
      SharedPreferences.setMockInitialValues({
        'defaults_generation': 2,
        'app_theme': 'spotlight',
        'detail_theme': 'spotlight',
        'tv_home_style': 'canvas',
      });
      await StorageService.migrateDefaultsGeneration();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('debrify_tv_style'), 'spotlight');
    });

    test('generation 3: an explicitly written value survives untouched',
        () async {
      // Written by a newer build, or by the picker before this migration ran
      // on another device's backup: stored means chosen, and chosen wins.
      SharedPreferences.setMockInitialValues({
        'defaults_generation': 2,
        'app_theme': 'spotlight',
        'debrify_tv_style': 'grid',
      });
      await StorageService.migrateDefaultsGeneration();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('debrify_tv_style'), 'grid');
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

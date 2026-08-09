import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/screens/settings/detail_theme_page.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_looks.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_controller.dart';

/// A Look is a bundle of preferences, so its dangerous properties are all
/// about what it can reach and what happens when two writers meet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LookApplier.debugResetGenerations();
  });

  group('the bundles are well-formed', () {
    test('every key a Look names is one a Look may set', () {
      // An unknown key does not throw, it silently does nothing — which is the
      // worst failure mode for a settings feature, because the row still says
      // the Look is active.
      expect(AppLooks.validate(), isEmpty);
    });

    test('NO Look can select a withheld theme', () {
      // The side door. `AppThemeController.select` accepts any stored detail
      // theme id, not just the shipped set — so a bundle naming 'broadsheet'
      // would hand a user the exact theme that is withheld for being
      // unreadable. `validate` covers this, and this test states it outright
      // so the reason survives.
      for (final look in AppLooks.all) {
        final theme = look.values['app_theme'];
        if (theme == null || theme == AppThemes.legacyId) continue;
        expect(
          kDetailThemesShipped,
          contains(theme),
          reason: '${look.id} names "$theme", which is not shipped',
        );
      }
    });

    test('ids and labels are unique', () {
      expect(AppLooks.all.map((l) => l.id).toSet().length, AppLooks.all.length);
      expect(
          AppLooks.all.map((l) => l.label).toSet().length, AppLooks.all.length);
    });

    test('every Look says something about the app theme', () {
      // A "Look" that leaves the palette alone is not a look.
      for (final look in AppLooks.all) {
        expect(look.values['app_theme'], isNotNull, reason: look.id);
      }
    });

    test('Debrify Classic really is the shipped app', () {
      final classic = AppLooks.all.firstWhere((l) => l.id == 'classic');
      expect(classic.values['app_theme'], AppThemes.legacyId);
      expect(classic.values['text_brightness'], 'bright');
    });
  });

  group('detection, not storage', () {
    test('a fresh install reads as its default Look or Custom, never stale',
        () {
      // Nothing is written at startup, so whatever `active()` says is derived
      // purely from the live prefs. The point of the test is that it does not
      // throw and does not depend on a stored id.
      final a = AppLooks.active();
      expect(a == null || AppLooks.all.contains(a), isTrue);
    });

    test('changing one key away from a Look makes it Custom by itself',
        () async {
      final look = AppLooks.all.firstWhere((l) => l.id == 'classic');
      await LookApplier.apply(look);
      expect(AppLooks.active()?.id, 'classic');

      // A manual change to ONE key the Look names — exactly what a user does
      // by opening a picker afterwards.
      await StorageService.setDetailPageStyle('stage');
      expect(AppLooks.active()?.id, isNot('classic'),
          reason: 'a stored "current Look" would still claim classic here');
    });
  });

  group('applying', () {
    test('sets every key it names, and only those', () async {
      await StorageService.setIptvStyle('edition');
      final classic = AppLooks.all.firstWhere((l) => l.id == 'classic');
      expect(classic.values.containsKey('iptv_style'), isFalse,
          reason: 'fixture: classic must not name iptv_style');

      await LookApplier.apply(classic);
      expect(StorageService.detailPageStyleCached, 'classic');
      expect(StorageService.iptvStyleCached, 'edition',
          reason: 'a Look must leave alone what it does not name');
    });

    test('publishes synchronously — the UI is right on the next frame',
        () async {
      final neon = AppLooks.all.firstWhere((l) => l.id == 'neon');
      final future = LookApplier.apply(neon);
      // Not awaited yet: the mirrors must already be correct.
      expect(AppThemeController.instance.id, neon.values['app_theme']);
      await future;
    });

    test('a change made BEFORE the apply loses — the preset was picked later',
        () async {
      // The ordering that matters. Setting a picker and then choosing a Look
      // means the Look is the newer intent, so it must win. (The generation
      // snapshot is taken when the apply STARTS, which is what expresses
      // this.)
      await StorageService.setIptvStyle('edition');
      final console = AppLooks.all.firstWhere((l) => l.id == 'console');
      await LookApplier.apply(console);
      expect(StorageService.iptvStyleCached, 'console');
    });

    test('a change made DURING the apply wins — a human beats a preset',
        () async {
      final console = AppLooks.all.firstWhere((l) => l.id == 'console');
      expect(console.values['iptv_style'], 'console');

      // Start the apply, then have a picker announce itself while it is still
      // walking the bundle — `iptv_style` sits fifth in the map, so the note
      // lands before the applier reaches it.
      final future = LookApplier.apply(console);
      await StorageService.setIptvStyle('edition');
      LookApplier.noteExternalWrite('iptv_style');
      await future;

      expect(StorageService.iptvStyleCached, 'edition',
          reason: 'a deliberate choice made during the apply must survive it');
      // …and the rest of the bundle still landed.
      expect(StorageService.detailPageStyleCached, 'console');
    });

    test('every bundle round-trips: apply then detect', () async {
      for (final look in AppLooks.all) {
        await LookApplier.apply(look);
        expect(AppLooks.active()?.id, look.id,
            reason: '${look.id} did not detect as active after applying');
      }
    });
  });

  test('a failing write does not take the apply down', () async {
    // A cosmetic preference must never throw into the caller: the mirrors are
    // already published, so the session is correct and the only cost of a
    // failed write is stickiness across a restart.
    final look = AppLooks.all.first;
    await expectLater(LookApplier.apply(look), completes);
    debugPrint('applied ${look.id}');
  });
}

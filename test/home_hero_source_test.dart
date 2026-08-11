import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageService home hero source', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to auto with no ids', () async {
      final source = await StorageService.getHomeHeroSource();
      expect(source.mode, HomeHeroSourceMode.auto);
      expect(source.ids, isEmpty);
    });

    test('round-trips a custom pick and clears the key on the default',
        () async {
      await StorageService.setHomeHeroSource((
        mode: HomeHeroSourceMode.custom,
        ids: ['cinemeta:movie:top', 'cinemeta:series:top'],
      ));
      var source = await StorageService.getHomeHeroSource();
      expect(source.mode, HomeHeroSourceMode.custom);
      expect(source.ids, ['cinemeta:movie:top', 'cinemeta:series:top']);

      // Ids survive a mode flip so a curated selection isn't lost by trying
      // "Surprise me".
      await StorageService.setHomeHeroSource((
        mode: HomeHeroSourceMode.random,
        ids: ['cinemeta:movie:top'],
      ));
      source = await StorageService.getHomeHeroSource();
      expect(source.mode, HomeHeroSourceMode.random);
      expect(source.ids, ['cinemeta:movie:top']);

      await StorageService.setHomeHeroSource((
        mode: HomeHeroSourceMode.auto,
        ids: [],
      ));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('home_hero_source_v1'), isNull);
    });

    test('degrades custom with no ids to auto on read', () async {
      SharedPreferences.setMockInitialValues({
        'home_hero_source_v1': jsonEncode({'mode': 'custom', 'ids': []}),
      });
      final source = await StorageService.getHomeHeroSource();
      expect(source.mode, HomeHeroSourceMode.auto);
    });

    test('tolerates corrupt json, unknown modes and malformed ids', () async {
      SharedPreferences.setMockInitialValues({
        'home_hero_source_v1': 'not-json{',
      });
      var source = await StorageService.getHomeHeroSource();
      expect(source.mode, HomeHeroSourceMode.auto);
      expect(source.ids, isEmpty);

      SharedPreferences.setMockInitialValues({
        'home_hero_source_v1': jsonEncode({
          'mode': 'nonsense',
          'ids': [
            'cinemeta:movie:top',
            42,
            '',
            'cinemeta:movie:top', // duplicate
            'other:series:x',
          ],
        }),
      });
      source = await StorageService.getHomeHeroSource();
      expect(source.mode, HomeHeroSourceMode.auto);
      expect(source.ids, ['cinemeta:movie:top', 'other:series:x']);
    });
  });
}

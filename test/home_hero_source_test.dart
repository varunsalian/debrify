import 'dart:convert';

import 'package:debrify/models/home_preferences.dart';
import 'package:debrify/services/storage/home_hero_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageService home hero source', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to random ("Surprise me") with no ids', () async {
      final source = await HomeHeroStorage.getHomeHeroSource();
      expect(source.mode, HomeHeroSourceMode.random);
      expect(source.ids, isEmpty);
    });

    test('round-trips a custom pick and clears the key on the default',
        () async {
      await HomeHeroStorage.setHomeHeroSource((
        mode: HomeHeroSourceMode.custom,
        ids: ['cinemeta:movie:top', 'cinemeta:series:top'],
      ));
      var source = await HomeHeroStorage.getHomeHeroSource();
      expect(source.mode, HomeHeroSourceMode.custom);
      expect(source.ids, ['cinemeta:movie:top', 'cinemeta:series:top']);

      // Ids survive a mode flip so a curated selection isn't lost by trying
      // "Surprise me" — and random WITH ids must keep the key for exactly
      // that reason.
      await HomeHeroStorage.setHomeHeroSource((
        mode: HomeHeroSourceMode.random,
        ids: ['cinemeta:movie:top'],
      ));
      source = await HomeHeroStorage.getHomeHeroSource();
      expect(source.mode, HomeHeroSourceMode.random);
      expect(source.ids, ['cinemeta:movie:top']);

      await HomeHeroStorage.setHomeHeroSource((
        mode: HomeHeroSourceMode.random,
        ids: [],
      ));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('home_hero_source_v1'), isNull,
          reason: 'the default (random, no ids) removes the key');
    });

    test('auto is an explicit choice: stored, and read back as auto',
        () async {
      await HomeHeroStorage.setHomeHeroSource((
        mode: HomeHeroSourceMode.auto,
        ids: [],
      ));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('home_hero_source_v1'), isNotNull,
          reason: 'removing the key would read back as the random default');
      final source = await HomeHeroStorage.getHomeHeroSource();
      expect(source.mode, HomeHeroSourceMode.auto);
    });

    test('degrades custom with no ids to the random default on read',
        () async {
      SharedPreferences.setMockInitialValues({
        'home_hero_source_v1': jsonEncode({'mode': 'custom', 'ids': []}),
      });
      final source = await HomeHeroStorage.getHomeHeroSource();
      expect(source.mode, HomeHeroSourceMode.random);
    });

    test('tolerates corrupt json, unknown modes and malformed ids', () async {
      SharedPreferences.setMockInitialValues({
        'home_hero_source_v1': 'not-json{',
      });
      var source = await HomeHeroStorage.getHomeHeroSource();
      expect(source.mode, HomeHeroSourceMode.random);
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
      source = await HomeHeroStorage.getHomeHeroSource();
      expect(source.mode, HomeHeroSourceMode.random);
      expect(source.ids, ['cinemeta:movie:top', 'other:series:x']);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/play_loader_art.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/play_loader_style.dart';
import 'package:debrify/services/profiles/profile_creation_service.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:debrify/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlayLoaderStyleController.cached = PlayLoaderStyleController.defaultStyle;
  });

  group('play_loader_style preference', () {
    test('unset reads as Marquee — the shipped default', () async {
      expect(await StorageService.getPlayLoaderStyle(), 'marquee');
      expect(PlayLoaderStyleController.defaultStyle, 'marquee');
    });

    test('an unknown stored value coerces to Marquee on read', () async {
      SharedPreferences.setMockInitialValues({
        'play_loader_style': 'some-future-look',
      });
      expect(await StorageService.getPlayLoaderStyle(), 'marquee');
    });

    test('an unknown value coerces on write too', () async {
      await StorageService.setPlayLoaderStyle('nonsense');
      expect(await StorageService.getPlayLoaderStyle(), 'marquee');
    });

    test('select publishes to the synchronous mirror before persisting',
        () async {
      final future = PlayLoaderStyleController.select('classic');
      // The play path reads [cached] synchronously — it must already be right.
      expect(PlayLoaderStyleController.cached, 'classic');
      await future;
      expect(await StorageService.getPlayLoaderStyle(), 'classic');
    });

    test('warm restores an explicit Classic choice', () async {
      SharedPreferences.setMockInitialValues({
        'play_loader_style': 'classic',
      });
      await PlayLoaderStyleController.warm();
      expect(PlayLoaderStyleController.cached, 'classic');
    });
  });

  group('profile plumbing', () {
    test('the pref is copyable to a new profile', () {
      expect(
        ProfileCreationService.copyablePreferenceKeys,
        contains('play_loader_style'),
      );
    });

    test('the sanitizer accepts both looks and nothing else', () {
      bool accepts(Object? v) =>
          SanitizedProfilePreferences.allowsEntry('play_loader_style', v);
      expect(accepts('marquee'), isTrue);
      expect(accepts('classic'), isTrue);
      expect(accepts('ott'), isFalse);
      expect(accepts(''), isFalse);
      expect(accepts(1), isFalse);
    });
  });

  group('PlayLoaderArt.fromMeta', () {
    StremioMeta meta({
      String? background,
      String? logo,
      String? year,
      double? rating,
      List<String>? genres,
      String? runtime,
    }) => StremioMeta(
      id: 'tt15239678',
      type: 'movie',
      name: 'Dune: Part Two',
      background: background,
      logo: logo,
      year: year,
      imdbRating: rating,
      genres: genres,
      runtime: runtime,
    );

    test('formats every bit the loader paints', () {
      final art = PlayLoaderArt.fromMeta(
        meta(
          background: 'https://art/bg.jpg',
          logo: 'https://art/logo.png',
          year: '2024',
          rating: 8.5,
          genres: const ['Sci-Fi', 'Adventure', 'Drama'],
          runtime: '166 min',
        ),
        certificate: 'PG-13',
      );
      expect(art.backdropUrl, 'https://art/bg.jpg');
      expect(art.logoUrl, 'https://art/logo.png');
      expect(art.yearLabel, '2024');
      expect(art.ratingLabel, '8.5');
      expect(art.certificate, 'PG-13');
      expect(art.runtimeLabel, '2h 46m');
      // Two genres is all the meta line has room for on a phone.
      expect(art.genreLabel, 'Sci-Fi · Adventure');
      expect(art.isEmpty, isFalse);
    });

    test('a bare catalog row yields empty art, so the loader stays as it was',
        () {
      expect(PlayLoaderArt.fromMeta(meta()).isEmpty, isTrue);
      // Blank strings are not artwork.
      expect(PlayLoaderArt.fromMeta(meta(background: '   ')).isEmpty, isTrue);
    });
  });
}

import 'dart:convert';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:debrify/services/profiles/profile_preference_portability.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unspecified cast follows build availability; other categories retain current sources', () {
    for (final prefs in [
      MetadataPreferences(),
      MetadataPreferences.fromJson({}),
    ]) {
      expect(prefs.isCurrent, MetadataPreferences.defaultCreditsProvider == MetadataPreferences.current);
      expect(prefs.features, isEmpty);
      expect(prefs.fallback, isFalse);
      for (final c in MetadataCategory.values) {
        expect(prefs.provider(c), c == MetadataCategory.credits
            ? MetadataPreferences.defaultCreditsProvider : MetadataPreferences.current);
      }
    }
  });

  test('explicit cast choices survive the new default and round trip', () {
    for (final choice in ['current', 'imdb', 'tmdb']) {
      final prefs = MetadataPreferences.fromJson({'providers': {'credits': choice}});
      expect(prefs.provider(MetadataCategory.credits), choice);
      expect(MetadataPreferences.fromJson(prefs.toJson()).provider(MetadataCategory.credits), choice);
    }
  });

  test('independent selections survive round trip without changing others', () {
    final prefs = MetadataPreferences(
      providers: {
        MetadataCategory.posters: 'tmdb',
        MetadataCategory.information: 'addon:${'a' * 64}',
      },
      features: {MetadataFeature.people},
      language: 'hi-IN',
    );
    final decoded = MetadataPreferences.fromJson(prefs.toJson());
    expect(decoded.toJson(), prefs.toJson());
    expect(decoded.provider(MetadataCategory.trailers), 'current');
    expect(decoded.fallback, isFalse);
  });

  test('malformed imported settings use defaults', () {
    final prefs = MetadataPreferences.fromJson({
      'providers': {'posters': 42, 'information': 'unknown'},
      'features': 'people',
      'fallback': 'true',
      'language': '../../x',
      'region': 'not a region',
    });
    expect(prefs.isCurrent, MetadataPreferences.defaultCreditsProvider == MetadataPreferences.current);
    expect(prefs.fallback, isFalse);
    expect(prefs.language, 'en-US');
    expect(prefs.region, 'US');
  });

  test('caller mutation cannot change a captured preference snapshot', () {
    final providers = {MetadataCategory.posters: 'tmdb'};
    final features = {MetadataFeature.people};
    final prefs = MetadataPreferences(providers: providers, features: features);
    providers.clear();
    features.clear();
    expect(prefs.provider(MetadataCategory.posters), 'tmdb');
    expect(prefs.features, {MetadataFeature.people});
  });
  test(
    'provider settings cannot serialize addon URLs or unsupported capabilities',
    () {
      final prefs = MetadataPreferences(
        providers: {
          MetadataCategory.information:
              'addon:https://example.test/private-token/manifest.json',
          MetadataCategory.posters: 'imdb',
          MetadataCategory.credits: 'addon:${'a' * 64}',
          MetadataCategory.episodeArtwork: 'tvmaze',
        },
      );
      expect(prefs.provider(MetadataCategory.information), 'current');
      expect(prefs.provider(MetadataCategory.posters), 'current');
      expect(prefs.provider(MetadataCategory.credits), MetadataPreferences.defaultCreditsProvider);
      expect(prefs.provider(MetadataCategory.episodeArtwork), 'tvmaze');
      expect(prefs.toJson().toString(), isNot(contains('private-token')));
    },
  );
  test(
    'metadata policy survives safe exports while unknown payloads are rejected',
    () {
      final prefs = MetadataPreferences(
        providers: {MetadataCategory.posters: 'tmdb'},
        features: {MetadataFeature.franchises},
        language: 'hi-IN',
        region: 'IN',
      );
      const key = 'metadata_providers_v1';
      final value = jsonEncode(prefs.toJson());
      expect(ProfilePreferencePortability.allowsKey(key), isTrue);
      expect(SanitizedProfilePreferences.allowsEntry(key, value), isTrue);
      expect(
        SanitizedProfilePreferences.allowsEntry(
          key,
          jsonEncode({...prefs.toJson(), 'token': 'private-token'}),
        ),
        isFalse,
      );
      expect(SanitizedProfilePreferences.allowsEntry(key, '{invalid'), isFalse);
      expect(
        SanitizedProfilePreferences.allowsEntry(
          key,
          jsonEncode({
            ...prefs.toJson(),
            'providers': {
              'posters': 'addon:https://example.test/private-token',
            },
          }),
        ),
        isFalse,
      );
    },
  );
}

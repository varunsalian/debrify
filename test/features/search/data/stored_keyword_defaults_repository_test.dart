import 'dart:convert';

import 'package:debrify/features/search/data/stored_keyword_defaults_repository.dart';
import 'package:debrify/models/torrent_filter_state.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfileRuntime.debugReset);

  StoredKeywordDefaultsRepository repository() =>
      StoredKeywordDefaultsRepository(
        owner: ProfileSessionMemory.captureOwner(),
      );

  test(
    'reads all five original JSON preferences with exact enum matching',
    () async {
      SharedPreferences.setMockInitialValues({
        'default_filter_qualities_v1': jsonEncode([
          'hd',
          'fullHd',
          'hd',
          'FullHd',
          ' fullHd',
        ]),
        'default_filter_rip_sources_v1': jsonEncode(['web', 'invalid']),
        'default_filter_languages_v1': jsonEncode(['hindi', 'english']),
        'default_filter_sizes_v1': jsonEncode(['gb4to6']),
        'default_filter_dynamic_ranges_v1': jsonEncode(['hdr']),
      });
      final filters = await repository().load();
      expect(filters.qualities.toList(), [QualityTier.hd, QualityTier.fullHd]);
      expect(filters.ripSources, {RipSourceCategory.web});
      expect(filters.languages.toList(), [
        AudioLanguage.hindi,
        AudioLanguage.english,
      ]);
      expect(filters.sizes, {SizeBucket.gb4to6});
      expect(filters.dynamicRanges, {DynamicRange.hdr});
      expect(() => filters.qualities.clear(), throwsUnsupportedError);
    },
  );

  test('missing and unknown saved values leave filters off', () async {
    expect((await repository().load()).isEmpty, isTrue);
    SharedPreferences.setMockInitialValues({
      'default_filter_qualities_v1': '["unknown"]',
    });
    expect((await repository().load()).isEmpty, isTrue);
  });

  test(
    'malformed storage still fails the read for the controller to handle',
    () async {
      SharedPreferences.setMockInitialValues({
        'default_filter_qualities_v1': 'invalid json',
      });
      await expectLater(repository().load(), throwsFormatException);
    },
  );

  test('reads the captured profile preference namespace', () async {
    final scope = ProfileScope(
      profileId: 'origin',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    SharedPreferences.setMockInitialValues({
      'default_filter_qualities_v1': '["ultraHd"]',
      scope.preferenceKey('default_filter_qualities_v1'): '["hd"]',
    });
    expect((await repository().load()).qualities, {QualityTier.hd});
  });

  test(
    'handoff during sequential reads never consumes incoming malformed data',
    () async {
      final origin = ProfileScope(
        profileId: 'origin',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final incoming = ProfileScope(
        profileId: 'incoming',
        dataGeneration: 1,
        sessionEpoch: 2,
      );
      ProfileRuntime.initializeCommitted(origin);
      SharedPreferences.setMockInitialValues({
        origin.preferenceKey('default_filter_qualities_v1'): '["hd"]',
        for (final suffix in [
          'qualities',
          'rip_sources',
          'languages',
          'sizes',
          'dynamic_ranges',
        ])
          incoming.preferenceKey('default_filter_${suffix}_v1'):
              'malformed incoming JSON',
      });
      final repo = repository();
      final load = repo.load();
      ProfileRuntime.publish(incoming);
      expect((await load).isEmpty, isTrue);
      expect((await repo.load()).isEmpty, isTrue);
    },
  );
}

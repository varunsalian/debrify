import 'package:debrify/screens/video_player/utils/subtitle_audio_policy.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<String?> select(
    List<Map<String, String>> tracks, {
    String? language = 'en',
    bool Function()? current,
  }) => findForcedSubtitleId(
    preferredSubtitle: language,
    isCurrent: current ?? () => true,
    readProperty: (key) async {
      if (key == 'track-list/count') return '${tracks.length}';
      final parts = key.split('/');
      return tracks[int.parse(parts[1])][parts[2]] ?? '';
    },
  );
  Map<String, String> sub(
    String id,
    String language, {
    bool forced = false,
    bool external = false,
  }) => {
    'type': 'sub',
    'id': id,
    'lang': language,
    'forced': forced ? 'yes' : 'no',
    'external': external ? 'yes' : 'no',
  };

  test(
    'selects flagged preferred-language track over ordinary and other-language tracks',
    () async {
      expect(
        await select([
          sub('1', 'en'),
          sub('2', 'fr', forced: true),
          sub('3', 'eng', forced: true),
        ]),
        '3',
      );
    },
  );
  test(
    'does not use titles, unmarked tracks, addons or unknown languages as evidence',
    () async {
      expect(
        await select([
          {...sub('1', 'en'), 'title': 'English forced'},
          sub('2', 'en', forced: true, external: true),
          sub('3', 'und', forced: true),
        ]),
        isNull,
      );
    },
  );
  test(
    'off remains off and unset language consistently defaults to English',
    () async {
      final tracks = [
        sub('1', 'fr', forced: true),
        sub('2', 'en', forced: true),
      ];
      expect(await select(tracks, language: 'off'), isNull);
      expect(await select(tracks, language: null), '2');
      expect(await select([], language: null), isNull);
    },
  );
  test('does not commit selection after media generation changes', () async {
    var valid = true;
    expect(
      await findForcedSubtitleId(
        preferredSubtitle: 'en',
        isCurrent: () => valid,
        readProperty: (key) async {
          if (key == 'track-list/count') {
            valid = false;
            return '1';
          }
          return 'yes';
        },
      ),
      isNull,
    );
  });
  test('unavailable metadata safely leaves subtitles off', () async {
    expect(
      await findForcedSubtitleId(
        preferredSubtitle: 'en',
        isCurrent: () => true,
        readProperty: (_) async => throw StateError('unavailable'),
      ),
      isNull,
    );
  });
  test(
    'forced-only setting defaults off and round-trips as a profile boolean',
    () async {
      SharedPreferences.setMockInitialValues({});
      expect(await StorageService.getSubtitleForcedOnly(), isFalse);
      await StorageService.setSubtitleForcedOnly(true);
      expect(await StorageService.getSubtitleForcedOnly(), isTrue);
      expect(
        SanitizedProfilePreferences.allowsEntry('subtitle_forced_only', true),
        isTrue,
      );
      expect(
        SanitizedProfilePreferences.allowsEntry('subtitle_forced_only', 'true'),
        isFalse,
      );
    },
  );
}

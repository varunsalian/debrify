import 'dart:async';

import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/utils/subtitle_audio_policy.dart';
import 'package:debrify/screens/video_player/utils/subtitle_priority_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_preference_portability.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  bool allows(String? audio, {String? preferred = 'en', bool enabled = true}) =>
      allowsAutomaticSubtitles(
        onlyForeignAudio: enabled,
        preferredAudio: preferred,
        selectedAudio: audio,
      );

  test('opt-in defaults off and survives profile preference storage', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await StorageService.getSubtitleOnlyForeignAudio(), isFalse);
    await StorageService.setSubtitleOnlyForeignAudio(true);
    expect(await StorageService.getSubtitleOnlyForeignAudio(), isTrue);
    const key = 'subtitle_only_foreign_audio';
    expect(ProfilePreferencePortability.prepareValue(key, true), (
      include: true,
      value: true,
    ));
    expect(SanitizedProfilePreferences.allowsEntry(key, true), isTrue);
    expect(SanitizedProfilePreferences.allowsEntry(key, 'true'), isFalse);
    await StorageService.setSubtitleOnlyForeignAudio(false);
    expect(await StorageService.getSubtitleOnlyForeignAudio(), isFalse);
  });

  test('disabled option preserves existing automatic selection', () {
    expect(allows(null, preferred: null, enabled: false), isTrue);
    expect(allows('eng', enabled: false), isTrue);
  });

  test('same language stays off across names and regional ISO variants', () {
    for (final language in ['en', 'eng', 'English', 'EN_us', 'en-GB']) {
      expect(allows(language), isFalse, reason: language);
    }
    expect(allows('fra', preferred: 'fr'), isFalse);
    expect(allows('pt-BR', preferred: 'pt'), isFalse);
  });

  test('known foreign audio enables subtitles', () {
    for (final language in ['jpn', 'Japanese', 'ja-JP', 'hin', 'fra']) {
      expect(allows(language), isTrue, reason: language);
    }
  });

  test('unknown audio or unset preference does not imply a mismatch', () {
    for (final language in [
      null,
      '',
      'und',
      'mul',
      'zxx',
      'unknown',
      'Track 1',
    ]) {
      expect(allows(language), isFalse, reason: '$language');
    }
    expect(allows('ja', preferred: null), isFalse);
  });

  test(
    'audio switches invalidate a delayed addon; switching back can retry',
    () async {
      var audio = 'ja';
      var revision = 0;
      final download = Completer<void>();
      var applied = 0;
      final slots = [
        AddonSubtitleSlot(
          addonId: 'a',
          addonName: 'A',
          status: AddonSubtitleStatus.ok,
          subtitles: const [
            StremioSubtitle(
              id: 'en',
              url: 'https://example.test/en.srt',
              lang: 'en',
              source: 'a',
            ),
          ],
        ),
      ];
      Future<SubtitlePriorityResult?> select({bool wait = false}) {
        final startedRevision = revision;
        bool current() => revision == startedRevision && allows(audio);
        return selectSubtitleBySourcePriority(
          saved: ['addon:a', 'embedded'],
          language: 'en',
          slots: slots,
          discoveryReady: true,
          isCurrent: current,
          tryEmbedded: () async => false,
          tryAddon: (_) async {
            if (wait) await download.future;
            if (!current()) return false;
            applied++;
            return true;
          },
        );
      }

      final pending = select(wait: true);
      audio = 'en';
      revision++;
      download.complete();
      expect(await pending, isNull);
      expect(applied, 0);
      expect(await select(), isNull);
      audio = 'ja';
      revision++;
      expect((await select())?.addon?.id, 'en');
      expect(applied, 1);
    },
  );
}

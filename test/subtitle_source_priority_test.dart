import 'dart:convert';

import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/subtitle_source_priority.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_preference_portability.dart';
import 'package:debrify/services/profiles/profile_appearance_preferences.dart';
import 'package:debrify/services/profiles/legacy_backup_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

StremioSubtitle sub(String id, String lang) => StremioSubtitle(
  id: id,
  url: 'https://example.test/$id.srt',
  lang: lang,
  source: 'Same display name',
);

void main() {
  test(
    'configuration identity survives resource ID changes and distinguishes same-named addons',
    () {
      final first = StremioAddon.fromManifest({
        'id': 'provider',
        'name': 'Subtitles',
        'resources': ['subtitles'],
      }, 'https://example.test/config-a/manifest.json');
      final restored = first.copyWith(id: 'new-local-resource-id');
      final other = first.copyWith(
        manifestUrl: 'https://example.test/config-b/manifest.json',
      );
      expect(first.portableConfigurationKey, restored.portableConfigurationKey);
      expect(
        first.portableConfigurationKey,
        isNot(other.portableConfigurationKey),
      );
      expect(
        SubtitleSourcePriority.configurationId(first.manifestUrl),
        first.portableConfigurationKey,
      );
      final slot = AddonSubtitleSlot(
        addonId: restored.id,
        addonName: restored.name,
        configurationKey: restored.portableConfigurationKey,
        status: AddonSubtitleStatus.loading,
      );
      expect(
        slot.copyWith(status: AddonSubtitleStatus.ok).priorityId,
        first.portableConfigurationKey,
      );
    },
  );

  test('default order is embedded then addons in installation order', () {
    expect(SubtitleSourcePriority.effective([], ['b', 'a']), [
      'embedded',
      'addon:b',
      'addon:a',
    ]);
  });
  test(
    'custom order can put embedded last; missing sources are skipped and new ones appended',
    () {
      expect(
        SubtitleSourcePriority.effective(
          ['addon:b', 'addon:gone', 'addon:a', 'embedded'],
          ['a', 'b', 'new'],
        ),
        ['addon:b', 'addon:a', 'embedded', 'addon:new'],
      );
    },
  );
  test('invalid or duplicate saved values do not remove embedded fallback', () {
    expect(SubtitleSourcePriority.decode('garbage'), ['embedded']);
    expect(
      SubtitleSourcePriority.decode('["addon:a",null,"invalid","addon:a"]'),
      ['addon:a', 'embedded'],
    );
  });
  test(
    'language preference filters; no preference prefers English then any language; Off stays off',
    () {
      final subs = [
        sub('spanish', 'spa'),
        sub('english', 'eng'),
        sub('french', 'fre'),
      ];
      expect(SubtitleSourcePriority.matching(subs, 'fr').map((s) => s.id), [
        'french',
      ]);
      expect(SubtitleSourcePriority.matching(subs, null).map((s) => s.id), [
        'english',
        'spanish',
        'french',
      ]);
      expect(SubtitleSourcePriority.matching(subs, 'de'), isEmpty);
      expect(SubtitleSourcePriority.matching(subs, 'off'), isEmpty);
    },
  );
  test(
    'preference persists as portable native-projected profile data and is not excluded from sync',
    () async {
      SharedPreferences.setMockInitialValues({});
      expect(await StorageService.getSubtitleSourcePriority(), ['embedded']);
      await StorageService.setSubtitleSourcePriority([
        'addon:b',
        'embedded',
        'addon:a',
      ]);
      expect(await StorageService.getSubtitleSourcePriority(), [
        'addon:b',
        'embedded',
        'addon:a',
      ]);
      const key = SubtitleSourcePriority.preferenceKey;
      expect(ProfilePreferences.nativeProjectionKeys, contains(key));
      expect(ProfileAppearancePreferences.keys, isNot(contains(key)));
      expect(ProfilePreferencePortability.allowsKey(key), isTrue);
      final encoded = jsonEncode(
        await StorageService.getSubtitleSourcePriority(),
      );
      expect(ProfilePreferencePortability.prepareValue(key, encoded), (
        include: true,
        value: encoded,
      ));
    },
  );
  test(
    'legacy backups promote subtitle priority into portable preferences',
    () {
      final package = LegacyBackupAdapter.adapt({
        'version': 1,
        'subtitleSourcePriority': ['addon:b', 'embedded'],
      });
      final values =
          (package.sections['legacy-preferences'] as Map)['values'] as Map;
      expect(
        SubtitleSourcePriority.decode(
          values[SubtitleSourcePriority.preferenceKey] as String,
        ),
        ['addon:b', 'embedded'],
      );
    },
  );
}

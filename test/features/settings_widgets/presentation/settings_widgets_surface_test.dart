import 'package:flutter_test/flutter_test.dart';
import '../../../support/settings_widgets_source.dart';

const originalPublicNames = <String>{
  'kSettingsBg',
  'kSettingsAccent',
  'kSettingsAccent2',
  'kSettingsPanel',
  'kSettingsPanel2',
  'kSettingsGreen',
  'kSettingsRed',
  'kSettingsAmber',
  'kSettingsLine',
  'kSettingsDim',
  'kSettingsDim2',
  'kSettingsMaxWidth',
  'WebDavSyncPendingBadge',
  'settingsInitialsFor',
  'SettingsRowContent',
  'SettingsRows',
  'launchSettingsUrl',
  'settingsPageTheme',
  'pushSettingsPage',
  'showSettingsDialog',
  'SettingsPageScaffold',
  'SettingsPageHeader',
  'SettingsBannerTone',
  'SettingsInfoBanner',
  'SettingsBackground',
  'SettingsHeader',
  'SettingsSectionLabel',
  'ConnectionInfo',
  'settingsConnectionNeedsAttention',
  'settingsConnectionIsReady',
  'ConnectionsSummary',
  'ConnectionCard',
  'SettingsSection',
  'SettingsLookHero',
  'SettingsTile',
  'SettingsToggleTile',
  'TvUiScaleChoice',
  'kTvUiScaleChoices',
  'tvUiScaleLabel',
  'TvRenderQualityChoice',
  'kTvRenderQualityChoices',
  'tvRenderQualityLabel',
  'SettingsSelectOption',
  'SettingsSelectDropdown',
  'SettingsInfoTile',
  'SettingsSkeleton',
  'showLegacyModeInfoDialog',
};

void main() {
  test('facade namespace remains exactly the original 47 names', () {
    final files = settingsWidgetsPhysicalFiles();
    final facade = files[settingsWidgetsFacade]!;
    final names = settingsWidgetsSpans(
      facade,
    ).map((s) => s.name).where((n) => !n.startsWith('_')).toList();
    for (final directive in RegExp(
      r"export '[^']+'\s+show\s+([^;]+);",
      multiLine: true,
    ).allMatches(facade)) {
      names.addAll(directive[1]!.split(',').map((n) => n.trim()));
    }
    expect(names, hasLength(47));
    expect(names.toSet(), originalPublicNames);
    for (final name in originalPublicNames) {
      expect(() => settingsWidgetsDeclaration(name), returnsNormally);
    }
  });
}
